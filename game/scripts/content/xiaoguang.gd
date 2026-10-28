extends Node3D
## 小光, the little star that fell into the grass. Before it is found it glimmers by the
## tree-house steps; afterwards it floats by the player's head ("lantern": with the
## player), always facing the camera with a small face: two eyes that blink, a blush.
## Its mood follows the story: shy at first (half hidden behind the shoulder, small,
## trembling a little), then curious and warm (in front, livelier), and at the end close
## by the cheek. react() makes it hop and smile or shrink; light_up() flies it to a
## thing it lights and back. During the ending it is handed to the sky (leave_for()).
var content
var star: MeshInstance3D
var halo: MeshInstance3D
var light: OmniLight3D
var material: StandardMaterial3D
var where := "grass"          # grass, lantern (with the player), perform, flying, sky
var face: Node3D
var eyes: Array[MeshInstance3D] = []
var _blink := 2.5
var _smile := 0.0                # > 0: eyes squint into a smile
var _scared := 0.0               # > 0: shrinks and hides behind the shoulder
var _hop := 0.0
## Growth you can see, level 0..10: size, halo, warmth; a second ring of points from
## level 4, two small orbiting stars from level 8; a pulse ring and a spin on each step.
var rays: MeshInstance3D
var orbiters: Array[MeshInstance3D] = []
var pulse_ring: MeshInstance3D
var _pulse := 0.0
var _spin := 0.0
var trail: CPUParticles3D
var clock := 0.0
var flight_tween: Tween
## The ten things 小光 lights (content/island_lights.gd), one notch each on the meter under
## the quest box, and finding its home in the sky. A key is a story flag or "star:<id>"
## for a constellation in the journal.
const DEEDS := [
	["lit_garden", "花园的夜光花"], ["lit_treehouse", "树屋的小圆窗"], ["lit_lamps", "广场的路灯"],
	["lit_oven", "面包房的炉火"], ["lit_child", "孩子的小夜灯"], ["lit_fountain", "喷泉的灯"],
	["lit_ship", "飞艇的心"], ["lit_lighthouse", "灯塔"], ["lit_grandma", "奶奶窗台的灯"], ["star:home", "找到了家"],
]

func _ready() -> void:
	name = "Xiaoguang"
	star = MeshInstance3D.new()
	star.mesh = preload("res://scripts/actor_visual.gd")._soft_star()
	star.scale = Vector3.ONE * .26
	material = StandardMaterial3D.new()
	material.albedo_color = Color("fff1c4")
	material.emission_enabled = true
	material.emission = Color("ffe6a0")
	material.emission_energy_multiplier = 1.4
	star.material_override = material
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(star)
	halo = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radial_segments = 12
	ball.rings = 6
	ball.radius = .16
	ball.height = .32
	halo.mesh = ball
	var soft := StandardMaterial3D.new()
	soft.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	soft.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	soft.albedo_color = Color(1, .9, .6, .14)
	soft.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo.material_override = soft
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	_build_face()
	_build_growth()
	light = OmniLight3D.new()
	light.light_color = Color("ffe2a0")
	light.omni_range = 3.2
	light.light_energy = .8
	add_child(light)
	_restore.call_deferred()

## Two dark eyes with a white glint and two pink cheeks on the star's front (+Z).
func _build_face() -> void:
	face = Node3D.new()
	star.add_child(face)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("3a2839")
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("fffaf0")
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pink := StandardMaterial3D.new()
	pink.albedo_color = Color(1, .62, .62, .55)
	pink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for x in [-.1, .1]:
		var eye := _dot(dark, Vector3(.042, .062, .02))
		eye.position = Vector3(x, .03, .155)
		face.add_child(eye)
		eyes.append(eye)
		var glint := _dot(white, Vector3(.38, .3, .5))
		glint.position = Vector3(.25, .3, .6)
		eye.add_child(glint)
		var cheek := _dot(pink, Vector3(.05, .028, .01))
		cheek.position = Vector3(x * 1.75, -.06, .14)
		face.add_child(cheek)

func _dot(mat: Material, size: Vector3) -> MeshInstance3D:
	var dot := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radial_segments = 10
	ball.rings = 5
	ball.radius = 1.0
	ball.height = 2.0
	dot.mesh = ball
	dot.scale = size
	dot.material_override = mat
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return dot

