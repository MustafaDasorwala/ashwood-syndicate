## The parts of the presentation layer that carry logic: the day/night curve and
## the player's movement and collision.
extends GdUnitTestSuite

const _Z := TownGrid.Zone


func before_test() -> void:
	GameClock.time_scale = 0.0
	GameClock.reset()


func after_test() -> void:
	GameClock.reset()
	GameClock.time_scale = 1.0


func _sim() -> TownSim:
	var sim: TownSim = auto_free(TownSim.new())
	sim.setup(20260730)
	return sim


func _avatar(sim: TownSim) -> PlayerAvatar:
	var avatar: PlayerAvatar = auto_free(PlayerAvatar.new())
	avatar.setup(sim)
	return avatar


# --- day and night ---------------------------------------------------------

func test_every_hour_has_a_tint() -> void:
	for hour in GameClock.HOURS_PER_DAY:
		var tint: Color = DayNight.tint_for(hour, 0.0)
		assert_float(tint.r).is_between(0.0, 1.0)
		assert_float(tint.g).is_between(0.0, 1.0)
		assert_float(tint.b).is_between(0.0, 1.0)


func test_midday_is_brighter_than_midnight() -> void:
	var noon: Color = DayNight.tint_for(12, 0.0)
	var midnight: Color = DayNight.tint_for(0, 0.0)
	assert_float(noon.r + noon.g + noon.b).is_greater(midnight.r + midnight.g + midnight.b)


func test_night_is_cooler_than_day() -> void:
	# Blue-shifted after dark, warm at midday. Cheap, but it reads instantly.
	var midnight: Color = DayNight.tint_for(1, 0.0)
	assert_float(midnight.b).is_greater(midnight.r)

	var noon: Color = DayNight.tint_for(12, 0.0)
	assert_float(noon.r).is_greater_equal(noon.b)


func test_the_tint_slides_rather_than_snapping() -> void:
	var early: Color = DayNight.tint_for(7, 0.0)
	var halfway: Color = DayNight.tint_for(7, 0.5)
	var late: Color = DayNight.tint_for(7, 0.999)

	assert_bool(early.is_equal_approx(halfway)).is_false()
	var early_sum: float = early.r + early.g + early.b
	var half_sum: float = halfway.r + halfway.g + halfway.b
	var late_sum: float = late.r + late.g + late.b
	assert_float(half_sum).is_between(early_sum, late_sum)


func test_the_tint_wraps_around_midnight() -> void:
	# Hour 23 interpolates toward hour 0 of the next day, not backwards through
	# the whole afternoon.
	var late: Color = DayNight.tint_for(23, 0.5)
	assert_float(late.b).is_greater(late.r)


func test_lamps_are_lit_after_dark_and_not_at_noon() -> void:
	assert_bool(DayNight.is_lamplight(22)).is_true()
	assert_bool(DayNight.is_lamplight(3)).is_true()
	assert_bool(DayNight.is_lamplight(12)).is_false()


# --- movement --------------------------------------------------------------

func test_the_player_starts_somewhere_walkable() -> void:
	var sim := _sim()
	var avatar := _avatar(sim)
	var tile := Vector2i(roundi(avatar.tile_position.x), roundi(avatar.tile_position.y))
	assert_bool(sim.grid.is_walkable(tile)).is_true()


func test_walking_moves_the_player() -> void:
	GameClock.time_scale = 1.0
	var sim := _sim()
	var avatar := _avatar(sim)
	var before: Vector2 = avatar.tile_position

	avatar._step(Vector2.RIGHT, 0.5)
	assert_float(avatar.tile_position.distance_to(before)).is_greater(0.0)


func test_a_paused_game_does_not_move_the_player() -> void:
	# Conversations freeze the clock; the body must freeze with it.
	GameClock.time_scale = 0.0
	var sim := _sim()
	var avatar := _avatar(sim)
	var before: Vector2 = avatar.tile_position

	avatar._step(Vector2.RIGHT, 1.0)
	assert_vector(avatar.tile_position).is_equal(before)


