## The social web: typed ties, shared secrets, and lovers who have to meet
## somewhere.
extends GdUnitTestSuite

const _K := RelationGraph.Kind
const _Z := TownGrid.Zone


func before_test() -> void:
	GameClock.time_scale = 0.0
	GameClock.reset()


func after_test() -> void:
	GameClock.reset()
	GameClock.time_scale = 1.0


func _sim(seed_value: int = 20260730) -> TownSim:
	var sim: TownSim = auto_free(TownSim.new())
	sim.setup(seed_value)
	return sim


func _agent(id: StringName) -> Agent:
	return Agent.new(Psyche.new(id, str(id)))


# --- graph mechanics -------------------------------------------------------

func test_a_mutual_tie_is_felt_from_both_sides() -> void:
	var graph := RelationGraph.new().add(&"a", &"b", _K.KIN)
	assert_float(graph.attachment(&"a", &"b")).is_greater(0.0)
	assert_float(graph.attachment(&"b", &"a")).is_equal(graph.attachment(&"a", &"b"))


func test_a_one_way_tie_is_felt_from_one_side_only() -> void:
	# Bram loves the Widow. The Widow need not love Bram.
	var graph := RelationGraph.new().add(&"bram", &"widow", _K.UNREQUITED)
	assert_float(graph.attachment(&"bram", &"widow")).is_greater(0.0)
	assert_float(graph.attachment(&"widow", &"bram")).is_equal(0.0)


func test_a_debt_sours_the_debtor_not_the_holder() -> void:
	var graph := RelationGraph.new().add(&"sheriff", &"merchant", _K.DEBT)
	assert_float(graph.attachment(&"sheriff", &"merchant")).is_less(0.0)
	assert_float(graph.attachment(&"merchant", &"sheriff")).is_equal(0.0)


func test_ties_are_ranked_by_how_much_they_bind() -> void:
	var strength := RelationGraph.STRENGTH
	assert_float(strength[_K.KIN]).is_greater(strength[_K.FRIENDSHIP])
	assert_float(strength[_K.FRIENDSHIP]).is_greater(strength[_K.MENTOR])
	assert_float(strength[_K.RIVALRY]).is_less(strength[_K.ESTRANGED])


func test_strangers_are_unattached() -> void:
	var graph := RelationGraph.new().add(&"a", &"b", _K.KIN)
	assert_float(graph.attachment(&"a", &"stranger")).is_equal(0.0)


func test_the_strongest_tie_wins_when_several_exist() -> void:
	var graph := RelationGraph.new()
	graph.add(&"a", &"b", _K.MENTOR)
	graph.add(&"a", &"b", _K.KIN)
	assert_float(graph.attachment(&"a", &"b")).is_equal(RelationGraph.STRENGTH[_K.KIN])


func test_nobody_is_tied_to_themselves() -> void:
	var graph := RelationGraph.new().add(&"a", &"a", _K.KIN)
	assert_int(graph.size()).is_equal(0)


# --- the Ashwood web -------------------------------------------------------

func test_the_web_is_sparse() -> void:
	# Ten people fully connected would be forty-five edges of mush.
	var sim := _sim()
	assert_int(sim.relations.size()).is_between(10, 22)


func test_nobody_is_completely_unconnected() -> void:
	var sim := _sim()
	for agent in sim.agents:
		assert_int(sim.relations.involvement_of(agent.id)).override_failure_message(
			"%s appears in no tie at all" % agent.id
		).is_greater(0)


func test_a_creditor_is_central_even_though_he_feels_nothing() -> void:
	# The Merchant is owed by two people and pulled on by almost nobody. Counting
	# only the ties he feels reports him as an isolate, which is exactly wrong.
	var sim := _sim()
	assert_int(sim.relations.involvement_of(Roster.MERCHANT)).is_greater(
		sim.relations.degree_of(Roster.MERCHANT)
	)
	assert_int(sim.relations.holds_over(Roster.MERCHANT).size()).is_greater_equal(2)


