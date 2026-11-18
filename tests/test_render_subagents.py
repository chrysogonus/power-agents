#!/usr/bin/env python3
"""Tests for rendering the shared subagent definitions for both agents."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import tomlkit
import yaml


ROOT = Path(__file__).resolve().parents[1]
RENDER = ROOT / "scripts" / "render-subagents.py"
ROLES = ("docs-researcher", "reviewer", "test-runner")


def frontmatter(text: str) -> tuple[dict, str]:
    _, header, body = text.split("---\n", 2)
    return yaml.safe_load(header), body


class RenderSubagentsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary_directory.name)
        self.output = self.directory / "out"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def render(self, models: object | None = None,
               source: Path = ROOT / "subagents") -> subprocess.CompletedProcess:
        args = [sys.executable, str(RENDER), str(source), str(self.output)]
        if models is not None:
            path = self.directory / "agent-models.json"
            path.write_text(models if isinstance(models, str) else json.dumps(models),
                            encoding="utf-8")
            args += ["--models", str(path)]
        return subprocess.run(args, capture_output=True, text=True, check=False)

    def claude(self, role: str) -> tuple[dict, str]:
        return frontmatter((self.output / "claude" / f"{role}.md").read_text(
            encoding="utf-8"))

    def codex(self, role: str) -> dict:
        return tomlkit.parse((self.output / "codex" / f"{role}.toml").read_text(
            encoding="utf-8")).unwrap()

    def test_every_role_renders_for_both_agents(self) -> None:
        result = self.render()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(p.stem for p in (self.output / "claude").iterdir()),
                         list(ROLES))
        self.assertEqual(sorted(p.stem for p in (self.output / "codex").iterdir()),
                         list(ROLES))
        for role in ROLES:
            with self.subTest(role=role):
                header, body = self.claude(role)
                codex = self.codex(role)
                self.assertEqual(header["name"], role)
                self.assertEqual(codex["name"], role)
                self.assertEqual(header["description"], codex["description"])
                self.assertEqual(body.strip(), codex["developer_instructions"].strip())
                self.assertEqual(set(codex), {"name", "description",
                                              "developer_instructions",
                                              "model_reasoning_effort"})

    def test_defaults_match_each_role(self) -> None:
        self.assertEqual(self.render().returncode, 0)
        expected = {"reviewer": ("opus", "high"), "docs-researcher": ("sonnet", "medium"),
                    "test-runner": ("haiku", "low")}
        for role, (model, effort) in expected.items():
            self.assertEqual(self.claude(role)[0]["model"], model)
            self.assertEqual(self.codex(role)["model_reasoning_effort"], effort)
        self.assertEqual(self.claude("reviewer")[0]["tools"], "Read, Grep, Glob")
        self.assertNotIn("Bash", self.claude("docs-researcher")[0]["tools"])
        self.assertIn("Bash", self.claude("test-runner")[0]["tools"])

    def test_model_overlay_overrides_each_agent(self) -> None:
        result = self.render({"claude": {"reviewer": "claude-opus-5-5"},
                              "codex": {"reviewer": "gpt-5.5", "test-runner": "gpt-mini"}})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.claude("reviewer")[0]["model"], "claude-opus-5-5")
        self.assertEqual(self.claude("test-runner")[0]["model"], "haiku")
        self.assertEqual(self.codex("reviewer")["model"], "gpt-5.5")
        self.assertEqual(self.codex("test-runner")["model"], "gpt-mini")
        self.assertNotIn("model", self.codex("docs-researcher"))

    def test_invalid_overlays_render_nothing(self) -> None:
        cases = {
            "not json": "{",
            "unknown agent": {"gemini": {"reviewer": "x"}},
            "unknown role": {"claude": {"planner": "opus"}},
            "unsafe model": {"codex": {"reviewer": 'x"\ninjected = true'}},
            "not a string": {"claude": {"reviewer": 5}},
        }
        for label, models in cases.items():
            with self.subTest(label):
                result = self.render(models)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr.startswith("ERROR:"), result.stderr)
                self.assertFalse(self.output.exists())

    def test_invalid_sources_are_rejected(self) -> None:
        source = self.directory / "subagents"
        source.mkdir()
        good = (ROOT / "subagents" / "reviewer.md").read_text(encoding="utf-8")
        cases = {
            "name mismatch": good.replace("name: reviewer", "name: other"),
            "missing key": good.replace("codex-reasoning-effort: high\n", ""),
            "bad effort": good.replace("codex-reasoning-effort: high",
                                       "codex-reasoning-effort: max"),
            "toml breaking body": good + "\n'''\n",
        }
        for label, text in cases.items():
            with self.subTest(label):
                (source / "reviewer.md").write_text(text, encoding="utf-8")
                result = self.render(source=source)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr.startswith("ERROR:"), result.stderr)


if __name__ == "__main__":
    unittest.main()
