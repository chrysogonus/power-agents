#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRUSTED_SIGNERS="$HOME/.config/power-agents/trusted-signing-keys"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

if ((BASH_VERSINFO[0] < 4)); then
  fail "Bash 4 or newer is required; see README.md#installation."
fi

for command in git realpath; do
  if ! command -v "$command" >/dev/null 2>&1; then
    fail "Required command not found: $command"
  fi
done

verify_trusted_commit() {
  local commit="$1"
  local fingerprint
  local signature_status

  if ! git -C "$ROOT" -c gpg.format=openpgp \
    verify-commit "$commit" >/dev/null 2>&1; then
    fail "Signature verification failed for incoming commit $commit."
  fi

  read -r signature_status fingerprint < <(
    git -C "$ROOT" -c gpg.format=openpgp \
      show -s --format='%G? %GP' "$commit" 2>/dev/null
  )

  if [[ "$signature_status" != "G" && "$signature_status" != "U" ]]; then
    fail "Incoming commit $commit does not have a valid OpenPGP signature."
  fi

  if ! awk -v fingerprint="$fingerprint" '
    /^[[:space:]]*($|#)/ {
      next
    }

    toupper($1) == toupper(fingerprint) {
      found = 1
    }

    END {
      exit !found
    }
  ' "$TRUSTED_SIGNERS"; then
    fail "Incoming commit $commit is not signed by a trusted key."
  fi
}

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

if [[ ! -f "$TRUSTED_SIGNERS" || ! -s "$TRUSTED_SIGNERS" ]]; then
  fail "Missing trusted signer allowlist: $TRUSTED_SIGNERS"
fi

root_path=$(realpath -e -- "$ROOT") ||
  fail "GNU realpath is required; see README.md#installation."
trusted_signers_path=$(realpath -e -- "$TRUSTED_SIGNERS") ||
  fail "Cannot resolve trusted signer allowlist: $TRUSTED_SIGNERS"
case "$trusted_signers_path" in
  "$root_path" | "$root_path"/*)
    fail "Trusted signer allowlist must be stored outside the repository."
    ;;
esac
TRUSTED_SIGNERS="$trusted_signers_path"

mapfile -t incoming_commits < <(
  git -C "$ROOT" rev-list --reverse "HEAD..$candidate"
)

echo "Verifying ${#incoming_commits[@]} incoming commit(s)..."
for commit in "${incoming_commits[@]}"; do
  verify_trusted_commit "$commit"
done

git -C "$ROOT" merge --ff-only "$candidate"
"$ROOT/install.sh"
