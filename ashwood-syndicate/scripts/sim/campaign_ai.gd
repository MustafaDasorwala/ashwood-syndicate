class_name CampaignAi
extends RefCounted

## Rival candidates working the town.
##
## They use the player's exact code path — same approaches, same witness leak,
## same diminishing returns — so nothing they do is unavailable to you, and
## anything you learn about the system applies to reading them.
##
## Their choice of approach comes from their psychology, not from a difficulty
## setting. The Merchant buys people because he is Machiavellian; the Mayor
## flatters because he is a narcissist who assumes everyone else is too.

## In-game hours between one rival's approaches.
##
## Matched to the player's own once-per-hour limit. Anything slower and they are
## not really contesting the election: at one approach every three hours they
## lost every measured playthrough while the player simply out-worked them.
const CAMPAIGN_INTERVAL := 1

## Ignore anyone already this far ahead for us — effort is better spent on the
## undecided than on the already-committed.
const SECURE_ENOUGH := 88.0


## Runs one hour of rival campaigning.
##
## Returns the reports of whatever was attempted, for the log.
static func step(sim: TownSim, hour_index: int, day: int) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []

	for candidate_id in sim.candidate_ids:
		if candidate_id == Agent.PLAYER_ID:
			continue

		var rival: Agent = sim.agent_by_id(candidate_id)
		if rival == null:
			continue

		# Stagger rivals so they do not all act on the same hour.
		var offset: int = absi(str(candidate_id).hash()) % CAMPAIGN_INTERVAL
		if (hour_index + offset) % CAMPAIGN_INTERVAL != 0:
			continue

		var target: Agent = _choose_target(sim, rival)
		if target == null:
			continue

		var report: Dictionary = PlayerActions.perform(
			_choose_approach(sim, rival, target), target, sim, day, rival.id
		)
		if report["ok"]:
			reports.append(report)

	return reports


## Who this rival works on: whoever in the room they are closest to taking.
##
## Measured as the deficit to whichever candidate that voter currently favours
## most. Working on the narrowest deficit first is how a campaign actually
## allocates effort.
##
## An earlier heuristic scored targets by closeness to the minimum-support line,
## which meant a rival abandoned anyone the player had already pushed high —
## precisely the voters being taken from them. They won no votes at all in eight
## measured playthroughs.
static func _choose_target(sim: TownSim, rival: Agent) -> Agent:
	var best: Agent = null
	var smallest_deficit: float = INF

	for other in sim.agents_in_zone(rival.current_zone):
		if other.id == rival.id or sim.candidate_ids.has(other.id):
			continue

		var mine: float = other.relationships.score_for(rival.id)
		if mine >= SECURE_ENOUGH:
			continue

		var leader: float = -INF
		for candidate_id in sim.candidate_ids:
			if candidate_id == rival.id:
				continue
			leader = maxf(leader, other.relationships.score_for(candidate_id))

		# Negative deficit means they are already ahead here; still worth
		# shoring up, but behind anyone genuinely contested.
		var deficit: float = leader - mine
		if deficit < smallest_deficit:
			smallest_deficit = deficit
			best = other

	return best


## Approaches a rival will consider. Probing and blackmail are the player's
## alone for now — rivals compete on persuasion, not on leverage.
const CONSIDERED: Array[PlayerActions.Kind] = [
	PlayerActions.Kind.BRIBE,
	PlayerActions.Kind.THREATEN,
	PlayerActions.Kind.HELP,
	PlayerActions.Kind.FLATTER,
]


## Which approach this rival takes, given who they are working on.
##
## They actually model the target: each option is scored with the same
## `GossipEngine.evaluate` the target will use, then adjusted by how willing
## this particular rival is to use that method at all.
##
## An earlier version picked purely from the rival's own character — the Mayor
## flattered everyone because he is vain, the Merchant bribed moralists because
## he is corrupt. Both spent the whole week losing support, and neither was ever
## a threat.
static func _choose_approach(sim: TownSim, rival: Agent, target: Agent) -> PlayerActions.Kind:
	var room: Array[Agent] = sim.agents_in_zone(target.current_zone)

	var best: PlayerActions.Kind = PlayerActions.Kind.HELP
	var best_score: float = -INF

	for kind in CONSIDERED:
		var definition: Dictionary = PlayerActions.DEFINITIONS[kind]
		var token := MemoryToken.new(
			rival.id, definition["action"], target.id, true, definition["severity"], &"", 0
		)

		var score: float = GossipEngine.evaluate(token, target) + _willingness(rival, kind)

		# Count the room. Ignoring witnesses made the Merchant bribe people in
		# front of the whole town and sink to zero regard with everyone by
		# midweek — he was never a threat, he was a cautionary tale.
		for observer in room:
			if observer.id == target.id or observer.id == rival.id:
				continue
			score += GossipEngine.evaluate(token, observer) * Agent.WITNESS_WEIGHT

		if score > best_score:
			best_score = score
			best = kind

	return best


## How readily this rival reaches for a given method, independent of whether it
## would work. Keeps them in character: the honest do not buy people, and the
## vain over-rate flattery even when it is not their best option.
static func _willingness(rival: Agent, kind: PlayerActions.Kind) -> float:
	var psyche: Psyche = rival.psyche
	# Deliberately small next to the expected-outcome maths above: character
	# should tilt the choice, not override a plainly self-destructive one.
	match kind:
		PlayerActions.Kind.BRIBE:
			return (psyche.dark_of(Psyche.Dark.MACHIAVELLIANISM) - 0.5) * 8.0
		PlayerActions.Kind.THREATEN:
			return (psyche.dark_of(Psyche.Dark.PSYCHOPATHY) - 0.5) * 8.0
		PlayerActions.Kind.FLATTER:
			return psyche.dark_of(Psyche.Dark.NARCISSISM) * 3.0
		_:
			return psyche.trait_of(Psyche.Trait.AGREEABLENESS) * 2.0
