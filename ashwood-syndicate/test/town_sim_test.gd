## The whole town, run headless for a full seven days.
##
## This is the test the frame-coupled clock design made impossible: an entire
## playthrough resolves in milliseconds, so emergent properties — does gossip
## actually spread? does the same seed replay identically? — become assertions
## rather than things you hope hold after 168 minutes of watching.
extends GdUnitTestSuite

const _Z := TownGrid.Zone
const HOURS_IN_WEEK := GameClock.TOTAL_DAYS * GameClock.HOURS_PER_DAY


func before_test() -> void:
	GameClock.time_scale = 0.0
	GameClock.reset()


func after_test() -> void:
	GameClock.reset()
	GameClock.time_scale = 1.0


## A sim that is NOT connected to the clock, so tests drive it explicitly.
func _sim(seed_value: int = 1) -> TownSim:
	var sim: TownSim = auto_free(TownSim.new())
	sim.setup(seed_value)
	return sim


func _run_week(sim: TownSim) -> void:
	for hour_index in HOURS_IN_WEEK:
		sim.step_hour(hour_index / GameClock.HOURS_PER_DAY, hour_index % GameClock.HOURS_PER_DAY)


func _scandal(severity: int = 8) -> MemoryToken:
	return MemoryToken.new(
		Agent.PLAYER_ID, ActionCatalog.BRIBED, Roster.BLACKSMITH, true, severity, &"", 0
	)


# --- roster ----------------------------------------------------------------

func test_the_town_has_ten_inhabitants() -> void:
	assert_int(_sim().agents.size()).is_equal(10)


func test_every_inhabitant_has_a_distinct_id() -> void:
	var seen := {}
	for agent in _sim().agents:
		assert_bool(seen.has(agent.id)).override_failure_message(
			"duplicate id %s" % agent.id
		).is_false()
		seen[agent.id] = true


func test_inhabitants_are_reachable_by_id() -> void:
	var sim := _sim()
	assert_object(sim.agent_by_id(Roster.SHERIFF)).is_not_null()
	assert_object(sim.agent_by_id(&"nobody")).is_null()


func test_everyone_starts_indifferent_to_the_player() -> void:
	for agent in _sim().agents:
		assert_float(agent.opinion_of_player()).is_equal(RelationshipBook.NEUTRAL)


# --- movement --------------------------------------------------------------

func test_inhabitants_follow_their_schedule() -> void:
	# Candidates excepted — they abandon their trade to work the room with the
	# most voters in it.
	var sim := _sim()
	sim.step_hour(0, 9)
	for agent in sim.agents:
		if sim.candidate_ids.has(agent.id):
			continue
		assert_int(agent.current_zone).is_equal(agent.schedule.zone_at(9))


func test_candidates_go_where_the_voters_are() -> void:
	var sim := _sim()
	sim.step_hour(0, 9)

	var mayor: Agent = sim.agent_by_id(Roster.MAYOR)
	var crowd: int = sim.agents_in_zone(mayor.current_zone).size()
	for zone in TownGrid.Zone.values():
		assert_int(sim.agents_in_zone(zone).size()).is_less_equal(crowd)


func test_the_town_gathers_at_the_tavern_in_the_evening() -> void:
	var sim := _sim()
	sim.step_hour(0, 20)
	assert_int(sim.agents_in_zone(_Z.TAVERN).size()).is_greater(5)


func test_the_town_goes_home_at_night() -> void:
	var sim := _sim()
	sim.step_hour(0, 23)
	assert_int(sim.agents_in_zone(_Z.RESIDENCES).size()).is_equal(sim.agents.size())


# --- gossip propagation ----------------------------------------------------

func test_a_witnessed_scandal_changes_the_witness_opinion() -> void:
	var sim := _sim()
	var delta: float = sim.witness(Roster.SHERIFF, _scandal())
	assert_float(delta).is_less(0.0)
	assert_float(sim.agent_by_id(Roster.SHERIFF).opinion_of_player()).is_less(RelationshipBook.NEUTRAL)


