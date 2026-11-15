## The contested election: rival candidates, relative voting, secrets, and the
## town generating its own news.
extends GdUnitTestSuite

const _Z := TownGrid.Zone
const HOURS_IN_WEEK := GameClock.TOTAL_DAYS * GameClock.HOURS_PER_DAY


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


func _electorate(sim: TownSim) -> Array[Agent]:
	var out: Array[Agent] = []
	for agent in sim.agents:
		if not sim.candidate_ids.has(agent.id):
			out.append(agent)
	return out


func _run_week(sim: TownSim) -> void:
	for h in HOURS_IN_WEEK:
		sim.step_hour(h / GameClock.HOURS_PER_DAY, h % GameClock.HOURS_PER_DAY)


# --- relative voting -------------------------------------------------------

func test_the_town_has_more_than_one_candidate() -> void:
	var sim := _sim()
	assert_int(sim.candidate_ids.size()).is_greater(1)
	assert_bool(sim.candidate_ids.has(Agent.PLAYER_ID)).is_true()


func test_a_vote_goes_to_whoever_is_favoured_most() -> void:
	var sim := _sim()
	var voter: Agent = _electorate(sim)[0]
	voter.relationships.set_score(Agent.PLAYER_ID, 80.0)
	voter.relationships.set_score(Roster.MAYOR, 70.0)
	assert_str(str(sim.tally_votes()["ballots"][voter.id])).is_equal(str(Agent.PLAYER_ID))

	# A rival pulling ahead takes the vote, even though regard for the player
	# has not dropped at all. This is what an absolute threshold could not do.
	voter.relationships.set_score(Roster.MAYOR, 85.0)
	assert_str(str(sim.tally_votes()["ballots"][voter.id])).is_equal(str(Roster.MAYOR))


func test_raising_your_own_number_is_not_enough_if_a_rival_raises_theirs() -> void:
	var sim := _sim()
	var voter: Agent = _electorate(sim)[0]
	voter.relationships.set_score(Agent.PLAYER_ID, 95.0)
	voter.relationships.set_score(Roster.MERCHANT, 96.0)
	assert_str(str(sim.tally_votes()["ballots"][voter.id])).is_not_equal(str(Agent.PLAYER_ID))


func test_the_tally_reports_every_candidate() -> void:
	var counts: Dictionary = _sim().tally_votes()["counts"]
	for candidate_id in _sim().candidate_ids:
		assert_bool(counts.has(candidate_id)).is_true()


func test_swing_voters_exclude_people_already_backing_you() -> void:
	var sim := _sim()
	var voter: Agent = _electorate(sim)[0]
	voter.relationships.set_score(Agent.PLAYER_ID, 95.0)

	for swing in sim.swing_voters():
		assert_str(str(swing.id)).is_not_equal(str(voter.id))


# --- rival campaigning -----------------------------------------------------

func test_rivals_actually_campaign() -> void:
	var sim := _sim()
	var seen: Array[StringName] = []
	var handler := func(actor_id: StringName, _k: int, _t: StringName, _d: float, _w: Array) -> void:
		if actor_id != Agent.PLAYER_ID:
			seen.append(actor_id)
	EventBus.approach_made.connect(handler)
	_run_week(sim)
	EventBus.approach_made.disconnect(handler)

	assert_int(seen.size()).override_failure_message(
		"no rival made a single approach over seven days"
	).is_greater(0)


func test_rivals_win_votes_if_left_unopposed() -> void:
	var sim := _sim()
	_run_week(sim)

	var counts: Dictionary = sim.tally_votes()["counts"]
	var rival_votes: int = 0
	for candidate_id in sim.candidate_ids:
		if candidate_id != Agent.PLAYER_ID:
			rival_votes += counts[candidate_id]

	# Each rival votes for themselves, so anything above that count is a vote
	# they actively won from the electorate.
	assert_int(rival_votes).is_greater(sim.candidate_ids.size() - 1)


func test_doing_nothing_loses() -> void:
	var sim := _sim()
	_run_week(sim)
	assert_bool(sim.tally_votes()["won"]).is_false()


