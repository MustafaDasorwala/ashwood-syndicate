# The Ashwood Syndicate

A 7-day emergent social simulation in Godot 4.6 (mono). Ten autonomous NPCs with
psychological profiles; the player must secure 6 of 10 votes. Design documents
live in `docs/`.

## Layout

```
ashwood-syndicate/        Godot project
  scripts/main.gd         entry point + game flow (title -> play -> results)
  scripts/core/           autoloads: EventBus, GameClock; SimRng
  scripts/data/           Psyche, MemoryToken, MemoryLedger, RelationshipBook,
                          ActionCatalog, RelationGraph, Secret
  scripts/sim/            Agent, TownGrid, Schedule, GossipEngine, TownSim,
                          Roster, PlayerActions, Election, CampaignAi,
                          IncidentEngine, TownGenerator, Archetypes, NamePool,
                          TownBlueprint
  scripts/dialogue/       DialogueBackend, OllamaBackend, PromptBuilder,
                          Conversation, IntentReader
  scripts/entities/       NpcView, PlayerAvatar (drawing + movement only)
  scripts/gfx/            ProcArt, TownRenderer, DayNight — placeholder art;
                          CharacterSprite + tunic_recolor.gdshader — real art
  scripts/audio/          ProcAudio — synthesised cues, no audio files
  scripts/ui/             Hud, DialoguePanel, TitleScreen, BriefingScreen,
                          ResultsScreen
  assets/characters/      villager_base.png — the one villager walk sheet
  test/                   gdUnit4 suites (264 tests)
  shots/                  screenshots written by tools/shot.sh
tools/                    verification scripts, and build_character_sheet.py
docs/                     original design documents
README.md                 what the game is
SETUP.md                  install guide, written for an agent to execute
```

## MCP servers in use

- **godot** — project-scoped in `.mcp.json`. Rarely needed; `tools/` is the
  real workflow and is what catches problems.
- **spritecook** — user-scoped *plugin* (`claude plugin`), for generating art.
  Not in `~/.claude.json`; see the SpriteCook memory for removal.

## The verification loop

Always run the gate before reporting a change works. It is fast (~15s).

```
tools/loop.sh          # check -> test -> headless smoke run
tools/verify_setup.sh  # is this machine set up? --full also runs the suite
tools/check.sh         # parse/import errors only
tools/test.sh [target] # gdUnit4, headless, non-zero exit on failure
tools/run.sh [secs]    # headless run, fails on runtime script errors
tools/shot.sh [frames] [out.png] [--title] [--skip HOURS]
```

`tools/shot.sh` needs a real display; the headless renderer has no viewport to
capture. `SHOT_RES=1280x800 tools/shot.sh …` overrides the capture size, which
matters for UI work: the default 900x680 is smaller than the project's own
window, so a panel that fits in a screenshot may still overflow in the game.
`--talk "line"` opens a conversation, `--briefing` keeps the opening briefing
up. It fails on script errors rather than producing a stale screenshot.
`--title` keeps the menu up; `--skip 170` jumps near the deadline to capture the
results screen without waiting out seven real days.

**Look at the screenshots.** Several real bugs were invisible to 200+ passing
tests and obvious on sight: ten NPCs stacked on one tile, HUD panels rendered
off-screen, the Sheriff accusing himself of paying his own bribe, a blacksmith
who had mercy-killed a patient.

## Architecture rules

- **Simulation never depends on the scene tree.** `Agent`, `GossipEngine`,
  `TownGrid` and friends are `RefCounted`. `TownSim` is a `Node` only so it can
  sit in the scene; every method is callable without one. This is why a full
  seven-day playthrough runs in a unit test in milliseconds.
- **No global randomness.** Everything probabilistic goes through `SimRng`,
  seeded from `Main.world_seed`. Calling `randf()` directly breaks reproducibility
  and makes emergent behaviour untestable.
- **Time advances through `GameClock.advance()`**, never off frame delta directly.
  `_process` feeds it; tests call it. `skip_hours()` fast-forwards.
- **No LLM calls for background NPC-to-NPC interaction.** `GossipEngine` resolves
  those as arithmetic over Memory Tokens. The LLM only ever phrases outcomes in
  scenes the player is present for.
