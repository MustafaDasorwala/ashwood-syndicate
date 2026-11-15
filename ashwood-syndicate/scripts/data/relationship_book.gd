class_name RelationshipBook
extends RefCounted

## How one NPC feels about everyone else, on a 0-100 scale.
##
## 50 is indifference, 0 is hatred, 100 is devotion. The voting rule in the GDD
## reads this: at the end of Day 7, a score above VOTE_THRESHOLD against the
## player becomes a vote.

const NEUTRAL := 50.0
const MIN_SCORE := 0.0
const MAX_SCORE := 100.0

## Relationship with the player required to secure their vote.
const VOTE_THRESHOLD := 75.0

## id -> float
var _scores: Dictionary = {}


func score_for(other_id: StringName) -> float:
	return _scores.get(other_id, NEUTRAL)


func set_score(other_id: StringName, value: float) -> void:
	_scores[other_id] = clampf(value, MIN_SCORE, MAX_SCORE)


## Applies a delta and returns the amount actually applied after clamping, so
## callers can tell a real swing from one absorbed by the floor or ceiling.
func adjust(other_id: StringName, delta: float) -> float:
	var before: float = score_for(other_id)
	set_score(other_id, before + delta)
	return score_for(other_id) - before


func would_vote_for(other_id: StringName) -> bool:
	return score_for(other_id) > VOTE_THRESHOLD


## Everyone this NPC has an opinion about.
func known_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in _scores:
		out.append(key)
	return out


## How much weight to give something this source claims, 0.0..1.0.
##
## A trusted friend's word lands close to firsthand; a hated rival is largely
## discounted. Unknown sources sit at neutral trust.
func trust_in(source_id: StringName) -> float:
	if source_id == &"":
		return 1.0  # Witnessed it personally.
	return score_for(source_id) / MAX_SCORE


func _to_string() -> String:
	return str(_scores)
