extends Node3D
## Short staged moments for everyday actions (plant, water, wish lantern, wind chime,
## skipping a stone, fireflies, knocking, polishing): walk to a mark, turn, glide the
## camera to a mid shot, play procedural poses with a small prop, fire the effect on the
## beat, glide back. Game state changes happen in the caller right away; this only shows
## them. E / Esc / Space hurries the rest of a performance.
signal started(kind: String)
signal finished(kind: String)

const X := Vector3(1, 0, 0)    # skeleton space: +X is the character's left
const Y := Vector3(0, 1, 0)
const Z := Vector3(0, 0, 1)    # forward

var world: Node3D
var player: CharacterBody3D
var camera: Camera3D
var busy := false
var kind := ""
var hurry := false
var socket: BoneAttachment3D
var prop: Node3D
var _glide: Tween
var _return_camera: Camera3D
var _mouse := 0
var _hidden_layers: Array[CanvasLayer] = []

func _ready() -> void:
	name = "Performance"
	player = world.player
	camera = Camera3D.new()
	camera.name = "PerformanceCamera"
	camera.fov = 46
	camera.near = .05
	camera.far = 1500
	add_child(camera)
	var skeletons: Array[Node] = player.model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		socket = BoneAttachment3D.new()
		socket.name = "PropSocket"
		socket.bone_name = "hand.R"
		skeletons[0].add_child(socket)

# ------------------------------------------------------------------ poses
static func rot(axis: Vector3, degrees: float) -> Quaternion:
	return Quaternion(axis, deg_to_rad(degrees))

## Right arm rest points to the character's right (-X); left arm to +X.
static func arm_r(forward: float, lift := 0.0) -> Quaternion:
	return rot(X, -lift) * rot(Y, forward)

static func arm_l(forward: float, lift := 0.0) -> Quaternion:
	return rot(X, -lift) * rot(Y, -forward)

static func relaxed() -> Dictionary:
	return {"arm.R": rot(Z, 72), "arm.L": rot(Z, -72)}

static func pose(name: String, t := 0.0) -> Dictionary:
	match name:
		"kneel":
			return {"spine": rot(X, 34), "head": rot(X, 14), "arm.R": arm_r(90, -55 + sin(t * 9.0) * 9.0), "arm.L": arm_l(90, -50), "hand.R": rot(X, 18), "hand.L": rot(X, 18)}
		"admire":
			return {"spine": rot(X, 8), "head": rot(X, 16), "arm.R": arm_r(70, -35), "arm.L": arm_l(70, -35)}
		"pour":
			return {"spine": rot(X, 12), "head": rot(X, 12), "arm.R": arm_r(82, -22), "hand.R": rot(Z, 38 + sin(t * 3.0) * 4.0), "arm.L": rot(Z, -70)}
		"hold_up":
			return {"spine": rot(X, -8), "head": rot(X, -24), "arm.R": arm_r(90, 58), "arm.L": arm_l(90, 58)}
		"release":
			return {"spine": rot(X, -12), "head": rot(X, -34), "arm.R": arm_r(80, 82), "arm.L": arm_l(80, 82)}
		"reach_up":
			return {"head": rot(X, -18), "arm.R": arm_r(88, 50 + sin(t * 14.0) * 6.0), "arm.L": rot(Z, -70)}
		"listen":
			return {"head": rot(Z, 12) * rot(X, -6), "arm.R": rot(Z, 70), "arm.L": arm_l(60, -40)}
		"windup":
			return {"spine": rot(Y, 22) * rot(X, 10), "arm.R": arm_r(-30, 10), "arm.L": arm_l(60, -20)}
		"throw":
			return {"spine": rot(Y, -18) * rot(X, 14), "arm.R": arm_r(112, 6), "arm.L": arm_l(30, -40), "head": rot(X, 10)}
		"cup":
			return {"spine": rot(X, 18), "head": rot(X, 22), "arm.R": arm_r(74, -18), "arm.L": arm_l(74, -18), "hand.R": rot(Y, -20), "hand.L": rot(Y, 20)}
		"look_up":
			return {"head": rot(X, -30), "spine": rot(X, -6), "arm.R": rot(Z, 64), "arm.L": rot(Z, -64)}
		"knock":
			return {"arm.R": arm_r(86, 8), "hand.R": rot(X, -22 + absf(sin(t * 7.0)) * 34.0), "arm.L": rot(Z, -72)}
		"polish":
			return {"spine": rot(X, 6), "arm.R": arm_r(84 + cos(t * 6.0) * 10.0, 10 + sin(t * 6.0) * 10.0), "arm.L": rot(Z, -70)}
		"hug":
			return {"head": rot(X, 14), "arm.R": arm_r(70, -10), "arm.L": arm_l(70, -10), "hand.R": rot(Y, -30), "hand.L": rot(Y, 30)}
	return relaxed()