- **Views read the simulation, never mutate it.** Deleting `scripts/gfx` and
  `scripts/entities` would leave a working headless sim.

## Non-obvious invariants

- `MemoryLedger` deduplicates by `MemoryToken.content_key()`. Without this a
  rumour echoing around ten NPCs re-applies its relationship hit every retelling
  and every score saturates by Day 2.
- `TownSim._seed_social_graph()` turns the roster's `loyal_to` / `rivals` into
  real relationship scores. Skipping it leaves a blank social graph where trust
  is uniform, which silently disables the gossip engine's trust discount and
  makes every playthrough converge on identical numbers.
- Moral offense is *saturated* (`x/(1+x)`), not clamped. A hard clamp flattened
  every multi-foundation violation to the same ceiling, which made murder score
  better than theft once the Dark Triad admiration bonus was added.
- A trauma trigger applies a severity-scaled *floor*, not a multiplier — a
  multiplier means an NPC whose morals happen not to condemn the act barely
  reacts to their own ghost.
- Don't name a GDScript enum `Corner`; it collides with Godot's global enum and
  parameter annotations silently resolve to the built-in.
- Repetition decay must be **geometric** (`pow(decay, n)`), not harmonic
  (`1/(1+kn)`). The harmonic form diverges, so given enough hours every voter
  reached the 100 ceiling for every candidate and the election became a tie
  nobody could lose.
- Witnessing has its own decay (`Agent.witness_approach`), separate from belief
  dedup. Each favour has a different recipient, so every one is a genuinely new
  claim — without a witness-side counter a candidate could stand in a crowded
  tavern doing favours all week and drive the whole room to maximum regard.
- An election tie is an abstention, not a win. Ties previously resolved by
  candidate order, which silently handed the player every saturated vote.
- Incidents are for keeping the town talking, not for ruining people. At a 12%
  hourly desperation chance the Merchant committed ~20 public thefts a week and
  ended every run at zero regard with everyone.
- Rival candidates ignore their work schedules and go where the voters are, and
  they weigh the room before choosing an approach. Both were necessary before
  they could win a single vote.
- A secret is an object with participants, not a string on one person. An affair
  cannot be modelled the old way — it belongs to two people and exposing it
  ruins both.
- A secret is never filed in its participants' own ledgers. Agents gossip from
  their ledger and would cheerfully volunteer their own ruin.
- `RelationGraph.degree_of` counts ties an inhabitant *feels*; a creditor feels
  no debt. Use `involvement_of` to ask how connected someone is — the Merchant
  is owed by two people and reports degree 1.
- Mutual ties (kin, marriage, affair, friendship, estranged, rivalry) are stored
  once and answered both ways. Everything else is directional on purpose: Bram
  loves the Widow, and she need not love him back.
- Dialogue backends must emit through `deliver()`, never `line_ready.emit`
  directly. A backend that answers instantly fires the signal before the
  caller's `await` subscribes and deadlocks the conversation permanently — the
  test double exposed this, a slow HTTP backend never would.
- Write secrets subject-first in the direction they read back out. `the_payroll`
  is `merchant bribed sheriff`, so the Sheriff's prompt says "Yolen the Merchant
  bribed you" rather than accusing him of paying his own bribe.
- Generated secrets must fit the role, not just the stats. Gating the mercy
  killing on high Care alone handed "you ended a dying patient's suffering" to a
  blacksmith; it now requires a `caregiver` archetype.
- Nothing in the simulation may look up a specific inhabitant by id. A generated
  town has no `sheriff`. `TownSim.protector_id` / `broker_id` resolve the roles
  from character (highest Authority, highest Machiavellianism), which lands on
  Ashwood's own Sheriff and Merchant anyway.
- Archetype ambition alone made the same two people run every time. Candidate
  choice blends the role with the *rolled* psyche, so an unusually vain smith
  can stand.
- `Agent.REPEAT_DECAY` is load-bearing and not a free knob. At 0.55 the ceiling
  on one person landed near 72 regard — *below* the 74 a plain friendship opens
  at — so a rival's oldest friend was mathematically unwinnable however well the
  player played. Both balance guards move when this does.
