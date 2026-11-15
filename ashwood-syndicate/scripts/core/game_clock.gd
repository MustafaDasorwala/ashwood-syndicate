extends Node

## Autoload. The simulation's authoritative time source.
##
## Registered as `GameClock`. Per the GDD: 1 real minute = 1 in-game hour, a
## 24-hour cycle, and a hard 7-day deadline.
##
## The design draft ran the clock straight off frame delta, which makes a full
## playthrough 168 unskippable real minutes and makes any test of Day 7 behaviour
## impossible. Instead all advancement goes through `advance()`, which `_process`
## merely feeds. Tests call `advance()` (or `skip_hours()`) directly and run the
## entire week in milliseconds.

## Real seconds of unscaled time per in-game hour.
const REAL_SECONDS_PER_HOUR := 60.0

const HOURS_PER_DAY := 24
const TOTAL_DAYS := 7

## Hour the player's day starts on a fresh game.
const START_HOUR := 6

var day: int = 0
var hour: int = START_HOUR

## Multiplier on real time. 1.0 is the GDD's baseline; raise it to fast-forward.
## Set to 0.0 to pause, which is what the LLM bridge does while awaiting a reply.
var time_scale: float = 1.0

## Set once the 7-day limit expires. The clock stops advancing.
var is_over: bool = false

## Fractional progress through the current hour, 0.0..1.0. Drives smooth NPC
## movement between the discrete hourly schedule slots.
var hour_progress: float = 0.0

var _accumulator: float = 0.0


func _process(delta: float) -> void:
	if is_over or time_scale <= 0.0:
		return
	advance(delta * time_scale)


## Advances the clock by `real_seconds` of scaled time, emitting one
## `hour_changed` per hour crossed.
##
## Safe to call with large values: a 10-hour jump emits 10 hour signals in order
## rather than skipping the intervening schedule slots.
func advance(real_seconds: float) -> void:
	if is_over or real_seconds <= 0.0:
		return

	_accumulator += real_seconds
	while _accumulator >= REAL_SECONDS_PER_HOUR:
		_accumulator -= REAL_SECONDS_PER_HOUR
		_tick_hour()
		if is_over:
			_accumulator = 0.0
			break

	hour_progress = _accumulator / REAL_SECONDS_PER_HOUR


## Jumps forward whole in-game hours. Equivalent to advancing real time, but
## reads clearly in tests and debug tooling.
func skip_hours(count: int) -> void:
	advance(float(count) * REAL_SECONDS_PER_HOUR)


## Total in-game hours since the game began. The simulation's monotonic index.
func total_hours() -> int:
	return day * HOURS_PER_DAY + hour


## Hours remaining before the vote is called.
func hours_remaining() -> int:
	return maxi(TOTAL_DAYS * HOURS_PER_DAY - total_hours(), 0)


func is_night() -> bool:
	return hour >= 22 or hour < 6


func reset() -> void:
	day = 0
	hour = START_HOUR
	is_over = false
	hour_progress = 0.0
	_accumulator = 0.0


func _tick_hour() -> void:
	hour += 1
	if hour >= HOURS_PER_DAY:
		hour = 0
		day += 1
		if day >= TOTAL_DAYS:
			# The deadline lands the instant Day 7 would begin. Clamp so the
			# displayed date never reads past the end of the game.
			day = TOTAL_DAYS - 1
			hour = HOURS_PER_DAY - 1
			is_over = true
			EventBus.deadline_reached.emit()
			return
		EventBus.day_changed.emit(day)

	EventBus.hour_changed.emit(day, hour)
