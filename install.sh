#!/usr/bin/env bash
set -Eeuo pipefail

# Bash 4.4 is the first to expand empty arrays under set -u.
if ((BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] < 404)); then
  echo "ERROR: Bash 4.4 or newer is required; see README.md#installation." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOBAL_INSTRUCTIONS="$ROOT/instructions/general-global.md"
SKILLS="$ROOT/skills"
SKILL_EXTRAS="$SKILLS/extras.txt"
CLAUDE_SETTINGS="$ROOT/settings/claude/settings.json"
CLAUDE_STATUS_LINE="$ROOT/settings/claude/statusline-command.sh"
CLAUDE_HOOKS="$ROOT/settings/claude/hooks.json"
CLAUDE_GUARD_HOOKS="$ROOT/settings/claude/guards-hooks.json"
CLAUDE_PERMISSIONS="$ROOT/settings/claude/permissions.json"
GUARDS="$ROOT/hooks/guards"
CODEX_TUI_SETTINGS="$ROOT/settings/codex/tui.toml"
CODEX_HOOKS="$ROOT/settings/codex/hooks.json"
CODEX_PERMISSION_RULES="$ROOT/policies/codex/permissions.rules"
CODEX_SHARED_RULES="$ROOT/policies/codex/shared.rules"
CODEX_CONFIG_RECONCILER="$ROOT/scripts/reconcile-codex-config.py"
HOOKS_RECONCILER="$ROOT/scripts/reconcile-hooks.py"
VERIFY_GATE="$ROOT/hooks/verify-gate.py"
AGENT_HUB="$ROOT/hooks/agent-hub.py"
SKILL_VALIDATOR="$ROOT/scripts/validate-skills.py"
SUBAGENTS="$ROOT/subagents"
SUBAGENT_RENDERER="$ROOT/scripts/render-subagents.py"
INSTALL_HOME="$HOME"
AGENTS_ROOT=""
CODEX_ROOT="${CODEX_HOME:-$HOME/.codex}"
CLAUDE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_STATUS_LINE_COMMAND=""
VERIFY_GATE_COMMAND=""
GUARDS_LINK=""
AGENT_HUB_COMMAND=""
# The verify gate is always installed; these components are optional.
ALL_COMPONENTS="instructions,skills,skills-extra,statusline,codex-rules,guards,permissions,notify,context,format,subagents"
# Components whose hooks run the agent hub, from settings/<agent>/<component>-hooks.json.
HUB_COMPONENTS=(notify context format)
HUB_FRAGMENTS=()
for hub_component in "${HUB_COMPONENTS[@]}"; do
  HUB_FRAGMENTS+=("$ROOT/settings/claude/$hub_component-hooks.json"
    "$ROOT/settings/codex/$hub_component-hooks.json")
done
COMPONENTS_FILE=""
INSTRUCTIONS_OVERLAY=""
DISABLED_SKILLS_FILE=""
GENERATED_INSTRUCTIONS=""
AGENT_MODELS_OVERLAY=""
GENERATED_AGENTS=""
SUBAGENT_ROLES=","
INSTRUCTIONS_SOURCE=""
EXTRA_SKILLS=","
DISABLED_SKILLS=","
CODEX_TUI_SNAPSHOT=""
PERMISSIONS_SNAPSHOT=""
PERMISSIONS_MODE=""
PERMISSIONS_OWNED="/dev/null"
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
components: a comma-separated subset of instructions, skills, skills-extra,
statusline, codex-rules, guards, permissions, notify, context, format, and
subagents,
or "all" or "none".
Without --components, the selection saved by the previous install is reused.

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

# Codex skips symlinked rules files and refuses symlinked agent roles, so
# those are installed as copies whose first line marks them as this
# installer's and names EDIT, the repository file to change instead.
copy_marker() {
  printf '# Managed by power-agents. Edit %s in that repository and run ./install.sh.' "$1"
}

# True when TARGET is a copy this installer made, marked with EDIT.
is_managed_copy() {
  [[ -f "$1" && ! -L "$1" ]] &&
    [[ "$(head -n 1 -- "$1" 2>/dev/null)" == "$(copy_marker "$2")" ]]
}

# True when TARGET is this installer's copy of the rules file SOURCE, or the
# symlink earlier installs created.
owns_rules() {
  links_to "$1" "$2" || is_managed_copy "$2" "${1#"$ROOT"/}"
}

# True when TARGET, in Codex's agents directory, is this installer's copy of a
# generated role, or the symlink earlier installs created.
owns_codex_agent() {
  local name="${1##*/}"

  links_to_generated_agent "$1" || is_managed_copy "$1" "subagents/${name%.*}.md"
}

# True when NAME is listed in skills/extras.txt.
extra_skill() {
  [[ "$EXTRA_SKILLS" == *",$1,"* ]]
}

# True when the selected tiers include skill NAME and the overlay does not
# disable it.
skill_selected() {
  [[ "$DISABLED_SKILLS" != *",$1,"* ]] || return 1
  if extra_skill "$1"; then
    has_component skills-extra
  else
    has_component skills
  fi
}

