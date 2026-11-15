#!/bin/bash
# Run the game headless for a bounded time and capture all output.
# Useful for smoke-testing simulation ticks without a window.
# Usage: tools/run.sh [seconds] [scene]
#   tools/run.sh 10
#   tools/run.sh 10 res://scenes/town.tscn
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

cd "$PROJECT_DIR"

secs="${1:-10}"
scene="${2:-}"

args=(--headless --path . --quit-after "$((secs * 60))")
[ -n "$scene" ] && args+=("$scene")

echo "--- running ${secs}s ${scene:-(main scene)} ---"
out="$("$GODOT_BIN" "${args[@]}" 2>&1)"
printf '%s\n' "$out"

errors="$(printf '%s\n' "$out" | grep -E 'SCRIPT ERROR|Parse Error|ERROR:' || true)"
if [ -n "$errors" ]; then
  echo "--- FAIL: runtime errors ---"
  printf '%s\n' "$errors"
  exit 1
fi
echo "--- OK: clean run ---"
