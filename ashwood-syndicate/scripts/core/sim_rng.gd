class_name SimRng
extends RefCounted

## Seeded random source for every probabilistic decision in the simulation.
##
## Nothing in the sim may call the global `randf()` / `randi()`. All randomness
## flows through an injected SimRng so a playthrough is reproducible from a
## single integer, and so tests can assert on exact emergent outcomes.

var _rng: RandomNumberGenerator


func _init(seed_value: int = 0) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value


## The seed this generator was created with is recoverable for save games.
var seed_value: int:
	get:
		return _rng.seed


## Returns a float in [0, 1).
func randf() -> float:
	return _rng.randf()


## Returns an int in [from, to] inclusive.
func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


## Returns true with the given probability (0.0 = never, 1.0 = always).
func chance(probability: float) -> bool:
	return _rng.randf() < probability


## Picks one element from `items`, or null when the array is empty.
func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[_rng.randi_range(0, items.size() - 1)]


## Picks one element from `items` where `weights[i]` is the relative likelihood
## of `items[i]`. Non-positive weights are treated as zero. Returns null when the
## arrays are empty, mismatched, or every weight is zero.
func pick_weighted(items: Array, weights: Array[float]) -> Variant:
	if items.is_empty() or items.size() != weights.size():
		return null

	var total: float = 0.0
	for w in weights:
		if w > 0.0:
			total += w
	if total <= 0.0:
		return null

	var roll: float = _rng.randf() * total
	var running: float = 0.0
	for i in items.size():
		if weights[i] <= 0.0:
			continue
		running += weights[i]
		if roll < running:
			return items[i]
	# Floating point drift can leave `roll` a hair past `running`; fall back to
	# the last positively-weighted entry rather than returning null.
	for i in range(items.size() - 1, -1, -1):
		if weights[i] > 0.0:
			return items[i]
	return null
