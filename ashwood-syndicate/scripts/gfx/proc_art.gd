class_name ProcArt
extends RefCounted

## Procedural placeholder art.
##
## Everything the game draws is generated from math here, so the project runs on
## a clean checkout with no imported assets. Each helper is a single function
## returning colour or geometry, which is the seam for swapping in real sprites
## later: replace the call site, not the systems around it.

const TILE_SIZE := 16

## Zone -> base colour. Muted, low-saturation frontier palette so the NPC dots
## stay legible on top.
const ZONE_COLORS := {
	TownGrid.Zone.TAVERN: Color("6b4a2f"),
	TownGrid.Zone.MARKET: Color("7a6a3d"),
	TownGrid.Zone.RESIDENCES: Color("4a4a55"),
	TownGrid.Zone.SHERIFF: Color("3d5266"),
	TownGrid.Zone.WOODS: Color("2f4a35"),
}

const STREET_COLOR := Color("23232a")
const WALL_COLOR := Color("15151a")
const GRID_LINE_COLOR := Color(1, 1, 1, 0.04)
const PLAYER_COLOR := Color("e8d8a0")


static func zone_color(zone: int) -> Color:
	return ZONE_COLORS.get(zone, STREET_COLOR)


## Converts tile coordinates to pixels.
static func tile_to_px(tile: Vector2) -> Vector2:
	return tile * float(TILE_SIZE)


static func rect_to_px(rect: Rect2i) -> Rect2:
	return Rect2(Vector2(rect.position) * TILE_SIZE, Vector2(rect.size) * TILE_SIZE)


## A stable, well-separated colour per NPC id.
##
## Derived from the id's hash rather than assigned by hand, so adding an
## eleventh inhabitant needs no palette bookkeeping. Saturation and value are
## pinned so every NPC reads clearly against any zone.
static func npc_color(id: StringName) -> Color:
	var hue: float = float(abs(str(id).hash()) % 360) / 360.0
	return Color.from_hsv(hue, 0.55, 0.95)


## The colour one inhabitant's tunic is dyed, keyed on their position in the
## roster rather than on their id.
##
## Hashing the id spreads hues arbitrarily, and arbitrary is not the same as
## separated: Ashwood's blacksmith and trapper hashed close enough to be dressed
## identically. That was survivable when an NPC was a five pixel dot and is not
## now that it is a person. Stepping the hue by the golden ratio instead gives
## the largest gap any cast size can have, and a generated town gets the same
## guarantee as the hand-authored one.
##
## Saturation and value are held low because these are clothes, not map
## markers; at full strength the recolour turns ten villagers into traffic cones
## and buries the sprite's own shading.
static func tunic_color(index: int) -> Color:
	const GOLDEN_RATIO_CONJUGATE := 0.6180339887
	var hue: float = fposmod(float(index) * GOLDEN_RATIO_CONJUGATE, 1.0)
	return Color.from_hsv(hue, 0.40, 0.72)


## Mood tint applied over an NPC's base colour, so the player can see at a
## glance that someone's opinion has moved without opening a panel.
##
## This is the design doc's "expose the system" requirement: background maths
## must leave visible traces.
static func mood_color(opinion: float) -> Color:
	var t: float = clampf(opinion / RelationshipBook.MAX_SCORE, 0.0, 1.0)
	return Color("c04040").lerp(Color("40c060"), t)


## Points of a regular polygon, used for NPC bodies. Sides encode role without
## needing distinct sprites: more sides reads as more "civilised".
static func polygon_points(sides: int, radius: float, rotation: float = 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count: int = maxi(sides, 3)
	for i in count:
		var angle: float = rotation + TAU * float(i) / float(count)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


## A soft vertical gradient used for zone fills, so flat rectangles read as
## lit spaces rather than colour swatches.
static func zone_gradient(base: Color) -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, base.lightened(0.12))
	gradient.set_color(1, base.darkened(0.18))
	return gradient
