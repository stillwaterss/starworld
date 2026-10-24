extends Node3D
## The fountain answers a skipped stone with a short water dance: a column rises, eight
## jets close into a crown, twist into a rose, open into a five-point star and settle.
## Droplets follow ballistic arcs from the jets (no physics), drawn as one MultiMesh.
signal show_finished

const CENTER := Vector3(6.5, 0, 1.0)
const WATER_Y := .45
const RING := 1.85
const PILLAR_TOP := 2.55
const JETS := 8
const PER_JET := 56
const CENTER_DROPS := 120
const GRAVITY := 9.0
const LENGTH := 15.0

var world: Node3D
var drops: MultiMeshInstance3D
var light: OmniLight3D
var time := -1.0
var material: StandardMaterial3D
var night := 0.0

func _ready() -> void:
	name = "WaterShow"
	position = CENTER
	drops = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var mesh := SphereMesh.new()
	mesh.radius = .03
	mesh.height = .08
	mesh.radial_segments = 6
	mesh.rings = 3
	mm.mesh = mesh
	mm.instance_count = JETS * PER_JET + CENTER_DROPS
	drops.multimesh = mm
	material = StandardMaterial3D.new()
	material.albedo_color = Color(.82, .93, 1.0)
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = .1
	material.metallic_specular = .9
	drops.material_override = material
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drops.custom_aabb = AABB(Vector3(-5, -1, -5), Vector3(10, 9, 10))
	drops.visible = false
	add_child(drops)
	light = OmniLight3D.new()
	light.position = Vector3(0, 1.2, 0)
	light.omni_range = 5.5
	light.light_energy = 0
	add_child(light)

func playing() -> bool:return time >= 0

func play() -> void:
	time = 0.0
	drops.visible = true
	var cycle = world.get("day_cycle") if world else null
	night = cycle.weights.z if cycle else 0.0

## Per figure: jet launch speed, outward tilt (+ out / - in), swirl and spread.
func _figure(t: float) -> Dictionary:
	var keys := [
		[0.0, {"center": 0.0, "speed": 0.0, "tilt": .0, "swirl": .0, "star": 0.0}],
		[2.2, {"center": 6.2, "speed": 0.0, "tilt": .0, "swirl": .0, "star": 0.0}],
		[4.2, {"center": 5.0, "speed": 5.2, "tilt": -.42, "swirl": .0, "star": 0.0}],
		[7.2, {"center": 4.0, "speed": 5.6, "tilt": -.30, "swirl": .55, "star": 0.0}],
		[10.0, {"center": 2.6, "speed": 4.6, "tilt": .45, "swirl": .0, "star": 1.0}],
		[13.0, {"center": 3.4, "speed": 3.0, "tilt": .2, "swirl": .0, "star": .6}],
		[LENGTH, {"center": 0.0, "speed": 0.0, "tilt": .0, "swirl": .0, "star": 0.0}],
	]
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t <= b[0]:
			var k := smoothstep(0.0, 1.0, (t - a[0]) / (b[0] - a[0]))
			var out := {}
			for key in a[1]:out[key] = lerpf(a[1][key], b[1][key], k)
			return out
	return keys[-1][1]

func _process(delta: float) -> void:
	if time < 0:return
	time += delta
	var f := _figure(time)
	var mm := drops.multimesh
	var index := 0
	var tint := Color(.82, .93, 1.0).lerp(Color(1.0, .86, .55), night * .7)
	material.emission_enabled = night > .1
	material.emission = tint
	material.emission_energy_multiplier = night * 1.6
	light.light_color = tint
	light.light_energy = (0.4 + night * 1.6) * clampf(f.speed / 5.0 + f.center / 8.0, 0, 1)
	for j in JETS:
		var around := TAU * j / JETS
		var origin := Vector3(cos(around) * RING, WATER_Y, sin(around) * RING)
		var outward := Vector3(cos(around), 0, sin(around))
		var tangent := Vector3(-sin(around), 0, cos(around))
		# star figure: every other jet low and long, the rest short
		var star_gain := lerpf(1.0, (1.25 if j % 2 == 0 else .55), f.star)
		var speed: float = float(f.speed) * star_gain
		var dir: Vector3 = (Vector3.UP + outward * f.tilt * star_gain + tangent * f.swirl).normalized()
		var v: Vector3 = dir * speed
		var flight := maxf(2.0 * v.y / GRAVITY, .05)
		for n in PER_JET:
			var phase := fmod(time * .9 + float(n) / PER_JET, 1.0)
			var t := phase * flight
			var p: Vector3 = origin + v * t + Vector3.DOWN * .5 * GRAVITY * t * t
			var alive: bool = speed > .3 and p.y > WATER_Y - .02
			var scale := .7 + .5 * sin(float(n) * 1.7)
			mm.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (scale if alive else .001)), p))
			mm.set_instance_color(index, Color(tint, (.75 if alive else 0.0) * (1.0 - phase * .35)))
			index += 1
	for n in CENTER_DROPS:
		var phase := fmod(time * .8 + float(n) / CENTER_DROPS, 1.0)
		var v: Vector3 = Vector3(sin(float(n) * 2.4) * .45, f.center, cos(float(n) * 2.4) * .45)
		var flight := maxf(2.0 * v.y / GRAVITY, .05)
		var t := phase * flight
		var p: Vector3 = Vector3(0, PILLAR_TOP, 0) + v * t + Vector3.DOWN * .5 * GRAVITY * t * t
		var alive: bool = f.center > .3 and p.y > WATER_Y
		mm.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (1.0 if alive else .001)), p))
		mm.set_instance_color(index, Color(tint, .8 if alive else 0.0))
		index += 1
	if time >= LENGTH:
		time = -1.0
		drops.visible = false
		light.light_energy = 0
		show_finished.emit()
