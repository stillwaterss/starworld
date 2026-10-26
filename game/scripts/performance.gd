extends Node3D
## Short staged moments for everyday actions (plant, water, wish lantern, wind chime,
## skipping a stone, fireflies, knocking, polishing): walk to a mark, turn, glide the
## camera to a mid shot, play procedural poses with a small prop, fire the effect on the
## beat, glide back. Game state changes happen in the caller right away; this only shows
## them. E / Esc / Space hurries the rest of a performance.
signal started(kind: String)
signal finished(kind: String)

const X := Vector3(1, 0, 0)    # skeleton space: +X is the character's left
const Y := Vector3(0, 1, 0)
const Z := Vector3(0, 0, 1)    # forward

var world: Node3D
var player: CharacterBody3D
var camera: Camera3D
var busy := false
var kind := ""
var hurry := false
var socket: BoneAttachment3D
var prop: Node3D
var _glide: Tween
var _return_camera: Camera3D
var _mouse := 0
var _hidden_layers: Array[CanvasLayer] = []

func _ready() -> void:
	name = "Performance"
	player = world.player
	camera = Camera3D.new()
	camera.name = "PerformanceCamera"
	camera.fov = 46
	camera.near = .05
	camera.far = 1500
	add_child(camera)
	var skeletons: Array[Node] = player.model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		socket = BoneAttachment3D.new()
		socket.name = "PropSocket"
		socket.bone_name = "hand.R"
		skeletons[0].add_child(socket)

# ------------------------------------------------------------------ poses
static func rot(axis: Vector3, degrees: float) -> Quaternion:
	return Quaternion(axis, deg_to_rad(degrees))

## Right arm rest points to the character's right (-X); left arm to +X.
static func arm_r(forward: float, lift := 0.0) -> Quaternion:
	return rot(X, -lift) * rot(Y, forward)

static func arm_l(forward: float, lift := 0.0) -> Quaternion:
	return rot(X, -lift) * rot(Y, -forward)

static func relaxed() -> Dictionary:
	return {"arm.R": rot(Z, 72), "arm.L": rot(Z, -72)}

static func pose(name: String, t := 0.0) -> Dictionary:
	match name:
		"kneel":
			return {"spine": rot(X, 34), "head": rot(X, 14), "arm.R": arm_r(90, -55 + sin(t * 9.0) * 9.0), "arm.L": arm_l(90, -50), "hand.R": rot(X, 18), "hand.L": rot(X, 18)}
		"admire":
			return {"spine": rot(X, 8), "head": rot(X, 16), "arm.R": arm_r(70, -35), "arm.L": arm_l(70, -35)}
		"pour":
			return {"spine": rot(X, 12), "head": rot(X, 12), "arm.R": arm_r(82, -22), "hand.R": rot(Z, 38 + sin(t * 3.0) * 4.0), "arm.L": rot(Z, -70)}
		"hold_up":
			return {"spine": rot(X, -8), "head": rot(X, -24), "arm.R": arm_r(90, 58), "arm.L": arm_l(90, 58)}
		"release":
			return {"spine": rot(X, -12), "head": rot(X, -34), "arm.R": arm_r(80, 82), "arm.L": arm_l(80, 82)}
		"reach_up":
			return {"head": rot(X, -18), "arm.R": arm_r(88, 50 + sin(t * 14.0) * 6.0), "arm.L": rot(Z, -70)}
		"listen":
			return {"head": rot(Z, 12) * rot(X, -6), "arm.R": rot(Z, 70), "arm.L": arm_l(60, -40)}
		"windup":
			return {"spine": rot(Y, 22) * rot(X, 10), "arm.R": arm_r(-30, 10), "arm.L": arm_l(60, -20)}
		"throw":
			return {"spine": rot(Y, -18) * rot(X, 14), "arm.R": arm_r(112, 6), "arm.L": arm_l(30, -40), "head": rot(X, 10)}
		"cup":
			return {"spine": rot(X, 18), "head": rot(X, 22), "arm.R": arm_r(74, -18), "arm.L": arm_l(74, -18), "hand.R": rot(Y, -20), "hand.L": rot(Y, 20)}
		"look_up":
			return {"head": rot(X, -30), "spine": rot(X, -6), "arm.R": rot(Z, 64), "arm.L": rot(Z, -64)}
		"knock":
			return {"arm.R": arm_r(86, 8), "hand.R": rot(X, -22 + absf(sin(t * 7.0)) * 34.0), "arm.L": rot(Z, -72)}
		"polish":
			return {"spine": rot(X, 6), "arm.R": arm_r(84 + cos(t * 6.0) * 10.0, 10 + sin(t * 6.0) * 10.0), "arm.L": rot(Z, -70)}
		"hug":
			return {"head": rot(X, 14), "arm.R": arm_r(70, -10), "arm.L": arm_l(70, -10), "hand.R": rot(Y, -30), "hand.L": rot(Y, 30)}
	return relaxed()

