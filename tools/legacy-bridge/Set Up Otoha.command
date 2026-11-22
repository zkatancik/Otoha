#!/bin/zsh -l
set -eu
cd -- "${0:A:h}/../.."

if ! xcode-select -p >/dev/null 2>&1; then
  print 'Choose Install in the Mac software prompt. When it finishes, double-click Set Up Otoha again.'
  xcode-select --install
  exit 0
fi
if ! command -v node >/dev/null || ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)'; then
  print 'Download the Node.js LTS macOS Installer, open the downloaded package, then double-click Set Up Otoha again.'
  open 'https://nodejs.org/en/download'
  exit 0
fi
exec python3 scripts/install-mac.py --lan --open