## Plays the strongest thoughtless strategy available: stay where the crowd is,
## act every single hour, alternate the two approaches that cannot backfire on
## the target. Returns the final tally.
func _play_naively(sim: TownSim) -> Dictionary:
	for h in HOURS_IN_WEEK:
		var day: int = h / GameClock.HOURS_PER_DAY
		sim.step_hour(day, h % GameClock.HOURS_PER_DAY)

		# Work the room you are in; when it empties, move to the busiest one.
		# That is the constraint rivals live under, and now so does the player.
		var here: Array[Agent] = []
		for agent in sim.agents_with_player():
			if not sim.candidate_ids.has(agent.id):
				here.append(agent)

		if here.is_empty():
			sim.player_zone = _busiest_zone(sim)
			continue

		var kind: PlayerActions.Kind = (
			PlayerActions.Kind.HELP if h % 2 == 0 else PlayerActions.Kind.FLATTER
		)
		PlayerActions.perform(kind, here[h % here.size()], sim, day)

	return sim.tally_votes()


func test_help_and_flattery_alone_is_not_a_reliable_win() -> void:
	# The exploit this whole system exists to close: six votes used to arrive
	# from nothing but Help and Flatter, with no opposition and no decisions.
	#
	# The bar is deliberately "not reliable" rather than "always loses". A
	# player who works the room every hour for seven days *should* sometimes
	# succeed — what must not happen is that it works regardless of who they
	# are talking to.
	var wins: int = 0
	var results: Array[String] = []

	for seed_value in [20260730, 1, 7, 99, 31337]:
		GameClock.reset()
		var sim: TownSim = auto_free(TownSim.new())
		sim.setup(seed_value)

		var tally: Dictionary = _play_naively(sim)
		if tally["won"]:
			wins += 1
		results.append("%d:%d" % [seed_value, tally["votes_for"]])

	assert_int(wins).override_failure_message(
		"thoughtless spam won every playthrough (votes by seed: %s)" % ", ".join(results)
	).is_less(5)


func test_a_thoughtless_run_still_loses_the_miller() -> void:
	# Flattery is half of the naive strategy and it is exactly what ruins Elias.
	# Spamming it must carry a visible cost.
	var sim := _sim()
	_play_naively(sim)

	var miller: Agent = sim.agent_by_id(Roster.MILLER)
	assert_str(str(sim.tally_votes()["ballots"][miller.id])).override_failure_message(
		"flattering a man whose trauma is flattery still won his vote"
	).is_not_equal(str(Agent.PLAYER_ID))


func _busiest_zone(sim: TownSim) -> int:
	var best: int = TownGrid.Zone.MARKET
	var best_count: int = -1
	for zone in TownGrid.Zone.values():
		var count: int = sim.agents_in_zone(zone).size()
		if count > best_count:
			best_count = count
			best = zone
	return best


# --- secrets ---------------------------------------------------------------

func test_everyone_is_hiding_something() -> void:
	var sim := _sim()
	for agent in sim.agents:
		assert_array(sim.secrets_about(agent.id)).override_failure_message(
			"%s has no secret" % agent.id
		).is_not_empty()


func test_a_secret_is_not_in_its_owners_own_ledger() -> void:
	# Otherwise they would cheerfully gossip about their own ruin.
	var sim := _sim()
	for secret in sim.secrets:
		for participant in secret.participants:
			var agent: Agent = sim.agent_by_id(participant)
			if agent != null:
				assert_bool(agent.ledger.knows(secret.content)).is_false()


func test_participants_already_know_their_own_secret() -> void:
	var sim := _sim()
	for secret in sim.secrets:
		for participant in secret.participants:
			assert_bool(secret.is_known_to(participant)).is_true()


func test_a_shared_secret_gives_leverage_over_everyone_in_it() -> void:
	# The whole reason secrets became objects: the affair belongs to two people
	# and one discovery exposes both.
	var sim := _sim()
	var affair: Secret = null
	for secret in sim.secrets:
		if secret.participants.size() > 1:
			affair = secret
			break
	assert_object(affair).is_not_null()

	sim.reveal_secret(affair, Agent.PLAYER_ID)
	for participant in affair.participants:
		assert_bool(sim.knows_secret_of(Agent.PLAYER_ID, participant)).override_failure_message(
			"knowing the shared secret gave no leverage over %s" % participant
		).is_true()


func test_a_participant_holds_no_leverage_over_their_own_secret() -> void:
	var sim := _sim()
	for secret in sim.secrets:
		for participant in secret.participants:
			assert_bool(sim.knows_secret_of(participant, participant)).is_false()