func set_pose(name: String, speed := 7.0) -> void:
	player.model.set_pose(pose(name, 0.0), speed)

## Keeps a moving pose (digging, pouring, polishing) alive for `seconds`.
func animate_pose(name: String, seconds: float, speed := 9.0) -> void:
	var t := 0.0
	while t < seconds:
		player.model.set_pose(pose(name, t), speed)
		var step := get_process_delta_time()
		await get_tree().process_frame
		t += step * (4.0 if hurry else 1.0)

# ------------------------------------------------------------------ flow
func can_start() -> bool:
	if busy or not is_instance_valid(player) or player.model.using_fallback:return false
	var cozy = world.get("activities")
	if cozy and cozy.photo:return false
	if world.interactions.mode != "idle":return false
	var scene = world.get("scene_actions")
	return scene == null or scene.seat_state == "free"

func begin(id: String, focus: Vector3, view := {}) -> bool:
	if not can_start():return false
	busy = true
	kind = id
	hurry = false
	player.controls_locked = true
	player.velocity = Vector3.ZERO
	player.model.set_performing(true)
	_return_camera = get_viewport().get_camera_3d()
	camera.global_transform = _return_camera.global_transform if _return_camera else camera.global_transform
	camera.fov = _return_camera.fov if _return_camera else 50.0
	camera.current = true
	# a little cutscene: every HUD layer steps aside until the moment is over
	_hidden_layers.clear()
	for node in world.get_children():
		if node is CanvasLayer and node.visible:
			_hidden_layers.append(node)
			node.visible = false
	started.emit(id)
	frame(focus, view)
	return true

## Glides to a three-quarter mid shot of the player and `focus`, avoiding walls.
func frame(focus: Vector3, view := {}) -> void:
	var p := player.global_position
	var facing: Vector3 = -player.model.global_basis.z
	facing.y = 0
	facing = facing.normalized() if facing.length() > .01 else Vector3.FORWARD
	var look: Vector3 = view.get("look", p.lerp(focus, float(view.get("mix", .45))) + Vector3.UP * float(view.get("look_height", .75)))
	# Wide and from the side or behind: the characters are small figures in their place,
	# never a close look at a face (the models are not made for close-ups).
	var distance := maxf(float(view.get("distance", 4.6)), 4.4)
	# a low shot looking up (the wish lantern rising) keeps its height
	var height := float(view.get("height", 2.0)) if view.get("low", false) else maxf(float(view.get("height", 2.0)), 1.9)
	var eye: Vector3 = view.get("eye", Vector3.INF)
	if eye == Vector3.INF:
		var space := world.get_world_3d().direct_space_state
		# NPCs count as obstacles: a friend standing in front of the camera is a bad shot
		var exclude: Array[RID] = [player.get_rid()]
		eye = look + facing.rotated(Vector3.UP, deg_to_rad(100)) * distance + Vector3.UP * height
		for angle in [100, -100, 130, -130, 75, -75, 160, -160, 55, -55]:
			var candidate: Vector3 = look + facing.rotated(Vector3.UP, deg_to_rad(angle)) * distance + Vector3.UP * height
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(look, candidate, 3, exclude)).is_empty():
				eye = candidate
				break
	glide_to(Transform3D(Basis.looking_at(look - eye), eye), minf(float(view.get("fov", 44)), 50.0), float(view.get("time", .9)))

