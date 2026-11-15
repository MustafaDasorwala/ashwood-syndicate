# Setting up The Ashwood Syndicate

Written to be executed by an AI agent on a machine that has none of this
installed. Every step has a command and a check. Run the checks; do not assume a
step worked because the command exited zero.

**Read this first — it changes how you handle failure.** The game is in two
halves. The simulation and the whole seven-day playthrough need only Godot.
The local LLM only changes *how dialogue is phrased*; it never decides what
happens, and with no model installed the game falls back to templates and
keyword matching and remains fully playable.

So:

| If this fails | Then |
|---|---|
| Godot (steps 1–3) | Stop. There is no game. Fix it before going on. |
| Ollama (steps 4–5) | Report it and continue. The install is a success. |

Do not uninstall or "repair" a working install because the LLM half failed.

---

## 0. Preflight

Collect these before installing anything, and report them:

```bash
uname -sm                                     # macOS/Linux: OS and arch
sysctl -n hw.memsize                          # macOS: RAM in bytes
df -h .                                       # free disk
```

```powershell
# Windows (PowerShell)
$env:PROCESSOR_ARCHITECTURE
(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
Get-PSDrive C | Select-Object Free
```

Requirements:

| Component | Disk | Notes |
|---|---|---|
| Godot 4.6 | ~150 MB | required |
| This repo | ~20 MB | required |
| `qwen3:4b` | ~2.5 GB | reads what the player typed |
| `qwen3:14b` | ~9.3 GB | speaks as the characters |

**Decide the model tier now from RAM**, and remember the decision — step 4
depends on it:

- **16 GB or more** → both models, no changes needed.
- **8–16 GB** → pull `qwen3:4b` only, and follow step 4b to point the dialogue
  model at it. `qwen3:14b` needs roughly 10 GB resident and will swap badly.
- **Under 8 GB, or no GPU/Apple Silicon** → skip Ollama entirely. Do steps 1–3
  and stop. The game plays on templates.

---

## 1. Install Godot 4.6

The project is **pure GDScript** — there is one `.cs` file and it belongs to the
vendored test framework's optional .NET bridge, and there is no `.csproj`. Either
the standard or the .NET build works. Development and all 275 tests are run
against **4.6.3 .NET on macOS arm64**; the standard build is expected to work but
has not been verified here.

**macOS**

```bash
brew install --cask godot
```

**Windows**

```powershell
winget install --id GodotEngine.GodotEngine -e
```

If the package manager does not have it, or installs a version other than 4.6.x,
download it instead from <https://godotengine.org/download/archive/> and unpack
it anywhere.

### Check

Point `GODOT_BIN` at the binary and confirm the version:

```bash
# macOS — adjust if you installed elsewhere
export GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
"$GODOT_BIN" --version
```

```bash
# Windows, from Git Bash
export GODOT_BIN="/c/Program Files/Godot/Godot_console.exe"
"$GODOT_BIN" --version
```

Expected: a string beginning `4.6.` — for example `4.6.3.stable.mono.official`.

`GODOT_BIN` is read by every script in `tools/`. On macOS it defaults to
`/Applications/Godot_mono.app/Contents/MacOS/Godot`, so only set it if you
installed somewhere else. On Windows you must always set it.

Make it permanent so later sessions do not have to rediscover it:

```bash
echo 'export GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"' >> ~/.zshrc
```

---

## 2. Get the repository

```bash
git clone https://github.com/MustafaDasorwala/ashwood-syndicate.git
cd ashwood-syndicate
```

The repository is private. If the clone fails on authentication, the operator
must authenticate first — `gh auth login`, or an SSH key. Do not work around it.

### Check

```bash
ls tools/ ashwood-syndicate/project.godot
```

Expected: the `tools/` scripts and the project file both exist. Note the nesting:
the repository root contains a folder also called `ashwood-syndicate`, which is
the Godot project. `tools/` scripts are run **from the repository root**.

Nothing needs installing for the tests — gdUnit4 6.2.0 is vendored in
`ashwood-syndicate/addons/`.

---

## 3. Verify the game builds, tests and runs

This is the acceptance gate for the required half.

**Windows: use Git Bash**, which ships with Git for Windows. The `tools/`
scripts are bash. PowerShell and `cmd` will not run them.

