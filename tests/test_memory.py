#!/usr/bin/env python3
"""Tests for the remember skill's memory store script."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "skills" / "remember" / "scripts" / "memory.py"


class MemoryStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary_directory.name)
        self.home = self.directory / "home"
        self.home.mkdir()
        self.store = self.home / ".agents" / "memory"
        self.project = self.directory / "shop"
        self.project.mkdir()
        subprocess.run(["git", "init", "-q", str(self.project)], check=True)
        self.env = {
            key: value for key, value in os.environ.items()
            if key not in {"CLAUDE_CODE_SESSION_ID", "CODEX_THREAD_ID"}
            and not key.startswith("GIT_")
        }
        self.env.update({"HOME": str(self.home),
                         "GIT_CONFIG_GLOBAL": str(self.directory / "gitconfig"),
                         "GIT_CONFIG_NOSYSTEM": "1"})

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def memory(self, *args: str, body: str = "", env: dict | None = None,
               cwd: Path | None = None) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            input=body, capture_output=True, text=True,
            cwd=cwd or self.project, env={**self.env, **(env or {})},
            timeout=30, check=False,
        )

    def save(self, name: str = "uses-pnpm", kind: str = "user",
             description: str = "Uses pnpm, never npm, for JavaScript.",
             body: str = "The user installs packages with pnpm.\n",
             *extra: str, env: dict | None = None) -> subprocess.CompletedProcess:
        return self.memory("save", name, "--type", kind, "--description",
                           description, *extra, body=body, env=env)

    def git_log(self) -> list[str]:
        return subprocess.run(
            ["git", "-C", str(self.store), "log", "--format=%s"],
            capture_output=True, text=True, check=True, env=self.env,
        ).stdout.splitlines()

    def index(self) -> str:
        return (self.store / "MEMORY.md").read_text(encoding="utf-8")

    def test_save_creates_a_committed_memory_and_index(self) -> None:
        result = self.save(env={"CLAUDE_CODE_SESSION_ID": "abc123"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(self.store / "uses-pnpm.md"), result.stdout)

        text = (self.store / "uses-pnpm.md").read_text(encoding="utf-8")
        frontmatter, body = text.split("---\n")[1:3]
        self.assertIn("name: uses-pnpm\n", frontmatter)
        self.assertIn('description: "Uses pnpm, never npm, for JavaScript."\n',
                      frontmatter)
        self.assertIn("metadata:\n  type: user\n", frontmatter)
        self.assertIn("  source-project: shop\n", frontmatter)
        self.assertIn("  source-session: claude abc123\n", frontmatter)
        self.assertRegex(frontmatter, r"  created: \d{4}-\d{2}-\d{2}\n")
        self.assertEqual(body, "\nThe user installs packages with pnpm.\n")

        self.assertIn("## User\n\n- [uses-pnpm](uses-pnpm.md) — "
                      "Uses pnpm, never npm, for JavaScript.\n", self.index())
        self.assertEqual(self.git_log(), ["remember: uses-pnpm"])
        remotes = subprocess.run(["git", "-C", str(self.store), "remote"],
                                 capture_output=True, text=True, env=self.env)
        self.assertEqual(remotes.stdout, "")

    def test_codex_session_is_recorded(self) -> None:
        self.assertEqual(self.save(env={"CODEX_THREAD_ID": "t-9"}).returncode, 0)
        text = (self.store / "uses-pnpm.md").read_text(encoding="utf-8")
        self.assertIn("  source-session: codex t-9\n", text)

    def test_existing_memories_change_only_with_replace(self) -> None:
        self.assertEqual(self.save().returncode, 0)
        result = self.save(description="Uses yarn.")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already exists", result.stderr)
        self.assertIn("pnpm", self.index())

        result = self.save("uses-pnpm", "user", "Uses yarn.", "Yarn.\n",
                           "--replace")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("— Uses yarn.", self.index())
        self.assertNotIn("pnpm, never", self.index())
        self.assertEqual(self.git_log(),
                         ["update: uses-pnpm", "remember: uses-pnpm"])

    def test_invalid_entries_write_nothing(self) -> None:
        cases = [
            ("Bad Name", "user", "Fine.", "Body.\n"),
            ("ok-name", "secret", "Fine.", "Body.\n"),
            ("ok-name", "user", "", "Body.\n"),
            ("ok-name", "user", "Two\nlines.", "Body.\n"),
            ("ok-name", "user", "Fine.", "   \n"),
            ("memory", "user", "Fine.", "Body.\n"),
        ]
        for name, kind, description, body in cases:
            with self.subTest(name=name, kind=kind, description=description):
                result = self.save(name, kind, description, body)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr.startswith("ERROR:"), result.stderr)
        self.assertFalse(self.store.exists())

    def test_descriptions_with_yaml_characters_round_trip(self) -> None:
        description = 'Prefers "tabs": never spaces # really'
        self.assertEqual(self.save("tabs", "feedback", description).returncode, 0)
        self.assertIn(f"- [tabs](tabs.md) — {description}\n", self.index())
        text = (self.store / "tabs.md").read_text(encoding="utf-8")
        self.assertIn(f"description: {json.dumps(description)}\n", text)

    def test_forget_removes_the_memory_and_its_index_line(self) -> None:
        self.assertEqual(self.save().returncode, 0)
        self.assertEqual(self.save("api-docs", "reference",
                                   "Internal API docs live at docs.example.com."
                                   ).returncode, 0)
        result = self.memory("forget", "uses-pnpm")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.store / "uses-pnpm.md").exists())
        self.assertNotIn("uses-pnpm", self.index())
        self.assertIn("## Reference\n\n- [api-docs](api-docs.md)", self.index())
        self.assertEqual(self.git_log()[0], "forget: uses-pnpm")

        result = self.memory("forget", "uses-pnpm")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No memory named uses-pnpm", result.stderr)

    def test_index_groups_by_type_and_reports_unreadable_files(self) -> None:
        for name, kind in [("zeta", "project"), ("alpha", "project"),
                           ("me", "user")]:
            self.assertEqual(self.save(name, kind, f"About {name}.").returncode, 0)
        (self.store / "hand-written.md").write_text("no frontmatter\n",
                                                   encoding="utf-8")
        result = self.memory("index")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("hand-written.md", result.stderr)
        index = self.index()
        self.assertLess(index.index("## User"), index.index("## Project"))
        self.assertLess(index.index("[alpha]"), index.index("[zeta]"))
        self.assertNotIn("hand-written", index)

    def test_project_falls_back_to_the_directory_name(self) -> None:
        plain = self.directory / "notes"
        plain.mkdir()
        result = self.memory("save", "x", "--type", "user", "--description",
                             "Fact.", body="Body.\n", cwd=plain)
        self.assertEqual(result.returncode, 0, result.stderr)
        text = (self.store / "x.md").read_text(encoding="utf-8")
        self.assertIn("  source-project: notes\n", text)
        self.assertIn("  source-session: unknown\n", text)


if __name__ == "__main__":
    unittest.main()
