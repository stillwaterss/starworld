extends RefCounted
## Walkable map baked at runtime from the scene's own collision, so it follows
## whatever island, rails and doors the scene currently has. Each 0.5 m column
## keeps up to two floors: the top surface and, when there is head room, the
## floor under an overhang (covered walkways under house roofs). Thin props
## (rails, lamps, trunks) block the floor under them. Paths come from AStar2D.
const CELL := .5
const MIN_X := -52.0
const MAX_X := 58.0
const MIN_Z := -42.0
const MAX_Z := 40.0
const TOP := 40.0
const LEVELS := 2
const HEADROOM := 2.0              # a lower floor needs this much space under the surface above it
const FLOOR_NORMAL := .64          # player floor_max_angle 50 degrees
const MAX_RISE := .9               # per metre between neighbouring cells on a slope (stair ramps are ~.71)
const STEP := .22                  # height change without a ramp the player steps over (player.gd _step_up .23)
const BLOCKERS := ["Lamps", "Vegetation", "TreeTrunks", "StarTreeCore", "Decor_WishingTree_trunk", "Telescope", "Railings", "BridgeRails", "Physics_", "Solid_V10_Chair", "Solid_V11", "Solid_V13", "Solid_V8", "Fountain"]
const CLEARANCE := .26             # body test radius; posts thinner than a cell are caught here
const ROOMY := .4                  # player capsule .38: cells tighter than this cost more

var width := int((MAX_X - MIN_X) / CELL)
var depth := int((MAX_Z - MIN_Z) / CELL)
var cells := width * depth
## Per slot (slot = level * cells + cell index)
var heights := PackedFloat32Array()   # floor height, NAN when none
var normals := PackedVector3Array()
var walkable := PackedByteArray()
var component := PackedInt32Array()   # connected area id, -1 none
var tight := PackedByteArray()         # walkable, but a full body would brush something
var hops := {}                         # slot -> true at both ends of a ledge the player jumps (Space)
var component_size := {}               # area id -> cells
const HOP := .6                        # jump height is 1.28 m; a hop link climbs at most this
var astar := AStar2D.new()
var ready := false
var bake_ms := 0
var main_component := -1

func save_web_cache(path: String) -> bool:
	var points := []
	var edges := PackedInt32Array()
	for id in astar.get_point_ids():
		points.append([id, astar.get_point_position(id), astar.get_point_weight_scale(id)])
		for other in astar.get_point_connections(id):
			if id < other:
				edges.append(id)
				edges.append(other)
	var file := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:return false
	file.store_var({"version": 1, "heights": heights, "normals": normals, "walkable": walkable, "component": component, "tight": tight, "hops": hops, "component_size": component_size, "main_component": main_component, "points": points, "edges": edges})
	file.close()
	return true

func load_web_cache(path: String) -> bool:
	if not FileAccess.file_exists(path):return false
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:return false
	var data = file.get_var()
	if not data is Dictionary or data.get("version") != 1:return false
	heights = data.heights
	normals = data.normals
	walkable = data.walkable
	component = data.component
	tight = data.tight
	hops = data.hops
	component_size = data.component_size
	main_component = data.main_component
	astar.clear()
	for point in data.points:astar.add_point(point[0], point[1], point[2])
	for i in range(0, data.edges.size(), 2):astar.connect_points(data.edges[i], data.edges[i + 1])
	ready = true
	return true

func index(x: int, z: int) -> int:return z * width + x
func cell_of(p: Vector3) -> Vector2i:return Vector2i(int(floor((p.x - MIN_X) / CELL)), int(floor((p.z - MIN_Z) / CELL)))
func inside(c: Vector2i) -> bool:return c.x >= 0 and c.y >= 0 and c.x < width and c.y < depth
func slot_cell(slot: int) -> Vector2i:
	var i := slot % cells
	return Vector2i(i % width, i / width)
func center(slot: int) -> Vector3:
	var c := slot_cell(slot)
	return Vector3(MIN_X + (c.x + .5) * CELL, heights[slot] + .05, MIN_Z + (c.y + .5) * CELL)

## The slot a map should show for a cell: the walkable main-area floor if any, else the top one.
func shown_slot(x: int, z: int) -> int:
	var i := index(x, z)
	for level in LEVELS:
		var s := level * cells + i
		if walkable[s] and component[s] == main_component:return s
	return i