func test_probing_a_stranger_fails() -> void:
	var sim := _sim()
	var target: Agent = sim.agent_by_id(Roster.HEALER)
	sim.player_zone = target.current_zone
	var report: Dictionary = PlayerActions.perform(PlayerActions.Kind.PROBE, target, sim, 0)

	assert_bool(report["ok"]).is_false()
	assert_str(report["note"]).is_not_empty()
	assert_bool(sim.knows_secret_of(Agent.PLAYER_ID, target.id)).is_false()


func test_probing_someone_who_trusts_you_uncovers_their_secret() -> void:
	var sim := _sim()
	var target: Agent = sim.agent_by_id(Roster.HEALER)
	sim.player_zone = target.current_zone
	target.relationships.set_score(Agent.PLAYER_ID, 90.0)

	var report: Dictionary = PlayerActions.perform(PlayerActions.Kind.PROBE, target, sim, 0)

	assert_bool(report["ok"]).is_true()
	assert_object(report["discovered"]).is_not_null()
	assert_bool(sim.knows_secret_of(Agent.PLAYER_ID, target.id)).is_true()


func test_a_failed_approach_reports_why() -> void:
	var sim := _sim()
	var target: Agent = sim.agent_by_id(Roster.HEALER)
	sim.player_zone = target.current_zone
	var report: Dictionary = PlayerActions.perform(PlayerActions.Kind.BLACKMAIL, target, sim, 0)
	assert_bool(report["ok"]).is_false()
	assert_str(report["note"]).contains("nothing to hold over")


# --- exposing a rival ------------------------------------------------------

func test_you_cannot_expose_what_you_do_not_know() -> void:
	var sim := _sim()
	var listener: Agent = sim.agent_by_id(Roster.HEALER)
	sim.player_zone = listener.current_zone
	assert_bool(PlayerActions.can_expose(listener, sim)).is_false()

	var report: Dictionary = PlayerActions.perform(PlayerActions.Kind.EXPOSE, listener, sim, 0)
	assert_bool(report["ok"]).is_false()


func test_repeating_a_secret_damages_the_person_it_is_about() -> void:
	# The counterweight to a relative vote: you cannot always out-charm a rival,
	# so you have to give their supporters a reason to think less of them.
	var sim := _sim()
	var listener: Agent = sim.agent_by_id(Roster.HEALER)
	sim.player_zone = listener.current_zone

	var ledger: Secret = null
	for secret in sim.secrets:
		if secret.involves(Roster.MAYOR):
			ledger = secret
	sim.reveal_secret(ledger, Agent.PLAYER_ID)

	var before: float = listener.relationships.score_for(Roster.MAYOR)
	var report: Dictionary = PlayerActions.perform(PlayerActions.Kind.EXPOSE, listener, sim, 0)

	assert_bool(report["ok"]).is_true()
	assert_float(listener.relationships.score_for(Roster.MAYOR)).is_less(before)


func test_carrying_tales_costs_you_with_the_scrupulous() -> void:
	var sim := _sim()
	var listener: Agent = sim.agent_by_id(Roster.PREACHER)  # Sanctity 0.95
	sim.player_zone = listener.current_zone

	for secret in sim.secrets:
		if secret.involves(Roster.MAYOR):
			sim.reveal_secret(secret, Agent.PLAYER_ID)

	var before: float = listener.opinion_of_player()
	PlayerActions.perform(PlayerActions.Kind.EXPOSE, listener, sim, 0)

	assert_float(listener.opinion_of_player()).override_failure_message(
		"gossip-mongering to a man who prizes decency cost nothing"
	).is_less(before)


func test_a_shared_secret_tarnishes_everyone_in_it() -> void:
	var sim := _sim()
	var listener: Agent = sim.agent_by_id(Roster.HEALER)
	sim.player_zone = listener.current_zone

	var payroll: Secret = null
	for secret in sim.secrets:
		if secret.id == &"the_payroll":
			payroll = secret
	sim.reveal_secret(payroll, Agent.PLAYER_ID)

	var sheriff_before: float = listener.relationships.score_for(Roster.SHERIFF)
	PlayerActions.perform(PlayerActions.Kind.EXPOSE, listener, sim, 0, Agent.PLAYER_ID, Roster.MERCHANT)

	assert_float(listener.relationships.score_for(Roster.SHERIFF)).override_failure_message(
		"the Sheriff took no damage from his own arrangement being aired"
	).is_less(sheriff_before)


