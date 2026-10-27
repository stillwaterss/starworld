extends Node3D
## 小光 lights the island up again. The island's lamps run on starlight; since the
## lighthouse went dark they have burned low, so while the story runs every town lamp
## is dimmed to a share of its strength that grows with each place 小光 lights (weights
## below; all of them together give full strength). perform(site) is the staged moment:
## the player lifts both hands, 小光 flies to the place, the place lights up (with its
## own glow, sparkles and, for the street lamps, a wave of lamps coming on outward from
## the square) and 小光 comes back a little brighter.
## Before the lighthouse is lit, a faint light blinks three times every few seconds at
## dusk and night on the lighthouse island and in grandma's window: the two of them
## still signalling each other across the cloud sea.
const SITES := {
	"garden": {"label": "花园的夜光花", "weight": .08},
	"treehouse": {"label": "树屋的小圆窗", "weight": .08},
	"lamps": {"label": "广场的路灯", "weight": .3},
	"oven": {"label": "面包房的炉火", "weight": .06},
	"child": {"label": "孩子的小夜灯", "weight": .06},
	"fountain": {"label": "喷泉的灯", "weight": .1},
	"ship": {"label": "飞艇的心", "weight": .07},
	"lighthouse": {"label": "灯塔", "weight": .15},
	"grandma": {"label": "奶奶窗台的灯", "weight": .1},
}
const DIM := .2
const WAVE_SPEED := 14.0          # metres per second the street lamps come on at

var content
var world: Node3D
var factor := 1.0                 # what the town lamps are at now
var boost := 1.0                  # the last night: everything a little brighter
var _wave_origin := Vector3.ZERO
var _wave_clock := -1.0
var _wave_from := 1.0
var _clock := 0.0
var _built := {}                  # site -> nodes made for it
var _blinks: Array[MeshInstance3D] = []
## The scene's own glowing parts that dim with the lamps: the lamp heads, the house
## windows and the bridge bulbs. [material, its full emission, its colour]
var _glowing: Array = []
const GLOWING := ["Lamps_star", "Decor_Details_window", "Bridge_L_bulb", "Bridge_R_bulb"]

func _ready() -> void:
	name = "IslandLights"
	world = content.world
	_setup.call_deferred()

func _setup() -> void:
	var guard := 0
	while content.props.doors.is_empty() and guard < 600:
		await get_tree().physics_frame
		guard += 1
	await get_tree().physics_frame
	for site in SITES:
		if is_lit(site):_show(site, false)
	_build_door_lamps()
	_build_blinks()
	_find_glowing()
	factor = target_factor()

func is_lit(site: String) -> bool:
	return content.state.flag("lit_" + site)

## How bright the town lamps should be: full outside the story and after it.
func target_factor() -> float:
	var data: Dictionary = content.state.data
	if data.mode != "story" or not data.started or content.director.main_done():return 1.0
	var share := 0.0
	for site in SITES:share += float(SITES[site].weight) if is_lit(site) else 0.0
	return DIM + (1.0 - DIM) * clampf(share, 0, 1)

## The place 小光 flies to for a site.
func point(site: String) -> Vector3:
	var registry = content.registry
	match site:
		"garden":return registry.position_of("garden") + Vector3(-.6, .6, 1.2)
		"treehouse":return Vector3(0, 2.8, -.2)
		"lamps":return registry.position_of("spawn") + Vector3(0, 3.2, 0)
		"oven":return _door_point("baker", .0, .9, 1.0)
		"child":return _door_lamps["child"][1] if _door_lamps.has("child") else _door_point("child", .75, .35, .75)
		"fountain":return registry.position_of("fountain") + Vector3(0, 1.4, 0)
		"grandma":return _door_lamps["grandma"][1] if _door_lamps.has("grandma") else _door_point("grandma", .75, .35, .75)
		"lighthouse":return registry.position_of("keeper_lamp") + Vector3(0, 1.2, 0)
		"ship":
			var ship = content.airship
			if ship and ship.rig:
				for part: MeshInstance3D in ship.rig.find_children("Airship_balloon*", "MeshInstance3D", true, false):
					return (part.global_transform * part.get_aabb()).get_center()
			return registry.position_of("dock") + Vector3(-6, 4, 2)
	return world.player.global_position + Vector3.UP * 2.0