func set_pose(name: String, speed := 7.0) -> void:
	player.model.set_pose(pose(name, 0.0), speed)

## Keeps a moving pose (digging, pouring, polishing) alive for `seconds`.
func animate_pose(name: String, seconds: float, speed := 9.0) -> void:
	var t := 0.0
	while t < seconds:
		player.model.set_pose(pose(name, t), speed)
		var step := get_process_delta_time()
		await get_tree().process_frame
		t += step * (4.0 if hurry else 1.0)

# ------------------------------------------------------------------ flow
func can_start() -> bool:
	if busy or not is_instance_valid(player) or player.model.using_fallback:return false
	var cozy = world.get("activities")
	if cozy and cozy.photo:return false
	if world.interactions.mode != "idle":return false
	var scene = world.get("scene_actions")
	return scene == null or scene.seat_state == "free"

func begin(id: String, focus: Vector3, view := {}) -> bool:
	if not can_start():return false
	busy = true
	kind = id
	hurry = false
	player.controls_locked = true
	player.velocity = Vector3.ZERO
	player.model.set_performing(true)
	_return_camera = get_viewport().get_camera_3d()
	camera.global_transform = _return_camera.global_transform if _return_camera else camera.global_transform
	camera.fov = _return_camera.fov if _return_camera else 50.0
	camera.current = true
	# a little cutscene: every HUD layer steps aside until the moment is over
	_hidden_layers.clear()
	for node in world.get_children():
		if node is CanvasLayer and node.visible:
			_hidden_layers.append(node)
			node.visible = false
	started.emit(id)
	frame(focus, view)
	return true

## Glides to a three-quarter mid shot of the player and `focus`, avoiding walls.
func frame(focus: Vector3, view := {}) -> void:
	var p := player.global_position
	var facing: Vector3 = -player.model.global_basis.z
	facing.y = 0
	facing = facing.normalized() if facing.length() > .01 else Vector3.FORWARD
	var look: Vector3 = view.get("look", p.lerp(focus, float(view.get("mix", .45))) + Vector3.UP * float(view.get("look_height", .75)))
	var distance := float(view.get("distance", 3.1))
	var height := float(view.get("height", 1.45))
	var eye: Vector3 = view.get("eye", Vector3.INF)
	if eye == Vector3.INF:
		var space := world.get_world_3d().direct_space_state
		# NPCs count as obstacles: a friend standing in front of the camera is a bad shot
		var exclude: Array[RID] = [player.get_rid()]
		eye = look + facing.rotated(Vector3.UP, deg_to_rad(40)) * distance + Vector3.UP * height
		for angle in [40, -40, 65, -65, 20, -20, 95, -95]:
			var candidate: Vector3 = look + facing.rotated(Vector3.UP, deg_to_rad(angle)) * distance + Vector3.UP * height
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(look, candidate, 3, exclude)).is_empty():
				eye = candidate
				break
	glide_to(Transform3D(Basis.looking_at(look - eye), eye), float(view.get("fov", 46)), float(view.get("time", .9)))

func glide_to(goal: Transform3D, fov: float, seconds := .9) -> void:
	if _glide:_glide.kill()
	_glide = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glide.tween_property(camera, "global_transform", goal, seconds)
	_glide.tween_property(camera, "fov", fov, seconds)

func finish(back_seconds := .8) -> void:
	set_pose("relaxed")
	if is_instance_valid(_return_camera):
		glide_to(_return_camera.global_transform, _return_camera.fov, back_seconds)
		await wait(back_seconds)
		if is_instance_valid(_return_camera):_return_camera.current = true
	drop_prop()
	for layer in _hidden_layers:
		if is_instance_valid(layer):layer.visible = true
	_hidden_layers.clear()
	player.model.set_performing(false)
	player.controls_locked = false
	busy = false
	var done := kind
	kind = ""
	finished.emit(done)

func wait(seconds: float) -> void:
	var left := seconds
	while left > 0:
		await get_tree().process_frame
		left -= get_process_delta_time() * (4.0 if hurry else 1.0)

