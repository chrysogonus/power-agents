#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREVIOUS_HEAD=""
SYNC_UPDATE_ACTIVE=0

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

if ((BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] < 404)); then
  fail "Bash 4.4 or newer is required; see README.md#installation."
fi

if ! command -v git >/dev/null 2>&1; then
  fail "Required command not found: git"
fi

restore_previous_installation() {
  local status="$1"
  local rollback_failed=0

  trap - HUP INT TERM
  SYNC_UPDATE_ACTIVE=0
  echo "ERROR: Sync failed after update activation; restoring the previous version." >&2

  if ! git -C "$ROOT" reset --hard "$PREVIOUS_HEAD"; then
    echo "ERROR: Could not restore the previous checkout: $PREVIOUS_HEAD" >&2
    rollback_failed=1
  elif ! "$ROOT/install.sh"; then
    echo "ERROR: Could not restore the previous installed configuration." >&2
    rollback_failed=1
  fi

  if ((rollback_failed)); then
    echo "ERROR: Sync rollback was incomplete; inspect the checkout and installed configuration." >&2
  else
    echo "Previous checkout and installed configuration restored." >&2
  fi
  exit "$status"
}

handle_signal() {
  local status="$1"

  trap - HUP INT TERM
  if ((SYNC_UPDATE_ACTIVE)); then
    restore_previous_installation "$status"
  fi
  exit "$status"
}

trap 'handle_signal 129' HUP
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM

tracked_status=$(git -C "$ROOT" status --porcelain --untracked-files=no) ||
  fail "Could not inspect the working tree."
if [[ -n "$tracked_status" ]]; then
  fail "Tracked or staged changes are present; commit or discard them before syncing."
fi

PREVIOUS_HEAD=$(git -C "$ROOT" rev-parse --verify 'HEAD^{commit}') ||
  fail "Could not resolve the current commit."

git -C "$ROOT" fetch

upstream=$(git -C "$ROOT" rev-parse \
  --abbrev-ref --symbolic-full-name '@{upstream}') ||
  fail "The current branch has no configured upstream."
candidate=$(git -C "$ROOT" rev-parse --verify "$upstream^{commit}")

if git -C "$ROOT" merge-base --is-ancestor "$candidate" HEAD; then
  echo "Already up to date."
  "$ROOT/install.sh"
  exit
fi

if ! git -C "$ROOT" merge-base --is-ancestor HEAD "$candidate"; then
  fail "Local and upstream histories have diverged; refusing to update."
fi

SYNC_UPDATE_ACTIVE=1
if git -C "$ROOT" merge --ff-only "$candidate"; then
  :
else
  status=$?
  restore_previous_installation "$status"
fi

if "$ROOT/install.sh"; then
  SYNC_UPDATE_ACTIVE=0
else
  status=$?
  restore_previous_installation "$status"
fi
