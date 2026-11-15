Game Design Document: The Ashwood Syndicate

1. High-Level Concept

Genre: Emergent Social Simulation / Tactical RPG (Inspired by Big Brother, Mafia, and Dwarf Fortress)
Setting: A secluded, low-fantasy or frontier town (10 NPCs).
Objective: The town leader is dead/missing. The player has 7 in-game days to secure 6 out of 10 votes to become the new leader and claim a hidden stash of immense value.
Core Hook: There are no scripted dialogue trees. All NPCs are driven by an underlying physical/social simulation and brought to life via local LLM injection. The town is a volatile social sandbox of shifting alliances, paranoia, and betrayals.

2. Core Gameplay Loops

Observe & Track: Time is always ticking. The player must observe NPC schedules (who goes to the tavern, who sneaks out at night).

Probe (General Interaction): Talk to NPCs naturally to uncover their psychological traits. The game client parses LLM text to unlock UI "Trait Symbols" (e.g., a Coin for Greed, a Shield for Paranoia).

Exploit (Targeted Action): Use unlocked Trait Symbols to trigger specific approaches (Bribe, Intimidate, Seduce, Blackmail).

Manage the Social Ecosystem: The player is not the center of the universe. NPCs will form their own alliances, lie to each other, and conspire. The player must manage these ripples.

3. Dynamic NPC-to-NPC Interactions (The Social Sandbox)

To capture the tension of social deduction games, NPCs interact autonomously without player prompting.

Passive Encounters (Proximity): NPCs working the same shift (e.g., in the mines, at the market) or sitting at the same table in the tavern have a baseline chance to converse. They may swap low-level memory tokens (gossip).

Active Seeking (Trait & Knowledge Driven): NPCs will dynamically alter their pathfinding to hunt down specific characters based on their internal state.

Example 1 (Paranoia): If NPC A learns a dangerous secret about the player, their Safety need spikes. They may abandon their work shift to actively seek out the Sheriff to tell them.

Example 2 (Machiavellian): NPC B notices NPC C has acquired a lot of gold. NPC B will actively follow NPC C into an empty alleyway to extort them.

Variable Impact: Interactions do not always result in a state change. If an NPC shares a rumor, the listener's AI evaluates it against their own traits. They might believe it, dismiss it as lies, or use it as blackmail material later.

Last-Minute Vote Flipping: Just like in Big Brother, a promised vote is never guaranteed until the final day. A well-placed rumor spread by an enemy NPC on Day 6 can completely flip a vital ally's decision on Day 7.

4. System Architecture

The Engine (Godot): Handles the physical simulation. Maintains the grid, time of day, NPC coordinates, inventory, and the "Relationship/Memory Ledger" (a database of who knows what).

The AI Bridge (Python/FastAPI + Local LLM): A local server running a fast model (e.g., Llama 3 8B). The game engine sends JSON payloads containing the NPC's state to the LLM. The LLM returns a JSON payload with dialogue and an "internal state change".

5. Implementation Task Breakdown (Agile Sprints)

Phase 1: The Simulation Foundation (The Clockwork)

Task 1.1: Create a 2D top-down grid map of the town with 5 distinct zones (Tavern, Market, Residences, Sheriff's Office, Woods).

Task 1.2: Implement the Time System. 1 real minute = 1 in-game hour. 24-hour cycle. 7-day limit.

Task 1.3: Build the base NPC Entity-Component-System. Assign a simple state-machine schedule to 10 generic cubes (e.g., 08:00 Market, 18:00 Tavern, 22:00 Sleep).

Task 1.4: Implement pathfinding (A*) so NPCs physically move between zones according to their schedule.

Phase 2: The LLM Bridge & Memory Ledger

Task 2.1: Set up a local Python server with an LLM inference engine. Create a REST API endpoint /interact.

Task 2.2: Build the Memory Ledger data structure in the game engine.

Task 2.3: Connect the game UI text input to the /interact endpoint. Send a hardcoded character state and print the LLM's response to the screen.

Phase 3: The Trait Symbol UI & Phased Interaction

Task 3.1: Create the Player UI with the "Trait Symbols" grid.

Task 3.2: Implement Keyword Parsing to unlock symbols dynamically based on LLM output.

Task 3.3: Implement Targeted Prompts to alter the system prompt sent to the LLM based on clicked UI symbols.

Phase 4: The Social Engine (Gossip & Active Seeking)

Task 4.1: Implement Passive Gossip: When two NPCs share a zone and are idle, trigger a background LLM or logic check to exchange memory tokens.

Task 4.2: Implement Active Seeking: Add a subroutine to the NPC State Machine. If a specific need (e.g., Paranoia/Fear) crosses a threshold, override their daily schedule and pathfind directly to a target NPC.

Task 4.3: Build the evaluation logic: When an NPC receives a token from another NPC, calculate the impact on their Relationship Scores based on their Big Five traits.

Phase 5: The Voting Logic & Win State

Task 5.1: Create a hidden "Vote Threshold" integer for each NPC (0-100).

Task 5.2: At the end of Day 7, query all 10 NPCs. If their relationship with the player > 75, cast vote for Player. Calculate Win/Loss screen based on 6/10 majority.