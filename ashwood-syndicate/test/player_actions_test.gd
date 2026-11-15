## Player approaches, and the witness leak that makes them risky.
extends GdUnitTestSuite

const _Z := TownGrid.Zone


func before_test() -> void:
	GameClock.time_scale = 0.0
	GameClock.reset()


func after_test() -> void:
	GameClock.reset()
	GameClock.time_scale = 1.0


func _sim() -> TownSim:
	var sim: TownSim = auto_free(TownSim.new())
	sim.setup(1)
	return sim


## Puts everyone somewhere private so a test can control exactly who is watching.
## The player is placed in the tavern, which the scattered cast leaves empty.
func _isolate(sim: TownSim) -> void:
	for i in sim.agents.size():
		sim.agents[i].current_zone = _Z.WOODS if i % 2 == 0 else _Z.RESIDENCES
	sim.player_zone = _Z.TAVERN


## Gets `agent` on their own with the player, with nobody else in earshot.
func _alone(sim: TownSim, agent: Agent) -> void:
	for other in sim.agents:
		other.current_zone = _Z.RESIDENCES
	agent.current_zone = _Z.WOODS
	sim.player_zone = _Z.WOODS


## Puts the player and everyone named into `zone`, leaving the rest elsewhere.
func _gather(sim: TownSim, zone: int, ids: Array) -> void:
	_isolate(sim)
	for id in ids:
		sim.agent_by_id(id).current_zone = zone
	sim.player_zone = zone


# --- basics ----------------------------------------------------------------

func test_every_approach_is_defined() -> void:
	for kind in PlayerActions.Kind.values():
		assert_bool(PlayerActions.DEFINITIONS.has(kind)).is_true()
		assert_str(PlayerActions.label_for(kind)).is_not_empty()
		assert_str(PlayerActions.hint_for(kind)).is_not_empty()


func test_acting_on_nobody_fails_cleanly() -> void:
	var report: Dictionary = PlayerActions.perform(PlayerActions.Kind.HELP, null, _sim(), 0)
	assert_bool(report["ok"]).is_false()


func test_helping_someone_improves_their_opinion() -> void:
	var sim := _sim()
	var healer: Agent = sim.agent_by_id(Roster.HEALER)
	_alone(sim, healer)

	var report: Dictionary = PlayerActions.perform(PlayerActions.Kind.HELP, healer, sim, 0)

	assert_bool(report["ok"]).is_true()
	assert_float(report["target_delta"]).is_greater(0.0)
	assert_float(healer.opinion_of_player()).is_greater(RelationshipBook.NEUTRAL)


func test_threatening_the_sheriff_costs_you() -> void:
	var sim := _sim()
	var sheriff: Agent = sim.agent_by_id(Roster.SHERIFF)
	_alone(sim, sheriff)

	PlayerActions.perform(PlayerActions.Kind.THREATEN, sheriff, sim, 0)
	assert_float(sheriff.opinion_of_player()).is_less(RelationshipBook.NEUTRAL)


func test_the_same_bribe_wins_the_merchant_and_loses_the_sheriff() -> void:
	# The whole design in one assertion: identical act, opposite outcomes.
	var sim := _sim()
	var merchant: Agent = sim.agent_by_id(Roster.MERCHANT)
	var sheriff: Agent = sim.agent_by_id(Roster.SHERIFF)

	_alone(sim, merchant)
	PlayerActions.perform(PlayerActions.Kind.BRIBE, merchant, sim, 0)
	_alone(sim, sheriff)
	PlayerActions.perform(PlayerActions.Kind.BRIBE, sheriff, sim, 0)

	assert_float(merchant.opinion_of_player()).is_greater(sheriff.opinion_of_player())


# --- the witness leak ------------------------------------------------------

func test_an_approach_in_an_empty_room_has_no_witnesses() -> void:
	var sim := _sim()
	var merchant: Agent = sim.agent_by_id(Roster.MERCHANT)
	_alone(sim, merchant)

	var report: Dictionary = PlayerActions.perform(PlayerActions.Kind.BRIBE, merchant, sim, 0)
	assert_array(report["witnesses"]).is_empty()


