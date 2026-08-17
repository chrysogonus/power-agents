#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

git -C "$ROOT" pull --ff-only
"$ROOT/install.sh"
