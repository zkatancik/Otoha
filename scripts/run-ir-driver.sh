#!/bin/sh
# Install optional libraries only on explicit setup, in driver-specific environments.
set -eu
family="$1"
shift
case "$family" in
    broadlink) module=broadlink; package=broadlink==0.19.0 ;;
    bonjour) module=zeroconf; package=zeroconf==0.148.0 ;;
    *) exit 2 ;;
esac
script="$(dirname "$0")/$family-ir.py"
if [ "$family" = bonjour ] && [ "$1" != discover ]; then
    exec python3 -B "$script" "$@"
fi
runtime="$HOME/Library/Application Support/Otoha/$family-venv"
if [ "$(uname -s)" != Darwin ]; then
    runtime="${XDG_DATA_HOME:-$HOME/.local/share}/otoha/$family-venv"
fi
case "$1" in
    configure|discover)
        if [ ! -x "$runtime/bin/python" ]; then
            python3 -m venv "$runtime" >&2
        fi
        if ! "$runtime/bin/python" -c "import $module" 2>/dev/null; then
            "$runtime/bin/python" -m pip --disable-pip-version-check install --timeout 8 --retries 1 "$package" >&2
        fi
        ;;
esac
exec "$runtime/bin/python" -B "$script" "$@"
