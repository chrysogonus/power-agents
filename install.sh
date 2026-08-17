#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOBAL_INSTRUCTIONS="$ROOT/instructions/general-global.md"
SKILLS="$ROOT/skills"
BACKUP_BASE="$HOME/.agents-backups"
BACKUP_ROOT=""
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"

if [[ ! -f "$GLOBAL_INSTRUCTIONS" ]]; then
  echo "ERROR: Missing $GLOBAL_INSTRUCTIONS" >&2
  exit 1
fi

if [[ ! -d "$SKILLS" ]]; then
  echo "ERROR: Missing $SKILLS" >&2
  exit 1
fi

skill_name_from_file() {
  local skill_file="$1"

  sed -n \
    's/^name:[[:space:]]*["'\'' ]*\([^"'\'' ]*\)["'\'' ]*[[:space:]]*$/\1/p' \
    "$skill_file" |
    head -n 1
}

validate_skills() {
  local failed=0
  local folder_name
  local skill_dir
  local skill_name

  for skill_dir in "$SKILLS"/*; do
    [[ -d "$skill_dir" ]] || continue

    folder_name="$(basename "$skill_dir")"

    if [[ ! -f "$skill_dir/SKILL.md" ]]; then
      echo "ERROR: Missing $skill_dir/SKILL.md" >&2
      failed=1
      continue
    fi

    skill_name="$(skill_name_from_file "$skill_dir/SKILL.md")"

    if [[ -z "$skill_name" ]]; then
      echo "ERROR: Missing or invalid name in $skill_dir/SKILL.md" >&2
      failed=1
    elif [[ "$skill_name" != "$folder_name" ]]; then
      echo "ERROR: Skill folder and name do not match: $skill_dir" >&2
      echo "       folder: $folder_name" >&2
      echo "       name:   $skill_name" >&2
      failed=1
    fi
  done

  return "$failed"
}

ensure_backup_root() {
  if [[ -z "$BACKUP_ROOT" ]]; then
    BACKUP_ROOT="$BACKUP_BASE/$RUN_ID"
    mkdir -p "$BACKUP_ROOT"
  fi
}

backup_target() {
  local target="$1"
  local relative_target
  local backup

  ensure_backup_root

  relative_target="${target#"$HOME"/}"
  if [[ "$relative_target" == "$target" ]]; then
    relative_target="$(basename "$target")"
  fi

  backup="$BACKUP_ROOT/$relative_target"
  mkdir -p "$(dirname "$backup")"
  mv "$target" "$backup"
  echo "BACKUP: $target -> $backup"
}

backup_and_link() {
  local source="$1"
  local target="$2"

  if [[ -L "$target" && "$target" -ef "$source" ]]; then
    echo "OK: $target"
    return
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    backup_target "$target"
  fi

  ln -s "$source" "$target"
  echo "LINK: $target -> $source"
}

migrate_legacy_codex_skills() {
  local legacy_root="$HOME/.codex/skills"
  local legacy_skill
  local skill_dir

  [[ -d "$legacy_root" ]] || return

  for skill_dir in "$SKILLS"/*; do
    [[ -d "$skill_dir" ]] || continue
    legacy_skill="$legacy_root/$(basename "$skill_dir")"

    if [[ -e "$legacy_skill" || -L "$legacy_skill" ]]; then
      backup_target "$legacy_skill"
      echo "MIGRATE: Codex reads $skill_dir directly"
    fi
  done
}

validate_skills

mkdir -p \
  "$HOME/.codex" \
  "$HOME/.claude/skills" \
  "$HOME/.copilot"

echo
echo "Installing global agent configuration..."
echo

# Shared instructions.
backup_and_link \
  "$GLOBAL_INSTRUCTIONS" \
  "$HOME/.codex/AGENTS.md"

backup_and_link \
  "$GLOBAL_INSTRUCTIONS" \
  "$HOME/.claude/CLAUDE.md"

backup_and_link \
  "$GLOBAL_INSTRUCTIONS" \
  "$HOME/.copilot/copilot-instructions.md"

# Codex and GitHub Copilot discover ~/.agents/skills directly. Remove only
# same-named legacy Codex copies so each canonical skill is registered once.
migrate_legacy_codex_skills

# Claude Code expects personal skills under ~/.claude/skills. Link individual
# skills so independently managed Claude skills remain available.
for skill_dir in "$SKILLS"/*; do
  [[ -d "$skill_dir" ]] || continue
  backup_and_link \
    "$skill_dir" \
    "$HOME/.claude/skills/$(basename "$skill_dir")"
done

echo
echo "Done."
echo
echo "Canonical instructions:"
echo "  $GLOBAL_INSTRUCTIONS"
echo
echo "Canonical skills:"
echo "  $SKILLS"

if [[ -n "$BACKUP_ROOT" ]]; then
  echo
  echo "Backups created:"
  echo "  $BACKUP_ROOT"
fi
