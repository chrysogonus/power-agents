#!/usr/bin/env python3
"""Validate repository skill metadata and optional evaluation fixtures."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

import yaml


SKILL_NAME_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def parse_frontmatter(skill_file: Path) -> tuple[dict[str, Any], list[str]]:
    try:
        lines = skill_file.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        raise ValueError(f"could not read {skill_file}: {error}") from error

    if not lines or lines[0] != "---":
        raise ValueError(f"{skill_file}: must start with YAML frontmatter")

    try:
        closing_index = lines.index("---", 1)
    except ValueError as error:
        raise ValueError(f"{skill_file}: YAML frontmatter is not closed") from error

    try:
        fields = yaml.safe_load("\n".join(lines[1:closing_index]))
    except yaml.YAMLError as error:
        raise ValueError(f"{skill_file}: invalid YAML frontmatter: {error}") from error
    if not isinstance(fields, dict) or any(
        not isinstance(key, str) for key in fields
    ):
        raise ValueError(f"{skill_file}: YAML frontmatter must be a mapping")

    return fields, lines[closing_index + 1 :]


def required_string(
    fields: dict[str, Any], field: str, skill_file: Path
) -> str:
    if field not in fields:
        raise ValueError(f"{skill_file}: missing required {field} frontmatter field")
    value = fields[field]
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{skill_file}: {field} must be a non-empty string")
    return value.strip()


def validate_evals(skill_dir: Path, skill_name: str) -> list[str]:
    evals_dir = skill_dir / "evals"
    evals_file = evals_dir / "evals.json"
    if not evals_dir.exists():
        return []
    if not evals_file.is_file():
        return [f"{evals_dir}: evaluation directory must contain evals.json"]

    try:
        document: Any = json.loads(evals_file.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        return [f"{evals_file}: invalid JSON: {error}"]

    errors: list[str] = []
    if not isinstance(document, dict):
        return [f"{evals_file}: top-level value must be an object"]
    if document.get("skill_name") != skill_name:
        errors.append(f"{evals_file}: skill_name must be {skill_name!r}")

    evaluations = document.get("evals")
    if not isinstance(evaluations, list) or not evaluations:
        errors.append(f"{evals_file}: evals must be a non-empty array")
        return errors

    seen_ids: set[int] = set()
    for index, evaluation in enumerate(evaluations, start=1):
        location = f"{evals_file}: eval {index}"
        if not isinstance(evaluation, dict):
            errors.append(f"{location} must be an object")
            continue

        evaluation_id = evaluation.get("id")
        if not isinstance(evaluation_id, int) or isinstance(evaluation_id, bool):
            errors.append(f"{location} id must be an integer")
        elif evaluation_id in seen_ids:
            errors.append(f"{location} has duplicate id {evaluation_id}")
        else:
            seen_ids.add(evaluation_id)

        for field in ("prompt", "expected_output"):
            value = evaluation.get(field)
            if not isinstance(value, str) or not value.strip():
                errors.append(f"{location} {field} must be a non-empty string")

        assertions = evaluation.get("assertions")
        if assertions is not None and (
            not isinstance(assertions, list)
            or not assertions
            or any(not isinstance(item, str) or not item.strip() for item in assertions)
        ):
            errors.append(
                f"{location} assertions must be a non-empty array of strings"
            )

        files = evaluation.get("files")
        if files is None:
            continue
        if not isinstance(files, list) or any(
            not isinstance(item, str) or not item for item in files
        ):
            errors.append(f"{location} files must be an array of paths")
            continue
        for item in files:
            candidate = (skill_dir / item).resolve()
            try:
                candidate.relative_to(skill_dir.resolve())
            except ValueError:
                errors.append(f"{location} file escapes the skill directory: {item}")
                continue
            if not candidate.is_file():
                errors.append(f"{location} file does not exist: {item}")

    return errors


def validate_skill(skill_dir: Path) -> list[str]:
    errors: list[str] = []
    skill_name = skill_dir.name
    if not SKILL_NAME_PATTERN.fullmatch(skill_name):
        errors.append(f"{skill_dir}: directory name must match {SKILL_NAME_PATTERN.pattern}")

    skill_file = skill_dir / "SKILL.md"
    if not skill_file.is_file():
        return errors + [f"{skill_file}: missing skill entrypoint"]

    try:
        fields, body_lines = parse_frontmatter(skill_file)
        declared_name = required_string(fields, "name", skill_file)
        required_string(fields, "description", skill_file)
        if declared_name != skill_name:
            errors.append(
                f"{skill_file}: name {declared_name!r} does not match directory "
                f"{skill_name!r}"
            )
        if not any(line.strip() for line in body_lines):
            errors.append(f"{skill_file}: markdown body must not be empty")
    except ValueError as error:
        errors.append(str(error))

    errors.extend(validate_evals(skill_dir, skill_name))
    return errors


def validate_skills(skills_root: Path) -> list[str]:
    if not skills_root.is_dir():
        return [f"{skills_root}: skills root is not a directory"]

    skill_dirs = sorted(path for path in skills_root.iterdir() if path.is_dir())
    if not skill_dirs:
        return [f"{skills_root}: no skill directories found"]

    errors: list[str] = []
    for skill_dir in skill_dirs:
        errors.extend(validate_skill(skill_dir))
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("skills_root", type=Path)
    arguments = parser.parse_args()

    errors = validate_skills(arguments.skills_root)
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())
