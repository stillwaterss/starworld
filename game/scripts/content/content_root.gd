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
	_tower_walls()
	_bake.call_deferred()

## v29: the lighthouse gallery had no wall round the lamp room (you could walk into it,
## and the camera with you) and gaps in the rail (your face went through it). A cylinder
## for the lamp room (layer 1: the camera keeps out too) and a ring of thin boxes along the
## rail (layer 2: only you bump into it; the camera may look over it).
func _tower_walls() -> void:
	var keeper: Dictionary = world.meta.get("keeper_isle", {})
	if not keeper.has("lamp"):return
	var lamp := Vector3(keeper.lamp[0], keeper.lamp[1], keeper.lamp[2])
	var floor_y: float = float(keeper.gallery[1]) if keeper.has("gallery") else lamp.y - .65
	var room := StaticBody3D.new()
	room.name = "LampRoomWall"
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.22
	cyl.height = 2.6
	shape.shape = cyl
	room.add_child(shape)
	add_child(room)
	room.global_position = Vector3(lamp.x, floor_y + 1.3, lamp.z)
	var rail := StaticBody3D.new()
	rail.name = "GalleryRail"
	rail.collision_layer = 2
	rail.collision_mask = 0
	var count := 24
	for k in count:
		var a := k * TAU / count
		var seg := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.0 * PI * 2.16 / count + .06, 1.1, .1)
		seg.shape = box
		seg.position = Vector3(cos(a) * 2.16, .55, sin(a) * 2.16)
		seg.rotation.y = -a + PI / 2
		rail.add_child(seg)
	add_child(rail)
	rail.global_position = Vector3(lamp.x, floor_y, lamp.z)
	_gallery = Vector3(lamp.x, floor_y, lamp.z)

## v30: on the gallery the follow camera keeps to the outside (the lamp room's wall would
## push it into your face): it may swing at most 80° from straight out; past that it is
## eased back round. Outward of the walkway, nothing is between you and it.
var _gallery := Vector3.INF

func _gallery_camera(delta: float) -> void:
	if _gallery == Vector3.INF:return
	var player: CharacterBody3D = world.player
	if player.controls_locked:return
	var rel := player.global_position - _gallery
	if absf(rel.y) > 1.6 or Vector2(rel.x, rel.z).length() > 2.5:return
	var out := Vector3(rel.x, 0, rel.z).normalized()
	var back := Vector3(sin(player.cam_yaw), 0, cos(player.cam_yaw))
	var angle := out.signed_angle_to(back, Vector3.UP)
	var limit := deg_to_rad(80.0)
	if absf(angle) <= limit:return
	var goal := out.rotated(Vector3.UP, signf(angle) * limit)
	player.cam_yaw = lerp_angle(player.cam_yaw, atan2(goal.x, goal.z), clampf(delta * 8.0, 0, 1))

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

## Chapters two and four begin the next morning: the sky turns to day by itself and stays
## there through their first stages (chapter index -> the last stage of the morning), so
## the daytime music and island get a real stretch of play. Dusk comes when a stage asks.
const MORNINGS := {1: 3, 3: 1}

func morning(fade: bool) -> void:
	var data: Dictionary = state.data
	if data.mode != "story" or director.main_done():return
	var chapter := int(data.main.chapter)
	if not MORNINGS.has(chapter) or int(data.main.stage) > int(MORNINGS[chapter]):return
	var cycle = world.get("day_cycle")
	if cycle == null or cycle.current == 0:return
	cycle.set_time(0, 5.0 if fade else 0.0)
	if fade:ui.toast("天亮了。新的一天。", 4.0)

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
	if String(stage.get("id", "")) == "s_lamp_back":_hand_lamp(true)

# ------------------------------------------------------------------ v25: 老星 and the chair
var _chair_props: Node3D
var _visitors: Array[Node3D] = []
var _visit_clock := 0.0

func _slot(id: String) -> Dictionary:
	for slot in npcs.SLOTS:
		if String(slot.id) == id:return slot
	return {}

## A model of a resident at `at`, looking toward `look` (for staged moments). `seat`: the
## height of a seat to sit on (the short legs go down into it), or NAN to stand.
func _figure(id: String, at: Vector3, look: Vector3, seat := NAN) -> Node3D:
	var body: Node3D = npcs._model(_slot(id))
	if body == null:return null
	var root := Node3D.new()
	root.add_child(body)
	world.add_child(root)
	root.global_position = Vector3(at.x, seat - .2, at.z) if not is_nan(seat) else props._ground(at, 1.5)
	var d := look - root.global_position
	root.rotation.y = atan2(-d.x, -d.z)
	return root

## 绵绵 widened his grandfather's chair: a plank on the side, two cushions (blue for 老星,
## purple for grandma).
func widen_chair(animate: bool) -> void:
	state.set_flag("chair_widened")
	if is_instance_valid(_chair_props):return
	var scene = world.scene_actions
	var seat: Vector3 = scene._seat_point()
	var facing: Vector3 = scene.FACING
	var side := Vector3(-facing.z, 0, facing.x)
	_chair_props = Node3D.new()
	_chair_props.name = "WidenedChair"
	add_child(_chair_props)
	var turn := atan2(facing.x, facing.z)
	var parts := [
		[Vector3(.66, .07, .5), seat + side * .62 + Vector3.DOWN * .045, Color("a77a52")],
		[Vector3(.07, .42, .07), seat + side * .9 + facing * .18 + Vector3.DOWN * .29, Color("8a6040")],
		[Vector3(.07, .42, .07), seat + side * .9 - facing * .18 + Vector3.DOWN * .29, Color("8a6040")],
		[Vector3(.44, .07, .4), seat + side * .62 + Vector3.UP * .02, Color("b79be0")],
		[Vector3(.44, .07, .4), seat + Vector3.UP * .02, Color("6f86c9")],
	]
	for p in parts:
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = p[0]
		piece.mesh = box
		var m := StandardMaterial3D.new()
		m.albedo_color = p[2]
		m.roughness = .85
		piece.material_override = m
		_chair_props.add_child(piece)
		piece.global_position = p[1]
		piece.rotation.y = turn
		if animate:
			piece.scale = Vector3.ONE * .05
			create_tween().tween_property(piece, "scale", Vector3.ONE, .8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	state.save()

# ------------------------------------------------------------------ v26: 老星 comes down for one evening
## Where 老星 and grandma are during 「今晚我来守灯」: he leaves the lighthouse (his figure
## there is hidden), walks behind you in town; grandma joins; both sit on the chair until
## the morning after your night on the tower. One place at a time, also after a reload.
var _followers: Array[Node3D] = []
var _staging := false            # a scene is moving them: the upkeep leaves them alone

func _visiting() -> bool:
	return (state.flag("keeper_leaving") or state.flag("keeper_in_town")) and not state.flag("watch_done")

func _ensure_company() -> void:
	if _staging:return
	var visiting := _visiting()
	if npcs.actors.has("keeper"):
		var home: Node3D = npcs.actors["keeper"].node
		if visiting:home.visible = false
		elif bool(npcs.actors["keeper"].shown) and not home.visible:home.visible = true
	if visiting and state.flag("grandma_joined") and npcs.actors.has("grandma"):npcs.actors["grandma"].node.visible = false
	var seated: bool = visiting and state.flag("reunion_seen")
	if seated:
		_drop_followers()
		if _visitors.is_empty():_seat_visitors(false)
		return
	if not visiting:
		for v in _visitors:
			if is_instance_valid(v):v.queue_free()
		_visitors.clear()
		_drop_followers()
		return
	_followers.assign(_followers.filter(func(f): return is_instance_valid(f)))
	if state.flag("keeper_in_town") and _followers.is_empty() and not airship.flying():
		# after a reload: they are just behind you
		var player: CharacterBody3D = world.player
		_trail.clear()
		_trail_len.clear()
		var back: Vector3 = player.model.global_basis.z
		back.y = 0
		back = back.normalized() if back.length() > .01 else Vector3.BACK
		var ids := ["keeper", "grandma"] if state.flag("grandma_joined") else ["keeper"]
		var occupied: Array[Vector3] = [player.global_position]
		for k in ids.size():
			var at := _company_spot(player.global_position, back, occupied, FOLLOW_GAP[k])
			if at == Vector3.INF:break
			var f := _figure(ids[k], at, player.global_position)
			if f:
				f.global_position = at
				_join(f)
				occupied.append(at)

## Find walkable ground around a mark without placing two costumes in the same spot.
func _company_spot(origin: Vector3, facing: Vector3, occupied: Array[Vector3], reach := 1.35) -> Vector3:
	for radius: float in [reach, reach + .45, reach + .9]:
		for turn: float in [0.0, .65, -.65, 1.3, -1.3, 2.0, -2.0, PI]:
			var wanted := origin + facing.rotated(Vector3.UP, turn) * radius
			var slot: int = grid.nearest_slot(wanted, .45, true)
			if slot < 0:continue
			var at: Vector3 = grid.center(slot)
			if absf(at.y - origin.y) > .4 or not _company_clear(at, occupied):continue
			return at + Vector3.UP * .04
	return Vector3.INF

func _company_clear(at: Vector3, occupied: Array[Vector3]) -> bool:
	for other in occupied:
		if absf(at.y - other.y) < 1.15 and Vector2(at.x - other.x, at.z - other.z).length_squared() < 1.1 * 1.1:return false
	return true

func _drop_followers() -> void:
	for f in _followers:
		if is_instance_valid(f):f.queue_free()
	_followers.clear()

func _anim(f, what: String, speed := 1.0) -> void:
	if not is_instance_valid(f) or f.get_child_count() == 0:return
	var body: Node3D = f.get_child(0)
	if body.has_meta("anim"):(body.get_meta("anim") as AnimationPlayer).speed_scale = speed
	if String(f.get_meta("anim_state", "")) == what:return
	f.set_meta("anim_state", what)
	npcs._play(body, what)

## The floor under p (the player is not floor).
func _floor_at(p: Vector3, up := 1.2) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * up, p + Vector3.DOWN * 6.0, 1, [world.player.get_rid()])
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else p

