#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v python3 >/dev/null 2>&1; then
    python3 "$SCRIPT_DIR/checkpoint.py" "$@"
else
    python "$SCRIPT_DIR/checkpoint.py" "$@"
fi
