class_name TownGenerator
extends RefCounted

## Builds a new town from a seed.
##
## The order matters more than any individual roll. Ties are woven first, then
## secrets are derived **from** those ties — so the affair produces a shared
## secret, the debt produces a blackmail, and the scandals implicate people who
## already had reason to care about each other.
##
## Generating secrets independently would give ten unrelated skeletons and no
## drama. A secret is only interesting because of who else it touches.
##
## Every attempt is checked against `_assess`, and a town that fails is thrown
## away rather than shipped. Random webs reliably produce unplayable towns:
## nobody with a lever, no route to the election, somebody stranded with no ties
## at all.

const TOWN_SIZE := 10

## Candidates besides the player. Two splits the opposition; one is a duel.
const RIVAL_CANDIDATES := 2

## How many towns to try before giving up and returning the best of a bad lot.
const MAX_ATTEMPTS := 24


## Builds a town, retrying until one passes the fitness check.
static func generate(seed_value: int) -> TownBlueprint:
	var rejections: Array[String] = []

	for attempt in MAX_ATTEMPTS:
		# A fresh derived seed per attempt, so a rejected town does not bias the
		# next one and the whole run stays reproducible from `seed_value`.
		var blueprint: TownBlueprint = _attempt(SimRng.new(seed_value * 1000 + attempt))
		var problem: String = _assess(blueprint)
		if problem == "":
			blueprint.rejections = rejections
			return blueprint
		rejections.append("attempt %d: %s" % [attempt, problem])

	# Fall back to a final unchecked town rather than returning nothing. The
	# rejection list travels with it so a bad seed can be diagnosed.
	var last: TownBlueprint = _attempt(SimRng.new(seed_value))
	last.rejections = rejections
	return last


static func _attempt(rng: SimRng) -> TownBlueprint:
	var entries: Array[Dictionary] = _choose_archetypes(rng)
	var agents: Array[Agent] = _build_agents(entries, rng)
	var relations: RelationGraph = _weave(agents, entries, rng)
	var candidates: Array[StringName] = _choose_candidates(agents, entries, rng)
	var secrets: Array[Secret] = _derive_secrets(agents, entries, relations, candidates, rng)

	return TownBlueprint.new(agents, relations, secrets, candidates)


# --- people ----------------------------------------------------------------

static func _choose_archetypes(rng: SimRng) -> Array[Dictionary]:
	var chosen: Array[Dictionary] = []
	var pool: Array[Dictionary] = []

	for entry in Archetypes.ALL:
		if Archetypes.REQUIRED.has(entry["key"]):
			chosen.append(entry)
		else:
			pool.append(entry)

	while chosen.size() < TOWN_SIZE and not pool.is_empty():
		var index: int = rng.randi_range(0, pool.size() - 1)
		chosen.append(pool[index])
		pool.remove_at(index)

	return chosen


static func _build_agents(entries: Array[Dictionary], rng: SimRng) -> Array[Agent]:
	var names: Array[String] = NamePool.deal(entries.size(), rng)
	var agents: Array[Agent] = []

	for i in entries.size():
		var entry: Dictionary = entries[i]
		var given: String = names[i] if i < names.size() else "Stranger"
		var psyche: Psyche = Archetypes.make_psyche(
			entry, entry["key"], NamePool.full_name(entry, given), rng
		)
		psyche.short_name = NamePool.short_name(given)

		var agent := Agent.new(psyche, Schedule.for_workplace(entry["zone"]))
		agent.set_need(entry["need"], 0.35 + rng.randf() * 0.35)
		agents.append(agent)

	return agents


