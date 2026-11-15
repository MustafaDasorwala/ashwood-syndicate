Master Prompt: Godot 4 MVP Generation

Instructions: Copy everything below this line and paste it into Claude (Opus or Sonnet 3.5). When you paste it, make sure to also paste the contents of our previously generated design documents where the brackets indicate.

You are an elite Godot 4 Game Developer, Systems Architect, and Narrative Designer. You specialize in building emergent, systemic simulations, custom Entity-Component-Systems (ECS) in GDScript, and procedural asset generation.

Your task is to build a functional vertical slice / MVP of a 2D top-down emergent social simulation game called "The Ashwood Syndicate."

<project_context>
The game is a 7-day social simulation where the player must secure a majority vote from 10 autonomous NPCs. The NPCs possess deep psychological traits, moral compasses, and dynamic relationships. They follow physical schedules on a 2D grid, interact with each other to spread "memory tokens" (gossip), and their dialogue will eventually be driven by a local LLM.
</project_context>

<provided_documents>
Below are the initial draft design documents for the game. Treat these as foundational drafts, not rigid gospel.

[PASTE GDD_Ashwood_Syndicate.md HERE]
[PASTE Psycho_Profile_Engine.md HERE]
[PASTE Human_Condition_Architecture.md HERE]
[PASTE Background_Convo_Architecture.md HERE]
</provided_documents>

<core_objectives>

Validate and Enhance: Before writing code, analyze the provided drafts. Identify any logical gaps, edge cases in the simulation loops, or architectural bottlenecks (especially regarding the UI-to-AI data flow and the background gossip engine). Propose specific improvements.

Build the Godot Architecture: Design the foundational GDScript architecture for the ECS, the Grid/Pathfinding system, and the Time/Schedule Manager.

Procedural Placeholder Assets: The game must run immediately upon pasting your code into Godot, without requiring me to import any external assets.

Graphics: Use Godot's _draw() function, ColorRect, Polygon2D, or procedural noise to generate distinct visual representations for the town zones, the player, and the NPCs. These must be modular so I can easily swap them for actual PNG sprites later.

Audio: Use Godot's AudioStreamGenerator and math (sine/square waves) to create procedural, synthesized UI sounds, footsteps, or "speech blips" (like Animal Crossing) that can be easily replaced by WAV/OGG files later.
</core_objectives>

Step 1: In a <design_review> XML block, provide a critical analysis of the provided design documents. Highlight at least 3 areas that need refinement for the Godot implementation to be scalable and performant. Suggest concrete solutions.

Step 2: In a <project_structure> XML block, outline the exact Godot file/folder structure (e.g., res://scenes, res://scripts/ecs, res://scripts/audio).

Step 3: Begin generating the foundational GDScript files inside standard markdown code blocks. Start with the most critical foundational systems:

The Global Time & State Manager (Autoload/Singleton).

The base NPC Entity script (handling the traits data structure and schedule).

The Procedural Asset Generators (Graphics and Audio).

Step 4: Ensure all code is strictly typed (using Godot 4's static typing, e.g., var health: int = 100) and heavily commented so I can understand the data flow.


Take a deep breath and think step-by-step. Let's build a living world.