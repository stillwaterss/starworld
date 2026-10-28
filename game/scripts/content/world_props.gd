extends Node3D
## World objects the story uses, built on the scene from island_meta.json:
## doors that swing open (warm light inside), the tree-house window glow, the keeper's
## lighthouse beam, the five islet keepsakes (sign, mailbox, bell, spring, lamp) and the
## locations they stand at, registered so story, map and guide follow the real scene.
var content
var world: Node3D
var doors := {}             # id -> {node, info, front, open, light, blocker}
var window_glow: MeshInstance3D
var beam: Node3D
var beacon_material: StandardMaterial3D
var keepsakes := {}
var spring: Node3D
var _clock := 0.0

func _ready() -> void:
	name = "WorldProps"
	world = content.world
	_setup.call_deferred()

func _meta() -> Dictionary:
	return world.meta if world.get("meta") is Dictionary else {}

func _v(raw) -> Vector3:return Vector3(raw[0], raw[1], raw[2])

func _ground(p: Vector3, up := 3.0) -> Vector3:
	var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * up, p + Vector3.DOWN * 8.0, 1))
	return hit.position if not hit.is_empty() else p

func _setup() -> void:
	for i in 4:await get_tree().physics_frame
	var guard := 0
	while not content.grid.ready and guard < 120:
		await get_tree().physics_frame
		guard += 1
	var meta := _meta()
	var info_all: Dictionary = meta.get("doors", {})
	for node: Node3D in world.find_children("Decor_Door_*", "Node3D", true, false):
		var id := String(node.name).trim_prefix("Decor_Door_")
		if not info_all.has(id):continue
		doors[id] = {"node": node, "info": info_all[id], "front": _v(info_all[id].front), "open": false, "rest": node.rotation.y}
	_register_places(meta)
	_build_keepsakes()
	if content.state.flag("reaction_lighthouse_lit"):light_lighthouse(false)
	if content.state.flag("window_polished") or content.state.flag("ev_window_polished"):light_window(false)
	_guard_keeper_isle()
	if content.state.flag("keeper_door_open"):open_door("keeper", true, false)
	elif doors.has("keeper"):_block_doorway("keeper")
	content.registry.refresh()
	content.ui.refresh()

## Door centre and the walkable side in front of it (the scene's hint can be flipped).
## Props sometimes stand right outside a door, so each side is searched outward for
## the first open outdoor cell (no roof above it) near the doorstep height.
func door_front(id: String) -> Vector3:
	var d: Dictionary = doors[id]
	var info: Dictionary = d.info
	var centre := _v(info.centre)
	var base := Vector3(centre.x, centre.y - float(info.height) / 2.0, centre.z)
	var normal: Vector3 = d.front
	var distance := .95
	if content.grid.ready:
		var ahead := _stand_distance(base, normal)
		var behind := _stand_distance(base, -normal)
		if ahead < 0 and behind > 0 or (behind > 0 and ahead > 0 and behind < ahead - .5):
			normal = -normal
			ahead = behind
		if ahead > 0:distance = ahead
	d.front = normal
	return base + normal * distance

func _stand_distance(base: Vector3, normal: Vector3) -> float:
	var grid = content.grid
	for distance in [.95, 1.25, 1.6, 2.0, 2.4]:
		var slot: int = grid.nearest_slot(base + normal * distance, .4, true)
		if slot >= 0 and slot < grid.cells and absf(grid.center(slot).y - base.y) < .6:return distance
	return -1.0

