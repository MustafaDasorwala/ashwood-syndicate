class_name TownSim
extends Node

## Drives the whole town: one simulation step per in-game hour.
##
## Each step, in order:
##   1. Move every agent to where their schedule (or their panic) puts them.
##   2. Resolve passive conversations between co-located idle agents.
##   3. Decay needs, and let urgent needs override tomorrow's routine.
##
## Stepping is hour-granular rather than frame-granular so the same code path
## runs identically at 1x speed and in a headless test that burns through all
## seven days in a few milliseconds.

## Cap on conversations resolved per hour, protecting the frame budget when a
## festival-sized crowd ends up in one zone.
const MAX_EXCHANGES_PER_HOUR := 12

## How fast unmet needs climb each hour when the agent does nothing about them.
const NEED_DRIFT := 0.02

## How far a satisfied need falls after the agent acts on it.
const NEED_RELIEF := 0.5

## Starting opinion of someone an NPC is bonded to.
const BOND_SCORE := 85.0

## Starting opinion of an arch-rival.
const FEUD_SCORE := 15.0

## Everyone contesting the leadership. The player plus the two inhabitants with
## the strongest reasons to want it: a narcissist who already holds office and a
## manipulator who thinks he should.
##
## Candidates vote for themselves, so the player must win a clear majority of
## the remaining town rather than a bare majority overall.
var candidate_ids: Array[StringName] = [Agent.PLAYER_ID]

var grid: TownGrid
var rng: SimRng

var agents: Array[Agent] = []

## Where the player is standing. They can only approach people who are actually
## in the room with them, exactly as rivals can — and moving costs an hour.
##
## Without this the player could reach all ten inhabitants every hour from
## nowhere at all, while rivals were limited to whoever happened to be beside
## them. That asymmetry, not the persuasion maths, was what made the election
## trivial to grind.
var player_zone: int = TownGrid.Zone.TAVERN

## The town's web of ties.
var relations: RelationGraph

## Every hidden thing in town. Knowledge of each lives on the Secret itself,
## including the player's, so there is one answer to "who knows".
var secrets: Array[Secret] = []

## What the player has been told. Asking someone about a third party is how most
## of this arrives, which makes conversation a way of gathering information
## rather than only a way of spending it.
var player_ledger: MemoryLedger = MemoryLedger.new()

## Hours elapsed, used to stagger rival campaigning.
var _hour_index: int = 0
## id -> Agent, for lookups during seeking and player interaction.
var _by_id: Dictionary = {}

var _connected: bool = false


## Builds the town. Call once before stepping.
##
## `seed_value` makes an entire playthrough reproducible: the same seed with the
## same player actions produces the same rumours, the same feuds and the same
## final vote.
func setup(seed_value: int = 1, roster: Array[Agent] = []) -> void:
	var blueprint := TownBlueprint.new(
		roster if not roster.is_empty() else Roster.build_all(),
		Roster.build_relations(),
		Roster.build_secrets(),
		[Agent.PLAYER_ID, Roster.MAYOR, Roster.MERCHANT] as Array[StringName]
	)
	setup_from(blueprint, seed_value)


## Builds a fresh town from a seed instead of the hand-authored one.
func setup_generated(seed_value: int) -> TownBlueprint:
	var blueprint: TownBlueprint = TownGenerator.generate(seed_value)
	setup_from(blueprint, seed_value)
	return blueprint


## Installs a town. Ashwood and a generated town arrive here identically — the
## simulation cannot tell which it is running.
func setup_from(blueprint: TownBlueprint, seed_value: int = 1) -> void:
	rng = SimRng.new(seed_value)
	grid = TownGrid.new()

	agents = blueprint.agents
	relations = blueprint.relations
	secrets = blueprint.secrets
	candidate_ids = blueprint.candidate_ids
	player_ledger = MemoryLedger.new()

	_by_id.clear()
	for agent in agents:
		_by_id[agent.id] = agent
		agent.relations = relations
		agent.current_zone = agent.schedule.zone_at(GameClock.hour)

	_resolve_roles()
	_seed_social_graph()


## Who a frightened inhabitant runs to, and who the ambitious go to for money.
##
## Derived from character rather than hardcoded ids, because a generated town
## has no "sheriff" — but it always has somebody who holds authority sacred and
## somebody who reads every conversation for advantage.
var protector_id: StringName = &""
var broker_id: StringName = &""


