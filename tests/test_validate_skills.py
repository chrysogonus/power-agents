#!/usr/bin/env python3
"""Focused tests for the shared skill validator."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / "scripts" / "validate-skills.py"


class ValidateSkillsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary_directory.name)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_skill(
        self,
        root: Path,
        directory_name: str = "example-skill",
        *,
        frontmatter: str | None = None,
        body: str = "# Example Skill\n\nFollow these instructions.\n",
    ) -> Path:
        skill_dir = root / directory_name
        skill_dir.mkdir(parents=True)
        if frontmatter is None:
            frontmatter = (
                "---\n"
                f'name: "{directory_name}"\n'
                'description: "Use for a representative task."\n'
                "---\n"
            )
        (skill_dir / "SKILL.md").write_text(
            frontmatter + body, encoding="utf-8"
        )
        return skill_dir

    def validate(self, root: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(VALIDATOR), str(root)],
            check=False,
            capture_output=True,
            text=True,
        )

    def test_repository_skills_are_valid(self) -> None:
        result = self.validate(ROOT / "skills")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_accepts_quoted_required_fields_and_valid_evals(self) -> None:
        root = self.directory / "valid"
        skill_dir = self.write_skill(root)
        evals_dir = skill_dir / "evals"
        evals_dir.mkdir()
        (evals_dir / "evals.json").write_text(
            json.dumps(
                {
                    "skill_name": "example-skill",
                    "evals": [
                        {
                            "id": 1,
                            "prompt": "Use the representative skill.",
                            "expected_output": "A representative result.",
                            "assertions": ["The output is non-empty."],
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )

        result = self.validate(root)

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_malformed_skill_metadata(self) -> None:
        cases = {
            "invalid directory name": (
                "Invalid_Name",
                None,
                "# Body\n",
                "directory name must match",
            ),
            "missing opening frontmatter": (
                "example-skill",
                "name: example-skill\ndescription: Example.\n---\n",
                "# Body\n",
                "must start with YAML frontmatter",
            ),
            "unclosed frontmatter": (
                "example-skill",
                "---\nname: example-skill\ndescription: Example.\n",
                "",
                "YAML frontmatter is not closed",
            ),
            "missing name": (
                "example-skill",
                "---\ndescription: Example.\n---\n",
                "# Body\n",
                "missing required name",
            ),
            "missing description": (
                "example-skill",
                "---\nname: example-skill\n---\n",
                "# Body\n",
                "missing required description",
            ),
            "malformed yaml": (
                "example-skill",
                "---\nname: example-skill\ndescription: [unclosed\n---\n",
                "# Body\n",
                "invalid YAML frontmatter",
            ),
            "non-string description": (
                "example-skill",
                "---\nname: example-skill\ndescription: [one, two]\n---\n",
                "# Body\n",
                "description must be a non-empty string",
            ),
            "mismatched name": (
                "example-skill",
                "---\nname: other-skill\ndescription: Example.\n---\n",
                "# Body\n",
                "does not match directory",
            ),
            "empty body": (
                "example-skill",
                "---\nname: example-skill\ndescription: Example.\n---\n",
                "\n",
                "markdown body must not be empty",
            ),
        }

        for name, (directory_name, frontmatter, body, expected_error) in cases.items():
            with self.subTest(name=name):
                root = self.directory / name.replace(" ", "-")
                self.write_skill(
                    root,
                    directory_name,
                    frontmatter=frontmatter,
                    body=body,
                )

                result = self.validate(root)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(expected_error, result.stderr)

    def test_rejects_missing_skill_entrypoint(self) -> None:
        root = self.directory / "missing-entrypoint"
        (root / "example-skill").mkdir(parents=True)

        result = self.validate(root)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing skill entrypoint", result.stderr)

    def test_rejects_invalid_eval_contracts(self) -> None:
        root = self.directory / "invalid-evals"
        skill_dir = self.write_skill(root)
        evals_dir = skill_dir / "evals"
        evals_dir.mkdir()
        (evals_dir / "evals.json").write_text(
            json.dumps(
                {
                    "skill_name": "wrong-skill",
                    "evals": [
                        {
                            "id": 1,
                            "prompt": "",
                            "expected_output": "A result.",
                            "files": ["evals/files/missing.txt"],
                        },
                        {
                            "id": 1,
                            "prompt": "Another prompt.",
                            "expected_output": "",
                        },
                    ],
                }
            ),
            encoding="utf-8",
        )

        result = self.validate(root)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("skill_name must be 'example-skill'", result.stderr)
        self.assertIn("prompt must be a non-empty string", result.stderr)
        self.assertIn("duplicate id 1", result.stderr)
        self.assertIn("expected_output must be a non-empty string", result.stderr)
        self.assertIn("file does not exist", result.stderr)


if __name__ == "__main__":
    unittest.main()