# v27: they walk where you walked. Your steps are kept as a trail (only places you
# really stood or walked: stairs, ladders, the gangway, no roofs and no thin air), and
# each of them walks along it a little way behind you.
var _trail: Array[Vector3] = []
var _trail_len: Array[float] = []      # distance along the trail to each point
const FOLLOW_GAP := [1.45, 2.8]

func _record_trail() -> void:
	var p: Vector3 = world.player.global_position
	if _trail.is_empty():
		_trail.append(p)
		_trail_len.append(0.0)
		return
	var last := _trail[-1]
	var step := p.distance_to(last)
	if step < .2:return
	if step > 3.0:
		# a jump in place (a fade, the airship): the trail starts again here; whoever
		# follows walks over to it
		_trail.clear()
		_trail_len.clear()
		for f in _followers:
			if is_instance_valid(f):f.set_meta("approach", true)
		_trail.append(p)
		_trail_len.append(0.0)
		return
	_trail.append(p)
	_trail_len.append(_trail_len[-1] + step)
	# forget what nobody needs any more
	if _trail.size() > 500:
		var cut := 200
		var gone := _trail_len[cut]
		_trail = _trail.slice(cut)
		_trail_len.assign(_trail_len.slice(cut).map(func(v): return v - gone))
		for f in _followers:
			if is_instance_valid(f):f.set_meta("s", maxf(0.0, float(f.get_meta("s", 0.0)) - gone))

func _trail_at(s: float) -> Vector3:
	if _trail.size() == 1 or s <= 0.0:return _trail[0]
	var hi := _trail_len.bsearch(s)
	if hi >= _trail.size():return _trail[-1]
	var lo := maxi(hi - 1, 0)
	var span := _trail_len[hi] - _trail_len[lo]
	return _trail[lo].lerp(_trail[hi], (s - _trail_len[lo]) / span if span > .0001 else 0.0)

## Someone starts walking with you (from wherever they stand: first over to your trail).
func _join(f: Node3D) -> void:
	f.set_meta("approach", true)
	f.set_meta("s", 0.0)
	_followers.append(f)

func _move_company(delta: float) -> void:
	if airship.flying() or _staging or _followers.is_empty():return
	_record_trail()
	var player: CharacterBody3D = world.player
	var head := _trail_len[-1] + player.global_position.distance_to(_trail[-1])
	for k in _followers.size():
		var f := _followers[k]
		if not is_instance_valid(f):continue
		var gap: float = FOLLOW_GAP[mini(k, FOLLOW_GAP.size() - 1)]
		var goal_s := head - gap
		var from := f.global_position
		var to := from
		var occupied: Array[Vector3] = [player.global_position]
		for other in _followers:
			if is_instance_valid(other) and other != f:occupied.append(other.global_position)
		# Until there is enough trail, keep the actors at their individual marks.
		if goal_s >= 0.0:
			var aim := _trail_at(goal_s)
			if bool(f.get_meta("approach", false)):
				var d := aim - from
				if d.length() < .24:
					f.set_meta("approach", false)
					f.set_meta("s", goal_s)
				elif d.length() > 16.0 and _company_clear(aim, occupied):
					to = aim
					f.set_meta("approach", false)
					f.set_meta("s", goal_s)
				else:
					to = from.move_toward(aim, 3.2 * delta)
			else:
				var progress: float = f.get_meta("s", 0.0)
				var next := minf(goal_s, progress + clampf((goal_s - progress) * 2.2, 1.0, 6.0) * delta)
				if next > progress:
					var point := _trail_at(next)
					if _company_clear(point, occupied):
						to = point
						f.set_meta("s", next)
		if not _company_clear(to, occupied):
			to = from
			# If the player doubles back into a follower, step clear to a nearby
			# walkable mark instead of converging on the same trail point.
			var away := from - player.global_position
			away.y = 0
			if away.length_squared() < .01:away = player.model.global_basis.x
			var spare := _company_spot(from, away.normalized(), occupied, 1.15)
			if spare != Vector3.INF:
				to = from.move_toward(spare, 3.2 * delta)
				f.set_meta("approach", true)
		var moved := to - from
		var flat := Vector2(moved.x, moved.z).length()
		f.global_position = to
		var speed := flat / maxf(delta, .001)
		if speed > .3:
			f.rotation.y = lerp_angle(f.rotation.y, atan2(-moved.x, -moved.z), clampf(delta * 9.0, 0, 1))
			_anim(f, "walk", clampf(speed / 1.25, .75, 1.9))
		else:
			var face := player.global_position - f.global_position
			if Vector2(face.x, face.z).length() > .2:f.rotation.y = lerp_angle(f.rotation.y, atan2(-face.x, -face.z), clampf(delta * 3.0, 0, 1))
			_anim(f, "idle")

## Side by side on the chair, looking out (after the evening, until the night is over).
func _seat_visitors(animate: bool, people: Array = []) -> void:
	var scene = world.scene_actions
	var seat: Vector3 = scene._seat_point()
	var facing: Vector3 = scene.FACING
	var side := Vector3(-facing.z, 0, facing.x)
	var spots := [seat, seat + side * (.62 if state.flag("chair_widened") else .5)]
	var ids := ["keeper", "grandma"]
	for k in 2:
		var f: Node3D = people[k] if k < people.size() and is_instance_valid(people[k]) else _figure(ids[k], spots[k], spots[k] + facing * 10.0)
		if f == null:continue
		var sit := Vector3(spots[k].x, seat.y - .2, spots[k].z)
		if animate:
			_anim(f, "walk")
			var d: Vector3 = sit - f.global_position
			f.rotation.y = atan2(-d.x, -d.z)
			var t := create_tween()
			t.tween_property(f, "global_position", sit + Vector3.UP * .2 - facing * .35, 1.8)
			t.tween_property(f, "rotation:y", atan2(-facing.x, -facing.z), .5)
			t.tween_property(f, "global_position", sit, .5)
			t.tween_callback(func():_anim(f, "idle"))
		else:
			f.global_position = sit
			f.rotation.y = atan2(-facing.x, -facing.z)
		_visitors.append(f)

## A figure walks through `points` in `seconds` (in the frame of `space`, the airship's rig
## while boarding, so it stays on the deck however the ship moves), facing the way it goes.
func _walk_figure(f: Node3D, points: Array, seconds: float) -> void:
	var lengths: Array[float] = []
	var total := 0.0
	for i in points.size() - 1:
		lengths.append((points[i + 1] as Vector3).distance_to(points[i]))
		total += lengths[i]
	if total < .05:return
	_anim(f, "walk", clampf(total / seconds / 1.25, .75, 1.9))
	var t := 0.0
	while t < seconds and is_instance_valid(f):
		t = minf(t + get_process_delta_time(), seconds)
		var along := total * t / seconds
		var i := 0
		while i < lengths.size() - 1 and along > lengths[i]:
			along -= lengths[i]
			i += 1
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		f.position = a.lerp(b, clampf(along / maxf(lengths[i], .001), 0, 1))
		var flat := b - a
		flat.y = 0
		if flat.length() > .05:f.rotation.y = lerp_angle(f.rotation.y, atan2(-flat.x, -flat.z), clampf(get_process_delta_time() * 10.0, 0, 1))
		await get_tree().process_frame
	_anim(f, "idle")