# True when any skill of a tier (skills or skills-extra) is linked.
skill_tier_installed() {
  local name
  local root
  local skill_dir

  for root in "$AGENTS_ROOT/skills" "$CLAUDE_ROOT/skills"; do
    links_to "$SKILLS" "$root" && return 0
    for skill_dir in "$SKILLS"/*/; do
      name="$(basename "$skill_dir")"
      if extra_skill "$name"; then
        [[ "$1" == skills-extra ]] || continue
      else
        [[ "$1" == skills ]] || continue
      fi
      links_to "$skill_dir" "$root/$name" && return 0
    done
  done
  return 1
}

# True when a component whose hooks run the agent hub is selected.
hub_selected() {
  local component
  for component in "${HUB_COMPONENTS[@]}"; do
    if has_component "$component"; then
      return 0
    fi
  done
  return 1
}

# True when LINK points at a subagent file the installer generated.
links_to_generated_agent() {
  [[ -L "$1" && "$(readlink "$1")" == "$GENERATED_AGENTS/"* ]]
}

# The directory and file extension of AGENT's subagent definitions.
subagent_directory() {
  if [[ "$1" == claude ]]; then
    printf '%s\n' "$CLAUDE_ROOT/agents"
  else
    printf '%s\n' "$CODEX_ROOT/agents"
  fi
}

subagent_extension() {
  if [[ "$1" == claude ]]; then
    printf '%s\n' md
  else
    printf '%s\n' toml
  fi
}

# True when TARGET links to the shared instructions or the generated
# instructions, even when the generated file is missing.
links_to_instructions() {
  links_to "$GLOBAL_INSTRUCTIONS" "$1" || links_to "$GENERATED_INSTRUCTIONS" "$1" ||
    { [[ -L "$1" ]] && [[ "$(readlink "$1")" == "$GENERATED_INSTRUCTIONS" ]]; }
}

# Prints the names listed in FILE, one per line, skipping comments and blanks.
read_name_list() {
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    if [[ -n "$line" ]]; then
      printf '%s\n' "$line"
    fi
  done <"$1"
}

# Prints the saved selection, failing when it was saved for other agent roots.
read_saved_components() {
  local claude=""
  local codex=""
  local components=""
  local format=""
  local line

  while IFS= read -r line; do
    case "$line" in
      components=*) components="${line#components=}" ;;
      codex_root=*) codex="${line#codex_root=}" ;;
      claude_root=*) claude="${line#claude_root=}" ;;
      format=*) format="${line#format=}" ;;
    esac
  done <"$COMPONENTS_FILE"

  [[ "$codex" == "$CODEX_ROOT" && "$claude" == "$CLAUDE_ROOT" ]] || return 1
  # Before format 2, the skills component installed every skill.
  if [[ -z "$format" && ",$components," == *",skills,"* ]]; then
    components+=",skills-extra"
  fi
  printf '%s\n' "$components"
}

# Without a saved selection for these roots, the links already present stand
# in for one. Installs from before component selection linked everything.
detect_installed_components() {
  local detected=""

  if links_to_instructions "$CODEX_ROOT/AGENTS.md" ||
    links_to_instructions "$CLAUDE_ROOT/CLAUDE.md"; then
    detected+=",instructions"
  fi
  if skill_tier_installed skills; then
    detected+=",skills"
  fi
  if skill_tier_installed skills-extra; then
    detected+=",skills-extra"
  fi
  if links_to "$CLAUDE_STATUS_LINE" "$CLAUDE_ROOT/statusline-command.sh"; then
    detected+=",statusline"
  fi
  if owns_rules "$CODEX_SHARED_RULES" "$CODEX_ROOT/rules/shared.rules"; then
    detected+=",codex-rules"
  fi
  if links_to "$GUARDS" "$GUARDS_LINK"; then
    detected+=",guards"
  fi
  if owns_rules "$CODEX_PERMISSION_RULES" "$CODEX_ROOT/rules/permissions.rules"; then
    detected+=",permissions"
  fi
  for hub_component in "${HUB_COMPONENTS[@]}"; do
    for hooks_file in "$CLAUDE_ROOT/settings.json" "$CODEX_ROOT/hooks.json"; do
      if jq -e --arg command "python3 \"$AGENT_HUB_COMMAND\" $hub_component " '
        [.. | .command? | strings] | any(startswith($command))
      ' "$hooks_file" >/dev/null 2>&1; then
        detected+=",$hub_component"
        break
      fi
    done
  done
  for agent_link in "$CLAUDE_ROOT/agents"/* "$CODEX_ROOT/agents"/*; do
    if links_to_generated_agent "$agent_link" || owns_codex_agent "$agent_link"; then
      detected+=",subagents"
      break
    fi
  done
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
GUARDS_LINK="$AGENTS_ROOT/hooks/guards"
AGENT_HUB_COMMAND="$AGENTS_ROOT/hooks/agent-hub.py"
COMPONENTS_FILE="$INSTALL_HOME/.config/power-agents/components"
# The Codex TUI values the last statusline install wrote, so removal can tell
# them apart from user values after settings/codex/tui.toml changes.
CODEX_TUI_SNAPSHOT="$INSTALL_HOME/.config/power-agents/codex-tui.toml"
# The Claude permission rules the permissions component added, and the Claude
# root it added them to, so removal leaves rules the user wrote.
PERMISSIONS_SNAPSHOT="$INSTALL_HOME/.config/power-agents/claude-permissions.json"
# Personal overlay: instructions appended to the shared ones, and skills to
# leave out. Both belong to the user and may be symlinks.
INSTRUCTIONS_OVERLAY="$INSTALL_HOME/.config/power-agents/instructions.md"
DISABLED_SKILLS_FILE="$INSTALL_HOME/.config/power-agents/disabled-skills"
# The shared instructions followed by the overlay, written only while an
# overlay exists.
GENERATED_INSTRUCTIONS="$AGENTS_ROOT/instructions.md"
# Model names for the subagents, per agent and role; part of the overlay.
AGENT_MODELS_OVERLAY="$INSTALL_HOME/.config/power-agents/agent-models.json"
# Subagent definitions rendered from subagents/ and the model overlay, linked
# from each agent's agents directory.
GENERATED_AGENTS="$AGENTS_ROOT/agents"

for state_file in "$COMPONENTS_FILE" "$CODEX_TUI_SNAPSHOT" \
  "$GENERATED_INSTRUCTIONS" "$PERMISSIONS_SNAPSHOT"; do
  if [[ -L "$state_file" ]] ||
    [[ -e "$state_file" && ! -f "$state_file" ]]; then
    echo "ERROR: Installer state is not a regular file: $state_file" >&2
    exit 1
  fi
done

if [[ -e "$INSTRUCTIONS_OVERLAY" || -L "$INSTRUCTIONS_OVERLAY" ]] &&
  [[ ! -f "$INSTRUCTIONS_OVERLAY" || ! -r "$INSTRUCTIONS_OVERLAY" ]]; then
  echo "ERROR: Instructions overlay is not a regular file: $INSTRUCTIONS_OVERLAY" >&2
  exit 1
fi
if [[ -f "$INSTRUCTIONS_OVERLAY" ]]; then
  INSTRUCTIONS_SOURCE="$GENERATED_INSTRUCTIONS"
else
  INSTRUCTIONS_SOURCE="$GLOBAL_INSTRUCTIONS"
fi

if [[ ! -f "$SKILL_EXTRAS" ]]; then
  echo "ERROR: Missing $SKILL_EXTRAS" >&2
  exit 1
fi
mapfile -t extra_skill_names < <(read_name_list "$SKILL_EXTRAS")
for name in "${extra_skill_names[@]}"; do
  if [[ ! -d "$SKILLS/$name" ]]; then
    echo "ERROR: Unknown skill in $SKILL_EXTRAS: $name" >&2
    exit 1
  fi
  EXTRA_SKILLS+="$name,"
done

if [[ -e "$AGENT_MODELS_OVERLAY" || -L "$AGENT_MODELS_OVERLAY" ]] &&
  [[ ! -f "$AGENT_MODELS_OVERLAY" || ! -r "$AGENT_MODELS_OVERLAY" ]]; then
  echo "ERROR: Subagent models overlay is not a regular file: $AGENT_MODELS_OVERLAY" >&2
  exit 1
fi

for subagent_source in "$SUBAGENTS"/*.md; do
  [[ -f "$subagent_source" ]] || continue
  subagent_name="${subagent_source##*/}"
  SUBAGENT_ROLES+="${subagent_name%.md},"
