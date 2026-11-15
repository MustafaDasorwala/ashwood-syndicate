class_name PlayerAvatar
extends Node2D

## The player, actually walking around the town.
##
## Replaces the earlier click-a-zone-and-teleport model. Walking somewhere takes
## real time, you can be seen on the way, and standing in the wrong place at the
## wrong hour is how you discover things — which only works if there is a body
## to stand there.
##
## The avatar is the only writer of `TownSim.player_zone`. Everything downstream
## (who you can talk to, who witnesses what you do) already keys off that, so
## the simulation needed no changes to accept a moving player.

## Tiles per second at 1x time scale. Tuned so crossing the whole town costs
## roughly twenty in-game minutes: long enough that where you stand is a real
## decision, short enough that you are not watching a dot crawl.
const SPEED := 1.9

## How close you must be to speak to somebody.
const REACH := 2.4

## Radius of the ring drawn on the ground at the player's feet. The body itself
## is a sprite; this marks which of the figures is you.
const BODY_RADIUS := 6.0

## Height of the drawn sprite in world pixels, used to place the label clear of
## the head.
const BODY_HEIGHT := 32.0

var sim: TownSim
var grid: TownGrid

## Position in tile space, fractional between tiles.
var tile_position: Vector2 = Vector2.ZERO

## Facing, for the sprite and for a little directional feel.
var facing: Vector2 = Vector2.DOWN

## Set when the player clicks somewhere; cleared once reached or interrupted.
var _path: Array[Vector2i] = []
var _path_index: int = 0

var _last_zone: int = -2
var _font: Font
var _sprite: CharacterSprite

## Tile position at the end of the previous physics step, so the walk cycle
## runs off ground actually covered rather than off input being held — sliding
## along a wall should not look like striding through it.
var _previous_tile_position: Vector2 = Vector2.ZERO


func setup(p_sim: TownSim) -> void:
	sim = p_sim
	grid = p_sim.grid
	tile_position = Vector2(TownGrid.zone_center(p_sim.player_zone))
	_previous_tile_position = tile_position
	_sync_zone()


func _ready() -> void:
	_font = ThemeDB.fallback_font

	# Deliberately the same z_index as the NPCs: y-sorting only orders siblings
	# that share one, and lifting the player above everyone would mean walking
	# through the town permanently in front of it.
	z_index = 5

	_sprite = CharacterSprite.new()
	add_child(_sprite)
	_sprite.set_tint(ProcArt.PLAYER_COLOR)


func _physics_process(delta: float) -> void:
	if sim == null or grid == null:
		return

	var moved: bool = _apply_keyboard(delta)
	if not moved:
		_follow_path(delta)

	position = ProcArt.tile_to_px(tile_position)
	_sync_zone()
	_drive_sprite(delta)
	queue_redraw()


func _drive_sprite(delta: float) -> void:
	if _sprite == null:
		return

	var travelled: Vector2 = tile_position - _previous_tile_position
	_previous_tile_position = tile_position

	# Face where the body actually went when it went somewhere, and otherwise
	# hold the last intended facing, so pressing into a wall still turns you.
	if travelled.length() > 0.0005:
		_sprite.face(travelled)
		_sprite.animate(delta, true)
	else:
		_sprite.face(facing)
		_sprite.animate(delta, false)


## Direct control. Takes priority over a click destination, and cancels it —
## grabbing the keys should always mean "no, this way".
func _apply_keyboard(delta: float) -> bool:
	var direction := Vector2(
		Input.get_axis(&"ui_left", &"ui_right"),
		Input.get_axis(&"ui_up", &"ui_down")
	)
	if direction == Vector2.ZERO:
		return false

	_path.clear()
	_step(direction.normalized(), delta)
	return true


func _follow_path(delta: float) -> void:
	if _path_index >= _path.size():
		return

	var target := Vector2(_path[_path_index])
	var offset: Vector2 = target - tile_position
	if offset.length() < 0.08:
		_path_index += 1
		return
	_step(offset.normalized(), delta)


## Moves along `direction`, sliding along walls rather than sticking to them.
func _step(direction: Vector2, delta: float) -> void:
	facing = direction
	var distance: float = SPEED * maxf(GameClock.time_scale, 0.0) * delta
	if is_zero_approx(distance):
		return

	var wanted: Vector2 = tile_position + direction * distance
	if _walkable(wanted):
		tile_position = wanted
		return

	# Try each axis alone so a diagonal into a corner still slides.
	var horizontal := Vector2(wanted.x, tile_position.y)
	if _walkable(horizontal):
		tile_position = horizontal
		return
	var vertical := Vector2(tile_position.x, wanted.y)
	if _walkable(vertical):
		tile_position = vertical


