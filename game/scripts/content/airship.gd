extends Node3D
## The old airship at the west dock. Its Airship_* meshes are moved onto one rig that
## flies smooth curves: dock -> keeper's island, back, and the last night flight up above
## the clouds. A rail with a closing gate rings the gondola deck; the player stands in
## the middle, carried by the rig (physics off, so nothing can clip). After five seconds
## a skip button shows (E / Space / Esc / click) and ends the flight at its destination.
## Boarding and leaving are walked: to the gangway, up the step and onto the deck. At the
## lighthouse island the ship turns its gate to the pier and a plank bridges the gap.
## In flight the camera follows the mouse: moving it left or right turns the view.
signal arrived(place: String)
signal at_summit

var content
var world: Node3D
var rig: Node3D
var deck_offset := Vector3.ZERO     # deck stand point relative to the rig origin
var home_transform := Transform3D()
var at := "dock"                    # dock, keeper_isle, flying
var gate: Node3D
var gate_dir := Vector3.FORWARD     # gate opening, horizontal, in the rig's frame
var gate_reach := .8                # deck centre to the rail
var camera: Camera3D
var ship_lamp: OmniLight3D
var lamp_glass: MeshInstance3D
var hurry := false
var skip := false
const SKIP_AFTER := 5.0
var skip_layer: CanvasLayer
var skip_button: Button
var _cam_yaw := 0.0
var _cam_drag := false
var _look := Vector2.ZERO           # mouse offset from the window centre, -1..1
var _look_smooth := Vector2.ZERO
var _pitch_drag := 0.0
var look_hint: Label
var hull_reach := 2.0               # deck centre to the hull's far edge, along the gate
var gangway: Node3D
var _hidden_layers: Array[CanvasLayer] = []

func _ready() -> void:
	name = "Airship"
	world = content.world
	camera = Camera3D.new()
	camera.name = "AirshipCamera"
	camera.fov = 52
	camera.far = 1500
	add_child(camera)
	_build_skip()
	_setup.call_deferred()

func _build_skip() -> void:
	skip_layer = CanvasLayer.new()
	skip_layer.layer = 6
	add_child(skip_layer)
	skip_button = Button.new()
	skip_button.text = "跳过 ▶▶   E"
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.add_theme_font_size_override("font_size", 18)
	var font := preload("res://assets/fonts/LXGWWenKai-Regular.ttf")
	skip_button.add_theme_font_override("font", font)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(.08, .08, .16, .55)
	box.set_corner_radius_all(18)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	skip_button.add_theme_stylebox_override("normal", box)
	skip_button.add_theme_stylebox_override("hover", box)
	skip_button.add_theme_stylebox_override("pressed", box)
	skip_button.add_theme_color_override("font_color", Color("fff1d7"))
	skip_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip_button.offset_left = -190
	skip_button.offset_top = -74
	skip_button.offset_right = -28
	skip_button.offset_bottom = -28
	skip_button.pressed.connect(func():skip = true)
	skip_button.visible = false
	skip_layer.add_child(skip_button)
	look_hint = Label.new()
	look_hint.text = "移动鼠标  左右转、上下看"
	look_hint.add_theme_font_override("font", font)
	look_hint.add_theme_font_size_override("font_size", 17)
	look_hint.add_theme_color_override("font_color", Color("fff1d7"))
	look_hint.add_theme_color_override("font_outline_color", Color(.08, .08, .16, .85))
	look_hint.add_theme_constant_override("outline_size", 5)
	look_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	look_hint.offset_left = -520
	look_hint.offset_right = -205
	look_hint.offset_top = -66
	look_hint.offset_bottom = -36
	look_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	look_hint.visible = false
	skip_layer.add_child(look_hint)

