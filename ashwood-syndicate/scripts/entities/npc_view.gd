class_name NpcView
extends Node2D

## The visible body of one Agent.
##
## Holds no simulation state of its own — it reads the Agent and walks toward
## wherever the sim has decided that Agent should be. Deleting this node would
## leave the simulation fully functional, which is the property that lets the
## whole town be tested headless.

## Tiles crossed per second at 1x time scale. Sized so a cross-town walk takes a
## meaningful fraction of an in-game hour without ever arriving late.
const BASE_SPEED := 3.0

## Radius of the ring drawn on the ground at the NPC's feet, in pixels. The
## body itself is a sprite; this is the footprint the status rings ride on.
const BODY_RADIUS := 5.0

## Height of the drawn sprite in world pixels, used to place the name label
## clear of the head.
const BODY_HEIGHT := 32.0

var agent: Agent
var grid: TownGrid

## Position in tile space, fractional between tiles.
var tile_position: Vector2 = Vector2.ZERO

## This NPC's personal standing spot within whatever zone they are in. Without
## it the whole town converges on the zone centre and stacks into one dot.
var slot_index: int = 0

## Highlighted as the player's current target.
var is_selected: bool = false

var _path: Array[Vector2i] = []
var _path_index: int = 0
var _last_zone: int = -1
var _font: Font
var _sprite: CharacterSprite

## Tile position at the end of the previous frame. Facing is read back out of
## actual movement rather than tracked separately, so the body can never end up
## walking one way and looking another.
var _previous_tile_position: Vector2 = Vector2.ZERO


func setup(p_agent: Agent, p_grid: TownGrid, p_slot_index: int = 0) -> void:
	agent = p_agent
	grid = p_grid
	slot_index = p_slot_index
	tile_position = Vector2(TownGrid.zone_slot(agent.current_zone, slot_index))
	_previous_tile_position = tile_position
	_last_zone = agent.current_zone
	position = ProcArt.tile_to_px(tile_position)
	_tint_sprite()


func _ready() -> void:
	_font = ThemeDB.fallback_font
	z_index = 5

	_sprite = CharacterSprite.new()
	add_child(_sprite)
	_tint_sprite()


## Safe to call before or after the sprite exists: `setup` and `_ready` arrive
## in either order depending on whether the caller adds the node first.
func _tint_sprite() -> void:
	if _sprite == null or agent == null:
		return
	# `slot_index` is the inhabitant's position in the roster, which is also
	# what picks their standing spot. Keying the tunic on it rather than on the
	# id is what guarantees no two of the cast are dressed alike.
	_sprite.set_tint(ProcArt.tunic_color(slot_index))


func _process(delta: float) -> void:
	if agent == null or grid == null:
		return

	if agent.current_zone != _last_zone:
		_last_zone = agent.current_zone
		_repath()

	_advance_along_path(delta)
	position = ProcArt.tile_to_px(tile_position)
	_drive_sprite(delta)
	queue_redraw()


func _drive_sprite(delta: float) -> void:
	if _sprite == null:
		return

	var travelled: Vector2 = tile_position - _previous_tile_position
	_previous_tile_position = tile_position

	# A tolerance rather than an exact zero: floating point leaves a hair of
	# movement on an NPC who has arrived, which would keep their legs going.
	var moving: bool = travelled.length() > 0.0005
	_sprite.face(travelled)
	_sprite.animate(delta, moving)


func _repath() -> void:
	var from := Vector2i(roundi(tile_position.x), roundi(tile_position.y))
	if not grid.is_walkable(from):
		# Snapped onto a wall by rounding; fall back to the zone we came from.
		from = TownGrid.zone_center(_last_zone)
	_path = grid.path_to_slot(from, agent.current_zone, slot_index)
	_path_index = 0


func _advance_along_path(delta: float) -> void:
	if _path_index >= _path.size():
		return

	# Movement is tied to the clock's time scale, so fast-forwarding the
	# simulation fast-forwards the walking too and NPCs never lag their schedule.
	var speed: float = BASE_SPEED * maxf(GameClock.time_scale, 0.0)
	if is_zero_approx(speed):
		return

	var remaining: float = speed * delta
	while remaining > 0.0 and _path_index < _path.size():
		var target := Vector2(_path[_path_index])
		var to_target: Vector2 = target - tile_position
		var distance: float = to_target.length()

		if distance <= remaining:
			tile_position = target
			remaining -= distance
			_path_index += 1
		else:
			tile_position += to_target / distance * remaining
			remaining = 0.0


func _draw() -> void:
	if agent == null:
		return

	# The body is the sprite child. Everything drawn here is status, and it now
	# all sits on the ground at the feet rather than orbiting a dot — flattened
	# so a ring reads as painted on the floor under a standing figure.
	var squash := Vector2(1.0, 0.45)
	draw_set_transform(Vector2.ZERO, 0.0, squash)

	# Contact shadow, so bodies separate from the zone fill beneath them.
	draw_circle(Vector2(0, 1), BODY_RADIUS, Color(0, 0, 0, 0.35))

	# Mood ring reflects their opinion of the player, so a rumour landing
	# off-screen still shows up as a visible change.
	#
	# Its shape carries what the polygon body used to: the more Dark Triad,
	# the sharper. One sprite serves the whole cast, so disposition has to be
	# said with the status marks or it stops being visible at all.
	var sides: int = 3 if agent.psyche.dark_factor() > 0.5 else 20
	var mood: Color = ProcArt.mood_color(agent.opinion_of_player())
	var ring: PackedVector2Array = ProcArt.polygon_points(sides, BODY_RADIUS + 3.0, -PI / 2.0)
	ring.append(ring[0])
	draw_polyline(ring, mood, 1.5)

	# An NPC who has abandoned their schedule to hunt someone is the design
	# doc's key visual clue that background gossip is happening.
	if agent.is_seeking():
		draw_arc(Vector2.ZERO, BODY_RADIUS + 6.0, 0.0, TAU, 16, Color("ffcc44"), 1.0)

	if is_selected:
		draw_arc(Vector2.ZERO, BODY_RADIUS + 8.0, 0.0, TAU, 24, Color("ffffff"), 2.0)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_name()


## Font size for names. Small on purpose: a name is an aid to picking someone
## out, not a thing to read at length, and every pixel it spends is a pixel of
## somebody else's name it can collide with.
const LABEL_SIZE := 8

## Vertical tiers labels are dealt into. Standing spots are two tiles apart
## horizontally, which is narrower than a name, so neighbours must be separated
## in height instead: three tiers means only every third column can clash, and
## the layout never puts those next to each other.
const LABEL_TIERS := 3

## Pixels between one label tier and the next.
const LABEL_TIER_STEP := 10.0


func _draw_name() -> void:
	var label: String = agent.psyche.short_name
	var size := Vector2(_font.get_string_size(
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE
	).x, float(LABEL_SIZE))

	# Deal each standing spot a tier by its index, so adjacent occupants never
	# land at the same height. The origin is at the feet, so every tier starts
	# from a full body height up.
	var tier: int = slot_index % LABEL_TIERS
	var baseline: float = -BODY_HEIGHT - 4.0 - float(tier) * LABEL_TIER_STEP
	var origin := Vector2(-size.x * 0.5, baseline)

	# A plate behind the text. Names sit over other people's heads in a crowd,
	# and pale text on a pale tunic is unreadable however it is outlined.
	draw_rect(
		Rect2(origin + Vector2(-2.0, -size.y), size + Vector2(4.0, 3.0)),
		Color(0, 0, 0, 0.55)
	)
	draw_string(
		_font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE,
		Color(1, 1, 1, 0.95)
	)