func _blocker(name: String) -> bool:
	for prefix in BLOCKERS:
		if name.begins_with(prefix):return true
	return false

func bake(space: PhysicsDirectSpaceState3D, exclude: Array[RID] = []) -> void:
	var started := Time.get_ticks_msec()
	hops.clear()
	var probe := PhysicsShapeQueryParameters3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = CLEARANCE
	cylinder.height = 1.1
	probe.shape = cylinder
	probe.collision_mask = 3
	probe.exclude = exclude
	heights.resize(cells * LEVELS)
	normals.resize(cells * LEVELS)
	walkable.resize(cells * LEVELS)
	component.resize(cells * LEVELS)
	tight.resize(cells * LEVELS)
	tight.fill(0)
	var roomy := PhysicsShapeQueryParameters3D.new()
	var wide := CylinderShape3D.new()
	wide.radius = ROOMY
	wide.height = 1.1
	roomy.shape = wide
	roomy.collision_mask = 3
	roomy.exclude = exclude
	heights.fill(NAN)
	walkable.fill(0)
	component.fill(-1)
	for z in depth:
		for x in width:
			var i := index(x, z)
			var column := Vector3(MIN_X + (x + .5) * CELL, TOP, MIN_Z + (z + .5) * CELL)
			var skip: Array[RID] = exclude.duplicate()
			var blocker_top := NAN
			var level := 0
			var above := INF
			for attempt in 7:
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(column, Vector3(column.x, -30, column.z), 3, skip))
				if hit.is_empty():break
				skip.append(hit.rid)
				var body: Object = hit.collider
				var owner_name := String(body.get_parent().name) if body is Node and body.get_parent() else ""
				if _blocker(owner_name):
					if is_nan(blocker_top):blocker_top = hit.position.y
					continue
				var y: float = hit.position.y
				if level > 0 and above - y < HEADROOM:
					continue
				var s := level * cells + i
				heights[s] = y
				normals[s] = hit.normal
				var blocked: bool = not is_nan(blocker_top) and blocker_top - y > .25 and blocker_top - y < 2.4
				if blocked:
					# a branch or canopy edge overhead still leaves room to walk under (capsule 1.58 m)
					var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(hit.position + Vector3.UP * .05, Vector3(column.x, blocker_top + .05, column.z), 3, exclude))
					if not up.is_empty() and up.position.y - y > 1.75:blocked = false
				var ok: bool = hit.normal.y >= FLOOR_NORMAL and not blocked
				if ok:
					probe.transform = Transform3D(Basis.IDENTITY, hit.position + Vector3.UP * .92)
					ok = space.intersect_shape(probe, 1).is_empty()
					if ok:
						roomy.transform = probe.transform
						tight[s] = 0 if space.intersect_shape(roomy, 1).is_empty() else 1
				walkable[s] = 1 if ok else 0
				above = y
				blocker_top = NAN
				level += 1
				if level >= LEVELS:break
	_connect(space, exclude)
	bake_ms = Time.get_ticks_msec() - started
	ready = true