func _build_growth() -> void:
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1, .86, .5, .55)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rays = MeshInstance3D.new()
	rays.mesh = preload("res://scripts/actor_visual.gd")._soft_star()
	rays.material_override = glow
	rays.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rays.position.z = -.06
	rays.rotation.z = PI / 5
	rays.scale = Vector3.ONE * 1.5
	rays.visible = false
	star.add_child(rays)
	for i in 2:
		var o := MeshInstance3D.new()
		o.mesh = rays.mesh
		o.material_override = material
		o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		o.scale = Vector3.ONE * .045
		o.visible = false
		add_child(o)
		orbiters.append(o)
	pulse_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = .9
	ring.outer_radius = 1.0
	ring.rings = 24
	ring.ring_segments = 6
	pulse_ring.mesh = ring
	var ring_mat := glow.duplicate()
	ring_mat.albedo_color = Color(1, .9, .6, 0)
	pulse_ring.material_override = ring_mat
	pulse_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pulse_ring.visible = false
	add_child(pulse_ring)
	trail = CPUParticles3D.new()
	trail.amount = 60
	trail.lifetime = .9
	trail.local_coords = false
	trail.emitting = false
	trail.gravity = Vector3(0, -.2, 0)
	trail.initial_velocity_min = .05
	trail.initial_velocity_max = .3
	trail.spread = 180
	trail.scale_amount_min = .5
	trail.scale_amount_max = 1.0
	var dot := SphereMesh.new()
	dot.radius = .03
	dot.height = .06
	dot.radial_segments = 6
	dot.rings = 3
	trail.mesh = dot
	var trail_mat := glow.duplicate()
	trail_mat.albedo_color = Color(1, .9, .6, .9)
	trail.material_override = trail_mat
	add_child(trail)

## 0..10: how far 小光 has grown (the meter's stars).
func growth() -> int:
	return 10 if content.director.main_done() else level()

## A small reaction: "happy" (hop and a smile), "scared" (shrinks behind the shoulder),
## "grow" (one step brighter: a ring of light spreads, a quick spin, a little hop).
func react(kind: String) -> void:
	if kind == "happy":
		_smile = 1.8
		_hop = 1.0
	elif kind == "scared":
		_scared = 2.5
	elif kind == "grow":
		_pulse = 1.0
		_spin = 1.0
		_smile = 2.5
		_hop = 1.0

## shy, warm or close: how near and how lively 小光 is, from the story so far.
func mood() -> String:
	var director = content.director
	if director.main_done():return "close"
	var chapter: int = int(content.state.data.main.chapter)
	if chapter <= 0:return "shy"
	return "close" if chapter >= director.main.size() - 1 else "warm"