func test_the_town_is_clustered_not_evenly_spread() -> void:
	# Somebody should be near-isolated and somebody well connected, or the
	# social map has no shape to read.
	var sim := _sim()
	var lowest: int = 99
	var highest: int = 0
	for agent in sim.agents:
		var degree: int = sim.relations.degree_of(agent.id)
		lowest = mini(lowest, degree)
		highest = maxi(highest, degree)
	assert_int(highest - lowest).is_greater(1)


func test_opening_regard_reflects_the_ties() -> void:
	var sim := _sim()
	var healer: Agent = sim.agent_by_id(Roster.HEALER)
	var sheriff: Agent = sim.agent_by_id(Roster.SHERIFF)

	# Kin opens warm, a feud opens cold.
	assert_float(healer.relationships.score_for(Roster.MILLER)).is_greater(80.0)
	assert_float(sheriff.relationships.score_for(Roster.DRUNKARD)).is_less(20.0)


# --- ties change how events land -------------------------------------------

func test_harming_kin_hurts_more_than_harming_a_friend() -> void:
	var graph := RelationGraph.new()
	graph.add(&"watcher_kin", &"victim", _K.KIN)
	graph.add(&"watcher_friend", &"victim", _K.FRIENDSHIP)

	var token := MemoryToken.new(&"player", ActionCatalog.THREATENED, &"victim", true, 7, &"", 0)

	var kin := _agent(&"watcher_kin")
	kin.relations = graph
	var friend := _agent(&"watcher_friend")
	friend.relations = graph

	assert_float(GossipEngine.evaluate(token, kin)).override_failure_message(
		"threatening a man's brother landed no harder than threatening his drinking companion"
	).is_less(GossipEngine.evaluate(token, friend))


func test_a_favour_to_someone_they_despise_is_not_a_favour() -> void:
	var graph := RelationGraph.new().add(&"watcher", &"target", _K.RIVALRY)
	var watcher := _agent(&"watcher")
	watcher.relations = graph

	var token := MemoryToken.new(&"player", ActionCatalog.HELPED, &"target", true, 6, &"", 0)
	assert_float(GossipEngine.evaluate(token, watcher)).is_less(0.0)


func test_wrongdoing_by_kin_is_excused_more_than_by_a_stranger() -> void:
	var graph := RelationGraph.new().add(&"watcher", &"culprit", _K.KIN)
	var loyal := _agent(&"watcher")
	loyal.relations = graph
	var stranger := _agent(&"other")
	stranger.relations = graph

	var token := MemoryToken.new(&"culprit", ActionCatalog.STOLE_FROM, &"someone", true, 7, &"", 0)
	assert_float(GossipEngine.evaluate(token, loyal)).is_greater(
		GossipEngine.evaluate(token, stranger)
	)


func test_an_agent_without_a_graph_still_honours_declared_attachments() -> void:
	# Bare agents are how the gossip unit tests are built; they must keep working.
	var bare := _agent(&"bare")
	bare.psyche.loyal_to = [&"friend"]
	bare.psyche.rivals = [&"enemy"]

	assert_float(bare.attachment_to(&"friend")).is_greater(0.0)
	assert_float(bare.attachment_to(&"enemy")).is_less(0.0)
	assert_float(bare.attachment_to(&"nobody")).is_equal(0.0)


# --- shared secrets --------------------------------------------------------

func test_the_affair_is_one_secret_belonging_to_two_people() -> void:
	var sim := _sim()
	var affair: Secret = null
	for secret in sim.secrets:
		if secret.content.action == ActionCatalog.ROMANCED:
			affair = secret
			break

	assert_object(affair).is_not_null()
	assert_int(affair.participants.size()).is_equal(2)
	assert_bool(affair.is_known_to(Roster.PREACHER)).is_true()
	assert_bool(affair.is_known_to(Roster.WIDOW)).is_true()
	assert_bool(affair.is_contained()).is_true()