func test_a_scandal_spreads_beyond_the_witness_over_a_week() -> void:
	var sim := _sim()
	sim.witness(Roster.DRUNKARD, _scandal())  # the loudest man in town
	_run_week(sim)

	var knowers: int = 0
	for agent in sim.agents:
		if not agent.ledger.about(Agent.PLAYER_ID).is_empty():
			knowers += 1

	assert_int(knowers).override_failure_message(
		"only %d of %d inhabitants ever heard the rumour" % [knowers, sim.agents.size()]
	).is_greater(1)


func test_the_fairness_zealot_and_the_corrupt_merchant_react_differently() -> void:
	# The design's central claim: identical information, opposite conclusions.
	var sim := _sim()
	sim.witness(Roster.SHERIFF, _scandal())
	sim.witness(Roster.MERCHANT, _scandal())

	var sheriff_opinion: float = sim.agent_by_id(Roster.SHERIFF).opinion_of_player()
	var merchant_opinion: float = sim.agent_by_id(Roster.MERCHANT).opinion_of_player()

	assert_float(sheriff_opinion).is_less(merchant_opinion)


func test_relationships_stay_within_bounds_across_a_full_week() -> void:
	var sim := _sim()
	sim.witness(Roster.DRUNKARD, _scandal(10))
	sim.witness(Roster.PREACHER, MemoryToken.new(
		Agent.PLAYER_ID, ActionCatalog.DESECRATED, Roster.PREACHER, true, 9, &"", 0
	))
	_run_week(sim)

	for agent in sim.agents:
		for other_id in agent.relationships.known_ids():
			var score: float = agent.relationships.score_for(other_id)
			assert_float(score).is_between(RelationshipBook.MIN_SCORE, RelationshipBook.MAX_SCORE)


func test_ledgers_stay_bounded_across_a_full_week() -> void:
	var sim := _sim()
	for i in 20:
		sim.witness(Roster.DRUNKARD, MemoryToken.new(
			Agent.PLAYER_ID, StringName("deed_%d" % i), Roster.WIDOW, true, 5 + i % 5, &"", 0
		))
	_run_week(sim)

	for agent in sim.agents:
		assert_int(agent.ledger.size()).is_less_equal(MemoryLedger.CAPACITY)


func test_a_quiet_week_leaves_opinions_untouched() -> void:
	# With nothing to talk about, the town cannot invent scandal on its own.
	var sim := _sim()
	_run_week(sim)
	for agent in sim.agents:
		assert_float(agent.opinion_of_player()).is_equal(RelationshipBook.NEUTRAL)


# --- determinism -----------------------------------------------------------

func test_the_same_seed_replays_identically() -> void:
	var first := _sim(1234)
	var second := _sim(1234)
	first.witness(Roster.DRUNKARD, _scandal())
	second.witness(Roster.DRUNKARD, _scandal())
	_run_week(first)
	_run_week(second)

	for i in first.agents.size():
		assert_float(first.agents[i].opinion_of_player()).override_failure_message(
			"agent %s diverged between identical seeds" % first.agents[i].id
		).is_equal(second.agents[i].opinion_of_player())


func test_different_seeds_produce_different_towns() -> void:
	# Rumour routing must actually depend on chance, or every playthrough is
	# the same playthrough.
	var outcomes := {}
	for seed_value in [1, 7, 99, 4242]:
		var sim := _sim(seed_value)
		sim.witness(Roster.DRUNKARD, _scandal())
		_run_week(sim)
		var fingerprint: Array = []
		for agent in sim.agents:
			fingerprint.append(roundi(agent.opinion_of_player()))
		outcomes[str(fingerprint)] = true

	assert_int(outcomes.size()).is_greater(1)


# --- the vote --------------------------------------------------------------

func test_an_indifferent_town_elects_nobody() -> void:
	var tally: Dictionary = _sim().tally_votes()
	assert_int(tally["votes_for"]).is_equal(0)
	assert_bool(tally["won"]).is_false()
	assert_int(tally["required"]).is_equal(6)


## The non-candidates, who are the only votes actually in play.
func _electorate(sim: TownSim) -> Array[Agent]:
	var out: Array[Agent] = []
	for agent in sim.agents:
		if not sim.candidate_ids.has(agent.id):
			out.append(agent)
	return out