func test_bystanders_form_their_own_opinion() -> void:
	var sim := _sim()
	var merchant: Agent = sim.agent_by_id(Roster.MERCHANT)
	var sheriff: Agent = sim.agent_by_id(Roster.SHERIFF)
	_gather(sim, _Z.TAVERN, [Roster.MERCHANT, Roster.SHERIFF])

	var report: Dictionary = PlayerActions.perform(PlayerActions.Kind.BRIBE, merchant, sim, 0)

	assert_array(report["witnesses"]).contains([Roster.SHERIFF])
	assert_float(sheriff.opinion_of_player()).is_less(RelationshipBook.NEUTRAL)


func test_a_bribe_can_win_the_target_and_still_cost_you_the_room() -> void:
	var sim := _sim()
	var merchant: Agent = sim.agent_by_id(Roster.MERCHANT)
	# Stack the room with the town's moralists.
	_gather(sim, _Z.TAVERN, [Roster.MERCHANT, Roster.SHERIFF, Roster.PREACHER, Roster.HEALER])

	var report: Dictionary = PlayerActions.perform(PlayerActions.Kind.BRIBE, merchant, sim, 0)

	assert_float(report["target_delta"]).is_greater(0.0)
	assert_float(report["witness_delta"]).is_less(0.0)
	assert_float(report["witness_delta"]).is_less(-report["target_delta"])


func test_helping_someone_publicly_plays_well_to_the_room() -> void:
	var sim := _sim()
	var widow: Agent = sim.agent_by_id(Roster.WIDOW)
	_gather(sim, _Z.MARKET, [Roster.WIDOW, Roster.HEALER, Roster.BLACKSMITH])

	var report: Dictionary = PlayerActions.perform(PlayerActions.Kind.HELP, widow, sim, 0)
	assert_float(report["witness_delta"]).is_greater(0.0)


func test_the_target_is_not_listed_as_their_own_witness() -> void:
	var sim := _sim()
	var merchant: Agent = sim.agent_by_id(Roster.MERCHANT)
	_gather(sim, _Z.TAVERN, [Roster.MERCHANT, Roster.SHERIFF])

	var report: Dictionary = PlayerActions.perform(PlayerActions.Kind.BRIBE, merchant, sim, 0)
	assert_array(report["witnesses"]).not_contains([Roster.MERCHANT])


# --- flattery and trauma ---------------------------------------------------

func test_flattery_wins_over_the_vain() -> void:
	var sim := _sim()
	var mayor: Agent = sim.agent_by_id(Roster.MAYOR)  # high Narcissism
	_alone(sim, mayor)

	PlayerActions.perform(PlayerActions.Kind.FLATTER, mayor, sim, 0)
	assert_float(mayor.opinion_of_player()).is_greater(RelationshipBook.NEUTRAL)


func test_flattery_backfires_on_the_miller() -> void:
	# Elias was ruined by a smooth talker. Flattery trips his trauma outright.
	var sim := _sim()
	var miller: Agent = sim.agent_by_id(Roster.MILLER)
	_alone(sim, miller)

	PlayerActions.perform(PlayerActions.Kind.FLATTER, miller, sim, 0)
	assert_float(miller.opinion_of_player()).is_less(RelationshipBook.NEUTRAL - 5.0)


func test_a_repeated_favour_still_counts_but_counts_for_less() -> void:
	var sim := _sim()
	var healer: Agent = sim.agent_by_id(Roster.HEALER)
	_alone(sim, healer)

	var first: Dictionary = PlayerActions.perform(PlayerActions.Kind.HELP, healer, sim, 0)
	var second: Dictionary = PlayerActions.perform(PlayerActions.Kind.HELP, healer, sim, 1)
	var third: Dictionary = PlayerActions.perform(PlayerActions.Kind.HELP, healer, sim, 2)

	assert_float(first["target_delta"]).is_greater(0.0)
	assert_float(second["target_delta"]).is_greater(0.0)
	assert_float(second["target_delta"]).is_less(first["target_delta"])
	assert_float(third["target_delta"]).is_less(second["target_delta"])


func test_a_witness_hearing_of_the_same_deed_twice_reacts_once() -> void:
	# Repeated deeds count; repeated *reports* of one deed must not.
	var sim := _sim()
	var merchant: Agent = sim.agent_by_id(Roster.MERCHANT)
	var sheriff: Agent = sim.agent_by_id(Roster.SHERIFF)
	_gather(sim, _Z.TAVERN, [Roster.MERCHANT, Roster.SHERIFF])

	var first: Dictionary = PlayerActions.perform(PlayerActions.Kind.BRIBE, merchant, sim, 0)
	var after_first: float = sheriff.opinion_of_player()
	var second: Dictionary = PlayerActions.perform(PlayerActions.Kind.BRIBE, merchant, sim, 1)

	assert_float(first["witness_delta"]).is_not_equal(0.0)
	assert_float(second["witness_delta"]).is_equal(0.0)
	assert_float(sheriff.opinion_of_player()).is_equal(after_first)


