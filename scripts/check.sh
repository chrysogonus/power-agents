#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ((BASH_VERSINFO[0] < 4)); then
  echo "ERROR: Bash 4 or newer is required." >&2
  echo "       See README.md#quality-checks for setup instructions." >&2
  exit 1
fi

for command in git gpg jq make python3 shellcheck; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $command" >&2
    echo "       See README.md#quality-checks for setup instructions." >&2
    exit 1
  fi
done

if ! python3 -c 'import tomlkit' >/dev/null 2>&1; then
  echo "ERROR: Required Python module not found: tomlkit" >&2
  echo "       See README.md#quality-checks for setup instructions." >&2
  exit 1
fi

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "ERROR: Required Python module not found: yaml (PyYAML)" >&2
  echo "       See README.md#quality-checks for setup instructions." >&2
  exit 1
fi

echo "Validating skills..."
python3 "$ROOT/scripts/validate-skills.py" "$ROOT/skills"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  mapfile -d '' shell_files < <(
    git ls-files --cached --others --exclude-standard -z -- '*.sh'
  )
  mapfile -d '' repository_files < <(
    git ls-files --cached --others --exclude-standard -z
  )
else
  mapfile -d '' shell_files < <(
    find . -path './.git' -prune -o -type f -name '*.sh' -print0
  )
  mapfile -d '' repository_files < <(
    find . -path './.git' -prune -o -type f -print0
  )
fi

if ((${#shell_files[@]} == 0)); then
  echo "ERROR: No shell scripts found to check." >&2
  exit 1
fi

echo "Checking Bash syntax..."
for shell_file in "${shell_files[@]}"; do
  bash -n "$shell_file"
done

echo "Running ShellCheck..."
shellcheck --severity=warning "${shell_files[@]}"

echo "Running behavioral tests..."
"$ROOT/tests/run.sh"

echo "Checking tracked files and the working tree for whitespace errors..."
whitespace_failed=0
for repository_file in "${repository_files[@]}"; do
  if check_output="$(git diff --no-index --check /dev/null "$repository_file" 2>&1)"; then
    check_status=0
  else
    check_status=$?
  fi

  # A clean file differs from /dev/null, so Git returns 1. Whitespace errors
  # and operational failures return a larger status.
  if ((check_status > 1)); then
    printf '%s\n' "$check_output" >&2
    whitespace_failed=1
  fi
done
((whitespace_failed == 0)) || exit 1

echo "All checks passed."