func _resolve_roles() -> void:
	protector_id = &""
	broker_id = &""
	var best_authority: float = -1.0
	var best_leverage: float = -1.0

	for agent in agents:
		var authority: float = agent.psyche.moral_of(Psyche.Foundation.AUTHORITY)
		if authority > best_authority:
			best_authority = authority
			protector_id = agent.id

		var leverage: float = agent.psyche.dark_of(Psyche.Dark.MACHIAVELLIANISM)
		if leverage > best_leverage:
			best_leverage = leverage
			broker_id = agent.id


## Turns the relation web into actual opening relationship scores.
##
## Without this the town begins as a blank graph where everyone trusts everyone
## equally — which quietly disables the trust discount in the gossip engine, so
## it stops mattering *who* carries a rumour and every playthrough converges on
## the same numbers. Pre-existing bonds and feuds are what make the transmission
## path consequential.
func _seed_social_graph() -> void:
	for agent in agents:
		for relation in relations.relations_of(agent.id):
			if not _by_id.has(relation["other"]):
				continue
			# Map tie strength onto the 0-100 regard scale: a blood tie opens
			# near devotion, a feud near contempt, a debt slightly sour.
			var strength: float = relation["strength"]
			var score: float = RelationshipBook.NEUTRAL + strength * (
				(RelationshipBook.MAX_SCORE - RelationshipBook.NEUTRAL) * 0.8
			)
			agent.relationships.set_score(relation["other"], score)

	# Anything still declared with the older flat arrays is honoured too, so a
	# hand-built agent without a graph entry still starts sensibly.
	for agent in agents:
		for ally_id in agent.psyche.loyal_to:
			if _by_id.has(ally_id) and relations.kind_between(agent.id, ally_id) == -1:
				agent.relationships.set_score(ally_id, BOND_SCORE)
		for rival_id in agent.psyche.rivals:
			if _by_id.has(rival_id) and relations.kind_between(agent.id, rival_id) == -1:
				agent.relationships.set_score(rival_id, FEUD_SCORE)
				(_by_id[rival_id] as Agent).relationships.set_score(agent.id, FEUD_SCORE)


func _ready() -> void:
	if grid == null:
		setup()
	_connect_clock()


func _connect_clock() -> void:
	if _connected:
		return
	EventBus.hour_changed.connect(_on_hour_changed)
	_connected = true


func agent_by_id(id: StringName) -> Agent:
	return _by_id.get(id)


func _on_hour_changed(_day: int, hour: int) -> void:
	step_hour(GameClock.day, hour)


## One simulation tick. Public so tests and debug tooling can drive the town
## without a running clock.
func step_hour(day: int, hour: int) -> void:
	_update_positions(hour)
	_resolve_trysts(day, hour)
	IncidentEngine.step(self, day)
	CampaignAi.step(self, _hour_index, day)
	_resolve_conversations(day)
	_update_needs()
	_hour_index += 1


## Files something the player was told. Returns true when it was new to them.
func player_learns(token: MemoryToken) -> bool:
	return player_ledger.record(token)


## What the player currently believes about someone.
func player_knows_about(subject_id: StringName) -> Array[MemoryToken]:
	return player_ledger.about(subject_id)


## Every secret `who` is a participant in.
func secrets_about(who: StringName) -> Array[Secret]:
	var out: Array[Secret] = []
	for secret in secrets:
		if secret.involves(who):
			out.append(secret)
	return out


## Secrets `who` knows but is not part of — pure leverage over other people.
func leverage_held_by(who: StringName) -> Array[Secret]:
	var out: Array[Secret] = []
	for secret in secrets:
		if secret.is_known_to(who) and not secret.involves(who):
			out.append(secret)
	return out


## Records that someone has uncovered a secret.
##
## A shared secret exposes everyone in it at once — learning about the affair
## gives leverage over the Preacher *and* the Widow from one discovery.
func reveal_secret(secret: Secret, finder_id: StringName) -> bool:
	if secret == null or not secret.reveal_to(finder_id):
		return false
	EventBus.secret_uncovered.emit(finder_id, secret.content.subject_id, secret.content)
	return true


## Convenience for uncovering whatever `subject` is hiding. Returns the secret
## found, or null when they have nothing left to hide from this finder.
func reveal_secret_of(subject_id: StringName, finder_id: StringName) -> Secret:
	for secret in secrets_about(subject_id):
		if not secret.is_known_to(finder_id):
			reveal_secret(secret, finder_id)
			return secret
	return null