done

if [[ -e "$DISABLED_SKILLS_FILE" || -L "$DISABLED_SKILLS_FILE" ]]; then
  if [[ ! -f "$DISABLED_SKILLS_FILE" || ! -r "$DISABLED_SKILLS_FILE" ]]; then
    echo "ERROR: Disabled skills list is not a regular file: $DISABLED_SKILLS_FILE" >&2
    exit 1
  fi
  mapfile -t disabled_skill_names < <(read_name_list "$DISABLED_SKILLS_FILE")
  for name in "${disabled_skill_names[@]}"; do
    if [[ ! -d "$SKILLS/$name" ]]; then
      echo "WARNING: Unknown skill in $DISABLED_SKILLS_FILE: $name" >&2
    fi
    DISABLED_SKILLS+="$name,"
  done
fi

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

# Claude permission rules are owned only through the snapshot of the rules an
# install added to this Claude root.
if [[ -f "$PERMISSIONS_SNAPSHOT" ]] && jq -e --arg root "$CLAUDE_ROOT" \
  '.claude_root == $root' "$PERMISSIONS_SNAPSHOT" >/dev/null 2>&1; then
  PERMISSIONS_OWNED="$PERMISSIONS_SNAPSHOT"
fi
if has_component permissions; then
  PERMISSIONS_MODE="install"
elif [[ "$PERMISSIONS_OWNED" != /dev/null ]]; then
  PERMISSIONS_MODE="remove"
fi

if [[ -n "$CODEX_CONFIG_MODE" ]] &&
  ! python3 -c 'import tomlkit' >/dev/null 2>&1; then
  echo "ERROR: Required Python module not found: tomlkit" >&2
  echo "       See README.md#installation for setup instructions." >&2
  exit 1
fi

if { has_component skills || has_component skills-extra; } &&
  ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "ERROR: Required Python module not found: yaml (PyYAML)" >&2
  echo "       See README.md#installation for setup instructions." >&2
  exit 1
fi

