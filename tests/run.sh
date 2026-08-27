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
  local test_home="$1"

  case "$test_home" in
    "$TEST_ROOT"/*) ;;
    *) fail "Refusing to run installer with non-test HOME: $test_home" ;;
  esac

  mkdir -p "$test_home"
  HOME="$test_home" \
    PYTHONPATH="$TOMLKIT_SITE_PACKAGES${PYTHONPATH:+:$PYTHONPATH}" \
    "$ROOT/install.sh" >"$test_home/install.log" 2>&1
}

expect_installer_failure() {
  local test_home="$1"

  if run_installer "$test_home"; then
    fail "Installer unexpectedly accepted conflict in $test_home"
  fi
  assert_contains "$test_home/install.log" "ERROR: Refusing to replace existing path:"
}

render_status_line() {
  env -u SSH_CONNECTION -u SSH_TTY bash \
    "$ROOT/settings/claude/statusline-command.sh"
}

frontmatter_value() {
  local file="$1"
  local key="$2"

  awk -v key="$key" '
    NR == 1 {
      if ($0 != "---") {
        exit
      }
      in_frontmatter = 1
      next
    }

    in_frontmatter && $0 == "---" {
      exit
    }

    in_frontmatter && index($0, key ":") == 1 {
      value = substr($0, length(key) + 2)
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      print value
      exit
    }
  ' "$file"
}

unquote() {
  local value="$1"

  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value#\"}"
    value="${value%\"}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value#\'}"
    value="${value%\'}"
  fi

  printf '%s' "$value"
}

test_skill_metadata() {
  local description
  local folder_name
  local name
  local skill_dir
  local skill_dirs=("$ROOT"/skills/*/)
  local skill_file

  ((${#skill_dirs[@]} > 0)) || fail "No skill directories found"

  for skill_dir in "${skill_dirs[@]}"; do
    folder_name="$(basename "$skill_dir")"
    skill_file="${skill_dir}SKILL.md"
    [[ "$folder_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] ||
      fail "Invalid skill directory name: $folder_name"
    [[ -f "$skill_file" ]] || fail "Missing skill metadata: $skill_file"
    [[ "$(sed -n '1p' "$skill_file")" == "---" ]] ||
      fail "SKILL.md must start with YAML frontmatter: $skill_file"
    awk '
      NR > 1 && $0 == "---" {
        found_end = 1
        exit
      }

      END {
        exit !found_end
      }
    ' "$skill_file" || fail "Unclosed YAML frontmatter: $skill_file"

    name="$(unquote "$(frontmatter_value "$skill_file" name)")"
    description="$(unquote "$(frontmatter_value "$skill_file" description)")"
    [[ "$name" == "$folder_name" ]] ||
      fail "Skill name '$name' does not match directory '$folder_name'"
    [[ -n "$description" ]] || fail "Missing skill description: $skill_file"
  done
}

test_clean_install_and_idempotence() {
  local claude_settings_before
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
  jq -e '
    . == {
      "statusLine": {
        "type": "command",
        "command": "~/.claude/statusline-command.sh"
      }
    }
  ' "$test_home/.claude/settings.json" >/dev/null ||
    fail "Clean install produced unexpected Claude settings"
  assert_same_link \
    "$ROOT/policies/codex/shared.rules" \
    "$test_home/.codex/rules/shared.rules"
  cmp -s "$ROOT/settings/codex/tui.toml" "$test_home/.codex/config.toml" ||
    fail "Clean install produced unexpected Codex config"

  claude_settings_before="$(cksum "$test_home/.claude/settings.json")"
  config_before="$(cksum "$test_home/.codex/config.toml")"
  run_installer "$test_home"
  [[ "$(cksum "$test_home/.claude/settings.json")" == "$claude_settings_before" ]] ||
    fail "Repeated install changed Claude settings"
  [[ "$(cksum "$test_home/.codex/config.toml")" == "$config_before" ]] ||
    fail "Repeated install changed Codex config"
  assert_skill_links "$test_home/.agents/skills"
  assert_skill_links "$test_home/.claude/skills"
  [[ -z "$(find "$test_home/.codex" -name 'config.toml.tmp.*' -print -quit)" ]] ||
    fail "Installer left a temporary Codex config behind"
  [[ -z "$(find "$test_home/.claude" -name 'settings.json.tmp.*' -print -quit)" ]] ||
    fail "Installer left a temporary Claude settings file behind"
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
  jq -e '
    . == {
      "model": "opus",
      "permissions": {
        "allow": ["Read"]
      },
      "statusLine": {
        "type": "command",
        "command": "~/.claude/statusline-command.sh"
      }
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

test_codex_command_policy() {
  local command
  local decision
  local expected_pattern
  local policy_output
  local rules="$ROOT/policies/codex/shared.rules"
  local -a command_parts

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

  if ! command -v codex >/dev/null 2>&1; then
    return
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
    policy_output="$(codex execpolicy check \
      --rules "$rules" -- "${command_parts[@]}")"
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
    policy_output="$(codex execpolicy check \
      --rules "$rules" -- "${command_parts[@]}")"
    decision="$(jq -r '.decision // "none"' <<<"$policy_output")"
    [[ "$decision" == "none" ]] ||
      fail "Codex policy unexpectedly matched: $command"
  done
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
}

test_sync_signature_verification() {
  local allowlist
  local clone
  local fingerprint
  local gpg_home
  local reported_primary
  local reported_signer
  local remote
  local signing_fingerprint
  local source
  local sync_home
  local sync_root="$TEST_ROOT/sync-verification"
  local trusted_commit
  local unsigned_commit

  allowlist="$sync_root/home/.config/power-agents/trusted-signing-keys"
  clone="$sync_root/clone"
  gpg_home="$sync_root/gnupg"
  remote="$sync_root/remote.git"
  source="$sync_root/source"
  sync_home="$sync_root/home"

  mkdir -p "$gpg_home" "$sync_home/.config/power-agents"
  chmod 700 "$gpg_home"
  GNUPGHOME="$gpg_home" gpg --batch --quiet --pinentry-mode loopback \
    --passphrase '' --quick-generate-key \
    'Power Agents Test <power-agents@example.invalid>' rsa2048 cert 0
  fingerprint="$(GNUPGHOME="$gpg_home" gpg --batch --with-colons \
    --list-secret-keys 2>/dev/null |
    awk -F: '$1 == "fpr" { print $10; exit }')"
  [[ "$fingerprint" =~ ^[[:xdigit:]]{40}$ ]] ||
    fail "Test primary key did not have a full OpenPGP fingerprint"
  GNUPGHOME="$gpg_home" gpg --batch --quiet --pinentry-mode loopback \
    --passphrase '' --quick-add-key "$fingerprint" rsa2048 sign 0
  signing_fingerprint="$(GNUPGHOME="$gpg_home" gpg --batch --with-colons \
    --list-secret-keys 2>/dev/null |
    awk -F: '$1 == "fpr" { count++; if (count == 2) { print $10; exit } }')"
  [[ "$signing_fingerprint" =~ ^[[:xdigit:]]{40}$ ]] ||
    fail "Test signing subkey did not have a full OpenPGP fingerprint"
  [[ "$signing_fingerprint" != "$fingerprint" ]] ||
    fail "Test signing subkey unexpectedly matched the primary key"

  git init -q --bare -b main "$remote"
  git init -q -b main "$source"
  git -C "$source" config user.name "Power Agents Test"
  git -C "$source" config user.email "power-agents@example.invalid"
  git -C "$source" config user.signingkey "$fingerprint"
  git -C "$source" config gpg.format openpgp
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
  git -C "$source" commit -qm "initial unsigned baseline"
  git -C "$source" remote add origin "$remote"
  git -C "$source" push -qu -u origin main
  git clone -q "$remote" "$clone"

  printf '%s\n' "signed" >"$source/version"
  GNUPGHOME="$gpg_home" git -C "$source" commit -q \
    -S"$fingerprint" -am "trusted signed update"
  trusted_commit="$(git -C "$source" rev-parse HEAD)"
  read -r reported_signer reported_primary < <(
    GNUPGHOME="$gpg_home" git -C "$source" show -s \
      --format='%GF %GP' "$trusted_commit" 2>/dev/null
  )
  [[ "$reported_signer" == "$signing_fingerprint" ]] ||
    fail "Test commit was not signed by the signing subkey"
  [[ "$reported_primary" == "$fingerprint" ]] ||
    fail "Git did not report the expected primary signing-key fingerprint"
  git -C "$source" push -q

  if HOME="$sync_home" GNUPGHOME="$gpg_home" \
    "$clone/sync.sh" >"$sync_root/missing-allowlist.log" 2>&1; then
    fail "Sync accepted an update without a trusted signer allowlist"
  fi
  assert_contains "$sync_root/missing-allowlist.log" \
    "Missing trusted signer allowlist:"
  [[ "$(git -C "$clone" rev-parse HEAD)" != "$trusted_commit" ]] ||
    fail "Sync changed HEAD without a trusted signer allowlist"
  [[ ! -e "$sync_home/installed-version" ]] ||
    fail "Sync ran the installer without a trusted signer allowlist"

  printf '%s\n' "$fingerprint" >"$clone/repository-signers"
  ln -s "$clone/repository-signers" "$allowlist"
  if HOME="$sync_home" GNUPGHOME="$gpg_home" \
    "$clone/sync.sh" >"$sync_root/repository-allowlist.log" 2>&1; then
    fail "Sync accepted a signer allowlist controlled by the repository"
  fi
  assert_contains "$sync_root/repository-allowlist.log" \
    "Trusted signer allowlist must be stored outside the repository."
  rm "$allowlist"

  printf '%040d\n' 0 >"$allowlist"
  if HOME="$sync_home" GNUPGHOME="$gpg_home" \
    "$clone/sync.sh" >"$sync_root/untrusted-signer.log" 2>&1; then
    fail "Sync accepted a signed commit from an unlisted key"
  fi
  assert_contains "$sync_root/untrusted-signer.log" \
    "Incoming commit $trusted_commit is not signed by a trusted key."
  [[ "$(git -C "$clone" rev-parse HEAD)" != "$trusted_commit" ]] ||
    fail "Sync changed HEAD for an unlisted signing key"
  [[ ! -e "$sync_home/installed-version" ]] ||
    fail "Sync ran the installer for an unlisted signing key"

  printf '%s\n' "$fingerprint" >"$allowlist"
  HOME="$sync_home" GNUPGHOME="$gpg_home" \
    "$clone/sync.sh" >"$sync_root/trusted-update.log" 2>&1
  [[ "$(git -C "$clone" rev-parse HEAD)" == "$trusted_commit" ]] ||
    fail "Sync did not fast-forward to a trusted signed commit"
  [[ "$(<"$sync_home/installed-version")" == "signed" ]] ||
    fail "Sync did not install the trusted signed update"

  printf '%s\n' "signed-two" >"$source/version"
  GNUPGHOME="$gpg_home" git -C "$source" commit -q \
    -S"$fingerprint" -am "second trusted signed update"
  printf '%s\n' "unsigned" >"$source/version"
  git -C "$source" commit -qam "unsigned update"
  unsigned_commit="$(git -C "$source" rev-parse HEAD)"
  git -C "$source" push -q

  if HOME="$sync_home" GNUPGHOME="$gpg_home" \
    "$clone/sync.sh" >"$sync_root/unsigned-update.log" 2>&1; then
    fail "Sync accepted an unsigned incoming commit"
  fi
  assert_contains "$sync_root/unsigned-update.log" \
    "Signature verification failed for incoming commit $unsigned_commit."
  [[ "$(git -C "$clone" rev-parse HEAD)" == "$trusted_commit" ]] ||
    fail "Sync partially applied commits before rejecting an unsigned update"
  [[ "$(<"$sync_home/installed-version")" == "signed" ]] ||
    fail "Sync ran incoming code before rejecting an unsigned update"
}

test_make_targets() {
  local actual
  local target

  actual="$(make --no-print-directory -C "$ROOT")"
  assert_contains <(printf '%s\n' "$actual") "Usage: make <target>"

  for target in install sync test check ci; do
    actual="$(make --no-print-directory -n -C "$ROOT" "$target")"
    case "$target" in
      install) [[ "$actual" == "./install.sh" ]] ;;
      sync) [[ "$actual" == "./sync.sh" ]] ;;
      test) [[ "$actual" == "./tests/run.sh" ]] ;;
      check) [[ "$actual" == "./scripts/check.sh" ]] ;;
      ci) [[ "$actual" == "./scripts/ci.sh" ]] ;;
    esac || fail "Unexpected make $target command: $actual"
  done
}