func test_you_are_not_told_about_yourself() -> void:
	var sim := _sim()
	var listener: Agent = sim.agent_by_id(Roster.MAYOR)
	sim.player_zone = listener.current_zone

	for secret in sim.secrets:
		if secret.involves(Roster.MAYOR):
			sim.reveal_secret(secret, Agent.PLAYER_ID)

	# The only thing the player knows concerns the listener, so there is nothing
	# to say to them.
	assert_bool(PlayerActions.can_expose(listener, sim)).is_false()


func test_the_same_news_twice_is_not_news() -> void:
	var sim := _sim()
	var listener: Agent = sim.agent_by_id(Roster.HEALER)
	sim.player_zone = listener.current_zone

	for secret in sim.secrets:
		if secret.involves(Roster.MAYOR):
			sim.reveal_secret(secret, Agent.PLAYER_ID)

	assert_bool(PlayerActions.perform(PlayerActions.Kind.EXPOSE, listener, sim, 0)["ok"]).is_true()
	var second: Dictionary = PlayerActions.perform(PlayerActions.Kind.EXPOSE, listener, sim, 1)
	assert_bool(second["ok"]).is_false()


func test_exposure_can_swing_a_vote_away_from_a_rival() -> void:
	var sim := _sim()
	var listener: Agent = sim.agent_by_id(Roster.HEALER)
	sim.player_zone = listener.current_zone

	listener.relationships.set_score(Roster.MAYOR, 80.0)
	listener.relationships.set_score(Agent.PLAYER_ID, 74.0)
	assert_str(str(sim.tally_votes()["ballots"][listener.id])).is_equal(str(Roster.MAYOR))

	for secret in sim.secrets:
		if secret.involves(Roster.MAYOR):
			sim.reveal_secret(secret, Agent.PLAYER_ID)
	PlayerActions.perform(PlayerActions.Kind.EXPOSE, listener, sim, 0)

	assert_str(str(sim.tally_votes()["ballots"][listener.id])).override_failure_message(
		"airing the Mayor's embezzlement did not cost him the vote"
	).is_not_equal(str(Roster.MAYOR))


# --- blackmail -------------------------------------------------------------

func test_blackmail_requires_leverage() -> void:
	var sim := _sim()
	var target: Agent = sim.agent_by_id(Roster.MILLER)
	sim.player_zone = target.current_zone
	assert_bool(PlayerActions.perform(PlayerActions.Kind.BLACKMAIL, target, sim, 0)["ok"]).is_false()


func test_blackmail_buys_the_vote_immediately() -> void:
	var sim := _sim()
	var target: Agent = sim.agent_by_id(Roster.MILLER)
	sim.player_zone = target.current_zone
	sim.reveal_secret_of(target.id, Agent.PLAYER_ID)

	var report: Dictionary = PlayerActions.perform(PlayerActions.Kind.BLACKMAIL, target, sim, 0)

	assert_bool(report["ok"]).is_true()
	assert_float(target.opinion_of_player()).is_greater_equal(PlayerActions.COERCED_SUPPORT)
	assert_str(str(sim.tally_votes()["ballots"][target.id])).is_equal(str(Agent.PLAYER_ID))


func test_a_blackmail_victim_goes_looking_for_the_sheriff() -> void:
	var sim := _sim()
	var target: Agent = sim.agent_by_id(Roster.MILLER)
	sim.player_zone = target.current_zone
	sim.reveal_secret_of(target.id, Agent.PLAYER_ID)
	PlayerActions.perform(PlayerActions.Kind.BLACKMAIL, target, sim, 0)

	assert_float(target.need_of(Agent.Need.SAFETY)).is_equal(1.0)
	assert_object(target.pending_report).is_not_null()

	sim.step_hour(0, 9)
	assert_bool(target.is_seeking()).is_true()


