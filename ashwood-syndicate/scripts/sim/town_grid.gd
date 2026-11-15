class_name TownGrid
extends RefCounted

## The physical town: a 2D tile grid partitioned into five named zones, plus
## A* pathfinding across it.
##
## Zones are rectangles rather than arbitrary shapes because every gameplay
## question the sim asks is "who is in the tavern with me?" — a fast
## point-in-rect test that runs 45 times an hour for a 10-NPC town.

enum Zone { TAVERN, MARKET, RESIDENCES, SHERIFF, WOODS }

const WIDTH := 40
const HEIGHT := 30

## Tiles that cannot be walked through, carving the town into corridors so
## pathfinding produces visibly different routes between zones.
const WALLS: Array[Rect2i] = [
	Rect2i(18, 0, 2, 9),
	Rect2i(18, 13, 2, 8),
	Rect2i(0, 20, 14, 2),
	Rect2i(24, 20, 12, 2),
]

## Zone -> Rect2i footprint in tile coordinates.
const ZONE_RECTS := {
	Zone.TAVERN: Rect2i(2, 2, 14, 8),
	Zone.MARKET: Rect2i(22, 2, 16, 8),
	Zone.RESIDENCES: Rect2i(2, 12, 14, 7),
	Zone.SHERIFF: Rect2i(22, 12, 10, 7),
	Zone.WOODS: Rect2i(4, 23, 32, 6),
}

const ZONE_NAMES := {
	Zone.TAVERN: "The Ashwood Tavern",
	Zone.MARKET: "Market Square",
	Zone.RESIDENCES: "Residences",
	Zone.SHERIFF: "Sheriff's Office",
	Zone.WOODS: "The Woods",
}

var _astar: AStarGrid2D


func _init() -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, WIDTH, HEIGHT)
	_astar.cell_size = Vector2.ONE
	# Diagonals only when both orthogonal neighbours are open, so NPCs never
	# clip through a wall corner.
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()

	for wall in WALLS:
		for x in range(wall.position.x, wall.end.x):
			for y in range(wall.position.y, wall.end.y):
				if is_in_bounds(Vector2i(x, y)):
					_astar.set_point_solid(Vector2i(x, y), true)


static func zone_name(zone: int) -> String:
	return ZONE_NAMES.get(zone, "Nowhere")


static func is_in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < WIDTH and tile.y < HEIGHT


static func zone_rect(zone: int) -> Rect2i:
	return ZONE_RECTS.get(zone, Rect2i())


## The zone containing `tile`, or -1 for the streets between zones.
static func zone_at(tile: Vector2i) -> int:
	for zone in ZONE_RECTS:
		if (ZONE_RECTS[zone] as Rect2i).has_point(tile):
			return zone
	return -1


## The tile an NPC heads for when told to go to a zone: its centre.
static func zone_center(zone: int) -> Vector2i:
	var rect: Rect2i = zone_rect(zone)
	return rect.position + rect.size / 2


## Distinct standing positions every zone must provide.
##
## Must exceed the town's population, since the whole cast can end up in the
## tavern on the same evening. A fixed tile stride cannot guarantee this — the
## Sheriff's Office is small enough that a 3x2 stride yielded only four spots —
## so the layout below divides whatever space a zone has into this many cells.
const SLOT_CAPACITY := 12

## Tiles of vertical clearance aimed for between standing spots.
##
## This is a rendering fact leaking into the layout, and it earns its place: an
## inhabitant is drawn two tiles tall from the feet up, so a one-tile row stride
## puts every back row's head inside the row in front. Zones too short to afford
## it fall back to what they have.
const ROW_SPACING := 2


## A personal standing spot inside a zone, so a crowd spreads across the room
## instead of every inhabitant occupying the same tile.
##
## Deterministic in `index`, which keeps each NPC in a consistent spot rather
## than shuffling on every arrival.
static func zone_slot(zone: int, index: int) -> Vector2i:
	var rect: Rect2i = zone_rect(zone)
	# Inset by one tile so nobody stands on the zone's own border.
	var inner := Rect2i(rect.position + Vector2i.ONE, rect.size - Vector2i(2, 2))
	if inner.size.x <= 0 or inner.size.y <= 0:
		return zone_center(zone)

	# Rows first, and as few of them as the zone allows: a villager sprite is two
	# tiles tall, so neighbours one tile apart vertically bury each other. Spare
	# capacity goes sideways instead, where a body is only one tile wide.
	var rows: int = clampi(inner.size.y / ROW_SPACING, 1, SLOT_CAPACITY)
	var columns: int = clampi(int(ceil(float(SLOT_CAPACITY) / float(rows))), 1, inner.size.x)
	# A narrow zone may not have offered enough columns; take the rows back.
	rows = clampi(int(ceil(float(SLOT_CAPACITY) / float(columns))), 1, inner.size.y)

	var step := Vector2i(inner.size.x / columns, inner.size.y / rows)
	var safe_index: int = maxi(index, 0) % (columns * rows)
	var cell := Vector2i(safe_index % columns, safe_index / columns)

	# Centre each occupant within their cell so nobody hugs a wall.
	return inner.position + cell * step + step / 2


func is_walkable(tile: Vector2i) -> bool:
	return is_in_bounds(tile) and not _astar.is_point_solid(tile)


## A* path from `from` to `to`, inclusive of both endpoints.
##
## Returns an empty array when either endpoint is out of bounds or no route
## exists. Callers treat empty as "stay put" rather than as an error.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not is_in_bounds(from) or not is_in_bounds(to):
		return empty
	if _astar.is_point_solid(from) or _astar.is_point_solid(to):
		return empty

	var raw: PackedVector2Array = _astar.get_point_path(from, to)
	var out: Array[Vector2i] = []
	for point in raw:
		out.append(Vector2i(roundi(point.x), roundi(point.y)))
	return out


## Path from wherever the NPC stands to the centre of a zone.
func path_to_zone(from: Vector2i, zone: int) -> Array[Vector2i]:
	return find_path(from, zone_center(zone))


## Path to this NPC's personal spot within a zone.
func path_to_slot(from: Vector2i, zone: int, slot_index: int) -> Array[Vector2i]:
	var destination: Vector2i = zone_slot(zone, slot_index)
	if not is_walkable(destination):
		destination = zone_center(zone)
	return find_path(from, destination)
