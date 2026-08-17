#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOBAL_INSTRUCTIONS="$ROOT/instructions/general-global.md"
SKILLS="$ROOT/skills"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

mkdir -p \
  "$ROOT/instructions" \
  "$SKILLS" \
  "$HOME/.codex" \
  "$HOME/.claude" \
  "$HOME/.copilot"

if [[ ! -f "$GLOBAL_INSTRUCTIONS" ]]; then
  echo "ERROR: Missing $GLOBAL_INSTRUCTIONS" >&2
  exit 1
fi

backup_and_link() {
  local source="$1"
  local target="$2"

  if [[ -L "$target" ]]; then
    local current
    local expected

    current="$(readlink -f "$target" 2>/dev/null || true)"
    expected="$(readlink -f "$source" 2>/dev/null || true)"

    if [[ "$current" == "$expected" ]]; then
      echo "OK: $target"
      return
    fi
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    local backup="${target}.backup-${TIMESTAMP}"
    mv "$target" "$backup"
    echo "BACKUP: $target -> $backup"
  fi

  ln -s "$source" "$target"
  echo "LINK: $target -> $source"
}

echo
echo "Installing global agent configuration..."
echo

# Shared instructions
backup_and_link \
  "$GLOBAL_INSTRUCTIONS" \
  "$HOME/.codex/AGENTS.md"

backup_and_link \
  "$GLOBAL_INSTRUCTIONS" \
  "$HOME/.claude/CLAUDE.md"

backup_and_link \
  "$GLOBAL_INSTRUCTIONS" \
  "$HOME/.copilot/copilot-instructions.md"

# Claude does not natively use ~/.agents/skills, so expose the
# canonical shared skills directory at Claude's expected location.
backup_and_link \
  "$SKILLS" \
  "$HOME/.claude/skills"

echo
echo "Checking skill names..."
echo

for skill_dir in "$SKILLS"/*; do
  [[ -d "$skill_dir" ]] || continue
  [[ -f "$skill_dir/SKILL.md" ]] || continue

  folder_name="$(basename "$skill_dir")"

  skill_name="$(
    sed -n \
      's/^name:[[:space:]]*["'\'']\{0,1\}\([^"'\'']*\)["'\'']\{0,1\}[[:space:]]*$/\1/p' \
      "$skill_dir/SKILL.md" |
    head -n 1 |
    xargs
  )"

  if [[ -n "$skill_name" && "$skill_name" != "$folder_name" ]]; then
    echo "WARNING: $folder_name/SKILL.md"
    echo "         folder: $folder_name"
    echo "         name:   $skill_name"
  fi
done

echo
echo "Done."
echo
echo "Canonical instructions:"
echo "  $GLOBAL_INSTRUCTIONS"
echo
echo "Canonical skills:"
echo "  $SKILLS"
