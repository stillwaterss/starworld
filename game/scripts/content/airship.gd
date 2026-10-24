extends Node3D
## The old airship at the west dock. Its Airship_* meshes are moved onto one rig that
## flies smooth curves: dock -> keeper's island, back, and the last night flight up above
## the clouds. A rail with a closing gate rings the gondola deck; the player stands in
## the middle, carried by the rig (physics off, so nothing can clip). E hurries a flight.
signal arrived(place: String)
signal at_summit

var content
var world: Node3D
var rig: Node3D
var deck_offset := Vector3.ZERO     # deck stand point relative to the rig origin
var home_transform := Transform3D()
var at := "dock"                    # dock, keeper_isle, flying
var gate: Node3D
var camera: Camera3D
var ship_lamp: OmniLight3D
var lamp_glass: MeshInstance3D
var hurry := false
var _cam_yaw := 0.0
var _cam_drag := false
var _hidden_layers: Array[CanvasLayer] = []

func _ready() -> void:
	name = "Airship"
	world = content.world
	camera = Camera3D.new()
	camera.name = "AirshipCamera"
	camera.fov = 52
	camera.far = 1500
	add_child(camera)
	_setup.call_deferred()

func flying() -> bool:return at == "flying"

func _setup() -> void:
	for i in 2:await get_tree().physics_frame
	var parts: Array[Node] = world.find_children("Airship_*", "MeshInstance3D", true, false)
	if parts.is_empty():return
	var hull: MeshInstance3D = null
	var deck: MeshInstance3D = null
	for p: MeshInstance3D in parts:
		if String(p.name).begins_with("Airship_wood_001") or (hull == null and String(p.name).begins_with("Airship_wood")):hull = p
		if String(p.name).begins_with("Airship_wood_light"):deck = p
	if hull == null:hull = parts[0]
	var hull_box: AABB = hull.global_transform * hull.get_aabb()
	rig = Node3D.new()
	rig.name = "AirshipRig"
	world.add_child(rig)
	rig.global_position = hull_box.get_center()
	home_transform = rig.global_transform
	for p in parts:p.reparent(rig, true)
	var deck_box: AABB = (deck.global_transform * deck.get_aabb()) if deck else hull_box
	deck_offset = Vector3(deck_box.get_center().x, deck_box.end.y + .02, deck_box.get_center().z) - rig.global_position
	_build_rail(deck_box)
	_build_lamp(deck_box)
	if content.state.flag("ship_lamp_lit"):light_lamp(false)
	if content.state.flag("airship_at_keeper"):
		_park_at(_keeper_rest())
		at = "keeper_isle"

func _keeper_rest() -> Vector3:
	var keeper: Dictionary = world.meta.get("keeper_isle", {})
	return Vector3(keeper.airship_rest[0], keeper.airship_rest[1], keeper.airship_rest[2]) if keeper.has("airship_rest") else home_transform.origin + Vector3(60, 14, 18)

func deck_point() -> Vector3:
	return rig.global_transform * (home_transform.basis.inverse() * deck_offset) if rig else Vector3.ZERO

func _park_at(deck_world: Vector3) -> void:
	rig.global_transform = Transform3D(home_transform.basis, deck_world - deck_offset)

