#!/usr/bin/env python3
"""Describe or explicitly execute isolated coding trials. Live calls are opt-in."""
from __future__ import annotations

import argparse
import contextlib
import difflib
import hashlib
import json
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CREDENTIALS = ('ANTHROPIC_API_KEY', 'CLAUDE_CODE_OAUTH_TOKEN', 'CODEX_API_KEY', 'OPENAI_API_KEY')
# Forwarded in Claude's own precedence order: an API key outranks the subscription token.
RUNTIME_CREDENTIALS = {'claude': ('ANTHROPIC_API_KEY', 'CLAUDE_CODE_OAUTH_TOKEN'), 'codex': ('CODEX_API_KEY',)}
REQUIRED = {
    'claude': ('--print', '--output-format', '--verbose', '--model', '--tools', '--allowedTools',
               '--permission-mode', '--setting-sources', '--settings', '--strict-mcp-config',
               '--mcp-config', '--no-session-persistence', '--max-budget-usd', '--debug-file'),
    'codex': ('--json', '--model', '--sandbox', '--ephemeral', '--config', '--strict-config'),
}
# Anything here in a dedicated CODEX_HOME would change the controlled trial configuration.
CODEX_HOME_RESERVED = ('AGENTS.md', 'AGENTS.override.md', 'config.toml', 'skills', 'rules', 'plugins', 'memories')
# Codex recreates its bundled skills and plugin caches on every run; staged config disables plugins.
CODEX_MANAGED = {'skills': {'.system'}, 'plugins': {'cache', '.remote-plugin-install-staging'}}


def redact(text: str) -> str:
    for name in CREDENTIALS:
        value = os.environ.get(name)
        if value:
            text = text.replace(value, '[REDACTED]').replace(json.dumps(value)[1:-1], '[REDACTED]')
    return re.sub(r'\bsk-(?:ant-)?[A-Za-z0-9_-]+', '[REDACTED]', text)


def local_path(root: Path, value: str) -> Path:
    if not isinstance(value, str) or not value or Path(value).is_absolute() or '..' in Path(value).parts:
        raise ValueError('Fixture paths must be relative without traversal.')
    path = (root / value).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError('Fixture path escapes its root.')
    return path


