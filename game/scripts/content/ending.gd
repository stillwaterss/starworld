extends Node
## The last night, played as one long scene:
## send_off(): as the ship leaves, every door opens and its resident waves; lanterns rise.
## release_at_summit(): at the top, a cut to the square below — everyone gathered, hands up,
## lanterns going up toward the far light of the ship; back on board, forty lanterns all
## around the ship; a look down at the lit island; the player lifts both hands and 小光
## rises out of them into the empty roof star of 归家座 as the sky turns dreamy.
## The release is seen from the airship: the camera stays by the deck and follows 小光 up.
## descent(): the ship drifts slowly back down among the lanterns while the closing words
## and the credits are read, one line at a time, like a letter.
## finale(): off the ship, the player walks to the square and stands looking up at the
## constellation and the lighthouse's beam; the last line; then the end page (its card).
const NARRATION_GROUND := [
	["那天夜里，全岛的人都来到了广场，抬起了头。", ""],
	["芽芽点亮了花园，奶奶擦亮了窗台，修灯的邻居没有落下一盏灯。", ""],
]
const NARRATION_SHIP := [
	["天灯一盏一盏升起来，托着风，托着心愿，也托着一颗很小的星星。", ""],
]
const NARRATION_RELEASE := [
	["光不是用掉的，是分出去的。", "art"],
	["小光：谢谢你，{name}。谢谢芽芽的花，眠眠的星图，奶奶的窗灯，还有全岛的光。", "xg"],
	["小光：我会在那里，每天晚上都在。你一抬头，就能找到我。", "xg"],
]
const NARRATION_DESCENT := [
	["小光飞得很高很高。它回头看了一眼——那座岛，亮得像另一片星空。", ""],
	["原来回家，不是回到原来的地方，\n是回到有人记得你的地方。", "art"],
	["后来，岛上的人都说，归家座比以前亮了一点。", ""],
	["眠眠在星图上那颗最小的星星旁边，写了一行很小的字：小光。", ""],
	["奶奶窗台上的灯，每天傍晚还是一闪三下。\n云海那边，也还是一闪三下。", ""],
]
const CREDITS := [
	["星星人的小世界", "title"],
	["作者 · 游戏设计\n密斯特李", ""],
	["剧本 · 程序 · 音乐　Claude\n场景 · 角色 · 镜头　GPT（Codex）", ""],
	["非商业、免费的爱好者作品，仅供学习与交流。\n“星星人”相关名称与形象归原权利人所有，本作与原权利人无关，也未获授权。", "small"],
]
const NARRATION_LAST := [
	["谢谢你，{name}。\n你一抬头，就能找到我。", "art"],
]
const Cozy := preload("res://scripts/content/cozy_style.gd")

var content
var layer: CanvasLayer
var sky_layer: CanvasLayer
var dream: TextureRect
var veil: ColorRect
var card: Label                   # kept for older review scripts
var playing := false
var hurry := false
var lanterns: Array[Node3D] = []
var _letter_font: FontVariation
var _clock := 0.0
var finale_panel: PanelContainer
var _words_running := false
var _cast_saved := {}             # npc node -> [position, rotation]
var _leads_saved := {}            # lead npc -> home
signal finale_closed
signal words_done

func _ready() -> void:
	name = "Ending"
	# the closing words: the handwriting font, letters a little apart, like a letter
	_letter_font = FontVariation.new()
	_letter_font.base_font = Cozy.hand()
	_letter_font.spacing_glyph = 3
	# the dreamy sky: a violet-pink-gold wash added over the night, under the words
	sky_layer = CanvasLayer.new()
	sky_layer.layer = 2
	add_child(sky_layer)
	dream = TextureRect.new()
	dream.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dream.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.set_color(0, Color(.42, .24, .74, .5))
	gradient.set_color(1, Color(1.0, .74, .5, .16))
	gradient.add_point(.5, Color(.92, .5, .72, .28))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 4
	texture.height = 256
	dream.texture = texture
	dream.stretch_mode = TextureRect.STRETCH_SCALE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	dream.material = add
	dream.modulate.a = 0
	sky_layer.add_child(dream)
	sky_layer.visible = false
	layer = CanvasLayer.new()
	layer.layer = 9
	layer.visible = false
	add_child(layer)
	veil = ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(.03, .03, .08, 0)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(veil)
	card = Label.new()
	card.visible = false
	layer.add_child(card)

