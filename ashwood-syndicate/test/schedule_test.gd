## Daily schedule lookup, including the wrap around midnight.
extends GdUnitTestSuite

const _Z := TownGrid.Zone


func test_an_empty_schedule_keeps_people_home() -> void:
	assert_int(Schedule.new().zone_at(12)).is_equal(_Z.RESIDENCES)


func test_an_entry_holds_until_the_next_one() -> void:
	var schedule := Schedule.new([
		{"hour": 8, "zone": _Z.MARKET},
		{"hour": 18, "zone": _Z.TAVERN},
	])
	assert_int(schedule.zone_at(8)).is_equal(_Z.MARKET)
	assert_int(schedule.zone_at(13)).is_equal(_Z.MARKET)
	assert_int(schedule.zone_at(17)).is_equal(_Z.MARKET)
	assert_int(schedule.zone_at(18)).is_equal(_Z.TAVERN)


func test_hours_before_the_first_entry_wrap_to_the_previous_night() -> void:
	# "Home from 22:00" has to still apply at 02:00.
	var schedule := Schedule.new([
		{"hour": 8, "zone": _Z.MARKET},
		{"hour": 22, "zone": _Z.RESIDENCES},
	])
	assert_int(schedule.zone_at(2)).is_equal(_Z.RESIDENCES)
	assert_int(schedule.zone_at(0)).is_equal(_Z.RESIDENCES)
	assert_int(schedule.zone_at(7)).is_equal(_Z.RESIDENCES)


func test_entries_are_order_independent() -> void:
	var forward := Schedule.new([
		{"hour": 6, "zone": _Z.RESIDENCES},
		{"hour": 14, "zone": _Z.WOODS},
	])
	var backward := Schedule.new([
		{"hour": 14, "zone": _Z.WOODS},
		{"hour": 6, "zone": _Z.RESIDENCES},
	])
	for hour in 24:
		assert_int(forward.zone_at(hour)).is_equal(backward.zone_at(hour))


func test_re_adding_an_hour_replaces_it() -> void:
	var schedule := Schedule.new([{"hour": 9, "zone": _Z.MARKET}])
	schedule.add(9, _Z.WOODS)
	assert_int(schedule.size()).is_equal(1)
	assert_int(schedule.zone_at(9)).is_equal(_Z.WOODS)


func test_out_of_range_hours_normalise() -> void:
	var schedule := Schedule.new([{"hour": 8, "zone": _Z.MARKET}])
	assert_int(schedule.zone_at(32)).is_equal(schedule.zone_at(8))
	assert_int(schedule.zone_at(-1)).is_equal(schedule.zone_at(23))


func test_the_default_routine_covers_the_whole_day() -> void:
	var schedule := Schedule.default_schedule()
	for hour in 24:
		assert_int(schedule.zone_at(hour)).is_greater_equal(0)


func test_a_workplace_routine_actually_uses_that_workplace() -> void:
	var schedule := Schedule.for_workplace(_Z.SHERIFF)
	assert_int(schedule.zone_at(9)).is_equal(_Z.SHERIFF)
	assert_int(schedule.zone_at(16)).is_equal(_Z.SHERIFF)
	assert_int(schedule.zone_at(20)).is_equal(_Z.TAVERN)
	assert_int(schedule.zone_at(23)).is_equal(_Z.RESIDENCES)
