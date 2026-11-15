## Town grid: zone lookup and A* pathfinding around walls.
extends GdUnitTestSuite

const _Z := TownGrid.Zone


func test_every_zone_has_a_footprint_inside_the_map() -> void:
	for zone in _Z.values():
		var rect: Rect2i = TownGrid.zone_rect(zone)
		assert_int(rect.size.x).is_greater(0)
		assert_int(rect.size.y).is_greater(0)
		assert_bool(TownGrid.is_in_bounds(rect.position)).is_true()
		assert_bool(TownGrid.is_in_bounds(rect.end - Vector2i.ONE)).is_true()


func test_zones_do_not_overlap() -> void:
	var zones: Array = _Z.values()
	for i in zones.size():
		for j in range(i + 1, zones.size()):
			var a: Rect2i = TownGrid.zone_rect(zones[i])
			var b: Rect2i = TownGrid.zone_rect(zones[j])
			assert_bool(a.intersects(b)).is_false()


func test_zone_center_resolves_back_to_its_own_zone() -> void:
	for zone in _Z.values():
		assert_int(TownGrid.zone_at(TownGrid.zone_center(zone))).is_equal(zone)


func test_streets_between_zones_belong_to_no_zone() -> void:
	# The gap between the tavern block and the market block.
	assert_int(TownGrid.zone_at(Vector2i(19, 11))).is_equal(-1)


func test_bounds_are_enforced() -> void:
	assert_bool(TownGrid.is_in_bounds(Vector2i(0, 0))).is_true()
	assert_bool(TownGrid.is_in_bounds(Vector2i(TownGrid.WIDTH - 1, TownGrid.HEIGHT - 1))).is_true()
	assert_bool(TownGrid.is_in_bounds(Vector2i(-1, 0))).is_false()
	assert_bool(TownGrid.is_in_bounds(Vector2i(TownGrid.WIDTH, 0))).is_false()


func test_walls_are_not_walkable() -> void:
	var grid := TownGrid.new()
	var wall: Rect2i = TownGrid.WALLS[0]
	assert_bool(grid.is_walkable(wall.position)).is_false()


func test_zone_centers_are_walkable() -> void:
	var grid := TownGrid.new()
	for zone in _Z.values():
		assert_bool(grid.is_walkable(TownGrid.zone_center(zone))).is_true()


func test_a_crowd_does_not_stack_on_one_tile() -> void:
	# Ten inhabitants sharing a zone must occupy ten distinct spots, or the
	# player cannot tell who is present, let alone click one of them.
	for zone in _Z.values():
		var seen := {}
		for index in TownGrid.SLOT_CAPACITY:
			var slot: Vector2i = TownGrid.zone_slot(zone, index)
			assert_bool(seen.has(slot)).override_failure_message(
				"slot %d collides in %s at %s" % [index, TownGrid.zone_name(zone), slot]
			).is_false()
			seen[slot] = true


func test_standing_spots_stay_inside_their_zone() -> void:
	var grid := TownGrid.new()
	for zone in _Z.values():
		for index in TownGrid.SLOT_CAPACITY:
			var slot: Vector2i = TownGrid.zone_slot(zone, index)
			assert_int(TownGrid.zone_at(slot)).override_failure_message(
				"slot %d of %s escaped the zone" % [index, TownGrid.zone_name(zone)]
			).is_equal(zone)
			assert_bool(grid.is_walkable(slot)).is_true()


func test_standing_spots_are_stable_between_calls() -> void:
	for index in 10:
		assert_vector(TownGrid.zone_slot(_Z.TAVERN, index)).is_equal(
			TownGrid.zone_slot(_Z.TAVERN, index)
		)


func test_more_arrivals_than_spots_wrap_rather_than_escape() -> void:
	for index in [100, 250, 999]:
		assert_int(TownGrid.zone_at(TownGrid.zone_slot(_Z.SHERIFF, index))).is_equal(_Z.SHERIFF)


func test_a_path_exists_to_every_standing_spot() -> void:
	var grid := TownGrid.new()
	for zone in _Z.values():
		for index in 10:
			var path: Array[Vector2i] = grid.path_to_slot(
				TownGrid.zone_center(_Z.WOODS), zone, index
			)
			assert_int(path.size()).is_greater(0)


func test_a_path_exists_between_every_pair_of_zones() -> void:
	# If any two zones are unreachable, NPCs silently stop following their
	# schedule and the whole simulation quietly stalls.
	var grid := TownGrid.new()
	for from_zone in _Z.values():
		for to_zone in _Z.values():
			var path: Array[Vector2i] = grid.path_to_zone(TownGrid.zone_center(from_zone), to_zone)
			assert_int(path.size()).override_failure_message(
				"no route from %s to %s" % [TownGrid.zone_name(from_zone), TownGrid.zone_name(to_zone)]
			).is_greater(0)


func test_a_path_starts_and_ends_where_asked() -> void:
	var grid := TownGrid.new()
	var from := TownGrid.zone_center(_Z.TAVERN)
	var to := TownGrid.zone_center(_Z.WOODS)
	var path: Array[Vector2i] = grid.find_path(from, to)

	assert_vector(path[0]).is_equal(from)
	assert_vector(path[path.size() - 1]).is_equal(to)


func test_a_path_never_crosses_a_wall() -> void:
	var grid := TownGrid.new()
	var path: Array[Vector2i] = grid.path_to_zone(TownGrid.zone_center(_Z.TAVERN), _Z.SHERIFF)
	for tile in path:
		assert_bool(grid.is_walkable(tile)).override_failure_message(
			"path crosses solid tile %s" % tile
		).is_true()


func test_a_path_is_contiguous() -> void:
	var grid := TownGrid.new()
	var path: Array[Vector2i] = grid.path_to_zone(TownGrid.zone_center(_Z.MARKET), _Z.RESIDENCES)
	for i in range(1, path.size()):
		var step: Vector2i = path[i] - path[i - 1]
		assert_int(maxi(absi(step.x), absi(step.y))).is_equal(1)


func test_out_of_bounds_requests_return_no_path_rather_than_erroring() -> void:
	var grid := TownGrid.new()
	assert_int(grid.find_path(Vector2i(-5, -5), TownGrid.zone_center(_Z.MARKET)).size()).is_equal(0)
	assert_int(grid.find_path(TownGrid.zone_center(_Z.MARKET), Vector2i(999, 999)).size()).is_equal(0)


func test_walking_into_a_wall_returns_no_path() -> void:
	var grid := TownGrid.new()
	var wall_tile: Vector2i = TownGrid.WALLS[0].position
	assert_int(grid.find_path(TownGrid.zone_center(_Z.TAVERN), wall_tile).size()).is_equal(0)
