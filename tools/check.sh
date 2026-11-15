#!/bin/bash
# Parse/compile check for the whole project. Fails on any script or scene error.
# Usage: tools/check.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

cd "$PROJECT_DIR"

out="$("$GODOT_BIN" --headless --path . --import 2>&1)"
status=$?

# Godot exits 0 even when scripts fail to parse, so scan the output.
errors="$(printf '%s\n' "$out" | grep -E 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load|Cannot open' || true)"

if [ -n "$errors" ]; then
  echo "FAIL: project has errors"
  printf '%s\n' "$errors"
  exit 1
fi

if [ $status -ne 0 ]; then
  echo "FAIL: godot exited $status"
  printf '%s\n' "$out" | tail -30
  exit 1
fi

echo "OK: project imports clean"