## A point by a door: `side` door-widths toward the latch... beside the frame, `up` above
## the door's middle, `out` in front of it.
func _door_point(door: String, side: float, up: float, out: float) -> Vector3:
	var props = content.props
	if not props.doors.has(door):return world.player.global_position + Vector3.UP * 2.0
	var d: Dictionary = props.doors[door]
	var centre: Vector3 = props._v(d.info.centre)
	var front: Vector3 = d.front
	var across := front.cross(Vector3.UP).normalized()
	return centre + across * (float(d.info.width) / 2.0 + .45) * side + Vector3.UP * up + front * out

# ------------------------------------------------------------------ the moment
## Staged: hands up, 小光 flies over, the place lights, 小光 comes back. Awaitable.
func perform(site: String) -> void:
	if is_lit(site) or not SITES.has(site):return
	var at := point(site)
	var perf = world.get("performance")
	var player: CharacterBody3D = world.player
	var reach := Vector2(at.x - player.global_position.x, at.z - player.global_position.z).length()
	if perf and perf.begin("light", at, {"distance": clampf(reach * 1.4 + 3.0, 5.5, 10.0), "height": 2.6, "look_height": 1.1, "mix": .5}):
		await perf.turn_to(Vector3(at.x, player.global_position.y, at.z))
		perf.set_pose("hold_up", 4.0)
		await perf.wait(.5)
		content.xiaoguang.light_up(at, 1.7)
		await perf.wait(.95)
		light(site, true)
		await perf.wait(1.7)
		if site == "grandma":await signal_shot(perf)
		perf.set_pose("admire", 4.0)
		await perf.wait(1.0)
		await perf.finish(.8)
	else:
		light(site, true)
	content.ui.toast("★ 小光点亮了%s" % SITES[site].label, 4.0)

## Marks the site lit and shows it; the story reads the flag "lit_<site>".
func light(site: String, animate: bool) -> void:
	if is_lit(site):return
	content.state.set_flag("lit_" + site)
	_show(site, animate)
	if animate:
		content.props._sparkle(point(site))
		_burst(point(site))
		content.xiaoguang.react("happy")
		if world.get("audio"):world.audio.play_sfx("objective")
		if site == "lamps":
			_wave_origin = point(site)
			_wave_clock = 0.0
			_wave_from = factor
	content.events.emit("lit", {"place": site})
	if site == "lighthouse":content.events.emit("lighthouse_lit", {"place": "keeper_lamp"})
	content.state.save()
	content.director.evaluate()

func _show(site: String, animate: bool) -> void:
	if _built.has(site):return
	_built[site] = true
	match site:
		"garden":
			content.state.set_flag("reaction_garden_glow")
			content._apply_reactions()
		"treehouse":content.props.light_window(animate)
		"oven":
			_glow_at(point(site) + Vector3.DOWN * .4, Color("ff9a4a"), 2.4, 4.5, animate, true)
			_porch_light("baker", animate)
		"child":
			_light_door_lamp("child", Color("ffe3a8"), animate)
			_porch_light("child", animate)
		"grandma":
			_light_door_lamp("grandma", Color("ffd58a"), animate)
			_porch_light("grandma", animate)
		"lamps":_porch_light("lamplighter", animate)
		"fountain":
			_glow_at(point(site), Color(.72, .9, 1.0), 2.6, 7.5, animate, false)
			_motes_at(point(site) + Vector3.DOWN * .6, Color(.8, .95, 1.0))
		"ship":
			content.airship.light_lamp(animate)
			_balloon_glow(animate)
		"lighthouse":content.props.light_lighthouse(animate)

