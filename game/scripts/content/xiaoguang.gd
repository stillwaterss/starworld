extends Node3D
## 小光, the little star that fell into the grass. Before it is found it glimmers by the
## tree-house steps; afterwards it rides in the hand lantern (or floats by the player's
## shoulder when the lantern is put away) and grows a little brighter each chapter.
## During the ending it is handed to the sky (leave_for()) and stays there.
var content
var star: MeshInstance3D
var halo: MeshInstance3D
var light: OmniLight3D
var material: StandardMaterial3D
var where := "grass"          # grass, lantern, shoulder, flying, sky
var clock := 0.0
var flight_tween: Tween

func _ready() -> void:
	name = "Xiaoguang"
	star = MeshInstance3D.new()
	star.mesh = preload("res://scripts/actor_visual.gd")._soft_star()
	star.scale = Vector3.ONE * .16
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
	light = OmniLight3D.new()
	light.light_color = Color("ffe2a0")
	light.omni_range = 2.2
	light.light_energy = .5
	add_child(light)
	_restore.call_deferred()

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

func brightness() -> float:
	var chapter: int = content.state.data.main.chapter
	if content.director.main_done():chapter = 5
	return .45 + chapter * .17 + (.25 if content.state.flag("reaction_lighthouse_lit") else 0.0)

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
	material.emission_energy_multiplier = 1.2 + glow * 1.6 * pulse
	light.light_energy = glow * .6 * pulse
	star.rotation.y += delta * .8
	var player: CharacterBody3D = content.world.player
	match where:
		"grass":
			visible = true
			# faint, like something that has been crying a little
			material.emission_energy_multiplier = .8 + .5 * pow(.5 + .5 * sin(clock * 1.3), 4.0)
			light.light_energy = .25
			star.position.y = .05 + sin(clock * 1.1) * .02
		"lantern":
			var scene = content.world.get("scene_actions")
			var lantern: Node3D = scene.lantern if scene and is_instance_valid(scene.lantern) else null
			if lantern and lantern.visible:
				visible = true
				global_position = lantern.global_position + Vector3(0, -.31, 0)
				star.scale = Vector3.ONE * .07
				halo.visible = false
				light.light_energy = 0.0
			else:
				# lantern put away: it rides by the player's shoulder instead
				visible = true
				halo.visible = true
				star.scale = Vector3.ONE * .11
				var shoulder: Vector3 = player.global_position + player.model.global_basis * Vector3(.42, 1.45 + sin(clock * 1.7) * .06, .1)
				global_position = global_position.lerp(shoulder, clampf(delta * 4.0, 0, 1)) if global_position.distance_to(shoulder) < 6.0 else shoulder
		"sky":
			visible = false
