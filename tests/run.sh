#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/power-agents-tests.XXXXXX")"

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
  HOME="$test_home" "$ROOT/install.sh" >"$test_home/install.log" 2>&1
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
  local config_before
  local test_home="$TEST_ROOT/clean-home"

  run_installer "$test_home"

  assert_same_link \
    "$ROOT/instructions/general-global.md" "$test_home/.codex/AGENTS.md"
  assert_same_link \
    "$ROOT/instructions/general-global.md" "$test_home/.claude/CLAUDE.md"
  assert_same_link "$ROOT/skills" "$test_home/.agents/skills"
  assert_same_link "$ROOT/skills" "$test_home/.claude/skills"
  assert_same_link \
    "$ROOT/settings/claude/statusline-command.sh" \
    "$test_home/.claude/statusline-command.sh"
  assert_same_link \
    "$ROOT/policies/codex/shared.rules" \
    "$test_home/.codex/rules/shared.rules"
  cmp -s "$ROOT/settings/codex/tui.toml" "$test_home/.codex/config.toml" ||
    fail "Clean install produced unexpected Codex config"

  config_before="$(cksum "$test_home/.codex/config.toml")"
  run_installer "$test_home"
  [[ "$(cksum "$test_home/.codex/config.toml")" == "$config_before" ]] ||
    fail "Repeated install changed Codex config"
  assert_same_link "$ROOT/skills" "$test_home/.agents/skills"
  [[ -z "$(find "$test_home/.codex" -name 'config.toml.tmp.*' -print -quit)" ]] ||
    fail "Installer left a temporary Codex config behind"
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
$managed_status
$managed_colors
theme = "dark"
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

test_codex_command_policy() {
  local command
  local decision
  local policy_output
  local pytest_rule
  local rules="$ROOT/policies/codex/shared.rules"
  local -a command_parts

  pytest_rule="$(awk '
    /^prefix_rule\([[:space:]]*$/ {
      rule = $0 ORS
      next
    }

    rule != "" {
      rule = rule $0 ORS
    }

    rule != "" && /^\)[[:space:]]*$/ {
      if (rule ~ /pattern[[:space:]]*=[[:space:]]*\["[.]venv\/bin\/pytest"\]/) {
        printf "%s", rule
        exit
      }
      rule = ""
    }
  ' "$rules")"

  if [[ "$pytest_rule" != *'decision = "prompt"'* ||
    "$pytest_rule" == *'decision = "allow"'* ]]; then
    fail "Codex policy does not require approval for unsandboxed project tests"
  fi

  if ! command -v codex >/dev/null 2>&1; then
    return
  fi

  for command in \
    ".venv/bin/pytest" \
    ".venv/bin/pytest tests/test_example.py" \
    ".venv/bin/pytest -c /tmp/attacker.ini /tmp/attacker_test.py"; do
    read -r -a command_parts <<<"$command"
    policy_output="$(codex execpolicy check \
      --rules "$rules" -- "${command_parts[@]}")"
    decision="$(jq -r '.decision // "none"' <<<"$policy_output")"
    [[ "$decision" == "prompt" ]] ||
      fail "Codex policy returned '$decision' for: $command"
  done

  policy_output="$(codex execpolicy check \
    --rules "$rules" -- python -m pytest)"
  decision="$(jq -r '.decision // "none"' <<<"$policy_output")"
  [[ "$decision" == "none" ]] ||
    fail "Codex policy unexpectedly matched: python -m pytest"
}

test_install_conflicts() {
  local file_home="$TEST_ROOT/file-conflict-home"
  local directory_home="$TEST_ROOT/directory-conflict-home"
  local symlink_home="$TEST_ROOT/symlink-conflict-home"
  local wrong_target="$TEST_ROOT/wrong-target"

  mkdir -p "$file_home/.codex"
  printf '%s\n' "keep this file" >"$file_home/.codex/AGENTS.md"
  expect_installer_failure "$file_home"
  [[ "$(<"$file_home/.codex/AGENTS.md")" == "keep this file" ]] ||
    fail "Installer changed a conflicting file"
  [[ ! -e "$file_home/.claude/CLAUDE.md" ]] ||
    fail "Installer partially installed after finding a conflict"

  mkdir -p "$directory_home/.agents/skills"
  printf '%s\n' "keep this directory" >"$directory_home/.agents/skills/marker"
  expect_installer_failure "$directory_home"
  [[ -f "$directory_home/.agents/skills/marker" ]] ||
    fail "Installer changed a conflicting directory"

  mkdir -p "$symlink_home/.claude"
  printf '%s\n' "wrong target" >"$wrong_target"
  ln -s "$wrong_target" "$symlink_home/.claude/statusline-command.sh"
  expect_installer_failure "$symlink_home"
  [[ "$(readlink "$symlink_home/.claude/statusline-command.sh")" == "$wrong_target" ]] ||
    fail "Installer changed an incorrect symlink"
}

test_status_line() {
  local actual
  local expected
  local injected_json
  local repo="$TEST_ROOT/status-repo"

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
    --arg model $'GPT\u009b31mINJECT' \
    --arg effort $'high\nINJECT' \
    '{
      workspace: {current_dir: $cwd, repo: {name: $repo}},
      model: {display_name: $model},
      effort: {level: $effort}
    }')"
  [[ "$injected_json" == *'\u001b'* ]] ||
    fail "Status-line injection fixture does not contain a JSON ESC character"

  actual="$(printf '%s\n' "$injected_json" | render_status_line)"
  expected=$'\033[1;34mtrusted]52;c;PAYLOAD\033[0m'
  expected+=$'\033[2m │ \033[0m\033[36mGPT31mINJECT\033[0m'
  expected+=$'\033[2m · \033[0m\033[36mhighINJECT\033[0m'
  [[ "$actual" == "$expected" ]] ||
    fail "Status line emitted control characters from workspace text"
}

test_make_targets() {
  local actual
  local target

  actual="$(make --no-print-directory -C "$ROOT")"
  assert_contains <(printf '%s\n' "$actual") "Usage: make <target>"

  for target in install sync test check; do
    actual="$(make --no-print-directory -n -C "$ROOT" "$target")"
    case "$target" in
      install) [[ "$actual" == "./install.sh" ]] ;;
      sync) [[ "$actual" == "./sync.sh" ]] ;;
      test) [[ "$actual" == "./tests/run.sh" ]] ;;
      check) [[ "$actual" == "./scripts/check.sh" ]] ;;
    esac || fail "Unexpected make $target command: $actual"
  done
}

test_skill_metadata
pass "skill structure and metadata"
test_clean_install_and_idempotence
pass "clean install and idempotence"
test_codex_config_reconciliation
pass "Codex config preservation and managed-key reconciliation"
test_codex_command_policy
pass "Codex command policy requires approval for unsandboxed project tests"
test_install_conflicts
pass "file, directory, and incorrect-symlink conflict refusal"
test_status_line
pass "status-line output"
test_make_targets
pass "Make targets"
