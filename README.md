# The Ashwood Syndicate

A seven-day emergent social simulation in Godot 4.6.

The town leader is dead. In seven days the ten people of Ashwood choose a
successor, and you are standing for it. You need six votes. Two of the ten are
standing against you and campaign every hour you do.

Everyone has a psychological profile, a place in a web of kinship, debts,
rivalries and secret affairs, and a memory of what they have seen and been told.
They walk to work, gossip, and form opinions of you whether or not you are in
the room. You win by working out what moves each of them — and, because charm
has a hard ceiling, by finding out what they would rather nobody knew.

Conversation is free text against a local LLM. You type; they answer in
character. The model interprets what you were attempting and phrases the result,
but **the simulation decides every consequence** — so nobody can be talked into
a vote they would not give.

## Quick start

```bash
export GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"   # your path
tools/loop.sh                 # import, 264 tests, headless smoke run
"$GODOT_BIN" --path ashwood-syndicate
```

Full instructions, including the local LLM, are in **[SETUP.md](SETUP.md)** —
written so an agent can execute it. `tools/verify_setup.sh` checks a machine.

Godot is the only requirement. Without Ollama the dialogue falls back to
templates and the game is still fully playable.

## How to play

Walk with WASD or click open ground. Click a person to walk over and talk to
them; type whatever you like. Talking costs nothing — ask about their
neighbours, their work, whoever they seem to resent. Actually trying to move
someone, with a favour or a bribe or a threat, costs an hour of the seven days.

Three things decide games: anyone in the room sees what you do, the vote is
relative so a rival gaining counts against you, and a secret belongs to
everyone it would ruin.

## Layout

```
ashwood-syndicate/   the Godot project
  scripts/sim/       the simulation — no dependency on the scene tree
  scripts/dialogue/  intent reading, prompting, local model backends
  test/              264 gdUnit4 tests, all headless
tools/               verification scripts; tools/loop.sh is the gate
docs/                original design documents, since drifted
```

`CLAUDE.md` is the working document: architecture, the invariants that are not
obvious, and the traps. Read it before changing anything.

## Local models only

No hosted APIs, by design. Background NPC-to-NPC interaction uses no model at
all — 45 pairs across 168 hours would bury any local one, so `GossipEngine`
resolves it arithmetically. A model is only ever asked about a conversation the
player is present for.

## Licence

The game code is released under the MIT licence (see `LICENSE`). Bundled third-party
content keeps its own terms: gdUnit4 (`ashwood-syndicate/addons/gdUnit4/LICENSE`) and the
Kenney Tiny Town pack (CC0, `assets_to_consider/kenney_tiny-town/License.txt`).
