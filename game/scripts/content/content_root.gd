extends Node
## Story, guide, map and settings for 星星人的小世界 (CONTENT-01).
## main.gd adds this after interactions/day_cycle/activities. Everything here
## reads the scene through location_registry and content_events, never through
## fixed chair/door/telescope coordinates.
const Registry := preload("res://scripts/content/location_registry.gd")
const Events := preload("res://scripts/content/content_events.gd")
const StoryState := preload("res://scripts/content/story_state.gd")
const Director := preload("res://scripts/content/story_director.gd")
const WalkGrid := preload("res://scripts/content/walk_grid.gd")
const Guide := preload("res://scripts/content/guide.gd")
const ContentUI := preload("res://scripts/content/content_ui.gd")
const ExamineBook := preload("res://scripts/content/examine_book.gd")
const WorldProps := preload("res://scripts/content/world_props.gd")
const Xiaoguang := preload("res://scripts/content/xiaoguang.gd")
const Airship := preload("res://scripts/content/airship.gd")
const Ending := preload("res://scripts/content/ending.gd")
const Opening := preload("res://scripts/content/opening.gd")
const NpcCast := preload("res://scripts/content/npc_cast.gd")
const IslandLights := preload("res://scripts/content/island_lights.gd")

var world: Node3D
var registry
var events
var state
var director
var grid
var guide
var ui
var examine_target := ""
var examine_entry: Dictionary = {}
var examines
var props
var xiaoguang
var airship
var ending
var opening
var npcs
var lights
var test_session := "--test-session" in OS.get_cmdline_user_args()
var reactions: Dictionary = {}

func _ready() -> void:
	name = "Content"
	registry = Registry.new()
	registry.setup(world)
	events = Events.new()
	add_child(events)
	events.setup(world)
	state = StoryState.new()
	state.persistent = not test_session
	state.load_state()
	director = Director.new()
	add_child(director)
	director.setup(world, registry, events, state)
	grid = WalkGrid.new()
	guide = Guide.new()
	guide.content = self
	add_child(guide)
	ui = ContentUI.new()
	ui.content = self
	add_child(ui)
	examines = ExamineBook.new()
	examines.setup(self)
	props = WorldProps.new()
	props.content = self
	add_child(props)
	xiaoguang = Xiaoguang.new()
	xiaoguang.content = self
	add_child(xiaoguang)
	airship = Airship.new()
	airship.content = self
	add_child(airship)
	ending = Ending.new()
	ending.content = self
	add_child(ending)
	opening = Opening.new()
	opening.content = self
	add_child(opening)
	npcs = NpcCast.new()
	npcs.content = self
	add_child(npcs)
	lights = IslandLights.new()
	lights.content = self
	add_child(lights)
	director.stage_started.connect(_on_stage_started)
	var talk = world.get("interactions")
	if talk and talk.has_signal("dialogue_finished"):talk.dialogue_finished.connect(_on_dialogue_finished)
	director.chapter_completed.connect(func(_title, _outro):_apply_reactions())
	events.content_event.connect(_on_event)
	if world.get("audio"):world.audio.bind_scene()
	_apply_reactions()
	world.player.respawn_hook = _respawn_point
	_bake.call_deferred()

func player_name() -> String:
	var name := String(state.data.get("player_name", "")).strip_edges()
	return name if not name.is_empty() else "星仔"

## Story text may say {name}; it becomes the player's name.
func named(text: String) -> String:
	return text.replace("{name}", player_name())

func _bake() -> void:
	# Collision shapes exist after the first physics frames
	for i in 3:await get_tree().physics_frame
	registry.refresh()
	var ignore: Array[RID] = [world.player.get_rid()]
	for npc in world.interactions.npcs:ignore.append(npc.get_rid())
	if OS.has_feature("web"):world._web_boot_mark("grid_begin")
	var used_cache: bool=OS.has_feature("web") and grid.load_web_cache("res://data/content/walk_grid_web.bin")
	if not used_cache:
		grid.bake(world.get_world_3d().direct_space_state, ignore)
	if OS.has_feature("web"):
		world._web_boot_mark("grid_done")
		JavaScriptBridge.eval("window.starworldGridCacheHit = "+("true" if used_cache else "false"))
	director.evaluate()
	guide.refresh_route(true)
	ui.refresh()
	if OS.has_feature("web"):
		await world.performance.prepare_web_props()
		JavaScriptBridge.eval("window.starworldSceneReady = true")

## Where a fall lands: on the lighthouse island's pier while the ship is moored there (so
## the ship is always within reach), otherwise the square.
func _respawn_point() -> Vector3:
	var player: CharacterBody3D = world.player
	var keeper: Vector3 = registry.position_of("keeper_isle") if registry.has("keeper_isle") else Vector3(45, 14, 27)
	var fell_near_keeper: bool = Vector2(player.global_position.x - keeper.x, player.global_position.z - keeper.z).length() < 30.0
	if airship and airship.at == "keeper_isle" and fell_near_keeper:
		return registry.position_of("keeper_dock") + Vector3.UP * .3
	return world.player.spawn_point