## 「今晚我来守灯」: he walks the pier behind you, up the gangway and onto the deck, stands
## beside you all the way, and walks off behind you at the town's dock.
func _keeper_ride() -> void:
	state.set_flag("keeper_leaving")
	_ensure_company()
	_staging = true
	var player: CharacterBody3D = world.player
	var board_from := player.global_position
	var deck: Vector3 = airship.deck_point()
	var toward := deck - board_from
	toward.y = 0
	toward = toward.normalized()
	var start := _floor_at(board_from - toward * 1.45, .6)
	if absf(start.y - board_from.y) > .4:start = board_from - toward * 1.45
	var fig := _figure("keeper", start, deck)
	if fig:
		var rig: Node3D = airship.rig
		fig.global_position = start
		fig.reparent(rig, true)
	var embark := func(plank: Array) -> void:
		if not is_instance_valid(fig):return
		var rig: Node3D = airship.rig
		var across := toward.cross(Vector3.UP).normalized()
		# A fixed mark in the ship's frame. Rotating the camera cannot move the passenger.
		var berth := deck + across * 1.1 - toward * .15
		await _walk_figure(fig, [fig.position, rig.to_local(plank[1]), rig.to_local(plank[0]), rig.to_local(berth)], 2.35)
		_rider = fig
	var disembark := func(plank: Array, landing: Vector3) -> void:
		if not is_instance_valid(fig):return
		_rider = null
		fig.reparent(world, true)
		var inward: Vector3 = plank[0] - plank[1]
		inward.y = 0
		var mark := _company_spot(landing, inward.normalized(), [player.global_position], 1.6)
		if mark == Vector3.INF:mark = plank[0]
		var path: Array = [fig.global_position, plank[0]]
		if mark != plank[0]:
			if Vector2(landing.x - plank[1].x, landing.z - plank[1].z).length() > 1.15:path.append(plank[1])
			path.append(mark)
		await _walk_figure(fig, path, 1.8)
		_trail.clear()
		_trail_len.clear()
		_join(fig)
	await airship.board(embark, disembark)
	state.set_flag("keeper_in_town")
	_staging = false
	state.save()
	director.evaluate()

var _rider: Node3D

func _update_rider(delta: float) -> void:
	if not is_instance_valid(_rider) or not airship.flying() or not airship.camera.current:return
	var to_cam: Vector3 = airship.camera.global_position - _rider.global_position
	if Vector2(to_cam.x, to_cam.z).length_squared() < .01:return
	var face := atan2(-to_cam.x, -to_cam.z) - .5
	var yaw := lerp_angle(_rider.global_rotation.y, face, clampf(delta * 3.0, 0, 1))
	_rider.global_rotation = Vector3(0, yaw, 0)

## Grandma comes out and comes along (her figure at the door stays hidden meanwhile).
func _grandma_join() -> void:
	var at: Vector3 = world.player.global_position
	if npcs.actors.has("grandma"):
		at = npcs.actors["grandma"].node.global_position
		npcs.actors["grandma"].node.visible = false
	var player_at: Vector3 = world.player.global_position
	var occupied: Array[Vector3] = [player_at]
	for f in _followers:
		if is_instance_valid(f):occupied.append(f.global_position)
	if not _company_clear(at, occupied):
		var dir := at - player_at
		dir.y = 0
		var mark := _company_spot(at, dir.normalized() if dir.length() > .1 else Vector3.BACK, occupied)
		if mark != Vector3.INF:at = mark
	var g := _figure("grandma", at, player_at)
	if g:
		g.global_position = at
		_join(g)
	state.set_flag("grandma_joined")
	state.save()
	director.evaluate()

## v28 「今晚我来守灯」 at grandma's door: she comes out; you step aside; 老星 walks up and
## stands in front of her, face to face; two lines; then she comes along.
func _door_reunion() -> void:
	var player: CharacterBody3D = world.player
	player.controls_locked = true
	_hud(false)
	_staging = true
	_bring_out("grandma")
	var rest: Vector3 = npcs.actors["grandma"].rest if npcs.actors.has("grandma") else player.global_position
	var front: Vector3 = props.doors["grandma"].front if props.doors.has("grandma") else Vector3.BACK
	front.y = 0
	front = front.normalized()
	var side := front.cross(Vector3.UP).normalized()
	var keeper: Node3D = _followers[0] if not _followers.is_empty() and is_instance_valid(_followers[0]) else null
	# you step back and to one side (on ground you can stand on, clear of the two of them)
	var mine_side := 1.0 if (player.global_position - rest).dot(side) >= 0.0 else -1.0
	var aside := player.global_position
	for turn: float in [1.05 * mine_side, 1.35 * mine_side, -1.05 * mine_side, -1.35 * mine_side]:
		var slot: int = grid.nearest_slot(rest + front.rotated(Vector3.UP, turn) * 2.0, .5, true)
		if slot < 0:continue
		var at: Vector3 = grid.center(slot)
		if absf(at.y - rest.y) > .45 or Vector2(at.x - rest.x, at.z - rest.z).length() < 1.5:continue
		aside = at + Vector3.UP * .05
		mine_side = 1.0 if (at - rest).dot(side) >= 0.0 else -1.0
		break
	if aside == player.global_position:
		var spare := _company_spot(rest, side * mine_side, [rest], 1.65)
		if spare != Vector3.INF:aside = spare
	player.set_physics_process(false)
	var step := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	step.tween_property(player, "global_position", aside, .7)
	var to_her := rest - aside
	player.model.rotation.y = atan2(-to_her.x, -to_her.z)
	# 老星 walks up in front of her and faces her
	var his := _company_spot(rest, front, [rest, aside], 1.35)
	if his == Vector3.INF:his = _floor_at(rest + front * 1.35, .8)
	if keeper:
		await step.finished
		var from := keeper.global_position
		await _walk_figure(keeper, [from, from.lerp(his, .5) - side * .55 * mine_side, his], clampf(from.distance_to(his) / 1.1, .9, 3.0))
		keeper.rotation.y = atan2(front.x, front.z)
	else:
		await get_tree().create_timer(.8).timeout
	await get_tree().create_timer(.4).timeout
	# (the lamp post by her door and you: nothing to film through)
	var avoid: Array = [aside]
	if lights._door_lamps.has("grandma"):
		avoid.append((lights._door_lamps["grandma"][0] as Node3D).global_position)
		avoid.append((lights._door_lamps["grandma"][1] as Vector3) + Vector3.DOWN * 1.4)   # its lantern, out on the arm
	var faces := rest.lerp(his, .5)
	var pair := _pair_eye(rest, his, front, avoid)
	var his_face := his + Vector3.UP * .75
	var her_face := rest + Vector3.UP * .7
	var at_him := _face_eye(his_face, -front, avoid + [rest])
	var at_her := _face_eye(her_face, front, avoid + [his])
	await _scene_talk("写信的奶奶", ["（门开了。）", "……", "老星：我回来了。", "……嗯。"], {
		0: func():_cut(pair, faces + Vector3.UP * .35, 52.0),
		1: func():_cut(pair, faces + Vector3.UP * .4, 46.0, 1.2),
		2: func():_cut(at_him, his_face + Vector3.DOWN * .5, 44.0),
		3: func():_cut(at_her, her_face + Vector3.DOWN * .5, 44.0),
	}, faces, pair)
	if props.doors.has("grandma"):
		props.doors["grandma"].hold = false
		props.close_door("grandma")
	player.set_physics_process(true)
	_staging = false
	_trail.clear()
	_trail_len.clear()
	for f in _followers:
		if is_instance_valid(f):f.set_meta("approach", true)
	_hud(true)
	player.controls_locked = false
	_grandma_join()

## Two people face to face (`a` at a door, `b` in front of it along `front`): seen from the
## side (both in profile), clear of walls and of `avoid`.
func _pair_eye(a: Vector3, b: Vector3, front: Vector3, avoid: Array) -> Vector3:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var mid := a.lerp(b, .5) + Vector3.UP * .6
	var side := front.cross(Vector3.UP).normalized()
	var best := mid + front * 3.0 + Vector3.UP * 1.0
	var best_score := -INF
	for k in 16:
		var dir := front.rotated(Vector3.UP, k * TAU / 16.0)
		if dir.dot(front) < -.3:continue
		for reach: float in [4.2, 3.4]:
			for lift: float in [1.6, 1.1]:
				var eye := mid + dir * reach + Vector3.UP * lift
				var blocked := 0
				var gap := 9.0
				for from: Vector3 in [a + Vector3.UP * .7, b + Vector3.UP * .75]:
					if not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, eye, 1, [world.player.get_rid()])).is_empty():blocked += 1
					for p: Vector3 in avoid:
						for h: float in [.45, .9, 1.4, 1.8]:
							gap = minf(gap, examines._gap(p + Vector3.UP * h, eye, from))
				# profile (both faces), nothing in the way, nobody close to the line of sight
				var score := -blocked * 10.0 + minf(gap, 1.0) * 4.0 + (1.0 - absf(dir.dot(front))) * 1.5 - lift * .3
				if score > best_score:
					best_score = score
					best = eye
	return best

## A camera on a face looking along `look`: from in front of it, a little to the side,
## with no wall and nobody (`avoid`: where people stand) in between.
func _face_eye(face: Vector3, look: Vector3, avoid: Array) -> Vector3:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for reach: float in [3.3, 2.7]:
		for turn: float in [.6, -.6, .9, -.9, .35, -.35, 1.2, -1.2]:
			var eye := face + look.rotated(Vector3.UP, turn) * reach + Vector3.UP * .7
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(face, eye, 1, [world.player.get_rid()])).is_empty():continue
			var clear := true
			for p: Vector3 in avoid:
				for h: float in [.45, .9, 1.4]:
					if examines._gap(p + Vector3.UP * h, eye, face) < .6:clear = false
			if clear:return eye
	return face + look * 2.3 + Vector3.UP * .8