if has_component guards && ! command -v node >/dev/null 2>&1; then
  echo "ERROR: Required command not found: node (needed by the guards component)" >&2
  echo "       Install Node.js, or omit guards from --components." >&2
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
  "$CLAUDE_HOOKS" "$CLAUDE_GUARD_HOOKS" "$CODEX_HOOKS" "$HOOKS_RECONCILER" \
  "$VERIFY_GATE" "$GUARDS/protect-tests.js" "$GUARDS/protect-secrets.js" \
  "$CLAUDE_PERMISSIONS" "$CODEX_PERMISSION_RULES" "$AGENT_HUB" \
  "${HUB_FRAGMENTS[@]}"; do
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
  if ! python3 "$HOOKS_RECONCILER" validate-managed "$CLAUDE_GUARD_HOOKS" \
    --placeholder "@GUARDS@"; then
    echo "ERROR: Invalid managed hooks fragment: $CLAUDE_GUARD_HOOKS" >&2
    return 1
  fi
  for fragment in "${HUB_FRAGMENTS[@]}"; do
    if ! python3 "$HOOKS_RECONCILER" validate-managed "$fragment" \
      --placeholder "@AGENT_HUB@"; then
      echo "ERROR: Invalid managed hooks fragment: $fragment" >&2
      return 1
    fi
  done
}

# True when FILE's permissions, if any, hold only string lists in deny and ask.
valid_permissions() {
  jq -e '
    .permissions == null or (.permissions | type == "object" and
      all(.deny, .ask; . == null or (type == "array" and all(.[]; type == "string"))))
  ' "$1" >/dev/null 2>&1
}

validate_permission_sources() {
  if ! jq -e '(.permissions | keys) == ["ask", "deny"]' "$CLAUDE_PERMISSIONS" \
    >/dev/null 2>&1 || ! valid_permissions "$CLAUDE_PERMISSIONS"; then
    echo "ERROR: Invalid Claude permissions fragment: $CLAUDE_PERMISSIONS" >&2
    return 1
  fi
  if [[ "$PERMISSIONS_OWNED" != /dev/null ]] &&
    ! valid_permissions "$PERMISSIONS_OWNED"; then
    echo "ERROR: Invalid installer state: $PERMISSIONS_SNAPSHOT" >&2
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
    skill_selected "${skill_dir##*/}" || continue
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
    skill_link="$target_root/$(basename "$skill_dir")"
    if skill_selected "${skill_dir##*/}"; then
      install_link "$skill_dir" "$skill_link"
    elif links_to "$skill_dir" "$skill_link"; then
      unlink_owned "$skill_link" "unselected skill"
    fi
  done
}

# Links TARGET to the instructions source, replacing a link to the other one.
install_instructions_link() {
  if ! links_to "$INSTRUCTIONS_SOURCE" "$1" && links_to_instructions "$1"; then
    unlink_owned "$1" "instructions source changed"
  fi
  install_link "$INSTRUCTIONS_SOURCE" "$1"
}

