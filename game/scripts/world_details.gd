extends Node3D
## Batched optical stars and separated fountain droplets; no collision or lights.
var drops: MultiMesh
var phase := 0.0

func _ready() -> void:
	var sky := MultiMeshInstance3D.new()
	sky.name="SkyStars"
	var stars := MultiMesh.new()
	stars.transform_format = MultiMesh.TRANSFORM_3D
	stars.use_colors = true
	stars.instance_count = 2600
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	stars.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/sky_sparkle.gdshader")
	sky.material_override = mat
	sky.multimesh = stars
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sky)
	var rng := RandomNumberGenerator.new()
	rng.seed = 102307
	for i in stars.instance_count:
		var y := rng.randf_range(-.12, 1.0)
		var a := rng.randf_range(0, TAU)
		var d := Vector3(cos(a)*sqrt(1-y*y), y, sin(a)*sqrt(1-y*y))
		var size := rng.randf_range(.22,.70) if i % 19 else rng.randf_range(1.1,1.8)
		stars.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*size), d*240.0))
		stars.set_instance_color(i, Color(1.0,.76,.40) if i%7==0 else Color(.66,.79,1.0))
	var jets := MultiMeshInstance3D.new()
	drops = MultiMesh.new()
	drops.transform_format = MultiMesh.TRANSFORM_3D
	drops.use_custom_data = true
	drops.instance_count = 672
	var droplet := SphereMesh.new()
	droplet.radius = .025
	droplet.height = .07
	droplet.radial_segments = 6
	droplet.rings = 2
	drops.mesh = droplet
	var water := ShaderMaterial.new()
	water.shader = preload("res://shaders/fountain_drops.gdshader")
	jets.material_override = water
	jets.multimesh = drops
	jets.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drops.custom_aabb = AABB(Vector3(3.2,-.3,-2.2),Vector3(6.6,4.5,6.6))
	add_child(jets)
	for i in 672:
		var jet := i / 56
		var jitter := fposmod(sin(float(i)*127.1)*43758.5453,1.0)
		drops.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3(6.5,0,1)))
		drops.set_instance_custom_data(i,Color(float(i%56)/56.0,jitter,float(jet)/12.0,1))