## Walks to `mark` (scene_actions' scripted movement) for at most two seconds, then turns to `face`.
func approach(mark: Vector3, face: Vector3) -> void:
	var limit := 2.2
	if Vector2(mark.x - player.global_position.x, mark.z - player.global_position.z).length() > .3:
		player.scripted_active = true
		player.scripted_speed = 1.7
		while limit > 0:
			var d := mark - player.global_position
			d.y = 0
			if d.length() < .18:break
			player.scripted_direction = d.normalized()
			await get_tree().physics_frame
			limit -= get_physics_process_delta_time()
		player.scripted_active = false
		player.scripted_direction = Vector3.ZERO
		player.velocity = Vector3.ZERO
	await turn_to(face)

func turn_to(face: Vector3, seconds := .35) -> void:
	var d := face - player.global_position
	if Vector2(d.x, d.z).length() < .05:return
	var goal := atan2(-d.x, -d.z)
	var start: float = player.model.rotation.y
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		player.model.rotation.y = lerp_angle(start, goal, smoothstep(0.0, 1.0, t / seconds))

func _input(event: InputEvent) -> void:
	if not busy or not event is InputEventKey or not event.pressed or event.echo:return
	if event.physical_keycode in [KEY_E, KEY_ESCAPE, KEY_SPACE]:
		hurry = true
		get_viewport().set_input_as_handled()
	elif event.physical_keycode != KEY_M:
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ props
func hold_prop(node: Node3D, offset := Vector3(0, -.06, .04)) -> void:
	drop_prop()
	prop = node
	if is_instance_valid(socket):
		socket.add_child(node)
		node.position = offset
		# the skeleton is scaled 1.55; keep props at their modelled size
		node.scale = Vector3.ONE / maxf(socket.global_basis.get_scale().x, .01)
	else:
		player.add_child(node)
		node.position = Vector3(.3, .8, -.3)

func drop_prop() -> void:
	if is_instance_valid(prop):prop.queue_free()
	prop = null

static func material(color: Color, glow := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.roughness = .7
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow > 0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m

static func piece(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material, rotation_deg := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.rotation_degrees = rotation_deg
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func cylinder(radius: float, height: float, top := -1.0, segments := 14) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius if top < 0 else top
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m

static func ball(radius: float, segments := 12) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2
	m.radial_segments = segments
	m.rings = segments / 2
	return m

static func watering_can() -> Node3D:
	var can := Node3D.new()
	can.name = "WateringCan"
	var tin := material(Color("7fa7b5"))
	var dark := material(Color("4f6f7c"))
	piece(can, cylinder(.075, .14), Vector3(0, -.04, .06), tin)
	piece(can, cylinder(.012, .16, .007), Vector3(0, -.01, .17), dark, Vector3(62, 0, 0))
	var handle := TorusMesh.new()
	handle.inner_radius = .045
	handle.outer_radius = .058
	piece(can, handle, Vector3(0, .05, .02), dark, Vector3(0, 90, 0))
	return can

static func paper_lantern() -> Node3D:
	var lantern := Node3D.new()
	lantern.name = "WishLanternProp"
	piece(lantern, cylinder(.13, .26, .16), Vector3(0, .22, 0), material(Color("ffd08a"), 1.4, .92))
	piece(lantern, cylinder(.16, .02), Vector3(0, .36, 0), material(Color("a47752")))
	piece(lantern, cylinder(.13, .02), Vector3(0, .09, 0), material(Color("a47752")))
	var light := OmniLight3D.new()
	light.light_color = Color("ffcf89")
	light.light_energy = .8
	light.omni_range = 2.6
	light.position.y = .22
	lantern.add_child(light)
	return lantern

static func pebble() -> Node3D:
	var stone := Node3D.new()
	var mesh := piece(stone, ball(.035, 8), Vector3.ZERO, material(Color("b8b3a6")))
	mesh.scale = Vector3(1.2, .55, 1.0)
	return stone

static func seed_pouch() -> Node3D:
	var pouch := Node3D.new()
	piece(pouch, ball(.05, 10), Vector3(0, -.02, .03), material(Color("c9a06a")))
	piece(pouch, cylinder(.02, .03), Vector3(0, .03, .03), material(Color("8a6a44")))
	return pouch

static func cloth() -> Node3D:
	var rag := Node3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(.11, .02, .09)
	piece(rag, box, Vector3(0, -.02, .05), material(Color("e9d7b8")), Vector3(10, 20, 0))
	return rag