## Whether `actor_id` holds leverage over `subject_id`.
func knows_secret_of(actor_id: StringName, subject_id: StringName) -> bool:
	for secret in secrets_about(subject_id):
		if secret.is_known_to(actor_id) and not secret.involves(actor_id):
			return true
	return false


## Lovers meeting where nobody should see them.
##
## Affairs need somewhere to be. Because they break their own routine to get
## there, a player who watches the town can notice the Preacher leaving for the
## Woods at eleven at night twice a week — and that, rather than a menu, is how
## a hidden relationship is meant to be found.
const TRYST_ZONE := TownGrid.Zone.WOODS
const TRYST_HOUR := 23


func _tryst_pairs(day: int, hour: int) -> Array[Array]:
	if hour != TRYST_HOUR:
		return []

	var out: Array[Array] = []
	for pair in relations.hidden_pairs():
		# Twice a week, on days fixed per couple rather than at random, so the
		# pattern is learnable by watching.
		var offset: int = absi(str(pair[0]).hash()) % 3
		if (day + offset) % 3 != 0:
			continue
		out.append(pair)
	return out


## Anyone present at a tryst finds out, including the player.
func _resolve_trysts(day: int, hour: int) -> void:
	for pair in _tryst_pairs(day, hour):
		var lovers: Array[Agent] = []
		for member_id in pair:
			var lover: Agent = agent_by_id(member_id)
			if lover != null:
				lovers.append(lover)
		if lovers.size() < 2:
			continue

		for lover in lovers:
			lover.current_zone = TRYST_ZONE

		var affair: Secret = _affair_between(pair[0], pair[1])
		if affair == null:
			continue

		if player_zone == TRYST_ZONE:
			reveal_secret(affair, Agent.PLAYER_ID)

		for observer in agents_in_zone(TRYST_ZONE):
			if pair.has(observer.id):
				continue
			if reveal_secret(affair, observer.id):
				observer.learn(affair.content.duplicate_token())


func _affair_between(a: StringName, b: StringName) -> Secret:
	for secret in secrets:
		if secret.involves(a) and secret.involves(b):
			return secret
	return null


## Everyone walks to where they are supposed to be. Agents in a seeking state
## chase their target's current zone instead of their own schedule.
func _update_positions(hour: int) -> void:
	for agent in agents:
		var destination: int = agent.schedule.zone_at(hour)

		# A candidate abandons their trade to work the room with the most
		# voters in it. Both rivals happen to work the Market, so leaving them
		# on their schedules stranded them away from most of the electorate all
		# day and neither could ever contest the vote.
		if candidate_ids.has(agent.id):
			destination = _campaign_zone(hour)

		if agent.is_seeking():
			var target: Agent = agent_by_id(agent.seeking_target)
			if target == null:
				agent.stop_seeking()
			else:
				destination = target.current_zone
				# Reaching them ends the hunt; the conversation itself is
				# resolved below like any other co-located pair.
				if agent.current_zone == target.current_zone:
					agent.stop_seeking()
					agent.set_need(agent.dominant_need(), agent.need_of(agent.dominant_need()) - NEED_RELIEF)
					_deliver_report(agent, target)

		if agent.current_zone != destination:
			agent.current_zone = destination
			EventBus.npc_entered_zone.emit(agent.id, destination)


## Where the persuadable part of town will be at `hour`.
##
## Read from schedules rather than current positions so the answer does not
## depend on the order agents happen to be updated in.
func _campaign_zone(hour: int) -> int:
	var counts: Dictionary = {}
	for agent in agents:
		if candidate_ids.has(agent.id):
			continue
		var zone: int = agent.schedule.zone_at(hour)
		counts[zone] = counts.get(zone, 0) + 1

	var best: int = TownGrid.Zone.MARKET
	var best_count: int = -1
	# Iterate the enum, not the dictionary, so ties break deterministically.
	for zone in TownGrid.Zone.values():
		var count: int = counts.get(zone, 0)
		if count > best_count:
			best_count = count
			best = zone
	return best


