extends Node

## Autoload. Single place systems announce things without knowing each other.
##
## Registered as `EventBus`. Keeping the simulation, the UI and the eventual LLM
## bridge decoupled matters here because the gossip engine fires constantly and
## the UI must never be on its call path.

## An in-game hour elapsed. `day` is 0-based, `hour` is 0-23.
signal hour_changed(day: int, hour: int)

## Midnight rolled over into a new day.
signal day_changed(day: int)

## The 7-day limit expired. Time to tally votes.
signal deadline_reached()

## An NPC moved to a different zone.
signal npc_entered_zone(npc_id: StringName, zone: int)

## Two NPCs exchanged a memory token in the background. Carries enough for the
## UI to show a clue without exposing the underlying math.
signal gossip_exchanged(speaker_id: StringName, listener_id: StringName, token: MemoryToken)

## An NPC's opinion of someone shifted. `delta` is the applied change.
signal relationship_changed(holder_id: StringName, about_id: StringName, delta: float)

## An NPC abandoned their schedule to hunt someone down.
signal seeking_started(npc_id: StringName, target_id: StringName)

## A candidate — the player or a rival — approached someone. `witnesses` are the
## NPCs who saw it and formed their own opinion, which is usually the part that
## decides the election.
signal approach_made(
	actor_id: StringName, kind: int, target_id: StringName,
	target_delta: float, witnesses: Array
)

## Somebody learned what someone else has been hiding.
signal secret_uncovered(finder_id: StringName, subject_id: StringName, secret: MemoryToken)

## Two inhabitants generated their own trouble, with no candidate involved.
signal incident_occurred(token: MemoryToken)

## The election resolved. `result` is the tally dictionary.
signal election_resolved(result: Dictionary)