func _register_places(meta: Dictionary) -> void:
	var registry = content.registry
	for id in ["baker", "child", "grandma", "lamplighter", "islet_nw", "islet_ne", "islet_e", "islet_sw", "isle_south_r"]:
		if doors.has(id):registry.register("door_" + id, _ground(door_front(id), 1.0) + Vector3.UP * .1, 1.6)
	var keeper: Dictionary = meta.get("keeper_isle", {})
	if not keeper.is_empty():
		registry.register("keeper_isle", _v(keeper.center), 9.0)
		registry.register("keeper_dock", _v(keeper.pier_start) + Vector3(-1.2, .1, 0), 2.0)
		registry.register("keeper_house", _v(keeper.house_door), 1.6)
		registry.register("keeper_desk", _v(keeper.desk), 1.3)
		registry.register("keeper_lamp", _v(keeper.gallery), 1.6)
		registry.register("keeper_tower", _v(keeper.tower_door), 1.6)
	var star := _ground(Vector3(1.75, 0, 1.9), 2.0)
	registry.register("fallen_star", star + Vector3.UP * .05, 1.6)

# ------------------------------------------------------------------ doors
func open_door(id: String, stay := false, animate := true) -> void:
	if not doors.has(id):return
	var d: Dictionary = doors[id]
	if d.open:return
	d.open = true
	var node: Node3D = d.node
	var leaf_dir := Vector3.RIGHT if String(d.info.axis) == "x" else Vector3.FORWARD
	door_front(id)
	var angle := deg_to_rad(100.0 if id in ["keeper", "tower", "treehouse"] else 58.0)
	if leaf_dir.rotated(Vector3.UP, angle).dot(d.front) < 0:angle = -angle
	var goal: float = float(d.rest) + angle
	if animate:create_tween().tween_property(node, "rotation:y", goal, .9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:node.rotation.y = goal
	# warm light from inside, as if someone just lit a lamp
	if not d.has("light"):
		var centre := _v(d.info.centre)
		var glow := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(float(d.info.width) * .92, float(d.info.height) * .95)
		glow.mesh = quad
		var warm := StandardMaterial3D.new()
		warm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		warm.albedo_color = Color(1, .78, .45)
		warm.emission_enabled = true
		warm.emission = Color(1, .74, .4)
		warm.emission_energy_multiplier = 1.6
		glow.material_override = warm
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(glow)
		glow.global_position = centre - d.front * .06
		glow.look_at(glow.global_position - d.front, Vector3.UP)
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1, .76, .45)
		lamp.light_energy = 1.2
		lamp.omni_range = 3.2
		add_child(lamp)
		lamp.global_position = centre + d.front * .4
		d.light = [glow, lamp]
		if animate:
			glow.scale = Vector3(.01, 1, 1)
			create_tween().tween_property(glow, "scale", Vector3.ONE, .9)
	if world.get("audio"):world.audio.play_sfx("door")
	if d.has("blocker"):
		d.blocker.queue_free()
		d.erase("blocker")
	if id == "keeper":content.state.set_flag("keeper_door_open")
	if not stay and not id in ["keeper", "tower"]:
		get_tree().create_timer(9.0).timeout.connect(close_door.bind(id))

func close_door(id: String) -> void:
	if not doors.has(id) or not doors[id].open:return
	var d: Dictionary = doors[id]
	# someone is still talking at this door: try again a little later
	if d.get("hold", false):
		get_tree().create_timer(3.0).timeout.connect(close_door.bind(id))
		return
	d.open = false
	create_tween().tween_property(d.node, "rotation:y", float(d.rest), 1.1).set_trans(Tween.TRANS_SINE)
	if d.has("light"):
		for n in d.light:n.queue_free()
		d.erase("light")

## The keeper's cottage has a real doorway: while the door is shut, nobody walks through it.
func _block_doorway(id: String) -> void:
	var d: Dictionary = doors[id]
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var axis_x := String(d.info.axis) == "x"
	box.size = Vector3(float(d.info.width) if axis_x else .2, float(d.info.height), .2 if axis_x else float(d.info.width))
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = _v(d.info.centre)
	d.blocker = body