func _connect(space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> void:
	astar.clear()
	astar.reserve_space(cells / 2)
	for s in cells * LEVELS:
		if walkable[s]:
			var c := slot_cell(s)
			astar.add_point(s, Vector2(c.x, c.y))
	for z in depth:
		for x in width:
			for level in LEVELS:
				var a := level * cells + index(x, z)
				if not walkable[a]:continue
				for offset in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
					var n: Vector2i = Vector2i(x, z) + offset
					if not inside(n):continue
					for other in LEVELS:
						var b := other * cells + index(n.x, n.y)
						if walkable[b] and _linked(space, exclude, a, b, offset):astar.connect_points(a, b)
	# Keep routes off edges: a floor that is missing any of its 8 links sits at a drop,
	# a wall or a ramp's side; it and the ring next to it cost more to walk on.
	var edge := {}
	for s in astar.get_point_ids():
		if astar.get_point_connections(s).size() < 8:edge[s] = true
	for s in astar.get_point_ids():
		var cost := 3.0 if edge.has(s) else 1.0
		if tight[s]:cost *= 2.5
		if cost == 1.0:
			for other in astar.get_point_connections(s):
				if edge.has(other):
					cost = 1.8
					break
		astar.set_point_weight_scale(s, cost)
	_label_components()
	if _bridge_components(space, exclude) > 0:_label_components()

## Connected areas; the largest is the main one routes snap to.
func _label_components() -> void:
	component.fill(-1)
	var next_id := 0
	var sizes := {}
	for s in cells * LEVELS:
		if not astar.has_point(s) or component[s] >= 0:continue
		var stack := [s]
		component[s] = next_id
		var count := 0
		while not stack.is_empty():
			var at: int = stack.pop_back()
			count += 1
			for other in astar.get_point_connections(at):
				if component[other] < 0:
					component[other] = next_id
					stack.append(other)
		sizes[next_id] = count
		next_id += 1
	component_size = sizes
	var best := 0
	for id in sizes:
		if sizes[id] > best:
			best = sizes[id]
			main_component = id

## Neighbouring floors in different areas that the body probe kept apart (a squeeze
## beside a stair ramp, a curb the step-up climbs): link them when a player-sized
## capsule can actually move from one to the other.
func _bridge_components(space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> int:
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.2
	var motion := PhysicsShapeQueryParameters3D.new()
	motion.shape = capsule
	motion.collision_mask = 3
	motion.exclude = exclude
	var added := 0
	for s in astar.get_point_ids():
		var c := slot_cell(s)
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				if dx == 0 and dz == 0:continue
				var n := c + Vector2i(dx, dz)
				if not inside(n):continue
				for level in LEVELS:
					var t := level * cells + index(n.x, n.y)
					if t <= s or not walkable[t] or component[t] == component[s]:continue
					if absf(heights[t] - heights[s]) > HOP or astar.are_points_connected(s, t):continue
					# ground under the whole way, rising a step at a time, or once by a ledge low
					# enough to jump (a hop: the guide says so); never across a stream or a wall
					var ground := _ground_profile(space, exclude, center(s), center(t))
					if ground == 0:continue
					# hops only between real areas, not onto a bench or a table top
					if ground == 2 and mini(int(component_size.get(component[s], 0)), int(component_size.get(component[t], 0))) < 24:continue
					var low := s if heights[s] <= heights[t] else t
					var high := t if low == s else s
					# capsule bottom .25 above the floor: only a curb the step-up climbs is ignored
					var lift := Vector3.UP * (heights[high] - heights[low] + .25 + .6)
					motion.transform = Transform3D(Basis.IDENTITY, center(low) + lift)
					motion.motion = center(high) - center(low)
					motion.motion.y = 0
					var free := space.cast_motion(motion)
					# and room to stand at the low end with the capsule lowered to the step height
					motion.transform = Transform3D(Basis.IDENTITY, center(low) + Vector3.UP * (.25 + .6))
					motion.motion = Vector3.UP * (heights[high] - heights[low])
					var rise := space.cast_motion(motion)
					if free[0] >= .999 and rise[0] >= .999:
						astar.connect_points(s, t)
						added += 1
						if ground == 2:
							hops[s] = true
							hops[t] = true
	return added

func _linked(space: PhysicsDirectSpaceState3D, exclude: Array[RID], a: int, b: int, offset: Vector2i) -> bool:
	var run := Vector2(offset).length() * CELL
	var rise := heights[b] - heights[a]
	if absf(rise) > MAX_RISE * run:return false
	# The surface itself must explain the rise (a ramp); otherwise it is a ledge,
	# e.g. the side of a stair ramp, and only a small step is climbable.
	var step := Vector2(offset) * CELL
	if minf(absf(rise - _slope_rise(normals[a], step)), absf(rise - _slope_rise(normals[b], step))) > STEP:return false
	if offset.x != 0 and offset.y != 0:
		var c := slot_cell(a)
		if not (_floor_near(c.x + offset.x, c.y, heights[a]) and _floor_near(c.x, c.y + offset.y, heights[a])):return false
	# Climbing links and anything under an overhang must not pass through a wall face
	if absf(rise) > .1 or a >= cells or b >= cells:return not _wall_between(space, exclude, a, b)
	return true

func _floor_near(x: int, z: int, y: float) -> bool:
	for level in LEVELS:
		var s := level * cells + index(x, z)
		if walkable[s] and absf(heights[s] - y) < .6:return true
	return false

## True when walking from slot a to b meets a vertical face (a ramp's side, a wall).
## `lifts` above the lower floor; bridges pass only taller ones, since the step-up
## climbs a low ramp side.
func _wall_between(space: PhysicsDirectSpaceState3D, exclude: Array[RID], a: int, b: int, lifts := [.12, .3, .9]) -> bool:
	var low := a if heights[a] < heights[b] else b
	var high := b if low == a else a
	var from := center(low)
	var to := center(high)
	for lift in lifts:
		# both ways: a cell centre can sit inside a thin wall, and a ray never hits from inside
		for flip in [false, true]:
			var near := Vector3(from.x, from.y + lift, from.z)
			var far := Vector3(to.x, from.y + lift, to.z)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(far if flip else near, near if flip else far, 3, exclude))
			if not hit.is_empty() and absf(hit.normal.y) < .55:return true
	return false

## 0 blocked, 1 walkable in steps, 2 needs one jump up or down a ledge of at most HOP.
func _ground_profile(space: PhysicsDirectSpaceState3D, exclude: Array[RID], from: Vector3, to: Vector3) -> int:
	var top := maxf(from.y, to.y) + 1.5
	var last := from.y
	var jumped := false
	var samples := int(ceil(Vector2(to.x - from.x, to.z - from.z).length() / .15))
	for i in range(1, samples + 1):
		var p := from.lerp(to, float(i) / samples)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, top, p.z), Vector3(p.x, minf(from.y, to.y) - 1.0, p.z), 3, exclude))
		if hit.is_empty():return 0
		var change := absf(hit.position.y - last)
		if change > STEP:
			if jumped or change > HOP:return 0
			jumped = true
		# no wall standing on this spot: from under one this meets its underside, which sits at
		# floor level (from inside a wall a ray sees nothing); rails higher up are left to the capsule
		var overhead := space.intersect_ray(PhysicsRayQueryParameters3D.create(hit.position + Vector3.UP * .03, hit.position + Vector3.UP * .5, 3, exclude))
		if not overhead.is_empty():return 0
		last = hit.position.y
	if absf(last - to.y) > STEP:return 0
	return 2 if jumped else 1

