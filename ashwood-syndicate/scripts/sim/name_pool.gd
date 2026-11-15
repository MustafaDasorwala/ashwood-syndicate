class_name NamePool
extends RefCounted

## Names for a generated town.
##
## Drawn from fixed pools rather than assembled from syllables — invented
## syllables produce names that read as fantasy filler, and this town is meant
## to feel like a hard place people actually live.

const GIVEN := [
	"Calder", "Thorne", "Bram", "Yolen", "Elias", "Maret", "Adric", "Pell",
	"Serrin", "Cass", "Hale", "Wren", "Otto", "Nessa", "Garrick", "Ivy",
	"Roswell", "Dorra", "Merrick", "Sable", "Ansel", "Rhoda", "Til", "Fenn",
	"Orla", "Bledd", "Kestrel", "Mabon", "Rue", "Tobias", "Winnow", "Corliss",
]

## Attached to a plain given name to make somebody sound long-settled.
const EPITHETS := ["Old", "Young", "Big", "Little", "Silent", "Red"]


## Deals `count` distinct given names.
static func deal(count: int, rng: SimRng) -> Array[String]:
	var remaining: Array[String] = []
	remaining.assign(GIVEN)

	var out: Array[String] = []
	for i in mini(count, remaining.size()):
		var index: int = rng.randi_range(0, remaining.size() - 1)
		out.append(remaining[index])
		remaining.remove_at(index)
	return out


## Full name for an inhabitant, from their archetype and a given name.
##
## "Sheriff Calder" and "Maret the Healer" read very differently; which form an
## archetype takes is part of its character.
static func full_name(entry: Dictionary, given: String) -> String:
	var role: String = entry.get("role", "")
	if role == "":
		return given
	if entry.get("title_first", false):
		return "%s %s" % [role, given]
	return "%s %s" % [given, role]


## The familiar form, drawn on the map where full names collide into a smear.
static func short_name(given: String) -> String:
	return given
