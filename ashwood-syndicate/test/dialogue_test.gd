## Conversations: contextual choices, sim-decided outcomes, model-written words.
##
## Everything here runs against a scripted backend. The dialogue system must be
## fully testable — and fully playable — with no model running at all.
extends GdUnitTestSuite

const _Z := TownGrid.Zone


## Returns canned lines and records what it was asked for, so tests can assert
## on the prompt without a server.
class ScriptedBackend extends DialogueBackend:
	var requests: Array[Dictionary] = []
	var reply: String = "A scripted line."

	func request_line(request: Dictionary) -> void:
		requests.append(request)
		deliver(reply)

	func last() -> Dictionary:
		return requests[requests.size() - 1] if not requests.is_empty() else {}


## Never answers, to prove the fallback path.
class SilentBackend extends DialogueBackend:
	func request_line(request: Dictionary) -> void:
		deliver(DialogueBackend.fallback_line(request))


func before_test() -> void:
	GameClock.time_scale = 0.0
	GameClock.reset()


func after_test() -> void:
	GameClock.reset()
	GameClock.time_scale = 1.0


func _sim() -> TownSim:
	var sim: TownSim = auto_free(TownSim.new())
	sim.setup(20260730)
	return sim


func _talk(sim: TownSim, agent: Agent, backend: DialogueBackend = null) -> Conversation:
	sim.player_zone = agent.current_zone
	return Conversation.new(agent, sim, backend if backend != null else ScriptedBackend.new(), 0)


func _find(choices: Array[Dictionary], kind: PlayerActions.Kind) -> Dictionary:
	for choice in choices:
		if choice["kind"] == Conversation.ChoiceKind.APPROACH and choice["approach"] == kind:
			return choice
	return {}


# --- opening ---------------------------------------------------------------

func test_a_conversation_opens_with_a_line() -> void:
	var sim := _sim()
	var conversation := _talk(sim, sim.agent_by_id(Roster.HEALER))
	var line: String = await conversation.open()
	assert_str(line).is_not_empty()


func test_the_opening_is_hostile_when_they_despise_you() -> void:
	var sim := _sim()
	var target: Agent = sim.agent_by_id(Roster.HEALER)
	target.relationships.set_score(Agent.PLAYER_ID, 10.0)

	var backend := ScriptedBackend.new()
	var conversation := _talk(sim, target, backend)
	await conversation.open()

	assert_str(backend.last()["outcome"]).is_equal("hostile")


# --- choices are contextual ------------------------------------------------

func test_the_ordinary_approaches_are_always_offered() -> void:
	var sim := _sim()
	var choices: Array[Dictionary] = _talk(sim, sim.agent_by_id(Roster.HEALER)).choices()
	for kind in [PlayerActions.Kind.HELP, PlayerActions.Kind.FLATTER,
			PlayerActions.Kind.BRIBE, PlayerActions.Kind.THREATEN]:
		assert_dict(_find(choices, kind)).is_not_empty()


func test_blackmail_is_hidden_until_you_hold_something() -> void:
	var sim := _sim()
	var target: Agent = sim.agent_by_id(Roster.MILLER)

	assert_dict(_find(_talk(sim, target).choices(), PlayerActions.Kind.BLACKMAIL)).is_empty()

	sim.reveal_secret_of(target.id, Agent.PLAYER_ID)
	assert_dict(_find(_talk(sim, target).choices(), PlayerActions.Kind.BLACKMAIL)).is_not_empty()


func test_probing_disappears_once_you_already_know() -> void:
	var sim := _sim()
	var target: Agent = sim.agent_by_id(Roster.MILLER)
	assert_dict(_find(_talk(sim, target).choices(), PlayerActions.Kind.PROBE)).is_not_empty()

	sim.reveal_secret_of(target.id, Agent.PLAYER_ID)
	assert_dict(_find(_talk(sim, target).choices(), PlayerActions.Kind.PROBE)).is_empty()


