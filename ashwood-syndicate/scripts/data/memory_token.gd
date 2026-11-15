class_name MemoryToken
extends RefCounted

## One atomic piece of information an NPC believes: "X did Y to Z".
##
## The gossip engine never generates prose. It moves these structs between
## Memory Ledgers and recomputes relationships from them. Text generation is
## reserved for interactions the player is actually present for.

var subject_id: StringName   ## Who performed the action.
var action: StringName       ## What they did. Key into ActionCatalog.
var target_id: StringName    ## Who it was done to. May be empty.
var truth_value: bool        ## Whether this actually happened.
var severity: int            ## 1 (mundane) .. 10 (treason).
var origin_id: StringName    ## Who told the holder. Empty means witnessed firsthand.
var day_learned: int         ## In-game day the holder acquired it.


func _init(
	p_subject_id: StringName = &"",
	p_action: StringName = &"",
	p_target_id: StringName = &"",
	p_truth_value: bool = true,
	p_severity: int = 1,
	p_origin_id: StringName = &"",
	p_day_learned: int = 0
) -> void:
	subject_id = p_subject_id
	action = p_action
	target_id = p_target_id
	truth_value = p_truth_value
	severity = clampi(p_severity, 1, 10)
	origin_id = p_origin_id
	day_learned = p_day_learned


## Identity of the *claim*, independent of who is retelling it or when.
##
## This is what stops the design's runaway-reinforcement problem: two NPCs
## telling you the same thing is one belief, not two relationship hits.
## Note that `truth_value` is part of the key, so a distorted retelling ("the
## player did NOT do it") is a genuinely different claim and lands separately.
func content_key() -> StringName:
	return StringName("%s|%s|%s|%s" % [subject_id, action, target_id, truth_value])


## Firsthand knowledge is trusted more than hearsay.
func is_firsthand() -> bool:
	return origin_id == &""


## A copy carrying a new origin and learn-day, for passing along a chain.
func retold_by(new_origin: StringName, day: int) -> MemoryToken:
	return MemoryToken.new(
		subject_id, action, target_id, truth_value, severity, new_origin, day
	)


func duplicate_token() -> MemoryToken:
	return MemoryToken.new(
		subject_id, action, target_id, truth_value, severity, origin_id, day_learned
	)


func _to_string() -> String:
	var truth_mark: String = "" if truth_value else " (false)"
	return "[%s %s %s sev=%d%s]" % [subject_id, action, target_id, severity, truth_mark]