## At the chair, at dusk: they walk to it and sit; first their backs and the town, then
## their faces; hardly a word.
func _reunion() -> void:
	var scene = world.scene_actions
	var seat: Vector3 = scene._seat_point()
	var facing: Vector3 = scene.FACING
	var side := Vector3(-facing.z, 0, facing.x)
	_staging = true
	var people: Array = _followers.duplicate()
	_followers.clear()
	_seat_visitors(true, people)
	var perf = world.performance
	var mid := seat + side * .31
	if perf.begin("reunion", mid + facing * 8.0, {"distance": 3.0, "height": 1.4, "look_height": 1.0, "mix": .0}):
		var eye := mid - facing * 2.8 + side * 1.6 + Vector3.UP * 1.25
		perf.glide_to(Transform3D(Basis.looking_at(mid + facing * 12.0 + Vector3.UP * .8 - eye), eye), 50.0, 1.4)
		await perf.wait(3.6)
		await perf.finish(.4)
	var lines: Array = ["奶奶：椅子宽了。", "老星：嗯。", "（他们没有再说话。天慢慢暗下来。）"] if state.flag("chair_widened") else ["奶奶：……还是这把椅子。", "老星：嗯。", "（他们没有再说话。天慢慢暗下来。）"]
	var faces := mid + Vector3.UP * .55
	var eye2 := _clear_eye(faces, [faces + facing * 2.3 + side * .5 + Vector3.UP * .7, faces + facing * 1.8 + side * 2.0 + Vector3.UP * .5,
		faces + facing * 1.8 - side * 1.6 + Vector3.UP * .5, faces + side * 2.6 + Vector3.UP * .4, faces - side * 2.2 + Vector3.UP * .4])
	var talk = world.interactions
	if talk.show_talk("观景椅", lines, faces, eye2):
		await talk.talk_closed
	state.set_flag("reunion_seen")
	_staging = false
	state.save()
	director.evaluate()
	ui._toast_time = 0.0
	ui.toast("该回灯塔了。今晚，你来守。", 6.0)

## v29: the bench itself (its model, not the spot in front of it that the registry holds):
## [seat point (the middle of the seat, at seat height), along the seat, facing out].
## Rays down across its depth find the seat (low) and the back (high).
func _bench_seat() -> Array:
	var spot: Vector3 = registry.position_of("keeper_bench")
	var gran: Vector3 = lights._blinks[1].global_position if lights._blinks.size() > 1 else spot + Vector3.LEFT * 10.0
	var meshes := world.find_children("Solid_V13_Keeper_bench*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		var out := (gran - spot).slide(Vector3.UP).normalized()
		return [_floor_at(spot, 1.4) + Vector3.UP * .45, out.cross(Vector3.UP).normalized(), out]
	var mesh: MeshInstance3D = meshes[0]
	var box: AABB = mesh.global_transform * mesh.get_aabb()
	var c := box.get_center()
	var along := Vector3.BACK if box.size.z >= box.size.x else Vector3.RIGHT
	var across := along.cross(Vector3.UP).normalized()
	var depth: float = box.size.x if along == Vector3.BACK else box.size.z
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var low := INF
	var low_at := c
	var high := -INF
	var high_at := c
	for k in 7:
		var p := c + across * (-.45 + k * .15) * depth
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, box.end.y + .5, p.z), Vector3(p.x, box.position.y - .2, p.z), 0xFFFFFFFF, [world.player.get_rid()]))
		if hit.is_empty() or hit.position.y < box.position.y + .15:continue
		if hit.position.y < low:
			low = hit.position.y
			low_at = p
		if hit.position.y > high:
			high = hit.position.y
			high_at = p
	var facing := (low_at - high_at).slide(Vector3.UP)
	if facing.length() < .05:facing = (gran - c).slide(Vector3.UP)
	facing = facing.normalized()
	# along the seat's long side, facing out
	facing = across * signf(facing.dot(across)) if absf(facing.dot(across)) > .1 else facing
	# (a plain box collider has no seat to find: a bench seat is about half its height)
	var seat_y := low if low < INF and high - low > .15 else box.position.y + box.size.y * .5
	var seat_point := Vector3(c.x, seat_y, c.z) + facing * depth * .12
	return [seat_point, along, facing]

## The bench on the lighthouse island: you at one end, 老星 at the other, both looking out.
func _bench_scene() -> void:
	var player: CharacterBody3D = world.player
	var seat := _bench_seat()
	var bench: Vector3 = seat[0]
	var top: float = bench.y
	var axis: Vector3 = seat[1]
	var facing: Vector3 = seat[2]
	var gran: Vector3 = lights._blinks[1].global_position
	var mine := bench + axis * .38
	var his := bench - axis * .38
	player.controls_locked = true
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	player.global_position = mine
	player.model.rotation.y = atan2(-facing.x, -facing.z)
	player.model.set_seated(true)
	player.model.seat_blend = 1.0
	var old_star := _figure("keeper", his, his + facing * 10.0, top)
	var perf = world.performance
	if perf.begin("bench", bench + facing * 8.0, {"distance": 3.0, "height": 1.4, "look_height": 1.0, "mix": .0}):
		var eye := bench - facing * 2.8 + axis * 1.0 + Vector3.UP * 1.5
		perf.glide_to(Transform3D(Basis.looking_at(gran - eye), eye), 42.0, 1.4)
		await perf.wait(2.2)
		await perf.finish(.01)
	# v28: then right over their shoulders, a long lens on grandma's window across the clouds,
	# so you see her lamp blink (three times), and 老星's lamp answer behind you; then faces
	# (above and behind your shoulder: 老星's tall hat is on the other side)
	var tele_eye := Vector3(bench.x, top + 1.55, bench.z) - facing * .9 + axis * .55
	# (her window faces away from the lighthouse: the house itself would hide it; the cut is
	# to just across from her window, the lamp big in the picture)
	var out: Vector3 = props.doors["grandma"].front if props.doors.has("grandma") else (tele_eye - gran).slide(Vector3.UP).normalized()
	var house: Vector3 = props._v(props.doors["grandma"].info.centre) if props.doors.has("grandma") else gran - out
	var away := (gran - house).slide(Vector3.UP)
	if away.length() > .3:out = away.normalized()
	tele_eye = _clear_eye(gran, [gran + out * 13.0 + Vector3.UP * 2.4, gran + out.rotated(Vector3.UP, .4) * 13.0 + Vector3.UP * 2.6,
		gran + out.rotated(Vector3.UP, -.4) * 13.0 + Vector3.UP * 2.6, gran + out * 10.0 + Vector3.UP * 3.0, gran + out * 7.0 + Vector3.UP * 1.5])
	var reach := tele_eye.distance_to(gran)
	var tele_fov := rad_to_deg(2.0 * atan(5.5 / reach))
	var tele_focus := gran + Vector3.DOWN * 1.8
	var faces := Vector3(bench.x, top + .55, bench.z)
	# (v29: from further off: closer, the models' seams show, and it is less quiet)
	var eye2 := _clear_eye(faces, [faces + facing * 4.0 + axis * .9 + Vector3.UP * .8, faces + facing * 4.0 - axis * .9 + Vector3.UP * .8,
		faces + facing * 3.2 + axis * 2.4 + Vector3.UP * .8, faces + facing * 3.2 - axis * 2.4 + Vector3.UP * .8, faces + axis * 3.6 + Vector3.UP * .6])
	var face_focus := faces + Vector3.DOWN * .5
	_hud(false)
	await _scene_talk("长椅", ["（云海那边，奶奶的窗台亮了。）", "（一闪，一闪，一闪。）", "老星：……每天这个时候，她都点灯。", "{name}：你不回去看看她吗？",
			"老星：灯塔离不开人。", "{name}：今晚，我来守。", "老星：…………", "老星：那就，一个傍晚。"], {
		0: func():_cut(tele_eye, tele_focus, tele_fov * 1.6),
		1: func():
			_cut(tele_eye, tele_focus, tele_fov, 1.2)
			lights._gran_signal = 0.0,
		2: func():
			lights._gran_signal = -1.0
			_cut(eye2, face_focus, 40.0),
	}, tele_focus, tele_eye, tele_fov * 1.6)
	lights._gran_signal = -1.0
	_hud(true)
	if is_instance_valid(old_star):old_star.queue_free()
	player.model.set_seated(false)
	player.model.seat_blend = 0.0
	player.global_position = _floor_at(bench + facing * 1.0) + Vector3.UP * .05
	player.set_physics_process(true)
	player.controls_locked = false
	state.set_flag("keeper_agreed")
	state.save()
	director.evaluate()

# ------------------------------------------------------------------ v27: staged conversations
## A conversation whose lines each bring their own moment: when line i comes up,
## `beats[i]` (a Callable) runs: a cut, a sound, someone moving. Lines are turned with E
## or the button as always. Returns when it is closed.
func _scene_talk(title: String, lines: Array, beats: Dictionary, focus: Vector3, eye: Vector3, fov := 50.0) -> void:
	var talk = world.interactions
	if not talk.show_talk(title, lines, focus, eye):return
	var was: float = talk.dialogue_camera.fov
	talk.dialogue_camera.fov = fov
	var shown := -1
	while talk.mode == "dialogue" and talk._talking:
		var i: int = talk.dialogue_index
		if i != shown:
			shown = i
			if beats.has(i):(beats[i] as Callable).call()
		await get_tree().process_frame
	if _cut_glide:_cut_glide.kill()
	talk.dialogue_camera.fov = was

