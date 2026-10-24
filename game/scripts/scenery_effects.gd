extends RefCounted
## Lightweight runtime materials; all source meshes remain editable in Blender.

static func apply(root: Node3D) -> Array[ShaderMaterial]:
	var occluders: Array[ShaderMaterial] = []
	var leaves := ShaderMaterial.new()
	leaves.shader = preload("res://shaders/foliage.gdshader")
	var bark := ShaderMaterial.new()
	bark.shader = leaves.shader
	bark.set_shader_parameter("leaves", false)
	occluders.assign([leaves, bark])
	var water_shader := preload("res://shaders/star_water.gdshader")
	var still := ShaderMaterial.new()
	still.shader = water_shader
	var fall := ShaderMaterial.new()
	fall.shader = water_shader
	fall.set_shader_parameter("waterfall", true)
	var cloud := ShaderMaterial.new()
	cloud.shader = preload("res://shaders/soft_cloud.gdshader")
	var handmade: Array[ShaderMaterial] = []
	for kind in 4:
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/handmade_surface.gdshader")
		material.set_shader_parameter("kind",kind)
		handmade.append(material)
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var n := String(mesh.name)
		# This Godot/glTF import combination omits the flag on the first surface
		# of several shared materials, even though COLOR_0 is present in the GLB.
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			var colors = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
			if material and colors != null and not colors.is_empty():
				material.vertex_color_use_as_albedo = true
				material.vertex_color_is_srgb = false
				var key := material.resource_name.to_lower()
				if key.begins_with("wood") or key.begins_with("stone") or key=="rock" or key=="cream" or key.begins_with("roof"):
					var kind := 1 if key.begins_with("wood") else (2 if key=="rock" else (3 if key.begins_with("roof") else 0))
					mesh.set_surface_override_material(surface,handmade[kind])
		if n.begins_with("Canopy_"):
			mesh.material_override = leaves
		elif n.begins_with("TreeTrunks") or n.begins_with("StarTreeCore") or n.begins_with("Decor_WishingTree_trunk") or n.begins_with("Decor_WishingTree_bark"):
			mesh.material_override = bark
		elif n.begins_with("Decor_Water"):
			mesh.material_override = fall if n.ends_with("fall") else still
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif n.begins_with("Clouds"):
			mesh.material_override = cloud
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif n.begins_with("Decor_Flora") or n.ends_with("star") or n.ends_with("bulb"):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return occluders
