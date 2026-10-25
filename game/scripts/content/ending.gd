extends Node
## The last night.
## send_off(): when the summit flight leaves, every door opens and its resident waves,
## and sky lanterns rise from all over the island, drifting up on the wind with the ship.
## release_at_summit(): at the top the island lies lit below, the sky turns dreamy, the
## player lifts both hands and 小光 rises into the empty roof star of 归家座 while the
## closing words float up (the key lines large and golden), then the credits and the
## note about the work. finale(): after the ship has drifted back down to the dock, the
## "故事完结" page, pointing at the side stories still waiting.
const NARRATION := [
	["那天夜里，全岛的人都抬起了头。", ""],
	["芽芽点亮了花园，奶奶擦亮了窗台，修灯的邻居没有落下一盏灯。", ""],
	["天灯一盏一盏升起来，托着风，托着心愿，也托着一颗很小的星星。", ""],
	["光不是用掉的，是分出去的。", "art"],
	["小光：谢谢你，{name}。谢谢芽芽的花，眠眠的星图，奶奶的窗灯，还有全岛的光。", "xg"],
	["小光：我会在那里，每天晚上都在。你一抬头，就能找到我。", "xg"],
	["小光飞得很高很高。它回头看了一眼——那座岛，亮得像另一片星空。", ""],
	["原来回家，不是回到原来的地方，\n是回到有人记得你的地方。", "art"],
	["后来，岛上的人都说，归家座比以前亮了一点。", ""],
	["眠眠在星图上那颗最小的星星旁边，写了一行很小的字：小光。", ""],
	["奶奶窗台上的灯，每天傍晚还是一闪三下。\n云海那边，也还是一闪三下。", ""],
	["谢谢你，{name}。", "art"],
]
const CREDITS := [
	["星星人的小世界", "art"],
	["作者 · 游戏设计\n密斯特李", ""],
	["剧本 · 程序 · 音乐　Claude\n场景 · 角色 · 镜头　GPT（Codex）", ""],
	["非商业、免费的爱好者作品，仅供学习与交流。\n“星星人”相关名称与形象归原权利人所有，本作与原权利人无关，也未获授权。", "small"],
]
const HAND_FONT := "res://assets/fonts/LXGWWenKai-Regular.ttf"

var content
var layer: CanvasLayer
var sky_layer: CanvasLayer
var dream: TextureRect
var veil: ColorRect
var card: Label                   # kept for older review scripts
var playing := false
var hurry := false
var lanterns: Array[Node3D] = []
var _font: Font
var _clock := 0.0
var finale_panel: PanelContainer
signal finale_closed

func _ready() -> void:
	name = "Ending"
	_font = load(HAND_FONT) if ResourceLoader.exists(HAND_FONT) else preload("res://assets/fonts/LXGWWenKai-Regular.ttf")
	# the dreamy sky: a violet-pink-gold wash added over the night, under the words
	sky_layer = CanvasLayer.new()
	sky_layer.layer = 2
	add_child(sky_layer)
	dream = TextureRect.new()
	dream.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dream.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.set_color(0, Color(.42, .22, .78, .55))
	gradient.set_color(1, Color(1.0, .72, .45, .18))
	gradient.add_point(.5, Color(.95, .45, .72, .32))
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

# ------------------------------------------------------------------ floating words
## One line rising slowly from below the middle while it fades in and out. "art" lines
## are large and golden with a glow, "xg" lines are 小光's (night blue), "small" is the
## note about the work.
func _float(text: String, style: String, hold: float) -> void:
	var label := Label.new()
	label.text = content.named(text.trim_prefix("小光："))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.offset_left = -520
	label.offset_right = 520
	label.offset_top = -80
	label.offset_bottom = 80
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", _font)
	var size := {"art": 50, "xg": 30, "small": 20}.get(style, 30) as int
	var color := {"art": Color("ffd98a"), "xg": Color("dce9ff"), "small": Color("e8e2d4")}.get(style, Color("fff4e0")) as Color
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(.12, .06, .2, .9))
	label.add_theme_constant_override("outline_size", 10 if style == "art" else 6)
	label.add_theme_color_override("font_shadow_color", Color(1, .78, .4, .7) if style == "art" else (Color(.6, .75, 1, .6) if style == "xg" else Color(1, .85, .55, .35)))
	label.add_theme_constant_override("shadow_outline_size", 22 if style == "art" else 12)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.modulate.a = 0
	label.pivot_offset = Vector2(520, 80)
	if style == "art":label.scale = Vector2.ONE * .92
	layer.add_child(label)
	var rise := 46.0
	var fade_in := 1.2
	var fade_out := 1.4
	var total := fade_in + hold + fade_out
	var t := 0.0
	while t < total:
		var step := get_process_delta_time() * (4.0 if hurry else 1.0)
		t += step
		var k := t / total
		label.offset_top = -80 + 70 - rise * k * 2.0
		label.offset_bottom = label.offset_top + 160
		label.modulate.a = clampf(t / fade_in, 0, 1) * clampf((total - t) / fade_out, 0, 1)
		if style == "art":label.scale = Vector2.ONE * lerpf(.92, 1.04, smoothstep(0.0, 1.0, k))
		await get_tree().process_frame
	label.queue_free()

