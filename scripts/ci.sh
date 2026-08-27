#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_DIR=""

cleanup() {
  [[ -z "$ARCHIVE_DIR" ]] || rm -rf -- "$ARCHIVE_DIR"
}
trap cleanup EXIT

for command in git make tar; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $command" >&2
    echo "       See README.md#quality-checks for setup instructions." >&2
    exit 1
  fi
done

if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: The CI pipeline must run from a Git checkout: $ROOT" >&2
  exit 1
fi

echo "Running checks in the working tree..."
make --no-print-directory -C "$ROOT" check

echo "Running checks from a source archive of HEAD..."
ARCHIVE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/power-agents-ci.XXXXXX")"
git -C "$ROOT" archive HEAD | tar -x -C "$ARCHIVE_DIR"
make --no-print-directory -C "$ARCHIVE_DIR" check

echo "CI pipeline passed."