func test_you_can_ask_about_people_they_are_tied_to() -> void:
	var sim := _sim()
	# Put the Preacher somewhere alone so his ties are elsewhere and askable.
	var preacher: Agent = sim.agent_by_id(Roster.PREACHER)
	for agent in sim.agents:
		agent.current_zone = _Z.MARKET
	preacher.current_zone = _Z.WOODS

	var asks: int = 0
	for choice in _talk(sim, preacher).choices():
		if choice["kind"] == Conversation.ChoiceKind.ASK_ABOUT:
			asks += 1
	assert_int(asks).is_greater(0)


func test_leaving_is_always_available() -> void:
	var sim := _sim()
	var choices: Array[Dictionary] = _talk(sim, sim.agent_by_id(Roster.HEALER)).choices()
	var found: bool = false
	for choice in choices:
		if choice["kind"] == Conversation.ChoiceKind.LEAVE:
			found = true
	assert_bool(found).is_true()


# --- the simulation decides, the words follow ------------------------------

func test_an_approach_moves_the_simulation_not_just_the_text() -> void:
	var sim := _sim()
	var target: Agent = sim.agent_by_id(Roster.HEALER)
	var conversation := _talk(sim, target)
	var before: float = target.opinion_of_player()

	await conversation.choose(_find(conversation.choices(), PlayerActions.Kind.HELP))

	assert_float(target.opinion_of_player()).is_greater(before)


func test_the_outcome_handed_to_the_backend_matches_what_happened() -> void:
	var sim := _sim()
	var target: Agent = sim.agent_by_id(Roster.SHERIFF)
	var backend := ScriptedBackend.new()
	var conversation := _talk(sim, target, backend)

	await conversation.choose(_find(conversation.choices(), PlayerActions.Kind.THREATEN))

	assert_str(backend.last()["outcome"]).is_equal("hostile")


func test_a_favour_reads_as_warmth() -> void:
	var sim := _sim()
	var backend := ScriptedBackend.new()
	var conversation := _talk(sim, sim.agent_by_id(Roster.HEALER), backend)

	await conversation.choose(_find(conversation.choices(), PlayerActions.Kind.HELP))

	assert_str(backend.last()["outcome"]).is_equal("warm")


func test_flattering_the_miller_still_backfires_in_conversation() -> void:
	# The psychology must survive the new layer, not be replaced by it.
	var sim := _sim()
	var miller: Agent = sim.agent_by_id(Roster.MILLER)
	var backend := ScriptedBackend.new()
	var conversation := _talk(sim, miller, backend)

	await conversation.choose(_find(conversation.choices(), PlayerActions.Kind.FLATTER))

	assert_str(backend.last()["outcome"]).is_equal("hostile")


# --- asking about people ---------------------------------------------------

func test_a_stranger_will_not_share_their_read_on_anyone() -> void:
	var sim := _sim()
	var target: Agent = sim.agent_by_id(Roster.PREACHER)
	target.relationships.set_score(Agent.PLAYER_ID, 20.0)
	for agent in sim.agents:
		agent.current_zone = _Z.MARKET
	target.current_zone = _Z.WOODS

	var backend := ScriptedBackend.new()
	var conversation := _talk(sim, target, backend)
	for choice in conversation.choices():
		if choice["kind"] == Conversation.ChoiceKind.ASK_ABOUT:
			await conversation.choose(choice)
			break

	assert_str(backend.last()["outcome"]).is_equal("refuse")


