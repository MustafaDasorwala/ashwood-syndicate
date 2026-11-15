## Gossip Engine: the arithmetic that replaces LLM calls for background talk.
##
## These tests are the guarantee that the psychology documents actually drive
## behaviour — that the same claim genuinely lands differently on a zealot and
## on a cynic, rather than applying a hardcoded delta to both.
extends GdUnitTestSuite

const _T := Psyche.Trait
const _D := Psyche.Dark
const _F := Psyche.Foundation


func _agent(id: StringName, traits: Dictionary = {}, dark: Dictionary = {}, morality: Dictionary = {}) -> Agent:
	return Agent.new(Psyche.new(id, str(id), traits, dark, morality))


func _bribe(severity: int = 6, origin: StringName = &"") -> MemoryToken:
	return MemoryToken.new(&"player", ActionCatalog.BRIBED, &"blacksmith", true, severity, origin, 0)


# --- moral weighting -------------------------------------------------------

func test_a_fairness_zealot_condemns_a_bribe() -> void:
	var zealot := _agent(&"zealot", {}, {}, {_F.FAIRNESS: 1.0})
	assert_float(GossipEngine.evaluate(_bribe(), zealot)).is_less(0.0)


func test_the_same_bribe_offends_a_zealot_more_than_a_cynic() -> void:
	var zealot := _agent(&"zealot", {}, {}, {_F.FAIRNESS: 1.0, _F.AUTHORITY: 1.0})
	var cynic := _agent(&"cynic", {}, {}, {_F.FAIRNESS: 0.05, _F.AUTHORITY: 0.05})

	var zealot_delta: float = GossipEngine.evaluate(_bribe(), zealot)
	var cynic_delta: float = GossipEngine.evaluate(_bribe(), cynic)

	assert_float(zealot_delta).is_less(cynic_delta)


func test_severity_scales_the_reaction() -> void:
	var judge := _agent(&"judge", {}, {}, {_F.FAIRNESS: 1.0})
	var mild: float = GossipEngine.evaluate(_bribe(2), judge)
	var severe: float = GossipEngine.evaluate(_bribe(10), judge)
	assert_float(severe).is_less(mild)


func test_prosocial_acts_improve_standing() -> void:
	var healer := _agent(&"healer", {}, {}, {_F.CARE: 1.0})
	var helped := MemoryToken.new(&"player", ActionCatalog.HELPED, &"widow", true, 6, &"", 0)
	assert_float(GossipEngine.evaluate(helped, healer)).is_greater(0.0)


func test_a_killing_outrages_more_than_a_theft_at_equal_severity() -> void:
	var citizen := _agent(&"citizen", {}, {}, {_F.CARE: 0.8, _F.FAIRNESS: 0.8, _F.AUTHORITY: 0.8, _F.SANCTITY: 0.8})
	var theft := MemoryToken.new(&"player", ActionCatalog.STOLE_FROM, &"x", true, 7, &"", 0)
	var murder := MemoryToken.new(&"player", ActionCatalog.KILLED, &"x", true, 7, &"", 0)
	assert_float(GossipEngine.evaluate(murder, citizen)).is_less(GossipEngine.evaluate(theft, citizen))


# --- dark triad ------------------------------------------------------------

func test_a_manipulator_is_less_repelled_by_ruthlessness_than_an_honest_peer() -> void:
	var morality := {_F.FAIRNESS: 0.5, _F.CARE: 0.5}
	var honest := _agent(&"honest", {}, {}, morality)
	var manipulator := _agent(&"manip", {}, {_D.MACHIAVELLIANISM: 1.0, _D.PSYCHOPATHY: 0.8, _D.NARCISSISM: 0.8}, morality)

	assert_float(GossipEngine.evaluate(_bribe(), manipulator)).is_greater(
		GossipEngine.evaluate(_bribe(), honest)
	)


func test_a_low_morality_manipulator_admires_playing_dirty() -> void:
	# The design doc's Corrupt Merchant: reads a bribe as competence.
	var merchant := _agent(
		&"merchant", {},
		{_D.MACHIAVELLIANISM: 0.9, _D.NARCISSISM: 0.6, _D.PSYCHOPATHY: 0.5},
		{_F.FAIRNESS: 0.15, _F.AUTHORITY: 0.15}
	)
	assert_float(GossipEngine.evaluate(_bribe(), merchant)).is_greater(0.0)


# --- trust in the source ---------------------------------------------------

