#!/usr/bin/env python3
"""Describe or explicitly execute isolated coding trials. Live calls are opt-in."""
from __future__ import annotations

import argparse
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
CREDENTIALS = ('ANTHROPIC_API_KEY', 'CODEX_API_KEY', 'OPENAI_API_KEY')
REQUIRED = {
    'claude': ('--print', '--output-format', '--verbose', '--model', '--tools', '--allowedTools',
               '--permission-mode', '--setting-sources', '--settings', '--strict-mcp-config',
               '--mcp-config', '--no-session-persistence', '--max-budget-usd', '--restricted', '--add-dir'),
    'codex': ('--json', '--model', '--sandbox', '--ephemeral', '--config', '--strict-config'),
}


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
    if agent:
        name = 'ANTHROPIC_API_KEY' if agent == 'claude' else 'CODEX_API_KEY'
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


def stage_trial(task: dict, trial_root: Path, agent: str, instruction_file: Path | None, skills_root: Path) -> Path:
    home, workspace = trial_root / 'home', trial_root / 'work'
    home.mkdir()
    shutil.copytree(Path(task['fixture_root']) / task['snapshot'], workspace)
    (workspace / '.tmp').mkdir()
    config = home / ('.claude' if agent == 'claude' else '.codex')
    config.mkdir()
    skill_target = config / 'skills' if agent == 'claude' else home / '.agents/skills'
    shutil.copytree(skills_root, skill_target)
    if instruction_file:
        shutil.copyfile(instruction_file, config / ('CLAUDE.md' if agent == 'claude' else 'AGENTS.md'))
    if agent == 'claude':
        (config / 'settings.json').write_text(json.dumps({'disableAllHooks': True,
            'sandbox': {'enabled': True, 'autoAllowBashIfSandboxed': True, 'allowUnsandboxedCommands': False}}))
    else:
        (config / 'config.toml').write_text('approval_policy = "never"\nsandbox_mode = "workspace-write"\n'
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


def run_subject(agent: str, executable: str, model: str, task: dict, workspace: Path, trial_root: Path,
                budget: float = 1) -> dict:
    if agent == 'claude':
        tools = 'Read,Edit,Write,Bash,Glob,Grep,Skill'
        argv = [executable, '--print', '--output-format', 'stream-json', '--verbose', '--model', model,
                '--tools', tools, '--allowedTools', tools, '--permission-mode', 'dontAsk',
                '--restricted', '--add-dir', str(trial_root / 'home/.claude/skills'),
                '--setting-sources', 'user', '--settings', str(trial_root / 'home/.claude/settings.json'),
                '--strict-mcp-config', '--mcp-config', '{"mcpServers":{}}', '--no-session-persistence',
                '--max-budget-usd', str(budget)]
    else:
        argv = [executable, 'exec', '--json', '--model', model, '--sandbox', 'workspace-write',
                '--ephemeral', '--strict-config', '--config', 'approval_policy="never"', '-']
    result = invoke(argv, workspace, environment(trial_root / 'home', agent), task['prompt'], task['timeout_seconds'])
    result['argv'] = argv
    if result['error'] or result['returncode']:
        result['error'] = result['error'] or f"Runtime exited with status {result['returncode']}."
        return result
    try:
        return {**result, **parse_runtime(agent, result['stdout'])}
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
             '| Task | Instructions | Status | Subject seconds | Scope review |', '| --- | --- | --- | --- | --- |']
    for trial in report['trials']:
        elapsed = trial.get('runtime', {}).get('elapsed_seconds', 'unknown')
        lines.append(f"| {trial['task']} | {trial['variant']} | {trial['status']} | {elapsed} | {trial.get('scope_review', 'unknown')} |")
        if trial.get('error'):
            lines.extend(['', f"Trial {trial['index']}: {trial['error']}"])
    (output / 'summary.md').write_text(redact('\n'.join(lines)) + '\n')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--agent', choices=('claude', 'codex'), required=True)
    parser.add_argument('--runtime', help='Explicit executable; defaults to the selected agent on PATH.')
    parser.add_argument('--model', required=True)
    parser.add_argument('--task')
    parser.add_argument('--manifest', type=Path, default=ROOT / 'evals/coding/tasks.json')
    parser.add_argument('--instructions', nargs='+', choices=('baseline', 'candidate', 'none'), default=['baseline'])
    parser.add_argument('--repeats', type=int, default=2)
    parser.add_argument('--timeout', type=float, help='Override subject timeout seconds.')
    parser.add_argument('--max-budget-usd', type=float, default=1, help='Claude per-session cap; not a total-run cap.')
    parser.add_argument('--supervised', action='store_true', help='Acknowledge manual supervision for one Codex trial without a dollar cap.')
    parser.add_argument('--execute', action='store_true', help='Opt in to paid execution after budget authorization.')
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    try:
        if args.repeats < 1 or len(set(args.instructions)) != len(args.instructions):
            raise ValueError('Repeats must be positive and variants unique.')
        for value in (args.timeout, args.max_budget_usd):
            if value is not None and (not math.isfinite(value) or value <= 0):
                raise ValueError('Time and budget limits must be positive and finite.')
        tasks = load_tasks(args.manifest.resolve(), args.task)
        if args.timeout:
            tasks = [{**task, 'timeout_seconds': args.timeout} for task in tasks]
        sources = {'baseline': ROOT / 'instructions/general-global.md',
                   'candidate': ROOT / 'instructions/general-global.candidate.md', 'none': None}
        trials = []
        for task in tasks:
            for repeat in range(args.repeats):
                variants = args.instructions if repeat % 2 == 0 else list(reversed(args.instructions))
                for variant in variants:
                    source = sources[variant]
                    trials.append({'index': len(trials) + 1, 'task': task['id'], 'repeat': repeat + 1,
                        'variant': variant, 'instruction_sha256': hashlib.sha256(source.read_bytes()).hexdigest() if source else None,
                        'status': 'NOT_RUN', 'started': False})
        report = {'schema_version': 1, 'agent': args.agent, 'requested_model': args.model,
                  'runtime': args.runtime or args.agent, 'runtime_version': None, 'trials': trials,
                  'manifest_sha256': hashlib.sha256(args.manifest.read_bytes()).hexdigest(),
                  'fixture_sha256': hashes(args.manifest.parent), 'skill_sha256': hashes(ROOT / 'skills'),
                  'isolation': {'host_configuration_copied': False, 'credential': 'ANTHROPIC_API_KEY' if args.agent == 'claude' else 'CODEX_API_KEY',
                                'native_instruction_loading_confirmed': False, 'external_machine_policy': 'unknown'},
                  'cost_control': {'per_session_usd': args.max_budget_usd if args.agent == 'claude' else None,
                                   'hard_total_cap': False, 'supervised': args.supervised}}
        if not args.execute:
            print(json.dumps(report, indent=2))
            return 0
        if args.agent == 'codex' and (len(trials) != 1 or not args.supervised):
            raise ValueError('Codex execution requires --supervised and a single trial; no dollar cap is available.')
        output = args.output_dir or ROOT / 'coding-eval-results' / str(time.time_ns())
        output.mkdir(parents=True, mode=0o700, exist_ok=False)
        credential = 'ANTHROPIC_API_KEY' if args.agent == 'claude' else 'CODEX_API_KEY'
        runtime = shutil.which(args.runtime or args.agent)
        preflight = None
        if not runtime or not os.environ.get(credential):
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
        write_results(output, report)
        for trial in trials:
            if preflight:
                trial.update(status=preflight[0], error=preflight[1])
                continue
            task = next(task for task in tasks if task['id'] == trial['task'])
            try:
                with tempfile.TemporaryDirectory(prefix='power-agents-coding-') as temporary:
                    root = Path(temporary)
                    work = stage_trial(task, root, args.agent, sources[trial['variant']], ROOT / 'skills')
                    trial['workspace'] = str(work)
                    trial['started'] = True
                    try:
                        trial['runtime'] = run_subject(args.agent, runtime, args.model, task, work, root, args.max_budget_usd)
                        if trial['runtime']['error']:
                            raise ValueError(trial['runtime']['error'])
                    finally:
                        trial.update(changes(task, work))
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