## The player plus the most ambitious inhabitants. Ambition is an archetype
## property, so who runs varies with who the town happens to contain.
static func _choose_candidates(
	agents: Array[Agent], entries: Array[Dictionary], rng: SimRng
) -> Array[StringName]:
	var ranked: Array[Dictionary] = []
	for i in agents.size():
		# Ambition is partly the role and partly the person. Reading it off the
		# archetype alone meant the same two always ran; drawing on the rolled
		# psyche lets an unusually vain blacksmith stand for the leadership.
		var psyche: Psyche = agents[i].psyche
		var appetite: float = 0.5 * (
			psyche.dark_of(Psyche.Dark.NARCISSISM) + psyche.dark_of(Psyche.Dark.MACHIAVELLIANISM)
		)
		var ambition: float = (
			entries[i].get("ambition", 0.0) * 0.55
			+ appetite * 0.45
			+ (rng.randf() - 0.5) * 0.35
		)
		ranked.append({"id": agents[i].id, "ambition": ambition})

	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["ambition"] == b["ambition"]:
			return str(a["id"]) < str(b["id"])  # deterministic tie-break
		return a["ambition"] > b["ambition"]
	)

	var out: Array[StringName] = [Agent.PLAYER_ID]
	for i in mini(RIVAL_CANDIDATES, ranked.size()):
		out.append(ranked[i]["id"])
	return out


# --- the web ---------------------------------------------------------------

## Weaves a sparse, clustered set of ties.
##
## Counts are chosen to land near fifteen edges across ten people. Enough that
## nobody is stranded, few enough that the map has shape.
static func _weave(agents: Array[Agent], entries: Array[Dictionary], rng: SimRng) -> RelationGraph:
	const K := RelationGraph.Kind
	var graph := RelationGraph.new()
	var ids: Array[StringName] = []
	for agent in agents:
		ids.append(agent.id)

	var loners: Array[StringName] = []
	var protectors: Array[StringName] = []
	var richest: StringName = ids[0]
	var most_wealth: float = -1.0

	for i in agents.size():
		var entry: Dictionary = entries[i]
		if entry.get("loner", false):
			loners.append(agents[i].id)
		if entry.get("protector", false):
			protectors.append(agents[i].id)
		if entry.get("wealth", 0.0) > most_wealth:
			most_wealth = entry["wealth"]
			richest = agents[i].id

	var sociable: Array[StringName] = ids.filter(func(id: StringName) -> bool: return not loners.has(id))

	# One family. Kin is the strongest tie in the game and more than one cluster
	# starts to crowd a ten-person town.
	var family: Array[StringName] = _take(sociable, 2, rng)
	if family.size() == 2:
		graph.add(family[0], family[1], K.KIN)

	# Exactly one affair, always. The whole observation mechanic — noticing two
	# people break their routine at night — depends on there being one.
	var lovers: Array[StringName] = _take(sociable, 2, rng)
	if lovers.size() == 2:
		graph.add(lovers[0], lovers[1], K.AFFAIR)

		# Someone else wants one of them, and does not know. This is the triangle
		# that makes telling the wrong person a strategy.
		var pining: Array[StringName] = _take(
			sociable.filter(func(id: StringName) -> bool: return not lovers.has(id)), 1, rng
		)
		if not pining.is_empty():
			graph.add(pining[0], lovers[rng.randi_range(0, 1)], K.UNREQUITED)

	# Debts, all owed to whoever has the money.
	var debtors: Array[StringName] = _take(
		ids.filter(func(id: StringName) -> bool: return id != richest), 2, rng
	)
	for debtor in debtors:
		graph.add(debtor, richest, K.DEBT)

	# Somebody owes their life to somebody who saves people. This is often the
	# loner's only thread to the rest of the town.
	if not protectors.is_empty():
		var saved_pool: Array[StringName] = loners if not loners.is_empty() else sociable
		var saved: Array[StringName] = _take(
			saved_pool.filter(func(id: StringName) -> bool: return not protectors.has(id)), 1, rng
		)
		if not saved.is_empty():
			graph.add(saved[0], protectors[rng.randi_range(0, protectors.size() - 1)], K.LIFE_DEBT)

	# Warmth, deference, old wounds and feuds.
	_add_pairs(graph, sociable, K.FRIENDSHIP, 2, rng)
	_add_pairs(graph, sociable, K.MENTOR, 1, rng)
	_add_pairs(graph, sociable, K.ESTRANGED, 1, rng)
	_add_pairs(graph, ids, K.RIVALRY, 2, rng)

	_connect_stragglers(graph, agents, rng)
	return graph


