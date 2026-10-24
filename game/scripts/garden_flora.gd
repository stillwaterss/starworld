extends RefCounted
## The player's own flowers: a soil mound, a curved stem with two leaves and a cup of
## two petal rings. open_amount 0 is a closed bud, 1 a full bloom; glow follows night.
const PETAL_COLORS := [Color("f29dbd"), Color("ffcf6e"), Color("8fb1ff")]
const CENTER := Color("ffe9a6")

static func _mat(color: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = .78
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow > 0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m

## Curved petal: a fan of quads bending upward at the tip, pointing along +Z.
static func _petal_mesh(length: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 5
	var cols := 4
	var grid := []
	for r in rows + 1:
		var t := float(r) / rows
		var row := []
		var w := width * sin(PI * clampf(t * .92 + .04, 0, 1)) * (1.0 - t * .25)
		for c in cols + 1:
			var u := float(c) / cols - .5
			row.append(Vector3(u * w, t * t * length * .35 - absf(u) * w * .25, t * length))
		grid.append(row)
	for r in rows:
		for c in cols:
			var a: Vector3 = grid[r][c]
			var b: Vector3 = grid[r][c + 1]
			var d: Vector3 = grid[r + 1][c]
			var e: Vector3 = grid[r + 1][c + 1]
			for v in [a, d, b, b, d, e]:st.add_vertex(v)
	st.generate_normals()
	return st.commit()

static func build(index: int) -> Node3D:
	var root := Node3D.new()
	root.name = "PlayerFlower%d" % index
	var petal_color: Color = PETAL_COLORS[index % PETAL_COLORS.size()]
	var soil := MeshInstance3D.new()
	var mound := SphereMesh.new()
	mound.radius = .2
	mound.height = .4
	mound.radial_segments = 14
	mound.rings = 6
	soil.mesh = mound
	soil.scale = Vector3(1, .22, 1)
	soil.position.y = .01
	soil.material_override = _mat(Color("6f5440"))
	root.add_child(soil)
	var plant := Node3D.new()
	plant.name = "Plant"
	root.add_child(plant)
	# stem: three tapering segments with a gentle S curve
	var points := [Vector3(0, 0, 0), Vector3(.025, .14, .01), Vector3(-.02, .28, -.01), Vector3(.01, .4, 0)]
	var stem_mat := _mat(Color("7fb48e"))
	for i in 3:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var seg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = .011 - i * .002
		cyl.bottom_radius = .014 - i * .002
		cyl.height = a.distance_to(b)
		cyl.radial_segments = 8
		cyl.rings = 1
		seg.mesh = cyl
		seg.material_override = stem_mat
		seg.position = (a + b) / 2
		seg.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
		plant.add_child(seg)
	var leaf_mesh := _petal_mesh(.16, .07)
	for side in [-1, 1]:
		var leaf := MeshInstance3D.new()
		leaf.mesh = leaf_mesh
		leaf.material_override = _mat(Color("8fc79a"))
		leaf.position = Vector3(0, .1 + (.06 if side > 0 else 0), 0)
		leaf.rotation = Vector3(-.5, side * 1.3 + index, 0)
		plant.add_child(leaf)
	var head := Node3D.new()
	head.name = "Head"
	head.position = points[3]
	plant.add_child(head)
	var petal := _petal_mesh(.15, .095)
	var petal_mat := _mat(petal_color, .0)
	for ring in 2:
		for j in 6:
			var hinge := Node3D.new()
			hinge.name = "Petal%d_%d" % [ring, j]
			hinge.rotation.y = TAU * j / 6.0 + ring * PI / 6.0
			head.add_child(hinge)
			var p := MeshInstance3D.new()
			p.mesh = petal
			p.material_override = petal_mat
			p.scale = Vector3.ONE * (1.0 - ring * .22)
			hinge.add_child(p)
	var center := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radial_segments = 12
	dome.rings = 6
	dome.radius = .028
	dome.height = .05
	center.mesh = dome
	center.material_override = _mat(CENTER, .6)
	center.position.y = .01
	head.add_child(center)
	root.set_meta("petal_material", petal_mat)
	set_open(root, 0.0)
	return root

## 0 closed bud (petals upright and wrapped) .. 1 open cup.
static func set_open(flower: Node3D, amount: float) -> void:
	var head := flower.get_node_or_null("Plant/Head")
	if not head:return
	for hinge in head.get_children():
		if not String(hinge.name).begins_with("Petal"):continue
		var ring := int(String(hinge.name)[5])
		var open := lerpf(-1.45, -.35 - ring * .35, amount)
		hinge.rotation.x = open
	flower.set_meta("open", amount)

static func set_glow(flower: Node3D, night: float) -> void:
	var m: StandardMaterial3D = flower.get_meta("petal_material")
	m.emission_enabled = night > .05
	m.emission = m.albedo_color
	m.emission_energy_multiplier = night * .55 * float(flower.get_meta("open", 0.0))
