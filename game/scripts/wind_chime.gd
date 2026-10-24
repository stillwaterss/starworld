extends Node3D
## Wind chime beside the tree-house door: a wooden arm, a disc and five brass tubes on
## strings. ring() gives each tube a damped swing; idle wind keeps them barely moving.
const TUBES := [[.0, .34], [.072, .28], [-.072, .30], [.04, .23], [-.04, .25]]

var tubes: Array[Node3D] = []
var swing: Array[float] = []
var phase: Array[float] = []
var clock := 0.0

func _ready() -> void:
	name = "WindChime"
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("8a5f3c")
	wood.roughness = .8
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("d9b46a")
	brass.metallic = .7
	brass.roughness = .32
	var string := StandardMaterial3D.new()
	string.albedo_color = Color("e8dcc6")
	var arm := MeshInstance3D.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(.06, .06, .62)
	arm.mesh = beam
	arm.material_override = wood
	arm.position = Vector3(0, .12, -.28)
	add_child(arm)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.radial_segments = 10
	cyl.rings = 1
	cyl.top_radius = .12
	cyl.bottom_radius = .12
	cyl.height = .035
	disc.mesh = cyl
	disc.material_override = wood
	add_child(disc)
	var hook := MeshInstance3D.new()
	var line := CylinderMesh.new()
	line.radial_segments = 10
	line.rings = 1
	line.top_radius = .004
	line.bottom_radius = .004
	line.height = .12
	hook.mesh = line
	hook.material_override = string
	hook.position.y = .06
	add_child(hook)
	for spec in TUBES:
		var pivot := Node3D.new()
		var a := TAU * tubes.size() / TUBES.size()
		pivot.position = Vector3(cos(a) * .085, -.02, sin(a) * .085)
		add_child(pivot)
		var thread := MeshInstance3D.new()
		var t := CylinderMesh.new()
		t.radial_segments = 10
		t.rings = 1
		t.top_radius = .003
		t.bottom_radius = .003
		t.height = .09
		thread.mesh = t
		thread.material_override = string
		thread.position.y = -.045
		pivot.add_child(thread)
		var tube := MeshInstance3D.new()
		var body := CylinderMesh.new()
		body.top_radius = .012
		body.bottom_radius = .012
		body.height = float(spec[1])
		body.radial_segments = 10
		tube.mesh = body
		tube.material_override = brass
		tube.position.y = -.09 - float(spec[1]) / 2
		pivot.add_child(tube)
		tubes.append(pivot)
		swing.append(0.0)
		phase.append(randf() * TAU)
	var clapper := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radial_segments = 12
	ball.rings = 6
	ball.radius = .028
	ball.height = .056
	clapper.mesh = ball
	clapper.material_override = wood
	clapper.position.y = -.2
	add_child(clapper)

func ring(strength := 1.0) -> void:
	for i in swing.size():swing[i] = strength * (.35 + .25 * sin(i * 2.1))

func _process(delta: float) -> void:
	clock += delta
	for i in tubes.size():
		swing[i] = lerpf(swing[i], 0.0, clampf(delta * .9, 0, 1))
		var breeze := .03 * sin(clock * .8 + phase[i])
		var amount := breeze + swing[i] * sin(clock * (7.5 + i * .6) + phase[i])
		tubes[i].rotation = Vector3(amount, 0, amount * .6 * cos(phase[i]))