## True when a route leg from a to b is a hop (both ends sit on a hop link).
func is_hop(a: Vector3, b: Vector3) -> bool:
	var sa := nearest_slot(a, .5, true)
	var sb := nearest_slot(b, .5, true)
	return sa >= 0 and sb >= 0 and hops.has(sa) and hops.has(sb) and absf(heights[sa] - heights[sb]) > STEP

static func _slope_rise(n: Vector3, step: Vector2) -> float:
	return -(n.x * step.x + n.z * step.y) / maxf(n.y, .3)

## Nearest walkable slot (main area unless any_component) within `reach` metres, or -1.
func nearest_slot(p: Vector3, reach := 3.0, any_component := false) -> int:
	if not ready:return -1
	var c := cell_of(p)
	var best := -1
	var best_score := INF
	var r := int(ceil(reach / CELL))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var n := c + Vector2i(dx, dz)
			if not inside(n):continue
			for level in LEVELS:
				var s := level * cells + index(n.x, n.y)
				if not walkable[s] or (not any_component and component[s] != main_component):continue
				var score := Vector2(dx, dz).length() * CELL + absf(heights[s] - p.y) * 1.5
				if score < best_score:
					best_score = score
					best = s
	return best

## Cell of the nearest walkable floor, (-1,-1) when none.
func nearest(p: Vector3, reach := 3.0, any_component := false) -> Vector2i:
	var s := nearest_slot(p, reach, any_component)
	return slot_cell(s) if s >= 0 else Vector2i(-1, -1)

func reachable(p: Vector3, reach := 3.0) -> bool:
	return nearest_slot(p, reach) >= 0

## World-space points from `from` to `to` along walkable floors; empty when no route.
func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	# Snap to the main walkable area first; small isolated patches (a fountain rim) only as a fallback
	var a := nearest_slot(from, 3.0)
	if a < 0:a = nearest_slot(from, 3.0, true)
	var b := nearest_slot(to, 4.0)
	if b < 0:b = nearest_slot(to, 4.0, true)
	if a < 0 or b < 0 or component[a] != component[b]:return out
	for s in astar.get_id_path(a, b):out.append(center(s))
	return out

static func length_of(points: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):total += points[i - 1].distance_to(points[i])
	return total