- Every approach carries its own `key` in `PlayerActions.DEFINITIONS`. Deriving
  the shortcut from the label's first letter gave Bribe and Blackmail both `B`.
- The avatar is the only writer of `TownSim.player_zone`. Streets between zones
  resolve to -1, which correctly means you can reach nobody from the road.
- The tunic recolour shader has no mask texture. It finds the tunic by "low
  saturation and bright", which only works because the sheet's skin, hair, belt,
  trousers and boots are all warm and saturated and the outline is near black.
  Regenerating the art in a grey-trousered palette silently recolours the legs.
- Tunic hue steps by the golden ratio over the roster index, not by hashing the
  id. Hashing spreads hues arbitrarily, and arbitrary is not separated —
  Ashwood's blacksmith and trapper hashed to the same colour and were dressed
  identically. A generated cast of any size needs the guarantee, not the luck.
- Everyone with a body shares one y-sorted parent (`Main._actors`) **and one
  z_index**. Y-sorting only orders siblings at the same z_index, so lifting the
  player above the NPCs — which is what the code used to do — puts them
  permanently in front of a town they should sometimes stand behind.
- Reach asks "is this agent close", never "is this agent the closest".
  `PlayerAvatar.can_reach` exists because `nearest_within_reach() == agent` is a
  different question that is false almost always in a crowded room: you stand
  beside your target, a neighbour is a fraction nearer, and the game refuses to
  open a conversation with somebody at arm's length.
- Walking to somebody uses `PlayerAvatar.approach_tile`, which is *their*
  standing spot. It used to be `zone_slot(zone, 0)`, so clicking anyone but the
  roster's first occupant marched the player to a different person entirely and
  then refused to talk. Any test or harness that picked `agents[0]` passed while
  the interaction was broken for the other nine — `tools/shot.sh --talk` now
  deliberately picks the *last* inhabitant.
- `OllamaBackend.warm_up` holds the single-flight lock through an eight second
  cold start. A real request arriving during it is deferred, not answered from
  templates, because otherwise the first conversation of every game opens on a
  canned greeting.
- `delivery` in `Agent.receive_approach` must be applied with the sign of the
  evaluation in mind. An offensive approach evaluates negative, so scaling it
  by a sub-1.0 multiplier makes it offend *less* and turns fumbling into the
  safe way to attempt something. See the dialogue section.
- `IntentReader` may only ever return an approach the player actually holds.
  It is handed `Conversation.available_approaches()` for exactly this reason —
  otherwise typing "I know what you did" lets a model conjure leverage that
  does not exist.
- The model's `fit` rating is asked for as 0-10 and does not always arrive that
  way; qwen3:4b sometimes answers `0.8` meaning eight tenths. Divided by ten
  that read as the most offensive thing the player could have said.
- `TownGrid.ROW_SPACING` is a rendering fact living in the simulation's layout,
  on purpose. A villager is drawn two tiles tall from the feet, so standing
  spots one tile apart bury the back row's head inside the front row. No test of
  the simulation would ever notice; only a screenshot does.

## Operational hazards

**An open Godot editor holds `project.godot` in memory and rewrites it.** This
already destroyed the `[autoload]` section once. Symptoms: a wall of
`Identifier "GameClock" not declared in the current scope` errors, and the
editor referencing files that no longer exist on disk.

The editor also does not re-read project settings when they change on disk, so
an editor opened before an edit will run the *old* configuration indefinitely.
After changing `project.godot`, use **Project → Reload Current Project**, and
afterwards confirm the section survived:

```
grep -A3 '\[autoload\]' ashwood-syndicate/project.godot
```

`tools/*` spawn their own Godot process and never see editor staleness. When the
editor and the scripts disagree, **the disk is the truth**.

## Art pipeline

Characters are real art. Everything else is still procedural placeholder,
deliberately isolated so assets drop in without touching the simulation:

| File | Draws | Replace with |
|------|-------|--------------|
| `gfx/proc_art.gd` | palette, tunic hues, tile↔pixel maths | palette constants |
| `gfx/town_renderer.gd` | ground, buildings, stalls, trees | tilesets |
| `gfx/character_sprite.gd` | villager bodies — **real sprites** | done |
| `entities/npc_view.gd` | mood ring, seeking ring, name label | keep |
| `entities/player_avatar.gd` | the player's ring and label | keep |
| `gfx/day_night.gd` | hourly tint | keep, or swap for real lights |
| `audio/proc_audio.gd` | synthesised blips and chimes | WAV/OGG |

SpriteCook (user-scoped plugin) generates the art. It ships a
`spritecook-use-assets-in-godot` skill worth reading before importing anything.

Remaining assets, in priority order:

1. Ground tileset (dirt, path, grass) for `_draw_ground`.
2. Building fronts for tavern / residences / sheriff's office.
3. Market stall and tree props.

Note `ProcArt.TILE_SIZE` is 16 and the town is 40×30 tiles. A villager is drawn
16×32 — one tile wide, two tall — so anything that seats a crowd has to budget
two tiles of height per person.

### The one villager sheet

`assets/characters/villager_base.png` is 100×200: four rows (down, left, right,
up) of four 25×50 frames, column 0 idle, cycle idle-step-idle-step. The whole
cast and the player wear it; they are told apart by `tunic_recolor.gdshader`.

The generator gave a 4×8 sheet with the facing lost in three frames and both
side rows pointing left. `tools/build_character_sheet.py` is the slicer that
picked the usable frames by measured leg spread and lead bias, mirrored the
right-facing row, recentred each frame and hard-edged the alpha. **Rerun that
script rather than reslicing by hand** if the sheet is ever regenerated; the
choices in it are recorded with the reasons.

## How to play

**You are standing for leader of Ashwood.** The old leader is dead; in seven
days the ten inhabitants choose a successor and you need six of them. Mayor
Thorne and Yolen the Merchant are standing too.

`BriefingScreen` says all of this before day one and holds the clock at zero
until it is dismissed, and the HUD repeats the objective whenever nobody is
selected. Both exist because the premise used to appear once, in small type on
the title screen above a seed field, where it read as flavour and was clicked
past — leaving seven days of "win 6 of 10 votes" without ever learning votes
*for what*. The briefing reads the rivals out of the live simulation, since a
procedural town has neither Thorne nor Yolen in it.

Title screen picks the seed and whether the town is procedural. WASD or click
open ground to walk. **Click a person to go and talk to them** — the avatar
walks over and the conversation opens on arrival. SPACE talks to whoever is
already beside you. Then **type**. The table below is what the approaches do;
you reach them by saying so in your own words, or by clicking a suggestion with
`1`-`9`.

| Key | Approach | Works on |
|-----|----------|----------|
| `B` | Bribe    | The greedy and amoral. Outrages anyone who values fairness. |
| `T` | Threaten | Fast. Their friends will hear about it. |
| `H` | Help     | Slow, safe — but a favour to someone I despise is not a favour to me. |
| `F` | Flatter  | Free. Works on vanity. Trips Elias the Miller's trauma. |
| `P` | Probe    | Needs their trust. Uncovers what they are hiding. |
| `K` | Blackmail| Needs their secret. Buys the vote — until they report you. |
| `E` | Expose   | Repeat a secret about someone else. Damages them, costs you. |

`0` pauses, `1`/`2`/`3` set speed. Conversation is free; each attempt on
somebody costs an in-game hour. The keyboard shortcuts above, used outside a
conversation, are still one approach per hour.

Persuasion has a hard ceiling per person, so **Expose is not optional**. You
cannot out-charm a rival's oldest friend; the way past a bonded ally is to give
them a reason to think less of the man they are backing.

Some things are only found by watching. Lovers have to meet somewhere — if a
routine quietly breaks late at night and two people end up in the same empty
place, that is the clue. No UI announces it.

Three mechanics decide games:

1. **Witnesses.** Anyone in the room sees what you do and forms their own view.
   Bribing the Merchant alone wins his respect; doing it in front of the Sheriff
   costs more than it gains.
2. **The vote is relative.** Mayor Thorne and Yolen the Merchant are also
   running, and they campaign every hour. Inhabitants back whoever they favour
   *most*, and abstain when torn. Raising your own standing is not enough if a
   rival raises theirs faster.
