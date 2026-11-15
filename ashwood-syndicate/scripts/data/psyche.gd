class_name Psyche
extends RefCounted

## The complete psychological profile of one inhabitant of Ashwood.
##
## Layers, per the design docs:
##   1. Big Five (OCEAN)        - baseline personality
##   2. Dark Triad              - antisocial modifiers
##   3. Moral Foundations       - what they hold sacred (Haidt)
##   4. Attachments             - who overrides their own logic
##   5. Cognitive biases        - how they misread evidence
##   6. Core trauma + trigger   - what bypasses reasoning entirely
##
## Every scalar is normalised to 0.0 - 1.0 so downstream math never has to know
## which scale a given document used.

## Big Five personality dimensions.
enum Trait { OPENNESS, CONSCIENTIOUSNESS, EXTRAVERSION, AGREEABLENESS, NEUROTICISM }

## Antisocial personality modifiers layered over the Big Five.
enum Dark { MACHIAVELLIANISM, NARCISSISM, PSYCHOPATHY }

## Haidt's moral foundations. Determines what an NPC treats as sacred.
enum Foundation { CARE, FAIRNESS, LOYALTY, AUTHORITY, SANCTITY }

## Systematic reasoning errors that make an NPC feel human rather than optimal.
enum Bias {
	NONE,
	## Believes evidence that confirms an existing opinion, discounts the rest.
	CONFIRMATION,
	## Doubles down on a failing investment rather than admit error.
	SUNK_COST,
	## Lets charm or attractiveness suppress red flags.
	HALO,
}

var id: StringName
var display_name: String

## What the town calls them. Drawn on the map, where full names from ten
## inhabitants standing together overlap into an unreadable smear.
var short_name: String

## Trait -> 0.0..1.0
var traits: Dictionary = {}
## Dark -> 0.0..1.0
var dark_triad: Dictionary = {}
## Foundation -> 0.0..1.0. How sacred this axis is to them.
var morality: Dictionary = {}

var bias: Bias = Bias.NONE

## Ids this NPC is bonded to. Harm to these overrides self-interest.
var loyal_to: Array[StringName] = []
## Ids this NPC despises. They will oppose whatever these ids support.
var rivals: Array[StringName] = []

## A subject that bypasses evaluation and provokes a raw emotional response.
## Matched against MemoryToken.action. Empty means no trigger.
var trauma_trigger: StringName = &""


func _init(
	p_id: StringName = &"",
	p_display_name: String = "",
	p_traits: Dictionary = {},
	p_dark_triad: Dictionary = {},
	p_morality: Dictionary = {}
) -> void:
	id = p_id
	display_name = p_display_name
	# Last word of the full name reads as the familiar form for most of the
	# cast ("Sheriff Calder" -> "Calder"). Overridable where it does not.
	var parts: PackedStringArray = p_display_name.split(" ", false)
	short_name = parts[parts.size() - 1] if parts.size() > 0 else p_display_name

	# Default every axis to the midpoint so a partially-specified profile is
	# still valid. Callers override only the dimensions they care about.
	for t in Trait.values():
		traits[t] = 0.5
	for d in Dark.values():
		dark_triad[d] = 0.1
	for f in Foundation.values():
		morality[f] = 0.5

	for key in p_traits:
		traits[key] = clampf(p_traits[key], 0.0, 1.0)
	for key in p_dark_triad:
		dark_triad[key] = clampf(p_dark_triad[key], 0.0, 1.0)
	for key in p_morality:
		morality[key] = clampf(p_morality[key], 0.0, 1.0)


func trait_of(t: Trait) -> float:
	return traits.get(t, 0.5)


func dark_of(d: Dark) -> float:
	return dark_triad.get(d, 0.0)


func moral_of(f: Foundation) -> float:
	return morality.get(f, 0.5)


## The foundation this NPC holds most sacred. Ties resolve by enum order, which
## keeps the result deterministic.
func highest_foundation() -> Foundation:
	var best: Foundation = Foundation.CARE
	var best_value: float = -1.0
	for f in Foundation.values():
		var value: float = moral_of(f)
		if value > best_value:
			best_value = value
			best = f
	return best


## Overall antisocial weighting, used where the three dark traits act together
## (e.g. willingness to distort a rumour before passing it on).
func dark_factor() -> float:
	var total: float = 0.0
	for d in Dark.values():
		total += dark_of(d)
	return total / float(Dark.size())


func is_triggered_by(action: StringName) -> bool:
	return trauma_trigger != &"" and trauma_trigger == action
