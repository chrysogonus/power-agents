#!/usr/bin/env python3
"""End-to-end runner tests against a free, isolated fake Claude runtime."""

from __future__ import annotations

import json
import os
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts" / "run-evals.py"
FAKE = ROOT / "tests" / "fixtures" / "fake-claude.py"


class RunEvalsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.skills = self.directory / "skills"
        self.secret = "test-only-environment-credential-123456789"
        for name in ("example-skill", "other-skill"):
            skill = self.skills / name
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text(
                f"---\nname: {name}\ndescription: Use for an example.\n---\n\n# Example\n"
            )
            (skill / "evals").mkdir()
            (skill / "evals" / "evals.json").write_text(json.dumps({
                "skill_name": name,
                "evals": [{"id": 1, "prompt": "A realistic task.",
                           "expected_output": "Expected behavior.",
                           "assertions": ["The task is handled.", "Constraints are preserved."]}]
            }))
        self.invocation = 0

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def prepare_run(self, mode="success", *, credentials=True, extra=(), missing=False):
        self.invocation += 1
        runtime = self.directory / f"claude-{self.invocation}"
        counter = self.directory / f"count-{self.invocation}"
        if not missing:
            runtime.write_text(
                "#!/usr/bin/env python3\nimport runpy\nfrom pathlib import Path\n"
                f"runpy.run_path({str(FAKE)!r})['main']({mode!r}, Path({str(counter)!r}))\n"
            )
            runtime.chmod(0o700)
        output = self.directory / f"results-{self.invocation}"
        env = dict(os.environ)
        env.pop("ANTHROPIC_API_KEY", None)
        if credentials:
            env["ANTHROPIC_API_KEY"] = self.secret
        env["EVAL_UNMANAGED_SECRET"] = "must-not-inherit"
        command = ["python3", str(RUNNER), "--runtime", str(runtime),
                   "--skills-root", str(self.skills), "--output-dir", str(output),
                   "--repeats", "5", *extra]
        return command, env, output, counter

    def run_eval(self, mode="success", **options):
        command, env, output, _ = self.prepare_run(mode, **options)
        result = subprocess.run(command, env=env, capture_output=True, text=True)
        return result, output

    def document(self, output):
        return json.loads((output / "results.json").read_text())

    def test_runs_all_cases_repeatedly_in_isolation_and_writes_summary(self):
        result, output = self.run_eval()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        report = self.document(output)
        self.assertEqual(len(report["cases"]), 2)
        for case in report["cases"]:
            self.assertEqual(case["status"], "PASS")
            self.assertEqual(case["pass_rate"], 1.0)
            self.assertEqual(len(case["trials"]), 5)
            for trial in case["trials"]:
                self.assertEqual(trial["loaded_skills"], ["example-skill"])
                self.assertEqual(len(trial["assertions"]), 2)
                self.assertEqual(trial["model"], "fake-model")
        summary = (output / "summary.md").read_text()
        self.assertIn("example-skill", summary)
        self.assertIn("other-skill", summary)
        self.assertIn("100.0%", summary)

    def test_skill_filter_and_threshold_boundary(self):
        result, output = self.run_eval("one-failure", extra=("--skill", "example-skill"))
        self.assertEqual(result.returncode, 0, result.stderr)
        case = self.document(output)["cases"][0]
        self.assertEqual(case["pass_rate"], 0.8)
        self.assertEqual(case["status"], "PASS")
        self.assertEqual(len(self.document(output)["cases"]), 1)
        result, output = self.run_eval("one-failure", extra=("--threshold", "0.81"))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.document(output)["status"], "FAIL")

    def test_missing_credentials_and_runtime_are_skip_never_pass(self):
        for options in ({"credentials": False}, {"missing": True}):
            with self.subTest(options=options):
                result, output = self.run_eval(**options)
                self.assertEqual(result.returncode, 2, result.stderr)
                report = self.document(output)
                self.assertEqual(report["status"], "SKIP")
                self.assertTrue(all(case["status"] == "SKIP" for case in report["cases"]))
                self.assertNotIn("PASS", result.stdout)

    def test_protocol_auth_and_judge_failures_cannot_pass(self):
        modes = ("malformed", "truncated", "nonzero", "error-result", "denied-load",
                 "unconfirmed-load", "permission-denial", "undiscovered", "bad-judge",
                 "invented-evidence", "duplicate-grade", "invalid-block", "spoofed-roles")
        for mode in modes:
            with self.subTest(mode=mode):
                result, output = self.run_eval(mode, extra=("--skill", "example-skill"))
                self.assertEqual(result.returncode, 2, result.stderr)
                report = self.document(output)
                self.assertEqual(report["status"], "ERROR")
                self.assertEqual(report["cases"][0]["pass_rate"], 0.0)

    def test_no_load_is_a_behavior_failure_even_when_judge_likes_the_text(self):
        result, output = self.run_eval("no-load")
        self.assertEqual(result.returncode, 1, result.stderr)
        trial = self.document(output)["cases"][0]["trials"][0]
        self.assertEqual(trial["loaded_skills"], [])
        self.assertEqual(trial["status"], "FAIL")
        self.assertTrue(all(item["passed"] for item in trial["assertions"]))

    def test_timeout_is_error(self):
        result, output = self.run_eval("timeout", extra=("--timeout", "0.1"))
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(self.document(output)["status"], "ERROR")

    def test_credentials_are_redacted_from_every_artifact_and_console(self):
        result, output = self.run_eval("redact")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(self.secret, result.stdout + result.stderr)
        for file in output.rglob("*"):
            if file.is_file():
                self.assertNotIn(self.secret, file.read_text(), str(file))
        self.assertIn("[REDACTED]", (output / "results.json").read_text())

    def test_invalid_options_fixtures_and_selection_are_errors(self):
        for extra in (("--repeats", "1"), ("--threshold", "nan"),
                      ("--threshold", "1.1"), ("--skill", "missing-skill")):
            with self.subTest(extra=extra):
                result, _ = self.run_eval(extra=extra)
                self.assertEqual(result.returncode, 2, result.stderr)
        fixture = self.skills / "example-skill" / "evals" / "evals.json"
        document = json.loads(fixture.read_text())
        document["evals"][0]["files"] = ["../../outside.txt"]
        fixture.write_text(json.dumps(document))
        result, _ = self.run_eval()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("escapes", result.stderr)

    def test_absolute_fixture_paths_are_rejected_even_inside_the_skill(self):
        fixture = self.skills / "example-skill" / "evals" / "evals.json"
        document = json.loads(fixture.read_text())
        document["evals"][0]["files"] = [str(self.skills / "example-skill" / "SKILL.md")]
        fixture.write_text(json.dumps(document))
        result, _ = self.run_eval()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("relative", result.stderr)

    def test_file_fixtures_fail_explicitly_in_this_prompt_only_runner(self):
        fixture = self.skills / "example-skill" / "evals" / "evals.json"
        document = json.loads(fixture.read_text())
        document["evals"][0]["files"] = ["SKILL.md"]
        fixture.write_text(json.dumps(document))
        result, _ = self.run_eval()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("prompt-only", result.stderr)

    def test_cancellation_terminates_the_runtime_process(self):
        for interruption in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(interruption=interruption):
                command, env, _, counter = self.prepare_run("cancel")
                process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE,
                                           stderr=subprocess.PIPE, text=True)
                runtime_pid = None
                try:
                    deadline = time.monotonic() + 5
                    while not counter.exists() and time.monotonic() < deadline:
                        time.sleep(0.01)
                    self.assertTrue(counter.exists(), "Sleeping runtime did not start.")
                    runtime_pid = int(counter.read_text())
                    process.send_signal(interruption)
                    process.communicate(timeout=5)
                    self.assertNotEqual(process.returncode, 0)
                    with self.assertRaises(ProcessLookupError):
                        os.kill(runtime_pid, 0)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.communicate()
                    if runtime_pid:
                        try:
                            os.kill(runtime_pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass


if __name__ == "__main__":
    unittest.main()