```bash
tools/loop.sh
```

This imports the project, runs the full suite, then runs the game headless for
five seconds and fails on any runtime script error. It takes about 30 seconds.

### Check

Expected final line:

```
=== ALL GREEN ===
```

and, above it, `275 test cases | 0 errors | 0 failures`.

If the suite reports a different *number* of tests but zero failures, that is
fine — it means the repository has moved on since this guide was written.

Now run it for real:

```bash
"$GODOT_BIN" --path ashwood-syndicate
```

A window opens on the title screen. Press **Begin**, read the briefing, dismiss
it. You should see a town with ten walking villagers.

**At this point the game is installed and playable.** Everything below improves
the dialogue.

---

## 4. Install Ollama and the models

**macOS**

```bash
brew install ollama
ollama serve &            # or: brew services start ollama
```

**Windows**

```powershell
winget install --id Ollama.Ollama -e
```

The Windows installer runs Ollama as a background service; no `serve` needed.
If the package manager fails, download from <https://ollama.com/download>.

You only need `ollama serve` for the checks in this step. **The game starts the
daemon itself** if nothing is listening when it launches — see step 4c.

### Check the daemon

```bash
curl -s http://localhost:11434/api/tags
```

Expected: JSON, probably `{"models":[]}` on a fresh install. A connection error
means the daemon is not running — start it with `ollama serve`.

Note what this check cannot tell you. `{"models":[]}` is the correct, healthy
answer from a daemon with nothing pulled *and* from a daemon reading the wrong
model directory. Step 4c is about the second one.

### 4a. Pull the models (16 GB RAM or more)

```bash
ollama pull qwen3:4b
ollama pull qwen3:14b
```

This downloads about 12 GB. It will take a while.

### 4b. Small-memory alternative (8–16 GB)

Pull only the small model and point both roles at it:

```bash
ollama pull qwen3:4b
```

Then edit `ashwood-syndicate/scripts/main.gd` lines 379–380:

```gdscript
const DIALOGUE_MODEL := "qwen3:4b"    # was qwen3:14b
const INTENT_MODEL := "qwen3:4b"
```

Dialogue will be noticeably less characterful. Intent reading is unaffected —
that job was measured at 8/8 on the 4B model.

### 4c. Where the models live, and who started the daemon

The game does not require you to start Ollama by hand. On launch it probes
`/api/tags`, and if nothing answers it spawns `ollama serve` itself. It also
chooses the model directory rather than accepting the default, because the
default is wrong more often than you would expect.

`OLLAMA_MODELS` defaults to `$HOME/.ollama/models`. So a machine where the
models were pulled under a **different user account** — a second macOS login, a
shared workstation, `sudo`-ing a pull — gives a daemon with a valid, empty store
sitting beside a perfectly good 11 GB one. Nothing reports an error. `/api/tags`
returns `{"models":[]}` and the game plays on templates.

The launcher looks for a store that actually holds both models by checking the
manifest files, in this order:

1. `$OLLAMA_MODELS`, if you have set it
2. `$HOME/.ollama/models`
3. every `/Users/*/.ollama/models` on the machine

The first one holding **every** model in `main.gd` wins. So on a multi-account
machine it finds the real store without being told. If you would rather be
explicit, set it yourself and both the game and the CLI will agree:

```bash
echo 'export OLLAMA_MODELS="$HOME/.ollama/models"' >> ~/.zshrc
```

To stop the game launching anything — if you manage the daemon yourself, or you
are running on a shared box:

```bash
export ASHWOOD_NO_OLLAMA_LAUNCH=1
```

**The store is only chosen when the game starts the daemon.** If one is already
answering on 11434, the game uses it as it finds it — a daemon someone else
started against an empty store is not something the game can or should fix, and
it will not kill a server it did not start. That case is the one warning
`tools/verify_setup.sh` will name for you:

```
WARN  model qwen3:14b not served by this daemon, but present in /Users/other/.ollama/models
```

Fix it by restarting the daemon with `OLLAMA_MODELS` set, or by stopping it and
letting the game start its own.

Two things it deliberately will not do:

- **It never downloads.** A model that is nowhere on the machine is reported to
  stdout and the game carries on with templates. Pulling 12 GB is not a decision
  a game should make while you wait at the title screen. Step 4a is still yours
  to run.
- **It never stops the daemon.** Ollama is shared with everything else on the
  machine, so a server the game started is left running when the game quits.

It also skips entirely when Godot is headless, so `tools/loop.sh` and
`tools/run.sh` neither depend on a server nor leave one behind.

### Check

```bash
ollama list
```

Expected: the models you pulled, with their sizes.

The model names in `main.gd` must match `ollama list` **exactly**, tag included.
A missing model is not an error the game reports — `OllamaBackend` treats every
failure as a reason to fall back to a template, so a typo shows up as bland
dialogue rather than as a crash. This is the single most likely thing to go
quietly wrong in this whole setup.

`ollama list` reports whatever store *your shell* resolves, which on a
multi-account machine is not necessarily the one the game will choose. An empty
`ollama list` beside a working game is not a contradiction — read step 4c.

---

## 5. Verify the whole install

```bash
tools/verify_setup.sh
```

It checks Godot, the project, the autoloads, the art, a clean import, the Ollama
daemon, both models, and a live generation round-trip. Add `--full` to run the
test suite as well.

### Check

Expected:

```
RESULT: everything ready
```

`RESULT: playable, with N warning(s)` is also a success — read the warnings; they
will be about the LLM. Only `RESULT: N failure(s)` means the install is broken.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `error: godot binary not found` | `GODOT_BIN` unset or wrong | `export GODOT_BIN=/path/to/godot`; confirm with `"$GODOT_BIN" --version` |
| `tools/loop.sh: command not found` or syntax errors on Windows | run from PowerShell or `cmd` | use Git Bash |
| Wall of `Identifier "GameClock" not declared` | the `[autoload]` section of `project.godot` was lost | an open Godot editor rewrites that file. Close the editor, `git checkout ashwood-syndicate/project.godot` |
| Editor runs old behaviour after a config change | the editor does not re-read project settings from disk | **Project → Reload Current Project**. `tools/*` spawn their own process and never see this |
| Dialogue is flat and generic | Ollama unreachable, or a model name does not match | `tools/verify_setup.sh`; compare `ollama list` against `DIALOGUE_MODEL`/`INTENT_MODEL` in `scripts/main.gd` |
| Dialogue is flat and generic, but `ollama list` shows both models | the daemon is reading a different store than the one you pulled into — commonly a second user account | the game resolves this itself on launch (step 4c). For the CLI, `export OLLAMA_MODELS=/path/to/the/real/models` |
| `{"models":[]}` from a daemon you know has models | same as above — a valid, empty store | `ls ~/.ollama/models/manifests/registry.ollama.ai/library` to see what that store really holds |
| Console says `Ollama: not running (no model store holds …)` | no directory on the machine has both models | pull them (step 4a), or point `main.gd` at what you do have (step 4b) |
| The game started a daemon you did not want | it spawns one when nothing answers on 11434 | `export ASHWOOD_NO_OLLAMA_LAUNCH=1` |
| Long pause before the first line | cold model load, roughly 8 seconds | expected once per session; `warm_up()` hides it if you do not talk immediately |
| Every reply takes many seconds | `qwen3:14b` is swapping | switch to `qwen3:4b` as in step 4b |
| `tools/shot.sh` fails | no display | it needs a real desktop; the headless renderer has no viewport to capture |

## What not to do

- **Do not run `npx spritecook-mcp setup`.** It writes MCP configuration into
  Cursor, VS Code and Claude Desktop and is hard to undo. It is not needed to
  play or develop.
- **Do not leave the Godot editor open while editing `project.godot`.** It holds
  the file in memory and rewrites it; it has destroyed the `[autoload]` section
  before.
- **Do not add a hosted LLM API.** The project's standing rule is local models
  only. `GossipEngine` resolves all background NPC interaction arithmetically
  and deliberately involves no model at all.

## Reference

- Architecture, invariants and the verification loop: `CLAUDE.md`
- Original design documents (drifted from the code — intent, not spec): `docs/`
- Everything probabilistic goes through `SimRng`, seeded from `Main.world_seed`,
  so a seed reproduces a town exactly. Useful for reporting a bug.