func test_someone_who_trusts_you_hands_over_what_they_know() -> void:
	var sim := _sim()
	var target: Agent = sim.agent_by_id(Roster.PREACHER)
	target.relationships.set_score(Agent.PLAYER_ID, 90.0)
	for agent in sim.agents:
		agent.current_zone = _Z.MARKET
	target.current_zone = _Z.WOODS

	# Give them something worth repeating.
	target.learn(MemoryToken.new(Roster.MAYOR, ActionCatalog.STOLE_FROM, &"the purse", true, 8, &"", 0))

	var conversation := _talk(sim, target)
	for choice in conversation.choices():
		if choice["kind"] == Conversation.ChoiceKind.ASK_ABOUT and choice["subject"] == Roster.MAYOR:
			await conversation.choose(choice)
			break

	assert_array(sim.player_knows_about(Roster.MAYOR)).override_failure_message(
		"they answered honestly and the player learned nothing"
	).is_not_empty()


# --- bounds ----------------------------------------------------------------

func test_pleasant_conversation_can_run_as_long_as_you_like() -> void:
	# The whole point of being able to type is finding out who somebody is
	# before deciding what will work on them. A turn budget made that
	# impossible: three lines and they walked off.
	var sim := _sim()
	var conversation := _talk(sim, sim.agent_by_id(Roster.HEALER))
	await conversation.open()

	for i in 20:
		await conversation.say("Fine weather for the season.")

	assert_bool(conversation.is_over).override_failure_message(
		"they lost patience with harmless conversation"
	).is_false()
	assert_int(conversation.hours_spent).override_failure_message(
		"talking burned hours of a seven day week"
	).is_equal(0)


func test_they_walk_away_from_someone_who_keeps_offending_them() -> void:
	# Patience is finite; it is just spent by rebuffs rather than by turns.
	var sim := _sim()
	var healer: Agent = sim.agent_by_id(Roster.HEALER)
	var conversation := _talk(sim, healer)

	for i in Conversation.MAX_PATIENCE + 2:
		if conversation.is_over:
			break
		await conversation.choose(_find(conversation.choices(), PlayerActions.Kind.THREATEN))

	assert_bool(conversation.is_over).override_failure_message(
		"a single conversation could be farmed indefinitely"
	).is_true()


func test_someone_who_despises_you_has_less_patience_than_a_friend() -> void:
	assert_int(Conversation.patience_for(0.0)).is_less(Conversation.patience_for(100.0))
	assert_int(Conversation.patience_for(0.0)).is_equal(Conversation.MIN_PATIENCE)


func test_an_attempt_costs_an_hour_and_talk_does_not() -> void:
	var sim := _sim()
	var conversation := _talk(sim, sim.agent_by_id(Roster.HEALER))

	await conversation.say("Good morning to you.")
	assert_int(conversation.hours_spent).is_equal(0)

	await conversation.choose(_find(conversation.choices(), PlayerActions.Kind.HELP))
	assert_int(conversation.hours_spent).override_failure_message(
		"an approach was free, so the seven day clock means nothing"
	).is_equal(1)


func test_choices_dry_up_once_it_is_over() -> void:
	var sim := _sim()
	var conversation := _talk(sim, sim.agent_by_id(Roster.HEALER))
	await conversation.choose({"kind": Conversation.ChoiceKind.LEAVE, "text": "", "subject": &""})

	assert_bool(conversation.is_over).is_true()
	assert_array(conversation.choices()).is_empty()


func test_the_transcript_records_both_voices() -> void:
	var sim := _sim()
	var conversation := _talk(sim, sim.agent_by_id(Roster.HEALER))
	await conversation.open()
	await conversation.choose(_find(conversation.choices(), PlayerActions.Kind.HELP))

	var speakers: Array[String] = []
	for entry in conversation.transcript:
		speakers.append(entry["speaker"])
	assert_array(speakers).contains(["You"])


# --- no model required -----------------------------------------------------

func test_the_game_is_playable_with_no_model_running() -> void:
	var sim := _sim()
	var conversation := _talk(sim, sim.agent_by_id(Roster.HEALER), SilentBackend.new())

	var opening: String = await conversation.open()
	assert_str(opening).is_not_empty()

	var reply: String = await conversation.choose(
		_find(conversation.choices(), PlayerActions.Kind.HELP)
	)
	assert_str(reply).is_not_empty()