# ------------------------------------------------------------------ the words
## One line, read slowly: it fades in where the eye rests (the lower third), stays long
## enough to be read twice, fades out, and a breath passes before the next. "art" lines
## are larger, pale gold with a soft glow; "xg" are 小光's (pale blue); "title" is the
## name of the game; "small" is the note about the work.
func _line(text: String, style: String) -> void:
	var label := Label.new()
	label.text = content.named(text.trim_prefix("小光："))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.offset_left = -470
	label.offset_right = 470
	label.offset_top = 110
	label.offset_bottom = 250
	label.add_theme_font_override("font", _letter_font)
	label.add_theme_constant_override("line_spacing", 10)
	var size: int = {"art": 40, "title": 46, "xg": 30, "small": 19}.get(style, 29)
	var color: Color = {"art": Color("ffe9c4"), "title": Color("fff1d6"), "xg": Color("e3eeff"), "small": Color("efe7d8")}.get(style, Color("fff8ee"))
	var glow: Color = {"art": Color(1, .8, .55, .55), "title": Color(1, .8, .55, .6), "xg": Color(.62, .76, 1, .5)}.get(style, Color(.98, .82, .7, .28))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(.16, .1, .22, .55))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_shadow_color", glow)
	label.add_theme_constant_override("shadow_outline_size", 18 if style in ["art", "title"] else 10)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.modulate.a = 0
	layer.add_child(label)
	var fade_in := 1.8
	var hold := clampf(3.4 + label.text.length() * .13, 4.0, 8.0) + (1.5 if style in ["art", "title"] else 0.0)
	var fade_out := 1.6
	var t := 0.0
	var total := fade_in + hold + fade_out
	while t < total:
		t += get_process_delta_time() * (4.0 if hurry else 1.0)
		# still: only the opacity changes (a moving line read as shaking)
		label.modulate.a = smoothstep(0.0, 1.0, clampf(t / fade_in, 0, 1)) * smoothstep(0.0, 1.0, clampf((total - t) / fade_out, 0, 1))
		await get_tree().process_frame
	label.queue_free()
	await _wait(1.1)

func _words(lines: Array) -> void:
	for line in lines:await _line(String(line[0]), String(line[1]))

## The same, running alongside a moving scene: emits side_words_done when finished.
signal side_words_done
var _side_words := false

func _words_alongside(lines: Array) -> void:
	_side_words = true
	await _words(lines)
	_side_words = false
	side_words_done.emit()

# ------------------------------------------------------------------ sky lanterns
## A paper lantern rising on the wind; a few carry a real light (the rest just glow).
func _lantern(at: Vector3, speed: float, lit: bool, drift := Vector3.ZERO) -> Node3D:
	var lantern: Node3D = content.world.performance.paper_lantern()
	if not lit:
		for child in lantern.get_children():
			if child is OmniLight3D:child.queue_free()
	lantern.scale = Vector3.ONE * randf_range(1.6, 2.4)
	content.world.add_child(lantern)
	lantern.global_position = at
	lantern.set_meta("speed", speed)
	lantern.set_meta("phase", randf() * TAU)
	lantern.set_meta("drift", drift)
	lanterns.append(lantern)
	return lantern

## Doors open, everyone waves, lanterns go up from all over the island.
func send_off() -> void:
	playing = true
	content.npcs.cheer()
	if content.lights:content.lights.boost = 1.5
	var registry = content.registry
	var spots: Array[Vector3] = []
	for id in ["garden", "spawn", "fountain", "tree_house", "star_roof_shop", "dock"]:
		if registry.has(id):spots.append(registry.position_of(id))
	for i in 24:
		var base: Vector3 = spots[i % spots.size()]
		_lantern(base + Vector3(randf_range(-2.5, 2.5), randf_range(.5, 4.0) + float(i / spots.size()) * 6.0, randf_range(-2.5, 2.5)), randf_range(1.6, 2.6), i % 7 == 0)

