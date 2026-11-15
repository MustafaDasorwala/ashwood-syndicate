class_name IncidentEngine
extends RefCounted

## The town making its own trouble.
##
## Without this, the only events in Ashwood are the ones candidates cause. One
## rumour saturates ten people within a day, `select_token` then finds nothing
## new for any pair, and the remaining six days pass in total silence with
## opinions frozen — measured at 19 exchanges on Day 1 and zero thereafter.
##
## Incidents are the renewable source of information: feuds flare, debts get
## collected, secrets slip out. Each one becomes a token, enters the gossip
## pipeline, and gives the town something to talk about tomorrow.

## Chance per eligible pair, per hour, that a standing feud produces an incident.
const FEUD_CHANCE := 0.10

## Chance per hour that an agent with a boiling need acts on it badly.
##
## Deliberately rare. At 0.12 the Merchant committed roughly twenty public
## thefts a week and ended every playthrough at zero regard with the entire
## town — incidents are meant to keep the town talking, not to destroy the
## people they happen to.
const DESPERATION_CHANCE := 0.03

## Need level above which an agent will do something they would normally refuse.
const DESPERATION_THRESHOLD := 0.8

## How far acting on a need settles it. Large enough that one incident buys real
## quiet afterwards.
const DESPERATION_RELIEF := 0.6

## Chance per hour that someone in the room notices what another is hiding.
const SECRET_SLIP_CHANCE := 0.04


## Runs one hour of unprompted town life. Returns the tokens generated.
static func step(sim: TownSim, day: int) -> Array[MemoryToken]:
	var generated: Array[MemoryToken] = []

	for zone in TownGrid.Zone.values():
		var present: Array[Agent] = sim.agents_in_zone(zone)
		if present.size() < 2:
			continue

		generated.append_array(_feuds(sim, present, day))
		generated.append_array(_desperation(sim, present, day))
		generated.append_array(_slips(sim, present, day))

	return generated


## Rivals in the same room do not stay civil forever.
static func _feuds(sim: TownSim, present: Array[Agent], day: int) -> Array[MemoryToken]:
	var out: Array[MemoryToken] = []

	for i in present.size():
		for j in range(i + 1, present.size()):
			var a: Agent = present[i]
			var b: Agent = present[j]
			if not a.psyche.rivals.has(b.id) and not b.psyche.rivals.has(a.id):
				continue
			if not sim.rng.chance(FEUD_CHANCE):
				continue

			# The more ruthless of the two is the one who starts it.
			var aggressor: Agent = a if a.psyche.dark_factor() >= b.psyche.dark_factor() else b
			var victim: Agent = b if aggressor == a else a

			var action: StringName = ActionCatalog.THREATENED
			if aggressor.psyche.dark_of(Psyche.Dark.MACHIAVELLIANISM) > 0.6:
				action = ActionCatalog.LIED_TO

			out.append(_publish(aggressor.id, action, victim.id, 5, present, day))

	return out


## Someone whose need has boiled over does something they will regret.
static func _desperation(sim: TownSim, present: Array[Agent], day: int) -> Array[MemoryToken]:
	var out: Array[MemoryToken] = []

	for agent in present:
		if agent.need_of(agent.dominant_need()) < DESPERATION_THRESHOLD:
			continue
		if not sim.rng.chance(DESPERATION_CHANCE * (0.4 + agent.psyche.dark_factor())):
			continue

		var victim: Variant = sim.rng.pick(present.filter(func(o: Agent) -> bool: return o.id != agent.id))
		if victim == null:
			continue

		var action: StringName = ActionCatalog.STOLE_FROM
		match agent.dominant_need():
			Agent.Need.RESPECT:
				action = ActionCatalog.THREATENED
			Agent.Need.BELONGING:
				action = ActionCatalog.LIED_TO
			_:
				action = ActionCatalog.STOLE_FROM

		# Acting on it relieves the pressure, win or lose.
		agent.set_need(agent.dominant_need(), agent.need_of(agent.dominant_need()) - DESPERATION_RELIEF)
		out.append(_publish(agent.id, action, (victim as Agent).id, 6, present, day))

	return out


## A secret slips in company. This is how leverage reaches the town without the
## player having to be present for everything.
static func _slips(sim: TownSim, present: Array[Agent], day: int) -> Array[MemoryToken]:
	var out: Array[MemoryToken] = []

	for agent in present:
		var carried: Array[Secret] = sim.secrets_about(agent.id)
		if carried.is_empty():
			continue
		# The guarded and the sober keep their mouths shut; the loud do not.
		var looseness: float = agent.psyche.trait_of(Psyche.Trait.EXTRAVERSION)
		if not sim.rng.chance(SECRET_SLIP_CHANCE * looseness):
			continue

		var slipped: Variant = sim.rng.pick(carried)
		if slipped == null:
			continue
		var secret: Secret = slipped

		var leaked: bool = false
		for observer in present:
			if secret.involves(observer.id):
				continue
			if sim.reveal_secret(secret, observer.id):
				observer.learn(secret.content.duplicate_token())
				leaked = true

		if leaked:
			EventBus.incident_occurred.emit(secret.content)
			out.append(secret.content)

	return out


## Files an incident as firsthand knowledge for everyone in the room.
static func _publish(
	subject_id: StringName,
	action: StringName,
	target_id: StringName,
	severity: int,
	present: Array[Agent],
	day: int
) -> MemoryToken:
	var token := MemoryToken.new(subject_id, action, target_id, true, severity, &"", day)

	for observer in present:
		# The subject knows what they did; the victim certainly does.
		observer.learn(token.duplicate_token())

	# People elsewhere in town have not seen it — it reaches them, if at all,
	# through the gossip engine like anything else.
	EventBus.incident_occurred.emit(token)
	return token
