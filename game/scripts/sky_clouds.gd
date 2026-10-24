extends Node3D
## Soft clouds around the archipelago: camera-facing puffs in loose banks at several
## distances and heights, high thin streaks, and two drifting mist layers of cloud sea.
## The lumpy far cloud meshes (Clouds_V11_*) are hidden; day_cycle drives the tint.
const BANKS := 26
const HIGH := 10

var world: Node3D
var materials: Array[ShaderMaterial] = []
var puffs: Array[Node3D] = []
var drift: Array[Vector3] = []

func _ready() -> void:
	name = "SkyClouds"
	var rng := RandomNumberGenerator.new()
	rng.seed = 131025
	var shader := preload("res://shaders/cloud_billboard.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	for b in BANKS:
		var a := rng.randf() * TAU
		var r := rng.randf_range(85.0, 260.0)
		var base := Vector3(cos(a) * r, rng.randf_range(-16.0, 10.0), sin(a) * r)
		var count := rng.randi_range(3, 6)
		for k in count:
			var m := ShaderMaterial.new()
			m.shader = shader
			m.set_shader_parameter("seed", rng.randf() * 40.0)
			m.set_shader_parameter("flatness", rng.randf_range(.45, .7))
			m.set_shader_parameter("opacity", rng.randf_range(.72, .95))
			m.render_priority = -1
			var puff := MeshInstance3D.new()
			puff.mesh = quad
			puff.material_override = m
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var size := rng.randf_range(22.0, 48.0) * (r / 160.0 + .4)
			puff.scale = Vector3(size * rng.randf_range(1.4, 2.2), size, 1)
			puff.position = base + Vector3(rng.randf_range(-1, 1) * size * 1.2, rng.randf_range(-.2, .5) * size * .4, rng.randf_range(-1, 1) * size * .6)
			puff.extra_cull_margin = 64
			add_child(puff)
			materials.append(m)
			puffs.append(puff)
			drift.append(Vector3(rng.randf_range(-.25, .25), 0, rng.randf_range(-.15, .15)))
	for h in HIGH:
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("seed", 100.0 + h * 7.3)
		m.set_shader_parameter("flatness", .22)
		m.set_shader_parameter("opacity", .42)
		m.set_shader_parameter("softness", 1.8)
		var streak := MeshInstance3D.new()
		streak.mesh = quad
		streak.material_override = m
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := rng.randf() * TAU
		var r := rng.randf_range(140.0, 320.0)
		streak.position = Vector3(cos(a) * r, rng.randf_range(55.0, 110.0), sin(a) * r)
		streak.scale = Vector3(rng.randf_range(120.0, 220.0), 40.0, 1)
		streak.extra_cull_margin = 64
		add_child(streak)
		materials.append(m)
		puffs.append(streak)
		drift.append(Vector3(rng.randf_range(-.4, .4), 0, 0))
	var sea_shader := preload("res://shaders/cloud_sea.gdshader")
	for layer in [[-17.0, 0.0, .78], [-11.0, 13.0, .45]]:
		var sea := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(900, 900)
		plane.subdivide_depth = 0
		sea.mesh = plane
		var m := ShaderMaterial.new()
		m.shader = sea_shader
		m.set_shader_parameter("layer_seed", layer[1])
		m.set_shader_parameter("strength", layer[2])
		sea.material_override = m
		sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sea.position.y = layer[0]
		add_child(sea)
		materials.append(m)
	# hand the tints to the day cycle and retire the lumpy distant banks
	var cycle = world.get("day_cycle")
	for m in materials:
		if cycle:
			m.set_shader_parameter("time_weights", cycle.weights)
			if not m in cycle.clouds:cycle.clouds.append(m)
	for mesh: MeshInstance3D in world.find_children("Clouds_V11_*", "MeshInstance3D", true, false):
		mesh.visible = false

func _process(delta: float) -> void:
	for i in puffs.size():
		puffs[i].position += drift[i] * delta