func test_a_rivals_word_is_discounted() -> void:
	var listener := _agent(&"listener", {}, {}, {_F.FAIRNESS: 1.0})
	listener.relationships.set_score(&"trusted", 100.0)
	listener.relationships.set_score(&"distrusted", 5.0)

	var from_friend: float = GossipEngine.evaluate(_bribe(6, &"trusted"), listener)
	var from_rival: float = GossipEngine.evaluate(_bribe(6, &"distrusted"), listener)

	assert_float(absf(from_rival)).is_less(absf(from_friend))


func test_firsthand_knowledge_is_undiscounted() -> void:
	var listener := _agent(&"listener", {}, {}, {_F.FAIRNESS: 1.0})
	listener.relationships.set_score(&"someone", RelationshipBook.NEUTRAL)

	var witnessed: float = GossipEngine.evaluate(_bribe(6, &""), listener)
	var hearsay: float = GossipEngine.evaluate(_bribe(6, &"someone"), listener)

	assert_float(absf(witnessed)).is_greater(absf(hearsay))


# --- attachments and trauma ------------------------------------------------

func test_harm_to_a_loved_one_hits_harder() -> void:
	var traits := {}
	var morality := {_F.CARE: 0.7}
	var stranger_case := _agent(&"a", traits, {}, morality)
	var attached_case := _agent(&"b", traits, {}, morality)
	attached_case.psyche.loyal_to = [&"blacksmith"]

	var threat := MemoryToken.new(&"player", ActionCatalog.THREATENED, &"blacksmith", true, 6, &"", 0)
	assert_float(GossipEngine.evaluate(threat, attached_case)).is_less(
		GossipEngine.evaluate(threat, stranger_case)
	)


func test_wrongdoing_by_a_loved_one_is_excused() -> void:
	var loyalist := _agent(&"loyalist", {}, {}, {_F.FAIRNESS: 0.9})
	loyalist.psyche.loyal_to = [&"player"]
	var neutral := _agent(&"neutral", {}, {}, {_F.FAIRNESS: 0.9})

	assert_float(GossipEngine.evaluate(_bribe(), loyalist)).is_greater(
		GossipEngine.evaluate(_bribe(), neutral)
	)


func test_trauma_trigger_produces_hostility_regardless_of_morality() -> void:
	# A cynic who would normally shrug off a betrayal, but it is their ghost.
	var scarred := _agent(&"scarred", {}, {}, {_F.LOYALTY: 0.05, _F.FAIRNESS: 0.05})
	scarred.psyche.trauma_trigger = ActionCatalog.BETRAYED

	var token := MemoryToken.new(&"player", ActionCatalog.BETRAYED, &"someone", true, 4, &"", 0)
	assert_float(GossipEngine.evaluate(token, scarred)).is_less(-1.0)


func test_an_npc_does_not_revise_their_self_image_on_hearsay() -> void:
	var subject := _agent(&"player", {}, {}, {_F.FAIRNESS: 1.0})
	assert_float(GossipEngine.evaluate(_bribe(), subject)).is_equal(0.0)


# --- cognitive bias --------------------------------------------------------

func test_confirmation_bias_amplifies_agreeable_evidence() -> void:
	var biased := _agent(&"biased", {}, {}, {_F.FAIRNESS: 0.8})
	biased.psyche.bias = Psyche.Bias.CONFIRMATION
	biased.relationships.set_score(&"player", 5.0)  # already hates them

	var neutral := _agent(&"neutral", {}, {}, {_F.FAIRNESS: 0.8})
	neutral.relationships.set_score(&"player", 5.0)

	assert_float(GossipEngine.evaluate(_bribe(), biased)).is_less(
		GossipEngine.evaluate(_bribe(), neutral)
	)


func test_sunk_cost_resists_bad_news_about_a_prior_commitment() -> void:
	var invested := _agent(&"invested", {}, {}, {_F.FAIRNESS: 0.8})
	invested.psyche.bias = Psyche.Bias.SUNK_COST
	invested.relationships.set_score(&"player", 90.0)

	var neutral := _agent(&"neutral", {}, {}, {_F.FAIRNESS: 0.8})
	neutral.relationships.set_score(&"player", 90.0)

	assert_float(GossipEngine.evaluate(_bribe(), invested)).is_greater(
		GossipEngine.evaluate(_bribe(), neutral)
	)


# --- bounds ----------------------------------------------------------------