test_ci_workflow() {
  local workflow="$ROOT/.github/workflows/checks.yml"

  assert_contains "$workflow" "python3-tomlkit"
  assert_contains "$workflow" "run: make ci"

  if grep -Fq "run: make check" "$workflow"; then
    fail "GitHub workflow bypasses the shared CI target"
  fi
}

test_skill_metadata
pass "skill structure and metadata"
python3 "$ROOT/tests/test_reconcile_codex_config.py"
pass "Codex TOML reconciler"
test_clean_install_and_idempotence
pass "clean install, stale-link cleanup, unrelated-skill preservation, and idempotence"
test_claude_settings_reconciliation
pass "Claude settings preservation and managed-key reconciliation"
test_claude_settings_rejection
pass "invalid Claude settings fail without partial installation"
test_skill_link_migration
pass "legacy whole-directory skill links migrate to per-skill links"
test_codex_config_reconciliation
pass "Codex config preservation and managed-key reconciliation"
test_invalid_codex_config_rejection
pass "invalid and incompatible Codex configs fail without partial installation"
test_nested_tui_dotted_key
pass "nested dotted TUI-like keys remain unmanaged"
test_codex_command_policy
pass "Codex command policy requires approval for unsandboxed project tests"
test_install_conflicts
pass "file, same-name skill, and incorrect-symlink conflict refusal"
test_status_line
pass "status-line output"
test_sync_signature_verification
pass "sync verifies every incoming commit before activation"
test_make_targets
pass "Make targets"
test_ci_workflow
pass "GitHub workflow uses the shared CI pipeline and dependencies"
