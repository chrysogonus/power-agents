#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOBAL_INSTRUCTIONS="$ROOT/instructions/general-global.md"
SKILLS="$ROOT/skills"
CLAUDE_SETTINGS="$ROOT/settings/claude/settings.json"
CLAUDE_STATUS_LINE="$ROOT/settings/claude/statusline-command.sh"
CLAUDE_HOOKS="$ROOT/settings/claude/hooks.json"
CODEX_TUI_SETTINGS="$ROOT/settings/codex/tui.toml"
CODEX_HOOKS="$ROOT/settings/codex/hooks.json"
CODEX_SHARED_RULES="$ROOT/policies/codex/shared.rules"
CODEX_CONFIG_RECONCILER="$ROOT/scripts/reconcile-codex-config.py"
HOOKS_RECONCILER="$ROOT/scripts/reconcile-hooks.py"
VERIFY_GATE="$ROOT/hooks/verify-gate.py"
SKILL_VALIDATOR="$ROOT/scripts/validate-skills.py"
INSTALL_HOME="$HOME"
AGENTS_ROOT=""
CODEX_ROOT="${CODEX_HOME:-$HOME/.codex}"
CLAUDE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_STATUS_LINE_COMMAND=""
VERIFY_GATE_COMMAND=""
# The verify gate is always installed; these components are optional.
ALL_COMPONENTS="instructions,skills,statusline,codex-rules"
COMPONENTS_FILE=""
CODEX_TUI_SNAPSHOT=""
REQUESTED_COMPONENTS=""
COMPONENTS_REQUESTED=0
UNINSTALL=0
PREVIOUS_COMPONENTS=""
SELECTED_COMPONENTS=""
CODEX_CONFIG_MODE=""
CODEX_TUI_SOURCE=""
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

usage() {
  cat <<'EOF'
Usage: ./install.sh [--components LIST]
       ./install.sh --uninstall

Installs the verify gate for Codex and Claude Code. LIST selects optional
components: a comma-separated subset of instructions, skills, statusline, and
codex-rules, or "all" or "none". Without --components, the selection saved by
the previous install is reused.

--uninstall removes the verify gate and every component this checkout
installed, and keeps all other settings.
EOF
}

while (($#)); do
  case "$1" in
    --components)
      if (($# < 2)); then
        echo "ERROR: --components requires a list." >&2
        usage >&2
        exit 2
      fi
      REQUESTED_COMPONENTS="$2"
      COMPONENTS_REQUESTED=1
      shift 2
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ((UNINSTALL)); then
  if ((COMPONENTS_REQUESTED)); then
    echo "ERROR: --uninstall cannot be combined with --components." >&2
    exit 2
  fi
  REQUESTED_COMPONENTS="none"
  COMPONENTS_REQUESTED=1
fi

# Prints the components named in a list, in canonical order.
normalize_components() {
  local list="${1// /}"
  local name
  local -a names
  local -a result=()

  case "$list" in
    all) list="$ALL_COMPONENTS" ;;
    none) list="" ;;
  esac

  IFS=, read -r -a names <<<"$list"
  for name in "${names[@]}"; do
    if [[ -n "$name" && ",$ALL_COMPONENTS," != *",$name,"* ]]; then
      echo "ERROR: Unknown component: $name" >&2
      echo "       Choose from $ALL_COMPONENTS, all, or none." >&2
      return 1
    fi
  done

  IFS=, read -r -a names <<<"$ALL_COMPONENTS"
  for name in "${names[@]}"; do
    if [[ ",$list," == *",$name,"* ]]; then
      result+=("$name")
    fi
  done
  (IFS=,; printf '%s\n' "${result[*]}")
}

has_component() {
  [[ ",$SELECTED_COMPONENTS," == *",$1,"* ]]
}

# True when a component was installed before and is now deselected.
dropping_component() {
  [[ ",$PREVIOUS_COMPONENTS," == *",$1,"* ]] && ! has_component "$1"
}

links_to() {
  [[ -L "$2" && "$2" -ef "$1" ]]
}

skills_installed() {
  local root
  local skill_dir

  for root in "$AGENTS_ROOT/skills" "$CLAUDE_ROOT/skills"; do
    links_to "$SKILLS" "$root" && return 0
    for skill_dir in "$SKILLS"/*; do
      links_to "$skill_dir" "$root/${skill_dir##*/}" && return 0
    done
  done
  return 1
}