func glide_to(goal: Transform3D, fov: float, seconds := .9) -> void:
	if _glide:_glide.kill()
	_glide = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glide.tween_property(camera, "global_transform", goal, seconds)
	_glide.tween_property(camera, "fov", fov, seconds)

func finish(back_seconds := .8) -> void:
	set_pose("relaxed")
	if is_instance_valid(_return_camera):
		glide_to(_return_camera.global_transform, _return_camera.fov, back_seconds)
		if _glide:await _glide.finished
		if is_instance_valid(_return_camera):_return_camera.current = true
	drop_prop()
	for layer in _hidden_layers:
		if is_instance_valid(layer):layer.visible = true
	_hidden_layers.clear()
	player.model.set_performing(false)
	player.controls_locked = false
	busy = false
	var done := kind
	kind = ""
	finished.emit(done)

func wait(seconds: float) -> void:
	var left := seconds
	while left > 0:
		await get_tree().process_frame
		left -= get_process_delta_time() * (4.0 if hurry else 1.0)

## Walks to `mark` (scene_actions' scripted movement) for at most two seconds, then turns to `face`.
func approach(mark: Vector3, face: Vector3) -> void:
	var limit := 2.2
	if Vector2(mark.x - player.global_position.x, mark.z - player.global_position.z).length() > .3:
		player.scripted_active = true
		player.scripted_speed = 1.7
		while limit > 0:
			var d := mark - player.global_position
			d.y = 0
			if d.length() < .18:break
			player.scripted_direction = d.normalized()
			await get_tree().physics_frame
			limit -= get_physics_process_delta_time()
		player.scripted_active = false
		player.scripted_direction = Vector3.ZERO
		player.velocity = Vector3.ZERO
	await turn_to(face)

func turn_to(face: Vector3, seconds := .35) -> void:
	var d := face - player.global_position
	if Vector2(d.x, d.z).length() < .05:return
	var goal := atan2(-d.x, -d.z)
	var start: float = player.model.rotation.y
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		player.model.rotation.y = lerp_angle(start, goal, smoothstep(0.0, 1.0, t / seconds))

func _input(event: InputEvent) -> void:
	if not busy or not event is InputEventKey or not event.pressed or event.echo:return
	if event.physical_keycode in [KEY_E, KEY_ESCAPE, KEY_SPACE]:
		hurry = true
		get_viewport().set_input_as_handled()
	elif event.physical_keycode != KEY_M:
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ props
func hold_prop(node: Node3D, offset := Vector3(0, -.06, .04)) -> void:
	drop_prop()
	prop = node
	if is_instance_valid(socket):
		socket.add_child(node)
		node.position = offset
		# the skeleton is scaled 1.55; keep props at their modelled size
		node.scale = Vector3.ONE / maxf(socket.global_basis.get_scale().x, .01)
	else:
		player.add_child(node)
		node.position = Vector3(.3, .8, -.3)

func drop_prop() -> void:
	if is_instance_valid(prop):prop.queue_free()
	prop = null