var _cut_glide: Tween
var staging_ui := false          # a staged scene with its own cameras: the HUD steps aside
var _hud_hidden: Array[CanvasLayer] = []

## The HUD steps aside for a staged scene (the conversation box stays), and comes back.
func _hud(shown: bool) -> void:
	staging_ui = not shown
	if not shown:
		_hud_hidden.clear()
		for node in world.get_children():
			if node is CanvasLayer and node.visible and node != world.interactions and node != ui:
				_hud_hidden.append(node)
				node.visible = false
	else:
		for layer in _hud_hidden:
			if is_instance_valid(layer):layer.visible = true
		_hud_hidden.clear()

## The conversation's camera: to `eye`, looking at `focus` (gliding there over `glide`
## seconds, or a cut).
func _cut(eye: Vector3, focus: Vector3, fov := 50.0, glide := 0.0) -> void:
	var cam: Camera3D = world.interactions.dialogue_camera
	if _cut_glide:_cut_glide.kill()
	var goal := Transform3D(Basis.looking_at(focus - eye), eye)
	if glide <= 0.0:
		cam.global_transform = goal
		cam.fov = fov
		return
	_cut_glide = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cut_glide.tween_property(cam, "global_transform", goal, glide)
	_cut_glide.tween_property(cam, "fov", fov, glide)

## A warm light that comes on at `at` (a glint you can see from afar, and its glow);
## fades away after `hold` seconds.
func _flare(at: Vector3, color: Color, size := 1.4, hold := 14.0) -> void:
	var glint: MeshInstance3D = lights._glint(at, size, color)
	glint.scale = Vector3.ONE * .1
	var glow := OmniLight3D.new()
	glow.light_color = color
	glow.omni_range = 5.0
	glow.light_energy = 0.0
	add_child(glow)
	glow.global_position = at
	var t := create_tween().set_parallel(true)
	t.tween_property(glint, "scale", Vector3.ONE, .8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(glow, "light_energy", 2.2, 1.0)
	t.chain().tween_interval(hold)
	t.chain().tween_property(glint, "scale", Vector3.ONE * .01, 2.0)
	t.parallel().tween_property(glow, "light_energy", 0.0, 2.0)
	t.chain().tween_callback(func():
		glint.queue_free()
		glow.queue_free())

func _sfx(id: String, delay := 0.0) -> void:
	if delay > 0.0:await get_tree().create_timer(delay).timeout
	if world.get("audio"):world.audio.play_sfx(id)

## A resident's door opens and they come out; [eye, focus, lens] that frames them whole.
func _bring_out(who: String) -> Array:
	if not npcs.actors.has(who):return []
	var door := String(npcs.actors[who].door)
	if not props.doors.has(door):return []
	props.open_door(door, true, true)
	props.doors[door].hold = true
	var phone := false
	return examines._frame_resident(who, props.doors[door].front, phone)

func _wave(who: String, delay := 1.6) -> void:
	await get_tree().create_timer(delay).timeout
	if npcs.actors.has(who) and npcs.actors[who].node.get_child_count() > 0:npcs._play(npcs.actors[who].node.get_child(0), "wave")

## 「有人听见了吗」: 青铃's bell at dusk, and you see the town answer, one house at a time:
## the sound crosses the clouds, the tree house's wind chime takes it up, the baker knocks
## on his oven door, the lamplighter turns up his lamp, grandma's window blinks; then the
## whole town, lit, from 青铃's islet; and 青铃.
func _bell_answer() -> void:
	var player: CharacterBody3D = world.player
	player.controls_locked = true
	_hud(false)
	var bell: Vector3 = registry.position_of("islet_sw_thing")
	var town: Vector3 = registry.position_of("spawn") + Vector3.UP * 2.0
	var toward := town - bell
	toward.y = 0
	toward = toward.normalized()
	var across := toward.cross(Vector3.UP)
	var qing := _bring_out("islet_sw")
	var her: Vector3 = npcs.actors["islet_sw"].rest if npcs.actors.has("islet_sw") else bell
	await get_tree().create_timer(.9).timeout
	var sky := String(events.sky_name())
	var chime_sound: String = {"day": "windchime_day", "night": "windchime_night"}.get(sky, "windchime")
	# you step to the bell's far side (out from in front of 青铃), facing the town
	var away := bell - her
	away.y = 0
	away = away.normalized() if away.length() > .05 else across
	for spot: Vector3 in [bell + away * .9, bell + across * .9, bell - across * .9]:
		var ground := _floor_at(spot, 1.0)
		if absf(ground.y - bell.y) < .4 and ground != spot:
			player.velocity = Vector3.ZERO
			player.global_position = ground + Vector3.UP * .05
			player.model.rotation.y = atan2(-toward.x, -toward.z)
			break
	await get_tree().physics_frame
	# 青铃 beside her bell, both whole and above the dialogue box
	var framed := _frame_two(her, bell, toward)
	var eye_bell: Vector3 = framed[0]
	var bell_focus: Vector3 = framed[1]
	# the tree house's wind chime (it hangs at CHIME_SPOT; the tree is to its east)
	var chime: Vector3 = (world.activities.CHIME_SPOT if world.get("activities") else town) + Vector3.DOWN * .2
	var chime_eye := _clear_eye(chime, [chime + Vector3(-2.2, .35, .7), chime + Vector3(-2.0, .4, -1.0), chime + Vector3(-1.5, .25, 1.6),
		chime + Vector3(-1.1, .5, -1.9), chime + Vector3(-2.6, .8, 0)])
	var shots := {}
	for who in ["baker", "lamplighter", "grandma"]:
		if who == "grandma" and state.flag("grandma_joined") and not state.flag("watch_done"):continue
		shots[who] = _bring_out(who)
	# the whole town, from beside the bell
	var wide_eye := _clear_eye(bell + Vector3.UP * 1.5, [bell - toward * 3.0 + across * 2.6 + Vector3.UP * 2.6, bell - toward * 3.0 - across * 2.6 + Vector3.UP * 2.6,
		bell - toward * 1.5 + across * 3.4 + Vector3.UP * 2.2, bell + across * 3.0 + Vector3.UP * 3.0, bell - across * 3.0 + Vector3.UP * 3.0])
	var town_look := town.lerp(bell, .12)
	var lamp_at: Vector3 = lights._door_point("lamplighter", .75, .35, .75)
	var gran_at: Vector3 = lights._blinks[1].global_position if lights._blinks.size() > 1 else registry.position_of("door_grandma") + Vector3.UP * 2.0
	var beats := {
		0: func():
			_cut(eye_bell, bell_focus, 50.0)
			_sfx("bell_far", 1.2),
		1: func():
			_cut(chime_eye, chime + Vector3.DOWN * .1, 34.0)
			if world.get("activities") and world.activities.chime_prop:world.activities.chime_prop.ring(1.0)
			_sfx(chime_sound, .2),
		2: func():
			if shots.get("baker", []).size() == 3:_cut(shots.baker[0], shots.baker[1], shots.baker[2])
			_sfx("oven_knock", 1.0)
			_wave("baker", 2.6),
		3: func():
			if shots.get("lamplighter", []).size() == 3:_cut(shots.lamplighter[0], shots.lamplighter[1], shots.lamplighter[2])
			_flare_later(lamp_at, Color(1, .82, .5), 1.2, 1.1),
		4: func():
			if shots.get("grandma", []).size() == 3:_cut(shots.grandma[0], shots.grandma[1], shots.grandma[2])
			else:_cut(gran_at + Vector3(4.5, 1.0, 4.5), gran_at, 46.0)
			lights._gran_signal = 0.0
			_sfx("lamp_on", .4),
		5: func():
			lights._gran_signal = -1.0
			_cut(wide_eye, town_look, 40.0)
			_cut(wide_eye.lerp(bell + Vector3.UP * 2.0, .25), town_look, 36.0, 5.0)
			_flare(town + Vector3.UP * 1.0, Color(1, .86, .6), 4.0, 10.0)
			_sfx("bell_far", .6),
		6: func():
			if qing.size() == 3:_cut(qing[0], qing[1], qing[2]),
		8: func():
			_cut(eye_bell, bell_focus, 50.0, 1.2)
			props.ring_bell(),
	}
	await _scene_talk("雾铃", ["（铃声一圈一圈，往云海那边荡开。）", "（树屋前的风铃，轻轻接了一声。）",
		"（面包房的门开了。面包师敲了敲炉门——咚、咚、咚。）", "（修灯的邻居站在门口，把灯拧亮了。）",
		"（奶奶推开窗。窗台上的灯，一闪，一闪，一闪。）", "（小镇的灯，都朝这边亮着。）",
		"青铃：……", "青铃：原来，都听见了。", "（她又摇了一下铃。这一下，是谢谢。）"], beats, bell_focus, eye_bell)
	lights._gran_signal = -1.0
	for door in ["baker", "lamplighter", "grandma", "islet_sw"]:
		if props.doors.has(door):
			props.doors[door].hold = false
			props.close_door(door)
	player.controls_locked = false
	_hud(true)
	state.set_flag("bell_answered")
	state.save()
	director.evaluate()

## A camera for two things on the ground (a person and what they stand by): both in the
## picture's upper half, nothing in between, a little from the side of `prefer`.
func _frame_two(a: Vector3, b: Vector3, prefer: Vector3) -> Array:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var mid := a.lerp(b, .5)
	var apart := Vector2(a.x - b.x, a.z - b.z).length()
	var best: Array = [mid + prefer * 4.0 + Vector3.UP * 1.8, mid + Vector3.UP * .3]
	var best_score := -INF
	for k in 16:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 16.0)
		for reach: float in [apart * .9 + 2.6, apart * .9 + 1.8]:
			var eye := mid + dir * reach + Vector3.UP * 1.75
			var clear := true
			for from: Vector3 in [a + Vector3.UP * .8, a + Vector3.UP * .3, b + Vector3.UP * 1.1, b + Vector3.UP * .5]:
				if not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, eye, 1, [world.player.get_rid()])).is_empty():
					clear = false
					break
			if not clear:continue
			# the two side by side as seen from here (not one behind the other)
			var spread := (a - eye).normalized().angle_to((b - eye).normalized())
			var score := -absf(spread - .45) * 3.0 + dir.dot(prefer) * .4 + reach * .1
			if score > best_score:
				best_score = score
				best = [eye, mid + Vector3.UP * .25]
	return best

