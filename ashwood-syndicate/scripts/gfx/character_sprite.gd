class_name CharacterSprite
extends Sprite2D

## One villager body, drawn from the shared four-direction walk sheet.
##
## Every inhabitant and the player use the same 100x200 PNG; they are told
## apart by the tunic recolour shader, which tints the one desaturated region of
## the art. Ten bespoke sheets would have been ten times the generation cost and
## would still have had to agree on proportions.
##
## This node draws and nothing else. It is handed a facing and whether its owner
## is moving; it never reads the simulation, so `NpcView` and `PlayerAvatar`
## remain the only things that know what an Agent is.

const SHEET_PATH := "res://assets/characters/villager_base.png"
const SHADER_PATH := "res://scripts/gfx/tunic_recolor.gdshader"

## Cell size in the source sheet. Not square: the villagers are two tiles tall.
const FRAME_SIZE := Vector2i(25, 50)

const COLUMNS := 4
const ROWS := 4

## Row order in the sheet, which `tools/build_character_sheet.py` guarantees.
const ROW_DOWN := 0
const ROW_LEFT := 1
const ROW_RIGHT := 2
const ROW_UP := 3

## Column 0 is the idle pose; the cycle is idle-step-idle-step.
const IDLE_COLUMN := 0

## Drawn size, in world pixels: one tile wide and two tall. The sheet is 25x50,
## so this is a slight downscale rather than an upscale — detail is lost gently
## instead of turning blocky.
const DRAWN_WIDTH := 16.0

## Steps per second at 1x. Paced against `NpcView.BASE_SPEED` so feet roughly
## match ground covered rather than skating.
const WALK_FPS := 7.0

var _clock: float = 0.0
var _row: int = ROW_DOWN


func _ready() -> void:
	texture = load(SHEET_PATH)
	hframes = COLUMNS
	vframes = ROWS

	# Nearest filtering is set here rather than in project settings because an
	# open editor rewrites project.godot; a node property cannot be lost that way.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# Feet on the node's origin. The owning node's position is a point on the
	# ground, so anchoring at the centre would sink everyone half a body into it,
	# and it lets the mood ring read as a ring drawn on the floor.
	centered = false
	offset = Vector2(-FRAME_SIZE.x * 0.5, -FRAME_SIZE.y)

	var factor: float = DRAWN_WIDTH / float(FRAME_SIZE.x)
	scale = Vector2(factor, factor)

	var material_shader := ShaderMaterial.new()
	material_shader.shader = load(SHADER_PATH)
	material = material_shader

	_apply_frame(IDLE_COLUMN)


## The colour the tunic is recoloured to. Everything else in the art is left
## alone, so the face and boots stay consistent across the whole cast.
func set_tint(colour: Color) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("tint", colour)


## Picks a facing row from a movement vector. A zero vector keeps the current
## facing, so someone who stops does not snap back to facing the camera.
func face(direction: Vector2) -> void:
	if direction.is_zero_approx():
		return
	if absf(direction.x) > absf(direction.y):
		_row = ROW_RIGHT if direction.x > 0.0 else ROW_LEFT
	else:
		_row = ROW_DOWN if direction.y > 0.0 else ROW_UP


## Advances the walk cycle. `moving` false parks on the idle column rather than
## freezing mid-stride, which otherwise leaves a town of people standing with
## one leg raised.
func animate(delta: float, moving: bool) -> void:
	if not moving:
		_clock = 0.0
		_apply_frame(IDLE_COLUMN)
		return

	# Tied to the clock's scale so fast-forwarding speeds the legs up too.
	_clock += delta * WALK_FPS * maxf(GameClock.time_scale, 0.0)
	_apply_frame(int(_clock) % COLUMNS)


func _apply_frame(column: int) -> void:
	frame = _row * COLUMNS + column
