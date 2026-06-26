#!/usr/bin/env bash
# Stage changes in HKAPI (submodule) and Otoha from the repo root.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -d "$ROOT/HKAPI/.git" ]]; then
  echo "==> Staging HKAPI..."
  git -C "$ROOT/HKAPI" add -A
fi

echo "==> Staging Otoha..."
git -C "$ROOT" add -A