func _process(delta: float) -> void:
	if lanterns.is_empty():return
	_clock += delta
	for i in range(lanterns.size() - 1, -1, -1):
		var lantern := lanterns[i]
		if not is_instance_valid(lantern):
			lanterns.remove_at(i)
			continue
		var phase: float = lantern.get_meta("phase")
		var drift: Vector3 = lantern.get_meta("drift")
		# the wind carries them up and slowly round the island
		var p := lantern.global_position
		var swirl := Vector3(-p.z, 0, p.x).normalized() * .25
		lantern.global_position += (Vector3.UP * float(lantern.get_meta("speed")) + swirl + drift + Vector3(sin(_clock * .6 + phase), 0, cos(_clock * .5 + phase)) * .2) * delta
		lantern.rotation.y += delta * .3
		if lantern.global_position.y > 160.0:
			lantern.queue_free()
			lanterns.remove_at(i)

func _input(event: InputEvent) -> void:
	if playing and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_E, KEY_SPACE, KEY_ENTER]:
		hurry = true

func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0:
		await get_tree().process_frame
		left -= get_process_delta_time() * (4.0 if hurry else 1.0)

func _cut(seconds := .6) -> void:
	var t := create_tween()
	t.tween_property(veil, "color:a", 1.0, seconds * (.25 if hurry else 1.0))
	await t.finished

func _uncut(seconds := .8) -> void:
	var t := create_tween()
	t.tween_property(veil, "color:a", 0.0, seconds * (.25 if hurry else 1.0))
	await t.finished

# ------------------------------------------------------------------ the square
## Everyone in the square: the door folk and 芽芽 and 眠眠 in an arc facing the ship's
## light, waving. Their places are restored at the end.
func _gather(square: Vector3, toward: Vector3) -> Array[Vector3]:
	var hands: Array[Vector3] = []
	var facing := toward - square
	facing.y = 0
	facing = facing.normalized()
	var across := facing.cross(Vector3.UP).normalized()
	var people: Array[Node3D] = []
	for id in content.npcs.actors:
		var actor: Dictionary = content.npcs.actors[id]
		people.append(actor.node)
	var n := people.size() + 2
	var k := 0
	for node in people:
		_cast_saved[node] = [node.global_position, node.rotation.y]
		var x := (float(k) / float(n - 1) - .5) * 2.0
		var spot := square + across * x * 6.0 - facing * (absf(x) * 1.6) + Vector3.UP * .1
		node.global_position = _ground(spot)
		node.rotation.y = atan2(-facing.x, -facing.z)
		node.visible = true
		hands.append(node.global_position + Vector3.UP * 1.4)
		k += 1
	for npc in content.world.interactions.npcs:
		_leads_saved[npc] = npc.home
		var x := (float(k) / float(n - 1) - .5) * 2.0
		var spot := square + across * x * 6.0 - facing * (absf(x) * 1.6)
		npc.home = _ground(spot)
		npc.global_position = npc.home
		hands.append(npc.home + Vector3.UP * 1.4)
		k += 1
	return hands

## A camera spot beside the crowd with nothing (trunks, roofs) between it and the people
## or the sky above them: tries a ring of places around the square.
func clear_eye(crowd: Vector3, sky_point: Vector3, across: Vector3, toward: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = content.world.get_world_3d().direct_space_state
	var exclude: Array[RID] = [content.world.player.get_rid()]
	for angle in [0.0, -.45, .45, -.9, .9, -1.35, 1.35]:
		for reach in [9.0, 7.0, 11.0]:
			var eye: Vector3 = crowd + across.rotated(Vector3.UP, angle) * reach - toward * 2.0 + Vector3.UP * .5
			var blocked := false
			for aim in [crowd, sky_point, crowd + Vector3.UP * 3.0]:
				if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, aim, 3, exclude)).is_empty():
					blocked = true
					break
			if not blocked:return eye
	return crowd + across * 9.0 + Vector3.UP * 3.0

func _ground(p: Vector3) -> Vector3:
	var hit: Dictionary = content.world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p + Vector3.DOWN * 6.0, 1))
	return hit.position if not hit.is_empty() else p

func _scatter() -> void:
	for node in _cast_saved:
		if is_instance_valid(node):
			node.global_position = _cast_saved[node][0]
			node.rotation.y = _cast_saved[node][1]
	_cast_saved.clear()
	for npc in _leads_saved:
		if is_instance_valid(npc):
			npc.home = _leads_saved[npc]
			npc.global_position = npc.home
			if is_instance_valid(npc.visual) and "waving" in npc.visual:npc.visual.waving = false
	_leads_saved.clear()
	for door in ["baker", "grandma", "child", "lamplighter", "shop"]:content.props.close_door(door)

