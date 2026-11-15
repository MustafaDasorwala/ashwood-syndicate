class_name Schedule
extends RefCounted

## An NPC's daily routine: which zone they intend to occupy at each hour.
##
## Stored sparsely as "from this hour onward, be here" entries. Looking up any
## hour walks back to the most recent entry, so a full 24-slot table is never
## needed and a routine reads the way a person would describe it.

## { hour: int, zone: TownGrid.Zone }, kept sorted by hour.
var _entries: Array[Dictionary] = []


func _init(entries: Array = []) -> void:
	for entry in entries:
		add(entry["hour"], entry["zone"])


## Registers "at `hour`, go to `zone`". Re-adding an hour replaces it.
func add(hour: int, zone: int) -> Schedule:
	var normalised: int = posmod(hour, GameClock.HOURS_PER_DAY)
	for i in _entries.size():
		if _entries[i]["hour"] == normalised:
			_entries[i]["zone"] = zone
			return self
	_entries.append({"hour": normalised, "zone": zone})
	_entries.sort_custom(func(a, b): return a["hour"] < b["hour"])
	return self


## Where this NPC should be at `hour`.
##
## Wraps around midnight: an hour earlier than the first entry resolves to the
## last entry of the previous day, which is how "sleep from 22:00" covers 02:00.
func zone_at(hour: int) -> int:
	if _entries.is_empty():
		return TownGrid.Zone.RESIDENCES

	var normalised: int = posmod(hour, GameClock.HOURS_PER_DAY)
	var chosen: Dictionary = _entries[_entries.size() - 1]
	for entry in _entries:
		if entry["hour"] <= normalised:
			chosen = entry
		else:
			break
	return chosen["zone"]


func entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


func size() -> int:
	return _entries.size()


## The townsfolk baseline from the GDD: work by day, tavern in the evening,
## home at night.
static func default_schedule() -> Schedule:
	return Schedule.new([
		{"hour": 6, "zone": TownGrid.Zone.RESIDENCES},
		{"hour": 8, "zone": TownGrid.Zone.MARKET},
		{"hour": 18, "zone": TownGrid.Zone.TAVERN},
		{"hour": 22, "zone": TownGrid.Zone.RESIDENCES},
	])


## A routine built around a primary workplace, so the ten NPCs do not all stand
## in the same square all day.
static func for_workplace(work_zone: int) -> Schedule:
	return Schedule.new([
		{"hour": 6, "zone": TownGrid.Zone.RESIDENCES},
		{"hour": 8, "zone": work_zone},
		{"hour": 13, "zone": TownGrid.Zone.MARKET},
		{"hour": 15, "zone": work_zone},
		{"hour": 19, "zone": TownGrid.Zone.TAVERN},
		{"hour": 22, "zone": TownGrid.Zone.RESIDENCES},
	])