func test_every_outcome_has_a_fallback_line() -> void:
	for outcome in ["greeting", "hostile", "warm", "guarded", "reveal", "refuse"]:
		var line: String = DialogueBackend.fallback_line({
			"speaker_name": "Calder", "outcome": outcome, "topic": "the Mayor",
		})
		assert_str(line).is_not_empty()


# --- the prompt ------------------------------------------------------------

func test_the_prompt_carries_the_character_not_the_numbers() -> void:
	var sim := _sim()
	var sheriff: Agent = sim.agent_by_id(Roster.SHERIFF)
	var request: Dictionary = PromptBuilder.build(sheriff, sim, "guarded")

	var system: String = request["system"]
	assert_str(system).contains("Sheriff Calder")
	assert_str(system).contains("law, order and proper authority")
	assert_str(system).is_not_empty()


func test_the_prompt_tells_them_what_they_are_hiding() -> void:
	var sim := _sim()
	var request: Dictionary = PromptBuilder.build(sim.agent_by_id(Roster.SHERIFF), sim, "guarded")
	assert_str(request["system"]).contains("WHAT YOU HIDE")


func test_the_prompt_never_asks_the_model_to_decide_the_outcome() -> void:
	# The single rule that keeps the model from contradicting the simulation.
	var sim := _sim()
	var request: Dictionary = PromptBuilder.build(sim.agent_by_id(Roster.HEALER), sim, "hostile")
	assert_str(request["instruction"]).contains("Rebuff")


func test_the_prompt_stays_small_enough_for_a_phone() -> void:
	# Every character must fit a 3B model's budget, or mobile is dead on arrival.
	var sim := _sim()
	for agent in sim.agents:
		var request: Dictionary = PromptBuilder.build(agent, sim, "guarded")
		assert_int(str(request["system"]).length()).override_failure_message(
			"%s's character sheet is %d chars" % [agent.id, str(request["system"]).length()]
		).is_less(2200)


func test_hidden_ties_are_still_known_to_the_person_in_them() -> void:
	# The town must not know about the affair; the Preacher certainly does.
	var sim := _sim()
	var request: Dictionary = PromptBuilder.build(sim.agent_by_id(Roster.PREACHER), sim, "guarded")
	assert_str(request["system"]).contains("your lover, in secret")


func test_the_prompt_reflects_how_they_currently_feel_about_you() -> void:
	var sim := _sim()
	var target: Agent = sim.agent_by_id(Roster.HEALER)

	target.relationships.set_score(Agent.PLAYER_ID, 95.0)
	assert_str(PromptBuilder.build(target, sim, "guarded")["system"]).contains("would back them")

	target.relationships.set_score(Agent.PLAYER_ID, 5.0)
	assert_str(PromptBuilder.build(target, sim, "guarded")["system"]).contains("despise them")


# --- free text -------------------------------------------------------------

func _options(conversation: Conversation) -> Dictionary:
	return {
		"speaker_name": conversation.target.display_name,
		"approaches": conversation.available_approaches(),
		"people": [],
	}


func test_typing_an_offer_of_money_reads_as_a_bribe_with_no_model() -> void:
	# The keyword reader is not a nicety. Ollama absent must still leave a
	# playable game, and that means typed lines still have to mean something.
	var sim := _sim()
	var conversation := _talk(sim, sim.agent_by_id(Roster.HEALER))

	var intent: Dictionary = IntentReader.fallback_intent(
		"There is coin in this for you if you back me.", _options(conversation)
	)

	assert_str(str(intent["kind"])).is_equal(str(IntentReader.APPROACH))
	assert_int(intent["approach"]).is_equal(PlayerActions.Kind.BRIBE)


func test_idle_conversation_reads_as_no_attempt_at_all() -> void:
	var sim := _sim()
	var conversation := _talk(sim, sim.agent_by_id(Roster.HEALER))

	var intent: Dictionary = IntentReader.fallback_intent(
		"Cold morning, isn't it.", _options(conversation)
	)
	assert_str(str(intent["kind"])).is_equal(str(IntentReader.SMALLTALK))


