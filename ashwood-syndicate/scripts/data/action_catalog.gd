class_name ActionCatalog
extends RefCounted

## Static table describing what each token action *means* morally.
##
## This is the bridge between the psychology documents and the relationship
## math. An action carries:
##   - `violates`: which moral foundations it offends, and how strongly (0..1)
##   - `ruthlessness`: how much a Dark Triad personality *admires* it
##   - `prosocial`: whether it reflects well on the subject by default
##
## Keeping this as data rather than branching code means new actions are one
## dictionary entry, and the gossip engine never grows a switch statement.

const BRIBED := &"bribed"
const THREATENED := &"threatened"
const HELPED := &"helped"
const LIED_TO := &"lied_to"
const STOLE_FROM := &"stole_from"
const KILLED := &"killed"
const ROMANCED := &"romanced"
const DEFENDED := &"defended"
const BETRAYED := &"betrayed"
const DESECRATED := &"desecrated"
const FLATTERED := &"flattered"
const BLACKMAILED := &"blackmailed"

const _F := Psyche.Foundation

## action -> { violates: { Foundation: float }, ruthlessness: float, prosocial: bool }
const TABLE := {
	BRIBED: {
		"violates": {_F.FAIRNESS: 0.9, _F.AUTHORITY: 0.4},
		"ruthlessness": 0.5,
		"prosocial": false,
	},
	THREATENED: {
		"violates": {_F.CARE: 0.8, _F.FAIRNESS: 0.3},
		"ruthlessness": 0.7,
		"prosocial": false,
	},
	HELPED: {
		"violates": {},
		"ruthlessness": 0.0,
		"prosocial": true,
	},
	LIED_TO: {
		"violates": {_F.FAIRNESS: 0.6, _F.LOYALTY: 0.4},
		"ruthlessness": 0.5,
		"prosocial": false,
	},
	STOLE_FROM: {
		"violates": {_F.FAIRNESS: 0.9, _F.AUTHORITY: 0.5},
		"ruthlessness": 0.6,
		"prosocial": false,
	},
	KILLED: {
		"violates": {_F.CARE: 1.0, _F.AUTHORITY: 0.8, _F.SANCTITY: 0.7},
		"ruthlessness": 1.0,
		"prosocial": false,
	},
	ROMANCED: {
		"violates": {_F.SANCTITY: 0.4},
		"ruthlessness": 0.2,
		"prosocial": false,
	},
	DEFENDED: {
		"violates": {},
		"ruthlessness": 0.1,
		"prosocial": true,
	},
	BETRAYED: {
		"violates": {_F.LOYALTY: 1.0, _F.FAIRNESS: 0.5},
		"ruthlessness": 0.8,
		"prosocial": false,
	},
	DESECRATED: {
		"violates": {_F.SANCTITY: 1.0, _F.AUTHORITY: 0.4},
		"ruthlessness": 0.5,
		"prosocial": false,
	},
	# Flattery costs nothing and offends nobody's morals — it works purely on
	# vanity, which is why it lands so differently across the cast. `vanity` is
	# optional and defaults to zero for every other action.
	FLATTERED: {
		"violates": {},
		"ruthlessness": 0.1,
		"prosocial": false,
		"vanity": 1.0,
	},
	# The most effective and most dangerous thing in the game. Offends almost
	# every foundation at once, so if it ever becomes public it is ruinous.
	BLACKMAILED: {
		"violates": {_F.FAIRNESS: 0.9, _F.CARE: 0.7, _F.LOYALTY: 0.5, _F.AUTHORITY: 0.6},
		"ruthlessness": 0.9,
		"prosocial": false,
	},
}

const _UNKNOWN := {"violates": {}, "ruthlessness": 0.0, "prosocial": false}


static func entry(action: StringName) -> Dictionary:
	return TABLE.get(action, _UNKNOWN)


static func is_known(action: StringName) -> bool:
	return TABLE.has(action)


## How strongly `action` offends `foundation`, 0.0 when it does not.
static func violation(action: StringName, foundation: Psyche.Foundation) -> float:
	var violates: Dictionary = entry(action).get("violates", {})
	return violates.get(foundation, 0.0)


static func ruthlessness(action: StringName) -> float:
	return entry(action).get("ruthlessness", 0.0)


## How strongly this action appeals to the listener's self-regard rather than
## their morals. Only flattery uses it today.
static func vanity(action: StringName) -> float:
	return entry(action).get("vanity", 0.0)


static func is_prosocial(action: StringName) -> bool:
	return entry(action).get("prosocial", false)


## Every foundation this action offends. Used by the gossip engine to score a
## token against a listener's personal moral weighting.
static func violated_foundations(action: StringName) -> Array:
	return entry(action).get("violates", {}).keys()