# ------------------------------------------------------------------ lighthouse island guard
## The lighthouse island's edge and pier get an invisible rail, 1.3 m high: the visible
## fences have gaps the player could slip through. The edge is measured, not assumed:
## for each direction, rays step outward until there is no more ground at the island's
## height; the rail stands just inside that. The pier's land end stays open.
func _guard_keeper_isle() -> void:
	var keeper: Dictionary = _meta().get("keeper_isle", {})
	if not keeper.has("center"):return
	var centre := _v(keeper.center)
	var y := float(keeper.pier_start[1]) if keeper.has("pier_start") else centre.y
	var pier_start := _v(keeper.pier_start) if keeper.has("pier_start") else centre
	var pier_end := _v(keeper.pier_end) if keeper.has("pier_end") else centre
	var space := world.get_world_3d().direct_space_state
	var body := StaticBody3D.new()
	body.name = "KeeperIsleGuard"
	body.collision_layer = 1
	add_child(body)
	var steps := 72
	var edge: Array[Vector3] = []
	for i in steps:
		var a := TAU * i / steps
		var dir := Vector3(cos(a), 0, sin(a))
		var last := 3.0
		var r := 3.0
		while r < 16.0:
			var p := centre + dir * r
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, y + 12.0, p.z), Vector3(p.x, y - 2.5, p.z), 1))
			# a roof or the tower above counts as island; only nothing, or ground well below, is the edge
			if hit.is_empty() or hit.position.y < y - 1.2:break
			last = r
			r += .25
		edge.append(centre + dir * (last - .15))
	var pier_dir := (pier_end - pier_start)
	pier_dir.y = 0
	pier_dir = pier_dir.normalized()
	for i in steps:
		var a: Vector3 = edge[i]
		var b: Vector3 = edge[(i + 1) % steps]
		var mid := (a + b) / 2
		# leave the way onto the pier open
		var off := mid - pier_start
		off.y = 0
		if off.length() < 2.2:continue
		_guard_wall(body, a, b, y)
	var across := pier_dir.cross(Vector3.UP).normalized()
	for s in [-1.0, 1.0]:
		_guard_wall(body, pier_start + across * s * .95, pier_end + across * s * .95, y)

func _guard_wall(body: StaticBody3D, a: Vector3, b: Vector3, floor_y: float) -> void:
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	if length < .05:return
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length + .1, 1.3, .12)
	shape.shape = box
	body.add_child(shape)
	var mid := (a + b) / 2
	shape.global_position = Vector3(mid.x, floor_y + .65, mid.z)
	shape.rotation.y = -atan2(b.z - a.z, b.x - a.x)

# ------------------------------------------------------------------ tree-house window
func light_window(animate := true) -> void:
	if is_instance_valid(window_glow):return
	window_glow = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = .21
	disc.bottom_radius = .21
	disc.height = .01
	disc.radial_segments = 24
	window_glow.mesh = disc
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, .86, .55)
	m.emission_enabled = true
	m.emission = Color(1, .82, .5)
	m.emission_energy_multiplier = 1.2
	window_glow.material_override = m
	var parent: Node3D = doors.treehouse.node if doors.has("treehouse") else self
	parent.add_child(window_glow)
	window_glow.global_position = Vector3(0, 2.8, -.38)
	window_glow.global_rotation = Vector3(PI / 2, 0, 0)
	var light := OmniLight3D.new()
	light.light_color = Color(1, .82, .52)
	light.omni_range = 2.6
	light.light_energy = .8
	window_glow.add_child(light)
	light.position = Vector3(0, .3, 0)
	if animate:
		m.emission_energy_multiplier = 4.0
		create_tween().tween_property(m, "emission_energy_multiplier", 1.2, 2.0)
		_sparkle(window_glow.global_position + Vector3(0, 0, .1))

func _sparkle(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = .8
	p.direction = Vector3(0, 1, 1)
	p.spread = 70
	p.initial_velocity_min = .4
	p.initial_velocity_max = 1.0
	p.gravity = Vector3(0, -.3, 0)
	var m := SphereMesh.new()
	m.radial_segments = 12
	m.rings = 6
	m.radius = .02
	m.height = .04
	p.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, .95, .7)
	p.material_override = mat
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)

