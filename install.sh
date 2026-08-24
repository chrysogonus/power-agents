#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOBAL_INSTRUCTIONS="$ROOT/instructions/general-global.md"
SKILLS="$ROOT/skills"

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

validate_link_target() {
  local source="$1"
  local target="$2"

  if [[ -L "$target" && "$target" -ef "$source" ]]; then
    return 0
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    echo "ERROR: Refusing to replace existing path: $target" >&2
    echo "       Move its canonical content into $ROOT, then remove it." >&2
    return 1
  fi

  return 0
}

install_link() {
  local source="$1"
  local target="$2"

  if [[ -L "$target" && "$target" -ef "$source" ]]; then
    echo "OK: $target"
    return
  fi

  ln -s "$source" "$target"
  echo "LINK: $target -> $source"
}

validate_legacy_codex_skills() {
  local legacy_root="$HOME/.codex/skills"
  local legacy_skill
  local failed=0
  local skill_dir

  [[ -d "$legacy_root" ]] || return 0

  for skill_dir in "$SKILLS"/*; do
    [[ -d "$skill_dir" ]] || continue
    legacy_skill="$legacy_root/$(basename "$skill_dir")"

    if [[ -e "$legacy_skill" || -L "$legacy_skill" ]]; then
      echo "ERROR: Duplicate Codex skill exists: $legacy_skill" >&2
      echo "       Codex reads the canonical skill through ~/.agents/skills." >&2
      failed=1
    fi
  done

  return "$failed"
}

validate_skills

mkdir -p \
  "$HOME/.agents" \
  "$HOME/.codex" \
  "$HOME/.claude"

failed=0
validate_link_target \
  "$GLOBAL_INSTRUCTIONS" \
  "$HOME/.codex/AGENTS.md" || failed=1
validate_link_target \
  "$GLOBAL_INSTRUCTIONS" \
  "$HOME/.claude/CLAUDE.md" || failed=1
validate_link_target \
  "$SKILLS" \
  "$HOME/.agents/skills" || failed=1
validate_link_target \
  "$SKILLS" \
  "$HOME/.claude/skills" || failed=1
validate_legacy_codex_skills || failed=1

if ((failed)); then
  exit 1
fi

echo
echo "Installing global agent configuration..."
echo

# Shared instructions.
install_link \
  "$GLOBAL_INSTRUCTIONS" \
  "$HOME/.codex/AGENTS.md"

install_link \
  "$GLOBAL_INSTRUCTIONS" \
  "$HOME/.claude/CLAUDE.md"

# Codex discovers ~/.agents/skills. Claude Code discovers ~/.claude/skills.
# Both paths resolve to the same canonical directory.
install_link \
  "$SKILLS" \
  "$HOME/.agents/skills"

install_link \
  "$SKILLS" \
  "$HOME/.claude/skills"

echo
echo "Done."
echo
echo "Canonical instructions:"
echo "  $GLOBAL_INSTRUCTIONS"
echo
echo "Canonical skills:"
echo "  $SKILLS"