## Flies from the player to `point`, brightens there for `hold` seconds (the caller
## lights the thing meanwhile) and comes back. Awaitable.
func light_up(point: Vector3, hold := 1.6) -> void:
	where = "perform"
	if flight_tween:flight_tween.kill()
	var start := global_position
	trail.emitting = true
	flight_tween = create_tween()
	flight_tween.tween_method(func(t: float):
		global_position = start.lerp(point, t) + Vector3.UP * sin(t * PI) * 1.2, 0.0, 1.0, .9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	flight_tween.tween_callback(func():trail.emitting = false)
	flight_tween.tween_method(func(t: float):
		halo.scale = Vector3.ONE * lerpf(1.3, 7.0, sin(t * PI))
		light.light_energy = lerpf(.6, 6.0, sin(t * PI))
		light.omni_range = lerpf(3.2, 9.0, sin(t * PI)), 0.0, 1.0, hold)
	flight_tween.tween_callback(func():
		light.omni_range = 3.2
		where = "lantern")
	_smile = hold + 1.5
	await flight_tween.finished

func _restore() -> void:
	var state = content.state
	if state.flag("xiaoguang_home"):
		where = "sky"
		visible = false
	elif state.flag("xiaoguang"):
		where = "lantern"
	else:
		where = "grass"
		global_position = content.registry.position_of("fallen_star") + Vector3.UP * .12

## Picked up from the grass and put into the lantern (turns the lantern on).
func found() -> void:
	content.state.set_flag("xiaoguang")
	where = "lantern"
	var scene = content.world.get("scene_actions")
	if scene and is_instance_valid(scene.lantern) and not scene.lantern.visible:scene.toggle_lantern()

func deed_done(key: String) -> bool:
	if key.begins_with("chapter:"):return content.director._chapter_done(key.substr(8))
	if key.begins_with("star:"):return content.director._star_known(key.substr(5))
	return content.state.flag(key)

## How many of the warm deeds are done (0 .. DEEDS.size()).
func level() -> int:
	var n := 0
	for deed in DEEDS:n += 1 if deed_done(deed[0]) else 0
	return n

## Dim at first (a star that has fallen and lost most of its light), full at the end:
## the step from 1 to 10 should be plain to see.
func brightness() -> float:
	if content.director.main_done():return 1.6
	return lerpf(.12, 1.45, pow(level() / float(DEEDS.size()), 1.15))

## The ending: flies from the lantern to a point in the sky and stays there.
func leave_for(sky_point: Vector3, seconds := 9.0) -> void:
	where = "flying"
	if flight_tween:flight_tween.kill()
	var start := global_position
	var mid := start.lerp(sky_point, .35) + Vector3.UP * 6.0
	flight_tween = create_tween()
	flight_tween.tween_method(func(t: float):
		var a := start.lerp(mid, t)
		var b := mid.lerp(sky_point, t)
		global_position = a.lerp(b, t)
		star.scale = Vector3.ONE * lerpf(.16, 2.6, t * t), 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	flight_tween.tween_callback(func():
		where = "sky"
		content.state.set_flag("xiaoguang_home"))
	await flight_tween.finished

func _process(delta: float) -> void:
	clock += delta
	var glow := brightness()
	var pulse := .85 + .15 * sin(clock * 2.3)
	material.emission_energy_multiplier = .25 + glow * 2.6 * pulse
	_smile = maxf(0, _smile - delta)
	_scared = maxf(0, _scared - delta)
	_hop = maxf(0, _hop - delta * 1.6)
	_update_face(delta)
	_update_growth(delta)
	var player: CharacterBody3D = content.world.player
	match where:
		"grass":
			visible = true
			# faint, like something that has been crying a little
			material.emission_energy_multiplier = 1.2 + .8 * pow(.5 + .5 * sin(clock * 1.3), 4.0)
			light.light_energy = .6
			star.scale = Vector3.ONE * .3
			halo.visible = true
			halo.scale = Vector3.ONE * 1.6
			star.position.y = .12 + sin(clock * 1.1) * .03
		"lantern":
			visible = true
			halo.visible = true
			var m := mood()
			var size: float = {"shy": .22, "warm": .27, "close": .27}[m] * (1.0 - .3 * minf(_scared, 1.0)) * (1.0 + .06 * growth())
			star.scale = star.scale.lerp(Vector3.ONE * size, clampf(delta * 3.0, 0, 1))
			star.position = Vector3.UP * absf(sin(_hop * PI * 2.0)) * .25 * _hop
			halo.scale = Vector3.ONE * (1.1 + .2 * growth() + .4 * glow)
			light.light_energy = glow * .75 * pulse
			# shy: half behind the shoulder and trembling; warm: out in front, lively;
			# close: right by the cheek
			var lively: float = {"shy": .03, "warm": .09, "close": .05}[m]
			var spot: Vector3 = {"shy": Vector3(.5, 1.5, .32), "warm": Vector3(.55, 1.62, -.22), "close": Vector3(.38, 1.42, -.05)}[m]
			if _scared > 0:spot = Vector3(.42, 1.35, .45)
			spot += Vector3(sin(clock * 1.3) * lively, sin(clock * 1.7) * .07, cos(clock * 1.1) * lively)
			if m == "shy":spot += Vector3(sin(clock * 23.0), 0, 0) * .006
			var shoulder: Vector3 = player.global_position + player.model.global_basis * spot
			global_position = global_position.lerp(shoulder, clampf(delta * 4.0, 0, 1)) if global_position.distance_to(shoulder) < 6.0 else shoulder
		"perform":
			visible = true
			halo.visible = true
			star.scale = star.scale.lerp(Vector3.ONE * .3, clampf(delta * 3.0, 0, 1))
		"sky":
			visible = false

func _update_growth(delta: float) -> void:
	var g := float(growth()) / 10.0
	# warmer and richer with every step: pale cream at first, gold at the end
	material.albedo_color = Color("c9c2b2").lerp(Color("ffd88a"), g)
	material.emission = Color("d9d2c0").lerp(Color("ffc860"), g)
	(halo.material_override as StandardMaterial3D).albedo_color.a = lerpf(.035, .2, g)
	rays.visible = g >= .4 and where != "grass"
	rays.scale = Vector3.ONE * (1.25 + .5 * g + .08 * sin(clock * 2.0))
	rays.rotation.z += delta * .25
	for i in orbiters.size():
		var o := orbiters[i]
		o.visible = g >= .8 and where in ["lantern", "perform"]
		var a := clock * 1.6 + PI * i
		o.position = star.position + Vector3(cos(a) * .32, sin(a * .7) * .08, sin(a) * .32)
	_spin = maxf(0, _spin - delta * 1.2)
	if _spin > 0:star.rotate_object_local(Vector3.FORWARD, delta * 9.0 * _spin)
	_pulse = maxf(0, _pulse - delta * .8)
	pulse_ring.visible = _pulse > 0
	if _pulse > 0:
		var k := 1.0 - _pulse
		pulse_ring.position = star.position
		pulse_ring.scale = Vector3.ONE * lerpf(.15, 1.4, k)
		var cam := get_viewport().get_camera_3d()
		if cam:pulse_ring.look_at(cam.global_position, Vector3.UP)
		pulse_ring.rotate_object_local(Vector3.RIGHT, PI / 2)
		pulse_ring.material_override.albedo_color.a = .8 * _pulse

## Faces the camera (gently wobbling), blinks every few seconds, squints when happy.
func _update_face(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		var to_camera := camera.global_position - star.global_position
		to_camera.y *= .4
		if to_camera.length() > .05:
			var goal := Basis.looking_at(-to_camera.normalized()).rotated(Vector3.UP, sin(clock * .9) * .25) * Basis(Vector3.FORWARD, sin(clock * 1.4) * .12)
			star.basis = star.basis.orthonormalized().slerp(goal, clampf(delta * 6.0, 0, 1)).scaled(star.scale)
	_blink -= delta
	if _blink <= 0:_blink = randf_range(2.2, 4.5)
	var open := .12 if _blink < .12 else 1.0
	if _smile > 0:open = .32
	if _scared > 0:open = 1.25
	for eye in eyes:eye.scale.y = lerpf(eye.scale.y, .062 * open, clampf(delta * 18.0, 0, 1))
