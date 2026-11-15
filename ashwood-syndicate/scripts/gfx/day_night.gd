class_name DayNight
extends CanvasModulate

## Tints the whole town by the hour.
##
## Placeholder lighting, but it does the two things that matter: it makes time
## legible without reading the clock, and it makes the small hours feel like a
## reason to be careful. Trysts happen at twenty-three hundred.

## Hour -> tint. Interpolated between the nearest two entries, so dawn and dusk
## slide rather than snap.
const KEYFRAMES := {
	0: Color(0.30, 0.34, 0.52),
	5: Color(0.42, 0.42, 0.58),
	7: Color(0.86, 0.78, 0.72),
	9: Color(1.00, 0.99, 0.96),
	16: Color(1.00, 0.96, 0.88),
	19: Color(0.92, 0.72, 0.60),
	21: Color(0.52, 0.48, 0.62),
	23: Color(0.34, 0.36, 0.54),
}


func _ready() -> void:
	color = tint_for(GameClock.hour, 0.0)
	EventBus.hour_changed.connect(_on_hour_changed)


func _process(_delta: float) -> void:
	# Interpolating within the hour keeps sunrise smooth at high time scales,
	# where a per-hour step would strobe.
	color = tint_for(GameClock.hour, GameClock.hour_progress)


func _on_hour_changed(_day: int, hour: int) -> void:
	color = tint_for(hour, 0.0)


## The tint at `hour` plus `progress` of the way to the next one.
static func tint_for(hour: int, progress: float) -> Color:
	var keys: Array = KEYFRAMES.keys()
	keys.sort()

	var before: int = keys[keys.size() - 1]
	var after: int = keys[0]
	for key in keys:
		if key <= hour:
			before = key
	for key in keys:
		if key > hour:
			after = key
			break

	var span: float = float(posmod(after - before, GameClock.HOURS_PER_DAY))
	if span <= 0.0:
		return KEYFRAMES[before]

	var elapsed: float = float(posmod(hour - before, GameClock.HOURS_PER_DAY)) + clampf(progress, 0.0, 1.0)
	return (KEYFRAMES[before] as Color).lerp(KEYFRAMES[after], clampf(elapsed / span, 0.0, 1.0))


## Whether lit windows should be showing.
static func is_lamplight(hour: int) -> bool:
	return hour >= 18 or hour < 7
