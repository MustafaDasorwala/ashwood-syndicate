#!/bin/bash
# Run gdUnit4 tests headless. Exit code is non-zero when any test fails.
# Usage:
#   tools/test.sh                       # all tests under res://test
#   tools/test.sh res://test/foo_test.gd  # a single suite or directory
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

cd "$PROJECT_DIR"

target="${1:-res://test}"

if [ ! -d "test" ]; then
  echo "no test/ directory yet — nothing to run"
  exit 0
fi

exec ./addons/gdUnit4/runtest.sh --godot_binary "$GODOT_BIN" -a "$target" --continue