func test_the_reader_cannot_conjure_leverage_nobody_holds() -> void:
	# Typing "I know what you did" must not manufacture a secret. The reader is
	# only ever allowed to pick from approaches actually available.
	var sim := _sim()
	var healer: Agent = sim.agent_by_id(Roster.HEALER)
	var conversation := _talk(sim, healer)

	assert_array(conversation.available_approaches()).override_failure_message(
		"the player holds no secret, so blackmail must not be on the table"
	).not_contains([PlayerActions.Kind.BLACKMAIL])

	var reply := '{"intent":"approach","approach":"blackmail","about":"","fit":9}'
	var intent: Dictionary = IntentReader.parse_intent(
		reply, "I know what you did.", _options(conversation)
	)
	assert_int(intent["approach"]).override_failure_message(
		"a model naming an unavailable approach was allowed to use it"
	).is_not_equal(PlayerActions.Kind.BLACKMAIL)


func test_a_typed_line_moves_the_simulation() -> void:
	var sim := _sim()
	var healer: Agent = sim.agent_by_id(Roster.HEALER)
	var conversation := _talk(sim, healer)

	var before: float = healer.opinion_of_player()
	await conversation.say("Let me carry that for you, it looks heavy.")

	assert_float(healer.opinion_of_player()).override_failure_message(
		"typing a favour changed nothing in the simulation"
	).is_not_equal(before)


func test_garbage_from_the_model_falls_back_rather_than_breaking() -> void:
	var sim := _sim()
	var conversation := _talk(sim, sim.agent_by_id(Roster.HEALER))

	var intent: Dictionary = IntentReader.parse_intent(
		"I'm sorry, I can't help with that.", "There is gold in it for you.",
		_options(conversation)
	)
	assert_int(intent["approach"]).override_failure_message(
		"an unusable model reply lost the player's meaning entirely"
	).is_equal(PlayerActions.Kind.BRIBE)


func test_the_reader_always_answers_even_with_no_server() -> void:
	# A conversation awaits this signal. Any path that fails to emit hangs the
	# game permanently, which is the same deadlock the backend was bitten by.
	var reader: IntentReader = IntentReader.new(self, "definitely-not-a-model")
	reader.read("Hello there.", {"approaches": [], "people": []})
	var intent: Dictionary = await reader.intent_ready
	assert_bool(intent.has("kind")).is_true()


# --- what a well-judged line may and may not buy ---------------------------

func test_wording_is_neutral_by_default_so_the_menu_path_is_unchanged() -> void:
	assert_float(PlayerActions.delivery_of(PlayerActions.NEUTRAL_FIT)).is_equal(1.0)


func test_a_badly_judged_line_lands_softer_than_a_neutral_one() -> void:
	assert_float(PlayerActions.delivery_of(0.0)).is_less(1.0)


func test_no_wording_however_good_can_beat_the_simulation() -> void:
	# This is the guard on the whole design. Regard from repeating one approach
	# converges on raw / (1 - REPEAT_DECAY), so any delivery above 1.0 raises the
	# persuasion ceiling in proportion. Raise it and a rival's oldest friend
	# becomes winnable by charm, which retires Expose and the secrets with it.
	for fit in [0.5, 0.75, 0.9, 1.0]:
		assert_float(PlayerActions.delivery_of(fit)).override_failure_message(
			"fit %s bought a bonus, which lifts the persuasion ceiling" % fit
		).is_equal(1.0)


func test_putting_it_well_buys_candour_instead() -> void:
	# The reward for reading someone has to live somewhere that is not regard.
	var well: float = Conversation.candour_threshold(1.0)
	var neutral: float = Conversation.candour_threshold(PlayerActions.NEUTRAL_FIT)

	assert_float(neutral).is_equal(Conversation.OPINION_THRESHOLD)
	assert_float(well).override_failure_message(
		"a well-judged question was no more likely to be answered"
	).is_less(neutral)