func _walkable(where: Vector2) -> bool:
	return grid.is_walkable(Vector2i(roundi(where.x), roundi(where.y)))


## Walks to a clicked tile. Returns false when there is no route.
func walk_to(tile: Vector2i) -> bool:
	var from := Vector2i(roundi(tile_position.x), roundi(tile_position.y))
	_path = grid.find_path(from, tile)
	_path_index = 0
	return not _path.is_empty()


func is_walking() -> bool:
	return _path_index < _path.size()


## Keeps the simulation's idea of where the player is in step with the body.
##
## Streets between zones resolve to -1, so standing in the road genuinely means
## you cannot speak to anybody. That is intended: rooms are where people are.
func _sync_zone() -> void:
	var tile := Vector2i(roundi(tile_position.x), roundi(tile_position.y))
	var zone: int = TownGrid.zone_at(tile)
	if zone != _last_zone:
		_last_zone = zone
		sim.player_zone = zone


## Whoever is close enough to talk to, or null.
func nearest_within_reach() -> Agent:
	if sim == null:
		return null

	var best: Agent = null
	var best_distance: float = REACH
	for agent in sim.agents:
		var distance: float = distance_to(agent)
		if distance < best_distance:
			best_distance = distance
			best = agent
	return best


## Whether this particular person is close enough to speak to.
##
## Distinct from `nearest_within_reach` and the distinction is the whole point.
## Callers used to ask "is my selection the closest agent", which is a different
## question and false almost all the time in a crowded room: you stand beside
## the person you meant to talk to, somebody else is a fraction nearer, and the
## game tells you that you are too far away from someone within arm's reach.
func can_reach(agent: Agent) -> bool:
	return agent != null and distance_to(agent) < REACH


## Distance in tiles to where an agent is actually drawn.
##
## Falls back to their zone's first standing spot when there is no view, which
## only happens in headless tests.
func distance_to(agent: Agent) -> float:
	if agent == null:
		return INF
	var view: NpcView = _view_for(agent)
	var agent_tile := (
		view.tile_position if view != null
		else Vector2(TownGrid.zone_slot(agent.current_zone, slot_of(agent)))
	)
	return tile_position.distance_to(agent_tile)


## Where an inhabitant stands, by their position in the roster — which is the
## slot index `Main` hands their view.
func slot_of(agent: Agent) -> int:
	if sim == null:
		return 0
	var index: int = sim.agents.find(agent)
	return maxi(index, 0)


## The tile to walk to in order to stand beside somebody.
##
## Their own standing spot, not the room's first one. Walking to slot zero put
## the player next to whoever happened to be first in the roster, so clicking
## anybody else marched you across the room to the wrong person and then
## refused to open a conversation.
func approach_tile(agent: Agent) -> Vector2i:
	if agent == null:
		return Vector2i.ZERO
	var view: NpcView = _view_for(agent)
	if view != null:
		var tile := Vector2i(roundi(view.tile_position.x), roundi(view.tile_position.y))
		if grid != null and grid.is_walkable(tile):
			return tile
	return TownGrid.zone_slot(agent.current_zone, slot_of(agent))


## The body drawn for an agent, or null when there is none.
##
## Null is a real case, not a defensive flourish: the avatar is exercised
## headless with no parent and no views at all, which is the property that lets
## reach and movement be tested without a scene tree.
func _view_for(agent: Agent) -> NpcView:
	var parent: Node = get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child is NpcView and (child as NpcView).agent == agent:
			return child
	return null


func _draw() -> void:
	# The body is the sprite child; what is drawn here marks it as yours. The
	# ring is flattened onto the ground because the sprite stands up out of it,
	# and the sprite's own facing has replaced the direction nose.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 1), BODY_RADIUS, Color(0, 0, 0, 0.4))
	draw_arc(Vector2.ZERO, BODY_RADIUS + 2.0, 0.0, TAU, 20, Color(1, 1, 1, 0.9), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var label: String = "You"
	var width: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	draw_string(_font, Vector2(-width * 0.5, -BODY_HEIGHT - 4.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.95))
