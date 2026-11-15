#!/bin/bash
# Shared environment for Ashwood Syndicate tooling.
set -euo pipefail

export GODOT_BIN="${GODOT_BIN:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT
export PROJECT_DIR="$REPO_ROOT/ashwood-syndicate"

if [ ! -x "$GODOT_BIN" ]; then
  echo "error: godot binary not found at $GODOT_BIN" >&2
  echo "set GODOT_BIN to override" >&2
  exit 1
fi