# ------------------------------------------------------------------ the summit
## Called by the airship at the top of the night flight.
func release_at_summit() -> void:
	playing = true
	hurry = false
	var world: Node3D = content.world
	var player: CharacterBody3D = world.player
	var perf = world.get("performance")
	var camera: Camera3D = content.airship.camera
	var deck: Vector3 = player.global_position
	layer.visible = true
	sky_layer.visible = true
	player.model.set_performing(true)
	player.model.set_pose(perf.pose("hug"), 4.0)
	# 1. the square below: everyone gathered, hands up, lanterns going up to the ship
	await _cut()
	# the open lawn by 芽芽's garden: nothing tall between the crowd and the sky
	var square: Vector3 = content.registry.position_of("garden") + Vector3(1.5, 0, -1.0)
	var hands := _gather(square, deck)
	var to_ship := deck - square
	to_ship.y = 0
	to_ship = to_ship.normalized()
	var across := to_ship.cross(Vector3.UP).normalized()
	# from the side: the crowd in profile with hands up, the sky and the ship's light beyond
	# behind the crowd: their backs and raised hands, the lanterns going away toward the
	# ship's light high in the night
	var sky_point := square + to_ship * 12.0 + Vector3.UP * 8.0
	var ground_eye := square - to_ship * 8.0 + across * 1.5 + Vector3.UP * 1.8
	camera.global_transform = Transform3D(Basis.looking_at(sky_point - ground_eye), ground_eye)
	camera.fov = 58
	await _uncut()
	var released := 0
	_words_alongside(NARRATION_GROUND)
	var t := 0.0
	while t < 16.0:
		t += get_process_delta_time() * (4.0 if hurry else 1.0)
		if released < 40 and t > released * .32:
			var from: Vector3 = hands[released % hands.size()]
			_lantern(from + Vector3(randf_range(-.2, .2), 0, randf_range(-.2, .2)), randf_range(1.2, 1.9), released % 6 == 0, to_ship * randf_range(.4, .9))
			released += 1
		camera.global_position += Vector3.UP * get_process_delta_time() * .12
		await get_tree().process_frame
	if _side_words:await side_words_done
	# 2. back on board: forty lanterns all around the ship, the island lit below
	await _cut()
	for i in 44:
		var a := float(i) / 44.0 * TAU + randf_range(-.08, .08)
		var r := randf_range(6.5, 16.0)
		_lantern(deck + Vector3(cos(a) * r, randf_range(-12.0, 7.0), sin(a) * r), randf_range(.25, .6), i % 5 == 0)
	var island := Vector3(0, 0, 2)
	var outward := deck - island
	outward.y = 0
	outward = outward.normalized()
	var side := outward.cross(Vector3.UP).normalized()
	# below and beside the gondola: the balloon stays above the frame
	var low_eye := deck + side * 5.5 + outward * 2.0 + Vector3.DOWN * 3.2
	camera.global_transform = Transform3D(Basis.looking_at(island - low_eye), low_eye)
	camera.fov = 60
	await _uncut()
	_glide(camera, Transform3D(Basis.looking_at(island + Vector3.UP * 4 - low_eye), low_eye + side * 1.5), 10.0)
	await _words(NARRATION_SHIP)
	# 3. both hands up; 小光 rises from them; the sky turns dreamy
	var home: Vector3 = content.home_star_point(deck) - deck
	var home_h := Vector3(home.x, 0, home.z).normalized()
	var beside := home_h.cross(Vector3.UP).normalized()
	var hands_eye := deck + beside * 7.0 - home_h * 2.5 + Vector3.UP * 1.4
	_glide(camera, Transform3D(Basis.looking_at(deck + Vector3.UP * 1.5 - hands_eye), hands_eye), 2.5)
	camera.fov = 52
	await _wait(2.6)
	player.model.set_pose(perf.pose("hold_up"), 3.0)
	await _wait(2.0)
	create_tween().tween_property(dream, "modulate:a", 1.0, 8.0)
	content.state.set_flag("reaction_player_star")
	content._apply_reactions()
	var target: Vector3 = content.home_star_point(camera.global_position)
	content.xiaoguang.leave_for(target, 18.0)
	player.model.set_pose(perf.pose("release"), 4.0)
	_words_alongside(NARRATION_RELEASE)
	# seen from the ship: the camera stays by the deck and turns to follow the little light
	_follow(camera, 16.0)
	await _wait(16.0)
	if _side_words:await side_words_done
	player.model.set_pose(perf.pose("look_up"), 2.0)
	if world.get("audio"):world.audio.play_sfx("objective")
	content.events.emit("xiaoguang_home", {"place": "summit"})
	# the rest is read while the ship comes down (the airship calls descent())