# Prints the saved selection, failing when it was saved for other agent roots.
read_saved_components() {
  local claude=""
  local codex=""
  local components=""
  local line

  while IFS= read -r line; do
    case "$line" in
      components=*) components="${line#components=}" ;;
      codex_root=*) codex="${line#codex_root=}" ;;
      claude_root=*) claude="${line#claude_root=}" ;;
    esac
  done <"$COMPONENTS_FILE"

  [[ "$codex" == "$CODEX_ROOT" && "$claude" == "$CLAUDE_ROOT" ]] || return 1
  printf '%s\n' "$components"
}

# Without a saved selection for these roots, the links already present stand
# in for one. Installs from before component selection linked everything.
detect_installed_components() {
  local detected=""

  if links_to "$GLOBAL_INSTRUCTIONS" "$CODEX_ROOT/AGENTS.md" ||
    links_to "$GLOBAL_INSTRUCTIONS" "$CLAUDE_ROOT/CLAUDE.md"; then
    detected+=",instructions"
  fi
  if skills_installed; then
    detected+=",skills"
  fi
  if links_to "$CLAUDE_STATUS_LINE" "$CLAUDE_ROOT/statusline-command.sh"; then
    detected+=",statusline"
  fi
  if links_to "$CODEX_SHARED_RULES" "$CODEX_ROOT/rules/shared.rules"; then
    detected+=",codex-rules"
  fi
  printf '%s\n' "${detected#,}"
}