## Hands over whatever an agent was rushing to say.
##
## This is how blackmail comes home to roost: the victim reaches the Sheriff,
## the Sheriff learns what was done, and it enters the gossip pipeline like any
## other firsthand knowledge.
func _deliver_report(reporter: Agent, listener: Agent) -> void:
	if reporter.pending_report == null:
		return

	var report: MemoryToken = reporter.pending_report
	reporter.pending_report = null
	listener.learn(report)

	# Anyone else standing there hears it too.
	for observer in agents_in_zone(listener.current_zone):
		if observer.id == listener.id or observer.id == reporter.id:
			continue
		observer.learn(report.duplicate_token())

	EventBus.incident_occurred.emit(report)


## Passive gossip. Every co-located pair rolls once; conversations are capped so
## a crowded tavern cannot stall the sim.
func _resolve_conversations(day: int) -> void:
	var by_zone: Dictionary = {}
	for agent in agents:
		if not by_zone.has(agent.current_zone):
			by_zone[agent.current_zone] = [] as Array[Agent]
		by_zone[agent.current_zone].append(agent)

	var exchanges: int = 0
	for zone in by_zone:
		var present: Array = by_zone[zone]
		for i in present.size():
			for j in range(i + 1, present.size()):
				if exchanges >= MAX_EXCHANGES_PER_HOUR:
					return
				var a: Agent = present[i]
				var b: Agent = present[j]
				if not GossipEngine.should_converse(a, b, rng):
					continue

				# Both parties speak. Who goes first is decided by the rng so the
				# array order of the roster does not bias who spreads rumours.
				var speaker: Agent = a if rng.chance(0.5) else b
				var listener: Agent = b if speaker == a else a
				if GossipEngine.exchange(speaker, listener, day, rng) != null:
					exchanges += 1
				if GossipEngine.exchange(listener, speaker, day, rng) != null:
					exchanges += 1


## Needs climb with neglect. Once one crosses the threshold, the agent abandons
## their routine to do something about it.
func _update_needs() -> void:
	for agent in agents:
		for need in Agent.Need.values():
			agent.raise_need(need, NEED_DRIFT)

		if agent.is_seeking() or not agent.has_urgent_need():
			continue

		var target: StringName = _seek_target_for(agent)
		if target != &"":
			agent.begin_seeking(target)


## Who an agent goes looking for when a need boils over.
##
## Safety sends them to the law. Belonging sends them to whoever they like most.
## Money and respect send them to the market's power broker.
func _seek_target_for(agent: Agent) -> StringName:
	match agent.dominant_need():
		Agent.Need.SAFETY:
			return protector_id if agent.id != protector_id else &""
		Agent.Need.BELONGING:
			return _most_liked(agent)
		Agent.Need.MONEY, Agent.Need.RESPECT:
			return broker_id if agent.id != broker_id else &""
		_:
			return &""


func _most_liked(agent: Agent) -> StringName:
	var best: StringName = &""
	var best_score: float = RelationshipBook.NEUTRAL
	for other in agents:
		if other.id == agent.id:
			continue
		var score: float = agent.relationships.score_for(other.id)
		if score > best_score:
			best_score = score
			best = other.id
	return best


## Everyone currently in `zone`. The player interaction UI reads this.
func agents_in_zone(zone: int) -> Array[Agent]:
	var out: Array[Agent] = []
	for agent in agents:
		if agent.current_zone == zone:
			out.append(agent)
	return out


## Injects a first-hand observation into one agent's ledger, e.g. the player
## bribed someone and this NPC saw it.
func witness(observer_id: StringName, token: MemoryToken) -> float:
	var observer: Agent = agent_by_id(observer_id)
	if observer == null:
		return 0.0
	return observer.learn(token)


## The endgame tally: who each inhabitant backs, and whether the player has a
## majority. See `Election` for the rules.
func tally_votes() -> Dictionary:
	var result: Dictionary = Election.tally(agents, candidate_ids)

	# Raw regard for the player, kept for the debug view and the balance tests.
	var breakdown: Dictionary = {}
	for agent in agents:
		breakdown[agent.id] = agent.opinion_of_player()
	result["breakdown"] = breakdown

	return result


## Inhabitants not currently backing the player, closest to flipping first.
func swing_voters() -> Array[Agent]:
	return Election.swing_candidates(agents, candidate_ids)


## Whether the player is close enough to `target` to say anything to them.
func player_can_reach(target: Agent) -> bool:
	return target != null and target.current_zone == player_zone


## Everyone standing with the player right now.
func agents_with_player() -> Array[Agent]:
	return agents_in_zone(player_zone)