func test_the_sheriff_learns_of_it_once_the_victim_reaches_him() -> void:
	var sim := _sim()
	var target: Agent = sim.agent_by_id(Roster.MILLER)
	var sheriff: Agent = sim.agent_by_id(Roster.SHERIFF)

	# Get the victim alone, or the Sheriff simply witnesses the blackmail
	# directly and the delivery path never gets exercised.
	for agent in sim.agents:
		agent.current_zone = _Z.RESIDENCES
	target.current_zone = _Z.WOODS
	sim.player_zone = _Z.WOODS

	sim.reveal_secret_of(target.id, Agent.PLAYER_ID)
	var before: float = sheriff.opinion_of_player()
	PlayerActions.perform(PlayerActions.Kind.BLACKMAIL, target, sim, 0)
	assert_float(sheriff.opinion_of_player()).override_failure_message(
		"the Sheriff should not know yet — he was not in the room"
	).is_equal(before)
	for hour in range(9, 20):
		sim.step_hour(0, hour)
		if target.pending_report == null:
			break

	assert_object(target.pending_report).override_failure_message(
		"the victim never reached anyone to report it"
	).is_null()
	assert_float(sheriff.opinion_of_player()).override_failure_message(
		"the Sheriff heard about a blackmail and did not care"
	).is_less(before)


# --- incidents -------------------------------------------------------------

func test_the_town_generates_its_own_news() -> void:
	# The defect this closes: previously 19 exchanges on day one and zero for
	# the rest of the week, with every opinion frozen.
	var sim := _sim()
	var incidents: Array[MemoryToken] = []
	var handler := func(token: MemoryToken) -> void: incidents.append(token)
	EventBus.incident_occurred.connect(handler)
	_run_week(sim)
	EventBus.incident_occurred.disconnect(handler)

	assert_int(incidents.size()).override_failure_message(
		"the town produced no events of its own over seven days"
	).is_greater(0)


func test_conversation_continues_past_the_first_day() -> void:
	var sim := _sim()
	var counter: Array[int] = [0]
	var handler := func(_s: StringName, _l: StringName, _t: MemoryToken) -> void:
		counter[0] += 1
	EventBus.gossip_exchanged.connect(handler)

	for h in GameClock.HOURS_PER_DAY:
		sim.step_hour(0, h)
	var after_day_one: int = counter[0]

	for h in range(GameClock.HOURS_PER_DAY, HOURS_IN_WEEK):
		sim.step_hour(h / GameClock.HOURS_PER_DAY, h % GameClock.HOURS_PER_DAY)
	EventBus.gossip_exchanged.disconnect(handler)

	assert_int(counter[0] - after_day_one).override_failure_message(
		"town went silent after day one again (%d exchanges on day 1, none since)" % after_day_one
	).is_greater(0)


func test_opinions_keep_moving_all_week() -> void:
	var sim := _sim()
	for h in GameClock.HOURS_PER_DAY * 2:
		sim.step_hour(h / GameClock.HOURS_PER_DAY, h % GameClock.HOURS_PER_DAY)

	# Every relationship in town, not just regard for the player — the player is
	# doing nothing in this test, so their own standing has no reason to move.
	var midweek: Dictionary = _social_fingerprint(sim)

	for h in range(GameClock.HOURS_PER_DAY * 2, HOURS_IN_WEEK):
		sim.step_hour(h / GameClock.HOURS_PER_DAY, h % GameClock.HOURS_PER_DAY)

	var moved: int = 0
	var now: Dictionary = _social_fingerprint(sim)
	for key in now:
		if not midweek.has(key) or not is_equal_approx(midweek[key], now[key]):
			moved += 1

	assert_int(moved).override_failure_message(
		"no relationship in the whole town changed between day 3 and day 7"
	).is_greater(0)


func _social_fingerprint(sim: TownSim) -> Dictionary:
	var out: Dictionary = {}
	for agent in sim.agents:
		for other_id in agent.relationships.known_ids():
			out["%s->%s" % [agent.id, other_id]] = agent.relationships.score_for(other_id)
	return out


func test_the_week_still_runs_within_bounds() -> void:
	var sim := _sim()
	_run_week(sim)
	for agent in sim.agents:
		assert_int(agent.ledger.size()).is_less_equal(MemoryLedger.CAPACITY)
		for other_id in agent.relationships.known_ids():
			assert_float(agent.relationships.score_for(other_id)).is_between(
				RelationshipBook.MIN_SCORE, RelationshipBook.MAX_SCORE
			)


func test_the_contested_week_is_still_deterministic() -> void:
	var first := _sim(4242)
	var second := _sim(4242)
	_run_week(first)
	_run_week(second)

	for i in first.agents.size():
		assert_float(first.agents[i].opinion_of_player()).override_failure_message(
			"%s diverged between identical seeds" % first.agents[i].id
		).is_equal(second.agents[i].opinion_of_player())