def load_tasks(manifest: Path, selected: str | None) -> list[dict]:
    document = json.loads(manifest.read_text())
    if not isinstance(document, dict) or not isinstance(document.get('tasks'), list) or not document['tasks']:
        raise ValueError('Manifest requires a nonempty tasks array.')
    tasks, seen = [], set()
    for task in document['tasks']:
        if (not isinstance(task, dict) or not isinstance(task.get('id'), str)
                or not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', task['id'])):
            raise ValueError('Invalid task ID.')
        if task['id'] in seen:
            raise ValueError('Duplicate task ID.')
        seen.add(task['id'])
        if not isinstance(task.get('prompt'), str) or not task['prompt'].strip():
            raise ValueError('Task requires a prompt.')
        snapshot = local_path(manifest.parent, task.get('snapshot'))
        if not snapshot.is_dir() or (snapshot / '.git').exists():
            raise ValueError('Snapshot must be a fixture directory without .git.')
        for path in snapshot.rglob('*'):
            if path.is_symlink():
                raise ValueError('Snapshot symlinks are not supported.')
        for field in ('timeout_seconds', 'verification_timeout_seconds'):
            value = task.get(field)
            if type(value) not in (int, float) or not math.isfinite(value) or value <= 0:
                raise ValueError(f'{field} must be positive and finite.')
        for field in ('verification', 'regression_verification'):
            command = task.get(field)
            if (not isinstance(command, list) or len(command) != 2 or command[0] != 'python3'
                    or not local_path(manifest.parent, command[1]).is_file()):
                raise ValueError('Verification must name python3 and a local check script.')
        for field in ('implementation_paths', 'protected_paths'):
            paths = task.get(field)
            if not isinstance(paths, list) or not paths:
                raise ValueError(f'{field} must be a nonempty path list.')
            for path in paths:
                if not local_path(snapshot, path).exists():
                    raise ValueError(f'{field} names a missing snapshot path.')
        if not local_path(manifest.parent, task.get('reference_patch')).is_file():
            raise ValueError('Reference patch is missing.')
        if type(task.get('manual_review')) is not bool or type(task.get('baseline_acceptance')) is not bool:
            raise ValueError('Task review and baseline status must be booleans.')
        tasks.append({**task, 'fixture_root': str(manifest.parent.resolve())})
    tasks = [task for task in tasks if selected is None or task['id'] == selected]
    if not tasks:
        raise ValueError('No matching coding task.')
    return tasks


def environment(home: Path, agent: str | None = None) -> dict[str, str]:
    env = {'PATH': os.environ.get('PATH', os.defpath), 'LANG': 'C.UTF-8', 'HOME': str(home),
           'CLAUDE_CONFIG_DIR': str(home / '.claude'), 'CODEX_HOME': str(home / '.codex'),
           'XDG_CONFIG_HOME': str(home / '.config'), 'XDG_CACHE_HOME': str(home / '.cache'),
           'XDG_DATA_HOME': str(home / '.local/share'), 'GIT_CONFIG_NOSYSTEM': '1',
           'GIT_CONFIG_GLOBAL': '/dev/null', 'PYTHONDONTWRITEBYTECODE': '1',
           'DISABLE_AUTOUPDATER': '1', 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': '1'}
    for name in RUNTIME_CREDENTIALS.get(agent, ()):
        if os.environ.get(name):
            env[name] = os.environ[name]
    return env


def stop(process: subprocess.Popen) -> tuple[str, str]:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        return process.communicate(timeout=1)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        return process.communicate()
    finally:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def invoke(argv: list[str], cwd: Path, env: dict, prompt: str, timeout: float) -> dict:
    started = time.monotonic()
    process = subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, encoding='utf-8', errors='replace', start_new_session=True)
    error = None
    try:
        stdout, stderr = process.communicate(prompt, timeout=timeout)
    except subprocess.TimeoutExpired:
        stdout, stderr = stop(process)
        error = 'Process timed out.'
    except BaseException:
        stop(process)
        raise
    finally:
        # End descendants even when their parent exits before them.
        if process.poll() is not None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    return {'stdout': redact(stdout), 'stderr': redact(stderr), 'returncode': process.returncode,
            'elapsed_seconds': time.monotonic() - started, 'error': error}


def files(root: Path) -> dict[str, bytes]:
    result = {}
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if '.git' in relative.parts or '__pycache__' in relative.parts:
            continue
        if path.is_symlink():
            result[str(relative)] = ('symlink: ' + os.readlink(path)).encode()
        elif path.is_file():
            result[str(relative)] = path.read_bytes()
    return result


def hashes(root: Path) -> dict[str, str]:
    return {name: hashlib.sha256(data).hexdigest() for name, data in files(root).items()}


def stage_trial(task: dict, trial_root: Path, agent: str, instruction_file: Path | None, skills_root: Path,
                codex_home: Path | None = None, gate: bool = False) -> Path:
    home, workspace = trial_root / 'home', trial_root / 'work'
    home.mkdir()
    shutil.copytree(Path(task['fixture_root']) / task['snapshot'], workspace)
    (workspace / '.tmp').mkdir()
    config = codex_home or home / ('.claude' if agent == 'claude' else '.codex')
    config.mkdir(exist_ok=bool(codex_home))
    skill_target = config / 'skills' if agent == 'claude' else home / '.agents/skills'
    shutil.copytree(skills_root, skill_target)
    if instruction_file:
        shutil.copyfile(instruction_file, config / ('CLAUDE.md' if agent == 'claude' else 'AGENTS.md'))
    if agent == 'claude':
        # The verify gate runs from a copy outside the workspace; its state stays in the trial home.
        hooks = {'disableAllHooks': True}
        if gate:
            script = trial_root / 'verify-gate.py'
            shutil.copyfile(ROOT / 'hooks/verify-gate.py', script)
            template = (ROOT / 'settings/claude/hooks.json').read_text()
            hooks = json.loads(template.replace('@VERIFY_GATE@', str(script)))
        (config / 'settings.json').write_text(json.dumps({**hooks,
            'permissions': {'blockReadsOutsideWorkingDirectories': True},
            'sandbox': {'enabled': True, 'failIfUnavailable': True, 'autoAllowBashIfSandboxed': True,
                        'allowUnsandboxedCommands': False}}))
    else:
        (config / 'config.toml').write_text('approval_policy = "never"\nsandbox_mode = "workspace-write"\n'
            '[features]\nplugins = false\nremote_plugin = false\napps = false\n'
            '[memories]\ngenerate_memories = false\nuse_memories = false\n'
            '[sandbox_workspace_write]\nnetwork_access = false\nexclude_tmpdir_env_var = true\nexclude_slash_tmp = true\n'
            '[shell_environment_policy]\ninherit = "none"\n'
            '[shell_environment_policy.set]\n'
            f'HOME = {json.dumps(str(home))}\nTMPDIR = {json.dumps(str(workspace / ".tmp"))}\n'
            f'PATH = {json.dumps(os.defpath)}\n')
    env = environment(home)
    for args in (['init', '-q'], ['add', '.'], ['-c', 'user.name=Coding Eval', '-c', 'user.email=eval@example.invalid',
                                            '-c', 'commit.gpgsign=false', 'commit', '-qm', 'Fixture baseline']):
        result = invoke(['git', *args], workspace, env, '', 10)
        if result['error'] or result['returncode']:
            raise ValueError('Could not initialize isolated fixture repository.')
    return workspace


@contextlib.contextmanager
def staged_codex_home(codex_home: Path | None):
    try:
        yield
    finally:
        if codex_home:
            for name in ('AGENTS.md', 'config.toml'):
                (codex_home / name).unlink(missing_ok=True)


def parse_runtime(agent: str, stdout: str) -> dict:
    events = [json.loads(line) for line in stdout.splitlines() if line.strip()]
    if not events or any(not isinstance(event, dict) for event in events):
        raise ValueError('Invalid JSONL runtime events.')
    if agent == 'claude':
        terminal = [e for e in events if e.get('type') == 'result']
        if len(terminal) != 1 or events[-1] != terminal[0]:
            raise ValueError('Missing terminal Claude result.')
        final = terminal[0]
        if final.get('is_error') is not False or final.get('subtype') != 'success' or final.get('permission_denials'):
            raise ValueError('Claude failed or denied a necessary tool.')
        calls, loaded = {}, []
        observed_tools = False
        for event in events:
            message = event.get('message', {})
            if not isinstance(message, dict):
                raise ValueError('Invalid Claude message.')
            blocks = message.get('content', [])
            if not isinstance(blocks, list):
                raise ValueError('Invalid Claude content.')
            for block in blocks:
                if not isinstance(block, dict):
                    continue
                if block.get('type') == 'tool_use' and block.get('name') == 'Skill':
                    if event.get('type') != 'assistant' or not isinstance(block.get('input'), dict):
                        raise ValueError('Invalid skill event role or arguments.')
                    skill = block['input'].get('skill')
                    identifier = block.get('id')
                    if not isinstance(skill, str) or not isinstance(identifier, str):
                        raise ValueError('Invalid skill call.')
                    calls[identifier] = skill
                if block.get('type') == 'tool_use':
                    observed_tools = True
                if block.get('type') == 'tool_result' and block.get('is_error') and 'bwrap: ' in str(block.get('content')):
                    raise ValueError('Claude sandbox could not start a command (bwrap).')
                if block.get('type') == 'tool_result' and block.get('tool_use_id') in calls:
                    if event.get('type') != 'user' or block.get('is_error'):
                        raise ValueError('Skill invocation failed or was spoofed.')
                    loaded.append(calls.pop(block['tool_use_id']))
        if calls:
            raise ValueError('Unconfirmed skill load.')
        model = next((e.get('model') for e in events if e.get('subtype') == 'init'), None)
        result = {'usage': final.get('usage'), 'cost_usd': final.get('total_cost_usd'),
                  'model': model, 'loaded_skills': loaded if observed_tools else None}
    else:
        terminal = [e for e in events if e.get('type') in ('turn.completed', 'turn.failed')]
        if len(terminal) != 1 or events[-1] != terminal[0] or terminal[0].get('type') != 'turn.completed':
            raise ValueError('Missing successful terminal Codex turn.')
        if any('item' in e and not isinstance(e['item'], dict) for e in events):
            raise ValueError('Invalid Codex item.')
        if any(e.get('type') == 'error' or e.get('item', {}).get('type') == 'error' for e in events):
            raise ValueError('Codex reported an error.')
        result = {'usage': terminal[0].get('usage'), 'cost_usd': None, 'model': None, 'loaded_skills': None}
    if result['usage'] is not None and (not isinstance(result['usage'], dict)
            or any(type(value) not in (int, float) or not math.isfinite(value) or value < 0
                   for key, value in result['usage'].items() if key.endswith('_tokens') and value is not None)):
        raise ValueError('Invalid runtime usage metadata.')
    cost = result['cost_usd']
    if cost is not None and (type(cost) not in (int, float) or not math.isfinite(cost) or cost < 0):
        raise ValueError('Invalid runtime cost metadata.')
    result['instruction_loading'] = None
    result['missing_measurements'] = {key: 'Not established by runtime telemetry.'
        for key in ('usage', 'cost_usd', 'model', 'loaded_skills', 'instruction_loading') if result[key] is None}
    return result


def context_table(text: str, heading: str) -> list[list[str]]:
    """Return the body rows of one Markdown table from Claude's /context report."""
    rows, parts = [], text.split(f'### {heading}', 1)
    for line in parts[1].splitlines() if len(parts) == 2 else []:
        if line.startswith('###'):
            break
        cells = [cell.strip() for cell in line.strip().strip('|').split('|')]
        if line.startswith('|') and len(cells) >= 2 and not set(cells[0]) <= set('-'):
            rows.append(cells)
    return rows[1:]


def run_subject(agent: str, executable: str, model: str, task: dict, workspace: Path, trial_root: Path,
                budget: float = 1, codex_home: Path | None = None) -> dict:
    loading = None
    if agent == 'claude':
        # --restricted would also drop the user CLAUDE.md and skills; reads are fenced by settings
        # and dontAsk denies any edit outside the workspace. Skills stay readable under the read
        # block; --add-dir would make them sandbox-writable and breaks bwrap's protected-path mounts.
        config = trial_root / 'home/.claude'
        common = ['--model', model, '--tools', 'Read,Edit,Write,Bash,Glob,Grep,Skill',
                  '--allowedTools', f'Bash,Skill,Edit(/{workspace}/**)', '--permission-mode', 'dontAsk',
                  '--setting-sources', 'user',
                  '--settings', str(config / 'settings.json'), '--strict-mcp-config',
                  '--mcp-config', '{"mcpServers":{}}', '--no-session-persistence']
        argv = [executable, '--print', '--output-format', 'stream-json', '--verbose', *common,
                '--max-budget-usd', str(budget), '--debug-file', str(trial_root / 'claude-debug.log')]
        # /context is local; without credentials it cannot start a paid model call.
        context = invoke([executable, '--print', '--output-format', 'text', *common], workspace,
                         environment(trial_root / 'home'), '/context', 60)
        loading = {'source': 'Claude /context without credentials, before the subject run.',
                   'memory_files': [row[1] for row in context_table(context['stdout'], 'Memory Files')],
                   'user_skills': sorted(row[0] for row in context_table(context['stdout'], 'Skills') if row[1] == 'User')}
        staged = [str(config / 'CLAUDE.md')] if (config / 'CLAUDE.md').exists() else []
        skills = sorted(path.name for path in (config / 'skills').iterdir() if (path / 'SKILL.md').is_file())
        loading['confirmed'] = not (context['error'] or context['returncode']) and (
            loading['memory_files'] == staged and loading['user_skills'] == skills)
        if not loading['confirmed']:
            return {**context, 'argv': argv, 'instruction_loading': loading,
                    'error': 'Claude /context did not confirm exactly the staged instructions and skills.'}
    else:
        argv = [executable, 'exec', '--json', '--model', model, '--sandbox', 'workspace-write',
                '--ephemeral', '--strict-config', '--config', 'approval_policy="never"', '-']
    env = environment(trial_root / 'home', agent)
    if codex_home:
        env['CODEX_HOME'] = str(codex_home)
    result = invoke(argv, workspace, env, task['prompt'], task['timeout_seconds'])
    result['argv'] = argv
    if loading:
        result['instruction_loading'] = loading
    debug_log = trial_root / 'claude-debug.log'
    if agent == 'claude' and debug_log.is_file():
        result['debug_log'] = redact(debug_log.read_text(encoding='utf-8', errors='replace'))
    if result['error'] or result['returncode']:
        result['error'] = result['error'] or f"Runtime exited with status {result['returncode']}."
        return result
    try:
        result.update(parse_runtime(agent, result['stdout']))
        if loading:
            result['instruction_loading'] = loading
            result['missing_measurements'].pop('instruction_loading', None)
        return result
    except (ValueError, TypeError) as error:
        result['error'] = str(error)
        return result


def verify_trial(task: dict, workspace: Path, trial_root: Path) -> dict:
    home = trial_root / 'verifier-home'
    home.mkdir()
    result = {}
    for name, field in [('acceptance', 'verification'), ('regression', 'regression_verification')]:
        command = [sys.executable, '-I', str(Path(task['fixture_root']) / task[field][1]), str(workspace)]
        check = invoke(command, trial_root, environment(home), '', task['verification_timeout_seconds'])
        check['status'] = 'ERROR' if check['error'] else 'PASS' if check['returncode'] == 0 else 'FAIL'
        result[name] = check
    return result


def changes(task: dict, workspace: Path) -> dict:
    before = files(Path(task['fixture_root']) / task['snapshot'])
    after = files(workspace)
    original = Path(task['fixture_root']) / task['snapshot']
    before_modes = {name: (original / name).lstat().st_mode & 0o7777 for name in before}
    after_modes = {name: (workspace / name).lstat().st_mode & 0o7777 for name in after}
    changed = sorted(name for name in before.keys() | after.keys()
                     if before.get(name) != after.get(name) or before_modes.get(name) != after_modes.get(name))
    def matches(name, paths):
        return any(name == path or name.startswith(path + '/') for path in paths)
    diff = []
    for name in changed:
        if before_modes.get(name) != after_modes.get(name):
            diff.append(f'File mode {name}: {before_modes.get(name)} -> {after_modes.get(name)}\n')
        diff.extend(difflib.unified_diff(before.get(name, b'').decode('utf-8', 'replace').splitlines(True),
                                       after.get(name, b'').decode('utf-8', 'replace').splitlines(True),
                                       fromfile='a/' + name, tofile='b/' + name))
    return {'changes': changed, 'diff': redact(''.join(diff)),
            'protected_changes': [name for name in changed if matches(name, task['protected_paths'])],
            'implementation_changed': any(matches(name, task['implementation_paths']) for name in changed),
            'scope_review': 'pending' if any(not matches(name, task['implementation_paths']) for name in changed) else 'not_flagged'}


def gate_log(trial_root: Path) -> list[dict] | None:
    """The verify gate's decision records from the trial home, or None if it logged nothing."""
    path = trial_root / 'home/.cache/verify-gate/log.jsonl'
    if not path.is_file():
        return None
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def gate_ran(records: list[dict] | None) -> bool:
    """True if the gate sent the agent to verify and logged its reply."""
    steps = [r.get('step') for r in records or [] if r.get('step') != 'check' or r.get('why')]
    return 'check' in steps and 'verified' in steps


def write_results(output: Path, report: dict) -> None:
    statuses = {trial['status'] for trial in report['trials']}
    report['status'] = next((status for status in ('ERROR', 'SKIP', 'NOT_RUN', 'FAIL', 'REVIEW')
                             if status in statuses), 'PASS')
    report['counts'] = {'scheduled': len(report['trials']),
        'started': sum(t.get('started', False) for t in report['trials']),
        'completed': sum(t['status'] in ('PASS', 'FAIL', 'REVIEW') for t in report['trials']),
        'failed': sum(t['status'] in ('FAIL', 'ERROR') for t in report['trials']),
        'skipped': sum(t['status'] == 'SKIP' for t in report['trials']),
        'not_run': sum(t['status'] == 'NOT_RUN' for t in report['trials'])}
    (output / 'results.json').write_text(redact(json.dumps(report, indent=2)) + '\n')
    lines = ['# Coding evaluations', '', 'Unknown measurements are null. REVIEW requires human assessment.', '',
             '| Task | Instructions | Gate | Status | Subject seconds | Scope review |',
             '| --- | --- | --- | --- | --- | --- |']
    for trial in report['trials']:
        elapsed = trial.get('runtime', {}).get('elapsed_seconds', 'unknown')
        lines.append(f"| {trial['task']} | {trial['variant']} | {trial.get('gate', 'off')} | {trial['status']} | "
                     f"{elapsed} | {trial.get('scope_review', 'unknown')} |")
        if trial.get('error'):
            lines.extend(['', f"Trial {trial['index']}: {trial['error']}"])
    lines.extend(['', '| Gate | Passed | Failed | Pending review |', '| --- | --- | --- | --- |'])
    for gate in sorted({trial.get('gate', 'off') for trial in report['trials']}):
        counts = [sum(t.get('gate', 'off') == gate and t['status'] == status for t in report['trials'])
                  for status in ('PASS', 'FAIL', 'REVIEW')]
        lines.append(f"| {gate} | {' | '.join(map(str, counts))} |")
    (output / 'summary.md').write_text(redact('\n'.join(lines)) + '\n')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--agent', choices=('claude', 'codex'), required=True)
    parser.add_argument('--runtime', help='Explicit executable; defaults to the selected agent on PATH.')
    parser.add_argument('--model', required=True)
    parser.add_argument('--task')
    parser.add_argument('--manifest', type=Path, default=ROOT / 'evals/coding/tasks.json')
    parser.add_argument('--instructions', nargs='+', choices=('baseline', 'none'), default=['baseline'])
    parser.add_argument('--gate', nargs='+', choices=('off', 'on'), default=['off'],
                        help='Run the verify gate (self-check only) in the trial; Claude only.')
    parser.add_argument('--repeats', type=int, default=2)
    parser.add_argument('--timeout', type=float, help='Override subject timeout seconds.')
    parser.add_argument('--max-budget-usd', type=float, default=1, help='Claude per-session cap; not a total-run cap.')
    parser.add_argument('--supervised', action='store_true', help='Acknowledge manual supervision for one Codex trial without a dollar cap.')
    parser.add_argument('--execute', action='store_true', help='Opt in to paid execution after budget authorization.')
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--codex-home', type=Path,
                        help='Absolute dedicated CODEX_HOME holding a separate Codex login; trial files are staged and removed.')
    args = parser.parse_args()
    try:
        if (args.repeats < 1 or len(set(args.instructions)) != len(args.instructions)
                or len(set(args.gate)) != len(args.gate)):
            raise ValueError('Repeats must be positive and variants unique.')
        if args.agent == 'codex' and 'on' in args.gate:
            raise ValueError('--gate on supports only --agent claude: Codex skips hooks until they are trusted interactively.')
        if args.codex_home and (args.agent != 'codex' or not args.codex_home.is_absolute() or not args.codex_home.is_dir()):
            raise ValueError('--codex-home requires --agent codex and an existing absolute directory.')
        for value in (args.timeout, args.max_budget_usd):
            if value is not None and (not math.isfinite(value) or value <= 0):
                raise ValueError('Time and budget limits must be positive and finite.')
        tasks = load_tasks(args.manifest.resolve(), args.task)
        if args.timeout:
            tasks = [{**task, 'timeout_seconds': args.timeout} for task in tasks]
        sources = {'baseline': ROOT / 'instructions/general-global.md', 'none': None}
        trials = []
        combos = [(variant, gate) for variant in args.instructions for gate in args.gate]
        for task in tasks:
            for repeat in range(args.repeats):
                for variant, gate in combos if repeat % 2 == 0 else list(reversed(combos)):
                    source = sources[variant]
                    trials.append({'index': len(trials) + 1, 'task': task['id'], 'repeat': repeat + 1,
                        'variant': variant, 'gate': gate,
                        'instruction_sha256': hashlib.sha256(source.read_bytes()).hexdigest() if source else None,
                        'status': 'NOT_RUN', 'started': False})
        names = RUNTIME_CREDENTIALS[args.agent]
        credential = 'CODEX_HOME login' if args.codex_home else next(
            (name for name in names if os.environ.get(name)), ' or '.join(names))
        report = {'schema_version': 1, 'agent': args.agent,
                  'gate_sha256': hashlib.sha256((ROOT / 'hooks/verify-gate.py').read_bytes()).hexdigest()
                  if 'on' in args.gate else None, 'requested_model': args.model,
                  'runtime': args.runtime or args.agent, 'runtime_version': None, 'trials': trials,
                  'manifest_sha256': hashlib.sha256(args.manifest.read_bytes()).hexdigest(),
                  'fixture_sha256': hashes(args.manifest.parent), 'skill_sha256': hashes(ROOT / 'skills'),
                  'isolation': {'host_configuration_copied': False, 'credential': credential,
                                'native_instruction_loading_confirmed': False, 'external_machine_policy': 'unknown'},
                  'codex_home': {'path': str(args.codex_home),
                                 'shared_state': 'Codex-owned login refreshes, logs, and caches persist across trials.'}
                                if args.codex_home else None,
                  'cost_control': {'per_session_usd': args.max_budget_usd if args.agent == 'claude' else None,
                                   'hard_total_cap': False, 'supervised': args.supervised}}
        if not args.execute:
            print(json.dumps(report, indent=2))
            return 0
        if args.agent == 'codex' and (len(trials) != 1 or not args.supervised):
            raise ValueError('Codex execution requires --supervised and a single trial; no dollar cap is available.')
        output = args.output_dir or ROOT / 'coding-eval-results' / str(time.time_ns())
        output.mkdir(parents=True, mode=0o700, exist_ok=False)
        runtime = shutil.which(args.runtime or args.agent)
        preflight = None
        if not runtime or not (any(os.environ.get(name) for name in names) or args.codex_home):
            preflight = ('SKIP', 'Runtime or explicit environment credential is unavailable.')
        else:
            with tempfile.TemporaryDirectory(prefix='coding-preflight-') as temporary:
                root = Path(temporary)
                env = environment(root)
                help_args = ['exec', '--help'] if args.agent == 'codex' else ['--help']
                help_result = invoke([runtime, *help_args], root, env, '', 10)
                version = invoke([runtime, '--version'], root, env, '', 10)
                missing = [flag for flag in REQUIRED[args.agent] if flag not in help_result['stdout']]
                report['capabilities'] = {'required_flags': list(REQUIRED[args.agent]), 'missing_flags': missing}
                if (help_result['error'] or help_result['returncode'] or version['error'] or version['returncode'] or missing):
                    preflight = ('ERROR', 'Runtime preflight failed or lacks required flags.')
                report['runtime_version'] = version['stdout'].strip()
                if args.codex_home and not preflight:
                    conflicts = [name for name in CODEX_HOME_RESERVED if (args.codex_home / name).exists()
                                 and not (name in CODEX_MANAGED and (args.codex_home / name).is_dir()
                                          and {path.name for path in (args.codex_home / name).iterdir()}
                                          <= CODEX_MANAGED[name])]
                    login = invoke([runtime, 'login', 'status'], root, {**env, 'CODEX_HOME': str(args.codex_home)}, '', 10)
                    if conflicts:
                        preflight = ('ERROR', 'Dedicated CODEX_HOME already contains: ' + ', '.join(conflicts))
                    elif login['error'] or login['returncode']:
                        preflight = ('SKIP', 'Dedicated CODEX_HOME is not logged in.')
        write_results(output, report)
        for trial in trials:
            if preflight:
                trial.update(status=preflight[0], error=preflight[1])
                continue
            task = next(task for task in tasks if task['id'] == trial['task'])
            try:
                with (tempfile.TemporaryDirectory(prefix='power-agents-coding-') as temporary,
                      staged_codex_home(args.codex_home)):
                    root = Path(temporary)
                    work = stage_trial(task, root, args.agent, sources[trial['variant']], ROOT / 'skills', args.codex_home,
                                       gate=trial['gate'] == 'on')
                    trial['workspace'] = str(work)
                    trial['started'] = True
                    try:
                        trial['runtime'] = run_subject(args.agent, runtime, args.model, task, work, root,
                                                       args.max_budget_usd, args.codex_home)
                        debug_log = trial['runtime'].pop('debug_log', None)
                        if debug_log is not None:
                            # Native loading evidence for manual review; kept private beside the results.
                            path = output / f"trial-{trial['index']}-claude-debug.log"
                            path.touch(mode=0o600)
                            path.write_text(debug_log)
                            trial['runtime']['claude_md_debug_lines'] = [
                                line for line in debug_log.splitlines() if 'CLAUDE.md' in line][:20]
                        if trial['runtime']['error']:
                            raise ValueError(trial['runtime']['error'])
                    finally:
                        trial.update(changes(task, work))
                        if trial['gate'] == 'on':
                            trial['gate_log'] = gate_log(root)
                    if trial['gate'] == 'on' and not gate_ran(trial['gate_log']):
                        raise ValueError('The verify gate did not run its verification pass in this trial.')
                    trial['verification'] = verify_trial(task, work, root)
                    trial.update(changes(task, work))
                    statuses = [check['status'] for check in trial['verification'].values()]
                    trial['manual_review'] = 'pending' if task['manual_review'] else 'not_required'
                    trial['status'] = ('ERROR' if 'ERROR' in statuses else 'FAIL' if 'FAIL' in statuses
                        or trial['protected_changes'] or not trial['implementation_changed']
                        else 'REVIEW' if task['manual_review'] else 'PASS')
            except (OSError, ValueError, TypeError) as error:
                trial.update(status='ERROR', error=redact(str(error)))
            except KeyboardInterrupt:
                trial.update(status='ERROR', error='Interrupted; subject process group terminated.')
            write_results(output, report)
            if trial['status'] == 'ERROR':
                break
        # Confirmed only when /context matched the staged files in every trial.
        report['isolation']['native_instruction_loading_confirmed'] = all(
            ((trial.get('runtime') or {}).get('instruction_loading') or {}).get('confirmed') for trial in trials)
        write_results(output, report)
        statuses = {trial['status'] for trial in trials}
        print(f"Results: {output}")
        return 2 if statuses & {'ERROR', 'SKIP', 'NOT_RUN'} else 1 if 'FAIL' in statuses else 0
    except (OSError, ValueError, TypeError) as error:
        print('ERROR: ' + redact(str(error)), file=sys.stderr)
        return 2


if __name__ == '__main__':
    def interrupt(_signum, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupt)
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print('ERROR: Interrupted.', file=sys.stderr)
        sys.exit(2)