canonicalize_install_root() {
  local label="$1"
  local path="$2"
  local result_variable="$3"
  local canonical

  if [[ "$path" != /* ]]; then
    echo "ERROR: $label must be an absolute directory other than /: $path" >&2
    return 1
  fi

  if ! canonical="$(realpath -m -- "$path")"; then
    echo "ERROR: Could not resolve $label: $path" >&2
    return 1
  fi

  if [[ "$canonical" == "/" ]]; then
    echo "ERROR: $label must be an absolute directory other than /: $path" >&2
    return 1
  fi

  printf -v "$result_variable" '%s' "$canonical"
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

for command in jq python3 realpath; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $command" >&2
    exit 1
  fi
done

canonicalize_install_root "HOME" "$INSTALL_HOME" INSTALL_HOME
canonicalize_install_root \
  "Codex configuration root" "$CODEX_ROOT" CODEX_ROOT
canonicalize_install_root \
  "Claude configuration root" "$CLAUDE_ROOT" CLAUDE_ROOT
AGENTS_ROOT="$INSTALL_HOME/.agents"
canonicalize_install_root \
  "Shared configuration root" "$AGENTS_ROOT" AGENTS_ROOT
CLAUDE_STATUS_LINE_COMMAND="$CLAUDE_ROOT/statusline-command.sh"
VERIFY_GATE_COMMAND="$AGENTS_ROOT/hooks/verify-gate.py"
COMPONENTS_FILE="$INSTALL_HOME/.config/power-agents/components"
# The Codex TUI values the last statusline install wrote, so removal can tell
# them apart from user values after settings/codex/tui.toml changes.
CODEX_TUI_SNAPSHOT="$INSTALL_HOME/.config/power-agents/codex-tui.toml"

for state_file in "$COMPONENTS_FILE" "$CODEX_TUI_SNAPSHOT"; do
  if [[ -L "$state_file" ]] ||
    [[ -e "$state_file" && ! -f "$state_file" ]]; then
    echo "ERROR: Installer state is not a regular file: $state_file" >&2
    exit 1
  fi
done

saved_for_roots=0
if [[ -f "$COMPONENTS_FILE" ]] && saved_components="$(read_saved_components)"; then
  saved_for_roots=1
  PREVIOUS_COMPONENTS="$(normalize_components "$saved_components")" || {
    echo "ERROR: Invalid component selection: $COMPONENTS_FILE" >&2
    echo "       Fix or delete it; without it, installed components are detected." >&2
    exit 1
  }
else
  PREVIOUS_COMPONENTS="$(detect_installed_components)"
fi

if ((COMPONENTS_REQUESTED)); then
  SELECTED_COMPONENTS="$(normalize_components "$REQUESTED_COMPONENTS")" ||
    exit 2
else
  SELECTED_COMPONENTS="$PREVIOUS_COMPONENTS"
fi

# Codex config.toml is touched only to add the status line or to remove the
# one a previous install added. Its keys carry no proof of ownership, unlike
# links, so removal needs a selection saved for these exact roots and the
# values that install wrote.
if has_component statusline; then
  CODEX_CONFIG_MODE="reconcile"
  CODEX_TUI_SOURCE="$CODEX_TUI_SETTINGS"
elif dropping_component statusline && ((saved_for_roots)) &&
  [[ -f "$CODEX_TUI_SNAPSHOT" && -f "$CODEX_ROOT/config.toml" ]]; then
  CODEX_CONFIG_MODE="remove"
  CODEX_TUI_SOURCE="$CODEX_TUI_SNAPSHOT"
fi

if [[ -n "$CODEX_CONFIG_MODE" ]] &&
  ! python3 -c 'import tomlkit' >/dev/null 2>&1; then
  echo "ERROR: Required Python module not found: tomlkit" >&2
  echo "       See README.md#installation for setup instructions." >&2
  exit 1
fi

if has_component skills && ! python3 -c 'import yaml' >/dev/null 2>&1; then
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

for required_file in \
  "$CLAUDE_HOOKS" "$CODEX_HOOKS" "$HOOKS_RECONCILER" "$VERIFY_GATE"; do
  if [[ ! -f "$required_file" ]]; then
    echo "ERROR: Missing $required_file" >&2
    exit 1
  fi
done

validate_skills() {
  if ! python3 "$SKILL_VALIDATOR" "$SKILLS"; then
    echo "ERROR: Skill validation failed: $SKILLS" >&2
    return 1
  fi
}

validate_codex_tui_settings() {
  if ! python3 "$CODEX_CONFIG_RECONCILER" \
    validate-managed "$CODEX_TUI_SOURCE"; then
    echo "ERROR: Invalid Codex TUI settings fragment: $CODEX_TUI_SOURCE" >&2
    echo "       Expected one [tui] section with status_line and status_line_use_colors." >&2
    return 1
  fi
}

validate_hook_fragments() {
  local fragment

  for fragment in "$CLAUDE_HOOKS" "$CODEX_HOOKS"; do
    if ! python3 "$HOOKS_RECONCILER" validate-managed "$fragment"; then
      echo "ERROR: Invalid managed hooks fragment: $fragment" >&2
      return 1
    fi
  done
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

    unlink_owned "$skill_link" "stale repository skill link"
  done

  for skill_dir in "$SKILLS"/*; do
    [[ -d "$skill_dir" ]] || continue
    install_link \
      "$skill_dir" \
      "$target_root/$(basename "$skill_dir")"
  done
}

unlink_owned() {
  local label="${2:-deselected component}"
  local target="$1"

  record_rollback restore-symlink "$target" "$(readlink "$target")"
  if ! unlink "$target"; then
    echo "ERROR: Could not remove link: $target" >&2
    return 1
  fi
  echo "REMOVE: $target ($label)"
}

remove_owned_link() {
  if links_to "$1" "$2"; then
    unlink_owned "$2"
  fi
}

# Removes only links that point into this checkout's skills directory.
remove_skill_links() {
  local skill_link
  local target_root="$1"

  if [[ -L "$target_root" ]]; then
    remove_owned_link "$SKILLS" "$target_root"
    return
  fi

  for skill_link in "$target_root"/*; do
    [[ -L "$skill_link" ]] || continue
    if [[ "$(readlink "$skill_link")" == "$SKILLS/${skill_link##*/}" ]]; then
      unlink_owned "$skill_link"
    fi
  done
}

# Writes INPUT to OUTPUT with the verify-gate hooks from SOURCE added, or
# removed when uninstalling.
reconcile_gate_hooks() {
  if ((UNINSTALL)); then
    python3 "$HOOKS_RECONCILER" remove "$2" "$3" --script "$VERIFY_GATE_COMMAND"
  else
    python3 "$HOOKS_RECONCILER" reconcile "$1" "$2" "$3" \
      --script "$VERIFY_GATE_COMMAND"
  fi
}

# True for settings files to reconcile: all of them on install, and only
# existing ones on uninstall, so that it creates none.
managed_target() {
  ! ((UNINSTALL)) || [[ -f "$1" ]]
}

remove_state_file() {
  local backup

  [[ -f "$1" ]] || return 0
  backup="$TRANSACTION_DIR/backup-${#ROLLBACK_TYPES[@]}"
  if ! cp -p -- "$1" "$backup"; then
    echo "ERROR: Could not back up $1" >&2
    return 1
  fi
  record_rollback restore-file "$1" "$backup"
  if ! rm -f -- "$1"; then
    echo "ERROR: Could not remove $1" >&2
    return 1
  fi
  echo "REMOVE: $1 (installer state)"
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

  if ! python3 "$HOOKS_RECONCILER" validate-config "$target"; then
    echo "ERROR: Invalid or unsupported Claude hooks: $target" >&2
    return 1
  fi
}

prepare_claude_settings() {
  local output="$1"
  local target="$CLAUDE_ROOT/settings.json"
  local input="/dev/null"
  local status_line_output="$output.status-line"
  local mode="keep"
  local -a sources

  if [[ -f "$target" ]]; then
    input="$target"
  fi
  sources=("$input")

  if has_component statusline; then
    mode="install"
    sources+=("$CLAUDE_SETTINGS")
  elif dropping_component statusline &&
    links_to "$CLAUDE_STATUS_LINE" "$CLAUDE_STATUS_LINE_COMMAND"; then
    mode="remove"
  fi

  # A deselected status line is removed while it still runs the repository
  # script through its link, which is removed with it.
  if ! jq -s --arg command "$CLAUDE_STATUS_LINE_COMMAND" --arg mode "$mode" '
    reduce .[] as $settings ({}; . + $settings) |
    if $mode == "install" then
      .statusLine.command = $command
    elif $mode == "remove" and
      (.statusLine | type == "object" and .command == $command) then
      del(.statusLine)
    else
      .
    end
  ' "${sources[@]}" >"$status_line_output"; then
    echo "ERROR: Could not prepare Claude settings for $target" >&2
    return 1
  fi

  if ! reconcile_gate_hooks "$CLAUDE_HOOKS" "$status_line_output" "$output"; then
    echo "ERROR: Could not prepare Claude hooks for $target" >&2
    return 1
  fi

  if ! jq -e '
    type == "object" and
    ($mode != "install" or .statusLine == {
      "type": "command",
      "command": $command
    })
  ' --arg command "$CLAUDE_STATUS_LINE_COMMAND" --arg mode "$mode" \
    "$output" >/dev/null; then
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
  local target="$CODEX_ROOT/config.toml"
  local input="/dev/null"

  if [[ -f "$target" ]]; then
    input="$target"
  fi

  if ! python3 "$CODEX_CONFIG_RECONCILER" \
    "$CODEX_CONFIG_MODE" "$CODEX_TUI_SOURCE" "$input" "$output"; then
    echo "ERROR: Could not prepare Codex config for $target" >&2
    return 1
  fi
}

validate_codex_hooks_target() {
  local target="$CODEX_ROOT/hooks.json"

  if [[ -L "$target" ]]; then
    echo "ERROR: Refusing to update symlinked Codex hooks: $target" >&2
    echo "       Replace it with a regular file so local hooks can be preserved." >&2
    return 1
  fi

  if [[ -e "$target" && ! -f "$target" ]]; then
    echo "ERROR: Codex hooks are not a regular file: $target" >&2
    return 1
  fi

  [[ -f "$target" ]] || return 0

  if ! python3 "$HOOKS_RECONCILER" validate-config "$target"; then
    echo "ERROR: Invalid or unsupported Codex hooks: $target" >&2
    echo "       Fix the file before installing so local hooks can be preserved." >&2
    return 1
  fi
}

prepare_codex_hooks() {
  local output="$1"
  local target="$CODEX_ROOT/hooks.json"
  local input="/dev/null"

  if [[ -f "$target" ]]; then
    input="$target"
  fi

  if ! reconcile_gate_hooks "$CODEX_HOOKS" "$input" "$output"; then
    echo "ERROR: Could not prepare Codex hooks for $target" >&2
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

if has_component skills; then
  validate_skills
fi
if has_component statusline; then
  validate_claude_settings
fi
if [[ -n "$CODEX_CONFIG_MODE" ]]; then
  validate_codex_tui_settings
fi
validate_hook_fragments
validate_distinct_install_roots

failed=0
if has_component instructions; then
  validate_link_target \
    "$GLOBAL_INSTRUCTIONS" \
    "$CODEX_ROOT/AGENTS.md" || failed=1
  validate_link_target \
    "$GLOBAL_INSTRUCTIONS" \
    "$CLAUDE_ROOT/CLAUDE.md" || failed=1
fi
if has_component skills; then
  validate_skill_links_target "$AGENTS_ROOT/skills" || failed=1
  validate_skill_links_target "$CLAUDE_ROOT/skills" || failed=1
  validate_legacy_codex_skills || failed=1
fi
if has_component statusline; then
  validate_link_target \
    "$CLAUDE_STATUS_LINE" \
    "$CLAUDE_ROOT/statusline-command.sh" || failed=1
fi
validate_claude_settings_target || failed=1
if has_component codex-rules; then
  validate_link_target \
    "$CODEX_SHARED_RULES" \
    "$CODEX_ROOT/rules/shared.rules" || failed=1
fi
if [[ -n "$CODEX_CONFIG_MODE" ]]; then
  validate_codex_config_target || failed=1
fi
validate_codex_hooks_target || failed=1
if ! ((UNINSTALL)); then
  validate_link_target \
    "$VERIFY_GATE" \
    "$VERIFY_GATE_COMMAND" || failed=1
fi

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
codex_hooks_candidate="$TRANSACTION_DIR/codex-hooks.json"
components_candidate="$TRANSACTION_DIR/components"
if managed_target "$CLAUDE_ROOT/settings.json"; then
  prepare_claude_settings "$claude_candidate"
fi
if [[ -n "$CODEX_CONFIG_MODE" ]]; then
  prepare_codex_tui_settings "$codex_candidate"
fi
if managed_target "$CODEX_ROOT/hooks.json"; then
  prepare_codex_hooks "$codex_hooks_candidate"
fi
printf 'components=%s\ncodex_root=%s\nclaude_root=%s\n' \
  "$SELECTED_COMPONENTS" "$CODEX_ROOT" "$CLAUDE_ROOT" >"$components_candidate"

if ! ((UNINSTALL)); then
  ensure_directory "$AGENTS_ROOT"
  ensure_directory "$AGENTS_ROOT/hooks"
  ensure_directory "$CODEX_ROOT"
  if has_component codex-rules; then
    ensure_directory "$CODEX_ROOT/rules"
  fi
  ensure_directory "$CLAUDE_ROOT"
  ensure_directory "${COMPONENTS_FILE%/*}"
fi

claude_staged=""
codex_staged=""
codex_hooks_staged=""
components_staged=""
snapshot_staged=""
if managed_target "$CLAUDE_ROOT/settings.json"; then
  stage_managed_file \
    "$claude_candidate" \
    "$CLAUDE_ROOT/settings.json" \
    claude_staged
fi
if [[ -n "$CODEX_CONFIG_MODE" ]]; then
  stage_managed_file \
    "$codex_candidate" \
    "$CODEX_ROOT/config.toml" \
    codex_staged
fi
if managed_target "$CODEX_ROOT/hooks.json"; then
  stage_managed_file \
    "$codex_hooks_candidate" \
    "$CODEX_ROOT/hooks.json" \
    codex_hooks_staged
fi
if has_component statusline; then
  stage_managed_file \
    "$CODEX_TUI_SETTINGS" \
    "$CODEX_TUI_SNAPSHOT" \
    snapshot_staged
fi
if ! ((UNINSTALL)); then
  stage_managed_file \
    "$components_candidate" \
    "$COMPONENTS_FILE" \
    components_staged
fi

echo
if ((UNINSTALL)); then
  echo "Removing global agent configuration..."
else
  echo "Installing global agent configuration..."
fi
echo

# Shared instructions.
if has_component instructions; then
  install_link \
    "$GLOBAL_INSTRUCTIONS" \
    "$CODEX_ROOT/AGENTS.md"

  install_link \
    "$GLOBAL_INSTRUCTIONS" \
    "$CLAUDE_ROOT/CLAUDE.md"
elif dropping_component instructions; then
  remove_owned_link "$GLOBAL_INSTRUCTIONS" "$CODEX_ROOT/AGENTS.md"
  remove_owned_link "$GLOBAL_INSTRUCTIONS" "$CLAUDE_ROOT/CLAUDE.md"
fi

# Codex discovers ~/.agents/skills. Claude Code discovers skills in its selected
# configuration root. Link each canonical skill so unrelated local skills remain
# untouched.
if has_component skills; then
  install_skill_links "$AGENTS_ROOT/skills"
  install_skill_links "$CLAUDE_ROOT/skills"
elif dropping_component skills; then
  remove_skill_links "$AGENTS_ROOT/skills"
  remove_skill_links "$CLAUDE_ROOT/skills"
fi

# Agent-specific configuration that remains canonical in this repository.
if has_component statusline; then
  install_link \
    "$CLAUDE_STATUS_LINE" \
    "$CLAUDE_ROOT/statusline-command.sh"
elif dropping_component statusline; then
  remove_owned_link "$CLAUDE_STATUS_LINE" "$CLAUDE_ROOT/statusline-command.sh"
fi

# Both agents' hook entries run the verify gate through this link.
if ((UNINSTALL)); then
  remove_owned_link "$VERIFY_GATE" "$VERIFY_GATE_COMMAND"
else
  install_link \
    "$VERIFY_GATE" \
    "$VERIFY_GATE_COMMAND"
fi

# Claude keeps machine-local state in settings.json, so only the centrally
# managed statusLine key and verify-gate hook entries are reconciled.
if [[ -n "$claude_staged" ]]; then
  activate_managed_file \
    "Claude managed settings" \
    "$claude_staged" \
    "$CLAUDE_ROOT/settings.json"
fi

if has_component codex-rules; then
  install_link \
    "$CODEX_SHARED_RULES" \
    "$CODEX_ROOT/rules/shared.rules"
elif dropping_component codex-rules; then
  remove_owned_link "$CODEX_SHARED_RULES" "$CODEX_ROOT/rules/shared.rules"
fi

# Codex keeps machine-local state in config.toml, so only the centrally managed
# TUI keys are reconciled instead of linking the complete file.
if [[ -n "$CODEX_CONFIG_MODE" ]]; then
  activate_managed_file \
    "Codex TUI settings" \
    "$codex_staged" \
    "$CODEX_ROOT/config.toml"
fi

# Codex hooks.json may hold local hooks, so only the verify-gate entries are
# reconciled instead of linking the complete file.
if [[ -n "$codex_hooks_staged" ]]; then
  activate_managed_file \
    "Codex verify-gate hooks" \
    "$codex_hooks_staged" \
    "$CODEX_ROOT/hooks.json"
fi

if has_component statusline; then
  activate_managed_file \
    "installed Codex TUI values" \
    "$snapshot_staged" \
    "$CODEX_TUI_SNAPSHOT"
fi

# Saved last so that a failed install leaves the previous selection in place.
if ((UNINSTALL)); then
  remove_state_file "$COMPONENTS_FILE"
  remove_state_file "$CODEX_TUI_SNAPSHOT"
else
  activate_managed_file \
    "component selection" \
    "$components_staged" \
    "$COMPONENTS_FILE"
fi

TRANSACTION_ACTIVE=0

if ((UNINSTALL)); then
  echo
  echo "Done. Removed the verify gate and all optional components."
  echo "Kept: the cross-review toggle in ${COMPONENTS_FILE%/*} and the gate's"
  echo "log in ${XDG_CACHE_HOME:-$INSTALL_HOME/.cache}/verify-gate."
  exit 0
fi

echo
echo "Done."
echo "Installed: verify gate${SELECTED_COMPONENTS:+, ${SELECTED_COMPONENTS//,/, }}"
echo "Change optional components with: ./install.sh --components LIST"
echo "Codex: trust the verify-gate hooks with /hooks in a new session."
echo
echo "Canonical verify gate:"
echo "  $VERIFY_GATE"
if has_component instructions; then
  echo
  echo "Canonical instructions:"
  echo "  $GLOBAL_INSTRUCTIONS"
fi
if has_component skills; then
  echo
  echo "Canonical skills:"
  echo "  $SKILLS"
fi
if has_component statusline; then
  echo
  echo "Canonical status lines:"
  echo "  $CLAUDE_STATUS_LINE"
  echo "  $CODEX_TUI_SETTINGS"
fi
if has_component codex-rules; then
  echo
  echo "Canonical Codex command policy:"
  echo "  $CODEX_SHARED_RULES"
fi