func test_the_player_cannot_walk_through_a_wall() -> void:
	GameClock.time_scale = 1.0
	var sim := _sim()
	var avatar := _avatar(sim)

	var wall: Rect2i = TownGrid.WALLS[0]
	# Stand directly to the left of the wall and push into it.
	avatar.tile_position = Vector2(wall.position.x - 1, wall.position.y + 1)
	for i in 40:
		avatar._step(Vector2.RIGHT, 0.1)

	var tile := Vector2i(roundi(avatar.tile_position.x), roundi(avatar.tile_position.y))
	assert_bool(sim.grid.is_walkable(tile)).override_failure_message(
		"walked into solid ground at %s" % tile
	).is_true()


func test_walking_into_a_corner_slides_instead_of_sticking() -> void:
	GameClock.time_scale = 1.0
	var sim := _sim()
	var avatar := _avatar(sim)

	var wall: Rect2i = TownGrid.WALLS[0]
	avatar.tile_position = Vector2(wall.position.x - 1, wall.position.y + 1)
	var before_y: float = avatar.tile_position.y

	# Diagonally into the wall: the horizontal is blocked, the vertical is not.
	for i in 20:
		avatar._step(Vector2(1.0, 1.0).normalized(), 0.1)

	assert_float(avatar.tile_position.y).override_failure_message(
		"stuck on a corner instead of sliding along it"
	).is_greater(before_y)


func test_a_route_can_be_walked_across_town() -> void:
	var sim := _sim()
	var avatar := _avatar(sim)
	assert_bool(avatar.walk_to(TownGrid.zone_center(_Z.WOODS))).is_true()
	assert_bool(avatar.is_walking()).is_true()


func test_walking_into_solid_ground_is_refused() -> void:
	var sim := _sim()
	var avatar := _avatar(sim)
	assert_bool(avatar.walk_to(TownGrid.WALLS[0].position)).is_false()


func test_the_simulation_follows_the_body() -> void:
	# The avatar is the only writer of player_zone; everything downstream keys
	# off it, so they must never disagree.
	var sim := _sim()
	var avatar := _avatar(sim)

	avatar.tile_position = Vector2(TownGrid.zone_center(_Z.WOODS))
	avatar._sync_zone()
	assert_int(sim.player_zone).is_equal(_Z.WOODS)

	avatar.tile_position = Vector2(TownGrid.zone_center(_Z.TAVERN))
	avatar._sync_zone()
	assert_int(sim.player_zone).is_equal(_Z.TAVERN)


func test_standing_in_the_street_reaches_nobody() -> void:
	# Rooms are where people are. Standing in the road genuinely means you
	# cannot speak to anyone.
	var sim := _sim()
	var avatar := _avatar(sim)

	avatar.tile_position = Vector2(19, 11)
	avatar._sync_zone()

	assert_int(sim.player_zone).is_equal(-1)
	for agent in sim.agents:
		assert_bool(sim.player_can_reach(agent)).is_false()


# --- character sprites -----------------------------------------------------

func test_the_character_sheet_holds_a_full_four_direction_walk() -> void:
	# The sheet is sliced by fixed frame arithmetic, not by anything that would
	# notice a wrong-sized PNG. Regenerate it at another size and every NPC
	# silently renders a slice of two neighbouring frames.
	var sheet: Texture2D = load(CharacterSprite.SHEET_PATH)
	assert_object(sheet).is_not_null()
	assert_int(sheet.get_width()).is_equal(
		CharacterSprite.FRAME_SIZE.x * CharacterSprite.COLUMNS
	)
	assert_int(sheet.get_height()).is_equal(
		CharacterSprite.FRAME_SIZE.y * CharacterSprite.ROWS
	)