func _mat(color: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = .7
	if glow > 0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m

## Posts and two rails round the deck edge; the gate (facing the dock) swings shut on take-off.
func _build_rail(deck_box: AABB) -> void:
	var rail := Node3D.new()
	rail.name = "DeckRail"
	rig.add_child(rail)
	var centre := Vector3(deck_box.get_center().x, deck_box.end.y, deck_box.get_center().z)
	rail.global_position = centre
	var r := minf(deck_box.size.x, deck_box.size.z) * .5 - .08
	var wood := _mat(Color("7a5236"))
	var light_wood := _mat(Color("c79a6a"))
	var posts := 14
	var dock_dir: Vector3 = content.registry.position_of("dock") - centre
	var gate_angle := atan2(dock_dir.z, dock_dir.x)
	var points: Array[Vector3] = []
	for i in posts:
		var a := gate_angle + TAU * (i + .5) / posts
		points.append(Vector3(cos(a) * r, 0, sin(a) * r))
	for i in posts:
		var post := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = .035
		c.bottom_radius = .04
		c.height = .95
		c.radial_segments = 8
		post.mesh = c
		post.material_override = wood
		post.position = points[i] + Vector3.UP * .47
		rail.add_child(post)
	for i in posts - 1:
		for h in [.5, .92]:
			rail.add_child(_bar(points[i] + Vector3.UP * h, points[i + 1] + Vector3.UP * h, light_wood))
	gate = Node3D.new()
	gate.name = "Gate"
	gate.position = points[posts - 1]
	rail.add_child(gate)
	for h in [.5, .92]:
		gate.add_child(_bar(Vector3.UP * h, points[0] - points[posts - 1] + Vector3.UP * h, light_wood))
	gate.rotation.y = 1.6

func _bar(a: Vector3, b: Vector3, mat: Material) -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = .028
	c.bottom_radius = .028
	c.height = a.distance_to(b)
	c.radial_segments = 6
	bar.mesh = c
	bar.material_override = mat
	bar.position = (a + b) / 2
	bar.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	return bar

## A lamp on a post at the bow; 小光 lights it in chapter four.
func _build_lamp(deck_box: AABB) -> void:
	var post := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.radial_segments = 10
	c.rings = 1
	c.top_radius = .04
	c.bottom_radius = .05
	c.height = 1.5
	post.mesh = c
	post.material_override = _mat(Color("6b4a30"))
	rig.add_child(post)
	var bow := Vector3(deck_box.position.x + .25, deck_box.end.y, deck_box.get_center().z)
	post.global_position = bow + Vector3.UP * .75
	lamp_glass = MeshInstance3D.new()
	var g := CylinderMesh.new()
	g.radial_segments = 10
	g.rings = 1
	g.top_radius = .1
	g.bottom_radius = .12
	g.height = .22
	lamp_glass.mesh = g
	lamp_glass.material_override = _mat(Color("f2e2b8"))
	rig.add_child(lamp_glass)
	lamp_glass.global_position = bow + Vector3.UP * 1.6
	ship_lamp = OmniLight3D.new()
	ship_lamp.light_color = Color(1, .84, .52)
	ship_lamp.omni_range = 5.0
	ship_lamp.light_energy = 0
	rig.add_child(ship_lamp)
	ship_lamp.global_position = lamp_glass.global_position

func light_lamp(animate := true) -> void:
	content.state.set_flag("ship_lamp_lit")
	if not is_instance_valid(ship_lamp):return
	lamp_glass.material_override = _mat(Color("ffd890"), 2.4)
	if animate:create_tween().tween_property(ship_lamp, "light_energy", 1.6, 1.5)
	else:ship_lamp.light_energy = 1.6
	content.events.emit("ship_lamp_lit", {"place": "dock"})

# ------------------------------------------------------------------ flights
func _route(to: String) -> PackedVector3Array:
	var start := deck_point()
	var keeper := _keeper_rest()
	var home := home_transform * (home_transform.basis.inverse() * deck_offset)
	match to:
		"keeper_isle":
			return PackedVector3Array([start, start + Vector3(0, 6, 1), Vector3(-14, 18, 26), Vector3(6, 23, 40), Vector3(25, 20, 36), keeper + Vector3(-5, 4, 3), keeper])
		"dock":
			if at == "keeper_isle" or start.distance_to(keeper) < 3.0:
				return PackedVector3Array([start, start + Vector3(-4, 5, 2), Vector3(25, 21, 38), Vector3(4, 24, 42), Vector3(-16, 17, 26), home + Vector3(2, 5, 2), home])
			return PackedVector3Array([start, start + Vector3(0, 10, 0), Vector3(-14, 20, 10), home + Vector3(2, 5, 2), home])
		"summit":
			return PackedVector3Array([start, start + Vector3(0, 7, 0), Vector3(-16, 22, 8), Vector3(-6, 42, -2), Vector3(2, 58, -6)])
	return PackedVector3Array([start])

func _curve(points: PackedVector3Array) -> Curve3D:
	var curve := Curve3D.new()
	for i in points.size():
		var prev := points[maxi(i - 1, 0)]
		var next := points[mini(i + 1, points.size() - 1)]
		var tangent := (next - prev) * .28
		curve.add_point(points[i], -tangent if i > 0 else Vector3.ZERO, tangent if i < points.size() - 1 else Vector3.ZERO)
	curve.bake_interval = .25
	return curve

## Called from the dock examine: decides where this flight goes from the story.
func board() -> void:
	if flying() or not rig:return
	var stage: String = content.director.main_stage().get("id", "")
	var destination := "dock" if at == "keeper_isle" else "keeper_isle"
	if stage == "c5_fly":destination = "summit"
	await fly(destination)

func fly(destination: String) -> void:
	var performance = world.get("performance")
	var player: CharacterBody3D = world.player
	var from := at
	if performance and performance.busy:return
	at = "flying"
	hurry = false
	player.controls_locked = true
	player.velocity = Vector3.ZERO
	_hidden_layers.clear()
	for node in world.get_children():
		if node is CanvasLayer and node.visible and node != content.ui:
			_hidden_layers.append(node)
			node.visible = false
	# step onto the deck
	var board_from := player.global_position
	player.set_physics_process(false)
	camera.global_transform = world.get_viewport().get_camera_3d().global_transform
	camera.current = true
	var hop := create_tween()
	hop.tween_method(func(t: float):player.global_position = board_from.lerp(deck_point(), t) + Vector3.UP * sin(t * PI) * .6, 0.0, 1.0, .8)
	await hop.finished
	if world.get("audio"):world.audio.play_sfx("door")
	create_tween().tween_property(gate, "rotation:y", 0.0, .8)
	content.ui.whisper("扶好栏杆。" if destination != "summit" else "我们往上飞吧。一直往上。")
	var curve := _curve(_route(destination))
	var length := curve.get_baked_length()
	var seconds := clampf(length / 2.4, 12.0, 62.0)
	var t := 0.0
	var yaw := atan2(-home_transform.basis.z.x, -home_transform.basis.z.z)
	_cam_yaw = yaw + 2.4
	while t < seconds:
		var dt := get_process_delta_time() * (5.0 if hurry else 1.0)
		t += dt
		var k := smoothstep(0.0, 1.0, clampf(t / seconds, 0, 1))
		var p := curve.sample_baked(k * length)
		var ahead := curve.sample_baked(minf(k * length + 2.0, length))
		var dir := ahead - p
		dir.y = 0
		if dir.length() > .05:yaw = lerp_angle(yaw, atan2(-dir.x, -dir.z), clampf(dt * 1.2, 0, 1))
		var bob := sin(t * 1.3) * .08
		var deck_world := p + Vector3.UP * bob
		rig.global_transform = Transform3D(Basis(Vector3.UP, yaw - atan2(-home_transform.basis.z.x, -home_transform.basis.z.z)) * home_transform.basis, Vector3.ZERO)
		rig.global_position = deck_world - rig.global_basis * (home_transform.basis.inverse() * deck_offset)
		player.global_position = deck_world
		player.model.rotation.y = yaw
		# slow orbit; the mouse can turn it
		if not _cam_drag:_cam_yaw += dt * .05
		var orbit := Vector3(sin(_cam_yaw), 0, cos(_cam_yaw)) * 9.5 + Vector3.UP * 3.4
		camera.global_position = camera.global_position.lerp(deck_world + orbit, clampf(dt * 2.0, 0, 1))
		camera.look_at(deck_world + Vector3.UP * 1.2, Vector3.UP)
		await get_tree().process_frame
		if destination == "summit" and t >= seconds:break
	if destination == "summit":
		at_summit.emit()
		await content.ending.release_at_summit()
		await fly_after_summit()
		return
	_land(destination, from)

func fly_after_summit() -> void:
	at = "dock"
	await fly_home_from_summit()

func fly_home_from_summit() -> void:
	var curve := _curve(PackedVector3Array([deck_point(), deck_point() + Vector3(-6, -6, 6), Vector3(-16, 16, 14), home_transform * (home_transform.basis.inverse() * deck_offset) + Vector3(2, 5, 2), home_transform * (home_transform.basis.inverse() * deck_offset)]))
	var length := curve.get_baked_length()
	var seconds := clampf(length / 3.0, 10.0, 40.0)
	var t := 0.0
	var player: CharacterBody3D = world.player
	at = "flying"
	while t < seconds:
		var dt := get_process_delta_time() * (5.0 if hurry else 1.0)
		t += dt
		var p := curve.sample_baked(smoothstep(0.0, 1.0, clampf(t / seconds, 0, 1)) * length)
		rig.global_position = p - rig.global_basis * (home_transform.basis.inverse() * deck_offset)
		player.global_position = p
		_cam_yaw += dt * .05
		camera.global_position = camera.global_position.lerp(p + Vector3(sin(_cam_yaw), 0, cos(_cam_yaw)) * 9.5 + Vector3.UP * 3.4, clampf(dt * 2.0, 0, 1))
		camera.look_at(p + Vector3.UP * 1.2, Vector3.UP)
		await get_tree().process_frame
	_land("dock", "summit")

func _land(destination: String, _from: String) -> void:
	var player: CharacterBody3D = world.player
	rig.global_transform = home_transform if destination == "dock" else Transform3D(home_transform.basis, _keeper_rest() - deck_offset)
	at = destination
	content.state.data.flags.erase("airship_at_keeper")
	if destination == "keeper_isle":content.state.set_flag("airship_at_keeper")
	create_tween().tween_property(gate, "rotation:y", 1.6, .8)
	var step_to: Vector3 = content.registry.position_of("keeper_dock" if destination == "keeper_isle" else "dock")
	var from := deck_point()
	var hop := create_tween()
	hop.tween_method(func(t: float):player.global_position = from.lerp(step_to, t) + Vector3.UP * sin(t * PI) * .6, 0.0, 1.0, .8)
	await hop.finished
	player.set_physics_process(true)
	player.velocity = Vector3.ZERO
	player.controls_locked = false
	player.arm.get_child(0).current = true
	for layer in _hidden_layers:
		if is_instance_valid(layer):layer.visible = true
	_hidden_layers.clear()
	content.state.save()
	content.events.emit("airship_arrived", {"place": destination})
	arrived.emit(destination)

func _input(event: InputEvent) -> void:
	if not flying():return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_E, KEY_SPACE]:hurry = true
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		_cam_drag = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventMouseMotion and (_cam_drag or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		_cam_yaw -= event.relative.x * .004