## While the ship drifts down: the rest of the words, then the credits. The airship
## follows it with a wide shot; finale() waits for the words to end.
func descent() -> void:
	_words_running = true
	await _words(NARRATION_DESCENT)
	create_tween().tween_property(veil, "color:a", .4, 2.0)
	await _words(CREDITS)
	create_tween().tween_property(veil, "color:a", 0.0, 2.0)
	_words_running = false
	words_done.emit()

func _glide(camera: Camera3D, goal: Transform3D, seconds: float) -> void:
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(camera, "global_transform", goal, seconds * (.25 if hurry else 1.0))

## Keeps the camera turned toward 小光 as it climbs.
func _follow(camera: Camera3D, seconds: float) -> void:
	var t := 0.0
	while t < seconds and is_instance_valid(content.xiaoguang):
		t += get_process_delta_time()
		var look: Vector3 = content.xiaoguang.global_position
		if look.distance_to(camera.global_position) > .5:
			var goal := camera.global_transform.looking_at(look, Vector3.UP)
			camera.global_transform = camera.global_transform.interpolate_with(goal, clampf(get_process_delta_time() * 1.0, 0, 1))
		await get_tree().process_frame

# ------------------------------------------------------------------ after landing
## Off the ship: a walk to the square, a long look up at 归家座 and the lighthouse beam,
## the last line, then the end page.
func finale() -> void:
	var world: Node3D = content.world
	var player: CharacterBody3D = world.player
	player.controls_locked = true
	_scatter()
	if _words_running:await words_done
	var spot: Vector3 = content.registry.position_of("spawn")
	# walking like walking: the performance pose off so arms and legs swing
	player.model.set_performing(false)
	await _walk_to(spot)
	var home: Vector3 = content.home_star_point(spot) - spot
	var home_h := Vector3(home.x, 0, home.z).normalized()
	var perf = world.get("performance")
	await perf.turn_to(spot + home_h * 4.0, .8)
	var camera: Camera3D = content.airship.camera
	# low behind the shoulder: the player's back and head and shoulders, the constellation
	# and the lighthouse's beam above
	var eye: Vector3 = player.global_position - home_h * 3.4 + Vector3.UP * 1.35 + home_h.cross(Vector3.UP) * .8
	camera.global_transform = Transform3D(Basis.looking_at(player.global_position + home_h * 8.0 + Vector3.UP * 4.2 - eye), eye)
	camera.fov = 66
	camera.current = true
	player.model.set_performing(true)
	player.model.set_pose(perf.pose("look_up"), 2.0)
	await _wait(2.5)
	await _words(NARRATION_LAST)
	player.model.set_performing(false)
	var director = content.director
	content.events.emit("ending_seen", {"place": "square"})
	sky_layer.visible = false
	dream.modulate.a = 0
	if content.lights:content.lights.boost = 1.0
	layer.visible = false
	playing = false
	if content.test_session and not "--show-finale" in OS.get_cmdline_user_args():
		player.arm.get_child(0).current = true
		player.controls_locked = false
		return
	var left: Array[String] = []
	for id in director.side_order:
		if director.side_state(id) != "done":left.append(String(director.sides[id].title))
	_build_finale(left)
	finale_panel.modulate.a = 0
	finale_panel.visible = true
	create_tween().tween_property(finale_panel, "modulate:a", 1.0, 1.2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await finale_closed
	player.arm.get_child(0).current = true
	player.controls_locked = false

## Walks the player along the walk grid to `goal` (at most 30 seconds).
func _walk_to(goal: Vector3) -> void:
	var player: CharacterBody3D = content.world.player
	var limit := 30.0
	player.scripted_active = true
	player.scripted_speed = 2.2
	var camera: Camera3D = content.airship.camera
	camera.current = true
	while limit > 0:
		var here := player.global_position
		if Vector2(here.x - goal.x, here.z - goal.z).length() < 1.2:break
		var route: PackedVector3Array = content.grid.path(here, goal)
		var aim := goal
		for p in route:
			if Vector2(p.x - here.x, p.z - here.z).length() > .8:
				aim = p
				break
		var d := Vector3(aim.x - here.x, 0, aim.z - here.z)
		player.scripted_direction = d.normalized() if d.length() > .05 else Vector3.ZERO
		# a calm follow shot from behind and above
		var behind: Vector3 = -player.scripted_direction if player.scripted_direction.length() > .1 else Vector3.BACK
		var eye: Vector3 = here + behind * 5.0 + Vector3.UP * 2.6
		camera.global_position = camera.global_position.lerp(eye, clampf(get_physics_process_delta_time() * 2.0, 0, 1))
		camera.look_at(here + Vector3.UP * 1.0, Vector3.UP)
		await get_tree().physics_frame
		limit -= get_physics_process_delta_time() * (2.0 if hurry else 1.0)
	player.scripted_active = false
	player.scripted_direction = Vector3.ZERO
	player.velocity = Vector3.ZERO

## The end page: a cream card in the painted style, the side stories still waiting as
## small tags, and three choices: play them, keep wandering, or quit.
func _build_finale(left: Array[String]) -> void:
	if is_instance_valid(finale_panel):finale_panel.get_parent().queue_free()
	var top := CanvasLayer.new()
	top.layer = 10
	add_child(top)
	# only the card: the island itself stays behind it (a light veil keeps the words clear)
	var dim := ColorRect.new()
	dim.color = Color(.05, .04, .12, .18)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	top.add_child(dim)
	finale_panel = PanelContainer.new()
	finale_panel.add_theme_stylebox_override("panel", Cozy.frame("modal", [], [76, 60, 76, 98]))
	finale_panel.custom_minimum_size = Vector2(760, 570)
	finale_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	finale_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	finale_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	top.add_child(finale_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size.x = 600
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	finale_panel.add_child(box)
	var title_art := Cozy.art("title_ending")
	if title_art:
		var title_pic := TextureRect.new()
		title_pic.texture = title_art
		title_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		title_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		title_pic.custom_minimum_size = Vector2(0, 92)
		title_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(title_pic)
	box.add_child(Cozy.label("故事完结", 30))
	box.add_child(Cozy.StarRow.new(5))
	box.add_child(Cozy.label(content.named("小光回家了。谢谢你，{name}。"), 24, Cozy.INK))
	box.add_child(Cozy.label("你已经走完了《星星人的小世界》的故事。", 17, Cozy.INK_SOFT, false))
	if not left.is_empty():
		box.add_child(Cozy.label("岛上还有 %d 个小故事在等你：" % left.size(), 18, Cozy.INK_SOFT))
		var tags := HFlowContainer.new()
		tags.alignment = FlowContainer.ALIGNMENT_CENTER
		tags.add_theme_constant_override("h_separation", 8)
		tags.add_theme_constant_override("v_separation", 8)
		box.add_child(tags)
		for title in left:
			var tag := PanelContainer.new()
			var style := StyleBoxFlat.new()
			style.bg_color = Color("f6e6cc")
			style.set_corner_radius_all(14)
			style.content_margin_left = 12
			style.content_margin_right = 12
			style.content_margin_top = 4
			style.content_margin_bottom = 4
			tag.add_theme_stylebox_override("panel", style)
			var tag_text := Cozy.label(title, 16, Cozy.INK)
			tag_text.autowrap_mode = TextServer.AUTOWRAP_OFF
			tag.add_child(tag_text)
			tags.add_child(tag)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var close := func(open_book: bool) -> void:
		top.queue_free()
		finale_closed.emit()
		if open_book:content.ui.toggle_panel.call_deferred("story")
	var first_button := Cozy.button("去玩小故事", close.bind(true), true)
	row.add_child(first_button)
	first_button.grab_focus.call_deferred()
	row.add_child(Cozy.button("继续在岛上走走", close.bind(false)))
	row.add_child(Cozy.button("退出游戏", func():preload("res://scripts/web_platform.gd").exit_game(get_tree())))

## The old tree-house ending is gone (the story ends on the ship); kept so older saves
## or scripts that still call it do nothing harmful.
func play() -> void:
	pass