## Reads the target and picks the approach that suits them — bribe the venal,
## help the caring, flatter the vain, and never flatter a man whose trauma is
## flattery. This is what "playing well" means, as opposed to repeating one
## safe move; the balance guard below is about skill being rewarded, not about
## persistence being rewarded.
func _best_approach_for(target: Agent) -> PlayerActions.Kind:
	var best: PlayerActions.Kind = PlayerActions.Kind.HELP
	var best_score: float = -INF

	for kind in [PlayerActions.Kind.HELP, PlayerActions.Kind.FLATTER,
			PlayerActions.Kind.BRIBE, PlayerActions.Kind.THREATEN]:
		var definition: Dictionary = PlayerActions.DEFINITIONS[kind]
		var token := MemoryToken.new(
			Agent.PLAYER_ID, definition["action"], target.id, true,
			definition["severity"], &"", 0
		)
		var score: float = GossipEngine.evaluate(token, target)
		if score > best_score:
			best_score = score
			best = kind

	return best


func test_the_election_is_winnable_by_playing_well() -> void:
	# A balance guard, not a behaviour test. If diminishing returns or the swing
	# scale drift too far, six votes stop being reachable and the game is broken
	# in a way no unit test of an individual rule would catch.
	# One approach per hour over seven days is ~168 in total, so a dozen spent
	# on each inhabitant is a realistic budget rather than a generous one.
	const APPROACHES_PER_PERSON := 12

	var sim := _sim()

	# Playing well means both halves: build your own standing, and give people
	# reasons to think less of the rivals. Against a rival with warm opening
	# ties, persuasion alone has a ceiling and cannot catch them.
	for secret in sim.secrets:
		for candidate_id in sim.candidate_ids:
			if candidate_id != Agent.PLAYER_ID and secret.involves(candidate_id):
				sim.reveal_secret(secret, Agent.PLAYER_ID)

	for agent in sim.agents:
		# Court everyone privately, so no approach is spoiled by witnesses.
		_alone(sim, agent)
		for round_index in APPROACHES_PER_PERSON:
			PlayerActions.perform(_best_approach_for(agent), agent, sim, round_index)
		if not sim.candidate_ids.has(agent.id):
			PlayerActions.perform(PlayerActions.Kind.EXPOSE, agent, sim, APPROACHES_PER_PERSON)

	var tally: Dictionary = sim.tally_votes()
	assert_bool(tally["won"]).override_failure_message(
		"playing well secured only %d of %d votes: %s" % [
			tally["votes_for"], tally["total"], tally["breakdown"]
		]
	).is_true()


func test_an_approach_is_announced() -> void:
	var sim := _sim()
	var healer: Agent = sim.agent_by_id(Roster.HEALER)
	_alone(sim, healer)

	var seen: Array = []
	var handler := func(actor_id: StringName, kind: int, target_id: StringName, _d: float, _w: Array) -> void:
		seen.append([actor_id, kind, target_id])
	EventBus.approach_made.connect(handler)

	PlayerActions.perform(PlayerActions.Kind.HELP, healer, sim, 0)
	EventBus.approach_made.disconnect(handler)

	assert_int(seen.size()).is_equal(1)
	assert_str(str(seen[0][0])).is_equal(str(Agent.PLAYER_ID))
	assert_str(str(seen[0][2])).is_equal(str(Roster.HEALER))


func test_an_approach_can_be_enough_to_secure_a_vote() -> void:
	# Sanity check that the numbers are on a scale where the game is winnable.
	var sim := _sim()
	var healer: Agent = sim.agent_by_id(Roster.HEALER)
	_alone(sim, healer)
	healer.relationships.set_score(Agent.PLAYER_ID, 70.0)

	PlayerActions.perform(PlayerActions.Kind.HELP, healer, sim, 0)
	assert_bool(healer.relationships.would_vote_for(Agent.PLAYER_ID)).is_true()
