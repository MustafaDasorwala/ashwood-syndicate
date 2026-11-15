class_name Secret
extends RefCounted

## Something the town does not know, and who it would ruin.
##
## Previously a secret was one hidden string owned by one person. That cannot
## represent an affair — the single most useful kind of secret — because an
## affair belongs to *two* people and exposing it destroys both. Making the
## secret the object, with participants and a set of knowers, gives shared
## secrets, asymmetric leverage, and third parties who stumbled onto something
## they were never meant to see.

var id: StringName

## The claim itself, in the same form as any other belief so it can enter the
## gossip pipeline unchanged once it leaks.
var content: MemoryToken

## Everyone the secret is about. Exposure damages all of them.
var participants: Array[StringName] = []

## How ruinous exposure would be, 0.0 - 1.0. Scales the reputational hit.
var weight: float = 0.6

## id -> true, for everyone who currently knows. Includes the participants, and
## the player once they have uncovered it.
var _knowers: Dictionary = {}


func _init(
	p_id: StringName = &"",
	p_content: MemoryToken = null,
	p_participants: Array[StringName] = [],
	p_weight: float = 0.6
) -> void:
	id = p_id
	content = p_content
	participants = p_participants
	weight = clampf(p_weight, 0.0, 1.0)

	# You always know what you yourself did.
	for participant in participants:
		_knowers[participant] = true


func involves(who: StringName) -> bool:
	return participants.has(who)


func is_known_to(who: StringName) -> bool:
	return _knowers.has(who)


## Records that someone has found out. Returns true only the first time, which
## is the caller's cue to apply consequences.
func reveal_to(who: StringName) -> bool:
	if _knowers.has(who):
		return false
	_knowers[who] = true
	return true


func knowers() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in _knowers:
		out.append(key)
	return out


## How many people outside the secret itself have found out. The town's sense of
## how close this is to breaking.
func outsiders_who_know() -> int:
	var count: int = 0
	for key in _knowers:
		if not participants.has(key) and key != Agent.PLAYER_ID:
			count += 1
	return count


## Whether this is still contained among the people it belongs to.
func is_contained() -> bool:
	return outsiders_who_know() == 0


## The other participant, for two-person secrets. Empty for solitary ones.
func partner_of(who: StringName) -> StringName:
	for participant in participants:
		if participant != who:
			return participant
	return &""


func _to_string() -> String:
	return "[secret %s: %s, known to %d]" % [id, str(content), _knowers.size()]
