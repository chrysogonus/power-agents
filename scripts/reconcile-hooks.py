#!/usr/bin/env python3
"""Safely reconcile the managed verify-gate hook entries in a JSON document.

Claude Code settings and Codex hooks.json share the same hook layout:
{"hooks": {"<Event>": [{"matcher": ..., "hooks": [{"command": ...}]}]}}.
Managed entries are the handlers whose command references the installed
verify-gate script. Every other value is preserved.
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path
from typing import Any


PLACEHOLDER = "@VERIFY_GATE@"
LEGACY_SCRIPT = "verify_gate.py"
MANAGED_HANDLER_KEYS = {"type", "command", "timeout"}
UNSAFE_PATH_CHARACTERS = set('"$`\\\n\r')
DEFAULT_SCRIPT = Path.home() / ".agents" / "hooks" / "verify-gate.py"


def reject_constant(name: str) -> None:
    raise ValueError(f"unsupported JSON constant {name}")


def parse_file(path: Path) -> dict[str, Any]:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise ValueError(f"could not read {path}: {error}") from error
    if not text.strip():
        return {}
    try:
        value = json.loads(text, parse_constant=reject_constant)
    except ValueError as error:
        raise ValueError(f"invalid JSON in {path}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def validate_managed(document: dict[str, Any]) -> None:
    if set(document) != {"hooks"} or not isinstance(document["hooks"], dict):
        raise ValueError("managed hooks must contain only a hooks object")
    if not document["hooks"]:
        raise ValueError("managed hooks must define at least one event")

    for event, groups in document["hooks"].items():
        if not isinstance(groups, list) or not groups:
            raise ValueError(f"managed {event} must be a non-empty array")
        for group in groups:
            if (
                not isinstance(group, dict)
                or set(group) != {"hooks"}
                or not isinstance(group["hooks"], list)
                or not group["hooks"]
            ):
                raise ValueError(
                    f"managed {event} groups must contain only a non-empty "
                    "hooks array"
                )
            for handler in group["hooks"]:
                if not isinstance(handler, dict) or not (
                    {"type", "command"} <= set(handler) <= MANAGED_HANDLER_KEYS
                ):
                    raise ValueError(
                        f"managed {event} handlers must contain type, "
                        "command, and an optional timeout"
                    )
                if handler["type"] != "command":
                    raise ValueError(f"managed {event} handlers must be commands")
                command = handler["command"]
                if not isinstance(command, str) or PLACEHOLDER not in command:
                    raise ValueError(
                        f"managed {event} commands must reference {PLACEHOLDER}"
                    )
                timeout = handler.get("timeout", 1)
                if (
                    not isinstance(timeout, int)
                    or isinstance(timeout, bool)
                    or timeout <= 0
                ):
                    raise ValueError(
                        f"managed {event} timeouts must be positive integers"
                    )


def handlers(document: dict[str, Any]):
    """Yield every handler; reject layouts this tool cannot edit safely."""
    hooks = document.get("hooks")
    if hooks is None:
        return
    if not isinstance(hooks, dict):
        raise ValueError("top-level hooks value must be an object")
    for event, groups in hooks.items():
        if not isinstance(groups, list):
            raise ValueError(f"hooks.{event} must be an array")
        for group in groups:
            if not isinstance(group, dict):
                raise ValueError(f"hooks.{event} entries must be objects")
            entries = group.get("hooks")
            if entries is None:
                continue
            if not isinstance(entries, list):
                raise ValueError(f"hooks.{event}[].hooks must be an array")
            for handler in entries:
                if not isinstance(handler, dict):
                    raise ValueError(f"hooks.{event}[].hooks entries must be objects")
                yield handler


def validate_config(document: dict[str, Any], path: Path) -> None:
    for handler in handlers(document):
        command = handler.get("command")
        if isinstance(command, str) and LEGACY_SCRIPT in command:
            raise ValueError(
                f"legacy standalone verify gate hook in {path}: {command}\n"
                "       Run the standalone verify gate's uninstall.sh first, "
                "then rerun the installer."
            )


def is_managed(handler: Any, script: str) -> bool:
    return (
        isinstance(handler, dict)
        and isinstance(handler.get("command"), str)
        and script in handler["command"]
    )


def without_managed(document: dict[str, Any], script: str) -> dict[str, Any]:
    """Drop managed handlers and the containers that only they kept alive."""
    result = copy.deepcopy(document)
    hooks = result.get("hooks")
    if not isinstance(hooks, dict):
        return result

    for event in list(hooks):
        kept_groups = []
        removed = False
        for group in hooks[event]:
            entries = group.get("hooks")
            if isinstance(entries, list) and any(
                is_managed(handler, script) for handler in entries
            ):
                removed = True
                group["hooks"] = [
                    handler for handler in entries
                    if not is_managed(handler, script)
                ]
                if not group["hooks"]:
                    continue
            kept_groups.append(group)
        hooks[event] = kept_groups
        if removed and not kept_groups:
            del hooks[event]
            if not hooks:
                del result["hooks"]
    return result


def managed_entries(source: dict[str, Any], script: str) -> dict[str, Any]:
    text = json.dumps(source["hooks"])
    return json.loads(text.replace(PLACEHOLDER, json.dumps(script)[1:-1]))


def validate_script_path(script: str) -> None:
    if not script.startswith("/"):
        raise ValueError(f"script path must be absolute: {script}")
    if UNSAFE_PATH_CHARACTERS & set(script):
        raise ValueError(
            f"script path contains characters unsafe in a hook command: {script}"
        )


def dump(document: dict[str, Any]) -> str:
    return json.dumps(document, indent=2, ensure_ascii=False, allow_nan=False) + "\n"


def write(path: Path, document: dict[str, Any]) -> None:
    try:
        path.write_text(dump(document), encoding="utf-8")
    except OSError as error:
        raise ValueError(f"could not write {path}: {error}") from error


def reconcile(
    source_path: Path, input_path: Path, output_path: Path, script: str
) -> None:
    validate_script_path(script)
    source = parse_file(source_path)
    validate_managed(source)
    original = parse_file(input_path)
    validate_config(original, input_path)

    managed = managed_entries(source, script)
    candidate = without_managed(original, script)
    hooks = candidate.setdefault("hooks", {})
    for event, groups in managed.items():
        hooks.setdefault(event, []).extend(groups)

    if without_managed(candidate, script) != without_managed(original, script):
        raise ValueError("generated hooks change unmanaged values")
    if any(
        group not in candidate["hooks"][event]
        for event, groups in managed.items()
        for group in groups
    ):
        raise ValueError("generated hooks do not contain the managed entries")

    write(output_path, candidate)


def remove(input_path: Path, output_path: Path, script: str) -> None:
    original = parse_file(input_path)
    list(handlers(original))
    write(output_path, without_managed(original, script))


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate_managed_parser = subparsers.add_parser("validate-managed")
    validate_managed_parser.add_argument("source", type=Path)

    validate_config_parser = subparsers.add_parser("validate-config")
    validate_config_parser.add_argument("config", type=Path)

    reconcile_parser = subparsers.add_parser("reconcile")
    reconcile_parser.add_argument("source", type=Path)
    reconcile_parser.add_argument("input", type=Path)
    reconcile_parser.add_argument("output", type=Path)
    reconcile_parser.add_argument("--script", required=True)

    remove_parser = subparsers.add_parser("remove")
    remove_parser.add_argument("input", type=Path)
    remove_parser.add_argument("output", type=Path)
    remove_parser.add_argument("--script", default=str(DEFAULT_SCRIPT))

    arguments = parser.parse_args()

    try:
        if arguments.command == "validate-managed":
            validate_managed(parse_file(arguments.source))
        elif arguments.command == "validate-config":
            validate_config(parse_file(arguments.config), arguments.config)
        elif arguments.command == "reconcile":
            reconcile(
                arguments.source,
                arguments.input,
                arguments.output,
                arguments.script,
            )
        else:
            remove(arguments.input, arguments.output, arguments.script)
    except ValueError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
