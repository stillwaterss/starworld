extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	while not world.get("content") or not world.content.grid.ready:
		await process_frame
	assert(world.content.grid.save_web_cache("res://data/content/walk_grid_web.bin"))
	var original = world.content.grid
	var restored = load("res://scripts/content/walk_grid.gd").new()
	assert(restored.load_web_cache("res://data/content/walk_grid_web.bin"))
	assert(restored.walkable == original.walkable)
	assert(restored.component == original.component)
	assert(restored.hops == original.hops)
	for id in original.astar.get_point_ids():
		assert(restored.astar.get_point_position(id) == original.astar.get_point_position(id))
		assert(is_equal_approx(restored.astar.get_point_weight_scale(id), original.astar.get_point_weight_scale(id)))
		var before: PackedInt64Array = original.astar.get_point_connections(id)
		var after: PackedInt64Array = restored.astar.get_point_connections(id)
		before.sort()
		after.sort()
		assert(before == after)
	print("WEB_GRID_ROUNDTRIP_OK")
	print("WEB_GRID_SAVED points=", world.content.grid.astar.get_point_count(), " bake_ms=", world.content.grid.bake_ms)
	quit()