func test_no_single_claim_can_decide_the_election() -> void:
	var extreme := _agent(
		&"extreme", {},
		{},
		{_F.CARE: 1.0, _F.FAIRNESS: 1.0, _F.LOYALTY: 1.0, _F.AUTHORITY: 1.0, _F.SANCTITY: 1.0}
	)
	extreme.psyche.loyal_to = [&"victim"]
	extreme.psyche.trauma_trigger = ActionCatalog.KILLED

	var worst := MemoryToken.new(&"player", ActionCatalog.KILLED, &"victim", true, 10, &"", 0)
	var delta: float = GossipEngine.evaluate(worst, extreme)

	assert_float(delta).is_greater_equal(-GossipEngine.MAX_SWING)
	assert_float(delta).is_less(0.0)


func test_learning_the_same_claim_twice_moves_the_needle_once() -> void:
	var listener := _agent(&"listener", {}, {}, {_F.FAIRNESS: 0.9})
	var first: float = listener.learn(_bribe(6, &"sheriff"))
	var second: float = listener.learn(_bribe(6, &"mayor"))

	assert_float(first).is_not_equal(0.0)
	assert_float(second).is_equal(0.0)


# --- selection and distortion ----------------------------------------------

func test_a_speaker_with_nothing_new_to_say_says_nothing() -> void:
	var speaker := _agent(&"speaker")
	var listener := _agent(&"listener")
	var token := _bribe()
	speaker.ledger.record(token)
	listener.ledger.record(token.duplicate_token())

	assert_object(GossipEngine.select_token(speaker, listener, SimRng.new(1))).is_null()


func test_nobody_badmouths_the_listener_to_their_face() -> void:
	var speaker := _agent(&"speaker")
	var listener := _agent(&"listener")
	speaker.ledger.record(MemoryToken.new(&"listener", ActionCatalog.STOLE_FROM, &"x", true, 8, &"", 0))

	assert_object(GossipEngine.select_token(speaker, listener, SimRng.new(1))).is_null()


func test_an_honest_speaker_never_distorts() -> void:
	var honest := _agent(&"honest", {}, {_D.MACHIAVELLIANISM: 0.0, _D.NARCISSISM: 0.0, _D.PSYCHOPATHY: 0.0})
	var token := _bribe()

	for seed_value in 20:
		var retold: MemoryToken = GossipEngine.distort(token, honest, 0, SimRng.new(seed_value))
		assert_bool(retold.truth_value).is_true()
		assert_str(str(retold.subject_id)).is_equal("player")
		assert_str(str(retold.origin_id)).is_equal("honest")


func test_a_manipulator_sometimes_rewrites_the_story() -> void:
	var liar := _agent(&"liar", {}, {_D.MACHIAVELLIANISM: 1.0, _D.NARCISSISM: 1.0, _D.PSYCHOPATHY: 1.0})
	liar.psyche.rivals = [&"mayor"]

	var distorted: int = 0
	for seed_value in 60:
		var retold: MemoryToken = GossipEngine.distort(_bribe(), liar, 0, SimRng.new(seed_value))
		if not retold.truth_value or retold.subject_id != &"player":
			distorted += 1

	assert_int(distorted).is_greater(0)
	assert_int(distorted).is_less(60)  # not every retelling is a lie


func test_distortion_is_reproducible_from_a_seed() -> void:
	var liar := _agent(&"liar", {}, {_D.MACHIAVELLIANISM: 1.0, _D.NARCISSISM: 1.0, _D.PSYCHOPATHY: 1.0})
	liar.psyche.rivals = [&"mayor"]

	var a: MemoryToken = GossipEngine.distort(_bribe(), liar, 0, SimRng.new(42))
	var b: MemoryToken = GossipEngine.distort(_bribe(), liar, 0, SimRng.new(42))

	assert_str(str(a.content_key())).is_equal(str(b.content_key()))


func test_a_gossip_reaches_for_the_most_scandalous_item() -> void:
	var gossip := _agent(&"gossip", {_T.EXTRAVERSION: 1.0})
	var listener := _agent(&"listener")
	gossip.ledger.record(MemoryToken.new(&"player", &"mundane", &"x", true, 1, &"", 0))
	gossip.ledger.record(MemoryToken.new(&"player", &"scandal", &"x", true, 10, &"", 0))

	var scandal_picks: int = 0
	for seed_value in 40:
		var picked: MemoryToken = GossipEngine.select_token(gossip, listener, SimRng.new(seed_value))
		if picked != null and picked.action == &"scandal":
			scandal_picks += 1

	assert_int(scandal_picks).is_greater(20)  # majority of the time
