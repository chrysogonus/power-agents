#!/bin/bash

input=$(cat)

sanitize_display() {
  jq -Rrs 'gsub("[\u0000-\u001f\u007f-\u009f]"; "")'
}

fields=()
while IFS= read -r field; do
  fields+=("$field")
done < <(
  jq -r '
    def display_text:
      if type == "string" then
        gsub("[\u0000-\u001f\u007f-\u009f]"; "")
      else
        ""
      end;

    def percentage:
      if . == null then "" else round | tostring end;

    [
      ((.workspace.current_dir // .cwd // "") | display_text),
      ((.workspace.repo.name // "") | display_text),
      ((.model.display_name // "") | display_text),
      ((.effort.level // "") | display_text),
      (if .fast_mode == true then "fast" else "" end),
      (.context_window.used_percentage | percentage),
      (.rate_limits.five_hour.used_percentage | percentage),
      (.rate_limits.seven_day.used_percentage | percentage)
    ][]
  ' <<<"$input"
)

cwd=${fields[0]:-$PWD}
cwd=$(printf '%s' "$cwd" | sanitize_display)
repo=${fields[1]:-}
model=${fields[2]:-}
effort=${fields[3]:-}
fast_mode=${fields[4]:-}
ctx_used=${fields[5]:-}
five_hour=${fields[6]:-}
seven_day=${fields[7]:-}

trimmed_cwd=${cwd%/}
directory_name=${trimmed_cwd##*/}
[ -n "$directory_name" ] || directory_name="/"
location=${repo:-$directory_name}

if [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]; then
  remote_identity=$(printf '%s@%s' "$(whoami)" "$(hostname -s)" | sanitize_display)
  location="$remote_identity $location"
fi

branch=$(git --no-optional-locks -C "$cwd" branch --show-current 2>/dev/null |
  sanitize_display)

BLUE=$'\033[1;34m'
MAGENTA=$'\033[35m'
CYAN=$'\033[36m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
DIM=$'\033[2m'
RESET=$'\033[0m'

join_parts() {
  local separator="$1"
  shift
  local prefix=""
  local part

  for part in "$@"; do
    printf "%s%s" "$prefix" "$part"
    prefix="$separator"
  done
}

format_usage() {
  local label="$1"
  local value="$2"
  local color="$CYAN"

  if ((value >= 90)); then
    color="$RED"
  elif ((value >= 70)); then
    color="$YELLOW"
  fi

  printf "%s%s %s%%%s" "$color" "$label" "$value" "$RESET"
}

output="${BLUE}${location}${RESET}"
if [ -n "$branch" ]; then
  output="${output} ${MAGENTA}${branch}${RESET}"
fi

model_parts=()
if [ -n "$model" ]; then
  model_parts+=("${CYAN}${model}${RESET}")
fi
if [ -n "$effort" ]; then
  model_parts+=("${CYAN}${effort}${RESET}")
fi
if [ -n "$fast_mode" ]; then
  model_parts+=("${CYAN}${fast_mode}${RESET}")
fi

if ((${#model_parts[@]})); then
  output="${output}${DIM} │ ${RESET}$(join_parts "${DIM} · ${RESET}" "${model_parts[@]}")"
fi

if [ -n "$ctx_used" ]; then
  output="${output}${DIM} │ ${RESET}$(format_usage "ctx" "$ctx_used")"
fi

rate_limit_parts=()
if [ -n "$five_hour" ]; then
  rate_limit_parts+=("$(format_usage "5h" "$five_hour")")
fi
if [ -n "$seven_day" ]; then
  rate_limit_parts+=("$(format_usage "7d" "$seven_day")")
fi

if ((${#rate_limit_parts[@]})); then
  output="${output}${DIM} │ ${RESET}$(join_parts "${DIM} · ${RESET}" "${rate_limit_parts[@]}")"
fi

printf "%s" "$output"