func _words(lines: Array, hold: float) -> void:
	for line in lines:
		var style := String(line[1])
		await _float(String(line[0]), style, hold + (1.4 if style == "art" else 0.0) + String(line[0]).length() * .04)

# ------------------------------------------------------------------ sky lanterns
## A paper lantern rising on the wind; a few carry a real light (the rest just glow).
func _lantern(at: Vector3, speed: float, lit: bool) -> Node3D:
	var lantern: Node3D = content.world.performance.paper_lantern()
	if not lit:
		for child in lantern.get_children():
			if child is OmniLight3D:child.queue_free()
	# glowing warm paper, bright enough to read as a light from far away
	for child in lantern.get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D and child.material_override.emission_enabled:
			var paper: StandardMaterial3D = child.material_override.duplicate()
			paper.albedo_color = Color(1, .78, .45, .95)
			paper.emission = Color(1, .7, .35)
			paper.emission_energy_multiplier = 3.2
			child.material_override = paper
	lantern.scale = Vector3.ONE * randf_range(1.6, 2.4)
	content.world.add_child(lantern)
	lantern.global_position = at
	lantern.set_meta("speed", speed)
	lantern.set_meta("phase", randf() * TAU)
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
	for door in ["baker", "grandma", "child", "lamplighter"]:
		if content.props.doors.has(door):spots.append(content.props._v(content.props.doors[door].info.centre))
	var n := 0
	for i in 30:
		var base: Vector3 = spots[i % spots.size()]
		_lantern(base + Vector3(randf_range(-2.5, 2.5), randf_range(.5, 4.0) + float(i / spots.size()) * 6.0, randf_range(-2.5, 2.5)), randf_range(1.6, 2.6), n % 7 == 0)
		n += 1

func _process(delta: float) -> void:
	if lanterns.is_empty():return
	_clock += delta
	for i in range(lanterns.size() - 1, -1, -1):
		var lantern := lanterns[i]
		if not is_instance_valid(lantern):
			lanterns.remove_at(i)
			continue
		var phase: float = lantern.get_meta("phase")
		# the wind carries them up and slowly round the island
		var p := lantern.global_position
		var swirl := Vector3(-p.z, 0, p.x).normalized() * .35
		lantern.global_position += (Vector3.UP * float(lantern.get_meta("speed")) + swirl + Vector3(sin(_clock * .6 + phase), 0, cos(_clock * .5 + phase)) * .25) * delta
		lantern.rotation.y += delta * .3
		if lantern.global_position.y > 140.0:
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
	# more lanterns, all around and below the ship, rising past it
	for i in 20:
		var a := float(i) / 20.0 * TAU
		_lantern(deck + Vector3(cos(a) * randf_range(5, 14), randf_range(-26, -6), sin(a) * randf_range(5, 14)), randf_range(1.4, 2.2), i % 6 == 0)
	player.model.set_performing(true)
	player.model.set_pose(perf.pose("hug"), 4.0)
	# 1. looking down: the whole island lit, lanterns coming up
	var island := Vector3(0, 2, 2)
	var down_eye := deck + (deck - island).normalized() * 6.0 + Vector3.UP * 4.0
	_glide(camera, Transform3D(Basis.looking_at(island - down_eye), down_eye), 4.0)
	await _words(NARRATION.slice(0, 3), 1.6)
	# 2. both hands up; 小光 rises from them; the sky turns dreamy
	var side := Vector3(sin(content.airship._cam_yaw), 0, cos(content.airship._cam_yaw))
	var hands_eye := deck + side * 7.5 + Vector3.UP * 1.2
	_glide(camera, Transform3D(Basis.looking_at(deck + Vector3.UP * 2.6 - hands_eye), hands_eye), 2.5)
	player.model.set_pose(perf.pose("hold_up"), 3.0)
	await _wait(1.6)
	create_tween().tween_property(dream, "modulate:a", 1.0, 6.0)
	content.state.set_flag("reaction_player_star")
	content._apply_reactions()
	var target: Vector3 = content.home_star_point(camera.global_position)
	content.xiaoguang.leave_for(target, 14.0)
	player.model.set_pose(perf.pose("release"), 4.0)
	_follow(camera, 14.0)
	await _words(NARRATION.slice(3, 6), 1.8)
	player.model.set_pose(perf.pose("look_up"), 2.0)
	if world.get("audio"):world.audio.play_sfx("objective")
	content.events.emit("xiaoguang_home", {"place": "summit"})
	await _words(NARRATION.slice(6), 1.8)
	# 3. the credits and the note about the work
	create_tween().tween_property(veil, "color:a", .45, 2.0)
	await _words(CREDITS, 1.6)
	create_tween().tween_property(veil, "color:a", 0.0, 2.0)
	create_tween().tween_property(dream, "modulate:a", .35, 4.0)
	player.model.set_performing(false)
	layer.visible = false