func test_a_body_faces_the_way_it_is_moving() -> void:
	var sprite: CharacterSprite = auto_free(CharacterSprite.new())
	add_child(sprite)

	var cases := {
		Vector2.DOWN: CharacterSprite.ROW_DOWN,
		Vector2.UP: CharacterSprite.ROW_UP,
		Vector2.LEFT: CharacterSprite.ROW_LEFT,
		Vector2.RIGHT: CharacterSprite.ROW_RIGHT,
	}
	for direction: Vector2 in cases:
		sprite.face(direction)
		sprite.animate(0.0, false)
		assert_int(sprite.frame).is_equal(
			int(cases[direction]) * CharacterSprite.COLUMNS + CharacterSprite.IDLE_COLUMN
		)


func test_standing_still_keeps_the_last_facing() -> void:
	# Someone who stops walking should not pivot to face the camera. The facing
	# only ever changes on real movement, so a zero vector must be ignored.
	var sprite: CharacterSprite = auto_free(CharacterSprite.new())
	add_child(sprite)

	sprite.face(Vector2.LEFT)
	sprite.face(Vector2.ZERO)
	sprite.animate(0.0, false)

	assert_int(sprite.frame).is_equal(
		CharacterSprite.ROW_LEFT * CharacterSprite.COLUMNS + CharacterSprite.IDLE_COLUMN
	)


func test_stopping_parks_on_the_idle_pose() -> void:
	# Otherwise a town at rest is full of people frozen mid-stride.
	var sprite: CharacterSprite = auto_free(CharacterSprite.new())
	add_child(sprite)
	GameClock.time_scale = 1.0

	sprite.face(Vector2.DOWN)
	sprite.animate(0.5, true)
	sprite.animate(0.5, true)
	sprite.animate(0.1, false)

	assert_int(sprite.frame).is_equal(
		CharacterSprite.ROW_DOWN * CharacterSprite.COLUMNS + CharacterSprite.IDLE_COLUMN
	)


func test_walking_cycles_through_every_frame_of_the_row() -> void:
	var sprite: CharacterSprite = auto_free(CharacterSprite.new())
	add_child(sprite)
	GameClock.time_scale = 1.0

	sprite.face(Vector2.DOWN)
	var seen := {}
	for step in 40:
		sprite.animate(0.05, true)
		seen[sprite.frame] = true

	assert_int(seen.size()).is_equal(CharacterSprite.COLUMNS)


func test_every_inhabitant_gets_a_distinguishable_tunic() -> void:
	# One sheet dressed in ten colours is the whole reason a single generated
	# character can serve the cast. Two people the same colour undoes it.
	var sim: TownSim = auto_free(TownSim.new())
	sim.setup(20260730)

	var colours: Array[Color] = []
	for i in sim.agents.size():
		colours.append(ProcArt.tunic_color(i))

	for i in colours.size():
		for j in range(i + 1, colours.size()):
			var apart: float = absf(colours[i].h - colours[j].h)
			apart = minf(apart, 1.0 - apart)
			assert_float(apart).override_failure_message(
				"%s and %s wear the same colour" % [sim.agents[i].id, sim.agents[j].id]
			).is_greater(0.04)


func test_standing_spots_leave_room_for_a_two_tile_body() -> void:
	# A villager is drawn two tiles tall from the feet. Rows any closer than
	# that bury the back row's head inside the front row, which no test of the
	# simulation would ever notice.
	for zone: int in TownGrid.Zone.values():
		var rect: Rect2i = TownGrid.zone_rect(zone)
		if rect.size.y - 2 < TownGrid.ROW_SPACING * 2:
			continue  # Too short to seat two rows at all; nothing to check.

		var heights := {}
		for index in TownGrid.SLOT_CAPACITY:
			heights[TownGrid.zone_slot(zone, index).y] = true

		var rows: Array = heights.keys()
		rows.sort()
		for i in range(1, rows.size()):
			assert_int(rows[i] - rows[i - 1]).override_failure_message(
				"%s seats rows %d tiles apart" % [TownGrid.zone_name(zone), rows[i] - rows[i - 1]]
			).is_greater_equal(TownGrid.ROW_SPACING)


# --- reaching the person you actually clicked -------------------------------

