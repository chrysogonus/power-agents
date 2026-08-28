#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOBAL_INSTRUCTIONS="$ROOT/instructions/general-global.md"
SKILLS="$ROOT/skills"
CLAUDE_SETTINGS="$ROOT/settings/claude/settings.json"
CLAUDE_STATUS_LINE="$ROOT/settings/claude/statusline-command.sh"
CODEX_TUI_SETTINGS="$ROOT/settings/codex/tui.toml"
CODEX_SHARED_RULES="$ROOT/policies/codex/shared.rules"
CODEX_CONFIG_RECONCILER="$ROOT/scripts/reconcile-codex-config.py"
SKILL_VALIDATOR="$ROOT/scripts/validate-skills.py"
AGENTS_ROOT="$HOME/.agents"
CODEX_ROOT="${CODEX_HOME:-$HOME/.codex}"
CLAUDE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_STATUS_LINE_COMMAND="$CLAUDE_ROOT/statusline-command.sh"
TRANSACTION_DIR=""
# shellcheck disable=SC2034 # Read by the ERR trap at runtime.
TRANSACTION_ACTIVE=0
declare -a ROLLBACK_TYPES=()
declare -a ROLLBACK_PATHS=()
declare -a ROLLBACK_VALUES=()

cleanup_transaction() {
  if [[ -n "$TRANSACTION_DIR" && -d "$TRANSACTION_DIR" ]]; then
    if ! rm -rf -- "$TRANSACTION_DIR"; then
      echo "WARNING: Could not remove installer transaction directory: $TRANSACTION_DIR" >&2
    fi
  fi
}
trap cleanup_transaction EXIT

record_rollback() {
  ROLLBACK_TYPES+=("$1")
  ROLLBACK_PATHS+=("$2")
  ROLLBACK_VALUES+=("${3:-}")
}

rollback_installation() {
  local failed=0
  local index
  local path
  local type
  local value

  for ((index = ${#ROLLBACK_TYPES[@]} - 1; index >= 0; index--)); do
    type="${ROLLBACK_TYPES[index]}"
    path="${ROLLBACK_PATHS[index]}"
    value="${ROLLBACK_VALUES[index]}"

    case "$type" in
      remove-path)
        if [[ -e "$path" || -L "$path" ]]; then
          rm -f -- "$path" || failed=1
        fi
        ;;
      remove-directory)
        if [[ -d "$path" && ! -L "$path" ]]; then
          rmdir -- "$path" || failed=1
        fi
        ;;
      restore-file)
        cp -p -- "$value" "$path" || failed=1
        ;;
      restore-symlink)
        if [[ -e "$path" || -L "$path" ]]; then
          rm -f -- "$path" || failed=1
        fi
        ln -s -- "$value" "$path" || failed=1
        ;;
      *)
        echo "WARNING: Unknown rollback action: $type" >&2
        failed=1
        ;;
    esac
  done

  return "$failed"
}

installation_failed() {
  local status="$1"

  trap - ERR
  echo "ERROR: Installation failed; restoring previous configuration." >&2
  if ! rollback_installation; then
    echo "ERROR: Rollback was incomplete; inspect the paths reported above." >&2
  fi
  TRANSACTION_ACTIVE=0
  exit "$status"
}

handle_error() {
  local status="$1"

  if ((TRANSACTION_ACTIVE)); then
    installation_failed "$status"
  fi
  return "$status"
}

trap 'handle_error "$?"' ERR

handle_signal() {
  local status="$1"

  trap - HUP INT TERM
  if ((TRANSACTION_ACTIVE)); then
    installation_failed "$status"
  fi
  exit "$status"
}

trap 'handle_signal 129' HUP
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM

validate_install_root() {
  local label="$1"
  local path="$2"

  if [[ "$path" != /* || "$path" == "/" ]]; then
    echo "ERROR: $label must be an absolute directory other than /: $path" >&2
    return 1
  fi
}

validate_distinct_install_roots() {
  if [[ "$AGENTS_ROOT" == "$CODEX_ROOT" || \
    "$AGENTS_ROOT" == "$CLAUDE_ROOT" || \
    "$CODEX_ROOT" == "$CLAUDE_ROOT" ]]; then
    echo "ERROR: Shared, Codex, and Claude configuration roots must be distinct." >&2
    return 1
  fi
}

ensure_directory() {
  local parent
  local path="$1"

  if [[ -d "$path" ]]; then
    return
  fi

  if [[ -e "$path" || -L "$path" ]]; then
    echo "ERROR: Cannot create configuration directory over existing path: $path" >&2
    return 1
  fi

  parent="${path%/*}"
  if [[ -n "$parent" && "$parent" != "$path" && ! -d "$parent" ]]; then
    ensure_directory "$parent"
  fi

  record_rollback remove-directory "$path"
  if ! mkdir -- "$path"; then
    echo "ERROR: Could not create configuration directory: $path" >&2
    return 1
  fi
}

for command in jq python3; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $command" >&2
    exit 1
  fi
done

if ! python3 -c 'import tomlkit' >/dev/null 2>&1; then
  echo "ERROR: Required Python module not found: tomlkit" >&2
  echo "       See README.md#installation for setup instructions." >&2
  exit 1
fi

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "ERROR: Required Python module not found: yaml (PyYAML)" >&2
  echo "       See README.md#installation for setup instructions." >&2
  exit 1
fi

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

if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
  echo "ERROR: Missing $CLAUDE_SETTINGS" >&2
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

if [[ ! -f "$CODEX_CONFIG_RECONCILER" ]]; then
  echo "ERROR: Missing $CODEX_CONFIG_RECONCILER" >&2
  exit 1
fi

if [[ ! -f "$SKILL_VALIDATOR" ]]; then
  echo "ERROR: Missing $SKILL_VALIDATOR" >&2
  exit 1
fi

validate_skills() {
  if ! python3 "$SKILL_VALIDATOR" "$SKILLS"; then
    echo "ERROR: Skill validation failed: $SKILLS" >&2
    return 1
  fi
}

validate_codex_tui_settings() {
  if ! python3 "$CODEX_CONFIG_RECONCILER" \
    validate-managed "$CODEX_TUI_SETTINGS"; then
    echo "ERROR: Invalid Codex TUI settings fragment: $CODEX_TUI_SETTINGS" >&2
    echo "       Expected one [tui] section with status_line and status_line_use_colors." >&2
    return 1
  fi
}

validate_claude_settings() {
  if ! jq -e '
    type == "object" and
    keys == ["statusLine"] and
    .statusLine == {
      "type": "command",
      "command": "~/.claude/statusline-command.sh"
    }
  ' "$CLAUDE_SETTINGS" >/dev/null 2>&1; then
    echo "ERROR: Invalid Claude settings fragment: $CLAUDE_SETTINGS" >&2
    echo "       Expected only the managed statusLine command." >&2
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

  record_rollback remove-path "$target"
  if ! ln -s -- "$source" "$target"; then
    echo "ERROR: Could not create symlink: $target" >&2
    return 1
  fi
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
  local expected_target
  local previous_target
  local skill_link
  local skill_dir
  local skill_name
  local target_root="$1"

  if [[ -L "$target_root" && "$target_root" -ef "$SKILLS" ]]; then
    previous_target="$(readlink "$target_root")"
    record_rollback restore-symlink "$target_root" "$previous_target"
    if ! unlink "$target_root"; then
      echo "ERROR: Could not migrate legacy skill link: $target_root" >&2
      return 1
    fi
    echo "MIGRATE: $target_root (per-skill links)"
  fi

  ensure_directory "$target_root"

  for skill_link in "$target_root"/*; do
    [[ -L "$skill_link" ]] || continue
    skill_name="$(basename "$skill_link")"
    expected_target="$SKILLS/$skill_name"
    [[ ! -e "$expected_target" ]] || continue
    [[ "$(readlink "$skill_link")" == "$expected_target" ]] || continue

    previous_target="$(readlink "$skill_link")"
    record_rollback restore-symlink "$skill_link" "$previous_target"
    if ! unlink "$skill_link"; then
      echo "ERROR: Could not remove stale skill link: $skill_link" >&2
      return 1
    fi
    echo "REMOVE: $skill_link (stale repository skill link)"
  done

  for skill_dir in "$SKILLS"/*; do
    [[ -d "$skill_dir" ]] || continue
    install_link \
      "$skill_dir" \
      "$target_root/$(basename "$skill_dir")"
  done
}

validate_claude_settings_target() {
  local target="$CLAUDE_ROOT/settings.json"

  if [[ -L "$target" ]]; then
    echo "ERROR: Refusing to update symlinked Claude settings: $target" >&2
    echo "       Replace it with a regular file so local settings can be preserved." >&2
    return 1
  fi

  if [[ -e "$target" && ! -f "$target" ]]; then
    echo "ERROR: Claude settings are not a regular file: $target" >&2
    return 1
  fi

  [[ -f "$target" ]] || return 0

  if ! jq -e 'type == "object"' "$target" >/dev/null 2>&1; then
    echo "ERROR: Invalid Claude settings JSON: $target" >&2
    echo "       Fix the file before installing so local settings can be preserved." >&2
    return 1
  fi
}

prepare_claude_settings() {
  local output="$1"
  local source="$CLAUDE_SETTINGS"
  local target="$CLAUDE_ROOT/settings.json"
  local input="/dev/null"

  if [[ -f "$target" ]]; then
    input="$target"
  fi

  if ! jq -s --arg command "$CLAUDE_STATUS_LINE_COMMAND" '
    reduce .[] as $settings ({}; . + $settings) |
    .statusLine.command = $command
  ' "$input" "$source" >"$output"; then
    echo "ERROR: Could not prepare Claude settings for $target" >&2
    return 1
  fi

  if ! jq -e '
    type == "object" and
    .statusLine == {
      "type": "command",
      "command": $command
    }
  ' --arg command "$CLAUDE_STATUS_LINE_COMMAND" "$output" >/dev/null; then
    echo "ERROR: Prepared invalid Claude settings for $target" >&2
    return 1
  fi
}

validate_codex_config_target() {
  local target="$CODEX_ROOT/config.toml"

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

  if ! python3 "$CODEX_CONFIG_RECONCILER" validate-config "$target"; then
    echo "ERROR: Invalid or unsupported Codex config: $target" >&2
    echo "       Fix the file before installing so local settings can be preserved." >&2
    return 1
  fi
}

prepare_codex_tui_settings() {
  local output="$1"
  local source="$CODEX_TUI_SETTINGS"
  local target="$CODEX_ROOT/config.toml"
  local input="/dev/null"

  if [[ -f "$target" ]]; then
    input="$target"
  fi

  if ! python3 "$CODEX_CONFIG_RECONCILER" \
    reconcile "$source" "$input" "$output"; then
    echo "ERROR: Could not prepare Codex config for $target" >&2
    return 1
  fi
}

stage_managed_file() {
  local candidate="$1"
  local target="$2"
  local result_variable="$3"
  local temporary

  if ! temporary="$(mktemp "${target}.tmp.XXXXXX")"; then
    echo "ERROR: Could not create temporary file for $target" >&2
    return 1
  fi
  record_rollback remove-path "$temporary"

  if [[ -f "$target" ]] && ! cp -p -- "$target" "$temporary"; then
    echo "ERROR: Could not preserve metadata for $target" >&2
    return 1
  fi

  if ! cp -- "$candidate" "$temporary"; then
    echo "ERROR: Could not stage managed settings for $target" >&2
    return 1
  fi

  printf -v "$result_variable" '%s' "$temporary"
}

activate_managed_file() {
  local label="$1"
  local staged="$2"
  local target="$3"
  local backup

  if [[ -f "$target" ]] && cmp -s "$staged" "$target"; then
    if ! rm -f -- "$staged"; then
      echo "ERROR: Could not remove unchanged temporary file for $target" >&2
      return 1
    fi
    echo "OK: $target ($label)"
    return
  fi

  if [[ -f "$target" ]]; then
    backup="$TRANSACTION_DIR/backup-${#ROLLBACK_TYPES[@]}"
    if ! cp -p -- "$target" "$backup"; then
      echo "ERROR: Could not back up $target" >&2
      return 1
    fi
    record_rollback restore-file "$target" "$backup"
  else
    record_rollback remove-path "$target"
  fi

  if ! mv -- "$staged" "$target"; then
    echo "ERROR: Could not activate managed settings: $target" >&2
    return 1
  fi

  echo "UPDATE: $target ($label)"
}

validate_legacy_codex_skills() {
  local legacy_root="$CODEX_ROOT/skills"
  local legacy_skill
  local failed=0
  local skill_dir

  [[ -d "$legacy_root" ]] || return 0

  for skill_dir in "$SKILLS"/*; do
    [[ -d "$skill_dir" ]] || continue
    legacy_skill="$legacy_root/$(basename "$skill_dir")"

    if [[ -e "$legacy_skill" || -L "$legacy_skill" ]]; then
      echo "ERROR: Duplicate Codex skill exists: $legacy_skill" >&2
      echo "       Codex reads the canonical skill through $AGENTS_ROOT/skills." >&2
      failed=1
    fi
  done

  return "$failed"
}

validate_skills
validate_claude_settings
validate_codex_tui_settings
validate_install_root "HOME" "$HOME"
validate_install_root "Codex configuration root" "$CODEX_ROOT"
validate_install_root "Claude configuration root" "$CLAUDE_ROOT"
validate_distinct_install_roots

failed=0
validate_link_target \
  "$GLOBAL_INSTRUCTIONS" \
  "$CODEX_ROOT/AGENTS.md" || failed=1
validate_link_target \
  "$GLOBAL_INSTRUCTIONS" \
  "$CLAUDE_ROOT/CLAUDE.md" || failed=1
validate_skill_links_target "$AGENTS_ROOT/skills" || failed=1
validate_skill_links_target "$CLAUDE_ROOT/skills" || failed=1
validate_link_target \
  "$CLAUDE_STATUS_LINE" \
  "$CLAUDE_ROOT/statusline-command.sh" || failed=1
validate_claude_settings_target || failed=1
validate_link_target \
  "$CODEX_SHARED_RULES" \
  "$CODEX_ROOT/rules/shared.rules" || failed=1
validate_codex_config_target || failed=1
validate_legacy_codex_skills || failed=1

if ((failed)); then
  exit 1
fi

if ! TRANSACTION_DIR="$(mktemp -d "${TMPDIR:-/tmp}/power-agents-install.XXXXXX")"; then
  echo "ERROR: Could not create installer transaction directory." >&2
  exit 1
fi
TRANSACTION_ACTIVE=1

claude_candidate="$TRANSACTION_DIR/claude-settings.json"
codex_candidate="$TRANSACTION_DIR/codex-config.toml"
prepare_claude_settings "$claude_candidate"
prepare_codex_tui_settings "$codex_candidate"

ensure_directory "$AGENTS_ROOT"
ensure_directory "$CODEX_ROOT"
ensure_directory "$CODEX_ROOT/rules"
ensure_directory "$CLAUDE_ROOT"

claude_staged=""
codex_staged=""
stage_managed_file \
  "$claude_candidate" \
  "$CLAUDE_ROOT/settings.json" \
  claude_staged
stage_managed_file \
  "$codex_candidate" \
  "$CODEX_ROOT/config.toml" \
  codex_staged

echo
echo "Installing global agent configuration..."
echo

# Shared instructions.
install_link \
  "$GLOBAL_INSTRUCTIONS" \
  "$CODEX_ROOT/AGENTS.md"

install_link \
  "$GLOBAL_INSTRUCTIONS" \
  "$CLAUDE_ROOT/CLAUDE.md"

# Codex discovers ~/.agents/skills. Claude Code discovers skills in its selected
# configuration root. Link each canonical skill so unrelated local skills remain
# untouched.
install_skill_links "$AGENTS_ROOT/skills"
install_skill_links "$CLAUDE_ROOT/skills"

# Agent-specific configuration that remains canonical in this repository.
install_link \
  "$CLAUDE_STATUS_LINE" \
  "$CLAUDE_ROOT/statusline-command.sh"

# Claude keeps machine-local state in settings.json, so only the centrally
# managed statusLine key is reconciled.
activate_managed_file \
  "Claude managed settings" \
  "$claude_staged" \
  "$CLAUDE_ROOT/settings.json"

install_link \
  "$CODEX_SHARED_RULES" \
  "$CODEX_ROOT/rules/shared.rules"

# Codex keeps machine-local state in config.toml, so only the centrally managed
# TUI keys are reconciled instead of linking the complete file.
activate_managed_file \
  "Codex TUI settings" \
  "$codex_staged" \
  "$CODEX_ROOT/config.toml"

TRANSACTION_ACTIVE=0

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
echo "Canonical Claude settings:"
echo "  $CLAUDE_SETTINGS"
echo
echo "Canonical Codex TUI settings:"
echo "  $CODEX_TUI_SETTINGS"
echo
echo "Canonical Codex command policy:"
echo "  $CODEX_SHARED_RULES"
