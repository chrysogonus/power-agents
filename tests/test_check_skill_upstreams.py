#!/usr/bin/env python3
"""Offline tests for parsing pinned upstream skill revisions."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "check_skill_upstreams", ROOT / "scripts" / "check-skill-upstreams.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

SHA = "0123456789abcdef0123456789abcdef01234567"


class ParsePinsTests(unittest.TestCase):
    def test_deduplicates_and_keeps_dotted_paths(self) -> None:
        text = (
            f"[a](https://github.com/org/repo.name/tree/{SHA}/skills/.curated/x) "
            f"`{SHA}`\n"
            f"[again](https://github.com/org/repo.name/tree/{SHA}/skills/.curated/x)\n"
            f"https://github.com/org/other/tree/{SHA}/skills/y\n"
            "https://github.com/org/repo/tree/main/skills/unpinned\n"
        )
        self.assertEqual(
            MODULE.parse_pins(text),
            [("org/repo.name", SHA, "skills/.curated/x"), ("org/other", SHA, "skills/y")],
        )


if __name__ == "__main__":
    unittest.main()