## Uses a fresh story save at `path` (tests, or a second profile). Never touches the real save.
func use_save(path: String) -> void:
	state.path = path
	state.persistent = true
	state.load_state()
	director.evaluate()
	_apply_reactions()
	ui.refresh()

# ------------------------------------------------------------------ dialogue bridge
## town_interactions asks this for lines instead of its old hard-coded ones.
func dialogue_for(npc: String) -> Dictionary:
	return director.dialogue_for(npc)

func _on_dialogue_finished(npc: String) -> void:
	var info: Dictionary = director.dialogue_finished(npc)
	events.emit("npc_talked", {"npc": npc, "quest": info.get("quest", "")})

func _on_event(id: String, data: Dictionary) -> void:
	if id == "time_settled" or id == "seat_settled":ui.refresh()
	if id == "fireflies_called" and data.get("sky", -1) == 2:_maybe_lead_fireflies.call_deferred()


func _on_stage_started(_quest: String, stage: Dictionary) -> void:
	if String(stage.get("whisper", "")) != "":ui.whisper(String(stage.whisper))

## Named sequences examines and stages can start.
func special(id: String, entry: Dictionary, _variant: Dictionary) -> void:
	if id.begins_with("light:"):
		await lights.perform(id.substr(6))
		return
	match id:
		"find_xiaoguang":xiaoguang.found()
		"polish_window":props.light_window()
		"airship_board":airship.board()
		"airship_recall":airship.recall()
		"ship_lamp":airship.light_lamp()
		"light_lighthouse":props.light_lighthouse()
		"ending":ending.play()
		"door":props.open_door(String(entry.get("door", "")))
		"firefly_spring":props.firefly_spring_glow()
		"climb_tower":_teleport(registry.position_of("keeper_lamp"), "keeper_lamp")
		"descend_tower":_teleport(registry.position_of("keeper_tower"), "keeper_tower")
		"ring_bell":props.ring_bell()
		"light_small_lamp":props.light_keepsake_lamp()

## A short warm fade, used for stairs inside the lighthouse.
func _teleport(to: Vector3, face_toward: String) -> void:
	var player: CharacterBody3D = world.player
	player.controls_locked = true
	await ui.fade(true, .5)
	player.global_position = to + Vector3.UP * .15
	player.velocity = Vector3.ZERO
	var look: Vector3 = registry.position_of("keeper_isle") if face_toward == "keeper_tower" else registry.position_of("dock")
	player.cam_yaw = atan2(-(look.x - to.x), -(look.z - to.z))
	await get_tree().physics_frame
	await ui.fade(false, .6)
	player.controls_locked = false

## Fireflies called at night during "萤火虫的夜路" lead the way to the little spring.
func _maybe_lead_fireflies() -> void:
	var stage: String = director.side_stage("s_firefly").get("id", "") if director.side_state("s_firefly") == "active" else ""
	if not stage in ["s_firefly_call", "s_firefly_follow"]:return
	var swarm = world.activities.swarm
	var route: PackedVector3Array = grid.path(world.player.global_position, registry.position_of("firefly_spring"))
	if route.size() > 2:swarm.lead(route, func():
		props.firefly_spring_glow()
		events.emit("firefly_path_done", {"place": "isle_south_l"}))

# ------------------------------------------------------------------ examine points
func _process(_delta: float) -> void:
	if not is_instance_valid(world.player):return
	var p: Vector3 = world.player.global_position
	for id in registry.ids():
		if id in state.data.discovered:continue
		if p.distance_to(registry.position_of(id)) < registry.radius_of(id) * 1.5:
			state.data.discovered.append(id)
			if state.claim("found:" + id):
				state.add_log("发现 · " + registry.name_of(id))
				ui.toast("发现：" + registry.name_of(id))
			state.save()
			director.evaluate()
	examine_target = ""
	examine_entry = {}
	if world.interactions.mode != "idle" or world.interactions.active_target != "":return
	if airship.flying():return
	examine_entry = examines.nearest(p)
	if not examine_entry.is_empty():examine_target = String(examine_entry.id)

## True when an examine marked "first" is in reach: it goes before talking to someone.
func priority_examine(p: Vector3) -> bool:
	var entry: Dictionary = examines.nearest(p)
	return not entry.is_empty() and bool(entry.get("first", false))

## Uses the examine the player stands at (E or the prompt button).
func examine(id: String) -> bool:
	if examine_entry.is_empty() or String(examine_entry.id) != id:return false
	examines.use(examine_entry)
	return true

# ------------------------------------------------------------------ world reactions
func _apply_reactions() -> void:
	if state.flag("reaction_garden_glow") and not reactions.has("garden_glow"):
		reactions["garden_glow"] = _garden_glow()
	if state.flag("reaction_player_star") and not reactions.has("player_star"):
		reactions["player_star"] = _player_star()