# ------------------------------------------------------------------ lighthouse
func light_lighthouse(animate := true) -> void:
	content.state.set_flag("reaction_lighthouse_lit")
	var keeper: Dictionary = _meta().get("keeper_isle", {})
	if keeper.is_empty() or is_instance_valid(beam):return
	var lamp_at := _v(keeper.lamp)
	for node: MeshInstance3D in world.find_children("Decor_Keeper_beacon*", "MeshInstance3D", true, false):
		beacon_material = StandardMaterial3D.new()
		beacon_material.albedo_color = Color(1, .9, .6)
		beacon_material.emission_enabled = true
		beacon_material.emission = Color(1, .86, .5)
		beacon_material.emission_energy_multiplier = 3.0
		node.material_override = beacon_material
	beam = Node3D.new()
	beam.name = "LighthouseBeam"
	add_child(beam)
	beam.global_position = lamp_at
	for side in [0.0, PI]:
		var arm := Node3D.new()
		arm.rotation.y = side
		beam.add_child(arm)
		var cone := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = .25
		mesh.bottom_radius = 5.5
		mesh.height = 60.0
		mesh.radial_segments = 16
		mesh.cap_top = false
		mesh.cap_bottom = false
		cone.mesh = mesh
		var m := ShaderMaterial.new()
		m.shader = _beam_shader()
		cone.material_override = m
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone.rotation.x = PI / 2 - .06   # narrow top at the lamp, opening outward along -Z
		cone.position = Vector3(0, 0, -30.0)
		arm.add_child(cone)
		var spot := SpotLight3D.new()
		spot.light_color = Color(1, .88, .6)
		spot.light_energy = 3.0
		spot.spot_range = 60.0
		spot.spot_angle = 6.0
		arm.add_child(spot)
	var light := OmniLight3D.new()
	light.light_color = Color(1, .86, .55)
	light.omni_range = 6.0
	light.light_energy = 2.0
	beam.add_child(light)
	if animate:
		if world.get("audio"):world.audio.play_sfx("lighthouse")
		beam.scale = Vector3(.01, .01, .01)
		create_tween().tween_property(beam, "scale", Vector3.ONE, 2.5).set_trans(Tween.TRANS_SINE)

