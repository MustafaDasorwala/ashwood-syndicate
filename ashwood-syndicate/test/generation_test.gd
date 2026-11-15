## Procedural towns: a different cast every seed, and every one of them playable.
##
## The fitness check is the point of this file. Random webs reliably produce
## towns that fail quietly rather than crash — somebody with no lever, no route
## to the election, a stranded inhabitant nobody can talk about.
extends GdUnitTestSuite

const SEEDS := [1, 7, 42, 99, 4242, 31337, 555, 8080]


func before_test() -> void:
	GameClock.time_scale = 0.0
	GameClock.reset()


func after_test() -> void:
	GameClock.reset()
	GameClock.time_scale = 1.0


func _generated(seed_value: int) -> TownSim:
	var sim: TownSim = auto_free(TownSim.new())
	sim.setup_generated(seed_value)
	return sim


func _touches(sim: TownSim, who: StringName) -> bool:
	return not sim.secrets_about(who).is_empty()


# --- it produces a town at all ---------------------------------------------

func test_every_seed_yields_a_full_town() -> void:
	for seed_value in SEEDS:
		var blueprint: TownBlueprint = TownGenerator.generate(seed_value)
		assert_int(blueprint.agents.size()).override_failure_message(
			"seed %d produced %d people" % [seed_value, blueprint.agents.size()]
		).is_equal(TownGenerator.TOWN_SIZE)


func test_every_seed_passes_its_own_fitness_check() -> void:
	# A town that fails is thrown away, so a shipped one must be clean. If this
	# fails, generation is exhausting its attempts and returning a bad town.
	for seed_value in SEEDS:
		var blueprint: TownBlueprint = TownGenerator.generate(seed_value)
		assert_str(TownGenerator._assess(blueprint)).override_failure_message(
			"seed %d shipped an unplayable town: %s" % [seed_value, TownGenerator._assess(blueprint)]
		).is_empty()


func test_nobody_is_duplicated() -> void:
	for seed_value in SEEDS:
		var seen: Dictionary = {}
		for agent in TownGenerator.generate(seed_value).agents:
			assert_bool(seen.has(agent.id)).is_false()
			seen[agent.id] = true


func test_everyone_has_a_name_of_their_own() -> void:
	for seed_value in SEEDS:
		var names: Dictionary = {}
		for agent in TownGenerator.generate(seed_value).agents:
			assert_str(agent.display_name).is_not_empty()
			assert_bool(names.has(agent.display_name)).override_failure_message(
				"two people called %s" % agent.display_name
			).is_false()
			names[agent.display_name] = true


# --- towns actually differ -------------------------------------------------

func test_different_seeds_produce_different_towns() -> void:
	var fingerprints: Dictionary = {}
	for seed_value in SEEDS:
		var parts: Array[String] = []
		for agent in TownGenerator.generate(seed_value).agents:
			parts.append(agent.display_name)
		fingerprints["|".join(parts)] = true

	assert_int(fingerprints.size()).override_failure_message(
		"every seed produced the same cast"
	).is_greater(SEEDS.size() / 2)


func test_the_same_seed_produces_the_same_town() -> void:
	for seed_value in [7, 4242]:
		var first: TownBlueprint = TownGenerator.generate(seed_value)
		var second: TownBlueprint = TownGenerator.generate(seed_value)

		assert_array(first.agent_ids()).is_equal(second.agent_ids())
		assert_int(first.relations.size()).is_equal(second.relations.size())
		assert_int(first.secrets.size()).is_equal(second.secrets.size())
		for i in first.agents.size():
			assert_str(first.agents[i].display_name).is_equal(second.agents[i].display_name)


func test_personalities_vary_between_towns() -> void:
	# Same archetype, different person. Otherwise the cast is a fixed list with
	# the names swapped.
	var readings: Dictionary = {}
	for seed_value in SEEDS:
		for agent in TownGenerator.generate(seed_value).agents:
			if agent.id == &"merchant":
				readings["%.3f" % agent.psyche.trait_of(Psyche.Trait.EXTRAVERSION)] = true
	assert_int(readings.size()).is_greater(1)


func test_who_runs_for_leadership_varies() -> void:
	var line_ups: Dictionary = {}
	for seed_value in SEEDS:
		line_ups[str(TownGenerator.generate(seed_value).candidate_ids)] = true
	assert_int(line_ups.size()).is_greater(1)


# --- the fitness guarantees ------------------------------------------------

func test_nobody_is_stranded_in_any_town() -> void:
	for seed_value in SEEDS:
		var sim := _generated(seed_value)
		for agent in sim.agents:
			assert_int(sim.relations.involvement_of(agent.id)).override_failure_message(
				"seed %d left %s tied to nobody" % [seed_value, agent.id]
			).is_greater(0)


