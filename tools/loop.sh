#!/bin/bash
# Full verification gate: import check, then tests, then a headless smoke run.
# This is the "build + test" half of the implement -> build -> test -> enhance loop.
# Usage: tools/loop.sh [smoke_seconds]
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

secs="${1:-5}"
here="$(dirname "${BASH_SOURCE[0]}")"

echo "=== 1/3 check ==="
"$here/check.sh" || exit 1

echo "=== 2/3 test ==="
"$here/test.sh" || exit 1

echo "=== 3/3 smoke ==="
if [ -z "$(grep -E '^run/main_scene' "$PROJECT_DIR/project.godot" || true)" ]; then
  echo "no main scene set — skipping smoke run"
else
  "$here/run.sh" "$secs" || exit 1
fi

echo "=== ALL GREEN ==="