func test_you_can_reach_somebody_who_is_not_the_nearest_person() -> void:
	# Reach asked "is this the closest agent", not "is this agent close". In a
	# crowded room that means standing right beside your target and being told
	# you are too far, because a neighbour happened to be a pixel nearer.
	var sim := _sim()
	var avatar := _avatar(sim)

	var nearer: Agent = sim.agents[0]
	var further: Agent = sim.agents[1]
	nearer.current_zone = _Z.TAVERN
	further.current_zone = _Z.TAVERN

	# Stand between the two of them, closer to the first, but with both well
	# inside arm's reach.
	var first_spot := Vector2(TownGrid.zone_slot(_Z.TAVERN, 0))
	var second_spot := Vector2(TownGrid.zone_slot(_Z.TAVERN, 1))
	avatar.tile_position = first_spot.lerp(second_spot, 0.65)

	assert_float(avatar.distance_to(nearer)).is_less(PlayerAvatar.REACH)
	assert_float(avatar.distance_to(further)).is_less(PlayerAvatar.REACH)
	assert_float(avatar.distance_to(further)).is_less(avatar.distance_to(nearer))

	assert_bool(avatar.can_reach(nearer)).override_failure_message(
		"somebody within arm's reach was unreachable because another was nearer"
	).is_true()
	assert_bool(avatar.can_reach(further)).is_true()


func test_walking_to_somebody_walks_to_them_and_not_to_slot_zero() -> void:
	# Clicking anyone but the first occupant used to march the player to the
	# room's first standing spot — next to a different person entirely — and
	# then refuse to open a conversation because the target was too far.
	var sim := _sim()
	var avatar := _avatar(sim)

	var seventh: Agent = sim.agents[6]
	seventh.current_zone = _Z.TAVERN

	var destination: Vector2i = avatar.approach_tile(seventh)
	assert_vector(Vector2(destination)).override_failure_message(
		"walked to the room's first spot rather than to the person clicked"
	).is_not_equal(Vector2(TownGrid.zone_slot(_Z.TAVERN, 0)))

	# And standing there must actually put them in reach.
	avatar.tile_position = Vector2(destination)
	assert_bool(avatar.can_reach(seventh)).is_true()


# --- the opening briefing ---------------------------------------------------

func test_the_briefing_names_the_rivals_from_the_live_town() -> void:
	# Hardcoding "Mayor Thorne and Yolen the Merchant" would be wrong in every
	# procedural town, which has neither.
	var sim := _sim()
	var briefing: BriefingScreen = auto_free(BriefingScreen.new())

	var objective: String = briefing._objective(sim)
	for candidate in sim.candidate_ids:
		if candidate == Agent.PLAYER_ID:
			continue
		var rival: Agent = sim.agent_by_id(candidate)
		assert_str(objective).override_failure_message(
			"the briefing never mentions %s, who is standing against the player" % rival.display_name
		).contains(rival.display_name)


func test_the_briefing_names_the_rivals_of_a_generated_town_too() -> void:
	var sim: TownSim = auto_free(TownSim.new())
	sim.setup_generated(4242)
	var briefing: BriefingScreen = auto_free(BriefingScreen.new())

	var objective: String = briefing._objective(sim)
	for candidate in sim.candidate_ids:
		if candidate == Agent.PLAYER_ID:
			continue
		assert_str(objective).contains(sim.agent_by_id(candidate).display_name)


func test_the_briefing_states_the_objective_and_the_deadline() -> void:
	var briefing: BriefingScreen = auto_free(BriefingScreen.new())
	var objective: String = briefing._objective(_sim())

	assert_str(objective.to_lower()).contains("six")
	assert_str(objective.to_lower()).contains("ten")
	assert_str(briefing._situation(null).to_lower()).contains("seven days")


func test_the_briefing_survives_having_no_simulation() -> void:
	# It is built from whatever the scene has; a null town must not crash the
	# one screen standing between the player and the game.
	var briefing: BriefingScreen = auto_free(BriefingScreen.new())
	assert_str(briefing._objective(null)).is_not_empty()
	assert_str(briefing._situation(null)).is_not_empty()
