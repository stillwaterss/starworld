extends Node3D
## Fireflies that come out of the grass around the player, wander on smooth noise and
## blink one by one; during the gathering they circle the player's cupped hands, then
## most drift up and away while a few keep following for a while.
const COUNT := 64
const FOLLOWERS := 18

var world: Node3D
var player: CharacterBody3D
var flies: MultiMeshInstance3D
var glow: OmniLight3D
var state := "off"          # off, emerge, gather, scatter, follow
var clock := 0.0
var state_time := 0.0
var hands := Vector3.ZERO
var pos: Array[Vector3] = []
var home: Array[Vector3] = []
var seed_phase: Array[float] = []
var born: Array[float] = []
var route := PackedVector3Array()
var lead_done: Callable

func _ready() -> void:
	name = "Fireflies"
	flies = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var mesh := SphereMesh.new()
	mesh.radius = .025
	mesh.height = .05
	mesh.radial_segments = 6
	mesh.rings = 3
	mm.mesh = mesh
	mm.instance_count = COUNT
	flies.multimesh = mm
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color("ffe8a0")
	material.emission_energy_multiplier = 2.2
	flies.material_override = material
	flies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flies.custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 120, 400))
	flies.visible = false
	add_child(flies)
	glow = OmniLight3D.new()
	glow.light_color = Color("ffe2a0")
	glow.omni_range = 4.0
	glow.light_energy = 0
	add_child(glow)
	for i in COUNT:
		pos.append(Vector3.ZERO)
		home.append(Vector3.ZERO)
		seed_phase.append(randf() * TAU)
		born.append(0.0)

func active() -> bool:return state != "off"

## Starts the gathering around `cupped` (world position of the player's hands).
func gather(cupped: Vector3) -> void:
	hands = cupped
	var center := player.global_position
	for i in COUNT:
		var a := randf() * TAU
		var r := 2.0 + randf() * 5.0
		home[i] = center + Vector3(cos(a) * r, 0, sin(a) * r)
		pos[i] = home[i] + Vector3.UP * .05
		born[i] = randf() * 3.2
	state = "emerge"
	state_time = 0.0
	flies.visible = true

## Leads the player along `path`: the swarm waits a few metres ahead and moves on as they follow.
func lead(path: PackedVector3Array, on_arrive: Callable) -> void:
	route = path
	lead_done = on_arrive
	state = "lead"
	state_time = 0.0
	flies.visible = true

func _lead_point() -> Vector3:
	var p := player.global_position
	var best := 0
	var best_d := INF
	for i in route.size():
		var d := route[i].distance_to(p)
		if d < best_d:
			best_d = d
			best = i
	var ahead := mini(best + 9, route.size() - 1)
	return route[ahead] + Vector3.UP * 1.1

func scatter() -> void:
	if state == "lead":return
	state = "scatter"
	state_time = 0.0

func _wander(i: int, t: float) -> Vector3:
	var p := seed_phase[i]
	return Vector3(sin(t * .7 + p) + sin(t * 1.3 + p * 2.0) * .5, sin(t * .9 + p * 1.5) * .6, cos(t * .6 + p) + cos(t * 1.1 + p * .7) * .5)

func _process(delta: float) -> void:
	if state == "off":return
	clock += delta
	state_time += delta
	var mm := flies.multimesh
	var sum := Vector3.ZERO
	var lit := 0
	for i in COUNT:
		var target: Vector3
		var alpha := 1.0
		match state:
			"emerge":
				var age := state_time - born[i]
				if age < 0:
					alpha = 0.0
					target = home[i]
				else:
					target = home[i] + Vector3.UP * (.4 + fmod(seed_phase[i], 1.1)) + _wander(i, clock) * .35
					alpha = clampf(age / .8, 0, 1)
				if state_time > 4.2:
					state = "gather"
					state_time = 0.0
			"gather":
				var a := seed_phase[i] + clock * (.7 + fmod(seed_phase[i], .5))
				var r := .25 + fmod(seed_phase[i] * 3.1, .9)
				target = hands + Vector3(cos(a) * r, sin(clock * 1.3 + seed_phase[i]) * .25 + .1, sin(a) * r)
			"lead":
				var a := seed_phase[i] + clock * .6
				target = _lead_point() + Vector3(cos(a) * .7, sin(clock * 1.2 + seed_phase[i]) * .3, sin(a) * .7) + _wander(i, clock) * .25
			"scatter", "follow":
				if i < FOLLOWERS:
					var orbit := seed_phase[i] + clock * .35
					target = player.global_position + Vector3(cos(orbit) * 1.4, 1.0 + sin(clock + seed_phase[i]) * .4, sin(orbit) * 1.4) + _wander(i, clock) * .4
					if state == "follow":alpha = clampf((40.0 - state_time) / 4.0, 0, 1)
				else:
					target = pos[i] + (Vector3.UP * 1.4 + _wander(i, clock) * .8) * delta * 3.0
					alpha = clampf(1.0 - state_time / 6.0, 0, 1)
		var speed := 1.6 if state == "gather" else 2.2
		pos[i] = pos[i].lerp(target, clampf(delta * speed, 0, 1))
		var blink := .35 + .65 * pow(.5 + .5 * sin(clock * (1.6 + fmod(seed_phase[i], 1.3)) + seed_phase[i] * 3.0), 3.0)
		var a2 := alpha * blink
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (.6 + blink * .6)), pos[i]))
		mm.set_instance_color(i, Color(1.0, .92, .62, a2))
		if a2 > .2:
			sum += pos[i]
			lit += 1
	if lit > 0:glow.global_position = sum / lit
	glow.light_energy = clampf(float(lit) / 30.0, 0, 1) * (1.2 if state == "gather" else .6)
	if state == "lead" and route.size() > 0 and player.global_position.distance_to(route[route.size() - 1]) < 2.4:
		state = "gather"
		state_time = 0.0
		hands = route[route.size() - 1] + Vector3.UP * .6
		if lead_done.is_valid():lead_done.call()
		get_tree().create_timer(6.0).timeout.connect(scatter)
	if state == "scatter" and state_time > 6.0:
		state = "follow"
		state_time = 0.0
	elif state == "follow" and state_time > 40.0:
		state = "off"
		flies.visible = false
		glow.light_energy = 0
