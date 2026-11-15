Background Conversation Architecture (The Gossip Engine)

Running a full LLM inference for every single interaction between NPCs in the background would instantly overload the local server. To solve this, we must build a system that simulates meaningful conversations and relationship changes without generating actual text, saving the LLM exclusively for interactions involving the player.

This system handles how NPCs exchange information (Memory Tokens), influence each other, and decide to hunt each other down, all through lightweight mathematical logic.

1. The Core Data Structure: Memory Tokens

Instead of saving sentences, the game engine tracks information as standardized JSON objects called Memory Tokens.

{
  "subject_id": "player_01",
  "action": "bribed",
  "target_id": "npc_blacksmith",
  "truth_value": true, 
  "severity": 8, // 1-10 scale (1 = mundane, 10 = treason)
  "origin_id": "npc_sheriff" // Who told them this?
}


Every NPC has an array of these tokens in their Memory Ledger.

2. Interaction Triggers (When do NPCs talk?)

The Godot engine constantly checks the physical state of the NPCs to see if a conversation should occur.

Passive Trigger (Proximity): If NPC A and NPC B are in the same room (e.g., Tavern, Market) and their current state is Idle, there is a 30% chance per in-game hour that they will converse.

Active Trigger (Seeking): If an NPC's internal Needs cross a specific threshold (e.g., Paranoia > 80), they will override their daily schedule.

Example: NPC A learns the player killed someone. NPC A's Paranoia spikes. The AI looks for the nearest "Protector" (e.g., The Sheriff). NPC A pathfinds directly to the Sheriff to initiate an Active Conversation.

3. The Conversation Logic Loop

When a trigger fires, the Godot engine runs the Gossip Engine script. No text is generated. Instead, the engine performs the following mathematical exchange:

Step A: Selection (What to share?)

The speaker (NPC A) selects a Memory Token to share with the listener (NPC B). The selection is weighted by NPC A's traits.

Gossips (High Extraversion) will share tokens with high severity values.

Manipulators (High Machiavellianism) will share tokens that specifically lower the listener's relationship with a rival.

Paranoid (High Neuroticism) will share tokens relating to threats or danger.

Step B: Evaluation (How does the listener react?)

NPC B receives the token. The engine calculates how this new information changes NPC B's relationship scores based on their traits.

Example Token: [Subject: Player, Action: Bribed Blacksmith, Severity: 6]

NPC B is the Honest Mayor (High Conscientiousness, Low Dark Triad):

The action "Bribed" conflicts heavily with the Mayor's traits.

Result: Mayor's relationship with Player drops by 20 points. Mayor's relationship with Blacksmith drops by 10 points.

NPC B is the Corrupt Merchant (High Dark Triad):

The action "Bribed" indicates the Player is willing to play dirty, which the Merchant respects.

Result: Merchant's relationship with Player increases by 10 points.

Step C: The Lie & Distortion Mechanic (Optional Complexity)

Information degrades. When NPC A passes a token to NPC B, the engine checks NPC A's Agreeableness and Dark Triad scores. If they are highly manipulative, they might alter the token before passing it.

They might change truth_value to false (creating a rumor).

They might change the subject_id to frame someone else.

4. The Last-Minute Flip

Because this engine runs constantly, the town is extremely volatile.

On Day 6, the player might have a solid 80/100 relationship with the Blacksmith (securing his vote). However, on Day 7, the Blacksmith goes to the market and has a Passive Conversation with the Mayor. The Mayor shares a highly severe negative token about the Player. The Blacksmith evaluates the token, his relationship score plummets to 40/100, and the player loses the vote without ever knowing why.

5. Exposing the System to the Player

To prevent the player from feeling cheated by invisible background math, the engine must provide clues that these conversations happened.

Visual Clues: The player sees NPC A sprint across town to find the Sheriff.

UI Clues: If the player clicks the Blacksmith on Day 7, the UI might show a new locked symbol or a mood indicator (e.g., Suspicious), prompting the player to investigate what changed.

LLM Injection: The true power of this system! If the player talks to the Blacksmith after his score dropped, the Godot engine injects the new token into the LLM prompt. The Blacksmith will now dynamically generate dialogue referencing the rumor: "I heard what you did. Don't think you can buy me."