#!/bin/bash
# Checks that this machine can build, test and play Ashwood Syndicate.
#
# Written to be run by an agent following SETUP.md: every check prints one
# PASS/WARN/FAIL line, and the exit code is 0 only when nothing FAILed.
#
# The distinction between WARN and FAIL is the whole point. Godot missing is a
# FAIL — there is no game without it. Ollama missing is a WARN, because the
# dialogue layer falls back to templates and keyword matching and the game
# remains fully playable. An agent must not treat a missing model as a broken
# install and start uninstalling things.
#
# Usage:
#   tools/verify_setup.sh          # fast checks, no test suite
#   tools/verify_setup.sh --full   # also runs the 275-test suite

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/ashwood-syndicate"

OLLAMA_HOST_URL="${OLLAMA_HOST_URL:-http://localhost:11434}"

# Must match Main.DIALOGUE_MODEL and Main.INTENT_MODEL in scripts/main.gd.
DIALOGUE_MODEL="qwen3:14b"
INTENT_MODEL="qwen3:4b"

failures=0
warnings=0

# Model stores worth searching, mirroring OllamaLauncher.store_candidates().
# A daemon reads exactly one of these, and it is not always the one holding the
# models — see SETUP.md step 4c.
model_stores() {
  [ -n "${OLLAMA_MODELS:-}" ] && printf '%s\n' "$OLLAMA_MODELS"
  printf '%s\n' "$HOME/.ollama/models"
  for root in /Users /home; do
    [ -d "$root" ] || continue
    for home in "$root"/*; do
      [ -d "$home" ] && printf '%s\n' "$home/.ollama/models"
    done
  done
}

# Where Ollama files a manifest: qwen3:14b -> .../library/qwen3/14b
manifest_path() { printf 'manifests/registry.ollama.ai/library/%s/%s\n' "${1%%:*}" "${1##*:}"; }

# Prints the first store on disk holding $1, if any.
store_holding() {
  local store
  while read -r store; do
    if [ -n "$store" ] && [ -f "$store/$(manifest_path "$1")" ]; then
      printf '%s\n' "$store"
      return 0
    fi
  done < <(model_stores)
  return 1
}

pass() { printf '  PASS  %s\n' "$1"; }
warn() { printf '  WARN  %s\n' "$1"; warnings=$((warnings + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }
note() { printf '        %s\n' "$1"; }

echo "Ashwood Syndicate — setup check"
echo

# --- Godot ------------------------------------------------------------------

echo "Godot"

# Candidate locations, in the order an installer is likely to have used. An
# explicit GODOT_BIN always wins.
candidates=(
  "${GODOT_BIN:-}"
  "/Applications/Godot_mono.app/Contents/MacOS/Godot"
  "/Applications/Godot.app/Contents/MacOS/Godot"
  "$HOME/Applications/Godot_mono.app/Contents/MacOS/Godot"
  "$HOME/Applications/Godot.app/Contents/MacOS/Godot"
  "/c/Program Files/Godot/Godot.exe"
  "/c/Program Files/Godot/Godot_console.exe"
)
resolved=""
for candidate in "${candidates[@]}"; do
  [ -n "$candidate" ] && [ -x "$candidate" ] && resolved="$candidate" && break
done
# Fall back to whatever is on PATH.
if [ -z "$resolved" ]; then
  for name in godot godot4 Godot godot-mono; do
    if command -v "$name" >/dev/null 2>&1; then
      resolved="$(command -v "$name")"
      break
    fi
  done
fi

godot_ok=0
if [ -z "$resolved" ]; then
  fail "no Godot binary found"
  note "install Godot 4.6, then: export GODOT_BIN=/path/to/godot"
else
  version="$("$resolved" --version 2>/dev/null | tail -1)"
  case "$version" in
    4.6.*)
      pass "Godot $version"
      note "$resolved"
      godot_ok=1
      ;;
    "")
      fail "Godot at $resolved did not report a version"
      ;;
    *)
      # A different 4.x will usually run this project, but it is not what the
      # 275 tests were run against, so say so rather than quietly proceeding.
      warn "Godot $version — this project is developed against 4.6.x"
      note "$resolved"
      godot_ok=1
      ;;
  esac
  export GODOT_BIN="$resolved"
fi

echo

# --- Project ----------------------------------------------------------------

echo "Project"

if [ ! -f "$PROJECT_DIR/project.godot" ]; then
  fail "project.godot not found under $PROJECT_DIR"
else
  pass "project found"

  # The autoload section has been destroyed before by an editor holding the
  # file open, and the failure mode is a wall of "Identifier not declared".
  if grep -q '^EventBus=' "$PROJECT_DIR/project.godot" \
     && grep -q '^GameClock=' "$PROJECT_DIR/project.godot"; then
    pass "autoloads intact (EventBus, GameClock)"
  else
    fail "the [autoload] section is missing or incomplete"
    note "an open Godot editor rewrites project.godot; see CLAUDE.md"
  fi

  if [ -f "$PROJECT_DIR/addons/gdUnit4/plugin.cfg" ]; then
    pass "gdUnit4 present (vendored, no install needed)"
  else
    warn "gdUnit4 addon missing — tests cannot run"
  fi

  if [ -f "$PROJECT_DIR/assets/characters/villager_base.png" ]; then
    pass "character art present"
  else
    warn "assets/characters/villager_base.png missing — NPCs will not draw"
  fi
fi

echo

# --- Import and smoke -------------------------------------------------------

if [ "$godot_ok" = "1" ] && [ -f "$PROJECT_DIR/project.godot" ]; then
  echo "Build"
  import_log="$(cd "$PROJECT_DIR" && "$GODOT_BIN" --headless --import --quit 2>&1)"
  if printf '%s\n' "$import_log" | grep -qE 'SCRIPT ERROR|Parse Error|Compile Error'; then
    fail "project does not import cleanly"
    printf '%s\n' "$import_log" | grep -E 'SCRIPT ERROR|Parse Error|Compile Error' | head -5
  else
    pass "project imports with no script errors"
  fi
  echo
fi

# --- Ollama -----------------------------------------------------------------
#
# Everything below is an enhancement. None of it failing stops the game.

echo "Ollama (optional — the game plays without it)"

if ! command -v ollama >/dev/null 2>&1; then
  warn "ollama not installed"
  note "dialogue will use built-in templates and keyword matching"
elif ! curl -s -m 3 "$OLLAMA_HOST_URL/api/tags" >/dev/null 2>&1; then
  warn "ollama installed but not responding at $OLLAMA_HOST_URL"
  note "the game starts it on launch; start it here with: ollama serve"
else
  pass "ollama responding at $OLLAMA_HOST_URL"

  installed="$(ollama list 2>/dev/null)"
  for model in "$DIALOGUE_MODEL" "$INTENT_MODEL"; do
    if printf '%s\n' "$installed" | grep -q "^${model%%:*}:${model##*:}[[:space:]]"; then
      pass "model $model"
    # The running daemon does not serve it, but it is on the disk somewhere.
    # Telling the operator to pull 9GB they already have is the wrong advice,
    # and this is the case that looks exactly like "no model installed":
    # /api/tags answers 200 with an empty list and nothing reports an error.
    elif elsewhere="$(store_holding "$model")"; then
      warn "model $model not served by this daemon, but present in $elsewhere"
      note "the daemon is reading a different store — see SETUP.md step 4c"
      note "the game finds this store by itself; for the CLI: export OLLAMA_MODELS=$elsewhere"
    else
      warn "model $model not pulled"
      note "pull it with: ollama pull $model"
    fi
  done

  # A round trip proves the thing the game actually depends on, which is not
  # "the daemon is up" but "this model answers".
  if printf '%s\n' "$installed" | grep -q "^${INTENT_MODEL%%:*}:${INTENT_MODEL##*:}[[:space:]]"; then
    # Checks that the model loads and generates, not that it obeys. Asking for
    # one specific word and grepping for it fails on a reasoning-tuned model,
    # which opens with a few tokens of preamble even with think:false — the
    # check was reporting a healthy install as broken.
    reply="$(curl -s -m 120 "$OLLAMA_HOST_URL/api/chat" \
      -H 'Content-Type: application/json' \
      -d "{\"model\":\"$INTENT_MODEL\",\"stream\":false,\"think\":false,
           \"options\":{\"num_predict\":24},
           \"messages\":[{\"role\":\"user\",\"content\":\"Say hello.\"}]}" \
      2>/dev/null)"
    if printf '%s' "$reply" | grep -q '"content":"[^"]' ; then
      pass "$INTENT_MODEL loaded and generated a reply"
    else
      warn "$INTENT_MODEL did not generate anything"
      note "first load pulls the weights into RAM and can take a minute"
      note "re-run this script; if it persists, try: ollama run $INTENT_MODEL"
    fi
  fi
fi

echo

# --- Optional full test run -------------------------------------------------

if [ "${1:-}" = "--full" ]; then
  echo "Test suite"
  if [ "$godot_ok" = "1" ]; then
    if "$REPO_ROOT/tools/test.sh" >/tmp/ashwood_tests.log 2>&1; then
      summary="$(grep -oE '[0-9]+ test cases \| [0-9]+ errors \| [0-9]+ failures' /tmp/ashwood_tests.log | tail -1)"
      pass "${summary:-all tests passed}"
    else
      fail "test suite failed — see /tmp/ashwood_tests.log"
    fi
  else
    fail "cannot run tests without Godot"
  fi
  echo
fi

# --- Verdict ----------------------------------------------------------------

if [ "$failures" -gt 0 ]; then
  echo "RESULT: $failures failure(s), $warnings warning(s) — not playable yet"
  exit 1
fi

if [ "$warnings" -gt 0 ]; then
  echo "RESULT: playable, with $warnings warning(s)"
  echo "The game runs. Warnings above are about the local LLM, which only"
  echo "changes how dialogue is phrased, never what happens in the simulation."
  exit 0
fi

echo "RESULT: everything ready"
exit 0