func _show_skip(shown: bool) -> void:
	if skip_button.visible == shown:return
	skip_button.visible = shown
	if shown:
		skip_button.modulate.a = 0
		create_tween().tween_property(skip_button, "modulate:a", 1.0, .6)
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Walks the player through `points` at walking pace, facing the way it goes.
func _walk(points: Array, speed := 1.6) -> void:
	var player: CharacterBody3D = world.player
	var lengths: Array[float] = []
	var total := 0.0
	for i in points.size() - 1:
		lengths.append((points[i + 1] as Vector3).distance_to(points[i]))
		total += lengths[i]
	if total < .05:return
	var seconds := clampf(total / speed, .8, 3.5)
	var t := 0.0
	while t < seconds:
		t = minf(t + get_process_delta_time(), seconds)
		var along := total * t / seconds
		var i := 0
		while i < lengths.size() - 1 and along > lengths[i]:
			along -= lengths[i]
			i += 1
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		player.global_position = a.lerp(b, clampf(along / maxf(lengths[i], .001), 0, 1))
		var flat := b - a
		flat.y = 0
		if flat.length() > .05:player.model.rotation.y = lerp_angle(player.model.rotation.y, atan2(-flat.x, -flat.z), clampf(get_process_delta_time() * 10, 0, 1))
		player.model.set_locomotion(total / seconds * 1.6, true)
		if camera.current:camera.look_at(player.global_position + Vector3.UP * .9, Vector3.UP)
		await get_tree().process_frame
	player.model.set_locomotion(0, true)

## The gate and the ground end of the gangway: out through the rail's gate, then down
## to the ground's height. At the lighthouse island the plank spans the gap to the pier.
func _gangway(deck: Vector3, ground: Vector3) -> Array:
	var out := rig.global_basis * gate_dir
	out.y = 0
	out = out.normalized()
	var foot := deck + out * (gate_reach + (_keeper_gap() if at == "keeper_isle" else 1.0))
	foot.y = ground.y
	return [deck + out * gate_reach, foot]

## How far the plank must reach past the gate so the hull clears the pier's end.
func _keeper_gap() -> float:
	return maxf(.7, hull_reach - gate_reach + .25)

## Rig basis and deck point that put the gate square to the lighthouse pier, the hull
## just clear of its end: [basis, deck point].
func _keeper_park() -> Array:
	var keeper: Dictionary = world.meta.get("keeper_isle", {})
	if not keeper.has("pier_end"):return [home_transform.basis, _keeper_rest()]
	var pier_end := Vector3(keeper.pier_end[0], keeper.pier_end[1], keeper.pier_end[2])
	var pier_start := Vector3(keeper.pier_start[0], keeper.pier_start[1], keeper.pier_start[2])
	var toward := pier_start - pier_end
	toward.y = 0
	toward = toward.normalized()
	var home_gate := home_transform.basis * gate_dir
	home_gate.y = 0
	var turn := home_gate.normalized().signed_angle_to(toward, Vector3.UP)
	var basis := Basis(Vector3.UP, turn) * home_transform.basis
	var deck := pier_end - toward * (gate_reach + _keeper_gap())
	deck.y = _keeper_rest().y
	return [basis, deck]

func _place(basis: Basis, deck_world: Vector3) -> void:
	rig.global_transform = Transform3D(basis, Vector3.ZERO)
	rig.global_position = deck_world - basis * (home_transform.basis.inverse() * deck_offset)

