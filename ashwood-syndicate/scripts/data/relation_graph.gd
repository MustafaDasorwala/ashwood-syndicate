class_name RelationGraph
extends RefCounted

## Who is tied to whom, and how.
##
## Replaces the flat `loyal_to` / `rivals` arrays, which could not tell the
## difference between harming someone's brother, their business partner and
## their secret lover. Those are not the same event and should not produce the
## same reaction.
##
## Deliberately sparse. Ten people fully connected is forty-five edges of mush;
## the town wants a handful of tight clusters and at least one genuine isolate.

enum Kind {
	KIN,          ## Blood. Overrides self-interest entirely.
	MARRIAGE,     ## Public bond. Betrayal of it is catastrophic.
	AFFAIR,       ## Hidden bond. Creates a shared secret.
	UNREQUITED,   ## One-way, hidden. A blind spot and a jealousy.
	DEBT,         ## One-way. The holder can coerce; the debtor resents.
	LIFE_DEBT,    ## One-way. Will act against their own interest to repay.
	MENTOR,       ## One-way deference, from student to teacher.
	FRIENDSHIP,   ## Ordinary, public, warm.
	ESTRANGED,    ## Was close. The old closeness is the wound.
	RIVALRY,      ## Mutual, corrosive.
}

## How strongly each tie makes one party care about the other's fate.
## Positive protects, negative opposes.
const STRENGTH := {
	Kind.KIN: 1.0,
	Kind.MARRIAGE: 0.95,
	Kind.AFFAIR: 0.85,
	Kind.LIFE_DEBT: 0.8,
	Kind.UNREQUITED: 0.7,
	Kind.FRIENDSHIP: 0.6,
	Kind.MENTOR: 0.5,
	Kind.DEBT: -0.2,
	Kind.ESTRANGED: -0.5,
	Kind.RIVALRY: -0.85,
}

## Ties both parties feel equally. The rest are directional.
const MUTUAL := [Kind.KIN, Kind.MARRIAGE, Kind.AFFAIR, Kind.FRIENDSHIP, Kind.ESTRANGED, Kind.RIVALRY]

## Ties the town does not know about. These are what the player has to notice.
const HIDDEN := [Kind.AFFAIR, Kind.UNREQUITED]

## Every edge: { from, to, kind }.
var _edges: Array[Dictionary] = []


## Records a tie. Mutual kinds are stored once and answered in both directions.
func add(from_id: StringName, to_id: StringName, kind: Kind) -> RelationGraph:
	if from_id == to_id:
		return self
	_edges.append({"from": from_id, "to": to_id, "kind": kind})
	return self


func edges() -> Array[Dictionary]:
	return _edges.duplicate(true)


func size() -> int:
	return _edges.size()


static func is_mutual(kind: Kind) -> bool:
	return MUTUAL.has(kind)


static func is_hidden(kind: Kind) -> bool:
	return HIDDEN.has(kind)


## Every tie `id` feels, as { other, kind, strength }. Mutual edges are returned
## from whichever side is asking.
func relations_of(id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for edge in _edges:
		if edge["from"] == id:
			out.append({"other": edge["to"], "kind": edge["kind"], "strength": STRENGTH[edge["kind"]]})
		elif edge["to"] == id and is_mutual(edge["kind"]):
			out.append({"other": edge["from"], "kind": edge["kind"], "strength": STRENGTH[edge["kind"]]})
	return out


## The tie `from_id` feels toward `to_id`, or -1 when there is none.
func kind_between(from_id: StringName, to_id: StringName) -> int:
	for edge in _edges:
		if edge["from"] == from_id and edge["to"] == to_id:
			return edge["kind"]
		if edge["to"] == from_id and edge["from"] == to_id and is_mutual(edge["kind"]):
			return edge["kind"]
	return -1


func has_tie(from_id: StringName, to_id: StringName, kind: Kind) -> bool:
	return kind_between(from_id, to_id) == kind


## How much `from_id` cares what happens to `to_id`, in -1.0 .. 1.0.
##
## The single number the gossip engine needs: positive means harm to them lands
## harder and their wrongdoing gets excused, negative means the opposite.
## Strongest tie wins when several exist.
func attachment(from_id: StringName, to_id: StringName) -> float:
	var strongest: float = 0.0
	for edge in _edges:
		var applies: bool = edge["from"] == from_id and edge["to"] == to_id
		if not applies and is_mutual(edge["kind"]):
			applies = edge["to"] == from_id and edge["from"] == to_id
		if not applies:
			continue
		var value: float = STRENGTH[edge["kind"]]
		if absf(value) > absf(strongest):
			strongest = value
	return strongest


## Everyone tied to `id`, whether warmly or badly.
func connections_of(id: StringName) -> Array[StringName]:
	var seen: Dictionary = {}
	for relation in relations_of(id):
		seen[relation["other"]] = true
	var out: Array[StringName] = []
	for key in seen:
		out.append(key)
	return out


## Pairs meeting in secret. Affairs need somewhere to be, which is what makes
## them observable rather than merely recorded.
func hidden_pairs() -> Array[Array]:
	var out: Array[Array] = []
	for edge in _edges:
		if edge["kind"] == Kind.AFFAIR:
			out.append([edge["from"], edge["to"]])
	return out


## How many ties this inhabitant *feels*. A creditor does not feel a debt, so
## this counts what pulls on them, not what they hold over others.
func degree_of(id: StringName) -> int:
	return relations_of(id).size()


## How many ties this inhabitant appears in at all, in either direction.
##
## The Merchant feels almost nothing for anyone, yet two people owe him money
## and he is central to the town. `degree_of` reports him as near-isolated;
## this is the measure generation should check for stranded characters.
func involvement_of(id: StringName) -> int:
	var count: int = 0
	for edge in _edges:
		if edge["from"] == id or edge["to"] == id:
			count += 1
	return count


## Everyone with a one-way hold over `id` — people who are owed, looked up to,
## or pined after. The other half of the leverage map.
func holds_over(id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for edge in _edges:
		if edge["to"] == id and not is_mutual(edge["kind"]):
			out.append({"other": edge["from"], "kind": edge["kind"]})
	return out
