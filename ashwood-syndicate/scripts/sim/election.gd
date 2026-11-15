class_name Election
extends RefCounted

## Who the town actually votes for.
##
## The vote is *relative*, not a threshold. Each inhabitant backs whichever
## candidate they favour most — so winning is not about raising your own number,
## it is about being ahead of the rivals who are courting the same ten people.
##
## An absolute threshold made the game trivially grindable: help and flatter
## everyone often enough and six votes arrive with no opposition and no
## decisions. Opposition is what turns a number into a contest.

## Minimum regard before an inhabitant will back anyone at all. Below this they
## abstain rather than vote for the least bad option.
const MIN_SUPPORT := 58.0

## How far ahead a candidate must be before the voter commits. Inside this
## margin the inhabitant is genuinely torn and abstains.
const DECISIVE_MARGIN := 4.0

## Candidates vote for themselves, which is why the player must win a clear
## majority of the *remaining* town rather than a bare majority overall.
static func tally(agents: Array[Agent], candidate_ids: Array[StringName]) -> Dictionary:
	var counts: Dictionary = {}
	for candidate_id in candidate_ids:
		counts[candidate_id] = 0

	# agent id -> who they back, or &"" for an abstention.
	var ballots: Dictionary = {}
	# agent id -> { candidate id: regard }, for the UI.
	var regard: Dictionary = {}

	for agent in agents:
		if candidate_ids.has(agent.id):
			ballots[agent.id] = agent.id
			counts[agent.id] += 1
			regard[agent.id] = {agent.id: RelationshipBook.MAX_SCORE}
			continue

		var scores: Dictionary = {}
		var best: float = -INF
		var runner_up: float = -INF
		var choice: StringName = &""

		for candidate_id in candidate_ids:
			var score: float = agent.relationships.score_for(candidate_id)
			scores[candidate_id] = score
			if score > best:
				runner_up = best
				best = score
				choice = candidate_id
			elif score > runner_up:
				runner_up = score

		# Someone who regards two candidates equally has not been persuaded of
		# anything — they are torn, and they abstain. Without this, a voter maxed
		# out at 100 for everybody silently broke the tie by candidate order,
		# which handed the player every saturated vote in the town.
		if best <= MIN_SUPPORT or best - runner_up < DECISIVE_MARGIN:
			choice = &""

		regard[agent.id] = scores
		ballots[agent.id] = choice
		if choice != &"":
			counts[choice] += 1

	var required: int = int(floor(float(agents.size()) / 2.0)) + 1
	var leader: StringName = &""
	var leader_votes: int = -1
	for candidate_id in candidate_ids:
		if counts[candidate_id] > leader_votes:
			leader_votes = counts[candidate_id]
			leader = candidate_id

	var player_votes: int = counts.get(Agent.PLAYER_ID, 0)
	return {
		"counts": counts,
		"ballots": ballots,
		"regard": regard,
		"required": required,
		"leader": leader,
		"votes_for": player_votes,
		"total": agents.size(),
		"won": player_votes >= required,
	}


## How many more votes the player needs, and who is closest to switching.
##
## Drives the UI hint that stops the last two days being guesswork.
static func swing_candidates(agents: Array[Agent], candidate_ids: Array[StringName]) -> Array[Agent]:
	var result: Dictionary = tally(agents, candidate_ids)
	var ballots: Dictionary = result["ballots"]

	var swingable: Array[Agent] = []
	for agent in agents:
		if candidate_ids.has(agent.id):
			continue
		if ballots[agent.id] == Agent.PLAYER_ID:
			continue
		swingable.append(agent)

	# Closest to flipping first: highest current regard for the player.
	swingable.sort_custom(func(a: Agent, b: Agent) -> bool:
		return a.relationships.score_for(Agent.PLAYER_ID) > b.relationships.score_for(Agent.PLAYER_ID)
	)
	return swingable
