#!/usr/bin/env python3
"""Render the shared subagent definitions for Claude Code and Codex.

  render-subagents.py SOURCE_DIR OUTPUT_DIR [--models agent-models.json]

Each SOURCE_DIR/<role>.md has a frontmatter of plain `key: value` lines (name,
description, claude-tools, claude-model, codex-reasoning-effort) and the
instructions as its body. OUTPUT_DIR/claude/<role>.md and
OUTPUT_DIR/codex/<role>.toml are written only when everything is valid. The
optional models file maps agent and role to a model name, such as
{"claude": {"reviewer": "opus"}, "codex": {"reviewer": "gpt-5.5"}}. Python
standard library only.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


KEYS = ("name", "description", "claude-tools", "claude-model",
        "codex-reasoning-effort")
EFFORTS = ("minimal", "low", "medium", "high", "xhigh")
AGENTS = ("claude", "codex")
MODEL = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:/\[\]-]{0,127}")
TOOLS = re.compile(r"[A-Za-z]+(, [A-Za-z]+)*")


class RenderError(Exception):
    pass


def read_role(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    parts = text.split("---\n", 2)
    if len(parts) != 3 or parts[0]:
        raise RenderError(f"{path}: expected a --- frontmatter block")
    role = {}
    for line in parts[1].splitlines():
        key, separator, value = line.partition(": ")
        if not separator or key not in KEYS or key in role:
            raise RenderError(f"{path}: unexpected frontmatter line {line!r}")
        role[key] = value.strip()
    missing = [key for key in KEYS if not role.get(key)]
    if missing:
        raise RenderError(f"{path}: missing {', '.join(missing)}")
    if role["name"] != path.stem:
        raise RenderError(f"{path}: name must match the file name")
    if role["codex-reasoning-effort"] not in EFFORTS:
        raise RenderError(f"{path}: codex-reasoning-effort must be one of "
                          f"{', '.join(EFFORTS)}")
    if not MODEL.fullmatch(role["claude-model"]) or \
            not TOOLS.fullmatch(role["claude-tools"]):
        raise RenderError(f"{path}: invalid claude-model or claude-tools")
    role["body"] = parts[2].strip()
    if not role["body"] or "'''" in role["body"]:
        raise RenderError(f"{path}: the body must be non-empty and without '''")
    return role


def read_models(path: Path | None, roles: list[str]) -> dict[str, dict[str, str]]:
    if path is None:
        return {}
    try:
        models = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeError) as error:
        raise RenderError(f"{path}: {error}") from error
    if not isinstance(models, dict):
        raise RenderError(f"{path}: expected a JSON object")
    for agent, choices in models.items():
        if agent not in AGENTS or not isinstance(choices, dict):
            raise RenderError(f"{path}: keys must be {' or '.join(AGENTS)}, "
                              "each holding an object")
        for role, model in choices.items():
            if role not in roles:
                raise RenderError(f"{path}: unknown subagent {role!r}")
            if not isinstance(model, str) or not MODEL.fullmatch(model):
                raise RenderError(f"{path}: invalid model name for {agent}.{role}")
    return models


def claude_file(role: dict[str, str], model: str) -> str:
    return (
        "---\n"
        f"name: {role['name']}\n"
        f"description: {json.dumps(role['description'], ensure_ascii=False)}\n"
        f"tools: {role['claude-tools']}\n"
        f"model: {model}\n"
        "---\n\n"
        f"{role['body']}\n"
    )


def codex_file(role: dict[str, str], model: str | None) -> str:
    lines = [
        f"name = {json.dumps(role['name'])}",
        f"description = {json.dumps(role['description'], ensure_ascii=False)}",
        f"model_reasoning_effort = {json.dumps(role['codex-reasoning-effort'])}",
    ]
    if model:
        lines.append(f"model = {json.dumps(model)}")
    lines.append(f"developer_instructions = '''\n{role['body']}\n'''")
    return "\n".join(lines) + "\n"


def render(source: Path, output: Path, models_path: Path | None) -> None:
    roles = [read_role(path) for path in sorted(source.glob("*.md"))]
    if not roles:
        raise RenderError(f"{source}: no subagent definitions")
    models = read_models(models_path, [role["name"] for role in roles])
    files = {}
    for role in roles:
        name = role["name"]
        files[Path("claude") / f"{name}.md"] = claude_file(
            role, models.get("claude", {}).get(name, role["claude-model"]))
        files[Path("codex") / f"{name}.toml"] = codex_file(
            role, models.get("codex", {}).get(name))
    for relative, text in files.items():
        path = output / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--models", type=Path)
    arguments = parser.parse_args()
    try:
        render(arguments.source, arguments.output, arguments.models)
    except (RenderError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