func test_probing_one_lover_implicates_the_other() -> void:
	var sim := _sim()
	var preacher: Agent = sim.agent_by_id(Roster.PREACHER)
	sim.player_zone = preacher.current_zone
	preacher.relationships.set_score(Agent.PLAYER_ID, 90.0)

	var report: Dictionary = PlayerActions.perform(PlayerActions.Kind.PROBE, preacher, sim, 0)

	assert_bool(report["ok"]).is_true()
	assert_bool(sim.knows_secret_of(Agent.PLAYER_ID, Roster.WIDOW)).override_failure_message(
		"the Preacher confessed the affair and it gave no hold over the Widow"
	).is_true()


func test_a_secret_stops_being_contained_once_an_outsider_knows() -> void:
	var sim := _sim()
	var secret: Secret = sim.secrets[0]
	assert_bool(secret.is_contained()).is_true()

	sim.reveal_secret(secret, Roster.DRUNKARD)
	assert_bool(secret.is_contained()).is_false()
	assert_int(secret.outsiders_who_know()).is_equal(1)


func test_the_player_knowing_does_not_count_as_the_town_knowing() -> void:
	var sim := _sim()
	var secret: Secret = sim.secrets[0]
	sim.reveal_secret(secret, Agent.PLAYER_ID)
	assert_bool(secret.is_contained()).is_true()


func test_revealing_twice_is_not_news_twice() -> void:
	var sim := _sim()
	var secret: Secret = sim.secrets[0]
	assert_bool(sim.reveal_secret(secret, Roster.DRUNKARD)).is_true()
	assert_bool(sim.reveal_secret(secret, Roster.DRUNKARD)).is_false()


func test_at_least_one_secret_implicates_a_candidate() -> void:
	# There must be a route to the election through leverage, not only through
	# persuasion.
	var sim := _sim()
	var found: bool = false
	for secret in sim.secrets:
		for participant in secret.participants:
			if sim.candidate_ids.has(participant):
				found = true
	assert_bool(found).override_failure_message(
		"no secret touches any candidate — blackmail cannot affect the race"
	).is_true()


# --- trysts ----------------------------------------------------------------

func test_lovers_break_their_routine_to_meet() -> void:
	var sim := _sim()
	var preacher: Agent = sim.agent_by_id(Roster.PREACHER)
	var widow: Agent = sim.agent_by_id(Roster.WIDOW)

	var met: bool = false
	for day in GameClock.TOTAL_DAYS:
		for hour in GameClock.HOURS_PER_DAY:
			sim.step_hour(day, hour)
			if preacher.current_zone == TownSim.TRYST_ZONE and widow.current_zone == TownSim.TRYST_ZONE:
				met = true
	assert_bool(met).override_failure_message(
		"the lovers never once met over seven days"
	).is_true()


func test_a_tryst_is_not_every_night() -> void:
	# If it happened nightly it would be a schedule, not a secret.
	var sim := _sim()
	var nights: int = 0
	for day in GameClock.TOTAL_DAYS:
		if not sim._tryst_pairs(day, TownSim.TRYST_HOUR).is_empty():
			nights += 1
	assert_int(nights).is_greater(0)
	assert_int(nights).is_less(GameClock.TOTAL_DAYS)


func test_watching_the_woods_at_the_right_hour_uncovers_the_affair() -> void:
	# The intended discovery route: no menu, no probe, just noticing.
	var sim := _sim()
	sim.player_zone = TownSim.TRYST_ZONE

	for day in GameClock.TOTAL_DAYS:
		for hour in GameClock.HOURS_PER_DAY:
			sim.step_hour(day, hour)

	assert_bool(sim.knows_secret_of(Agent.PLAYER_ID, Roster.PREACHER)).override_failure_message(
		"stood in the woods all week and never noticed the affair"
	).is_true()


func test_staying_home_uncovers_nothing() -> void:
	var sim := _sim()
	sim.player_zone = _Z.SHERIFF

	for day in 2:
		for hour in GameClock.HOURS_PER_DAY:
			sim.step_hour(day, hour)

	assert_bool(sim.knows_secret_of(Agent.PLAYER_ID, Roster.PREACHER)).is_false()
