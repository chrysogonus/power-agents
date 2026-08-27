#!/usr/bin/env python3
"""Safely reconcile the managed Codex TUI settings in a TOML document."""

from __future__ import annotations

import argparse
import copy
import sys
from pathlib import Path
from typing import Any

import tomlkit


MANAGED_KEYS = ("status_line", "status_line_use_colors")


def parse_file(path: Path) -> tomlkit.TOMLDocument:
    try:
        return tomlkit.parse(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, tomlkit.exceptions.ParseError) as error:
        raise ValueError(f"invalid TOML in {path}: {error}") from error


def validate_managed_settings(document: tomlkit.TOMLDocument) -> None:
    values = document.unwrap()
    if set(values) != {"tui"} or not isinstance(values["tui"], dict):
        raise ValueError("managed settings must contain only a [tui] table")

    tui = values["tui"]
    if set(tui) != set(MANAGED_KEYS):
        raise ValueError(
            "managed [tui] table must contain only status_line and "
            "status_line_use_colors"
        )


def validate_config(document: tomlkit.TOMLDocument) -> None:
    tui = document.get("tui")
    if tui is not None and not isinstance(tui, dict):
        raise ValueError("top-level tui value must be a table")


def without_managed_values(values: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(values)
    tui = result.get("tui")
    if isinstance(tui, dict):
        for key in MANAGED_KEYS:
            tui.pop(key, None)
        if not tui:
            result.pop("tui")
    return result


def reconcile(source_path: Path, input_path: Path, output_path: Path) -> None:
    source = parse_file(source_path)
    validate_managed_settings(source)

    document = parse_file(input_path)
    validate_config(document)
    original_values = document.unwrap()
    managed_values = source.unwrap()["tui"]

    tui = document.get("tui")
    if tui is None:
        tui = tomlkit.table()
        document.append("tui", tui)

    for key in MANAGED_KEYS:
        tui[key] = managed_values[key]

    candidate_text = tomlkit.dumps(document)
    try:
        candidate = tomlkit.parse(candidate_text)
    except tomlkit.exceptions.ParseError as error:
        raise ValueError(f"generated invalid TOML: {error}") from error

    candidate_values = candidate.unwrap()
    candidate_tui = candidate_values.get("tui")
    if not isinstance(candidate_tui, dict) or any(
        candidate_tui.get(key) != managed_values[key] for key in MANAGED_KEYS
    ):
        raise ValueError("generated TOML does not contain the managed TUI values")

    if without_managed_values(original_values) != without_managed_values(
        candidate_values
    ):
        raise ValueError("generated TOML changes unmanaged values")

    try:
        output_path.write_text(candidate_text, encoding="utf-8")
    except OSError as error:
        raise ValueError(f"could not write {output_path}: {error}") from error


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

    arguments = parser.parse_args()

    try:
        if arguments.command == "validate-managed":
            document = parse_file(arguments.source)
            validate_managed_settings(document)
        elif arguments.command == "validate-config":
            document = parse_file(arguments.config)
            validate_config(document)
        else:
            reconcile(arguments.source, arguments.input, arguments.output)
    except ValueError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