func _glide(camera: Camera3D, goal: Transform3D, seconds: float) -> void:
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(camera, "global_transform", goal, seconds)

## Keeps the camera turned toward 小光 as it climbs.
func _follow(camera: Camera3D, seconds: float) -> void:
	var t := 0.0
	while t < seconds and is_instance_valid(content.xiaoguang):
		t += get_process_delta_time()
		var look: Vector3 = content.xiaoguang.global_position
		if look.distance_to(camera.global_position) > .5:
			var goal := camera.global_transform.looking_at(look, Vector3.UP)
			camera.global_transform = camera.global_transform.interpolate_with(goal, clampf(get_process_delta_time() * 1.2, 0, 1))
		await get_tree().process_frame

# ------------------------------------------------------------------ after landing
## The story is over: a clear page saying so, pointing to the side stories left.
func finale() -> void:
	var director = content.director
	content.events.emit("ending_seen", {"place": "dock"})
	sky_layer.visible = false
	dream.modulate.a = 0
	if content.lights:content.lights.boost = 1.0
	playing = false
	if content.test_session and not "--show-finale" in OS.get_cmdline_user_args():return
	var left: Array[String] = []
	for id in director.side_order:
		if director.side_state(id) != "done":left.append(String(director.sides[id].title))
	_build_finale(left)
	finale_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	content.world.player.controls_locked = true
	await finale_closed
	content.world.player.controls_locked = false

func _build_finale(left: Array[String]) -> void:
	if is_instance_valid(finale_panel):finale_panel.queue_free()
	var top := CanvasLayer.new()
	top.layer = 10
	add_child(top)
	finale_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.08, .08, .18, .92)
	style.border_color = Color(1, .84, .5, .8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(20)
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 34
	style.content_margin_bottom = 30
	style.shadow_color = Color(1, .8, .45, .25)
	style.shadow_size = 24
	finale_panel.add_theme_stylebox_override("panel", style)
	finale_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	finale_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	finale_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	top.add_child(finale_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size.x = 560
	finale_panel.add_child(box)
	var ui_font := preload("res://assets/fonts/LXGWWenKai-Regular.ttf")
	var add_label := func(text: String, size: int, color: Color, hand: bool) -> Label:
		var l := Label.new()
		l.text = content.named(text)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_override("font", _font if hand else ui_font)
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", color)
		box.add_child(l)
		return l
	add_label.call("★ 故事完结 ★", 44, Color("ffd98a"), true)
	add_label.call("小光回家了。谢谢你，{name}。", 22, Color("fff4e0"), true)
	add_label.call("你已通关《星星人的小世界》的故事模式。", 17, Color("d8d2c4"), false)
	if not left.is_empty():
		add_label.call("岛上还有 %d 个小故事在等你：\n%s" % [left.size(), "、".join(left)], 17, Color("cfe0ff"), false)
		add_label.call("按 P 打开故事本，就能开始。", 15, Color("d8d2c4"), false)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	for spec in [["去玩小故事", true], ["继续在岛上走走", false]]:
		var b := Button.new()
		b.text = spec[0]
		b.add_theme_font_override("font", ui_font)
		b.add_theme_font_size_override("font_size", 18)
		b.custom_minimum_size = Vector2(190, 44)
		var open_book: bool = spec[1]
		b.pressed.connect(func():
			finale_panel.visible = false
			finale_closed.emit()
			if open_book:content.ui.toggle_panel.call_deferred("story"))
		row.add_child(b)

## The old tree-house ending is gone (the story now ends on the ship); kept so older
## saves or scripts that still call it do nothing harmful.
func play() -> void:
	pass