## Draws `count` distinct ids without disturbing the caller's array.
static func _take(pool: Array[StringName], count: int, rng: SimRng) -> Array[StringName]:
	var remaining: Array[StringName] = pool.duplicate()
	var out: Array[StringName] = []
	for i in mini(count, remaining.size()):
		var index: int = rng.randi_range(0, remaining.size() - 1)
		out.append(remaining[index])
		remaining.remove_at(index)
	return out


static func _add_pairs(
	graph: RelationGraph, pool: Array[StringName], kind: RelationGraph.Kind, count: int, rng: SimRng
) -> void:
	for i in count:
		var pair: Array[StringName] = _take(pool, 2, rng)
		if pair.size() < 2:
			return
		# Never stack a second tie on a pair that already has one; the strongest
		# would simply mask the other and one edge would be wasted.
		if graph.kind_between(pair[0], pair[1]) != -1:
			continue
		graph.add(pair[0], pair[1], kind)


## Guarantees nobody ends up in the town with no ties at all.
##
## An unconnected inhabitant cannot be gossiped about, leveraged, or understood.
## Even the deliberate loner gets one thread.
static func _connect_stragglers(graph: RelationGraph, agents: Array[Agent], rng: SimRng) -> void:
	const K := RelationGraph.Kind
	var ids: Array[StringName] = []
	for agent in agents:
		ids.append(agent.id)

	for agent in agents:
		if graph.involvement_of(agent.id) > 0:
			continue
		var others: Array[StringName] = ids.filter(
			func(id: StringName) -> bool: return id != agent.id
		)
		var partner: Array[StringName] = _take(others, 1, rng)
		if not partner.is_empty():
			graph.add(agent.id, partner[0], K.FRIENDSHIP)


# --- secrets ---------------------------------------------------------------

## Derives what the town hides from what the town *is*.
##
## Every tie that could produce a scandal does, and anyone left without one gets
## something of their own, because an inhabitant with nothing to hide has no
## lever and drops out of the game entirely.
static func _derive_secrets(
	agents: Array[Agent],
	entries: Array[Dictionary],
	graph: RelationGraph,
	candidates: Array[StringName],
	rng: SimRng
) -> Array[Secret]:
	const K := RelationGraph.Kind
	var secrets: Array[Secret] = []
	var covered: Dictionary = {}

	var mark := func(secret: Secret) -> void:
		secrets.append(secret)
		for participant in secret.participants:
			covered[participant] = true

	# Affairs are shared secrets by their nature.
	for pair in graph.hidden_pairs():
		mark.call(_make(
			StringName("affair_%s" % pair[0]), pair[0], ActionCatalog.ROMANCED, pair[1], 7,
			[pair[0], pair[1]] as Array[StringName], 0.9
		))

	# A debt is leverage waiting to be used. The creditor has been using it.
	for edge in graph.edges():
		if edge["kind"] != K.DEBT:
			continue
		if covered.has(edge["to"]) and covered.has(edge["from"]):
			continue
		mark.call(_make(
			StringName("squeeze_%s" % edge["from"]), edge["to"], ActionCatalog.BLACKMAILED,
			edge["from"], 8, [edge["to"], edge["from"]] as Array[StringName], 0.8
		))
		break  # One is enough; two makes the creditor implausibly busy.

	# At least one candidate must be vulnerable, or leverage cannot reach the
	# election and blackmail becomes a side activity.
	for candidate_id in candidates:
		if candidate_id == Agent.PLAYER_ID:
			continue
		if _touches(secrets, candidate_id):
			continue
		mark.call(_make(
			StringName("ledger_%s" % candidate_id), candidate_id, ActionCatalog.STOLE_FROM,
			&"the town purse", 9, [candidate_id] as Array[StringName], 0.9
		))
		break

	# Everyone else carries something alone, weighted to their character: the
	# ruthless have done something violent, the rest something shabbier.
	for i in agents.size():
		var agent: Agent = agents[i]
		if covered.has(agent.id):
			continue
		mark.call(_solitary_secret(agent, entries[i], agents, rng))

	return secrets