## Warm light and a few slow motes over the player's flowers; brighter at dusk and night.
func _garden_glow() -> Node3D:
	var root := Node3D.new()
	root.name = "ContentGardenGlow"
	world.add_child(root)
	root.global_position = registry.position_of("garden") + Vector3(-.6, .9, 1.7)
	var light := OmniLight3D.new()
	light.light_color = Color("ffd9a0")
	light.omni_range = 4.5
	light.light_energy = 0
	root.add_child(light)
	root.set_meta("light", light)
	var motes := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := SphereMesh.new()
	mesh.radius = .035
	mesh.height = .07
	mesh.radial_segments = 6
	mesh.rings = 3
	mm.mesh = mesh
	mm.instance_count = 14
	motes.multimesh = mm
	motes.custom_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 4, 6))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, .88, .6, 0)
	motes.material_override = material
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(motes)
	root.set_meta("motes", motes)
	return root

## The ending's payoff should read at a glance: the sky version is drawn larger than the chart.
const HOME_SPREAD := 2.2

## 归家座 in the real night sky, at infinity (follows the camera), with 小光 as the
## roof star once it has gone home. Same direction and shape as the telescope chart.
func _player_star() -> Node3D:
	var root := Node3D.new()
	root.name = "ContentHomeConstellation"
	world.add_child(root)
	var talk = world.get("interactions")
	var entry: Dictionary = talk.constellations[2] if talk and talk.constellations.size() > 2 else {"direction": Vector3(.77, .58, .22).normalized(), "points": [Vector2(-.045, -.045), Vector2(-.045, .01), Vector2(0, .06), Vector2(.045, .01), Vector2(.045, -.045), Vector2(-.045, -.045)], "missing": 2}
	var direction: Vector3 = entry.direction
	var right := direction.cross(Vector3.UP).normalized()
	var up := right.cross(direction).normalized()
	var points: Array[Vector3] = []
	for p: Vector2 in entry.points:points.append((direction + (right * p.x + up * p.y) * HOME_SPREAD).normalized() * 450.0)
	var stars := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 4
	mm.mesh = mesh
	mm.instance_count = points.size()
	var apex := int(entry.get("missing", 2))
	for i in points.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (7.0 if i == apex else 4.2)), points[i]))
	stars.multimesh = mm
	var lines := MeshInstance3D.new()
	var strip := ImmediateMesh.new()
	strip.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in points:strip.surface_add_vertex(p)
	strip.surface_end()
	lines.mesh = strip
	for node in [stars, lines]:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1, .9, .66, 0)
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.extra_cull_margin = 16384
		root.add_child(node)
	root.set_meta("parts", [stars, lines])
	root.set_meta("apex", points[apex])
	return root

## Where 小光 flies to at the end: the roof of 归家座, seen from `from`.
func home_star_point(from: Vector3) -> Vector3:
	var talk = world.get("interactions")
	var direction: Vector3 = talk.constellations[2].direction if talk and talk.constellations.size() > 2 else Vector3(.77, .58, .22).normalized()
	var right := direction.cross(Vector3.UP).normalized()
	var up := right.cross(direction).normalized()
	return from + (direction + up * .06 * HOME_SPREAD).normalized() * 140.0

func _physics_process(_delta: float) -> void:
	var cycle = world.get("day_cycle")
	if not cycle:return
	var w: Vector3 = cycle.weights
	var glow := w.y * .7 + w.z
	if reactions.has("garden_glow"):
		var light: OmniLight3D = reactions.garden_glow.get_meta("light")
		light.light_energy = .2 + 1.6 * glow
		var motes: MultiMeshInstance3D = reactions.garden_glow.get_meta("motes")
		motes.material_override.albedo_color.a = clampf(glow, 0, .9)
		var t := Time.get_ticks_msec() / 1000.0
		for i in motes.multimesh.instance_count:
			var a := float(i) * 2.399 + t * .15
			motes.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(cos(a) * (.6 + float(i % 4) * .35), -.4 + float(i % 5) * .22 + sin(t * .7 + i) * .12, sin(a) * (.5 + float(i % 3) * .4))))
	if reactions.has("player_star"):
		var camera := world.get_viewport().get_camera_3d()
		if camera:reactions.player_star.global_position = camera.global_position
		var t := Time.get_ticks_msec() / 1000.0
		for part in reactions.player_star.get_meta("parts"):
			part.material_override.albedo_color.a = clampf(w.z * 1.1 - .1, 0, 1) * ((.55 + .1 * sin(t * 1.7)) if part is MeshInstance3D else 1.0)

func capabilities() -> Dictionary:
	return {
		"seat_event": events.seat_mode,
		"hand_lantern": events.lantern_mode,
		"walk_grid": grid.ready,
		"walk_grid_ms": grid.bake_ms,
		"locations": registry.report(),
	}
