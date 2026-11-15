## Time system: hour/day rollover and the hard 7-day deadline.
extends GdUnitTestSuite


func before_test() -> void:
	# The clock is an autoload with a live _process. Freeze it so only the
	# explicit advances in these tests move time.
	GameClock.time_scale = 0.0
	GameClock.reset()


func after_test() -> void:
	GameClock.reset()
	GameClock.time_scale = 1.0


func test_starts_on_day_zero_at_dawn() -> void:
	assert_int(GameClock.day).is_equal(0)
	assert_int(GameClock.hour).is_equal(GameClock.START_HOUR)
	assert_bool(GameClock.is_over).is_false()


func test_one_real_minute_is_one_game_hour() -> void:
	GameClock.advance(GameClock.REAL_SECONDS_PER_HOUR)
	assert_int(GameClock.hour).is_equal(GameClock.START_HOUR + 1)
	assert_int(GameClock.day).is_equal(0)


func test_partial_hour_accumulates_without_ticking() -> void:
	GameClock.advance(GameClock.REAL_SECONDS_PER_HOUR * 0.5)
	assert_int(GameClock.hour).is_equal(GameClock.START_HOUR)
	assert_float(GameClock.hour_progress).is_equal_approx(0.5, 0.001)

	GameClock.advance(GameClock.REAL_SECONDS_PER_HOUR * 0.5)
	assert_int(GameClock.hour).is_equal(GameClock.START_HOUR + 1)


func test_rolls_over_into_next_day_at_midnight() -> void:
	GameClock.skip_hours(GameClock.HOURS_PER_DAY - GameClock.START_HOUR)
	assert_int(GameClock.day).is_equal(1)
	assert_int(GameClock.hour).is_equal(0)


func test_large_jump_emits_every_intervening_hour() -> void:
	# Schedule slots must not be skipped when the clock is fast-forwarded.
	var seen: Array[int] = []
	var handler := func(_day: int, hour: int) -> void: seen.append(hour)
	EventBus.hour_changed.connect(handler)

	GameClock.skip_hours(5)
	EventBus.hour_changed.disconnect(handler)

	assert_array(seen).is_equal([7, 8, 9, 10, 11])


func test_deadline_fires_at_end_of_seventh_day() -> void:
	var fired: Array[bool] = []
	var handler := func() -> void: fired.append(true)
	EventBus.deadline_reached.connect(handler)

	GameClock.skip_hours(GameClock.TOTAL_DAYS * GameClock.HOURS_PER_DAY)
	EventBus.deadline_reached.disconnect(handler)

	assert_int(fired.size()).is_equal(1)
	assert_bool(GameClock.is_over).is_true()


func test_clock_stops_after_deadline() -> void:
	GameClock.skip_hours(GameClock.TOTAL_DAYS * GameClock.HOURS_PER_DAY)
	var frozen_day: int = GameClock.day
	var frozen_hour: int = GameClock.hour

	GameClock.skip_hours(10)

	assert_int(GameClock.day).is_equal(frozen_day)
	assert_int(GameClock.hour).is_equal(frozen_hour)


func test_displayed_date_never_reads_past_the_final_day() -> void:
	GameClock.skip_hours(GameClock.TOTAL_DAYS * GameClock.HOURS_PER_DAY)
	assert_int(GameClock.day).is_less_equal(GameClock.TOTAL_DAYS - 1)


func test_hours_remaining_counts_down_to_zero() -> void:
	var at_start: int = GameClock.hours_remaining()
	assert_int(at_start).is_equal(GameClock.TOTAL_DAYS * GameClock.HOURS_PER_DAY - GameClock.START_HOUR)

	GameClock.skip_hours(24)
	assert_int(GameClock.hours_remaining()).is_equal(at_start - 24)

	GameClock.skip_hours(1000)
	assert_int(GameClock.hours_remaining()).is_greater_equal(0)


func test_night_spans_midnight() -> void:
	GameClock.skip_hours(16)  # 22:00
	assert_bool(GameClock.is_night()).is_true()

	GameClock.skip_hours(4)   # 02:00
	assert_bool(GameClock.is_night()).is_true()

	GameClock.skip_hours(6)   # 08:00
	assert_bool(GameClock.is_night()).is_false()