static func _solitary_secret(
	agent: Agent, entry: Dictionary, agents: Array[Agent], rng: SimRng
) -> Secret:
	var others: Array[StringName] = []
	for other in agents:
		if other.id != agent.id:
			others.append(other.id)

	var dark: float = agent.psyche.dark_factor()
	if dark > 0.4 or entry.get("loner", false):
		return _make(
			StringName("blood_%s" % agent.id), agent.id, ActionCatalog.KILLED,
			&"a stranger, years ago", 10, [agent.id] as Array[StringName], 1.0
		)

	var victim: Variant = rng.pick(others)
	var victim_id: StringName = victim if victim != null else &"someone"

	# Only somebody who tends the sick can have ended a patient's suffering.
	# Gating this on high Care alone handed the mercy killing to a blacksmith.
	if entry.get("caregiver", false):
		return _make(
			StringName("mercy_%s" % agent.id), agent.id, ActionCatalog.KILLED,
			&"a dying patient", 9, [agent.id] as Array[StringName], 0.85
		)

	if rng.chance(0.5):
		return _make(
			StringName("informer_%s" % agent.id), agent.id, ActionCatalog.BETRAYED,
			victim_id, 6, [agent.id] as Array[StringName], 0.6
		)

	return _make(
		StringName("theft_%s" % agent.id), agent.id, ActionCatalog.STOLE_FROM,
		victim_id, 6, [agent.id] as Array[StringName], 0.6
	)


static func _make(
	id: StringName, subject: StringName, action: StringName, target: StringName,
	severity: int, participants: Array[StringName], weight: float
) -> Secret:
	return Secret.new(
		id, MemoryToken.new(subject, action, target, true, severity, &"", 0), participants, weight
	)


static func _touches(secrets: Array[Secret], who: StringName) -> bool:
	for secret in secrets:
		if secret.involves(who):
			return true
	return false


# --- fitness ---------------------------------------------------------------

## Returns "" when the town is playable, or the reason it is not.
##
## Each of these has been observed to happen from an unchecked roll, and each
## quietly ruins a playthrough rather than crashing it — which is exactly why
## generation has to check rather than hope.
static func _assess(blueprint: TownBlueprint) -> String:
	if blueprint.agents.size() != TOWN_SIZE:
		return "wrong population: %d" % blueprint.agents.size()

	if blueprint.candidate_ids.size() != RIVAL_CANDIDATES + 1:
		return "wrong number of candidates"

	for agent in blueprint.agents:
		if blueprint.relations.involvement_of(agent.id) == 0:
			return "%s is tied to nobody" % agent.id
		if not _touches(blueprint.secrets, agent.id):
			return "%s has nothing to hide, so no lever exists" % agent.id

	if blueprint.relations.hidden_pairs().is_empty():
		return "no hidden relationship for the player to discover"

	var candidate_exposed: bool = false
	for candidate_id in blueprint.candidate_ids:
		if candidate_id != Agent.PLAYER_ID and _touches(blueprint.secrets, candidate_id):
			candidate_exposed = true
	if not candidate_exposed:
		return "no secret reaches a candidate, so leverage cannot affect the race"

	var shared: int = 0
	for secret in blueprint.secrets:
		if secret.participants.size() > 1:
			shared += 1
	if shared == 0:
		return "no shared secrets, so every disclosure ruins only one person"

	var lowest: int = 99
	var highest: int = 0
	for agent in blueprint.agents:
		var involvement: int = blueprint.relations.involvement_of(agent.id)
		lowest = mini(lowest, involvement)
		highest = maxi(highest, involvement)
	if highest - lowest < 2:
		return "the web is evenly spread and has no shape"

	return ""