remove_instructions_link() {
  if links_to_instructions "$1"; then
    unlink_owned "$1"
  fi
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

validate_rules_target() {
  if owns_rules "$1" "$2"; then
    return 0
  fi
  validate_link_target "$1" "$2"
}

# Installs SOURCE at TARGET as a copy marked with EDIT.
install_managed_copy() {
  local backup
  local edit="$3"
  local source="$1"
  local staged
  local target="$2"

  if ! staged="$(mktemp "${target}.tmp.XXXXXX")"; then
    echo "ERROR: Could not create temporary file for $target" >&2
    return 1
  fi
  record_rollback remove-path "$staged"
  if ! { copy_marker "$edit" && echo && cat -- "$source"; } >"$staged" ||
    ! chmod 644 -- "$staged"; then
    echo "ERROR: Could not stage copy: $target" >&2
    return 1
  fi

  if [[ -f "$target" && ! -L "$target" ]] && cmp -s "$staged" "$target"; then
    if ! rm -f -- "$staged"; then
      echo "ERROR: Could not remove unchanged temporary file for $target" >&2
      return 1
    fi
    echo "OK: $target"
    return
  fi

  if [[ -L "$target" ]]; then
    record_rollback restore-symlink "$target" "$(readlink "$target")"
  elif [[ -e "$target" ]]; then
    backup="$TRANSACTION_DIR/backup-${#ROLLBACK_TYPES[@]}"
    if ! cp -p -- "$target" "$backup"; then
      echo "ERROR: Could not back up $target" >&2
      return 1
    fi
    record_rollback restore-file "$target" "$backup"
  else
    record_rollback remove-path "$target"
  fi
  if ! mv -f -- "$staged" "$target"; then
    echo "ERROR: Could not install copy: $target" >&2
    return 1
  fi
  echo "COPY: $target <- $source"
}

# Removes TARGET, a managed copy or an earlier install's symlink.
remove_managed_copy() {
  local backup
  local label="${2:-deselected component}"
  local target="$1"

  if [[ -L "$target" ]]; then
    unlink_owned "$target" "$label"
    return
  fi
  backup="$TRANSACTION_DIR/backup-${#ROLLBACK_TYPES[@]}"
  if ! cp -p -- "$target" "$backup"; then
    echo "ERROR: Could not back up $target" >&2
    return 1
  fi
  record_rollback restore-file "$target" "$backup"
  if ! rm -f -- "$target"; then
    echo "ERROR: Could not remove copy: $target" >&2
    return 1
  fi
  echo "REMOVE: $target ($label)"
}

remove_owned_rules() {
  if owns_rules "$1" "$2"; then
    remove_managed_copy "$2"
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
    # The text match also catches links to skills since removed here.
    if links_to "$SKILLS/${skill_link##*/}" "$skill_link" ||
      [[ "$(readlink "$skill_link")" == "$SKILLS/${skill_link##*/}" ]]; then
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

# Writes INPUT to OUTPUT with the guard hooks added when the guards component
# is selected, and removed otherwise. The trailing slash keeps the match to
# commands inside this directory.
reconcile_guard_hooks() {
  if has_component guards; then
    python3 "$HOOKS_RECONCILER" reconcile "$CLAUDE_GUARD_HOOKS" "$1" "$2" \
      --script "$GUARDS_LINK/" --placeholder "@GUARDS@"
  else
    python3 "$HOOKS_RECONCILER" remove "$1" "$2" --script "$GUARDS_LINK/"
  fi
}

# Writes INPUT to OUTPUT with the agent hub hooks of the selected components
# added, from AGENT's fragments. Every hook entry that runs the agent hub is
# managed, so deselected components' entries are removed.
reconcile_hub_hooks() {
  local -a fragments=()
  local merged="$2.hub-fragment"
  local component

  for component in "${HUB_COMPONENTS[@]}"; do
    if has_component "$component"; then
      fragments+=("$ROOT/settings/$3/$component-hooks.json")
    fi
  done
  if ((${#fragments[@]} == 0)); then
    python3 "$HOOKS_RECONCILER" remove "$1" "$2" --script "$AGENT_HUB_COMMAND"
    return
  fi
  jq -s '{"hooks": (reduce (.[].hooks | to_entries[]) as $event ({};
    .[$event.key] += $event.value))}' "${fragments[@]}" >"$merged" &&
    python3 "$HOOKS_RECONCILER" reconcile "$merged" "$1" "$2" \
      --script "$AGENT_HUB_COMMAND" --placeholder "@AGENT_HUB@"
}

# Writes the Claude settings INPUT to OUTPUT with the permission rules the last
# install added replaced by the current ones, or removed, and writes the rules
# it added, which the user did not already have, to SNAPSHOT.
reconcile_permissions() {
  local wanted="/dev/null"
  local merged="$TRANSACTION_DIR/permissions-merged.json"

  if [[ "$PERMISSIONS_MODE" == install ]]; then
    wanted="$CLAUDE_PERMISSIONS"
  fi
  jq --slurpfile owned "$PERMISSIONS_OWNED" --slurpfile wanted "$wanted" \
    --arg root "$CLAUDE_ROOT" '
    reduce ("deny", "ask") as $key ({settings: ., added: {}};
      ($owned[0].permissions[$key] // []) as $old |
      ((.settings.permissions[$key] // []) - $old) as $kept |
      [($wanted[0].permissions[$key] // [])[] |
        select(. as $rule | $kept | index([$rule]) | not)] as $added |
      .added[$key] = $added |
      if ($kept + $added) != [] then
        .settings.permissions[$key] = $kept + $added
      elif $old != [] then
        del(.settings.permissions[$key])
      else
        .
      end
    ) |
    if .settings.permissions == {} then del(.settings.permissions) else . end |
    [.settings, {claude_root: $root, permissions: .added}]
  ' "$1" >"$merged" &&
    jq '.[0]' "$merged" >"$2" &&
    jq '.[1]' "$merged" >"$3"
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

  if [[ -n "$PERMISSIONS_MODE" ]] && ! valid_permissions "$target"; then
    echo "ERROR: Invalid Claude permissions: $target" >&2
    echo "       permissions.deny and permissions.ask must be lists of strings." >&2
    return 1
  fi
}

prepare_claude_settings() {
  local output="$1"
  local target="$CLAUDE_ROOT/settings.json"
  local input="/dev/null"
  local status_line_output="$output.status-line"
  local permissions_output="$output.permissions"
  local gate_output="$output.gate"
  local guard_output="$output.guards"
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

  if [[ -z "$PERMISSIONS_MODE" ]]; then
    cp -- "$status_line_output" "$permissions_output"
  elif ! reconcile_permissions "$status_line_output" "$permissions_output" \
    "$TRANSACTION_DIR/claude-permissions.json"; then
    echo "ERROR: Could not prepare Claude permissions for $target" >&2
    return 1
  fi

  if ! reconcile_gate_hooks "$CLAUDE_HOOKS" "$permissions_output" "$gate_output"; then
    echo "ERROR: Could not prepare Claude hooks for $target" >&2
    return 1
  fi

  if ! reconcile_guard_hooks "$gate_output" "$guard_output"; then
    echo "ERROR: Could not prepare Claude guard hooks for $target" >&2
    return 1
  fi

  if ! reconcile_hub_hooks "$guard_output" "$output" claude; then
    echo "ERROR: Could not prepare Claude agent hub hooks for $target" >&2
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

  if ! reconcile_gate_hooks "$CODEX_HOOKS" "$input" "$output.gate" ||
    ! reconcile_hub_hooks "$output.gate" "$output" codex; then
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
    skill_selected "${skill_dir##*/}" || continue
    legacy_skill="$legacy_root/$(basename "$skill_dir")"

    if [[ -e "$legacy_skill" || -L "$legacy_skill" ]]; then
      echo "ERROR: Duplicate Codex skill exists: $legacy_skill" >&2
      echo "       Codex reads the canonical skill through $AGENTS_ROOT/skills." >&2
      failed=1
    fi
  done

  return "$failed"
}

if has_component skills || has_component skills-extra; then
  validate_skills
fi
if has_component statusline; then
  validate_claude_settings
fi
if [[ -n "$CODEX_CONFIG_MODE" ]]; then
  validate_codex_tui_settings
fi
validate_hook_fragments
validate_permission_sources
validate_distinct_install_roots

failed=0
if has_component instructions; then
  for instructions_target in "$CODEX_ROOT/AGENTS.md" "$CLAUDE_ROOT/CLAUDE.md"; do
    links_to_instructions "$instructions_target" ||
      validate_link_target \
        "$INSTRUCTIONS_SOURCE" "$instructions_target" || failed=1
  done
fi
if has_component skills || has_component skills-extra; then
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
  validate_rules_target \
    "$CODEX_SHARED_RULES" \
    "$CODEX_ROOT/rules/shared.rules" || failed=1
fi
if has_component guards; then
  validate_link_target "$GUARDS" "$GUARDS_LINK" || failed=1
fi
if has_component permissions; then
  validate_rules_target \
    "$CODEX_PERMISSION_RULES" \
    "$CODEX_ROOT/rules/permissions.rules" || failed=1
fi
if hub_selected; then
  validate_link_target "$AGENT_HUB" "$AGENT_HUB_COMMAND" || failed=1
fi
if has_component subagents; then
  IFS=, read -r -a subagent_roles <<<"${SUBAGENT_ROLES:1:-1}"
  for agent in claude codex; do
    for role in "${subagent_roles[@]}"; do
      subagent_link="$(subagent_directory "$agent")/$role.$(subagent_extension "$agent")"
      links_to_generated_agent "$subagent_link" ||
        { [[ "$agent" == codex ]] && owns_codex_agent "$subagent_link"; } ||
        validate_link_target "$GENERATED_AGENTS/$agent/${subagent_link##*/}" \
          "$subagent_link" || failed=1
    done
  done
fi
if [[ -n "$CODEX_CONFIG_MODE" ]]; then
  validate_codex_config_target || failed=1
fi
validate_codex_hooks_target || failed=1
if ! ((UNINSTALL)); then
  validate_link_target \
    "$VERIFY_GATE" \
    "$VERIFY_GATE_COMMAND" || failed=1
elif [[ -e "$VERIFY_GATE_COMMAND" || -L "$VERIFY_GATE_COMMAND" ]] &&
  ! links_to "$VERIFY_GATE" "$VERIFY_GATE_COMMAND"; then
  # The hook entries name only the shared path, so they would go too.
  echo "ERROR: $VERIFY_GATE_COMMAND is not this checkout's verify gate." >&2
  echo "       Run --uninstall from the checkout it links to." >&2
  failed=1
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
instructions_candidate="$TRANSACTION_DIR/instructions.md"
if managed_target "$CLAUDE_ROOT/settings.json"; then
  prepare_claude_settings "$claude_candidate"
fi
if [[ -n "$CODEX_CONFIG_MODE" ]]; then
  prepare_codex_tui_settings "$codex_candidate"
fi
if managed_target "$CODEX_ROOT/hooks.json"; then
  prepare_codex_hooks "$codex_hooks_candidate"
fi
printf 'format=2\ncomponents=%s\ncodex_root=%s\nclaude_root=%s\n' \
  "$SELECTED_COMPONENTS" "$CODEX_ROOT" "$CLAUDE_ROOT" >"$components_candidate"
subagents_candidate="$TRANSACTION_DIR/agents"
if has_component subagents; then
  subagent_models=()
  if [[ -f "$AGENT_MODELS_OVERLAY" ]]; then
    subagent_models=(--models "$AGENT_MODELS_OVERLAY")
  fi
  python3 "$SUBAGENT_RENDERER" "$SUBAGENTS" "$subagents_candidate" \
    "${subagent_models[@]}"
fi
generate_instructions=0
if has_component instructions &&
  [[ "$INSTRUCTIONS_SOURCE" == "$GENERATED_INSTRUCTIONS" ]]; then
  generate_instructions=1
  { cat -- "$GLOBAL_INSTRUCTIONS" && echo && cat -- "$INSTRUCTIONS_OVERLAY"; } \
    >"$instructions_candidate"
fi

if ! ((UNINSTALL)); then
  ensure_directory "$AGENTS_ROOT"
  ensure_directory "$AGENTS_ROOT/hooks"
  ensure_directory "$CODEX_ROOT"
  if has_component codex-rules || has_component permissions; then
    ensure_directory "$CODEX_ROOT/rules"
  fi
  ensure_directory "$CLAUDE_ROOT"
  ensure_directory "${COMPONENTS_FILE%/*}"
  if has_component subagents; then
    for agent in claude codex; do
      ensure_directory "$GENERATED_AGENTS/$agent"
      ensure_directory "$(subagent_directory "$agent")"
    done
  fi
fi

claude_staged=""
codex_staged=""
codex_hooks_staged=""
components_staged=""
snapshot_staged=""
instructions_staged=""
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
permissions_staged=""
if [[ "$PERMISSIONS_MODE" == install ]]; then
  stage_managed_file \
    "$TRANSACTION_DIR/claude-permissions.json" \
    "$PERMISSIONS_SNAPSHOT" \
    permissions_staged
fi
declare -a subagent_staged=()
declare -a subagent_targets=()
if has_component subagents; then
  for subagent_candidate in "$subagents_candidate"/*/*; do
    subagent_targets+=("$GENERATED_AGENTS/${subagent_candidate#"$subagents_candidate/"}")
    stage_managed_file "$subagent_candidate" "${subagent_targets[-1]}" staged_file
    subagent_staged+=("$staged_file")
  done
fi
if ((generate_instructions)); then
  stage_managed_file \
    "$instructions_candidate" \
    "$GENERATED_INSTRUCTIONS" \
    instructions_staged
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

# Shared instructions, with the overlay appended when there is one.
if ((generate_instructions)); then
  activate_managed_file \
    "shared instructions and overlay" \
    "$instructions_staged" \
    "$GENERATED_INSTRUCTIONS"
fi
if has_component instructions; then
  install_instructions_link "$CODEX_ROOT/AGENTS.md"
  install_instructions_link "$CLAUDE_ROOT/CLAUDE.md"
elif dropping_component instructions; then
  remove_instructions_link "$CODEX_ROOT/AGENTS.md"
  remove_instructions_link "$CLAUDE_ROOT/CLAUDE.md"
fi
# Like the verify gate, the generated file is shared by all agent roots, so
# it stays while a selection saved for other roots may still use it.
if ! ((generate_instructions)) && [[ -f "$GENERATED_INSTRUCTIONS" ]] &&
  { ((saved_for_roots)) || [[ ! -f "$COMPONENTS_FILE" ]]; }; then
  remove_state_file "$GENERATED_INSTRUCTIONS"
fi

# Codex discovers ~/.agents/skills. Claude Code discovers skills in its selected
# configuration root. Link each selected skill so unrelated local skills remain
# untouched.
if has_component skills || has_component skills-extra; then
  install_skill_links "$AGENTS_ROOT/skills"
  install_skill_links "$CLAUDE_ROOT/skills"
elif dropping_component skills || dropping_component skills-extra; then
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
if ((UNINSTALL)) && [[ -f "$COMPONENTS_FILE" ]] && ! ((saved_for_roots)); then
  # Shared by all agent roots: the install saved for other roots still runs it.
  echo "KEEP: $VERIFY_GATE_COMMAND (used by the install for other agent roots)"
elif ((UNINSTALL)); then
  remove_owned_link "$VERIFY_GATE" "$VERIFY_GATE_COMMAND"
else
  install_link \
    "$VERIFY_GATE" \
    "$VERIFY_GATE_COMMAND"
fi

# The guard hook entries run the guard scripts through this link. Like the
# verify gate, it is shared by all agent roots.
if has_component guards; then
  install_link "$GUARDS" "$GUARDS_LINK"
elif links_to "$GUARDS" "$GUARDS_LINK" && [[ -f "$COMPONENTS_FILE" ]] &&
  ! ((saved_for_roots)); then
  echo "KEEP: $GUARDS_LINK (may be used by the install for other agent roots)"
elif dropping_component guards; then
  remove_owned_link "$GUARDS" "$GUARDS_LINK"
fi

# The notify, context, and format hook entries run the agent hub through this
# link, which is shared by all agent roots like the verify gate.
if hub_selected; then
  install_link "$AGENT_HUB" "$AGENT_HUB_COMMAND"
elif links_to "$AGENT_HUB" "$AGENT_HUB_COMMAND" && [[ -f "$COMPONENTS_FILE" ]] &&
  ! ((saved_for_roots)); then
  echo "KEEP: $AGENT_HUB_COMMAND (may be used by the install for other agent roots)"
elif dropping_component notify || dropping_component context ||
  dropping_component format; then
  remove_owned_link "$AGENT_HUB" "$AGENT_HUB_COMMAND"
fi

# Where notifications are Windows toasts (WSL), a Windows link handler lets a
# click bring the session's window forward. Like the agent hub, it is shared by
# all agent roots. Windows settings cannot be rolled back, so it is changed
# after the transaction.
focus_handler_action=
if command -v powershell.exe >/dev/null 2>&1; then
  if has_component notify; then
    focus_handler_action=install
  elif [[ -f "$COMPONENTS_FILE" ]] && ! ((saved_for_roots)); then
    : # may be used by the install for other agent roots
  elif dropping_component notify; then
    focus_handler_action=remove
  fi
fi

# Claude keeps machine-local state in settings.json, so only the centrally
# managed statusLine key, verify-gate hook entries, and guard hook entries are
# reconciled.
if [[ -n "$claude_staged" ]]; then
  activate_managed_file \
    "Claude managed settings" \
    "$claude_staged" \
    "$CLAUDE_ROOT/settings.json"
fi

if has_component codex-rules; then
  install_managed_copy \
    "$CODEX_SHARED_RULES" \
    "$CODEX_ROOT/rules/shared.rules" \
    "${CODEX_SHARED_RULES#"$ROOT"/}"
elif dropping_component codex-rules; then
  remove_owned_rules "$CODEX_SHARED_RULES" "$CODEX_ROOT/rules/shared.rules"
fi

if has_component permissions; then
  install_managed_copy \
    "$CODEX_PERMISSION_RULES" \
    "$CODEX_ROOT/rules/permissions.rules" \
    "${CODEX_PERMISSION_RULES#"$ROOT"/}"
elif dropping_component permissions; then
  remove_owned_rules \
    "$CODEX_PERMISSION_RULES" "$CODEX_ROOT/rules/permissions.rules"
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

if [[ "$PERMISSIONS_MODE" == install ]]; then
  activate_managed_file \
    "added Claude permission rules" \
    "$permissions_staged" \
    "$PERMISSIONS_SNAPSHOT"
elif [[ "$PERMISSIONS_MODE" == remove ]]; then
  remove_state_file "$PERMISSIONS_SNAPSHOT"
fi

if has_component statusline; then
  activate_managed_file \
    "installed Codex TUI values" \
    "$snapshot_staged" \
    "$CODEX_TUI_SNAPSHOT"
fi

# Claude Code's agents directory links to the generated definitions, and
# Codex's holds marked copies of them. Those for roles no longer selected or
# defined are removed; your own agent files are never touched.
for agent in claude codex; do
  for subagent_link in "$(subagent_directory "$agent")"/*; do
    if [[ "$agent" == claude ]]; then
      links_to_generated_agent "$subagent_link" || continue
    else
      owns_codex_agent "$subagent_link" || continue
    fi
    subagent_name="${subagent_link##*/}"
    if ! has_component subagents; then
      remove_managed_copy "$subagent_link"
    elif [[ "$SUBAGENT_ROLES" != *",${subagent_name%.*},"* ]]; then
      remove_managed_copy "$subagent_link" "removed subagent"
    fi
  done
done
for index in "${!subagent_targets[@]}"; do
  activate_managed_file "subagent definition" "${subagent_staged[index]}" \
    "${subagent_targets[index]}"
  subagent_file="${subagent_targets[index]}"
  subagent_agent="${subagent_file%/*}"
  subagent_agent="${subagent_agent##*/}"
  if [[ "$subagent_agent" == claude ]]; then
    install_link "$subagent_file" \
      "$(subagent_directory "$subagent_agent")/${subagent_file##*/}"
  else
    subagent_name="${subagent_file##*/}"
    install_managed_copy "$subagent_file" \
      "$(subagent_directory "$subagent_agent")/$subagent_name" \
      "subagents/${subagent_name%.*}.md"
  fi
done
# Like the generated instructions, the generated definitions are shared by
# all agent roots, so they stay while a selection saved for other roots may
# still use them.
if { ((saved_for_roots)) || [[ ! -f "$COMPONENTS_FILE" ]]; }; then
  for generated_agent in "$GENERATED_AGENTS"/claude/* "$GENERATED_AGENTS"/codex/*; do
    [[ -f "$generated_agent" ]] || continue
    generated_name="${generated_agent##*/}"
    if ! has_component subagents ||
      [[ "$SUBAGENT_ROLES" != *",${generated_name%.*},"* ]]; then
      remove_state_file "$generated_agent"
    fi
  done
fi

# Saved last so that a failed install leaves the previous selection in place.
if ((UNINSTALL)); then
  # State saved for other agent roots still describes that install.
  if ((saved_for_roots)); then
    remove_state_file "$COMPONENTS_FILE"
    remove_state_file "$CODEX_TUI_SNAPSHOT"
  fi
else
  activate_managed_file \
    "component selection" \
    "$components_staged" \
    "$COMPONENTS_FILE"
fi

TRANSACTION_ACTIVE=0

if [[ "$focus_handler_action" == install ]]; then
  if python3 "$AGENT_HUB" focus-handler install; then
    echo "Registered the Windows handler that opens a session's window from its notification"
  else
    echo "WARNING: Could not register the notification click handler;" \
      "notifications still work, but clicking one does nothing." >&2
  fi
elif [[ "$focus_handler_action" == remove ]]; then
  if python3 "$AGENT_HUB" focus-handler remove; then
    echo "Removed the Windows notification click handler"
  else
    echo "WARNING: Could not remove the notification click handler" \
      "(HKCU\\Software\\Classes\\power-agents-focus)." >&2
  fi
fi

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
  if ((generate_instructions)); then
    echo "  $INSTRUCTIONS_OVERLAY (your overlay, appended)"
  fi
fi
if has_component skills || has_component skills-extra; then
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
if has_component guards; then
  echo
  echo "Canonical Claude Code guard hooks:"
  echo "  $GUARDS"
fi
if has_component permissions; then
  echo
  echo "Canonical permission rules:"
  echo "  $CLAUDE_PERMISSIONS"
  echo "  $CODEX_PERMISSION_RULES"
fi
if has_component subagents; then
  echo
  echo "Canonical subagents:"
  echo "  $SUBAGENTS"
  if [[ -f "$AGENT_MODELS_OVERLAY" ]]; then
    echo "  $AGENT_MODELS_OVERLAY (your model choices)"
  fi
fi
if hub_selected; then
  echo
  echo "Canonical agent hub (notify, context, and format hooks):"
  echo "  $AGENT_HUB"
fi