## Soft light shaft: warm core, edges and far end fade out, additive so it glows on the night sky.
func _beam_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec3 tint : source_color = vec3(1.0, 0.8, 0.46);
uniform float strength = 0.55;
void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 2.5);
	float from_lamp = UV.y;   // 0 at the narrow top (the lamp), 1 at the far end
	float fade = pow(clamp(1.0 - from_lamp, 0.0, 1.0), 1.6) * smoothstep(0.0, 0.04, from_lamp);
	ALBEDO = tint * core * fade * strength;
}
"""
	return shader

func _process(delta: float) -> void:
	_clock += delta
	if is_instance_valid(beam):
		beam.rotation.y += delta * .35
		var w: Vector3 = world.day_cycle.weights
		var dark := clampf(w.y * .6 + w.z, .15, 1.0)
		for arm in beam.get_children():
			if arm.get_child_count() == 0:continue
			var cone: MeshInstance3D = arm.get_child(0)
			cone.material_override.set_shader_parameter("strength", .12 + .5 * dark)   # faint by day, full at night
	if is_instance_valid(spring):
		spring.get_child(0).rotation.y += delta * .3

# ------------------------------------------------------------------ islet keepsakes
func _mat(color: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = .75
	if glow > 0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m

func _piece(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.position = at
	n.rotation = rot
	n.material_override = mat
	parent.add_child(n)
	return n

func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b

func _cyl(r: float, h: float, top := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r if top < 0 else top
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	return c

## Each islet gets one small thing to find; its stand point is registered as "<islet>_thing".
func _build_keepsakes() -> void:
	var registry = content.registry
	var wood := _mat(Color("8a5f3c"))
	var cream := _mat(Color("efe1c2"))
	var brass := _mat(Color("d9b46a"))
	var specs := {
		"islet_nw": Vector3(2.2, 0, 1.6), "islet_e": Vector3(1.4, 0, 1.0), "islet_sw": Vector3(-1.0, 0, -1.4),
		"isle_south_l": Vector3(.6, 0, .8), "isle_south_r": Vector3(-1.6, 0, .6),
	}
	for id in specs:
		if not registry.has(id):continue
		var base := _ground(registry.position_of(id) + specs[id], 4.0)
		var root := Node3D.new()
		root.name = "Keepsake_" + id
		add_child(root)
		root.global_position = base
		root.rotation.y = randf() * TAU
		match id:
			"islet_nw":   # a small carved sign on a post
				_piece(root, _cyl(.05, 1.1), Vector3(0, .55, 0), wood)
				_piece(root, _box(.62, .32, .05), Vector3(0, 1.0, 0), cream)
			"islet_e":    # a mailbox nobody addressed
				_piece(root, _cyl(.05, 1.0), Vector3(0, .5, 0), wood)
				_piece(root, _box(.34, .26, .46), Vector3(0, 1.05, 0), _mat(Color("6f90b8")))
				_piece(root, _box(.05, .18, .03), Vector3(.19, 1.16, .1), _mat(Color("d36a5a")))
			"islet_sw":   # a bell close to the clouds
				_piece(root, _cyl(.06, 1.5), Vector3(-.35, .75, 0), wood)
				_piece(root, _box(.8, .06, .06), Vector3(0, 1.48, 0), wood)
				_piece(root, _cyl(.06, .2, .14), Vector3(.2, 1.3, 0), brass)
			"isle_south_l":   # a tiny spring ringed with stones (the fireflies come here)
				var water := _piece(root, _cyl(.55, .04), Vector3(0, .03, 0), _mat(Color(.55, .8, .95), .4))
				water.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				water.material_override.albedo_color.a = .8
				for k in 9:
					var a := TAU * k / 9.0
					_piece(root, _box(.2, .12, .16), Vector3(cos(a) * .7, .05, sin(a) * .7), _mat(Color("b8b3a6")), Vector3(0, a, 0))
				spring = root
				registry.register("firefly_spring", base + Vector3.UP * .1, 2.2)
			"isle_south_r":   # a little lamp on a stake, unlit
				_piece(root, _cyl(.04, 1.2), Vector3(0, .6, 0), wood)
				_piece(root, _cyl(.12, .22, .09), Vector3(0, 1.3, 0), _mat(Color("ffe0a0"), .1))
		keepsakes[id] = root
		registry.register(id + "_thing", base + Vector3.UP * .1, 1.6)
		# the modelled version, when there is one: the simple pieces stay as hidden handles
		# (the east islet keeps its own simple mailbox: the modelled one read as broken)
		var model_name := {"islet_sw": "bell_post", "isle_south_r": "lamp_post"}.get(id, "") as String
		var model := prop(model_name, {"islet_e": 1.25, "islet_sw": 1.6, "isle_south_r": 1.5}.get(id, 1.0))
		if model:
			for piece in root.get_children():piece.visible = false
			root.add_child(model)
			root.set_meta("model", model)
		# solid, so the player stands beside it instead of inside it (the examine reaches 1.6 m)
		if id in ["islet_e", "islet_sw", "isle_south_r", "islet_nw"]:
			var solid := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var post := CylinderShape3D.new()
			post.radius = .34 if id == "islet_e" else .24
			post.height = 1.4
			shape.shape = post
			shape.position.y = .7
			solid.add_child(shape)
			root.add_child(solid)
	_swap_telescope()

## A Tripo prop from assets/props (made 1 unit tall, standing on its origin), `height` m.
const PROPS := "res://assets/props/"

func prop(prop_name: String, height: float) -> Node3D:
	if prop_name == "" or not ResourceLoader.exists(PROPS + "prop_" + prop_name + ".glb"):return null
	var node: Node3D = (load(PROPS + "prop_" + prop_name + ".glb") as PackedScene).instantiate()
	node.scale = Vector3.ONE * height
	return node

## The modelled brass telescope in place of the scene's simple one, the same size and
## turned the same way (its long side along the old one's).
func _swap_telescope() -> void:
	var parts: Array[MeshInstance3D] = []
	for mesh: MeshInstance3D in world.find_children("Telescope_*", "MeshInstance3D", true, false):parts.append(mesh)
	if parts.is_empty() or not ResourceLoader.exists(PROPS + "prop_telescope.glb"):return
	var box: AABB = parts[0].global_transform * parts[0].get_aabb()
	for mesh in parts:box = box.merge(mesh.global_transform * mesh.get_aabb())
	var model := prop("telescope", box.size.y * 1.05)
	if model == null:return
	for mesh in parts:mesh.visible = false
	add_child(model)
	model.global_position = Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var own := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = model.global_transform.affine_inverse() * (mesh.global_transform * mesh.get_aabb())
		own = b if first else own.merge(b)
		first = false
	if (own.size.x > own.size.z) != (box.size.x > box.size.z):model.rotation.y = PI / 2

func light_keepsake_lamp() -> void:
	if not keepsakes.has("isle_south_r"):return
	var lamp: MeshInstance3D = keepsakes.isle_south_r.get_child(1)
	lamp.material_override.emission_energy_multiplier = 2.4
	# only the lantern glows (lighting the whole model's colours washed it white)
	if keepsakes.isle_south_r.has_meta("model"):
		var spot: Vector3 = preload("res://scripts/content/island_lights.gd").lantern_spot(keepsakes.isle_south_r.get_meta("model"))
		var glow := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = .1
		ball.height = .2
		glow.mesh = ball
		glow.material_override = _mat(Color(1, .86, .55), 3.0)
		glow.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		add_child(glow)
		glow.global_position = spot
	var l := OmniLight3D.new()
	l.light_color = Color(1, .84, .55)
	l.omni_range = 3.0
	keepsakes.isle_south_r.add_child(l)
	l.position = Vector3(0, 1.3, 0)

## Makes a model's lamp glass glow: every material gets a warm emission.
func _glow_model(model: Node3D, energy: float) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.get_surface_override_material_count():
			var base := mesh.get_active_material(i)
			if not base is StandardMaterial3D:continue
			var m: StandardMaterial3D = base.duplicate()
			m.emission_enabled = true
			m.emission = Color(1, .8, .45)
			m.emission_energy_multiplier = energy * .25
			if m.albedo_texture:
				m.emission_texture = m.albedo_texture
				m.emission_energy_multiplier = energy * .5
			mesh.set_surface_override_material(i, m)

func ring_bell() -> void:
	if not keepsakes.has("islet_sw"):return
	var bell: Node3D = keepsakes.islet_sw.get_child(2)
	# the modelled post rocks a little instead (its bell is part of the model)
	var swing := .35
	if keepsakes.islet_sw.has_meta("model"):
		bell = keepsakes.islet_sw.get_meta("model")
		swing = .05
	var t := create_tween()
	for k in 5:
		t.tween_property(bell, "rotation:z", swing * (1 - k / 5.0) * (1 if k % 2 == 0 else -1), .22)
	t.tween_property(bell, "rotation:z", 0.0, .3)
	if world.get("audio"):world.audio.play_sfx("windchime")

func firefly_spring_glow() -> void:
	if is_instance_valid(spring):
		var water: MeshInstance3D = spring.get_child(0)
		water.material_override.emission_energy_multiplier = 2.2
