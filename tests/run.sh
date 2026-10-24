#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/power-agents-tests.XXXXXX")"
TOMLKIT_SITE_PACKAGES="$(python3 -c '
from pathlib import Path
import tomlkit
print(Path(tomlkit.__file__).parent.parent)
')"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

skip() {
  echo "SKIP: $*"
}

assert_same_link() {
  local source="$1"
  local target="$2"

  [[ -L "$target" ]] || fail "Expected symlink: $target"
  [[ "$target" -ef "$source" ]] || fail "Wrong symlink target: $target"
}

assert_skill_links() {
  local skill_dir
  local target_root="$1"

  [[ -d "$target_root" && ! -L "$target_root" ]] ||
    fail "Expected skill directory: $target_root"

  for skill_dir in "$ROOT"/skills/*; do
    [[ -d "$skill_dir" ]] || continue
    assert_same_link \
      "$skill_dir" \
      "$target_root/$(basename "$skill_dir")"
  done
}

assert_contains() {
  local file="$1"
  local expected="$2"

  if ! grep -Fq -- "$expected" "$file"; then
    echo "Expected to find '$expected' in $file:" >&2
    sed 's/^/  /' "$file" >&2
    fail "Missing expected output"
  fi
}

run_installer() {
  run_installer_args "$1" --components all
}

# Runs the installer with exactly the given arguments.
run_installer_args() {
  local test_home="$1"

  shift
  run_installer_with_roots \
    "$test_home" \
    "$test_home/.codex" \
    "$test_home/.claude" \
    "$@"
}

# INSTALLER selects another checkout's install.sh.
run_installer_with_roots() {
  local claude_root="$3"
  local codex_root="$2"
  local path
  local test_home="$1"

  shift 3
  for path in "$test_home" "$codex_root" "$claude_root"; do
    case "$path" in
      "$TEST_ROOT"/*) ;;
      *) fail "Refusing to run installer outside the test root: $path" ;;
    esac
  done

  mkdir -p "$test_home"
  HOME="$test_home" \
    CODEX_HOME="$codex_root" \
    CLAUDE_CONFIG_DIR="$claude_root" \
    PYTHONPATH="$TOMLKIT_SITE_PACKAGES${PYTHONPATH:+:$PYTHONPATH}" \
    "${INSTALLER:-$ROOT/install.sh}" "$@" >"$test_home/install.log" 2>&1
}

expect_installer_failure() {
  local test_home="$1"

  if run_installer "$test_home"; then
    fail "Installer unexpectedly accepted conflict in $test_home"
  fi
  assert_contains "$test_home/install.log" "ERROR: Refusing to replace existing path:"
}

managed_hooks() {
  local agent="$1"
  local script="$2"

  jq -n --arg agent "$agent" --arg script "$script" '{
    "UserPromptSubmit": [{"hooks": [{
      "type": "command",
      "command": ("python3 \"" + $script + "\" mark --agent " + $agent),
      "timeout": 30
    }]}],
    "Stop": [{"hooks": [{
      "type": "command",
      "command": ("python3 \"" + $script + "\" stop --agent " + $agent),
      "timeout": 600
    }]}]
  }'
}

saved_components() {
  sed -n 's/^components=//p' "$1/.config/power-agents/components"
}

render_status_line() {
  env -u SSH_CONNECTION -u SSH_TTY bash \
    "$ROOT/settings/claude/statusline-command.sh"
}

test_project_instruction_entrypoints() {
  [[ -f "$ROOT/AGENTS.md" && -s "$ROOT/AGENTS.md" ]] ||
    fail "AGENTS.md must contain the authoritative project instructions"
  [[ ! -e "$ROOT/CLAUDE.md" && ! -L "$ROOT/CLAUDE.md" ]] ||
    fail "Project instructions must use AGENTS.md without a CLAUDE.md fallback"
}

test_installer_rejects_invalid_skill_metadata() {
  local invalid_repo="$TEST_ROOT/invalid-skill-repo"
  local test_home="$TEST_ROOT/invalid-skill-home"

  mkdir -p "$invalid_repo" "$test_home"
  cp -a "$ROOT/." "$invalid_repo/"
  mkdir -p "$invalid_repo/skills/Invalid_Name"
  cat >"$invalid_repo/skills/Invalid_Name/SKILL.md" <<'EOF'
---
name: Invalid_Name
description: This directory name is not valid.
---

# Invalid Skill
EOF

  if HOME="$test_home" \
    CODEX_HOME="$test_home/.codex" \
    CLAUDE_CONFIG_DIR="$test_home/.claude" \
    PYTHONPATH="$TOMLKIT_SITE_PACKAGES${PYTHONPATH:+:$PYTHONPATH}" \
    "$invalid_repo/install.sh" --components all \
    >"$test_home/install.log" 2>&1; then
    fail "Installer accepted invalid skill metadata"
  fi

  assert_contains "$test_home/install.log" "directory name must match"
  assert_contains "$test_home/install.log" "Skill validation failed"
  [[ ! -e "$test_home/.codex/AGENTS.md" ]] ||
    fail "Installer partially installed after rejecting invalid skill metadata"
  [[ ! -e "$test_home/.claude/CLAUDE.md" ]] ||
    fail "Installer partially installed after rejecting invalid skill metadata"
}

test_clean_install_and_idempotence() {
  local claude_settings_before
  local codex_hooks_before
  local config_before
  local local_broken_target="$TEST_ROOT/missing-local-skill"
  local stale_skill_name="removed-repository-skill"
  local test_home="$TEST_ROOT/clean-home"

  mkdir -p "$test_home/.agents/skills" "$test_home/.claude/skills"
  printf '%s\n' "keep this Codex skill" >"$test_home/.agents/skills/local-skill"
  printf '%s\n' "keep this Claude skill" >"$test_home/.claude/skills/local-skill"
  ln -s "$local_broken_target" \
    "$test_home/.agents/skills/local-broken-skill"
  ln -s "$local_broken_target" \
    "$test_home/.claude/skills/local-broken-skill"
  ln -s "$ROOT/skills/$stale_skill_name" \
    "$test_home/.agents/skills/$stale_skill_name"
  ln -s "$ROOT/skills/$stale_skill_name" \
    "$test_home/.claude/skills/$stale_skill_name"
  run_installer "$test_home"

  assert_same_link \
    "$ROOT/instructions/general-global.md" "$test_home/.codex/AGENTS.md"
  assert_same_link \
    "$ROOT/instructions/general-global.md" "$test_home/.claude/CLAUDE.md"
  assert_skill_links "$test_home/.agents/skills"
  assert_skill_links "$test_home/.claude/skills"
  [[ "$(<"$test_home/.agents/skills/local-skill")" == "keep this Codex skill" ]] ||
    fail "Installer changed an unrelated Codex skill"
  [[ "$(<"$test_home/.claude/skills/local-skill")" == "keep this Claude skill" ]] ||
    fail "Installer changed an unrelated Claude skill"
  [[ "$(readlink "$test_home/.agents/skills/local-broken-skill")" == \
    "$local_broken_target" ]] ||
    fail "Installer changed an unrelated broken Codex skill link"
  [[ "$(readlink "$test_home/.claude/skills/local-broken-skill")" == \
    "$local_broken_target" ]] ||
    fail "Installer changed an unrelated broken Claude skill link"
  [[ ! -L "$test_home/.agents/skills/$stale_skill_name" ]] ||
    fail "Installer kept a stale repository-owned Codex skill link"
  [[ ! -L "$test_home/.claude/skills/$stale_skill_name" ]] ||
    fail "Installer kept a stale repository-owned Claude skill link"
  assert_contains "$test_home/install.log" \
    "REMOVE: $test_home/.agents/skills/$stale_skill_name"
  assert_contains "$test_home/install.log" \
    "REMOVE: $test_home/.claude/skills/$stale_skill_name"
  assert_same_link \
    "$ROOT/settings/claude/statusline-command.sh" \
    "$test_home/.claude/statusline-command.sh"
  [[ -x "$test_home/.claude/statusline-command.sh" ]] ||
    fail "Installed Claude status-line command is not executable"
  assert_same_link \
    "$ROOT/hooks/verify-gate.py" \
    "$test_home/.agents/hooks/verify-gate.py"
  jq -e --arg command "$test_home/.claude/statusline-command.sh" \
    --argjson hooks "$(managed_hooks claude \
      "$test_home/.agents/hooks/verify-gate.py")" '
    . == {
      "statusLine": {
        "type": "command",
        "command": $command
      },
      "hooks": $hooks
    }
  ' "$test_home/.claude/settings.json" >/dev/null ||
    fail "Clean install produced unexpected Claude settings"
  jq -e --argjson hooks "$(managed_hooks codex \
    "$test_home/.agents/hooks/verify-gate.py")" '
    . == {"hooks": $hooks}
  ' "$test_home/.codex/hooks.json" >/dev/null ||
    fail "Clean install produced unexpected Codex hooks"
  assert_contains "$test_home/install.log" \
    "Codex: trust the verify-gate hooks with /hooks in a new session."
  assert_same_link \
    "$ROOT/policies/codex/shared.rules" \
    "$test_home/.codex/rules/shared.rules"
  cmp -s "$ROOT/settings/codex/tui.toml" "$test_home/.codex/config.toml" ||
    fail "Clean install produced unexpected Codex config"

  claude_settings_before="$(cksum "$test_home/.claude/settings.json")"
  config_before="$(cksum "$test_home/.codex/config.toml")"
  codex_hooks_before="$(cksum "$test_home/.codex/hooks.json")"
  run_installer "$test_home"
  [[ "$(cksum "$test_home/.claude/settings.json")" == "$claude_settings_before" ]] ||
    fail "Repeated install changed Claude settings"
  [[ "$(cksum "$test_home/.codex/config.toml")" == "$config_before" ]] ||
    fail "Repeated install changed Codex config"
  [[ "$(cksum "$test_home/.codex/hooks.json")" == "$codex_hooks_before" ]] ||
    fail "Repeated install changed Codex hooks"
  assert_contains "$test_home/install.log" \
    "OK: $test_home/.codex/hooks.json (Codex verify-gate hooks)"
  assert_skill_links "$test_home/.agents/skills"
  assert_skill_links "$test_home/.claude/skills"
  [[ -z "$(find "$test_home/.codex" -name 'config.toml.tmp.*' -print -quit)" ]] ||
    fail "Installer left a temporary Codex config behind"
  [[ -z "$(find "$test_home/.claude" -name 'settings.json.tmp.*' -print -quit)" ]] ||
    fail "Installer left a temporary Claude settings file behind"
  [[ -z "$(find "$test_home/.codex" -name 'hooks.json.tmp.*' -print -quit)" ]] ||
    fail "Installer left a temporary Codex hooks file behind"
}

test_custom_agent_roots() {
  local claude_root="$TEST_ROOT/custom-root-home/config roots/claude"
  local codex_root="$TEST_ROOT/custom-root-home/config roots/codex"
  local test_home="$TEST_ROOT/custom-root-home"

  run_installer_with_roots "$test_home" "$codex_root" "$claude_root" \
    --components all

  assert_same_link \
    "$ROOT/instructions/general-global.md" "$codex_root/AGENTS.md"
  assert_same_link \
    "$ROOT/instructions/general-global.md" "$claude_root/CLAUDE.md"
  assert_skill_links "$test_home/.agents/skills"
  assert_skill_links "$claude_root/skills"
  assert_same_link \
    "$ROOT/settings/claude/statusline-command.sh" \
    "$claude_root/statusline-command.sh"
  jq -e --arg command "$claude_root/statusline-command.sh" '
    .statusLine == {
      "type": "command",
      "command": $command
    }
  ' "$claude_root/settings.json" >/dev/null ||
    fail "Custom Claude root produced an incorrect status-line command"
  assert_same_link \
    "$ROOT/hooks/verify-gate.py" "$test_home/.agents/hooks/verify-gate.py"
  jq -e --argjson hooks "$(managed_hooks claude \
    "$test_home/.agents/hooks/verify-gate.py")" \
    '.hooks == $hooks' "$claude_root/settings.json" >/dev/null ||
    fail "Custom Claude root produced incorrect verify-gate hooks"
  jq -e --argjson hooks "$(managed_hooks codex \
    "$test_home/.agents/hooks/verify-gate.py")" \
    '. == {"hooks": $hooks}' "$codex_root/hooks.json" >/dev/null ||
    fail "Custom Codex root produced incorrect verify-gate hooks"
  assert_same_link \
    "$ROOT/policies/codex/shared.rules" "$codex_root/rules/shared.rules"
  cmp -s "$ROOT/settings/codex/tui.toml" "$codex_root/config.toml" ||
    fail "Custom Codex root produced unexpected configuration"
  [[ ! -e "$test_home/.codex" ]] ||
    fail "Installer ignored CODEX_HOME"
  [[ ! -e "$test_home/.claude" ]] ||
    fail "Installer ignored CLAUDE_CONFIG_DIR"
}

test_invalid_agent_roots() {
  local actual_root
  local alias_root
  local label
  local root_alias_home
  local shared_root
  local test_home
  local variable

  while read -r variable label; do
    test_home="$TEST_ROOT/invalid-${variable,,}-home"
    mkdir -p "$test_home"
    if env \
      HOME="$test_home" \
      CODEX_HOME="$test_home/safe-codex" \
      CLAUDE_CONFIG_DIR="$test_home/safe-claude" \
      "$variable=relative/config" \
      PYTHONPATH="$TOMLKIT_SITE_PACKAGES${PYTHONPATH:+:$PYTHONPATH}" \
      "$ROOT/install.sh" >"$test_home/install.log" 2>&1; then
      fail "Installer accepted a relative $variable"
    fi
    assert_contains "$test_home/install.log" \
      "ERROR: $label must be an absolute directory other than /: relative/config"
    [[ ! -e "$test_home/.agents" && ! -e "$test_home/.codex" && \
      ! -e "$test_home/.claude" && ! -e "$test_home/safe-codex" && \
      ! -e "$test_home/safe-claude" ]] ||
      fail "Installer partially installed after rejecting $variable"
  done <<'EOF'
CODEX_HOME Codex configuration root
CLAUDE_CONFIG_DIR Claude configuration root
EOF

  test_home="$TEST_ROOT/shared-agent-root-home"
  shared_root="$test_home/shared-root"
  mkdir -p "$test_home"
  if HOME="$test_home" \
    CODEX_HOME="$shared_root" \
    CLAUDE_CONFIG_DIR="$shared_root" \
    PYTHONPATH="$TOMLKIT_SITE_PACKAGES${PYTHONPATH:+:$PYTHONPATH}" \
    "$ROOT/install.sh" >"$test_home/install.log" 2>&1; then
    fail "Installer accepted colliding Codex and Claude roots"
  fi
  assert_contains "$test_home/install.log" \
    "ERROR: Shared, Codex, and Claude configuration roots must be distinct."
  [[ ! -e "$test_home/.agents" && ! -e "$shared_root" ]] ||
    fail "Installer partially installed after rejecting colliding roots"

  test_home="$TEST_ROOT/aliased-agent-root-home"
  actual_root="$test_home/config"
  alias_root="$test_home/missing/../config"
  mkdir -p "$test_home"
  if HOME="$test_home" \
    CODEX_HOME="$actual_root" \
    CLAUDE_CONFIG_DIR="$alias_root" \
    PYTHONPATH="$TOMLKIT_SITE_PACKAGES${PYTHONPATH:+:$PYTHONPATH}" \
    "$ROOT/install.sh" >"$test_home/install.log" 2>&1; then
    fail "Installer accepted lexically distinct aliases of the same root"
  fi
  assert_contains "$test_home/install.log" \
    "ERROR: Shared, Codex, and Claude configuration roots must be distinct."
  [[ ! -e "$test_home/.agents" && ! -e "$actual_root" ]] ||
    fail "Installer partially installed after rejecting aliased roots"

  test_home="$TEST_ROOT/symlinked-agent-root-home"
  actual_root="$test_home/config"
  alias_root="$test_home/config-link"
  mkdir -p "$actual_root"
  ln -s "$actual_root" "$alias_root"
  if HOME="$test_home" \
    CODEX_HOME="$actual_root" \
    CLAUDE_CONFIG_DIR="$alias_root" \
    PYTHONPATH="$TOMLKIT_SITE_PACKAGES${PYTHONPATH:+:$PYTHONPATH}" \
    "$ROOT/install.sh" >"$test_home/install.log" 2>&1; then
    fail "Installer accepted symlink aliases of the same root"
  fi
  assert_contains "$test_home/install.log" \
    "ERROR: Shared, Codex, and Claude configuration roots must be distinct."
  [[ ! -e "$test_home/.agents" && -z "$(find "$actual_root" -mindepth 1 -print -quit)" ]] ||
    fail "Installer partially installed after rejecting symlinked roots"

  test_home="$TEST_ROOT/symlinked-shared-root-home"
  actual_root="$test_home/config"
  mkdir -p "$actual_root"
  ln -s "$actual_root" "$test_home/.agents"
  if HOME="$test_home" \
    CODEX_HOME="$actual_root" \
    CLAUDE_CONFIG_DIR="$test_home/.claude" \
    PYTHONPATH="$TOMLKIT_SITE_PACKAGES${PYTHONPATH:+:$PYTHONPATH}" \
    "$ROOT/install.sh" >"$test_home/install.log" 2>&1; then
    fail "Installer accepted shared and Codex roots resolving to the same location"
  fi
  assert_contains "$test_home/install.log" \
    "ERROR: Shared, Codex, and Claude configuration roots must be distinct."
  [[ -z "$(find "$actual_root" -mindepth 1 -print -quit)" && \
    ! -e "$test_home/.claude" ]] ||
    fail "Installer partially installed after rejecting a shared-root alias"

  root_alias_home="$TEST_ROOT/root-alias-home"
  mkdir -p "$root_alias_home"
  if HOME="$root_alias_home" \
    CODEX_HOME="/tmp/.." \
    CLAUDE_CONFIG_DIR="$root_alias_home/.claude" \
    PYTHONPATH="$TOMLKIT_SITE_PACKAGES${PYTHONPATH:+:$PYTHONPATH}" \
    "$ROOT/install.sh" >"$root_alias_home/install.log" 2>&1; then
    fail "Installer accepted an alias of the filesystem root"
  fi
  assert_contains "$root_alias_home/install.log" \
    "ERROR: Codex configuration root must be an absolute directory other than /: /tmp/.."
  [[ ! -e "$root_alias_home/.agents" && ! -e "$root_alias_home/.claude" ]] ||
    fail "Installer partially installed after rejecting a root alias"
}

run_rollback_case() {
  local claude_settings_before
  local codex_config_before
  local codex_hooks_before=""
  local components_file
  local fail_at
  local failed_target
  local kind="$1"
  local real_mv
  local shim="$TEST_ROOT/rollback-$kind-home/shim"
  local test_home="$TEST_ROOT/rollback-$kind-home"
  local transaction_tmp="$test_home/tmp"

  components_file="$test_home/.config/power-agents/components"
  mkdir -p "$test_home/.claude" "$test_home/.codex" "$shim" "$transaction_tmp"
  cat >"$test_home/.claude/settings.json" <<'EOF'
{
  "model": "opus"
}
EOF
  cat >"$test_home/.codex/config.toml" <<'EOF'
model = "machine-local-model"
EOF
  # Activation order: Claude settings, Codex config, Codex hooks, then the
  # component selection.
  case "$kind" in
    config)
      fail_at=2
      failed_target="$test_home/.codex/config.toml"
      printf '%s\n' \
        '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "local-stop"}]}]}}' \
        >"$test_home/.codex/hooks.json"
      codex_hooks_before="$(cksum "$test_home/.codex/hooks.json")"
      ;;
    hooks)
      fail_at=3
      failed_target="$test_home/.codex/hooks.json"
      ;;
    components)
      fail_at=5
      failed_target="$components_file"
      mkdir -p "${components_file%/*}"
      printf '%s\n' "instructions" >"$components_file"
      ;;
  esac
  cat >"$shim/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count=0
if [[ -f "$POWER_AGENTS_TEST_MV_COUNT" ]]; then
  read -r count <"$POWER_AGENTS_TEST_MV_COUNT"
fi
((count += 1))
printf '%s\n' "$count" >"$POWER_AGENTS_TEST_MV_COUNT"
if ((count == POWER_AGENTS_FAIL_MV_AT)); then
  exit 91
fi
exec "$POWER_AGENTS_REAL_MV" "$@"
EOF
  chmod +x "$shim/mv"

  claude_settings_before="$(cksum "$test_home/.claude/settings.json")"
  codex_config_before="$(cksum "$test_home/.codex/config.toml")"
  real_mv="$(command -v mv)"

  if HOME="$test_home" \
    CODEX_HOME="$test_home/.codex" \
    CLAUDE_CONFIG_DIR="$test_home/.claude" \
    PATH="$shim:$PATH" \
    TMPDIR="$transaction_tmp" \
    POWER_AGENTS_FAIL_MV_AT="$fail_at" \
    POWER_AGENTS_REAL_MV="$real_mv" \
    POWER_AGENTS_TEST_MV_COUNT="$test_home/mv-count" \
    PYTHONPATH="$TOMLKIT_SITE_PACKAGES${PYTHONPATH:+:$PYTHONPATH}" \
    "$ROOT/install.sh" --components all >"$test_home/install.log" 2>&1; then
    fail "Installer unexpectedly succeeded after an activation failure"
  fi

  assert_contains "$test_home/install.log" \
    "ERROR: Could not activate managed settings: $failed_target"
  assert_contains "$test_home/install.log" \
    "ERROR: Installation failed; restoring previous configuration."
  [[ "$(cksum "$test_home/.claude/settings.json")" == \
    "$claude_settings_before" ]] ||
    fail "Rollback did not restore Claude settings"
  [[ "$(cksum "$test_home/.codex/config.toml")" == "$codex_config_before" ]] ||
    fail "Rollback did not restore Codex config"
  if [[ -n "$codex_hooks_before" ]]; then
    [[ "$(cksum "$test_home/.codex/hooks.json")" == "$codex_hooks_before" ]] ||
      fail "Rollback did not restore Codex hooks"
  else
    [[ ! -e "$test_home/.codex/hooks.json" ]] ||
      fail "Rollback left Codex hooks installed"
  fi
  [[ -z "$(find "$test_home/.codex" -name '*.tmp.*' -print -quit)" ]] ||
    fail "Rollback left a temporary Codex file behind"
  [[ ! -e "$test_home/.codex/AGENTS.md" ]] ||
    fail "Rollback left Codex instructions installed"
  [[ ! -e "$test_home/.codex/rules" ]] ||
    fail "Rollback left Codex rules installed"
  [[ ! -e "$test_home/.claude/CLAUDE.md" ]] ||
    fail "Rollback left Claude instructions installed"
  [[ ! -e "$test_home/.claude/skills" ]] ||
    fail "Rollback left Claude skills installed"
  [[ ! -e "$test_home/.claude/statusline-command.sh" ]] ||
    fail "Rollback left the Claude status line installed"
  [[ ! -e "$test_home/.agents" ]] ||
    fail "Rollback left shared skills or the verify gate installed"
  if [[ "$kind" == components ]]; then
    [[ "$(<"$components_file")" == "instructions" ]] ||
      fail "Rollback did not restore the component selection"
    [[ -z "$(find "${components_file%/*}" -name 'components.tmp.*' -print -quit)" ]] ||
      fail "Rollback left a temporary component selection behind"
    [[ ! -e "${components_file%/*}/codex-tui.toml" ]] ||
      fail "Rollback left the installed Codex TUI values behind"
  else
    [[ ! -e "$test_home/.config" ]] ||
      fail "Rollback left a component selection behind"
  fi
  [[ -z "$(find "$transaction_tmp" -mindepth 1 -print -quit)" ]] ||
    fail "Rollback left transaction data behind"
}

test_transaction_rollback() {
  run_rollback_case config
  run_rollback_case hooks
  run_rollback_case components
}

test_claude_settings_reconciliation() {
  local test_home="$TEST_ROOT/claude-settings-home"

  mkdir -p "$test_home/.claude"
  cat >"$test_home/.claude/settings.json" <<'EOF'
{
  "model": "opus",
  "permissions": {
    "allow": ["Read"]
  },
  "statusLine": {
    "type": "command",
    "command": "old-status-line",
    "padding": 4
  }
}
EOF

  run_installer "$test_home"
  jq -e --arg command "$test_home/.claude/statusline-command.sh" \
    --argjson hooks "$(managed_hooks claude \
      "$test_home/.agents/hooks/verify-gate.py")" '
    . == {
      "model": "opus",
      "permissions": {
        "allow": ["Read"]
      },
      "statusLine": {
        "type": "command",
        "command": $command
      },
      "hooks": $hooks
    }
  ' "$test_home/.claude/settings.json" >/dev/null ||
    fail "Installer did not preserve and reconcile Claude settings"
}

test_claude_settings_rejection() {
  local test_home="$TEST_ROOT/invalid-claude-settings-home"

  mkdir -p "$test_home/.claude"
  printf '%s\n' '{"model":' >"$test_home/.claude/settings.json"

  if run_installer "$test_home"; then
    fail "Installer unexpectedly accepted invalid Claude settings"
  fi

  assert_contains "$test_home/install.log" \
    "ERROR: Invalid Claude settings JSON:"
  [[ "$(<"$test_home/.claude/settings.json")" == '{"model":' ]] ||
    fail "Installer changed rejected Claude settings"
  [[ ! -e "$test_home/.codex/AGENTS.md" ]] ||
    fail "Installer partially installed after rejecting Claude settings"
  [[ ! -e "$test_home/.claude/CLAUDE.md" ]] ||
    fail "Installer partially installed after rejecting Claude settings"
}

test_foreign_hooks_preservation() {
  local claude_settings_before
  local codex_hooks_before
  local script
  local test_home="$TEST_ROOT/foreign-hooks-home"

  script="$test_home/.agents/hooks/verify-gate.py"
  mkdir -p "$test_home/.claude" "$test_home/.codex"
  cat >"$test_home/.claude/settings.json" <<'EOF'
{
  "model": "opus",
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "claude-audit", "timeout": 5}]}
    ],
    "Stop": [
      {"hooks": [{"type": "command", "command": "claude-notify"}]}
    ]
  }
}
EOF
  cat >"$test_home/.codex/hooks.json" <<'EOF'
{
  "description": "local Codex hooks",
  "hooks": {
    "SessionStart": [
      {"matcher": "startup", "hooks": [{"type": "command", "command": "codex-start"}]}
    ],
    "Stop": [
      {"hooks": [{"type": "command", "command": "codex-notify"}]}
    ]
  }
}
EOF

  run_installer "$test_home"

  jq -e --arg command "$test_home/.claude/statusline-command.sh" \
    --argjson managed "$(managed_hooks claude "$script")" '
    . == {
      "model": "opus",
      "hooks": {
        "PreToolUse": [
          {"matcher": "Bash", "hooks": [{"type": "command", "command": "claude-audit", "timeout": 5}]}
        ],
        "Stop": ([
          {"hooks": [{"type": "command", "command": "claude-notify"}]}
        ] + $managed.Stop),
        "UserPromptSubmit": $managed.UserPromptSubmit
      },
      "statusLine": {"type": "command", "command": $command}
    }
  ' "$test_home/.claude/settings.json" >/dev/null ||
    fail "Installer did not preserve foreign Claude hooks"
  jq -e --argjson managed "$(managed_hooks codex "$script")" '
    . == {
      "description": "local Codex hooks",
      "hooks": {
        "SessionStart": [
          {"matcher": "startup", "hooks": [{"type": "command", "command": "codex-start"}]}
        ],
        "Stop": ([
          {"hooks": [{"type": "command", "command": "codex-notify"}]}
        ] + $managed.Stop),
        "UserPromptSubmit": $managed.UserPromptSubmit
      }
    }
  ' "$test_home/.codex/hooks.json" >/dev/null ||
    fail "Installer did not preserve foreign Codex hooks"

  claude_settings_before="$(cksum "$test_home/.claude/settings.json")"
  codex_hooks_before="$(cksum "$test_home/.codex/hooks.json")"
  run_installer "$test_home"
  [[ "$(cksum "$test_home/.claude/settings.json")" == "$claude_settings_before" ]] ||
    fail "Repeated install changed Claude settings with foreign hooks"
  [[ "$(cksum "$test_home/.codex/hooks.json")" == "$codex_hooks_before" ]] ||
    fail "Repeated install changed Codex hooks with foreign hooks"
}

test_legacy_verify_gate_rejection() {
  local file
  local kind
  local legacy_command="python3 ~/.agent-hooks/verify_gate.py stop --agent"
  local test_home

  for kind in claude codex; do
    test_home="$TEST_ROOT/legacy-$kind-hooks-home"
    mkdir -p "$test_home/.claude" "$test_home/.codex"
    case "$kind" in
      claude) file="$test_home/.claude/settings.json" ;;
      codex) file="$test_home/.codex/hooks.json" ;;
    esac
    jq -n --arg command "$legacy_command $kind" \
      '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": $command}]}]}}' \
      >"$file"
    cp "$file" "$test_home/before.json"

    if run_installer "$test_home"; then
      fail "Installer accepted a legacy standalone $kind verify gate hook"
    fi

    assert_contains "$test_home/install.log" \
      "legacy standalone verify gate hook in $file"
    assert_contains "$test_home/install.log" "$legacy_command $kind"
    assert_contains "$test_home/install.log" "uninstall.sh"
    cmp -s "$file" "$test_home/before.json" ||
      fail "Installer changed a config with a legacy $kind hook"
    [[ ! -e "$test_home/.agents" && ! -e "$test_home/.codex/AGENTS.md" && \
      ! -e "$test_home/.claude/CLAUDE.md" ]] ||
      fail "Installer partially installed after finding a legacy $kind hook"
    [[ "$kind" == codex || ! -e "$test_home/.codex/hooks.json" ]] ||
      fail "Installer wrote Codex hooks after finding a legacy Claude hook"
    [[ "$kind" == claude || ! -e "$test_home/.claude/settings.json" ]] ||
      fail "Installer wrote Claude settings after finding a legacy Codex hook"
  done
}

test_skill_link_migration() {
  local test_home="$TEST_ROOT/skill-migration-home"

  mkdir -p "$test_home/.agents" "$test_home/.claude"
  ln -s "$ROOT/skills" "$test_home/.agents/skills"
  ln -s "$ROOT/skills" "$test_home/.claude/skills"

  run_installer "$test_home"

  assert_skill_links "$test_home/.agents/skills"
  assert_skill_links "$test_home/.claude/skills"
  assert_contains "$test_home/install.log" \
    "MIGRATE: $test_home/.agents/skills (per-skill links)"
  assert_contains "$test_home/install.log" \
    "MIGRATE: $test_home/.claude/skills (per-skill links)"
}

test_gate_only_install() {
  local blocker="$TEST_ROOT/missing-optional-modules"
  local local_status_line
  local module
  local test_home="$TEST_ROOT/gate-only-home"

  local_status_line="$test_home/.claude/statusline-command.sh"
  mkdir -p "$blocker" "$test_home/.claude"
  for module in tomlkit yaml; do
    printf '%s\n' 'raise ImportError("hidden by the gate-only test")' \
      >"$blocker/$module.py"
  done
  printf '%s\n' '#!/bin/sh' 'echo local' >"$local_status_line"
  jq -n --arg command "$local_status_line" \
    '{"statusLine": {"type": "command", "command": $command}}' \
    >"$test_home/.claude/settings.json"

  if ! HOME="$test_home" \
    CODEX_HOME="$test_home/.codex" \
    CLAUDE_CONFIG_DIR="$test_home/.claude" \
    PYTHONPATH="$blocker" \
    "$ROOT/install.sh" >"$test_home/install.log" 2>&1; then
    sed 's/^/  /' "$test_home/install.log" >&2
    fail "Gate-only install failed without tomlkit and PyYAML"
  fi

  assert_same_link \
    "$ROOT/hooks/verify-gate.py" "$test_home/.agents/hooks/verify-gate.py"
  jq -e --arg command "$local_status_line" \
    --argjson hooks "$(managed_hooks claude \
      "$test_home/.agents/hooks/verify-gate.py")" '
    . == {
      "statusLine": {"type": "command", "command": $command},
      "hooks": $hooks
    }
  ' "$test_home/.claude/settings.json" >/dev/null ||
    fail "Gate-only install changed the local Claude status line"
  jq -e --argjson hooks "$(managed_hooks codex \
    "$test_home/.agents/hooks/verify-gate.py")" \
    '. == {"hooks": $hooks}' "$test_home/.codex/hooks.json" >/dev/null ||
    fail "Gate-only install produced unexpected Codex hooks"
  [[ -f "$local_status_line" && ! -L "$local_status_line" ]] ||
    fail "Gate-only install replaced a local status-line script"
  [[ ! -e "$test_home/.codex/AGENTS.md" && ! -e "$test_home/.claude/CLAUDE.md" && \
    ! -e "$test_home/.agents/skills" && ! -e "$test_home/.claude/skills" && \
    ! -e "$test_home/.codex/config.toml" && ! -e "$test_home/.codex/rules" ]] ||
    fail "Gate-only install installed an optional component"
  [[ -f "$test_home/.config/power-agents/components" && \
    -z "$(saved_components "$test_home")" ]] ||
    fail "Gate-only install did not save an empty component selection"
  assert_contains "$test_home/install.log" "Installed: verify gate"
}

test_component_selection() {
  local repository_links
  local test_home="$TEST_ROOT/component-selection-home"

  mkdir -p "$test_home/.codex"
  printf '%s\n' 'model = "local"' >"$test_home/.codex/config.toml"

  run_installer_args "$test_home" --components "skills, codex-rules"
  [[ "$(saved_components "$test_home")" == "skills,codex-rules" ]] ||
    fail "Installer saved an unexpected component selection"
  assert_skill_links "$test_home/.agents/skills"
  assert_skill_links "$test_home/.claude/skills"
  assert_same_link \
    "$ROOT/policies/codex/shared.rules" "$test_home/.codex/rules/shared.rules"
  [[ ! -e "$test_home/.codex/AGENTS.md" && \
    ! -e "$test_home/.claude/statusline-command.sh" ]] ||
    fail "Installer installed an unselected component"
  [[ "$(<"$test_home/.codex/config.toml")" == 'model = "local"' ]] ||
    fail "Installer changed Codex config without the status line selected"

  run_installer_args "$test_home"
  [[ "$(saved_components "$test_home")" == "skills,codex-rules" ]] ||
    fail "A plain rerun changed the saved component selection"
  assert_skill_links "$test_home/.claude/skills"
  [[ ! -e "$test_home/.claude/CLAUDE.md" ]] ||
    fail "A plain rerun installed an unselected component"

  run_installer_args "$test_home" --components all
  ln -s "$TEST_ROOT/elsewhere" "$test_home/.agents/skills/local-link"
  jq '.model = "opus" | .statusLine.padding = 2' \
    "$test_home/.claude/settings.json" \
    >"$test_home/settings.json"
  mv "$test_home/settings.json" "$test_home/.claude/settings.json"

  run_installer_args "$test_home" --components none
  [[ -z "$(saved_components "$test_home")" ]] ||
    fail "Installer did not save an empty component selection"
  repository_links="$(find "$test_home/.agents" "$test_home/.claude" \
    "$test_home/.codex" -lname "$ROOT/*" -print)"
  [[ "$repository_links" == "$test_home/.agents/hooks/verify-gate.py" ]] ||
    fail "Deselected components left repository links: $repository_links"
  [[ "$(readlink "$test_home/.agents/skills/local-link")" == \
    "$TEST_ROOT/elsewhere" ]] ||
    fail "Removing skills changed an unrelated skill link"
  jq -e --argjson hooks "$(managed_hooks claude \
    "$test_home/.agents/hooks/verify-gate.py")" \
    '. == {"model": "opus", "hooks": $hooks}' \
    "$test_home/.claude/settings.json" >/dev/null ||
    fail "Removing the status line did not keep only local Claude settings"
  assert_contains "$test_home/.codex/config.toml" 'model = "local"'
  if grep -q 'status_line' "$test_home/.codex/config.toml"; then
    fail "Removing the status line left managed Codex TUI keys"
  fi

  if run_installer_args "$test_home" --components bogus; then
    fail "Installer accepted an unknown component"
  fi
  assert_contains "$test_home/install.log" "ERROR: Unknown component: bogus"
  [[ -z "$(saved_components "$test_home")" ]] ||
    fail "Rejected component selection changed the saved selection"
}

test_component_detection() {
  local test_home="$TEST_ROOT/component-detection-home"

  run_installer "$test_home"
  rm "$test_home/.config/power-agents/components"
  rm "$test_home/.codex/rules/shared.rules"

  run_installer_args "$test_home"
  [[ "$(saved_components "$test_home")" == \
    "instructions,skills,statusline" ]] ||
    fail "Installer did not detect previously installed components"
  [[ ! -e "$test_home/.codex/rules/shared.rules" ]] ||
    fail "Installer reinstalled an undetected component"
  assert_skill_links "$test_home/.agents/skills"
}

test_component_profiles() {
  local profile_b="$TEST_ROOT/component-profiles-home/profile-b"
  local status_line_b
  local test_home="$TEST_ROOT/component-profiles-home"

  run_installer "$test_home"

  status_line_b="$profile_b/claude/statusline-command.sh"
  mkdir -p "$profile_b/claude" "$profile_b/codex"
  printf '%s\n' '[tui]' 'status_line_use_colors = true' \
    >"$profile_b/codex/config.toml"
  printf '%s\n' '#!/bin/sh' >"$status_line_b"
  jq -n --arg command "$status_line_b" \
    '{"statusLine": {"type": "command", "command": $command}}' \
    >"$profile_b/claude/settings.json"
  cp "$profile_b/codex/config.toml" "$test_home/profile-b-config.toml"

  run_installer_with_roots \
    "$test_home" "$profile_b/codex" "$profile_b/claude" --components none
  cmp -s "$test_home/profile-b-config.toml" "$profile_b/codex/config.toml" ||
    fail "Another profile's selection removed unmanaged Codex settings"
  jq -e --arg command "$status_line_b" \
    '.statusLine == {"type": "command", "command": $command}' \
    "$profile_b/claude/settings.json" >/dev/null ||
    fail "Another profile's selection removed an unmanaged Claude status line"
  assert_same_link \
    "$ROOT/instructions/general-global.md" "$test_home/.claude/CLAUDE.md"
  assert_skill_links "$test_home/.claude/skills"

  # The first profile's links still identify its components.
  run_installer_args "$test_home"
  [[ "$(saved_components "$test_home")" == \
    "instructions,skills,statusline,codex-rules" ]] ||
    fail "Switching profiles lost the first profile's components"
  assert_skill_links "$test_home/.agents/skills"

  # Changing only one agent root must not treat that root's unmanaged status
  # line as installed.
  mkdir -p "$profile_b/codex-only"
  cp "$test_home/profile-b-config.toml" "$profile_b/codex-only/config.toml"
  run_installer_with_roots \
    "$test_home" "$profile_b/codex-only" "$test_home/.claude" --components none
  cmp -s "$test_home/profile-b-config.toml" "$profile_b/codex-only/config.toml" ||
    fail "Changing only CODEX_HOME removed unmanaged Codex settings"

  run_installer "$test_home"
  run_installer_with_roots \
    "$test_home" "$test_home/.codex" "$profile_b/claude" --components none
  jq -e --arg command "$status_line_b" \
    '.statusLine == {"type": "command", "command": $command}' \
    "$profile_b/claude/settings.json" >/dev/null ||
    fail "Changing only CLAUDE_CONFIG_DIR removed an unmanaged status line"
}

test_replaced_status_line_script() {
  local script
  local test_home="$TEST_ROOT/replaced-status-line-home"

  script="$test_home/.claude/statusline-command.sh"
  run_installer "$test_home"
  rm "$script"
  printf '%s\n' '#!/bin/sh' 'echo local' >"$script"

  run_installer_args "$test_home" --components none
  [[ -f "$script" && ! -L "$script" ]] ||
    fail "Removing the status line deleted a local replacement script"
  jq -e --arg command "$script" \
    '.statusLine == {"type": "command", "command": $command}' \
    "$test_home/.claude/settings.json" >/dev/null ||
    fail "Removing the status line dropped the setting for a local script"
}

# Removal compares against the values the install wrote, not the current
# settings/codex/tui.toml, which may have changed since.
test_status_line_removal_after_update() {
  local checkout
  local config
  local old_values
  local snapshot
  local test_home="$TEST_ROOT/status-line-update-home"

  config="$test_home/.codex/config.toml"
  snapshot="$test_home/.config/power-agents/codex-tui.toml"
  old_values="$(printf '%s\n' '[tui]' 'status_line = ["old-item"]' \
    'status_line_use_colors = false')"

  run_installer "$test_home"
  cmp -s "$ROOT/settings/codex/tui.toml" "$snapshot" ||
    fail "Installer did not save the installed Codex TUI values"

  # Installed from an older tui.toml whose values still match.
  printf '%s\n' "$old_values" >"$snapshot"
  printf 'model = "local"\n%s\n' "$old_values" >"$config"
  run_installer_args "$test_home" --components none
  [[ "$(<"$config")" == 'model = "local"' ]] ||
    fail "Removal kept unchanged values from an older install"

  # A user value that equals the current tui.toml was not written by the install.
  run_installer "$test_home"
  printf '%s\n' "$old_values" >"$snapshot"
  run_installer_args "$test_home" --components none
  cmp -s <(sed -n '/^status_line/p' "$ROOT/settings/codex/tui.toml") \
    <(sed -n '/^status_line/p' "$config") ||
    fail "Removal deleted values the install did not write"

  # Without a snapshot, nothing proves ownership.
  run_installer "$test_home"
  rm "$snapshot"
  run_installer_args "$test_home" --components none
  assert_contains "$config" "status_line ="

  # Removal needs only the snapshot, even when tui.toml is now invalid.
  checkout="$TEST_ROOT/status-line-update-checkout"
  test_home="$TEST_ROOT/status-line-update-copy-home"
  config="$test_home/.codex/config.toml"
  mkdir -p "$checkout"
  tar -C "$ROOT" --exclude=.git -cf - . | tar -C "$checkout" -xf -
  INSTALLER="$checkout/install.sh" run_installer "$test_home"
  printf '%s\n' 'not toml [' >"$checkout/settings/codex/tui.toml"
  if ! INSTALLER="$checkout/install.sh" \
    run_installer_args "$test_home" --components none; then
    sed 's/^/  /' "$test_home/install.log" >&2
    fail "Status-line removal failed with an invalid current tui.toml"
  fi
  if grep -q 'status_line' "$config"; then
    fail "Removal with an invalid current tui.toml left managed keys"
  fi
}

test_codex_config_reconciliation() {
  local expected="$TEST_ROOT/expected-config.toml"
  local managed_colors
  local managed_status
  local test_home="$TEST_ROOT/config-home"

  mkdir -p "$test_home/.codex"
  cat >"$test_home/.codex/config.toml" <<'EOF'
model = "machine-local-model"
custom_flag = true

[tui] # keep this comment
theme = "dark"
status_line = [
  "old-project",
  "old-model",
] # old managed value
status_line_use_colors = false
notifications = ["local-command"]

[projects."/work/local"]
trust_level = "trusted"
EOF

  managed_status="$(sed -n 's/^[[:space:]]*\(status_line[[:space:]]*=.*\)$/\1/p' \
    "$ROOT/settings/codex/tui.toml")"
  managed_colors="$(sed -n 's/^[[:space:]]*\(status_line_use_colors[[:space:]]*=.*\)$/\1/p' \
    "$ROOT/settings/codex/tui.toml")"

  cat >"$expected" <<EOF
model = "machine-local-model"
custom_flag = true

[tui] # keep this comment
theme = "dark"
$managed_status # old managed value
$managed_colors
notifications = ["local-command"]

[projects."/work/local"]
trust_level = "trusted"
EOF

  run_installer "$test_home"
  if ! cmp -s "$expected" "$test_home/.codex/config.toml"; then
    diff -u "$expected" "$test_home/.codex/config.toml" >&2 || true
    fail "Installer did not preserve and reconcile Codex config as expected"
  fi

  run_installer "$test_home"
  cmp -s "$expected" "$test_home/.codex/config.toml" ||
    fail "Repeated install changed reconciled Codex config"
}

test_invalid_codex_config_rejection() {
  local config
  local kind
  local test_home

  for kind in invalid incompatible; do
    test_home="$TEST_ROOT/config-$kind-home"
    mkdir -p "$test_home/.codex"
    case "$kind" in
      invalid) config='model = "unterminated' ;;
      incompatible) config='tui = "not-a-table"' ;;
    esac
    printf '%s\n' "$config" >"$test_home/.codex/config.toml"

    if run_installer "$test_home"; then
      fail "Installer unexpectedly accepted a $kind Codex config"
    fi

    assert_contains "$test_home/install.log" \
      "ERROR: Invalid or unsupported Codex config:"
    [[ "$(<"$test_home/.codex/config.toml")" == "$config" ]] ||
      fail "Installer changed a rejected $kind Codex config"
    [[ ! -e "$test_home/.codex/AGENTS.md" ]] ||
      fail "Installer partially installed after rejecting a $kind Codex config"
    [[ ! -e "$test_home/.claude/CLAUDE.md" ]] ||
      fail "Installer partially installed after rejecting a $kind Codex config"
    [[ -z "$(find "$test_home/.codex" -name 'config.toml.tmp.*' -print -quit)" ]] ||
      fail "Installer left a temporary file after rejecting a $kind Codex config"
  done
}

test_nested_tui_dotted_key() {
  local test_home="$TEST_ROOT/nested-tui-key-home"

  mkdir -p "$test_home/.codex"
  cat >"$test_home/.codex/config.toml" <<'EOF'
[[hooks]]
tui.command = "local-command"
EOF

  run_installer "$test_home"

  assert_contains "$test_home/.codex/config.toml" 'tui.command = "local-command"'
  assert_contains "$test_home/.codex/config.toml" "[tui]"
}

test_codex_policy_source() {
  local expected_pattern
  local rules="$ROOT/policies/codex/shared.rules"

  for expected_pattern in \
    'pattern = [[".venv/bin/pytest", "./.venv/bin/pytest"]]' \
    'pattern = [["python", "python3"], "-m", "pytest"]' \
    'pattern = [[".venv/bin/python", "./.venv/bin/python", ".venv/bin/python3", "./.venv/bin/python3"], "-m", "pytest"]'; do
    assert_contains "$rules" "$expected_pattern"
  done

  [[ "$(grep -c 'decision = "prompt"' "$rules")" == 3 ]] ||
    fail "Codex policy does not prompt for every managed pytest invocation"
  if grep -q 'decision = "allow"' "$rules"; then
    fail "Codex pytest policy unexpectedly contains an allow decision"
  fi
}

test_codex_runtime_compatibility() {
  local command
  local codex_home="$TEST_ROOT/codex-runtime-home/config"
  local codex_version
  local decision
  local invalid_codex_home="$TEST_ROOT/codex-runtime-home/invalid-config"
  local invalid_runtime_log="$TEST_ROOT/codex-runtime-home/invalid-codex.log"
  local policy_output
  local rules="$ROOT/policies/codex/shared.rules"
  local runtime_log="$TEST_ROOT/codex-runtime-home/codex.log"
  local test_home="$TEST_ROOT/codex-runtime-home"
  local -a command_parts

  mkdir -p "$codex_home"
  cp "$ROOT/settings/codex/tui.toml" "$codex_home/config.toml"
  codex_version="$(HOME="$test_home" CODEX_HOME="$codex_home" \
    codex --version 2>>"$runtime_log")"
  echo "INFO: Testing $codex_version"
  if ! HOME="$test_home" CODEX_HOME="$codex_home" \
    codex features list >"$runtime_log" 2>&1; then
    sed 's/^/  /' "$runtime_log" >&2
    fail "Codex rejected the managed TUI settings"
  fi

  mkdir -p "$invalid_codex_home"
  printf '%s\n' '[tui]' 'status_line = 7' >"$invalid_codex_home/config.toml"
  if HOME="$test_home" CODEX_HOME="$invalid_codex_home" \
    codex features list >"$invalid_runtime_log" 2>&1; then
    fail "Codex compatibility check accepted a known-invalid TUI setting"
  fi

  for command in \
    ".venv/bin/pytest" \
    ".venv/bin/pytest tests/test_example.py" \
    ".venv/bin/pytest -c /tmp/attacker.ini /tmp/attacker_test.py" \
    "./.venv/bin/pytest" \
    "python -m pytest" \
    "python3 -m pytest tests/test_example.py" \
    ".venv/bin/python -m pytest" \
    ".venv/bin/python3 -m pytest" \
    "./.venv/bin/python -m pytest tests/test_example.py" \
    "./.venv/bin/python3 -m pytest"; do
    read -r -a command_parts <<<"$command"
    policy_output="$(HOME="$test_home" CODEX_HOME="$codex_home" \
      codex execpolicy check \
      --rules "$rules" -- "${command_parts[@]}" 2>>"$runtime_log")"
    decision="$(jq -r '.decision // "none"' <<<"$policy_output")"
    [[ "$decision" == "prompt" ]] ||
      fail "Codex policy returned '$decision' for: $command"
  done

  for command in \
    "pytest" \
    "python -m unittest" \
    "/work/project/.venv/bin/pytest" \
    "/work/project/.venv/bin/python -m pytest"; do
    read -r -a command_parts <<<"$command"
    policy_output="$(HOME="$test_home" CODEX_HOME="$codex_home" \
      codex execpolicy check \
      --rules "$rules" -- "${command_parts[@]}" 2>>"$runtime_log")"
    decision="$(jq -r '.decision // "none"' <<<"$policy_output")"
    [[ "$decision" == "none" ]] ||
      fail "Codex policy unexpectedly matched: $command"
  done
}

test_claude_runtime_compatibility() {
  local claude_root="$TEST_ROOT/claude-runtime-home/config/claude"
  local claude_version
  local codex_root="$TEST_ROOT/claude-runtime-home/config/codex"
  local invalid_hooks_runtime_log="$TEST_ROOT/claude-runtime-home/invalid-hooks-claude-doctor.log"
  local invalid_runtime_log="$TEST_ROOT/claude-runtime-home/invalid-claude-doctor.log"
  local runtime_log="$TEST_ROOT/claude-runtime-home/claude-doctor.log"
  local test_home="$TEST_ROOT/claude-runtime-home"

  run_installer_with_roots "$test_home" "$codex_root" "$claude_root" \
    --components all
  claude_version="$(HOME="$test_home" CLAUDE_CONFIG_DIR="$claude_root" \
    claude --version)"
  echo "INFO: Testing $claude_version"
  if ! HOME="$test_home" \
    CLAUDE_CONFIG_DIR="$claude_root" \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    DISABLE_AUTOUPDATER=1 \
    claude doctor >"$runtime_log" 2>&1; then
    sed 's/^/  /' "$runtime_log" >&2
    fail "Claude Code doctor failed"
  fi

  assert_contains "$runtime_log" "Claude Code doctor"
  if grep -Fq "Invalid settings" "$runtime_log"; then
    sed 's/^/  /' "$runtime_log" >&2
    fail "Claude Code rejected the installed settings"
  fi

  printf '%s\n' '{' >"$claude_root/settings.json"
  HOME="$test_home" \
    CLAUDE_CONFIG_DIR="$claude_root" \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    DISABLE_AUTOUPDATER=1 \
    claude doctor >"$invalid_runtime_log" 2>&1 || true
  assert_contains "$invalid_runtime_log" "Invalid settings"

  printf '%s\n' \
    '{"hooks": {"Stop": [{"hooks": [{"type": "bogus", "command": "true"}]}]}}' \
    >"$claude_root/settings.json"
  HOME="$test_home" \
    CLAUDE_CONFIG_DIR="$claude_root" \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    DISABLE_AUTOUPDATER=1 \
    claude doctor >"$invalid_hooks_runtime_log" 2>&1 || true
  assert_contains "$invalid_hooks_runtime_log" "Invalid settings"
  assert_contains "$invalid_hooks_runtime_log" "hooks.Stop"
}

test_install_conflicts() {
  local file_home="$TEST_ROOT/file-conflict-home"
  local skill_dir
  local skill_home="$TEST_ROOT/skill-conflict-home"
  local skill_name
  local symlink_home="$TEST_ROOT/symlink-conflict-home"
  local wrong_root_home="$TEST_ROOT/wrong-skill-root-home"
  local wrong_target="$TEST_ROOT/wrong-target"

  mkdir -p "$file_home/.codex"
  printf '%s\n' "keep this file" >"$file_home/.codex/AGENTS.md"
  expect_installer_failure "$file_home"
  [[ "$(<"$file_home/.codex/AGENTS.md")" == "keep this file" ]] ||
    fail "Installer changed a conflicting file"
  [[ ! -e "$file_home/.claude/CLAUDE.md" ]] ||
    fail "Installer partially installed after finding a conflict"

  skill_dir="$(find "$ROOT/skills" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  skill_name="$(basename "$skill_dir")"
  mkdir -p "$skill_home/.agents/skills/$skill_name"
  printf '%s\n' "keep this skill" >"$skill_home/.agents/skills/$skill_name/marker"
  expect_installer_failure "$skill_home"
  [[ -f "$skill_home/.agents/skills/$skill_name/marker" ]] ||
    fail "Installer changed a conflicting same-name skill"
  [[ ! -e "$skill_home/.claude/CLAUDE.md" ]] ||
    fail "Installer partially installed after finding a skill conflict"

  mkdir -p "$wrong_root_home/.agents" "$wrong_root_home/elsewhere"
  ln -s "$wrong_root_home/elsewhere" "$wrong_root_home/.agents/skills"
  expect_installer_failure "$wrong_root_home"
  [[ "$(readlink "$wrong_root_home/.agents/skills")" == \
    "$wrong_root_home/elsewhere" ]] ||
    fail "Installer changed an unrelated skill-directory symlink"

  mkdir -p "$symlink_home/.claude"
  printf '%s\n' "wrong target" >"$wrong_target"
  ln -s "$wrong_target" "$symlink_home/.claude/statusline-command.sh"
  expect_installer_failure "$symlink_home"
  [[ "$(readlink "$symlink_home/.claude/statusline-command.sh")" == "$wrong_target" ]] ||
    fail "Installer changed an incorrect symlink"
}

test_status_line() {
  local actual
  local c1_control
  local error_output="$TEST_ROOT/status-line.err"
  local expected
  local injected_json
  local repo="$TEST_ROOT/status-repo"

  printf -v c1_control '\302\233'

  git init -q -b feature/test "$repo"
  actual="$({
    printf '%s\n' \
      "{\"workspace\":{\"current_dir\":\"$repo\",\"repo\":{\"name\":\"power-agents\"}},\"model\":{\"display_name\":\"GPT-5\"},\"effort\":{\"level\":\"high\"},\"fast_mode\":true,\"context_window\":{\"used_percentage\":68.6},\"rate_limits\":{\"five_hour\":{\"used_percentage\":74.6},\"seven_day\":{\"used_percentage\":90.2}}}"
  } | render_status_line)"

  expected=$'\033[1;34mpower-agents\033[0m \033[35mfeature/test\033[0m'
  expected+=$'\033[2m │ \033[0m\033[36mGPT-5\033[0m\033[2m · \033[0m'
  expected+=$'\033[36mhigh\033[0m\033[2m · \033[0m\033[36mfast\033[0m'
  expected+=$'\033[2m │ \033[0m\033[36mctx 69%\033[0m'
  expected+=$'\033[2m │ \033[0m\033[33m5h 75%\033[0m\033[2m · \033[0m'
  expected+=$'\033[31m7d 90%\033[0m'

  [[ "$actual" == "$expected" ]] || fail "Status line output was unexpected"

  injected_json="$(jq -cn \
    --arg cwd "$TEST_ROOT" \
    --arg repo 'trusted\e[31mINJECT' \
    '{workspace: {current_dir: $cwd, repo: {name: $repo}}}')"
  actual="$(printf '%s\n' "$injected_json" | render_status_line)"
  expected=$'\033[1;34mtrusted\\e[31mINJECT\033[0m'
  [[ "$actual" == "$expected" ]] ||
    fail "Status line expanded a literal backslash escape from workspace text"

  injected_json="$(jq -cn \
    --arg cwd "$TEST_ROOT" \
    --arg repo $'trusted\033]52;c;PAYLOAD\a' \
    --arg model "GPT${c1_control}31mINJECT" \
    --arg effort $'high\nINJECT' \
    '{
      workspace: {current_dir: $cwd, repo: {name: $repo}},
      model: {display_name: $model},
      effort: {level: $effort}
    }')"
  [[ "$injected_json" == *'\u001b'* ]] ||
    fail "Status-line injection fixture does not contain a JSON ESC character"
  [[ "$injected_json" == *"$c1_control"* ]] ||
    fail "Status-line injection fixture does not contain a C1 control character"

  actual="$(printf '%s\n' "$injected_json" | render_status_line)"
  expected=$'\033[1;34mtrusted]52;c;PAYLOAD\033[0m'
  expected+=$'\033[2m │ \033[0m\033[36mGPT31mINJECT\033[0m'
  expected+=$'\033[2m · \033[0m\033[36mhighINJECT\033[0m'
  [[ "$actual" == "$expected" ]] ||
    fail "Status line emitted control characters from workspace text"

  injected_json="$(jq -cn \
    --arg cwd "$TEST_ROOT" \
    '{
      workspace: {current_dir: $cwd, repo: {name: "power-agents"}},
      model: {display_name: "GPT-5"},
      context_window: {used_percentage: "unknown"},
      rate_limits: {
        five_hour: {used_percentage: true},
        seven_day: {used_percentage: {value: 50}}
      }
    }')"
  actual="$(printf '%s\n' "$injected_json" | render_status_line 2>"$error_output")"
  expected=$'\033[1;34mpower-agents\033[0m'
  expected+=$'\033[2m │ \033[0m\033[36mGPT-5\033[0m'
  [[ "$actual" == "$expected" ]] ||
    fail "Status line displayed non-numeric percentage values"
  [[ ! -s "$error_output" ]] ||
    fail "Status line wrote errors for non-numeric percentage values"

  injected_json="$(jq -cn \
    --arg cwd "$TEST_ROOT" \
    '{workspace: {current_dir: $cwd, repo: {name: "power-agents"}},
      context_window: {used_percentage: null}}')"
  actual="$(printf '%s\n' "$injected_json" | render_status_line 2>"$error_output")"
  expected=$'\033[1;34mpower-agents\033[0m'
  [[ "$actual" == "$expected" ]] ||
    fail "Status line displayed a null percentage value"
  [[ ! -s "$error_output" ]] ||
    fail "Status line wrote errors for a null percentage value"

  injected_json='{
    "workspace": {"current_dir": "/tmp", "repo": {"name": "power-agents"}},
    "context_window": {"used_percentage": 1e999},
    "rate_limits": {
      "five_hour": {"used_percentage": -1},
      "seven_day": {"used_percentage": 101}
    }
  }'
  actual="$(printf '%s\n' "$injected_json" | render_status_line 2>"$error_output")"
  expected=$'\033[1;34mpower-agents\033[0m'
  [[ "$actual" == "$expected" ]] ||
    fail "Status line displayed an out-of-range percentage value"
  [[ ! -s "$error_output" ]] ||
    fail "Status line wrote errors for out-of-range percentage values"
}

test_sync() {
  local clone
  local dirty_kind
  local failed_commit
  local remote
  local source
  local sync_home
  local sync_root="$TEST_ROOT/sync"
  local update_commit

  clone="$sync_root/clone"
  remote="$sync_root/remote.git"
  source="$sync_root/source"
  sync_home="$sync_root/home"

  mkdir -p "$sync_home"
  git init -q --bare -b main "$remote"
  git init -q -b main "$source"
  git -C "$source" config user.name "Power Agents Test"
  git -C "$source" config user.email "power-agents@example.invalid"
  git -C "$source" config commit.gpgsign false

  cp "$ROOT/sync.sh" "$source/sync.sh"
  cat >"$source/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$ROOT/version" "$HOME/installed-version"
EOF
  chmod +x "$source/install.sh" "$source/sync.sh"
  printf '%s\n' "initial" >"$source/version"
  git -C "$source" add install.sh sync.sh version
  git -C "$source" commit -qm "initial baseline"
  git -C "$source" remote add origin "$remote"
  git -C "$source" push -qu -u origin main
  git clone -q "$remote" "$clone"

  printf '%s\n' "updated" >"$source/version"
  git -C "$source" commit -qam "update"
  update_commit="$(git -C "$source" rev-parse HEAD)"
  git -C "$source" push -q

  for dirty_kind in unstaged staged; do
    printf '%s\n' "$dirty_kind-local-change" >"$clone/version"
    if [[ "$dirty_kind" == "staged" ]]; then
      git -C "$clone" add version
    fi
    if HOME="$sync_home" \
      "$clone/sync.sh" >"$sync_root/dirty-$dirty_kind.log" 2>&1; then
      fail "Sync accepted a $dirty_kind tracked change"
    fi
    assert_contains "$sync_root/dirty-$dirty_kind.log" \
      "Tracked or staged changes are present; commit or discard them before syncing."
    [[ "$(git -C "$clone" rev-parse HEAD)" != "$update_commit" ]] ||
      fail "Sync changed HEAD with a $dirty_kind tracked change"
    [[ "$(<"$clone/version")" == "$dirty_kind-local-change" ]] ||
      fail "Sync changed a $dirty_kind tracked change"
    git -C "$clone" reset -q HEAD -- version
    git -C "$clone" checkout -q -- version
  done

  printf '%s\n' "keep this untracked file" >"$clone/local-note"
  HOME="$sync_home" "$clone/sync.sh" >"$sync_root/update.log" 2>&1
  [[ "$(git -C "$clone" rev-parse HEAD)" == "$update_commit" ]] ||
    fail "Sync did not fast-forward to the upstream commit"
  [[ "$(<"$sync_home/installed-version")" == "updated" ]] ||
    fail "Sync did not install the update"
  [[ "$(<"$clone/local-note")" == "keep this untracked file" ]] ||
    fail "Sync changed an unrelated untracked file"

  printf '%s\n' "failed-install" >"$source/version"
  cat >"$source/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$ROOT/version" "$HOME/installed-version"
exit 91
EOF
  git -C "$source" commit -qam "update with failing installer"
  failed_commit="$(git -C "$source" rev-parse HEAD)"
  git -C "$source" push -q

  if HOME="$sync_home" \
    "$clone/sync.sh" >"$sync_root/failed-install.log" 2>&1; then
    fail "Sync accepted an update whose installer failed"
  fi
  assert_contains "$sync_root/failed-install.log" \
    "ERROR: Sync failed after update activation; restoring the previous version."
  assert_contains "$sync_root/failed-install.log" \
    "Previous checkout and installed configuration restored."
  [[ "$(git -C "$clone" rev-parse HEAD)" == "$update_commit" ]] ||
    fail "Sync did not restore HEAD after installer failure at $failed_commit"
  [[ "$(<"$sync_home/installed-version")" == "updated" ]] ||
    fail "Sync did not restore the installed version after installer failure"
}

test_make_targets() {
  local actual
  local target

  actual="$(make --no-print-directory -C "$ROOT")"
  assert_contains <(printf '%s\n' "$actual") "Usage: make <target>"

  for target in install sync test check ci eval coding-eval; do
    actual="$(make --no-print-directory -n -C "$ROOT" "$target")"
    case "$target" in
      install) [[ "$actual" == "./install.sh" ]] ;;
      sync) [[ "$actual" == "./sync.sh" ]] ;;
      test) [[ "$actual" == "./tests/run.sh" ]] ;;
      check) [[ "$actual" == "./scripts/check.sh" ]] ;;
      ci) [[ "$actual" == "./scripts/ci.sh" ]] ;;
      eval) [[ "$actual" == "python3 ./scripts/run-evals.py " ]] ;;
      coding-eval) [[ "$actual" == "python3 ./scripts/run-coding-evals.py " ]] ;;
    esac || fail "Unexpected make $target command: $actual"
  done
}

test_ci_workflow() {
  local workflow="$ROOT/.github/workflows/checks.yml"

  assert_contains "$workflow" "python3-tomlkit"
  assert_contains "$workflow" "python3-yaml"
  assert_contains "$workflow" "actions/setup-node@249970729cb0ef3589644e2896645e5dc5ba9c38"
  assert_contains "$workflow" "@openai/codex@latest"
  assert_contains "$workflow" "@anthropic-ai/claude-code@latest"
  assert_contains "$workflow" "POWER_AGENTS_REQUIRE_AGENT_RUNTIMES: 1"
  assert_contains "$workflow" "run: make ci"

  if grep -Fq "run: make check" "$workflow"; then
    fail "GitHub workflow bypasses the shared CI target"
  fi
}

test_project_instruction_entrypoints
pass "AGENTS.md is the sole project instruction entrypoint"
python3 "$ROOT/tests/test_validate_skills.py"
pass "shared skill metadata and evaluation validator"
python3 "$ROOT/tests/test_check_skill_upstreams.py"
pass "upstream skill pin parsing"
python3 "$ROOT/tests/test_coding_fixtures.py"
python3 "$ROOT/tests/test_run_coding_evals.py"
pass "coding fixture integrity and isolated runtime adapters"
python3 "$ROOT/tests/test_run_evals.py"
pass "isolated evaluation runner with a fake runtime"
test_installer_rejects_invalid_skill_metadata
pass "installer rejects invalid skill metadata before installation"
python3 "$ROOT/tests/test_reconcile_codex_config.py"
pass "Codex TOML reconciler"
python3 "$ROOT/tests/test_reconcile_hooks.py"
pass "verify-gate hook reconciler"
python3 "$ROOT/tests/test_verify_gate.py"
pass "verify gate and cross-review hook with stub reviewers"
test_clean_install_and_idempotence
pass "clean install, stale-link cleanup, unrelated-skill preservation, and idempotence"
test_custom_agent_roots
pass "custom Codex and Claude configuration roots"
test_invalid_agent_roots
pass "unsafe, root-aliased, and colliding agent roots fail before installation"
test_transaction_rollback
pass "transactional rollback after a managed-file activation failure"
test_claude_settings_reconciliation
pass "Claude settings preservation and managed-key reconciliation"
test_claude_settings_rejection
pass "invalid Claude settings fail without partial installation"
test_foreign_hooks_preservation
pass "foreign Claude and Codex hooks survive install and reinstall"
test_legacy_verify_gate_rejection
pass "legacy standalone verify gate hooks fail without partial installation"
test_skill_link_migration
pass "legacy whole-directory skill links migrate to per-skill links"
test_gate_only_install
pass "default install adds only the verify gate and needs no optional modules"
test_component_selection
pass "optional components install, persist, and remove only owned links and keys"
test_component_detection
pass "installs without a saved selection keep their detected components"
test_component_profiles
pass "a selection saved for other agent roots is not applied to these roots"
test_replaced_status_line_script
pass "a status-line script replaced by a local file keeps its setting"
test_status_line_removal_after_update
pass "status-line removal compares against the values the install wrote"
test_codex_config_reconciliation
pass "Codex config preservation and managed-key reconciliation"
test_invalid_codex_config_rejection
pass "invalid and incompatible Codex configs fail without partial installation"
test_nested_tui_dotted_key
pass "nested dotted TUI-like keys remain unmanaged"
test_codex_policy_source
pass "Codex command policy source requires approval for unsandboxed project tests"
if command -v codex >/dev/null 2>&1; then
  test_codex_runtime_compatibility
  pass "Codex runtime validates managed TUI settings and command policy"
elif [[ "${POWER_AGENTS_REQUIRE_AGENT_RUNTIMES:-0}" == 1 ]]; then
  fail "Codex runtime compatibility is required, but codex is not installed"
else
  skip "Codex runtime compatibility (codex is not installed)"
fi
if command -v claude >/dev/null 2>&1; then
  test_claude_runtime_compatibility
  pass "Claude Code runtime validates installed settings"
elif [[ "${POWER_AGENTS_REQUIRE_AGENT_RUNTIMES:-0}" == 1 ]]; then
  fail "Claude runtime compatibility is required, but claude is not installed"
else
  skip "Claude runtime compatibility (claude is not installed)"
fi
test_install_conflicts
pass "file, same-name skill, and incorrect-symlink conflict refusal"
test_status_line
pass "status-line output and input validation"
test_sync
pass "sync fast-forwards, refuses local changes, and rolls back failed activation"
test_make_targets
pass "Make targets"
test_ci_workflow
pass "GitHub workflow uses the shared CI pipeline and dependencies"
