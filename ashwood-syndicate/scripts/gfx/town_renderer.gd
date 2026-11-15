class_name TownRenderer
extends Node2D

## Draws the town: ground, paths, buildings, trees.
##
## Still entirely procedural — no imported assets — but shaped like a place
## rather than five coloured rectangles. Everything is generated from the same
## zone rectangles the simulation uses, so swapping in real tilesets later means
## replacing these draw calls, not rearranging the town.
##
## Split into two layers because they invalidate at different rates: the ground
## and buildings never change, while lit windows follow the clock.

var grid: TownGrid

var _font: Font
var _lit: bool = false


func _ready() -> void:
	_font = ThemeDB.fallback_font
	z_index = -10
	_lit = DayNight.is_lamplight(GameClock.hour)
	EventBus.hour_changed.connect(_on_hour_changed)


func setup(p_grid: TownGrid) -> void:
	grid = p_grid
	queue_redraw()


func _on_hour_changed(_day: int, hour: int) -> void:
	var lit: bool = DayNight.is_lamplight(hour)
	if lit != _lit:
		_lit = lit
		queue_redraw()


func _draw() -> void:
	if grid == null:
		return

	_draw_ground()
	_draw_walls()
	for zone in TownGrid.ZONE_RECTS:
		_draw_zone(zone)


## Dirt, with stable per-tile variation so the ground is not a flat colour.
##
## The pattern is derived from tile coordinates rather than a random source, so
## it is identical every run and never needs storing.
func _draw_ground() -> void:
	var size := Vector2(TownGrid.WIDTH, TownGrid.HEIGHT) * ProcArt.TILE_SIZE
	draw_rect(Rect2(Vector2.ZERO, size), ProcArt.STREET_COLOR)

	for x in TownGrid.WIDTH:
		for y in TownGrid.HEIGHT:
			# Cheap deterministic hash; the pattern only needs to look unplanned.
			var noise: int = (x * 73856093) ^ (y * 19349663)
			var shade: float = float(absi(noise) % 4) * 0.006
			if shade <= 0.0:
				continue
			draw_rect(
				Rect2(Vector2(x, y) * ProcArt.TILE_SIZE, Vector2.ONE * ProcArt.TILE_SIZE),
				ProcArt.STREET_COLOR.lightened(shade)
			)


func _draw_zone(zone: int) -> void:
	var rect: Rect2 = ProcArt.rect_to_px(TownGrid.zone_rect(zone))
	match zone:
		TownGrid.Zone.WOODS:
			_draw_woods(rect)
		TownGrid.Zone.MARKET:
			_draw_market(rect)
		_:
			_draw_building(rect, ProcArt.zone_color(zone))
	_draw_label(zone, rect)


## A building seen from above-front: floor, roof slab, a lit face with door and
## windows. Crude, but it reads as a structure at a glance.
func _draw_building(rect: Rect2, base: Color) -> void:
	draw_rect(rect, base.darkened(0.35))

	var roof := Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.62))
	draw_rect(roof, base)
	draw_rect(Rect2(roof.position, Vector2(roof.size.x, 5.0)), base.lightened(0.22))
	draw_rect(roof, base.darkened(0.55), false, 2.0)

	# The front face below the roofline.
	var face := Rect2(
		Vector2(rect.position.x, roof.end.y),
		Vector2(rect.size.x, rect.size.y - roof.size.y)
	)
	draw_rect(face, base.darkened(0.22))
	draw_rect(face, base.darkened(0.6), false, 1.0)

	_draw_door(face, base)
	_draw_windows(face, base)


func _draw_door(face: Rect2, base: Color) -> void:
	var width: float = 14.0
	var height: float = minf(face.size.y * 0.7, 20.0)
	var door := Rect2(
		Vector2(face.position.x + face.size.x * 0.5 - width * 0.5, face.end.y - height),
		Vector2(width, height)
	)
	draw_rect(door, base.darkened(0.7))
	draw_rect(door, base.lightened(0.1), false, 1.0)


