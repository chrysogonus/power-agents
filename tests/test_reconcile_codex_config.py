#!/usr/bin/env python3
"""Focused tests for the Codex TOML reconciler."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

import tomlkit


ROOT = Path(__file__).resolve().parents[1]
RECONCILER = ROOT / "scripts" / "reconcile-codex-config.py"
MANAGED_SETTINGS = ROOT / "settings" / "codex" / "tui.toml"


class ReconcileCodexConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary_directory.name)
        self.input_path = self.directory / "input.toml"
        self.output_path = self.directory / "output.toml"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def reconcile(self, content: str) -> subprocess.CompletedProcess[str]:
        self.input_path.write_text(content, encoding="utf-8")
        return subprocess.run(
            [
                "python3",
                str(RECONCILER),
                "reconcile",
                str(MANAGED_SETTINGS),
                str(self.input_path),
                str(self.output_path),
            ],
            check=False,
            capture_output=True,
            text=True,
        )

    def assert_reconciled(self, result: subprocess.CompletedProcess[str]) -> dict:
        self.assertEqual(result.returncode, 0, result.stderr)
        config = tomlkit.parse(
            self.output_path.read_text(encoding="utf-8")
        ).unwrap()
        managed = tomlkit.parse(
            MANAGED_SETTINGS.read_text(encoding="utf-8")
        ).unwrap()
        self.assertEqual(
            config["tui"]["status_line"], managed["tui"]["status_line"]
        )
        self.assertEqual(
            config["tui"]["status_line_use_colors"],
            managed["tui"]["status_line_use_colors"],
        )
        return config

    def test_reconciles_supported_tui_representations(self) -> None:
        cases = {
            "quoted": ('["tui"]\ntheme = "dark"\n', '["tui"]'),
            "dotted": (
                'tui.status_line = ["old"]\ntui.theme = "dark"\n',
                "tui.status_line",
            ),
            "inline": (
                'tui = { status_line = ["old"], theme = "dark" }\n',
                "tui = {",
            ),
        }

        for name, (content, preserved_syntax) in cases.items():
            with self.subTest(name=name):
                config = self.assert_reconciled(self.reconcile(content))
                self.assertEqual(config["tui"]["theme"], "dark")
                self.assertIn(
                    preserved_syntax,
                    self.output_path.read_text(encoding="utf-8"),
                )

    def test_multiline_strings_do_not_create_false_tables(self) -> None:
        cases = {
            "basic": (
                'message = """\nThis is not a table:\n[tui]\n'
                'status_line = ["decoy"]\n"""\n'
            ),
            "literal": (
                "message = '''\nThis is not a table:\n[tui]\n"
                "status_line = [\"decoy\"]\n'''\n"
            ),
        }

        for name, content in cases.items():
            with self.subTest(name=name):
                config = self.assert_reconciled(self.reconcile(content))
                self.assertIn(
                    '[tui]\nstatus_line = ["decoy"]', config["message"]
                )

    def test_multiline_decoy_does_not_hide_real_table(self) -> None:
        content = (
            'message = """\n[tui]\nstatus_line_use_colors = false\n"""\n\n'
            '[tui]\ntheme = "dark"\n'
        )

        config = self.assert_reconciled(self.reconcile(content))

        self.assertIn(
            "[tui]\nstatus_line_use_colors = false", config["message"]
        )
        self.assertEqual(config["tui"]["theme"], "dark")

    def test_rejected_input_does_not_change_output(self) -> None:
        rejected_inputs = {
            "invalid": 'model = "unterminated\n',
            "incompatible": 'tui = "not-a-table"\n',
        }

        for name, content in rejected_inputs.items():
            with self.subTest(name=name):
                self.output_path.write_text("unchanged\n", encoding="utf-8")
                result = self.reconcile(content)

                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(
                    self.output_path.read_text(encoding="utf-8"), "unchanged\n"
                )

    def test_reconciliation_is_idempotent(self) -> None:
        content = (
            'model = "local"\n\n["tui"]\ntheme = "dark"\n'
            'status_line = ["old"]\n'
        )
        self.assert_reconciled(self.reconcile(content))
        first_result = self.output_path.read_text(encoding="utf-8")

        self.assert_reconciled(self.reconcile(first_result))

        self.assertEqual(
            self.output_path.read_text(encoding="utf-8"), first_result
        )


if __name__ == "__main__":
    unittest.main()
