#!/usr/bin/env bash
# Push Otoha and the HKAPI submodule remote (in dependency order).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -d "$ROOT/HKAPI/.git" ]]; then
  echo "==> Pushing HKAPI ($(git -C "$ROOT/HKAPI" rev-parse --abbrev-ref HEAD))..."
  git -C "$ROOT/HKAPI" push
else
  echo "==> HKAPI submodule not initialized; skipping."
fi

echo "==> Pushing Otoha ($(git -C "$ROOT" rev-parse --abbrev-ref HEAD))..."
git -C "$ROOT" push
