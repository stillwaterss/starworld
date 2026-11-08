extends RefCounted
## v28: the generated character models are not closed meshes (thousands of tiny seams);
## whatever is behind them (the sky, a wall) showed through as specks and cracks. Two more
## passes of the same material close them: one drawn 4 mm inside the surface (the seams
## show its own colour) and one 3 mm outside drawn from the back (it fills the seams along
## the outline). Materials are shared, so each is made once.
static var _sealed := {}

static func seal(model: Node) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:continue
		for k in mesh.mesh.get_surface_count():
			var m = mesh.get_surface_override_material(k)
			if m == null:m = mesh.mesh.surface_get_material(k)
			if not m is BaseMaterial3D or _sealed.values().has(m):continue
			if not _sealed.has(m):
				var outer: BaseMaterial3D = m.duplicate()
				outer.grow = true
				outer.grow_amount = .003
				outer.cull_mode = BaseMaterial3D.CULL_FRONT
				var inner: BaseMaterial3D = m.duplicate()
				inner.grow = true
				inner.grow_amount = -.004
				inner.cull_mode = BaseMaterial3D.CULL_DISABLED
				inner.next_pass = outer
				var front: BaseMaterial3D = m.duplicate()
				front.next_pass = inner
				_sealed[m] = front
			mesh.set_surface_override_material(k, _sealed[m])
