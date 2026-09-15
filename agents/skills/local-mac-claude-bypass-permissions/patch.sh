#!/usr/bin/env bash
# Max-bypass patch for the local Claude Code CLI on macOS or Linux.
#
# Usage: bash patch.sh [path/to/claude]
# Default target is the binary that ~/.local/bin/claude resolves to.
set -euo pipefail

DEFAULT_BIN=$(python3 - <<'PY'
import os
print(os.path.realpath(os.path.expanduser("~/.local/bin/claude")))
PY
)
BIN="${1:-$DEFAULT_BIN}"
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -f "$BIN" ]]; then
  echo "ERROR: Claude binary not found: $BIN" >&2
  exit 1
fi

if [[ ! -f "$SKILL_DIR/patch.py" ]]; then
  echo "ERROR: patch.py not found in $SKILL_DIR" >&2
  exit 1
fi

exec python3 "$SKILL_DIR/patch.py" "$BIN"
