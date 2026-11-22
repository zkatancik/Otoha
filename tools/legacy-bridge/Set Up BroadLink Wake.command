#!/bin/zsh -l
set -eu
cd -- "${0:A:h}/../.."
exec /bin/sh scripts/run-broadlink.sh configure "$@"
