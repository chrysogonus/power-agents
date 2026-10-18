#!/usr/bin/env python3
"""Offline end-to-end checks; never invoke a real model runtime."""
import json
import os
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / 'scripts/run-coding-evals.py'


class CodingRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.invocations = 0

    def tearDown(self):
        self.temp.cleanup()

    def prepare(self, agent='claude', mode='success', execute=True, extra=(), credential=True):
        self.invocations += 1
        runtime = self.root / f'runtime-{self.invocations}'
        counter = self.root / f'counter-{self.invocations}'
        fake = ROOT / 'tests/fixtures' / ('fake-codex.py' if agent == 'codex' else 'fake-coding-claude.py')
        runtime.write_text('#!/usr/bin/env python3\nimport runpy\nfrom pathlib import Path\n'
                           f"runpy.run_path({str(fake)!r})['main']({mode!r}, Path({str(counter)!r}))\n")
        runtime.chmod(0o700)
        output = self.root / f'results-{self.invocations}'
        env = dict(os.environ)
        for key in ('OPENAI_API_KEY', 'CODEX_API_KEY', 'ANTHROPIC_API_KEY'):
            env.pop(key, None)
        if credential:
            env['ANTHROPIC_API_KEY' if agent == 'claude' else 'CODEX_API_KEY'] = 'test-only-selected-credential'
        env['OPENAI_API_KEY'] = 'test-only-unselected-credential'
        env['UNMANAGED_SECRET'] = 'must-not-inherit'
        cmd = ['python3', str(RUNNER), '--agent', agent, '--runtime', str(runtime), '--model', 'fake-model',
               '--task', 'retry-idempotence', '--repeats', '1', '--output-dir', str(output)]
        if execute:
            cmd += ['--execute']
        if agent == 'codex':
            cmd += ['--supervised']
        return [*cmd, *extra], env, output, counter

    def run_cli(self, **options):
        cmd, env, output, counter = self.prepare(**options)
        result = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=30)
        report = json.loads((output / 'results.json').read_text()) if (output / 'results.json').exists() else None
        return result, report, output, counter

    def test_describe_never_starts_runtime_and_balances_matrix(self):
        cmd, env, output, counter = self.prepare(execute=False,
            extra=('--instructions', 'baseline', 'candidate', 'none', '--repeats', '2'))
        result = subprocess.run(cmd, env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual([t['variant'] for t in report['trials']], ['baseline', 'candidate', 'none', 'none', 'candidate', 'baseline'])
        self.assertFalse(counter.exists())
        self.assertFalse(output.exists())

    def test_both_adapters_and_all_instruction_variants(self):
        for agent in ('claude', 'codex'):
            for variant in ('baseline', 'candidate', 'none'):
                with self.subTest(agent=agent, variant=variant):
                    result, report, output, _ = self.run_cli(agent=agent, extra=('--instructions', variant))
                    self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                    trial = report['trials'][0]
                    self.assertEqual(trial['status'], 'PASS')
                    self.assertEqual(trial['verification']['acceptance']['status'], 'PASS')
                    self.assertEqual(trial['verification']['regression']['status'], 'PASS')
                    self.assertIn('retry.py', trial['changes'])
                    self.assertEqual(trial['runtime']['usage']['input_tokens'], 11)
                    events = [json.loads(line) for line in trial['runtime']['stdout'].splitlines()]
                    self.assertEqual(events[0]['native_instruction_sha256'], trial['instruction_sha256'])
                    self.assertEqual(trial['runtime']['cost_usd'], 0.01 if agent == 'claude' else None)
                    self.assertEqual(report['counts']['started'], 1)
                    self.assertEqual(output.stat().st_mode & 0o777, 0o700)
                    self.assertFalse(Path(trial['workspace']).exists())

    def test_fake_success_protected_changes_and_missing_measurements(self):
        for mode, status in [('early-stop', 'FAIL'), ('test-tamper', 'FAIL'), ('protected', 'FAIL'),
                             ('unrelated', 'PASS'), ('no-metadata', 'PASS'), ('protected-mode', 'FAIL'), ('verifier-side-effect', 'FAIL')]:
            with self.subTest(mode=mode):
                result, report, _, _ = self.run_cli(mode=mode)
                trial = report['trials'][0]
                self.assertEqual(trial['status'], status)
                self.assertEqual(result.returncode, 0 if status == 'PASS' else 1)
                if mode == 'protected':
                    self.assertEqual(trial['protected_changes'], ['README.md'])
                if mode == 'unrelated':
                    self.assertIn('extra.txt', trial['changes'])
                    self.assertIn('extra.txt', trial['diff'])
                    self.assertEqual(trial['scope_review'], 'pending')
                if mode == 'no-metadata':
                    self.assertIsNone(trial['runtime']['usage'])
                    self.assertIsNone(trial['runtime']['loaded_skills'])
                    self.assertTrue(trial['runtime']['missing_measurements'])

    def test_errors_skips_and_single_trial_cost_gate(self):
        for agent in ('claude', 'codex'):
            for mode in ('malformed', 'failed', 'denied', 'unsupported', 'truncated', 'spoofed-skill', 'bad-item', 'bad-usage'):
                with self.subTest(agent=agent, mode=mode):
                    result, report, _, _ = self.run_cli(agent=agent, mode=mode)
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertEqual(report['trials'][0]['status'], 'ERROR')
                    if mode not in ('unsupported',):
                        self.assertIn('stdout', report['trials'][0]['runtime'])
            result, report, _, _ = self.run_cli(agent=agent, credential=False)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(report['trials'][0]['status'], 'SKIP')
        result, report, _, _ = self.run_cli(agent='codex', extra=('--repeats', '2'))
        self.assertEqual(result.returncode, 2)
        self.assertIn('single', result.stderr)
        result, report, _, _ = self.run_cli(extra=('--runtime', '/missing/coding-runtime'))
        self.assertEqual(report['trials'][0]['status'], 'SKIP')

    def test_refactor_requires_change_and_manual_review(self):
        result, report, _, _ = self.run_cli(extra=('--task', 'parser-refactor'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(report['trials'][0]['status'], 'REVIEW')
        self.assertEqual(report['trials'][0]['manual_review'], 'pending')
        result, report, _, _ = self.run_cli(mode='early-stop', extra=('--task', 'parser-refactor'))
        self.assertEqual(result.returncode, 1)
        self.assertFalse(report['trials'][0]['implementation_changed'])

    def test_redaction_and_verifier_environment(self):
        for agent in ('claude', 'codex'):
            result, report, output, _ = self.run_cli(agent=agent, mode='redact')
            self.assertEqual(result.returncode, 0, result.stderr)
            for path in output.rglob('*'):
                if path.is_file():
                    data = path.read_text()
                    self.assertNotIn('test-only-selected-credential', data)
                    self.assertNotIn('test-only-unselected-credential', data)
            self.assertNotIn('test-only-selected-credential', result.stdout + result.stderr)
            self.assertIn('[REDACTED]', (output / 'results.json').read_text())

    def test_verifier_has_no_credentials_and_times_out(self):
        import runpy
        functions = runpy.run_path(str(RUNNER))
        fixture = self.root / 'fixture'
        fixture.mkdir()
        check = fixture / 'check.py'
        check.write_text("import os\nassert not any(os.environ.get(k) for k in "
                         "('CODEX_API_KEY', 'OPENAI_API_KEY', 'ANTHROPIC_API_KEY', 'UNMANAGED_SECRET'))\n")
        work = self.root / 'work'
        work.mkdir()
        task = {'fixture_root': str(fixture), 'verification': ['python3', 'check.py'],
                'regression_verification': ['python3', 'check.py'], 'verification_timeout_seconds': 0.2}
        result = functions['verify_trial'](task, work, self.root)
        self.assertEqual(result['acceptance']['status'], 'PASS')
        check.write_text('import time\ntime.sleep(2)\n')
        second = self.root / 'second'
        second.mkdir()
        result = functions['verify_trial'](task, work, second)
        self.assertEqual(result['acceptance']['status'], 'ERROR')

    def test_unknown_metadata_and_error_stops_remaining_trials(self):
        result, report, _, _ = self.run_cli(mode='malformed', extra=('--repeats', '2'))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(report['counts']['started'], 1)
        self.assertEqual(report['trials'][1]['status'], 'NOT_RUN')
        result, report, _, _ = self.run_cli(mode='symlink')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('symlink: ', report['trials'][0]['diff'])

    def test_timeout_and_interrupt_terminate_descendants(self):
        for interrupt in (False, True):
            cmd, env, output, counter = self.prepare(mode='hang', extra=('--timeout', '0.5'))
            process = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            deadline = time.monotonic() + 10
            while not counter.exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(counter.exists())
            pids = json.loads(counter.read_text())
            if interrupt:
                process.send_signal(signal.SIGTERM)
            process.communicate(timeout=10)
            self.assertEqual(process.returncode, 2)
            for pid in pids:
                stat = Path(f'/proc/{pid}/stat')
                self.assertTrue(not stat.exists() or stat.read_text().split()[2] == 'Z')
            report = json.loads((output / 'results.json').read_text())
            self.assertEqual(report['trials'][0]['status'], 'ERROR')


if __name__ == '__main__':
    unittest.main()
