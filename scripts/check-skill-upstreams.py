#!/usr/bin/env python3
"""Report imported skills whose upstream path changed after the pinned revision.

Pins are the GitHub tree URLs recorded in THIRD_PARTY_NOTICES.md. Requires an
authenticated `gh` CLI. Exit status: 0 all current, 1 some behind, 2 errors.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NOTICES = ROOT / "THIRD_PARTY_NOTICES.md"
PIN_PATTERN = re.compile(
    r"https://github\.com/([\w.-]+/[\w.-]+)/tree/([0-9a-f]{40})/([^)\s]+)"
)


def parse_pins(text: str) -> list[tuple[str, str, str]]:
    """Return unique (repository, revision, path) pins in order of appearance."""
    return list(dict.fromkeys(PIN_PATTERN.findall(text)))


def gh_api(endpoint: str) -> object:
    result = subprocess.run(
        ["gh", "api", endpoint], capture_output=True, text=True, check=True
    )
    return json.loads(result.stdout)


def check(repository: str, revision: str, path: str) -> str:
    commits = gh_api(f"repos/{repository}/commits?path={path}&per_page=1")
    if not commits:
        raise RuntimeError("upstream path no longer exists")
    latest = commits[0]
    status = gh_api(f"repos/{repository}/compare/{revision}...{latest['sha']}")["status"]
    if status in ("identical", "behind"):
        return "current"
    date = latest["commit"]["committer"]["date"][:10]
    return f"behind (last upstream change {date}, {latest['sha'][:7]})"


def main() -> int:
    pins = parse_pins(NOTICES.read_text(encoding="utf-8"))
    if not pins:
        print(f"ERROR: no pinned GitHub tree URLs found in {NOTICES}", file=sys.stderr)
        return 2
    exit_code = 0
    for repository, revision, path in pins:
        label = f"{repository}/{path}"
        try:
            state = check(repository, revision, path)
        except (OSError, subprocess.CalledProcessError, RuntimeError, KeyError, ValueError) as error:
            detail = getattr(error, "stderr", "") or error
            print(f"{label}: ERROR {str(detail).strip()}", file=sys.stderr)
            exit_code = 2
            continue
        print(f"{label}: {state}")
        if state != "current" and exit_code == 0:
            exit_code = 1
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
