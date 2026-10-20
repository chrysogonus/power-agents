#!/usr/bin/env python3
"""Focused tests for the verify-gate hook reconciler."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RECONCILER = ROOT / "scripts" / "reconcile-hooks.py"
FRAGMENTS = {
    agent: ROOT / "settings" / agent / "hooks.json"
    for agent in ("claude", "codex")
}
SCRIPT = "/home/user/.agents/hooks/verify-gate.py"

FOREIGN = {
    "description": "local hooks",
    "model": "opus",
    "hooks": {
        "PreToolUse": [
            {"matcher": "Bash",
             "hooks": [{"type": "command", "command": "audit.sh", "timeout": 5}]},
        ],
        "Stop": [
            {"hooks": [{"type": "command", "command": "notify-send done"}]},
        ],
    },
}


def managed(agent: str) -> dict:
    def handler(mode: str, timeout: int) -> dict:
        return {
            "type": "command",
            "command": f'python3 "{SCRIPT}" {mode} --agent {agent}',
            "timeout": timeout,
        }

    return {
        "UserPromptSubmit": [{"hooks": [handler("mark", 30)]}],
        "Stop": [{"hooks": [handler("stop", 600)]}],
    }


class ReconcileHooksTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary_directory.name)
        self.input_path = self.directory / "input.json"
        self.output_path = self.directory / "output.json"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def run_reconciler(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(RECONCILER), *args],
            check=False,
            capture_output=True,
            text=True,
        )

    def reconcile(
        self, content: str | dict, agent: str = "claude"
    ) -> subprocess.CompletedProcess[str]:
        if not isinstance(content, str):
            content = json.dumps(content)
        self.input_path.write_text(content, encoding="utf-8")
        return self.run_reconciler(
            "reconcile", str(FRAGMENTS[agent]), str(self.input_path),
            str(self.output_path), "--script", SCRIPT,
        )

    def output(self) -> dict:
        return json.loads(self.output_path.read_text(encoding="utf-8"))

    def test_fragments_are_valid(self) -> None:
        for agent, fragment in FRAGMENTS.items():
            with self.subTest(agent=agent):
                result = self.run_reconciler("validate-managed", str(fragment))
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_empty_input_receives_only_managed_hooks(self) -> None:
        for agent in FRAGMENTS:
            with self.subTest(agent=agent):
                self.input_path.write_text("", encoding="utf-8")
                result = self.run_reconciler(
                    "reconcile", str(FRAGMENTS[agent]), "/dev/null",
                    str(self.output_path), "--script", SCRIPT,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.output(), {"hooks": managed(agent)})

    def test_foreign_hooks_are_preserved(self) -> None:
        result = self.reconcile(FOREIGN, "codex")
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = json.loads(json.dumps(FOREIGN))
        expected["hooks"]["Stop"].extend(managed("codex")["Stop"])
        expected["hooks"]["UserPromptSubmit"] = managed("codex")["UserPromptSubmit"]
        self.assertEqual(self.output(), expected)
        self.assertEqual(
            list(self.output()["hooks"]),
            ["PreToolUse", "Stop", "UserPromptSubmit"],
        )

    def test_reconciliation_is_idempotent(self) -> None:
        self.assertEqual(self.reconcile(FOREIGN).returncode, 0)
        first = self.output_path.read_text(encoding="utf-8")

        self.assertEqual(self.reconcile(first).returncode, 0)
        self.assertEqual(self.output_path.read_text(encoding="utf-8"), first)

    def test_stale_managed_entries_are_replaced(self) -> None:
        stale = json.loads(json.dumps(FOREIGN))
        stale["hooks"]["Stop"].insert(0, {"hooks": [
            {"type": "command", "command": f'python3 "{SCRIPT}" old-mode'},
            {"type": "command", "command": "keep-me.sh"},
        ]})
        stale["hooks"]["SessionStart"] = [
            {"hooks": [{"type": "command", "command": f"{SCRIPT} retired"}]}
        ]
        result = self.reconcile(stale)
        self.assertEqual(result.returncode, 0, result.stderr)

        hooks = self.output()["hooks"]
        self.assertNotIn("SessionStart", hooks)
        self.assertEqual(
            hooks["Stop"][0], {"hooks": [{"type": "command", "command": "keep-me.sh"}]}
        )
        self.assertEqual(hooks["Stop"][-1], managed("claude")["Stop"][0])
        self.assertEqual(
            sum(SCRIPT in json.dumps(group) for group in hooks["Stop"]), 1
        )

    def test_remove_restores_pre_install_structure(self) -> None:
        for name, original in {"foreign": FOREIGN, "none": {"model": "opus"}}.items():
            with self.subTest(name=name):
                self.assertEqual(self.reconcile(original).returncode, 0)
                installed = self.directory / "installed.json"
                installed.write_text(
                    self.output_path.read_text(encoding="utf-8"), encoding="utf-8"
                )
                result = self.run_reconciler(
                    "remove", str(installed), str(self.output_path),
                    "--script", SCRIPT,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.output(), original)

    def test_legacy_entries_are_rejected(self) -> None:
        legacy = json.loads(json.dumps(FOREIGN))
        legacy["hooks"]["Stop"].append({"hooks": [{
            "type": "command",
            "command": "python3 ~/.agent-hooks/verify_gate.py stop --agent claude",
        }]})
        self.input_path.write_text(json.dumps(legacy), encoding="utf-8")

        for command in ("validate-config", "reconcile"):
            with self.subTest(command=command):
                self.output_path.write_text("unchanged\n", encoding="utf-8")
                if command == "reconcile":
                    result = self.reconcile(legacy)
                else:
                    result = self.run_reconciler(command, str(self.input_path))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("legacy standalone verify gate hook", result.stderr)
                self.assertIn("~/.agent-hooks/verify_gate.py", result.stderr)
                self.assertIn("uninstall.sh", result.stderr)
                self.assertEqual(
                    self.output_path.read_text(encoding="utf-8"), "unchanged\n"
                )

    def test_invalid_input_does_not_change_output(self) -> None:
        rejected_inputs = {
            "invalid JSON": '{"hooks":',
            "not an object": "[]",
            "hooks not an object": '{"hooks": []}',
            "event not an array": '{"hooks": {"Stop": "notify"}}',
            "group not an object": '{"hooks": {"Stop": ["notify"]}}',
            "handlers not an array": '{"hooks": {"Stop": [{"hooks": {}}]}}',
            "non-finite number": '{"timeout": NaN}',
        }
        for name, content in rejected_inputs.items():
            with self.subTest(name=name):
                self.output_path.write_text("unchanged\n", encoding="utf-8")
                result = self.reconcile(content)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("ERROR:", result.stderr)
                self.assertEqual(
                    self.output_path.read_text(encoding="utf-8"), "unchanged\n"
                )

    def test_unsafe_script_paths_are_rejected(self) -> None:
        for script in ("relative/verify-gate.py", '/tmp/a"b/verify-gate.py',
                       "/tmp/$HOME/verify-gate.py"):
            with self.subTest(script=script):
                result = self.run_reconciler(
                    "reconcile", str(FRAGMENTS["claude"]), "/dev/null",
                    str(self.output_path), "--script", script,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.output_path.exists())

    def test_rejects_invalid_managed_fragments(self) -> None:
        rejected = {
            "extra key": {"hooks": managed("claude"), "model": "x"},
            "no placeholder": {"hooks": managed("claude")},
            "bad timeout": {"hooks": {"Stop": [{"hooks": [{
                "type": "command", "command": "@VERIFY_GATE@", "timeout": 0}]}]}},
            "matcher": {"hooks": {"Stop": [{"matcher": "*", "hooks": [{
                "type": "command", "command": "@VERIFY_GATE@"}]}]}},
        }
        fragment = self.directory / "fragment.json"
        for name, content in rejected.items():
            with self.subTest(name=name):
                fragment.write_text(json.dumps(content), encoding="utf-8")
                result = self.run_reconciler("validate-managed", str(fragment))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("ERROR: managed", result.stderr)


if __name__ == "__main__":
    unittest.main()
