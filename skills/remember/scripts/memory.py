#!/usr/bin/env python3
"""Save, replace, or forget entries in the shared memory store.

The store is ~/.agents/memory, a local git repository with one Markdown file
per fact and a generated MEMORY.md index. Python standard library only.

  memory.py save NAME --type TYPE --description TEXT [--replace] < body
  memory.py forget NAME
  memory.py index
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
from pathlib import Path


TYPES = ("user", "feedback", "project", "reference")
NAME = re.compile(r"[a-z0-9]+(-[a-z0-9]+)*")
INDEX = "MEMORY.md"
MAX_DESCRIPTION = 200
FALLBACK_IDENTITY = ["-c", "user.name=Power Agents memory",
                     "-c", "user.email=memory@localhost"]


class MemoryError(Exception):
    pass


def store() -> Path:
    return Path.home() / ".agents" / "memory"


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    result = subprocess.run(["git", "-C", str(store()), *args],
                            capture_output=True, text=True, check=False)
    if check and result.returncode != 0:
        raise MemoryError(f"git {args[0]} failed: {result.stderr.strip()}")
    return result


def ensure_store() -> None:
    store().mkdir(parents=True, exist_ok=True)
    if not (store() / ".git").exists():
        git("init", "-q")


def commit(message: str) -> None:
    git("add", "-A")
    if git("diff", "--cached", "--quiet", check=False).returncode == 0:
        return
    identity = [] if git("config", "user.email", check=False).stdout.strip() \
        else FALLBACK_IDENTITY
    git(*identity, "commit", "-q", "--no-verify", "-m", message)


def source_project() -> str:
    result = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                            capture_output=True, text=True, check=False)
    top = result.stdout.strip() if result.returncode == 0 else ""
    return Path(top or os.getcwd()).name


def source_session() -> str:
    for agent, variable in (("claude", "CLAUDE_CODE_SESSION_ID"),
                            ("codex", "CODEX_THREAD_ID")):
        if os.environ.get(variable):
            return f"{agent} {os.environ[variable]}"
    return "unknown"


def validate(name: str, kind: str, description: str, body: str) -> None:
    if not NAME.fullmatch(name) or name == "memory":
        raise MemoryError(f"invalid name {name!r}: use lowercase words joined "
                          "by hyphens, other than 'memory'")
    if kind not in TYPES:
        raise MemoryError(f"invalid type {kind!r}: choose {', '.join(TYPES)}")
    if not description.strip() or "\n" in description or \
            len(description) > MAX_DESCRIPTION:
        raise MemoryError("the description must be one non-empty line of at "
                          f"most {MAX_DESCRIPTION} characters")
    if not body.strip():
        raise MemoryError("the memory body (standard input) is empty")


def render(name: str, kind: str, description: str, body: str) -> str:
    return (
        "---\n"
        f"name: {name}\n"
        f"description: {json.dumps(description.strip(), ensure_ascii=False)}\n"
        "metadata:\n"
        f"  type: {kind}\n"
        f"  source-project: {source_project()}\n"
        f"  source-session: {source_session()}\n"
        f"  created: {datetime.date.today().isoformat()}\n"
        "---\n\n"
        f"{body.strip()}\n"
    )


def frontmatter(path: Path) -> dict[str, str] | None:
    """The name, description, and type of a memory file, or None."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError):
        return None
    if not lines or lines[0] != "---" or "---" not in lines[1:]:
        return None
    fields = {}
    for line in lines[1:lines.index("---", 1)]:
        key, separator, value = line.strip().partition(":")
        if not separator:
            continue
        value = value.strip()
        if value.startswith('"'):
            try:
                value = json.loads(value)
            except ValueError:
                return None
        fields[key] = value
    if not all(fields.get(key) for key in ("name", "description", "type")):
        return None
    return fields


def write_index() -> list[Path]:
    """Rebuild MEMORY.md and return the files it could not read."""
    entries = {kind: [] for kind in TYPES}
    unreadable = []
    for path in sorted(store().glob("*.md")):
        if path.name == INDEX:
            continue
        fields = frontmatter(path)
        if fields is None or fields["type"] not in entries:
            unreadable.append(path)
            continue
        entries[fields["type"]].append(
            f"- [{fields['name']}]({path.name}) — {fields['description']}")
    sections = ["# Memory\n\nShared across projects. One fact per file; "
                "edit the files, then run the remember skill's index command."]
    for kind in TYPES:
        if entries[kind]:
            sections.append(f"## {kind.capitalize()}\n\n" + "\n".join(entries[kind]))
    (store() / INDEX).write_text("\n\n".join(sections) + "\n", encoding="utf-8")
    return unreadable


def report_unreadable(paths: list[Path]) -> None:
    for path in paths:
        print(f"WARNING: left out of the index (no valid frontmatter): {path}",
              file=sys.stderr)


def save(name: str, kind: str, description: str, replace: bool) -> Path:
    body = sys.stdin.read()
    validate(name, kind, description, body)
    path = store() / f"{name}.md"
    existed = path.exists()
    if existed and not replace:
        raise MemoryError(f"{path} already exists; pass --replace to update it")
    ensure_store()
    path.write_text(render(name, kind, description, body), encoding="utf-8")
    report_unreadable(write_index())
    commit(f"{'update' if existed else 'remember'}: {name}")
    return path


def forget(name: str) -> None:
    path = store() / f"{name}.md"
    if not NAME.fullmatch(name) or not path.is_file():
        raise MemoryError(f"No memory named {name} in {store()}")
    path.unlink()
    report_unreadable(write_index())
    commit(f"forget: {name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    save_parser = commands.add_parser("save", help="save a memory read from stdin")
    save_parser.add_argument("name")
    save_parser.add_argument("--type", required=True, dest="kind")
    save_parser.add_argument("--description", required=True)
    save_parser.add_argument("--replace", action="store_true")
    forget_parser = commands.add_parser("forget", help="delete a memory")
    forget_parser.add_argument("name")
    commands.add_parser("index", help="rebuild MEMORY.md after manual edits")
    arguments = parser.parse_args()

    try:
        if arguments.command == "save":
            path = save(arguments.name, arguments.kind, arguments.description,
                        arguments.replace)
            print(f"Saved {path}")
        elif arguments.command == "forget":
            forget(arguments.name)
            print(f"Forgot {arguments.name}")
        else:
            ensure_store()
            report_unreadable(write_index())
            commit("index: rebuild")
            print(f"Rebuilt {store() / INDEX}")
    except (MemoryError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