## A plank with two rope rails from the gate down to the pier (lighthouse island only).
func _show_gangway(shown: bool) -> void:
	if is_instance_valid(gangway):gangway.queue_free()
	gangway = null
	if not shown or not rig:return
	var keeper: Dictionary = world.meta.get("keeper_isle", {})
	var pier_y: float = keeper.pier_end[1] if keeper.has("pier_end") else deck_point().y - .5
	var ends := _gangway(deck_point(), Vector3(0, pier_y, 0))
	var a: Vector3 = ends[0] + Vector3.DOWN * .03
	var b: Vector3 = ends[1] + (ends[1] - ends[0]).normalized() * .35 + Vector3.UP * .02
	gangway = Node3D.new()
	gangway.name = "Gangway"
	world.add_child(gangway)
	var along := b - a
	var board := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(.78, .06, along.length())
	board.mesh = box
	board.material_override = _mat(Color("b4875a"))
	gangway.add_child(board)
	board.global_transform = Transform3D(Basis.looking_at(along.normalized()), (a + b) / 2)
	var side := along.cross(Vector3.UP).normalized()
	for s in [-1, 1]:
		for t in [0.0, 1.0]:
			var post := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = .03
			c.bottom_radius = .035
			c.height = .8
			c.radial_segments = 6
			post.mesh = c
			post.material_override = _mat(Color("6b4a30"))
			gangway.add_child(post)
			post.global_position = a.lerp(b, t) + side * s * .38 + Vector3.UP * .4
		gangway.add_child(_bar(a + side * s * .38 + Vector3.UP * .78, b + side * s * .38 + Vector3.UP * .78, _mat(Color("d9c29a"))))

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
	var home_gate := (home_transform.basis * gate_dir).normalized()
	var centre := deck_box.get_center()
	hull_reach = 0.0
	for i in 8:
		var corner := hull_box.get_endpoint(i) - centre
		corner.y = 0
		hull_reach = maxf(hull_reach, corner.dot(home_gate))
	if content.state.flag("ship_lamp_lit"):light_lamp(false)
	if content.state.flag("airship_at_keeper"):
		at = "keeper_isle"
		var park := _keeper_park()
		_place(park[0], park[1])
		_show_gangway(true)

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
	gate_reach = r
	var wood := _mat(Color("7a5236"))
	var light_wood := _mat(Color("c79a6a"))
	var posts := 14
	var dock_dir: Vector3 = content.registry.position_of("dock") - centre
	var gate_angle := atan2(dock_dir.z, dock_dir.x)
	gate_dir = rig.global_basis.inverse() * Vector3(cos(gate_angle), 0, sin(gate_angle))
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
			var park: Vector3 = _keeper_park()[1]
			return PackedVector3Array([start, start + Vector3(0, 6, 1), Vector3(-14, 18, 26), Vector3(6, 23, 40), Vector3(22, 20, 34), park + Vector3(-6, 3.5, 0), park])
		"dock":
			if at == "keeper_isle" or start.distance_to(keeper) < 4.0:
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
	if stage == "c5_fly":
		destination = "summit"
		content.ending.send_off()
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
	var plank := _gangway(deck_point(), board_from)
	await _walk([board_from, plank[1], plank[0], deck_point()])
	if world.get("audio"):world.audio.play_sfx("door")
	create_tween().tween_property(gate, "rotation:y", 0.0, .8)
	content.ui.whisper("扶好栏杆。" if destination != "summit" else "我们往上飞吧。一直往上。")
	var curve := _curve(_route(destination))
	var length := curve.get_baked_length()
	var seconds := clampf(length / 2.4, 12.0, 62.0)
	var t := 0.0
	var yaw0 := atan2(-home_transform.basis.z.x, -home_transform.basis.z.z)
	var yaw := yaw0 + (rig.global_basis * home_transform.basis.inverse()).get_euler().y
	# where the ship must point when it settles: square to the pier, or as at home
	var settle_yaw := yaw0
	if destination == "keeper_isle":settle_yaw = yaw0 + (_keeper_park()[0] * home_transform.basis.inverse()).get_euler().y
	_show_gangway(false)
	look_hint.visible = true
	_look = Vector2.ZERO
	_look_smooth = Vector2.ZERO
	_cam_yaw = yaw + 2.4
	skip = false
	var shown := 0.0
	while t < seconds:
		var dt := get_process_delta_time() * (5.0 if hurry else 1.0)
		shown += get_process_delta_time()
		_show_skip(shown >= SKIP_AFTER)
		t = seconds if skip else t + dt
		var k := smoothstep(0.0, 1.0, clampf(t / seconds, 0, 1))
		var p := curve.sample_baked(k * length)
		var ahead := curve.sample_baked(minf(k * length + 2.0, length))
		var dir := ahead - p
		dir.y = 0
		if dir.length() > .05:yaw = lerp_angle(yaw, atan2(-dir.x, -dir.z), clampf(dt * 1.2, 0, 1))
		# the last stretch turns the ship to how it will be moored
		if k > .82 and destination != "summit":yaw = lerp_angle(yaw, settle_yaw, clampf((k - .82) / .18, 0, 1))
		var bob := sin(t * 1.3) * .08
		var deck_world := p + Vector3.UP * bob
		rig.global_transform = Transform3D(Basis(Vector3.UP, yaw - atan2(-home_transform.basis.z.x, -home_transform.basis.z.z)) * home_transform.basis, Vector3.ZERO)
		rig.global_position = deck_world - rig.global_basis * (home_transform.basis.inverse() * deck_offset)
		player.global_position = deck_world
		player.model.rotation.y = yaw
		# slow orbit; moving the mouse left or right turns it, up or down raises it
		_cam_yaw += dt * .05
		var orbit := _orbit(dt)
		camera.global_position = deck_world + orbit if skip else camera.global_position.lerp(deck_world + orbit, clampf(dt * 2.0, 0, 1))
		camera.look_at(deck_world + Vector3.UP * 1.2, Vector3.UP)
		await get_tree().process_frame
		if destination == "summit" and t >= seconds:break
	_show_skip(false)
	look_hint.visible = false
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
	# the last night: the slow way down while the closing words are read, seen wide
	var ending: bool = content.ending.playing
	if ending:
		seconds = 92.0
		content.ending.descent()
	var t := 0.0
	var player: CharacterBody3D = world.player
	at = "flying"
	skip = false
	var shown := 0.0
	while t < seconds:
		var dt := get_process_delta_time() * (5.0 if hurry or (ending and content.ending.hurry) else 1.0)
		shown += get_process_delta_time()
		_show_skip(shown >= SKIP_AFTER and not ending)
		t = seconds if skip else t + dt
		var p := curve.sample_baked(smoothstep(0.0, 1.0, clampf(t / seconds, 0, 1)) * length)
		rig.global_position = p - rig.global_basis * (home_transform.basis.inverse() * deck_offset)
		player.global_position = p
		_cam_yaw += dt * .05
		if ending:
			# far out and a little below: the ship small among the lanterns, the lit island beneath
			var wide := p + Vector3(sin(_cam_yaw * .6), 0, cos(_cam_yaw * .6)) * 26.0 + Vector3.UP * 2.0
			camera.global_position = camera.global_position.lerp(wide, clampf(dt * .8, 0, 1))
			camera.look_at(p.lerp(Vector3(0, 0, 2), .35) + Vector3.UP * 2.0, Vector3.UP)
			player.global_position = p
			await get_tree().process_frame
			continue
		var goal := p + _orbit(dt)
		camera.global_position = goal if skip else camera.global_position.lerp(goal, clampf(dt * 2.0, 0, 1))
		camera.look_at(p + Vector3.UP * 1.2, Vector3.UP)
		await get_tree().process_frame
	_show_skip(false)
	_land("dock", "summit")