func test_winning_needs_six_of_ten() -> void:
	var sim := _sim()
	var electorate: Array[Agent] = _electorate(sim)

	for i in 5:
		electorate[i].relationships.set_score(Agent.PLAYER_ID, 90.0)
	assert_bool(sim.tally_votes()["won"]).is_false()

	electorate[5].relationships.set_score(Agent.PLAYER_ID, 90.0)
	assert_bool(sim.tally_votes()["won"]).is_true()


func test_rivals_vote_for_themselves() -> void:
	# Which is why six of ten means six of the eight actually persuadable.
	var sim := _sim()
	var ballots: Dictionary = sim.tally_votes()["ballots"]
	for candidate_id in sim.candidate_ids:
		if candidate_id == Agent.PLAYER_ID:
			continue
		assert_str(str(ballots[candidate_id])).is_equal(str(candidate_id))


func test_lukewarm_regard_is_an_abstention_not_a_vote() -> void:
	var sim := _sim()
	for agent in _electorate(sim):
		agent.relationships.set_score(Agent.PLAYER_ID, Election.MIN_SUPPORT)
	assert_int(sim.tally_votes()["votes_for"]).is_equal(0)


func test_the_tally_reports_every_inhabitant() -> void:
	var sim := _sim()
	var breakdown: Dictionary = sim.tally_votes()["breakdown"]
	assert_int(breakdown.size()).is_equal(sim.agents.size())


func test_a_late_rumour_can_flip_a_secured_vote() -> void:
	# The GDD's Day 7 reversal: a promised vote is never guaranteed.
	var sim := _sim()
	var blacksmith: Agent = sim.agent_by_id(Roster.BLACKSMITH)
	blacksmith.relationships.set_score(Agent.PLAYER_ID, 80.0)
	assert_bool(blacksmith.relationships.would_vote_for(Agent.PLAYER_ID)).is_true()

	blacksmith.learn(MemoryToken.new(
		Agent.PLAYER_ID, ActionCatalog.THREATENED, Roster.WIDOW, true, 9, &"", 6
	))

	assert_bool(blacksmith.relationships.would_vote_for(Agent.PLAYER_ID)).override_failure_message(
		"threatening the one person he is loyal to did not cost the vote"
	).is_false()


# --- needs and seeking -----------------------------------------------------

func test_an_urgent_need_overrides_the_daily_routine() -> void:
	var sim := _sim()
	var miller: Agent = sim.agent_by_id(Roster.MILLER)
	miller.set_need(Agent.Need.SAFETY, 1.0)

	sim.step_hour(0, 9)

	assert_bool(miller.is_seeking()).is_true()
	assert_str(str(miller.seeking_target)).is_equal(str(Roster.SHERIFF))


func test_reaching_the_target_ends_the_hunt_and_relieves_the_need() -> void:
	var sim := _sim()
	var miller: Agent = sim.agent_by_id(Roster.MILLER)
	miller.set_need(Agent.Need.SAFETY, 1.0)

	sim.step_hour(0, 9)   # starts seeking the sheriff
	sim.step_hour(0, 10)  # walks to wherever the sheriff is
	sim.step_hour(0, 11)  # arrives

	assert_bool(miller.is_seeking()).is_false()
	assert_float(miller.need_of(Agent.Need.SAFETY)).is_less(Agent.SEEK_THRESHOLD)


func test_nobody_hunts_themselves() -> void:
	var sim := _sim()
	var sheriff: Agent = sim.agent_by_id(Roster.SHERIFF)
	sheriff.set_need(Agent.Need.SAFETY, 1.0)
	sim.step_hour(0, 9)
	assert_str(str(sheriff.seeking_target)).is_not_equal(str(Roster.SHERIFF))


func test_the_sim_runs_a_full_week_without_erroring() -> void:
	var sim := _sim()
	sim.witness(Roster.DRUNKARD, _scandal())
	_run_week(sim)
	assert_int(sim.agents.size()).is_equal(10)
