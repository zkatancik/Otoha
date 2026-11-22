#!/bin/zsh -l
set -eu
cd -- "${0:A:h}/../.."
exec node scripts/pair-iphone.js