3. **Secrets are shared.** A secret belongs to everyone it would ruin, so
   getting one person to confess an affair hands you a hold over two. One
   secret implicates a candidate, which is the leverage route to the election.

Candidates vote for themselves, so six of ten means six of the eight
persuadable.

## Dialogue

`scripts/dialogue/`. Stand next to somebody, press SPACE, and **type whatever
you want to say**. They answer in character. The listed lines are suggestions,
kept only so a new player can discover that bribery and blackmail exist at all;
clicking one runs through exactly the same path as typing your own version.

The order is fixed and load-bearing:

1. The player says something, typed or clicked.
2. `IntentReader` decides what they were **attempting**, and rates how well it
   was put for this particular person.
3. The **simulation** resolves it (`PlayerActions` / `GossipEngine`).
4. The backend phrases that outcome in character.

The model interprets and voices. It never decides consequence. A model that
decided outcomes could be argued into handing over a vote, and the rivals, the
ties and the persuasion ceiling would all stop mattering — the game would become
finding the magic sentence. With Ollama absent the whole thing still plays, on
keyword matching and templates.

- `DialogueBackend` — the interface, and its own template fallback. `OllamaBackend`
  subclasses it for the local model; tests use a `ScriptedBackend` double defined
  inside `test/dialogue_test.gd`.
- `IntentReader` — free text to `{kind, approach, subject, fit}`. Uses Ollama's
  `format: json`. Falls back to keyword matching, which is why "there is coin in
  this for you" still reads as a bribe with no server running.
- `PromptBuilder` — character sheet from `Psyche` + ties + secrets + the top few
  beliefs, plus the tail of the conversation so far. Prose, not numbers: models
  hold character far better from "you obey the law even when it is cruel" than
  from `authority: 0.95`.
- `Conversation` — suggestions, patience, hours spent, transcript.

Two models, because the two jobs are not the same size:

| Model | Job | Measured |
|-------|-----|----------|
| `qwen3:14b` | voicing a character | ~1.3-2.0s warm on an M2 Max |
| `qwen3:4b`  | reading intent | ~0.5s warm, 8/8 on a hand-written set |

`think:false` is mandatory — Qwen3 is reasoning-tuned and otherwise burns
seconds on `<think>`.

### What a well-judged line may and may not buy

`fit` (0..1, neutral 0.5) is the model's rating of the player's actual wording
for this person. It feeds `PlayerActions.delivery_of`, and **the result is
capped at 1.0**. This is the load-bearing rule of the whole feature.

Regard from repeating one approach converges on `raw / (1 - REPEAT_DECAY)`, so
any multiplier above 1.0 raises the persuasion ceiling by the same proportion.
Raise that ceiling and a rival's oldest friend becomes winnable by charm alone,
which retires Expose, the secrets, and the entire leverage half of the game.

A good line is rewarded in the two places that do not touch that number:

- **candour** — `Conversation.candour_threshold` lowers the bar for an honest
  answer about a third party, by at most `CANDOUR_RELIEF`.
- **discretion** — a deftly put approach reaches fewer witnesses.

A *bad* line is punished directly, and the sign matters: delivery is applied as
`delivery` to a positive evaluation and `2 - delivery` to a negative one. Applied
without regard for sign, a clumsy bribe — which evaluates negative, because it
offends — was scaled *towards zero*, and fumbling an approach became the safest
way to make it.

Talking is free. Only an actual attempt on somebody costs an in-game hour, via
`Conversation.hours_spent`, which `Main._charge_hours` spends. Patience is spent
by rebuffs rather than by turns, so a pleasant conversation can run as long as
the player likes and a hostile one does not.

## Procedural towns

`TownGenerator.generate(seed)` builds a fresh town: cast, ties, secrets and
candidates. Set `Main.procedural = true` to play one; `false` gives Ashwood.
`TownSim.setup_from` installs either — the simulation cannot tell which.

Order is the whole design. Ties are woven first, then secrets are derived **from**
those ties: an affair becomes a shared secret, a debt becomes a blackmail. Rolling
secrets independently gives ten unrelated skeletons and no drama, because a secret
is only interesting through who else it touches.