func _glow_at(at: Vector3, color: Color, energy: float, reach: float, animate: bool, flicker: bool) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = reach
	light.light_energy = 0.0 if animate else energy
	if flicker:light.set_meta("flicker", energy)
	add_child(light)
	light.global_position = at
	if animate:create_tween().tween_property(light, "light_energy", energy, 1.4)
	return light

## The moment a place lights: a ball of light swells and fades, with a bright flash.
func _burst(at: Vector3) -> void:
	var ball := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	ball.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1, .85, .55, .7)
	ball.material_override = m
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)
	ball.global_position = at
	ball.scale = Vector3.ONE * .2
	var flash := OmniLight3D.new()
	flash.light_color = Color(1, .85, .55)
	flash.light_energy = 7.0
	flash.omni_range = 9.0
	add_child(flash)
	flash.global_position = at
	var t := create_tween().set_parallel(true)
	t.tween_property(ball, "scale", Vector3.ONE * 2.6, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(m, "albedo_color:a", 0.0, 1.1)
	t.tween_property(flash, "light_energy", 0.0, 1.4)
	t.chain().tween_callback(func():
		ball.queue_free()
		flash.queue_free())

## A warm light on the doorstep of a house that has been lit: the house itself glows.
func _porch_light(door: String, animate: bool) -> void:
	var props = content.props
	if not props.doors.has(door):return
	var d: Dictionary = props.doors[door]
	var c: Vector3 = props._v(d.info.centre)
	_glow_at(c + d.front * .9 + Vector3.UP * .5, Color(1, .8, .55), 2.2, 6.5, animate, false)

## Lamp posts (the hanging-lantern post model) by the child's and grandma's doors, there
## from the start with the lantern dark: 小光 lights the lantern itself.
var _door_lamps := {}            # door -> [post, lantern point, glow mesh]

func _build_door_lamps() -> void:
	var props = content.props
	for door in ["child", "grandma"]:
		if not props.doors.has(door):continue
		var post: Node3D = props.prop("lamp_post", 1.7)
		if post == null:continue
		var d: Dictionary = props.doors[door]
		var c: Vector3 = props._v(d.info.centre)
		var front: Vector3 = d.front
		var across := front.cross(Vector3.UP).normalized()
		var floor := c - Vector3.UP * float(d.info.height) / 2.0
		add_child(post)
		# against the wall beside the door, out of the way of anyone walking past
		post.global_position = props._ground(floor + across * (float(d.info.width) / 2.0 + .5) + front * .22)
		# the arm (the model's +X) reaches toward the door
		post.rotation.y = atan2(across.z, -across.x)
		var spot := lantern_spot(post)
		var glow := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = .09
		ball.height = .18
		glow.mesh = ball
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(.45, .38, .3)
		glow.material_override = m
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(glow)
		glow.global_position = spot
		# the post is solid
		var solid := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = .12
		cyl.height = 1.6
		shape.shape = cyl
		shape.position.y = .8
		solid.add_child(shape)
		post.add_child(solid)
		_door_lamps[door] = [post, spot, glow]

## Where the lantern hangs on a lamp-post model: the end of its arm, a little below the
## top (measured from the model's own bounds, so any size or turn works).
static func lantern_spot(model: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = model.global_transform.affine_inverse() * (mesh.global_transform * mesh.get_aabb())
		box = b if first else box.merge(b)
		first = false
	var local := Vector3(box.end.x - box.size.x * .13, box.position.y + box.size.y * .46, box.get_center().z)
	return model.global_transform * local

func _light_door_lamp(door: String, color: Color, animate: bool) -> void:
	if not _door_lamps.has(door):
		_lantern_at(_door_point(door, .75, .35, .75), color, animate)
		return
	var glow: MeshInstance3D = _door_lamps[door][2]
	var m: StandardMaterial3D = glow.material_override
	m.albedo_color = color
	m.emission_enabled = true
	glow.scale = Vector3.ONE * (.3 if animate else 1.0)
	if animate:create_tween().tween_property(glow, "scale", Vector3.ONE, .7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_glow_at(_door_lamps[door][1], color, 2.0, 5.5, animate, false)

## A paper lantern hung by a window, glowing.
func _lantern_at(at: Vector3, color: Color, animate: bool) -> void:
	var lantern: Node3D = world.performance.paper_lantern() if world.get("performance") else Node3D.new()
	add_child(lantern)
	lantern.global_position = at + Vector3.DOWN * .25
	lantern.scale = Vector3.ONE * 1.4
	_glow_at(at, color, 1.8, 5.0, animate, false)
	if animate:
		lantern.scale = Vector3.ONE * .05
		create_tween().tween_property(lantern, "scale", Vector3.ONE * 1.4, .8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## A slow ring of glowing motes (the fountain).
func _motes_at(at: Vector3, color: Color) -> void:
	var motes := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := SphereMesh.new()
	mesh.radius = .05
	mesh.height = .1
	mesh.radial_segments = 6
	mesh.rings = 3
	mm.mesh = mesh
	mm.instance_count = 18
	motes.multimesh = mm
	motes.custom_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 5, 8))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	motes.material_override = m
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(motes)
	motes.global_position = at
	motes.set_meta("ring", true)

## The airship's balloon lit from inside: its skin glows warm.
func _balloon_glow(animate: bool) -> void:
	var ship = content.airship
	if not ship or not ship.rig:return
	for part: MeshInstance3D in ship.rig.find_children("Airship_balloon*", "MeshInstance3D", true, false):
		for i in part.get_surface_override_material_count():
			var base := part.get_active_material(i)
			var m: StandardMaterial3D = base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
			m.emission_enabled = true
			m.emission = Color(1, .8, .5)
			m.emission_energy_multiplier = 0.0 if animate else .55
			part.set_surface_override_material(i, m)
			if animate:create_tween().tween_property(m, "emission_energy_multiplier", .55, 2.0)
		var inside := OmniLight3D.new()
		inside.light_color = Color(1, .82, .55)
		inside.omni_range = 7.0
		inside.light_energy = 1.4
		part.add_child(inside)
		inside.position = part.get_aabb().get_center() + Vector3.DOWN * part.get_aabb().size.y * .55

func _find_glowing() -> void:
	for mesh: MeshInstance3D in world.find_children("*", "MeshInstance3D", true, false):
		var name := String(mesh.name)
		if not GLOWING.any(func(prefix):return name.begins_with(prefix)):continue
		for i in mesh.get_surface_override_material_count():
			var base := mesh.get_active_material(i)
			if not base is StandardMaterial3D or not (base as StandardMaterial3D).emission_enabled:continue
			var own: StandardMaterial3D = base.duplicate()
			mesh.set_surface_override_material(i, own)
			_glowing.append([own, own.emission_energy_multiplier, own.albedo_color])

# ------------------------------------------------------------------ the two blinking lights
func _build_blinks() -> void:
	var keeper: Dictionary = world.meta.get("keeper_isle", {})
	var far := Vector3(keeper.window_view[0], keeper.window_view[1], keeper.window_view[2]) if keeper.has("window_view") else Vector3(45.8, 15.5, 24.4)
	# 老星's little lamp shines from the top of the tower: high enough to be seen over the
	# town from the seat on the north-west islet
	if content.registry.has("keeper_lamp"):far = content.registry.position_of("keeper_lamp") + Vector3.UP * 2.0
	# a soft round glint that always faces the camera; the far one is big enough to read
	# from the seat across the town (about a hundred metres)
	var glint := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, .95, .8, 1))
	g.set_color(1, Color(1, .8, .5, 0))
	g.add_point(.25, Color(1, .88, .62, .85))
	glint.gradient = g
	glint.fill = GradientTexture2D.FILL_RADIAL
	glint.fill_from = Vector2(.5, .5)
	glint.fill_to = Vector2(1, .5)
	glint.width = 128
	glint.height = 128
	for spec in [[far, 5.0], [point("grandma"), .9]]:
		var dot := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * 2.0
		dot.mesh = quad
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.albedo_texture = glint
		m.albedo_color = Color(1, .9, .7, 0)
		m.no_depth_test = false
		dot.material_override = m
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.scale = Vector3.ONE * float(spec[1])
		dot.extra_cull_margin = 64
		add_child(dot)
		dot.global_position = spec[0]
		_blinks.append(dot)

