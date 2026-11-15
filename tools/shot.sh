#!/bin/bash
# Run the game windowed, let it play forward, and save a screenshot.
# Requires a real display — the headless renderer has no viewport to capture.
# Usage: tools/shot.sh [frames] [output_png]
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

cd "$PROJECT_DIR"

frames="${1:-240}"
out="${2:-$REPO_ROOT/shots/latest.png}"
shift 2 2>/dev/null || true
mkdir -p "$(dirname "$out")"
rm -f "$out"

# Anything after the output path is forwarded to the game: --title keeps the
# menu up, --skip <hours> jumps the clock before capturing.
log="$("$GODOT_BIN" --path . --resolution ${SHOT_RES:-900x680} --position 0,0 -- --shot "$frames" "$out" "$@" 2>&1)"

printf '%s\n' "$log" | grep -E "capture:" || true

# A screenshot of a stale build is worse than no screenshot: it looks like the
# change worked. Fail loudly when the run logged script errors.
errors="$(printf '%s\n' "$log" | grep -E 'SCRIPT ERROR|Parse Error|Compile Error' || true)"
if [ -n "$errors" ]; then
  echo "FAIL: script errors during capture" >&2
  printf '%s\n' "$errors" | head -20 >&2
  exit 1
fi

if [ ! -f "$out" ]; then
  echo "FAIL: no screenshot produced" >&2
  exit 1
fi

echo "wrote $out"