func _flare_later(at: Vector3, color: Color, size: float, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	_flare(at, color, size)
	_sfx("lamp_on")

## The first of these spots from which nothing stands between it and `target`.
func _clear_eye(target: Vector3, spots: Array) -> Vector3:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for eye: Vector3 in spots:
		var q := PhysicsRayQueryParameters3D.create(target, eye, 0xFFFFFFFF, [world.player.get_rid()])
		if space.intersect_ray(q).is_empty():return eye
	return spots[0]

## v28 「今晚我来守灯」: the night on the tower, in four movements, all with its own cameras
## (a staged performance would take the E that turns the pages):
## 1. you sit on the gallery floor against the rail and think aloud: 老星's forty years,
##    the two on the chair (a long lens across the clouds), 归家座 overhead, missing 小光;
##    you nod off;
## 2. through your own eyes: 小光 is suddenly there beside you; a warm talk;
## 3. "你看——": her light spreads: the stars of 归家座 light up one by one and light
##    falls like snow round the tower;
## 4. dawn: a last word, and she flies home.
func _night_watch() -> void:
	var player: CharacterBody3D = world.player
	player.controls_locked = true
	_hud(false)
	await ui.fade(true, 1.0)
	world.day_cycle.set_time(2, 0)
	var gallery: Vector3 = registry.position_of("keeper_lamp")
	var lamp_room: Vector3 = props._v(world.meta.keeper_isle.lamp) if world.meta.has("keeper_isle") else gallery + Vector3.RIGHT * 1.6
	var chair: Vector3 = world.scene_actions._seat_point()
	var look := chair - gallery
	look.y = 0
	look = look.normalized()
	var side := look.cross(Vector3.UP).normalized()
	# you sit on the gallery floor, your back to the lamp room, facing the town
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	var lamp_c := Vector3(lamp_room.x, gallery.y, lamp_room.z)
	# (your back to the lamp room, clear of the rail: seen from outside, over the rail)
	var sit_at := lamp_c + look * 1.5
	player.global_position = sit_at
	player.model.rotation = Vector3(0, atan2(-look.x, -look.z), 0)
	player.model.set_seated(true)
	player.model.seat_blend = 1.0
	var head := sit_at + Vector3.UP * .55
	# the two on the chair: a small warm light between them
	var chair_light: MeshInstance3D = lights._glint(chair + Vector3.UP * .95, .7, Color(1.4, 1.1, .7))
	# 归家座 is drawn round the camera: its stars are lit as children of that sky
	var made_sky := not reactions.has("player_star")
	if made_sky:reactions["player_star"] = _player_star()
	var sky_root: Node3D = reactions.player_star
	var points: Array = sky_root.get_meta("points", [])
	var apex := int(sky_root.get_meta("apex_index", 2))
	var home_dir: Vector3 = sky_root.get_meta("direction", Vector3(.77, .58, .22).normalized())
	var sky_stars: Array[MeshInstance3D] = []
	for i in points.size():
		var g: MeshInstance3D = lights._glint(sky_root.global_position + points[i], 40.0 if i == apex else 32.0, Color(1.8, 1.65, 1.2))
		g.reparent(sky_root, true)
		g.position = points[i]
		var gm: BaseMaterial3D = g.material_override
		gm.disable_fog = true
		gm.albedo_color.a = .55 if i == apex else 0.0
		sky_stars.append(g)
	var home_star: MeshInstance3D = sky_stars[apex] if apex < sky_stars.size() else null
	var blink_home := func(times: int):
		if home_star == null:return
		var t := create_tween()
		for k in times:
			t.tween_property(home_star.material_override, "albedo_color:a", 1.0, .22)
			t.tween_property(home_star.material_override, "albedo_color:a", .55, .45)
		_sfx("twinkle")
	# cameras
	var cam := Camera3D.new()
	cam.far = 1500
	cam.near = .05
	world.add_child(cam)
	var wide_eye := gallery + look.rotated(Vector3.UP, .95) * 9.0 + Vector3.UP * 7.0
	var wide_focus := head + (lamp_room - gallery) * .3 + Vector3.UP * .2
	# (above the rail, looking down: from lower its bars cross your face)
	var near_eye := head + look.rotated(Vector3.UP, -.6) * 3.4 + Vector3.UP * 2.7
	var near_focus := head + Vector3.DOWN * .45
	var tele_eye := head + look * .7 + Vector3.UP * .9
	var tele_fov := rad_to_deg(2.0 * atan(2.2 / tele_eye.distance_to(chair)))
	var tele_focus := chair + Vector3.DOWN * .4
	# if anything stands between the tower and the chair, the cut goes to the chair itself
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(chair + Vector3.UP * .8, tele_eye, 1, [player.get_rid()])).is_empty():
		var facing: Vector3 = world.scene_actions.FACING
		var across := Vector3(-facing.z, 0, facing.x)
		var pair := chair + across * .31 + Vector3.UP * .5
		tele_eye = _clear_eye(pair, [pair + facing * 3.2 + across * 1.2 + Vector3.UP * .9, pair + facing * 3.2 - across * 1.2 + Vector3.UP * .9,
			pair - facing * 3.0 + across * .8 + Vector3.UP * 1.2])
		tele_focus = pair + Vector3.DOWN * .45
		tele_fov = 34.0
	var star_way := home_dir.slide(Vector3.UP).normalized()
	var up_eye := gallery - star_way * 7.5 + Vector3.UP * .8
	var elev := asin(clampf(home_dir.y, -1, 1)) - deg_to_rad(14.0)
	var sky_aim := Vector3(star_way.x * cos(elev), sin(elev), star_way.z * cos(elev))
	cam.global_transform = Transform3D(Basis.looking_at(wide_focus - wide_eye), wide_eye)
	cam.fov = 48
	cam.current = true
	await get_tree().create_timer(.3).timeout
	await ui.fade(false, 1.8)
	var drift := create_tween()
	drift.tween_property(cam, "global_position", wide_eye.lerp(head, .15), 6.0).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(1.4).timeout
	# 1. alone on the tower
	await _scene_talk("守夜", ["（灯一圈一圈地转。云海很安静。）", "{name}：……原来守灯，是这么安静。", "{name}：老星每天晚上，都是一个人，这样坐着吧。",
			"{name}：灯转过来，照一下奶奶的窗台；转过去，照一下回家的路。", "{name}：四十年，一个晚上也没有停过。",
			"（云海那边，观景椅上，两个人影挨在一起。）", "{name}：……今晚，他们终于坐在一起了。", "{name}：原来守灯的人，是把自己的晚上，借给了别人。",
			"（你抬起头。归家座亮着。最小的那一颗，是小光。）", "{name}：小光……你在那儿，看得见这里吗？", "{name}：好久，没跟你说话了。",
			"（你抱着膝盖，坐在灯塔的地上。想着想着——）"], {
		0: func():_cut(cam.global_position, wide_focus, 48.0),
		1: func():_cut(near_eye, near_focus, 44.0),
		2: func():_cut(near_eye.lerp(head, .3), near_focus, 40.0, 3.0),
		3: func():_cut(wide_eye.lerp(head, .1), wide_focus, 50.0, 1.4),
		5: func():
			_cut(tele_eye, tele_focus, tele_fov * 1.5)
			_cut(tele_eye, tele_focus, tele_fov, 3.0),
		7: func():_cut(near_eye, near_focus, 44.0),
		8: func():
			_cut(up_eye, up_eye + sky_aim * 10.0, 62.0)
			blink_home.call(2),
		9: func():blink_home.call(1),
		10: func():_cut(near_eye.lerp(head, .2), near_focus, 42.0),
		11: func():
			_cut(wide_eye.lerp(head, .3), wide_focus, 46.0, 4.0)
			_pose_player("hug_knees"),
	}, wide_focus, wide_eye, 48.0)
	drift.kill()
	cam.global_transform = world.interactions.dialogue_camera.global_transform
	cam.fov = world.interactions.dialogue_camera.fov
	cam.current = true
	player.controls_locked = true
	_pose_player("doze")
	await get_tree().create_timer(1.2).timeout
	await ui.fade(true, 2.4)
	await get_tree().create_timer(1.0).timeout
	# 2. through your own eyes: they open, slowly, blurred; she is there
	player.model.visible = false
	var fp_eye := head + Vector3.UP * .05 + look * .12
	cam.global_transform = Transform3D(Basis.looking_at(look * 5.0 + Vector3.UP * .25), fp_eye)
	cam.fov = 60
	var light_one = xiaoguang
	var fp_spot := fp_eye + look * 1.15 + side * .25 + Vector3.UP * .06
	light_one.visible = true
	light_one.where = "perform"
	light_one.star.scale = Vector3.ONE * .3
	light_one.star.position = Vector3.ZERO
	light_one.global_position = fp_spot
	light_one.trail.emitting = false
	cam.global_transform = Transform3D(Basis.looking_at(fp_spot + Vector3.DOWN * .22 - fp_eye), fp_eye)
	cam.fov = 56
	var lids := _eyelids()
	await ui.fade(false, .2)
	await _open_eyes(lids)
	_sfx("twinkle")
	var pulses := create_tween().set_loops()
	pulses.tween_property(light_one.halo, "scale", Vector3.ONE * 2.6, .35).set_trans(Tween.TRANS_SINE)
	pulses.tween_property(light_one.halo, "scale", Vector3.ONE * 1.2, .9).set_trans(Tween.TRANS_SINE)
	pulses.tween_interval(.6)
	var bob := create_tween().set_loops()
	bob.tween_property(light_one.star, "position:y", .05, 1.1).set_trans(Tween.TRANS_SINE)
	bob.tween_property(light_one.star, "position:y", -.04, 1.1).set_trans(Tween.TRANS_SINE)
	var hop := func():
		light_one._smile = 2.0
		var h := create_tween()
		h.tween_property(light_one.star, "scale", Vector3.ONE * .42, .15)
		h.tween_property(light_one.star, "scale", Vector3.ONE * .3, .35)
	var fp_look := func(at: Vector3, fov: float, glide: float):_cut(fp_eye, at, fov, glide)
	await _scene_talk("守夜", ["小光：……喂。", "小光：守灯的人，怎么能睡着呀。", "{name}：小光？……我是在做梦吗？", "小光：嘘——那你就当是做梦好了。",
			"小光：我从天上看见，灯塔今晚换了人。就想，下来陪陪你。", "{name}：天上……好吗？", "小光：很亮。很多很多星星，挤在一起亮着。",
			"小光：可我最喜欢的，还是那天晚上——你提着灯，走了那么远的路，送我回家。", "{name}：……我也想你。", "小光：我知道呀。你每次抬头，我都在闪。",
			"小光：你看——"], {
		0: func():
			fp_look.call(fp_spot + Vector3.DOWN * .22, 56.0, 0.0)
			hop.call(),
		1: func():hop.call(),
		2: func():fp_look.call(fp_spot + Vector3.DOWN * .25, 50.0, 1.0),
		3: func():hop.call(),
		4: func():hop.call(),
		6: func():hop.call(),
		7: func():fp_look.call(fp_spot + Vector3.DOWN * .22, 46.0, 2.0),
		9: func():hop.call(),
		10: func():hop.call(),
	}, fp_spot + Vector3.DOWN * .22, fp_eye, 56.0)
	cam.global_transform = world.interactions.dialogue_camera.global_transform
	cam.fov = world.interactions.dialogue_camera.fov
	cam.current = true
	player.controls_locked = true
	# 3. her light spreads: 归家座 lights up star by star, light falls like snow
	# (归家座 is behind you, over the lamp room: seen from the town's side, the tower below it)
	player.model.visible = true
	_pose_player("sit")
	var perch := head + side * .62 + look * .3 + Vector3.UP * .08
	light_one.global_position = perch
	cam.global_transform = Transform3D(Basis.looking_at(sky_aim), up_eye)
	cam.fov = 62.0
	light_one.react("grow")
	var burst := create_tween()
	burst.tween_property(light_one.halo, "scale", Vector3.ONE * 6.0, .5).set_trans(Tween.TRANS_SINE)
	burst.tween_property(light_one.halo, "scale", Vector3.ONE * 1.6, 1.2).set_trans(Tween.TRANS_SINE)
	_sfx("lamp_on")
	await get_tree().create_timer(1.3).timeout
	for i in sky_stars.size():
		if i == apex:continue
		var g := sky_stars[i]
		var on := create_tween().set_parallel(true)
		on.tween_property(g.material_override, "albedo_color:a", 1.0, .35)
		g.scale = Vector3.ONE * .4
		on.tween_property(g, "scale", Vector3.ONE, .5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_sfx("twinkle")
		await get_tree().create_timer(.5).timeout
	if home_star:
		var all := create_tween()
		all.tween_property(home_star.material_override, "albedo_color:a", 1.0, .3)
		all.tween_property(home_star, "scale", Vector3.ONE * 1.5, .3)
		all.tween_property(home_star, "scale", Vector3.ONE, .6)
	var snow := _light_snow(gallery + Vector3.UP * 5.0)
	_sfx("bloom")
	await get_tree().create_timer(1.6).timeout
	# the two of you, side by side, all night
	var mid := head.lerp(perch, .5)
	var two := _clear_eye(mid, [mid + look.rotated(Vector3.UP, -.25) * 3.2 + Vector3.UP * 2.7, mid + look * 3.3 + Vector3.UP * 2.7, mid + look.rotated(Vector3.UP, .25) * 3.2 + Vector3.UP * 2.7])
	var low := Vector3.DOWN * .45
	await _scene_talk("守夜", ["（小光亮了一下。归家座的星星，一颗接一颗，跟着亮了起来。）", "小光：守灯的人，从来不是一个人。", "小光：灯塔照着他们，我照着你。",
			"{name}：……那谁照着你呢？", "小光：你呀。你在下面亮着灯，我就知道往哪儿看。", "小光：今晚，我们一起守。",
			"（你们聊了很久很久。聊小镇，聊灯塔，聊那些亮着的窗。）", "小光：……困了吗？", "{name}：……一点点。",
			"小光：睡吧。下次抬头的时候，记得找我。", "{name}：嗯。一眼……就能找到。", "（聊着聊着，你又睡着了。）"], {
		0: func():_cut(up_eye, up_eye + sky_aim * 10.0, 62.0),
		1: func():
			_cut(two, mid + low, 40.0)
			hop.call(),
		2: func():hop.call(),
		3: func():_cut(two.lerp(mid, .1), head + low, 38.0, 1.0),
		4: func():
			_cut(two, perch + low, 38.0, .8)
			hop.call(),
		5: func():
			_cut(two, mid + low, 40.0, 1.0)
			hop.call(),
		6: func():_cut(wide_eye.lerp(head, .15), wide_focus, 48.0, 5.0),
		7: func():
			_cut(two, mid + low, 40.0)
			hop.call(),
		8: func():_pose_player("hug_knees"),
		9: func():hop.call(),
		10: func():_pose_player("doze"),
		11: func():
			_pose_player("sleep")
			_cut(wide_eye.lerp(head, .1), wide_focus, 48.0, 5.0),
	}, up_eye + sky_aim * 10.0, up_eye, 62.0)
	cam.global_transform = world.interactions.dialogue_camera.global_transform
	cam.fov = world.interactions.dialogue_camera.fov
	cam.current = true
	player.controls_locked = true
	# 4. still night: she goes home, up into 归家座; its smallest star blinks
	pulses.kill()
	bob.kill()
	var away_to: Vector3 = light_one.global_position + (home_dir * 40.0)
	var leave := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	leave.tween_property(cam, "global_transform", Transform3D(Basis.looking_at(sky_aim), up_eye), 1.6)
	leave.tween_property(cam, "fov", 62.0, 1.6)
	await leave.finished
	light_one.trail.emitting = true
	_sfx("twinkle")
	var up_and_away := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	up_and_away.tween_property(light_one, "global_position", away_to, 4.0)
	up_and_away.tween_property(light_one.star, "scale", Vector3.ONE * .12, 4.0)
	await up_and_away.finished
	light_one.trail.emitting = false
	light_one.where = "sky"
	light_one.visible = false
	if home_star:
		var home := create_tween()
		home.tween_property(home_star, "scale", Vector3.ONE * 1.9, .35).set_trans(Tween.TRANS_BACK)
		home.tween_property(home_star, "scale", Vector3.ONE * 1.1, .8)
	_sfx("twinkle")
	await get_tree().create_timer(.8).timeout
	await _scene_talk("守夜", ["（小光回到了归家座。最小的那一颗星，轻轻眨了一下。）"], {}, up_eye + sky_aim * 10.0, up_eye, 62.0)
	cam.current = true
	player.controls_locked = true
	# the story is done (its card, still at night); then the morning
	_hud(true)
	state.set_flag("watch_done")
	state.save()
	director.evaluate()
	await get_tree().create_timer(5.5).timeout
	await ui.fade(true, 1.6)
	world.day_cycle.set_time(0, 0)
	snow.queue_free()
	chair_light.queue_free()
	for g in sky_stars:g.queue_free()
	if made_sky:
		reactions.erase("player_star")
		sky_root.queue_free()
	_pose_player("")
	player.global_position = sit_at + Vector3.UP * .05
	# the follow camera outside the lamp room, as when you climb up
	var inward := (lamp_c - sit_at).slide(Vector3.UP).normalized()
	var aim_at := sit_at + inward.rotated(Vector3.UP, -.75) * 4.0
	player.cam_yaw = atan2(-(aim_at.x - sit_at.x), -(aim_at.z - sit_at.z))
	cam.queue_free()
	player.set_physics_process(true)
	player.arm.get_child(0).current = true
	_ensure_company()
	await get_tree().create_timer(.6).timeout
	await ui.fade(false, 1.6)
	player.controls_locked = false

## v29: the player's body in the night watch: "sit" on the floor, "hug_knees" (arms round
## the knees, chin down), "doze" (head nodding), "sleep" (leaning on the rail, head down),
## "" back to standing.
func _pose_player(what: String) -> void:
	var model = world.player.model
	if what == "":
		model.set_performing(false)
		model.set_seated(false)
		model.seat_blend = 0.0
		model.rotation.z = 0.0
		return
	model.set_seated(true)
	model.seat_blend = 1.0
	var P := preload("res://scripts/performance.gd")
	var hug := {"arm.R": P.arm_r(70, -10), "arm.L": P.arm_l(70, -10), "hand.R": P.rot(P.Y, -30), "hand.L": P.rot(P.Y, 30)}
	var pose := {}
	match what:
		"sit":pose = P.relaxed()
		"hug_knees":
			pose = hug.duplicate()
			pose["spine"] = P.rot(P.X, 16)
			pose["head"] = P.rot(P.X, 10)
		"doze":
			pose = hug.duplicate()
			pose["spine"] = P.rot(P.X, 20)
			pose["head"] = P.rot(P.X, 26)
		"sleep":
			pose = hug.duplicate()
			pose["spine"] = P.rot(P.X, 24)
			pose["head"] = P.rot(P.X, 34) * P.rot(P.Z, 12)
	model.set_performing(true)
	model.set_pose(pose, 3.0)
	var lean := 0.0
	create_tween().tween_property(model, "rotation:z", lean, 1.5).set_trans(Tween.TRANS_SINE)

## v29: waking up, through your own eyes: lids over the picture, blurred, then opening.
func _eyelids() -> ColorRect:
	var layer := CanvasLayer.new()
	layer.layer = 85
	add_child(layer)
	var lids := ColorRect.new()
	lids.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lids.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float open = 0.0;
uniform float blur = 1.0;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * (2.0 + blur * 9.0);
	vec3 c = vec3(0.0);
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			c += texture(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px).rgb;
		}
	}
	c = mix(texture(screen_tex, SCREEN_UV).rgb, c / 9.0, clamp(blur, 0.0, 1.0));
	vec2 p = (UV - 0.5) * vec2(1.0, 2.0);
	float d = length(p * vec2(0.6, 1.0));
	float lid = smoothstep(open * 0.75, open * 0.75 + 0.18, d);
	COLOR = vec4(mix(c, vec3(0.015, 0.012, 0.02), lid), 1.0);
}
"""
	m.shader = sh
	m.set_shader_parameter("open", 0.0)
	m.set_shader_parameter("blur", 1.0)
	lids.material = m
	layer.add_child(lids)
	return lids

func _open_eyes(lids: ColorRect) -> void:
	var m: ShaderMaterial = lids.material
	var t := create_tween()
	t.tween_method(func(v: float):m.set_shader_parameter("open", v), 0.0, .38, 1.1).set_trans(Tween.TRANS_SINE)
	t.tween_method(func(v: float):m.set_shader_parameter("open", v), .38, .1, .45).set_trans(Tween.TRANS_SINE)
	t.tween_interval(.5)
	t.tween_method(func(v: float):m.set_shader_parameter("open", v), .1, 1.6, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_method(func(v: float):m.set_shader_parameter("blur", v), 1.0, 0.0, 2.4).set_trans(Tween.TRANS_SINE)
	await t.finished
	lids.get_parent().queue_free()

## Small warm lights drifting down round the tower like snow (the night 小光 came).
func _light_snow(at: Vector3) -> CPUParticles3D:
	var snow := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(.16, .16)
	var m := StandardMaterial3D.new()
	m.albedo_texture = lights._glint_texture()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, .85, .5, .9)
	m.disable_fog = true
	quad.material = m
	snow.mesh = quad
	snow.amount = 60
	snow.lifetime = 5.0
	snow.preprocess = 2.0
	snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snow.emission_box_extents = Vector3(5, .5, 5)
	snow.direction = Vector3.DOWN
	snow.spread = 25.0
	snow.gravity = Vector3(0, -.25, 0)
	snow.initial_velocity_min = .3
	snow.initial_velocity_max = .7
	snow.scale_amount_min = .6
	snow.scale_amount_max = 1.4
	world.add_child(snow)
	snow.global_position = at
	return snow

func _hand_lamp(on: bool) -> void:
	var scene = world.get("scene_actions")
	if scene and is_instance_valid(scene.lantern) and scene.lantern.visible != on:scene.toggle_lantern()

## v24 「小灯的徒弟」: the night lesson (at night, at the little spring, the hand lamp lit).
## (v27: the last lesson no longer puts the flame out when you run: on a phone the stick
## makes walking slowly too hard.)
func _guard_flame() -> void:
	if director.side_state("s_lamp") != "active":return
	var lesson := String(director.side_stage("s_lamp").get("id", ""))
	if lesson == "s_lamp_walk" and not state.flag("s_lamp_walked"):
		var scene = world.get("scene_actions")
		var lit: bool = scene != null and is_instance_valid(scene.lantern) and scene.lantern.visible
		if lit and events.sky_name() == "night" and world.player.global_position.distance_to(registry.position_of("isle_south_l")) < 8.0:
			state.set_flag("s_lamp_walked")
			state.save()
			director.evaluate()

## Named sequences examines and stages can start.
func special(id: String, entry: Dictionary, _variant: Dictionary) -> void:
	if id.begins_with("light:"):
		await lights.perform(id.substr(6))
		return
	match id:
		"chair_widen":widen_chair(true)
		"bench_scene":_bench_scene()
		"keeper_ride":_keeper_ride()
		"grandma_join":_grandma_join()
		"door_reunion":_door_reunion()
		"reunion":_reunion()
		"bell_answer":_bell_answer()
		"night_watch":_night_watch()
		"write_letter":ui.compose_letter()
		"lamp_on":_hand_lamp(true)
		"admire_flowers":world.activities.admire_flowers()
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
	if face_toward == "keeper_lamp" and world.meta.has("keeper_isle"):
		# the middle of the walkway between the lamp room and the rail
		var lamp_at: Vector3 = props._v(world.meta.keeper_isle.lamp)
		var out := (to - lamp_at).slide(Vector3.UP).normalized()
		to = Vector3(lamp_at.x, to.y, lamp_at.z) + out * 1.66
	player.global_position = to + Vector3.UP * .15
	player.velocity = Vector3.ZERO
	var look: Vector3 = registry.position_of("keeper_isle") if face_toward == "keeper_tower" else registry.position_of("dock")
	if face_toward == "keeper_lamp":
		# v27: on the gallery the camera stays outside the lamp room: it looks in past you
		# toward the lamp, turned a little so the town shows beside it
		var lamp_room: Vector3 = props._v(world.meta.keeper_isle.lamp) if world.meta.has("keeper_isle") else to + Vector3.RIGHT
		var inward := lamp_room - to
		inward.y = 0
		look = to + inward.normalized().rotated(Vector3.UP, -.75) * 4.0
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
	_guard_flame()
	_move_company(_delta)
	_update_rider(_delta)
	_gallery_camera(_delta)
	_visit_clock -= _delta
	if _visit_clock <= 0:
		_visit_clock = 1.0
		_ensure_company()
		if state.flag("chair_widened") and not is_instance_valid(_chair_props) and world.get("scene_actions"):widen_chair(false)
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
	root.set_meta("apex_index", apex)
	root.set_meta("points", points)
	root.set_meta("direction", direction)
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
		# through the telescope its own chart draws 归家座; the sky one would be a second outline
		var talk = world.get("interactions")
		reactions.player_star.visible = not (talk and talk.mode == "scope")
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