## The answer across the clouds, staged (after grandma's lamp is lit): the camera turns
## to the lighthouse island and its light blinks three times, slowly, clearly.
var _signal := -1.0

func signal_shot(perf) -> void:
	var keeper_lamp: Vector3 = content.registry.position_of("keeper_lamp") if content.registry.has("keeper_lamp") else _blinks[0].global_position
	_blinks[0].global_position = keeper_lamp + Vector3.UP * 1.0
	var player: Vector3 = world.player.global_position
	var toward := keeper_lamp - player
	var flat := Vector3(toward.x, 0, toward.z).normalized()
	var eye := player - flat * 3.0 + Vector3.UP * 2.2 + flat.cross(Vector3.UP) * 1.2
	perf.glide_to(Transform3D(Basis.looking_at(keeper_lamp - eye), eye), 38.0, 1.6)
	await perf.wait(1.8)
	_signal = 0.0
	await perf.wait(4.6)
	_signal = -1.0

## Three blinks every seven seconds## Three blinks every seven seconds; the lighthouse island answers half a beat later.
func _blink_level(t: float) -> float:
	var phase := fmod(t, 7.0)
	if phase > 2.1:return 0.0
	return 1.0 if fmod(phase, .7) < .4 else 0.0

func _process(delta: float) -> void:
	_clock += delta
	# the town lamps follow what has been lit; the street lamps come on as a wave
	var goal := target_factor()
	factor = move_toward(factor, goal, delta * .35)
	if _wave_clock >= 0:_wave_clock += delta
	for lamp in get_tree().get_nodes_in_group("town_lamps"):
		var f := factor
		if _wave_clock >= 0 and (lamp as Node3D).global_position.distance_to(_wave_origin) > _wave_clock * WAVE_SPEED:f = _wave_from
		lamp.light_energy = float(lamp.get_meta("base_energy", 1.0)) * f * boost
	if _wave_clock > 12.0:_wave_clock = -1.0
	for entry in _glowing:
		entry[0].emission_energy_multiplier = float(entry[1]) * factor * boost
		# pale glass reads as lit even without glow: darken it too while the island is dim
		var base: Color = entry[2]
		entry[0].albedo_color = Color(base.r * (.3 + .7 * factor), base.g * (.3 + .7 * factor), base.b * (.3 + .7 * factor), base.a)
	for child in get_children():
		if child is OmniLight3D and child.has_meta("flicker"):
			child.light_energy = float(child.get_meta("flicker")) * (.85 + .15 * sin(_clock * 9.0) * sin(_clock * 3.7))
		elif child is MultiMeshInstance3D and child.has_meta("ring"):
			for i in child.multimesh.instance_count:
				var a: float = float(i) * TAU / child.multimesh.instance_count + _clock * .4
				child.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(cos(a) * 2.2, .3 + sin(_clock * 1.3 + i) * .35, sin(a) * 2.2)))
	# the old signal between grandma and 老星, at dusk and night, until their lamps are lit
	var cycle = world.get("day_cycle")
	var dark: float = (cycle.weights.y * .8 + cycle.weights.z) if cycle else 1.0
	if _blinks.size() == 2:
		var player: Vector3 = world.player.global_position
		var keeper_on: bool = not content.state.flag("reaction_lighthouse_lit") and player.distance_to(_blinks[0].global_position) > 30.0
		var grandma_on: bool = not is_lit("grandma")
		_blinks[0].material_override.albedo_color.a = (_blink_level(_clock - .35) * dark * .95) if keeper_on else 0.0
		if _signal >= 0:
			_signal += delta
			_blinks[0].material_override.albedo_color.a = 1.0 if fmod(_signal, 1.3) < .65 and _signal < 3.9 else 0.0
		_blinks[1].material_override.albedo_color.a = (_blink_level(_clock) * dark * .9) if grandma_on else 0.0
