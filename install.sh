#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOBAL_INSTRUCTIONS="$ROOT/instructions/general-global.md"
SKILLS="$ROOT/skills"
CLAUDE_STATUS_LINE="$ROOT/settings/claude/statusline-command.sh"
CODEX_TUI_SETTINGS="$ROOT/settings/codex/tui.toml"
CODEX_SHARED_RULES="$ROOT/policies/codex/shared.rules"

if [[ ! -f "$GLOBAL_INSTRUCTIONS" ]]; then
  echo "ERROR: Missing $GLOBAL_INSTRUCTIONS" >&2
  exit 1
fi

if [[ ! -d "$SKILLS" ]]; then
  echo "ERROR: Missing $SKILLS" >&2
  exit 1
fi

if [[ ! -f "$CLAUDE_STATUS_LINE" ]]; then
  echo "ERROR: Missing $CLAUDE_STATUS_LINE" >&2
  exit 1
fi

if [[ ! -f "$CODEX_TUI_SETTINGS" ]]; then
  echo "ERROR: Missing $CODEX_TUI_SETTINGS" >&2
  exit 1
fi

if [[ ! -f "$CODEX_SHARED_RULES" ]]; then
  echo "ERROR: Missing $CODEX_SHARED_RULES" >&2
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

validate_codex_tui_settings() {
  if ! awk '
    /^[[:space:]]*($|#)/ {
      next
    }

    /^[[:space:]]*\[tui\][[:space:]]*$/ {
      sections++
      next
    }

    /^[[:space:]]*status_line[[:space:]]*=/ {
      status_lines++
      next
    }

    /^[[:space:]]*status_line_use_colors[[:space:]]*=/ {
      color_settings++
      next
    }

    {
      invalid++
    }

    END {
      exit !(sections == 1 && status_lines == 1 && color_settings == 1 && invalid == 0)
    }
  ' "$CODEX_TUI_SETTINGS"; then
    echo "ERROR: Invalid Codex TUI settings fragment: $CODEX_TUI_SETTINGS" >&2
    echo "       Expected one [tui] section with status_line and status_line_use_colors." >&2
    return 1
  fi
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

validate_skill_links_target() {
  local skill_dir
  local target_root="$1"

  if [[ -L "$target_root" ]]; then
    if [[ "$target_root" -ef "$SKILLS" ]]; then
      return 0
    fi

    echo "ERROR: Refusing to replace existing path: $target_root" >&2
    echo "       Move its canonical content into $ROOT, then remove it." >&2
    return 1
  fi

  if [[ -e "$target_root" && ! -d "$target_root" ]]; then
    echo "ERROR: Refusing to replace existing path: $target_root" >&2
    echo "       Move its canonical content into $ROOT, then remove it." >&2
    return 1
  fi

  [[ -d "$target_root" ]] || return 0

  for skill_dir in "$SKILLS"/*; do
    [[ -d "$skill_dir" ]] || continue
    validate_link_target \
      "$skill_dir" \
      "$target_root/$(basename "$skill_dir")" || return 1
  done
}

install_skill_links() {
  local skill_dir
  local target_root="$1"

  if [[ -L "$target_root" && "$target_root" -ef "$SKILLS" ]]; then
    unlink "$target_root"
    echo "MIGRATE: $target_root (per-skill links)"
  fi

  mkdir -p "$target_root"
  for skill_dir in "$SKILLS"/*; do
    [[ -d "$skill_dir" ]] || continue
    install_link \
      "$skill_dir" \
      "$target_root/$(basename "$skill_dir")"
  done
}

validate_codex_config_target() {
  local target="$HOME/.codex/config.toml"

  if [[ -L "$target" ]]; then
    echo "ERROR: Refusing to update symlinked Codex config: $target" >&2
    echo "       Replace it with a regular file so local settings can be preserved." >&2
    return 1
  fi

  if [[ -e "$target" && ! -f "$target" ]]; then
    echo "ERROR: Codex config is not a regular file: $target" >&2
    return 1
  fi

  [[ -f "$target" ]] || return 0

  if awk '
    BEGIN {
      in_root = 1
    }

    in_root && /^[[:space:]]*(tui|"tui"|\047tui\047)[[:space:]]*[.=]/ {
      found = 1
      exit
    }

    /^[[:space:]]*\[\[?[^]]+\]\]?[[:space:]]*(#.*)?$/ {
      in_root = 0
    }

    END {
      exit !found
    }
  ' "$target"; then
    echo "ERROR: Unsupported top-level tui setting in Codex config: $target" >&2
    echo "       Use an explicit [tui] table so managed settings can be updated safely." >&2
    return 1
  fi
}

sync_codex_tui_settings() {
  local source="$CODEX_TUI_SETTINGS"
  local target="$HOME/.codex/config.toml"
  local input="/dev/null"
  local status_line
  local status_line_use_colors
  local temporary

  status_line="$(sed -n '/^[[:space:]]*status_line[[:space:]]*=/ {
    s/^[[:space:]]*//
    p
  }' "$source")"
  status_line_use_colors="$(sed -n '/^[[:space:]]*status_line_use_colors[[:space:]]*=/ {
    s/^[[:space:]]*//
    p
  }' "$source")"

  if [[ -f "$target" ]]; then
    input="$target"
  fi

  temporary="$(mktemp "$HOME/.codex/config.toml.tmp.XXXXXX")"
  if [[ -f "$target" ]] && ! cp -p "$target" "$temporary"; then
    rm -f "$temporary"
    return 1
  fi

  if ! awk \
    -v status_line="$status_line" \
    -v status_line_use_colors="$status_line_use_colors" '
      function emit_managed_settings() {
        print status_line
        print status_line_use_colors
      }

      {
        if (skipping_status_line) {
          if ($0 ~ /\][[:space:]]*(#.*)?$/) {
            skipping_status_line = 0
          }
          next
        }

        if ($0 ~ /^[[:space:]]*\[[^]]+\][[:space:]]*(#.*)?$/) {
          if ($0 ~ /^[[:space:]]*\[tui\][[:space:]]*(#.*)?$/) {
            in_tui = 1
            found_tui = 1
            print
            emit_managed_settings()
            next
          }

          in_tui = 0
        }

        if (in_tui && $0 ~ /^[[:space:]]*status_line[[:space:]]*=/) {
          if ($0 !~ /\][[:space:]]*(#.*)?$/) {
            skipping_status_line = 1
          }
          next
        }

        if (in_tui && $0 ~ /^[[:space:]]*status_line_use_colors[[:space:]]*=/) {
          next
        }

        print
      }

      END {
        if (!found_tui) {
          if (NR > 0) {
            print ""
          }
          print "[tui]"
          emit_managed_settings()
        }
      }
    ' "$input" >"$temporary"; then
    rm -f "$temporary"
    return 1
  fi

  if [[ -f "$target" ]] && cmp -s "$temporary" "$target"; then
    rm -f "$temporary"
    echo "OK: $target (Codex TUI settings)"
    return
  fi

  if ! mv "$temporary" "$target"; then
    rm -f "$temporary"
    return 1
  fi

  echo "UPDATE: $target (Codex TUI settings)"
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
validate_codex_tui_settings

mkdir -p \
  "$HOME/.agents" \
  "$HOME/.codex" \
  "$HOME/.codex/rules" \
  "$HOME/.claude"

failed=0
validate_link_target \
  "$GLOBAL_INSTRUCTIONS" \
  "$HOME/.codex/AGENTS.md" || failed=1
validate_link_target \
  "$GLOBAL_INSTRUCTIONS" \
  "$HOME/.claude/CLAUDE.md" || failed=1
validate_skill_links_target "$HOME/.agents/skills" || failed=1
validate_skill_links_target "$HOME/.claude/skills" || failed=1
validate_link_target \
  "$CLAUDE_STATUS_LINE" \
  "$HOME/.claude/statusline-command.sh" || failed=1
validate_link_target \
  "$CODEX_SHARED_RULES" \
  "$HOME/.codex/rules/shared.rules" || failed=1
validate_codex_config_target || failed=1
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
# Link each canonical skill so unrelated local skills remain untouched.
install_skill_links "$HOME/.agents/skills"
install_skill_links "$HOME/.claude/skills"

# Agent-specific configuration that remains canonical in this repository.
install_link \
  "$CLAUDE_STATUS_LINE" \
  "$HOME/.claude/statusline-command.sh"

install_link \
  "$CODEX_SHARED_RULES" \
  "$HOME/.codex/rules/shared.rules"

# Codex keeps machine-local state in config.toml, so only the centrally managed
# TUI keys are reconciled instead of linking the complete file.
sync_codex_tui_settings

echo
echo "Done."
echo
echo "Canonical instructions:"
echo "  $GLOBAL_INSTRUCTIONS"
echo
echo "Canonical skills:"
echo "  $SKILLS"
echo
echo "Canonical Claude status line:"
echo "  $CLAUDE_STATUS_LINE"
echo
echo "Canonical Codex TUI settings:"
echo "  $CODEX_TUI_SETTINGS"
echo
echo "Canonical Codex command policy:"
echo "  $CODEX_SHARED_RULES"
