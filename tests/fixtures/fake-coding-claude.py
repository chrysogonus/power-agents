#!/usr/bin/env python3
"""Free coding-runtime protocol simulator used only by offline tests."""
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def simulate(agent, mode, counter):
    flags = {
        'claude': '--print --output-format --verbose --model --tools --allowedTools --permission-mode --setting-sources --settings --strict-mcp-config --mcp-config --no-session-persistence --max-budget-usd --debug-file',
        'codex': '--json --model --sandbox --ephemeral --config --strict-config',
    }
    if '--help' in sys.argv:
        print('unsupported' if mode == 'unsupported' else flags[agent])
        return
    if '--version' in sys.argv:
        print('fake-coding-runtime 1.0')
        return
    if sys.argv[1:3] == ['login', 'status']:
        sys.exit(0 if (Path(os.environ['CODEX_HOME']) / 'auth.json').exists() else 1)
    prompt = sys.stdin.read()
    if agent == 'claude' and prompt == '/context':
        assert not os.environ.get('ANTHROPIC_API_KEY') and not os.environ.get('CLAUDE_CODE_OAUTH_TOKEN')
        config = Path(os.environ['CLAUDE_CONFIG_DIR'])
        memory = (['/elsewhere/CLAUDE.md'] if mode == 'context-mismatch'
                  else [str(config / 'CLAUDE.md')] if (config / 'CLAUDE.md').exists() else [])
        print('## Context Usage\n\n### Memory Files\n\n| Type | Path | Tokens |\n|------|------|--------|')
        for path in memory:
            print(f'| User | {path} | 1k |')
        print('\n### Skills\n\n| Skill | Source | Tokens |\n|-------|--------|--------|')
        for path in sorted((config / 'skills').glob('*/SKILL.md')):
            print(f'| {path.parent.name} | User | ~100 |')
        print('| simplify | Built-in | ~60 |')
        return
    home = Path(os.environ['HOME'])
    work = Path.cwd()
    assert home.parent == work.parent
    assert not os.environ.get('UNMANAGED_SECRET')
    assert not os.environ.get('OPENAI_API_KEY')
    assert not os.environ.get('ANTHROPIC_AUTH_TOKEN')
    assert not os.environ.get('CLAUDE_CODE_SIMPLE')
    assert not (home / '.config').exists()
    selected = 'ANTHROPIC_API_KEY' if agent == 'claude' else 'CODEX_API_KEY'
    if agent == 'claude' and not os.environ.get(selected):
        selected = 'CLAUDE_CODE_OAUTH_TOKEN'
    config = Path(os.environ['CLAUDE_CONFIG_DIR' if agent == 'claude' else 'CODEX_HOME'])
    assert os.environ.get(selected) or (agent == 'codex' and (config / 'auth.json').exists())
    assert not os.environ.get('CODEX_API_KEY' if agent == 'claude' else 'ANTHROPIC_API_KEY')
    if agent == 'claude':
        assert '--restricted' not in sys.argv
        assert '--add-dir' not in sys.argv
        allowed = sys.argv[sys.argv.index('--allowedTools') + 1].split(',')
        assert allowed == ['Bash', 'Skill', f'Edit(/{work}/**)']
        settings = json.loads((config / 'settings.json').read_text())
        assert settings['disableAllHooks']
        assert settings['permissions']['blockReadsOutsideWorkingDirectories']
        assert settings['sandbox']['enabled']
        assert not settings['sandbox']['allowUnsandboxedCommands']
        assert settings['sandbox']['failIfUnavailable']
        assert sys.argv[sys.argv.index('--permission-mode') + 1] == 'dontAsk'
        assert (config / 'skills/ponytail/SKILL.md').is_file()
    else:
        assert sys.argv[sys.argv.index('--sandbox') + 1] == 'workspace-write'
        assert (home / '.agents/skills/ponytail/SKILL.md').is_file()
        policy = (config / 'config.toml').read_text()
        assert 'inherit = "none"' in policy
        assert '[features]\nplugins = false\nremote_plugin = false\napps = false\n' in policy
        assert f'HOME = {json.dumps(str(home))}' in policy
        assert f'TMPDIR = {json.dumps(str(work / ".tmp"))}' in policy
        assert (work / '.tmp').is_dir()
    assert not any('bypass' in arg or arg == '--bare' for arg in sys.argv)
    instruction = config / ('CLAUDE.md' if agent == 'claude' else 'AGENTS.md')
    if instruction.exists():
        actual = hashlib.sha256(instruction.read_bytes()).hexdigest()
        allowed = [hashlib.sha256((ROOT / 'instructions' / name).read_bytes()).hexdigest()
                   for name in ('general-global.md', 'general-global.candidate.md')]
        assert actual in allowed
    if agent == 'claude':
        with open(sys.argv[sys.argv.index('--debug-file') + 1], 'w') as log:
            if instruction.exists():
                log.write(f'Loaded user memory {instruction} (CLAUDE.md)\n')
            if mode == 'redact':
                log.write(os.environ[selected] + '\n')
    task = next(task for task in json.loads((ROOT / 'evals/coding/tasks.json').read_text())['tasks']
                if (work / task['implementation_paths'][0]).exists())
    assert prompt == task['prompt']
    if mode == 'hang':
        child = subprocess.Popen(['sleep', '60'])
        counter.write_text(json.dumps([os.getpid(), child.pid]))
        time.sleep(60)
        return
    counter.write_text('started')
    if mode not in ('early-stop', 'test-tamper'):
        result = subprocess.run(['git', 'apply', str(ROOT / 'evals/coding' / task['reference_patch'])], capture_output=True)
        assert result.returncode == 0, result.stderr
    if mode == 'verifier-side-effect':
        source = work / task['implementation_paths'][0]
        source.write_text("from pathlib import Path\nPath(__file__).with_name('README.md').write_text('unexpected side effect')\n" + source.read_text())
    if mode == 'protected-mode':
        (work / 'README.md').chmod(0o700)
    if mode == 'protected':
        (work / 'README.md').write_text('changed')
    if mode in ('test-tamper', 'unrelated'):
        (work / ('test_fake.py' if mode == 'test-tamper' else 'extra.txt')).write_text('assert True\n')
    if mode == 'symlink':
        (work / 'external-link').symlink_to('/etc/passwd')
    if mode == 'redact':
        (work / 'extra.txt').write_text(os.environ[selected])
        print(os.environ[selected], file=sys.stderr)
    if mode == 'malformed':
        print('invalid jsonl')
        return
    emit = lambda value: print(json.dumps(value), flush=True)
    if mode == 'truncated':
        emit({'type': 'turn.started'})
        return
    emit({'type': 'system', 'native_instruction_sha256': hashlib.sha256(instruction.read_bytes()).hexdigest() if instruction.exists() else None})
    if mode == 'bad-item':
        emit({'type': 'item.completed', 'item': []})
        emit({'type': 'assistant', 'message': {'content': 'invalid'}})
    if agent == 'claude':
        emit({'type': 'system', 'subtype': 'init', 'model': 'fake-model'})
        if mode == 'sandbox-failure':
            emit({'type': 'user', 'message': {'content': [{'type': 'tool_result', 'tool_use_id': 'b', 'is_error': True,
                  'content': "Exit code 1\nbwrap: Can't create file at /x/.mcp.json: Read-only file system"}]}})
        if mode == 'spoofed-skill':
            emit({'type': 'user', 'message': {'content': [{'type': 'tool_use', 'id': 'x', 'name': 'Skill', 'input': {'skill': 'ponytail'}}]}})
        if mode != 'no-metadata':
            emit({'type': 'assistant', 'message': {'content': [{'type': 'tool_use', 'name': 'Skill', 'id': 'skill-1', 'input': {'skill': 'ponytail'}}]}})
            emit({'type': 'user', 'message': {'content': [{'type': 'tool_result', 'tool_use_id': 'skill-1', 'content': 'loaded'}]}})
        final = {'type': 'result', 'subtype': 'success', 'is_error': False, 'result': 'Done', 'permission_denials': []}
        if mode != 'no-metadata':
            final.update(usage={'input_tokens': 11, 'output_tokens': 7}, total_cost_usd=0.01)
        if mode == 'bad-usage':
            final['usage'] = 'invalid'
        if mode == 'denied':
            final['permission_denials'] = [{'tool_name': 'Bash'}]
        if mode == 'failed':
            final['is_error'] = True
        emit(final)
    else:
        emit({'type': 'thread.started', 'thread_id': 'fake'})
        if mode in ('denied', 'spoofed-skill'):
            emit({'type': 'error', 'message': 'Permission denied'})
        emit({'type': 'item.completed', 'item': {'type': 'agent_message', 'text': 'Done'}})
        final = {'type': 'turn.failed' if mode == 'failed' else 'turn.completed'}
        if mode != 'no-metadata':
            final['usage'] = {'input_tokens': 11, 'output_tokens': 7}
        if mode == 'bad-usage':
            final['usage'] = 'invalid'
        emit(final)


def main(mode, counter):
    simulate('claude', mode, counter)
