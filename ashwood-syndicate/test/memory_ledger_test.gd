## Memory Ledger: dedup, capacity and significance ranking.
##
## Dedup is the property that keeps the 7-day sim stable — without it, a rumour
## echoing between ten NPCs re-applies its relationship hit every retelling.
extends GdUnitTestSuite


func _token(
	subject: StringName,
	action: StringName,
	severity: int = 5,
	origin: StringName = &"",
	truth: bool = true,
	day: int = 0
) -> MemoryToken:
	return MemoryToken.new(subject, action, &"victim", truth, severity, origin, day)


func test_records_a_new_belief() -> void:
	var ledger := MemoryLedger.new()
	assert_bool(ledger.record(_token(&"player", ActionCatalog.BRIBED))).is_true()
	assert_int(ledger.size()).is_equal(1)


func test_same_claim_from_a_different_mouth_is_not_new_information() -> void:
	var ledger := MemoryLedger.new()
	ledger.record(_token(&"player", ActionCatalog.BRIBED, 5, &"sheriff"))

	var repeat := _token(&"player", ActionCatalog.BRIBED, 5, &"mayor")
	assert_bool(ledger.record(repeat)).is_false()
	assert_int(ledger.size()).is_equal(1)


func test_a_denial_is_a_distinct_claim_from_the_accusation() -> void:
	var ledger := MemoryLedger.new()
	ledger.record(_token(&"player", ActionCatalog.BRIBED, 5, &"sheriff", true))
	assert_bool(ledger.record(_token(&"player", ActionCatalog.BRIBED, 5, &"mayor", false))).is_true()
	assert_int(ledger.size()).is_equal(2)


func test_witnessing_upgrades_a_belief_previously_held_as_hearsay() -> void:
	var ledger := MemoryLedger.new()
	ledger.record(_token(&"player", ActionCatalog.STOLE_FROM, 5, &"drunkard"))

	var firsthand := _token(&"player", ActionCatalog.STOLE_FROM, 5, &"")
	assert_bool(ledger.record(firsthand)).is_false()  # not new, but...

	var held: MemoryToken = ledger.get_token(firsthand.content_key())
	assert_bool(held.is_firsthand()).is_true()


func test_hearsay_does_not_downgrade_firsthand_knowledge() -> void:
	var ledger := MemoryLedger.new()
	ledger.record(_token(&"player", ActionCatalog.KILLED, 9, &""))
	ledger.record(_token(&"player", ActionCatalog.KILLED, 9, &"drunkard"))

	var held: MemoryToken = ledger.all()[0]
	assert_bool(held.is_firsthand()).is_true()


func test_about_filters_by_subject() -> void:
	var ledger := MemoryLedger.new()
	ledger.record(_token(&"player", ActionCatalog.BRIBED))
	ledger.record(_token(&"player", ActionCatalog.LIED_TO))
	ledger.record(_token(&"mayor", ActionCatalog.STOLE_FROM))

	assert_int(ledger.about(&"player").size()).is_equal(2)
	assert_int(ledger.about(&"mayor").size()).is_equal(1)
	assert_int(ledger.about(&"nobody").size()).is_equal(0)


func test_capacity_is_enforced() -> void:
	var ledger := MemoryLedger.new()
	for i in MemoryLedger.CAPACITY + 20:
		ledger.record(MemoryToken.new(&"player", StringName("act_%d" % i), &"t", true, 1 + i % 10, &"", 0))
	assert_int(ledger.size()).is_equal(MemoryLedger.CAPACITY)


func test_overflow_forgets_the_least_significant_belief_first() -> void:
	var ledger := MemoryLedger.new()
	var treason := MemoryToken.new(&"player", &"treason", &"town", true, 10, &"", 0)
	ledger.record(treason)

	# Flood with mundane claims until the ledger overflows.
	for i in MemoryLedger.CAPACITY + 10:
		ledger.record(MemoryToken.new(&"player", StringName("trivia_%d" % i), &"t", true, 1, &"", 0))

	assert_bool(ledger.knows(treason)).is_true()
	assert_int(ledger.size()).is_equal(MemoryLedger.CAPACITY)


func test_most_significant_ranks_severity_then_recency() -> void:
	var ledger := MemoryLedger.new()
	ledger.record(MemoryToken.new(&"player", &"a", &"t", true, 3, &"", 1))
	ledger.record(MemoryToken.new(&"player", &"b", &"t", true, 9, &"", 0))
	ledger.record(MemoryToken.new(&"player", &"c", &"t", true, 9, &"", 5))

	var top: Array[MemoryToken] = ledger.most_significant(2)
	assert_int(top.size()).is_equal(2)
	assert_str(str(top[0].action)).is_equal("c")  # severity 9, most recent
	assert_str(str(top[1].action)).is_equal("b")  # severity 9, older


func test_most_significant_bounds_the_llm_prompt_budget() -> void:
	var ledger := MemoryLedger.new()
	for i in 30:
		ledger.record(MemoryToken.new(&"player", StringName("act_%d" % i), &"t", true, 5, &"", 0))
	assert_int(ledger.most_significant(5).size()).is_equal(5)
	assert_int(ledger.most_significant(0).size()).is_equal(0)