static func material(color: Color, glow := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.roughness = .7
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow > 0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m

static func piece(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material, rotation_deg := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.rotation_degrees = rotation_deg
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func cylinder(radius: float, height: float, top := -1.0, segments := 14) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius if top < 0 else top
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m

static func ball(radius: float, segments := 12) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2
	m.radial_segments = segments
	m.rings = segments / 2
	return m

static func watering_can() -> Node3D:
	if OS.has_feature("web") and is_instance_valid(_web_prop_templates.get("watering_can")) :return _web_prop_copy("watering_can")
	var can := Node3D.new()
	can.name = "WateringCan"
	var tin := material(Color("7fa7b5"))
	var dark := material(Color("4f6f7c"))
	piece(can, cylinder(.075, .14), Vector3(0, -.04, .06), tin)
	piece(can, cylinder(.012, .16, .007), Vector3(0, -.01, .17), dark, Vector3(62, 0, 0))
	var handle := TorusMesh.new()
	handle.inner_radius = .045
	handle.outer_radius = .058
	piece(can, handle, Vector3(0, .05, .02), dark, Vector3(0, 90, 0))
	return can

## The modelled star paper lantern (assets/props) when present, else a simple one.
const LANTERN_MODEL := "res://assets/props/prop_lantern.glb"
static var _lantern_scene: PackedScene

static func paper_lantern() -> Node3D:
	if OS.has_feature("web") and is_instance_valid(_web_prop_templates.get("paper_lantern")) :return _web_prop_copy("paper_lantern")
	if _lantern_scene == null and ResourceLoader.exists(LANTERN_MODEL):_lantern_scene = load(LANTERN_MODEL)
	if _lantern_scene:
		var root := Node3D.new()
		root.name = "WishLanternProp"
		var model: Node3D = _lantern_scene.instantiate()
		model.scale = Vector3.ONE * .36
		model.position.y = .06
		root.add_child(model)
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for i in mesh.get_surface_override_material_count():
				var base := mesh.get_active_material(i)
				if not base is StandardMaterial3D:continue
				var m: StandardMaterial3D = base.duplicate()
				m.emission_enabled = true
				m.emission = Color(1, .78, .45)
				m.emission_energy_multiplier = 1.0
				if m.albedo_texture:m.emission_texture = m.albedo_texture
				m.set_meta("lantern_glow", true)
				mesh.set_surface_override_material(i, m)
		var glow := OmniLight3D.new()
		glow.light_color = Color("ffcf89")
		glow.light_energy = .8
		glow.omni_range = 2.6
		glow.position.y = .22
		root.add_child(glow)
		return root
	var lantern := Node3D.new()
	lantern.name = "WishLanternProp"
	piece(lantern, cylinder(.13, .26, .16), Vector3(0, .22, 0), material(Color("ffd08a"), 1.4, .92))
	piece(lantern, cylinder(.16, .02), Vector3(0, .36, 0), material(Color("a47752")))
	piece(lantern, cylinder(.13, .02), Vector3(0, .09, 0), material(Color("a47752")))
	var light := OmniLight3D.new()
	light.light_color = Color("ffcf89")
	light.light_energy = .8
	light.omni_range = 2.6
	light.position.y = .22
	lantern.add_child(light)
	return lantern

static func pebble() -> Node3D:
	if OS.has_feature("web") and is_instance_valid(_web_prop_templates.get("pebble")) :return _web_prop_copy("pebble")
	var stone := Node3D.new()
	var mesh := piece(stone, ball(.035, 8), Vector3.ZERO, material(Color("b8b3a6")))
	mesh.scale = Vector3(1.2, .55, 1.0)
	return stone

static func seed_pouch() -> Node3D:
	if OS.has_feature("web") and is_instance_valid(_web_prop_templates.get("seed_pouch")) :return _web_prop_copy("seed_pouch")
	var pouch := Node3D.new()
	piece(pouch, ball(.05, 10), Vector3(0, -.02, .03), material(Color("c9a06a")))
	piece(pouch, cylinder(.02, .03), Vector3(0, .03, .03), material(Color("8a6a44")))
	return pouch

static func cloth() -> Node3D:
	if OS.has_feature("web") and is_instance_valid(_web_prop_templates.get("cloth")) :return _web_prop_copy("cloth")
	var rag := Node3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(.11, .02, .09)
	piece(rag, box, Vector3(0, -.02, .05), material(Color("e9d7b8")), Vector3(10, 20, 0))
	return rag

## Compile prop material variants during the loading cover, then reuse their meshes.
static var _web_prop_templates := {}
static var _web_shader_keepalive: Array[Material]=[]
static var _web_shader_variants:={}
func prepare_web_props() -> void:
	if not OS.has_feature("web"):return
	while not world._web_geometry_ready:await get_tree().process_frame
	if not _web_prop_templates.is_empty():
		if is_instance_valid(_web_prop_templates.get("paper_lantern")):return
		_web_prop_templates.clear()
	var nodes: Array[Node3D]=[watering_can(),paper_lantern(),pebble(),seed_pouch(),cloth()]
	var names: Array[String]=["watering_can","paper_lantern","pebble","seed_pouch","cloth"]
	for i in nodes.size():
		add_child(nodes[i])
		nodes[i].visible=false
		_web_prop_templates[names[i]]=nodes[i]
	var cozy=world.activities
	var flowers: Array[Node3D]=cozy._web_prepare_flowers()
	# Programs survive a scene reload; never switch the visible opening camera.
	if bool(JavaScriptBridge.eval("window.starworldAnimationsWarm === true")):return
	var previous:=get_viewport().get_camera_3d()
	var warm_camera:=Camera3D.new()
	warm_camera.fov=44
	warm_camera.far=1500
	world.add_child(warm_camera)
	# Render copies of the actual skinned costumes under both lighting paths.
	# Moving the real player during loading could accidentally trigger visits.
	var costumes:=Node3D.new()
	world.add_child(costumes)
	var swatches:=Node3D.new()
	costumes.add_child(swatches)
	var swatch_mesh:=BoxMesh.new()
	swatch_mesh.size=Vector3.ONE*.12
	var material_ids:={}
	for visual in world.find_children("*","Node3D",true,false):
		if visual.get_script()!=preload("res://scripts/actor_visual.gd"):continue
		if visual.get_child_count()==0:continue
		for mesh in visual.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh==null:continue
			for surface in mesh.mesh.get_surface_count():
				var material: Material=mesh.get_active_material(surface)
				if material==null or material_ids.has(material.get_rid()):continue
				material_ids[material.get_rid()]=true
				var sample:=MeshInstance3D.new()
				sample.mesh=swatch_mesh
				sample.material_override=material
				sample.position=Vector3((material_ids.size()%8-3.5)*.16,1.8,(material_ids.size()/8)*.16)
				swatches.add_child(sample)
	var stream: Node3D=cozy._pour_stream()
	stream.global_position=cozy.GARDEN+Vector3(0,.9,1.7)
	var ripple:=MeshInstance3D.new()
	var torus:=TorusMesh.new()
	torus.inner_radius=.24;torus.outer_radius=.27;torus.rings=24;torus.ring_segments=4
	ripple.mesh=torus
	var ripple_material:=StandardMaterial3D.new()
	ripple_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ripple_material.albedo_color=Color("c6e6e7")
	ripple.material_override=ripple_material
	world.add_child(ripple)
	ripple.global_position=cozy.WATER+Vector3.UP*.8
	var jets: MultiMeshInstance3D=cozy.water_show.drops
	var flies: MultiMeshInstance3D=cozy.swarm.flies
	var jets_buffer: PackedFloat32Array=jets.multimesh.buffer
	var flies_buffer: PackedFloat32Array=flies.multimesh.buffer
	var jets_count:=jets.multimesh.visible_instance_count
	var flies_count:=flies.multimesh.visible_instance_count
	jets.multimesh.visible_instance_count=4
	flies.multimesh.visible_instance_count=4
	jets.visible=true
	flies.visible=true
	for i in 4:
		jets.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3(i*.16,.8,0)))
		jets.multimesh.set_instance_color(i,Color(.8,.9,1,.8))
	for flower in flowers:
		flower.visible=true
		flower.scale=Vector3.ONE
	var points: Array[Vector3]=[cozy.GARDEN+Vector3(0,.4,1.7),Vector3(0,60,0)]
	var stage:=0
	var warm_materials: Array[Material]=[jets.material_override,flies.material_override,cozy._web_pour_material(),ripple_material]
	var ending=world.content.ending
	var old_sky_visible: bool=ending.sky_layer.visible
	var old_words_visible: bool=ending.layer.visible
	var old_dream_alpha: float=ending.dream.modulate.a
	ending.sky_layer.visible=true
	ending.dream.modulate.a=.01
	ending.layer.visible=true
	warm_materials.append(ending.dream.material)
	var words:={}
	for lines in [ending.NARRATION_GROUND,ending.NARRATION_SHIP,ending.NARRATION_RELEASE,ending.NARRATION_DESCENT,ending.CREDITS,ending.NARRATION_LAST]:
		for line in lines:
			var size: int={"art":40,"title":46,"xg":30,"small":19}.get(String(line[1]),29)
			if not words.has(size):words[size]=PackedStringArray()
			var snippets: PackedStringArray=words[size]
			snippets.append(world.content.named(String(line[0]).trim_prefix("小光：")))
			words[size]=snippets
	var type_samples:=CanvasLayer.new()
	type_samples.layer=15
	world.add_child(type_samples)
	for size in words:
		var label:=Label.new()
		# Prime each ending glyph at the actual outline size. Unique glyphs fit
		# inside the viewport, including words first seen late in the farewell.
		var glyphs:={}
		for glyph in String("\n".join(words[size])):
			if glyph!="\n":glyphs[glyph]=true
		label.text="".join(PackedStringArray(glyphs.keys()))
		label.size=Vector2(1180,2400)
		label.position=Vector2(40,20)
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_override("font",ending._letter_font)
		label.add_theme_font_size_override("font_size",size)
		label.add_theme_constant_override("outline_size",4)
		label.add_theme_constant_override("shadow_outline_size",18 if size>=40 else 10)
		label.add_theme_color_override("font_shadow_color",Color(1,.8,.55,.5))
		label.modulate.a=.01
		type_samples.add_child(label)
	for tree in nodes+flowers+[costumes]:
		for mesh in tree.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh==null:continue
			for surface in mesh.mesh.get_surface_count():
				var material: Material=mesh.get_active_material(surface)
				if material!=null and material not in warm_materials:warm_materials.append(material)
	for at in points:
		costumes.global_position=at+Vector3(0,-.4,1.0)
		jets.global_position=at-Vector3(0,.4,0)
		ripple.global_position=at+Vector3.UP*.2
		stream.global_position=at+Vector3.UP*.7
		for i in 4:
			flies.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY,at+Vector3(i*.16,1,0)))
			flies.multimesh.set_instance_color(i,Color(1,.9,.6,.7))
		for i in nodes.size():nodes[i].global_position=at+Vector3((i-2)*.35,.2,0);nodes[i].visible=true
		for angle in [0,90,180,270]:
			stage+=1
			JavaScriptBridge.eval("window.starworldWarmup = "+JSON.stringify({"stage":stage,"total":points.size()*4,"label":"准备花朵、浇水和演出材质"}))
			var eye: Vector3=at+Vector3(0,2.0,4.8).rotated(Vector3.UP,deg_to_rad(float(angle)))
			warm_camera.look_at_from_position(eye,at)
			warm_camera.current=true
			for lamp in nodes[1].find_children("*","Light3D",true,false):lamp.visible=angle>=180
			cozy.water_show.material.emission_enabled=angle in [90,270]
			cozy.water_show.light.light_energy=1.6 if angle>=180 else 0.0
			for flower in flowers:cozy.Flora.set_open(flower,1.0);cozy.Flora.set_glow(flower,1.0 if angle in [90,270] else 0.0)
			for i in 2:await RenderingServer.frame_post_draw
			for material in warm_materials:_web_pin_shader_variant(material)
			# Let duplicate materials retain their variant before changing the source.
			await RenderingServer.frame_post_draw
			if stage==1:type_samples.queue_free()
	# The last flight reveals distant scenery without local lights, then the
	# lighthouse beam. Prime those real-world light paths before handing over.
	var star_row=ending.Cozy.StarRow.new(5)
	var final_samples:=CanvasLayer.new()
	final_samples.layer=15
	world.add_child(final_samples)
	final_samples.add_child(star_row)
	star_row.modulate.a=.01
	var lights: Array[Light3D]=[]
	for lamp in world.find_children("*","Light3D",true,false):
		if (lamp is OmniLight3D or lamp is SpotLight3D) and lamp.visible:
			lights.append(lamp)
			lamp.visible=false
	var spotlight:=SpotLight3D.new()
	spotlight.spot_range=400
	spotlight.spot_angle=89
	spotlight.light_energy=1.0
	world.add_child(spotlight)
	spotlight.look_at_from_position(Vector3(0,100,0),Vector3.ZERO,Vector3.FORWARD)
	for mode in 2:
		JavaScriptBridge.eval("window.starworldWarmup = "+JSON.stringify({"stage":mode+1,"total":2,"label":"飞艇与告别画面"}))
		spotlight.visible=mode==1
		for lamp in lights:lamp.visible=mode==1
		warm_camera.look_at_from_position(Vector3(80,75,100),Vector3(0,5,0))
		for i in 2:await RenderingServer.frame_post_draw
	for lamp in lights:lamp.visible=true
	spotlight.queue_free()
	final_samples.queue_free()
	for flower in flowers:
		cozy.Flora.set_open(flower,0.0)
		cozy.Flora.set_glow(flower,world.day_cycle.weights.z)
		flower.visible=false
		flower.scale=Vector3.ONE*.01
	for lamp in nodes[1].find_children("*","Light3D",true,false):lamp.visible=true
	for node in nodes:node.visible=false;node.transform=Transform3D.IDENTITY
	costumes.queue_free()
	stream.queue_free()
	ripple.queue_free()
	jets.visible=false
	flies.visible=false
	jets.position=Vector3.ZERO
	jets.multimesh.buffer=jets_buffer
	flies.multimesh.buffer=flies_buffer
	jets.multimesh.visible_instance_count=jets_count
	flies.multimesh.visible_instance_count=flies_count
	cozy.water_show.material.emission_enabled=false
	cozy.water_show.light.light_energy=0.0
	ending.sky_layer.visible=old_sky_visible
	ending.dream.modulate.a=old_dream_alpha
	ending.layer.visible=old_words_visible
	if is_instance_valid(previous):previous.current=true
	warm_camera.queue_free()
	JavaScriptBridge.eval("window.starworldAnimationsWarm = true; window.starworldWarmup = null; window.starworldWarmupPrograms = "+str(_web_shader_keepalive.size()))

static func _web_prop_copy(id: String) -> Node3D:
	var node: Node3D=_web_prop_templates[id].duplicate()
	node.visible=true
	node.transform=Transform3D.IDENTITY
	return node

func _web_pin_shader_variant(material: Material) -> void:
	var key:=str(material.get_instance_id())
	if material is BaseMaterial3D:key+="/emission="+str(material.emission_enabled)
	if _web_shader_variants.has(key):return
	_web_shader_variants[key]=true
	# Strong immutable snapshots prevent Godot from dropping a precompiled variant
	# when an emission flag changes or a new story replaces the whole scene.
	var keep: Material=material.duplicate()
	_web_shader_keepalive.append(keep)