`TownGenerator._assess` rejects a town and retries. Every rule in it corresponds
to a failure that ruins a playthrough *quietly* rather than crashing:

- somebody tied to nobody — cannot be gossiped about or understood
- somebody with nothing to hide — no lever, drops out of the game
- no affair — the observation mechanic is dead
- no secret touching a candidate — leverage cannot reach the election
- no shared secret — every disclosure ruins only one person
- an evenly spread web — no shape to read

## LLM policy

Local models only — no paid APIs, ever.

Background NPC-to-NPC interaction uses **no LLM by design**. `GossipEngine`
resolves it arithmetically because 45 pairs x 24 hours x 7 days would bury any
local model. An LLM is only for dialogue the player is present for.

A 4B model was measured *judging* and failed: with a JSON schema it produced
structurally valid output containing nothing — echoing the player's own line
back as dialogue, `trust_delta` always 0. Structured output makes a small model
*parse*, not *think*. That is why the sim owns every decision; it is also what
makes a 3B model on a phone viable later, since voicing a given outcome is a far
smaller ask than judging one.

The same 4B model was later measured *classifying*, which is what `IntentReader`
asks of it, and scored 8/8 at ~0.5s. The distinction is the whole reason free
text works: reading "there's a purse of silver in it for you" as an attempted
bribe is a small job, and deciding whether it buys a vote is not.

## Status

Playable end to end: title → seven days → results → replay. Covered by 264
tests.

Systems: time, grid + A* pathfinding, schedules, psychological profiles, memory
ledger, gossip engine, needs-driven seeking, incidents, a typed relation web
with shared secrets and observable trysts, probe/blackmail/expose, rival
candidates with campaign AI, player approaches with witness leak, relative
voting, free-text local-LLM conversation, procedural town generation, player
avatar with real-time movement, and a day/night cycle.

Ashwood stays hand-authored as the fixed tutorial town — every balance number is
tuned against it. Generation builds *on* `RelationGraph` + `Secret` rather than
replacing them.

Characters are real sprites: one generated villager walk sheet, recoloured per
inhabitant, y-sorted so a crowd has depth. The town around them — ground,
buildings, props — and all audio are still procedural placeholders drawn in
`scripts/gfx` and `scripts/audio`. They stay isolated behind draw calls and
`play_*` methods, so replacing them means changing those files and nothing else.

Name labels no longer collide: they are dealt into three vertical tiers by
standing-spot index and drawn on a plate, because a name is wider than the two
tiles between neighbours and pale text on a pale tunic cannot be outlined into
legibility.

Two balance guards, which are not behaviour tests — they fail when tuning drifts:

- `test_the_election_is_winnable_by_playing_well` — six votes must stay
  reachable, using the *right* approach per person plus Expose against rivals.
- `test_help_and_flattery_alone_is_not_a_reliable_win` — thoughtless spam must
  not win every playthrough. Measured at 5 wins in 8 seeds, 4-7 votes.

The GDD in `docs/` is the original draft and has drifted. Its Phase 2-5 plan
(LLM bridge, trait-symbol UI, keyword parsing) was superseded: the LLM bridge
exists but phrases outcomes rather than deciding them, and the trait-symbol grid
was replaced by contextual dialogue choices. Treat `docs/` as intent, not spec.

## What is left

No missing *systems* — the mechanics are complete. What remains is presentation
and polish:

1. **The town is still placeholder.** Characters are real now, which makes the
   flat-rectangle buildings and circle trees they stand on the biggest gap. See
   the art pipeline above for the order.
2. **Everyone shares one body.** Ten recoloured copies of one villager read as a
   crowd but not as ten people; there is no variation in build, age or dress. A
   second and third base sheet would fix most of it, at 12 SpriteCook credits
   each.
3. **Audio** is synthesised placeholder cues.
4. **No save/load.** A run is seven days and disposable, so this may never be
   needed; `world_seed` + `procedural` reproduce any town exactly.
5. **Mobile** is unexplored. The dialogue layer was designed for it — the sim
   owns every decision, so a 3B model only has to voice a given outcome — but
   Godot would need a GDExtension wrapping llama.cpp for on-device inference.