func test_candour_never_opens_up_someone_who_despises_you() -> void:
	# The relief is small on purpose: it opens a door already ajar, it does not
	# pick the lock.
	assert_float(Conversation.candour_threshold(1.0)).is_greater(30.0)


func test_a_clumsy_offence_offends_more_rather_than_less() -> void:
	# Delivery multiplies the evaluation, and an offensive approach evaluates
	# negative. Applied without regard for the sign, a badly judged bribe was
	# scaled *towards zero* — so fumbling an approach became the safe way to
	# make it. Nothing in the simulation's own tests could see this.
	# Flattery is the Miller's trauma trigger, so this offends however it is put.
	var clumsy: Agent = _sim().agent_by_id(Roster.MILLER)
	var neutral: Agent = _sim().agent_by_id(Roster.MILLER)

	var clumsy_delta: float = clumsy.receive_approach(
		_flattery(), PlayerActions.delivery_of(0.0)
	)
	var neutral_delta: float = neutral.receive_approach(
		_flattery(), PlayerActions.delivery_of(PlayerActions.NEUTRAL_FIT)
	)

	assert_float(neutral_delta).is_less(0.0)
	assert_float(clumsy_delta).override_failure_message(
		"a badly judged offence hurt less than a neutral one, so fumbling was safest"
	).is_less(neutral_delta)


func _flattery() -> MemoryToken:
	return MemoryToken.new(
		Agent.PLAYER_ID, ActionCatalog.FLATTERED, Roster.MILLER, true, 2, &"", 0
	)


func test_a_rating_on_the_wrong_scale_is_not_read_as_an_insult() -> void:
	# qwen3:4b sometimes answers 0.8 meaning eight tenths, not eight. Divided by
	# ten that reads as 0.08 — the most offensive thing the player could say.
	var fractional: Dictionary = IntentReader.parse_intent(
		'{"intent":"smalltalk","approach":"","about":"","fit":0.8}',
		"Cold morning, isn't it.", {"approaches": [], "people": []}
	)
	assert_float(fractional["fit"]).override_failure_message(
		"a 0-1 rating was rescaled as though it were 0-10"
	).is_greater(Conversation.RUDENESS_FIT)

	# A plain integer still means what it says on the 0-10 scale.
	var whole: Dictionary = IntentReader.parse_intent(
		'{"intent":"smalltalk","approach":"","about":"","fit":8}',
		"Cold morning.", {"approaches": [], "people": []}
	)
	assert_float(whole["fit"]).is_equal_approx(0.8, 0.001)


func test_dull_small_talk_is_not_treated_as_rudeness() -> void:
	var sim := _sim()
	var conversation := _talk(sim, sim.agent_by_id(Roster.HEALER))
	var before: int = conversation.patience

	for i in 6:
		await conversation.say("Cold morning.")

	assert_int(conversation.patience).override_failure_message(
		"being boring cost patience, so small talk was quietly dangerous"
	).is_equal(before)


func test_a_line_asked_for_during_warm_up_is_not_lost_to_a_template() -> void:
	# Warm-up holds the single-flight lock through an eight second cold start,
	# so a player who walks straight up to somebody used to get a canned
	# greeting — the first impression of every character in the town.
	var backend: OllamaBackend = OllamaBackend.new(self, "definitely-not-a-model")
	backend.warm_up()

	var request := PromptBuilder.build(
		_sim().agent_by_id(Roster.HEALER), _sim(), "greeting"
	)
	backend.request_line(request)

	# Held, not answered from templates.
	assert_bool(backend._deferred.is_empty()).override_failure_message(
		"the request was answered immediately instead of waiting for warm-up"
	).is_false()

	# And it must still arrive, even though this model does not exist.
	var line: String = await backend.line_ready
	assert_str(line).is_not_empty()