func _draw_windows(face: Rect2, base: Color) -> void:
	var glass: Color = Color("ffd98a") if _lit else base.darkened(0.62)
	var size := Vector2(10.0, 9.0)
	var count: int = maxi(int(face.size.x / 42.0), 1)

	for i in count:
		var spacing: float = face.size.x / float(count + 1)
		for side in [-1.0, 1.0]:
			var centre: float = face.position.x + spacing * float(i + 1) + side * 26.0
			if centre < face.position.x + 6.0 or centre + size.x > face.end.x - 6.0:
				continue
			var pane := Rect2(Vector2(centre, face.position.y + 8.0), size)
			draw_rect(pane, glass)
			draw_rect(pane, base.darkened(0.75), false, 1.0)
			if _lit:
				# A soft spill so lit windows read at night without a light node.
				draw_rect(pane.grow(3.0), Color(1.0, 0.85, 0.5, 0.10))


## Market stalls: awnings on posts, no walls.
func _draw_market(rect: Rect2) -> void:
	draw_rect(rect, ProcArt.zone_color(TownGrid.Zone.MARKET).darkened(0.45))

	var stalls: int = 4
	var width: float = rect.size.x / float(stalls + 1)
	for i in stalls:
		var origin := Vector2(rect.position.x + width * (float(i) + 0.5), rect.position.y + 22.0)
		var awning := Rect2(origin, Vector2(width * 0.8, 16.0))
		var stripe: Color = ProcArt.zone_color(TownGrid.Zone.MARKET).lightened(0.25 if i % 2 == 0 else 0.05)
		draw_rect(awning, stripe)
		draw_rect(awning, stripe.darkened(0.5), false, 1.0)
		# Posts.
		for side in [0.0, awning.size.x - 2.0]:
			draw_rect(Rect2(origin + Vector2(side, 16.0), Vector2(2.0, 20.0)), Color("3b2f22"))


## Trees, placed deterministically so the wood is the same wood every run.
func _draw_woods(rect: Rect2) -> void:
	draw_rect(rect, ProcArt.zone_color(TownGrid.Zone.WOODS).darkened(0.3))

	var base: Color = ProcArt.zone_color(TownGrid.Zone.WOODS)
	var columns: int = int(rect.size.x / 34.0)
	var rows: int = maxi(int(rect.size.y / 30.0), 1)

	for i in columns:
		for j in rows:
			var noise: int = absi((i * 73856093) ^ (j * 83492791))
			# Wide jitter, or the wood reads as an orchard planted in rows.
			var jitter := Vector2(float(noise % 27) - 13.0, float((noise / 27) % 21) - 10.0)
			var centre: Vector2 = rect.position + Vector2(
				20.0 + float(i) * 34.0, 22.0 + float(j) * 30.0
			) + jitter
			if not rect.grow(-10.0).has_point(centre):
				continue
			draw_rect(Rect2(centre + Vector2(-2.0, 4.0), Vector2(4.0, 10.0)), Color("3a2b1d"))
			draw_circle(centre + Vector2(0, 2), 10.0, Color(0, 0, 0, 0.25))
			draw_circle(centre, 9.0, base.lightened(0.12 if noise % 2 == 0 else 0.0))


func _draw_label(zone: int, rect: Rect2) -> void:
	var label: String = TownGrid.zone_name(zone)
	var size: Vector2 = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var origin: Vector2 = rect.position + Vector2((rect.size.x - size.x) * 0.5, -6.0)

	draw_string(_font, origin + Vector2.ONE, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.75))
	draw_string(_font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.92, 0.85, 0.9))


func _draw_walls() -> void:
	for wall in TownGrid.WALLS:
		var rect: Rect2 = ProcArt.rect_to_px(wall)
		draw_rect(rect, Color("2a2118"))
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3.0)), Color("3c3024"))
		draw_rect(rect, Color("17110c"), false, 1.0)
