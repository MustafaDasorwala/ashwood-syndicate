class_name MemoryLedger
extends RefCounted

## Everything one NPC believes, keyed so the same claim can never be counted
## twice.
##
## Two properties matter for the simulation staying stable across 7 days:
##   1. Dedup by `content_key()` - hearing a rumour twice does not double its
##      relationship impact.
##   2. A hard capacity - a 10-NPC town gossiping every hour would otherwise
##      grow ledgers without bound, and the LLM prompt has a finite budget.

## Maximum claims one NPC can hold. On overflow the least significant belief is
## forgotten: low severity and old first.
const CAPACITY := 48

## content_key -> MemoryToken
var _tokens: Dictionary = {}


func size() -> int:
	return _tokens.size()


func is_empty() -> bool:
	return _tokens.is_empty()


func knows(token: MemoryToken) -> bool:
	return _tokens.has(token.content_key())


func knows_key(key: StringName) -> bool:
	return _tokens.has(key)


## Files a new belief. Returns true only when this was genuinely new
## information, which is the caller's signal to apply a relationship change.
##
## A repeat of a known claim is *not* new, but firsthand witnessing upgrades a
## belief previously held as hearsay, since the NPC now trusts it more.
func record(token: MemoryToken) -> bool:
	var key: StringName = token.content_key()
	var existing: MemoryToken = _tokens.get(key)

	if existing != null:
		if token.is_firsthand() and not existing.is_firsthand():
			_tokens[key] = token
		return false

	_tokens[key] = token
	if _tokens.size() > CAPACITY:
		_forget_least_significant()
	return true


func get_token(key: StringName) -> MemoryToken:
	return _tokens.get(key)


func all() -> Array[MemoryToken]:
	var out: Array[MemoryToken] = []
	for key in _tokens:
		out.append(_tokens[key])
	return out


## Every belief about a given subject, e.g. all the dirt held on the player.
func about(subject_id: StringName) -> Array[MemoryToken]:
	var out: Array[MemoryToken] = []
	for key in _tokens:
		var token: MemoryToken = _tokens[key]
		if token.subject_id == subject_id:
			out.append(token)
	return out


## The `count` most significant beliefs, newest and most severe first.
##
## This is the LLM prompt budget: the whole ledger never goes into a prompt,
## only what the NPC would actually bring up.
func most_significant(count: int) -> Array[MemoryToken]:
	var sorted: Array[MemoryToken] = all()
	sorted.sort_custom(_more_significant_than)
	return sorted.slice(0, maxi(count, 0))


func clear() -> void:
	_tokens.clear()


## Severity dominates; recency breaks ties so fresh scandal outranks stale
## scandal of equal weight.
static func _more_significant_than(a: MemoryToken, b: MemoryToken) -> bool:
	if a.severity != b.severity:
		return a.severity > b.severity
	if a.day_learned != b.day_learned:
		return a.day_learned > b.day_learned
	return a.content_key() < b.content_key()


func _forget_least_significant() -> void:
	var sorted: Array[MemoryToken] = all()
	sorted.sort_custom(_more_significant_than)
	for i in range(CAPACITY, sorted.size()):
		_tokens.erase(sorted[i].content_key())