## Camera offset from the deck: the slow orbit plus where the mouse is in the window.
func _orbit(dt: float) -> Vector3:
	_look_smooth = _look_smooth.lerp(_look, clampf(dt * 3.0, 0, 1))
	var a := _cam_yaw - _look_smooth.x * 2.4
	# mouse up: from below the gondola looking up at the sky; mouse down: high above,
	# looking down over the island
	var elevation := clampf(.3 + _look_smooth.y * 1.05, -.45, 1.25) + _pitch_drag
	elevation = clampf(elevation, -.55, 1.35)
	var reach := 10.5
	return Vector3(sin(a) * cos(elevation), sin(elevation), cos(a) * cos(elevation)) * reach

func _land(destination: String, _from: String) -> void:
	var player: CharacterBody3D = world.player
	look_hint.visible = false
	at = destination
	if destination == "dock":
		rig.global_transform = home_transform
	else:
		var park := _keeper_park()
		_place(park[0], park[1])
		_show_gangway(true)
	content.state.data.flags.erase("airship_at_keeper")
	if destination == "keeper_isle":content.state.set_flag("airship_at_keeper")
	create_tween().tween_property(gate, "rotation:y", 1.6, .8)
	var step_to: Vector3 = content.registry.position_of("keeper_dock" if destination == "keeper_isle" else "dock")
	var from := deck_point()
	await get_tree().create_timer(.5).timeout
	var plank := _gangway(from, step_to)
	await _walk([from, plank[0], plank[1], step_to])
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
	if _from == "summit":await content.ending.finale()

func _input(event: InputEvent) -> void:
	if not flying():return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_E, KEY_SPACE, KEY_ESCAPE] and skip_button.visible:skip = true
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_cam_yaw -= event.relative.x * .004
			_pitch_drag = clampf(_pitch_drag + event.relative.y * .003, -.8, .8)
		else:
			var size := get_viewport().get_visible_rect().size
			_look = Vector2(clampf(event.position.x / size.x * 2.0 - 1.0, -1, 1), clampf(event.position.y / size.y * 2.0 - 1.0, -1, 1))