func test_everyone_has_a_lever_against_them() -> void:
	for seed_value in SEEDS:
		var sim := _generated(seed_value)
		for agent in sim.agents:
			assert_bool(_touches(sim, agent.id)).override_failure_message(
				"seed %d left %s with nothing to hide" % [seed_value, agent.id]
			).is_true()


func test_every_town_has_a_hidden_relationship_to_discover() -> void:
	for seed_value in SEEDS:
		assert_array(_generated(seed_value).relations.hidden_pairs()).override_failure_message(
			"seed %d has no affair, so the observation mechanic is dead" % seed_value
		).is_not_empty()


func test_leverage_can_always_reach_the_election() -> void:
	for seed_value in SEEDS:
		var sim := _generated(seed_value)
		var reachable: bool = false
		for candidate_id in sim.candidate_ids:
			if candidate_id != Agent.PLAYER_ID and _touches(sim, candidate_id):
				reachable = true
		assert_bool(reachable).override_failure_message(
			"seed %d has no vulnerable candidate" % seed_value
		).is_true()


func test_every_town_has_a_shared_secret() -> void:
	for seed_value in SEEDS:
		var shared: int = 0
		for secret in _generated(seed_value).secrets:
			if secret.participants.size() > 1:
				shared += 1
		assert_int(shared).override_failure_message(
			"seed %d has no secret that ruins two people" % seed_value
		).is_greater(0)


func test_the_web_stays_sparse() -> void:
	for seed_value in SEEDS:
		var sim := _generated(seed_value)
		assert_int(sim.relations.size()).override_failure_message(
			"seed %d wove %d ties" % [seed_value, sim.relations.size()]
		).is_between(8, 24)


func test_an_unplayable_town_is_recognised_as_such() -> void:
	# The check must actually reject things, or it is decoration.
	var blueprint := TownBlueprint.new()
	assert_str(TownGenerator._assess(blueprint)).is_not_empty()


# --- generated towns run the whole simulation ------------------------------

func test_roles_are_resolved_without_hardcoded_names() -> void:
	# A generated town has no "sheriff", but seeking still needs somebody to run
	# to and somebody to owe.
	for seed_value in SEEDS:
		var sim := _generated(seed_value)
		assert_str(str(sim.protector_id)).is_not_empty()
		assert_str(str(sim.broker_id)).is_not_empty()
		assert_object(sim.agent_by_id(sim.protector_id)).is_not_null()
		assert_object(sim.agent_by_id(sim.broker_id)).is_not_null()


func test_ashwood_still_resolves_to_its_own_sheriff_and_merchant() -> void:
	var sim: TownSim = auto_free(TownSim.new())
	sim.setup(20260730)
	assert_str(str(sim.protector_id)).is_equal(str(Roster.SHERIFF))
	assert_str(str(sim.broker_id)).is_equal(str(Roster.MERCHANT))


func test_a_generated_town_survives_a_full_week() -> void:
	for seed_value in [7, 4242]:
		var sim := _generated(seed_value)
		for h in GameClock.TOTAL_DAYS * GameClock.HOURS_PER_DAY:
			sim.step_hour(h / GameClock.HOURS_PER_DAY, h % GameClock.HOURS_PER_DAY)

		for agent in sim.agents:
			assert_int(agent.ledger.size()).is_less_equal(MemoryLedger.CAPACITY)
			for other_id in agent.relationships.known_ids():
				assert_float(agent.relationships.score_for(other_id)).is_between(
					RelationshipBook.MIN_SCORE, RelationshipBook.MAX_SCORE
				)


func test_a_generated_town_holds_an_election() -> void:
	var sim := _generated(4242)
	var tally: Dictionary = sim.tally_votes()
	assert_int(tally["total"]).is_equal(TownGenerator.TOWN_SIZE)
	assert_int(tally["required"]).is_equal(6)
	assert_bool(tally["counts"].has(Agent.PLAYER_ID)).is_true()


func test_conversation_works_in_a_generated_town() -> void:
	# The dialogue prompt reads ties and secrets, so a generated cast has to
	# produce a usable character sheet too.
	var sim := _generated(99)
	var someone: Agent = sim.agents[0]
	var request: Dictionary = PromptBuilder.build(someone, sim, "guarded")

	assert_str(request["system"]).contains(someone.display_name)
	assert_str(request["system"]).contains("WHAT YOU HIDE")
	assert_int(str(request["system"]).length()).is_less(2200)
