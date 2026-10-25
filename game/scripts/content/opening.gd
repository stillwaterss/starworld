extends Node
## The opening, played once when the story starts: a meteor shower over the island,
## one small star breaks off and falls into the grass by the tree house, and the
## player wakes at the door. About 35 seconds; a skip button shows after 3 seconds
## (E / Space / Esc / click). Tests and review runs skip it unless --opening is given.
const CAPTIONS := [
	["云海上漂着一座小小的岛。\n岛上住着星星人——很久以前，从天上落下来的星光变成的。", 5.0],
	["那天夜里，天上下起了流星雨。", 3.6],
	["有一颗特别小的星星，被挤出了队伍。", 3.4],
	["它掉进了树屋旁边的草丛里。", 3.2],
	["{name}被那道光照醒了。", 3.0],
]
const SKIP_AFTER := 3.0

var content
var layer: CanvasLayer
var card: Label
var veil: ColorRect
var skip_button: Button
var camera: Camera3D
var playing := false
var skip := false
var _clock := 0.0
var _streaks: Array[Node3D] = []
var _flights: Array[Dictionary] = []
var _shower_centre := Vector3.ZERO

func _ready() -> void:
	name = "Opening"
	layer = CanvasLayer.new()
	layer.layer = 9
	layer.visible = false
	add_child(layer)
	veil = ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(.02, .02, .06, 1)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(veil)
	card = Label.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	card.offset_left = -520
	card.offset_right = 520
	card.offset_top = -190
	card.offset_bottom = -70
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_theme_font_size_override("font_size", 26)
	card.add_theme_color_override("font_color", Color("fff1d7"))
	card.add_theme_color_override("font_outline_color", Color(.03, .03, .1, .9))
	card.add_theme_constant_override("outline_size", 7)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Serif CJK SC", "Noto Sans CJK SC", "Source Han Serif SC"])
	font.fallbacks = [preload("res://assets/fonts/NotoSansSC.ttf"), preload("res://assets/fonts/LXGWWenKai-Regular.ttf")]
	card.add_theme_font_override("font", font)
	card.modulate.a = 0
	layer.add_child(card)
	skip_button = Button.new()
	skip_button.text = "跳过 ▶▶   E"
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.add_theme_font_size_override("font_size", 18)
	skip_button.add_theme_font_override("font", font)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(.08, .08, .16, .55)
	box.set_corner_radius_all(18)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	for state in ["normal", "hover", "pressed"]:skip_button.add_theme_stylebox_override(state, box)
	skip_button.add_theme_color_override("font_color", Color("fff1d7"))
	skip_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip_button.offset_left = -190
	skip_button.offset_top = -74
	skip_button.offset_right = -28
	skip_button.offset_bottom = -28
	skip_button.pressed.connect(func():skip = true)
	skip_button.visible = false
	layer.add_child(skip_button)
	camera = Camera3D.new()
	camera.name = "OpeningCamera"
	camera.fov = 55
	camera.far = 2000
	add_child(camera)

static func wanted() -> bool:
	var args := OS.get_cmdline_user_args()
	return "--opening" in args or not ("--visual-review" in args or "--no-opening" in args)

func _process(delta: float) -> void:
	if not _streaks.is_empty():_move_shower(delta)
	if not playing:return
	_clock += delta
	skip_button.visible = _clock >= SKIP_AFTER and not _ending_scene

var _ending_scene := false

func playing_scenes_done() -> void:
	_ending_scene = true
	skip_button.visible = false

func _input(event: InputEvent) -> void:
	if not playing:return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_E, KEY_SPACE, KEY_ESCAPE, KEY_ENTER] and skip_button.visible:skip = true
		get_viewport().set_input_as_handled()

## Waits `seconds` of the opening, or less once skipped.
func _hold(seconds: float) -> void:
	var left := seconds
	while left > 0 and not skip:
		await get_tree().process_frame
		left -= get_process_delta_time()

func _caption(index: int) -> void:
	var line: Array = CAPTIONS[index]
	card.text = content.named(String(line[0]))
	var t := create_tween()
	t.tween_property(card, "modulate:a", 1.0, .8)
	await _hold(float(line[1]))
	t = create_tween()
	t.tween_property(card, "modulate:a", 0.0, .6)
	await _hold(.6)

func play() -> void:
	if playing:return
	playing = true
	skip = false
	_ending_scene = false
	_clock = 0.0
	var world: Node3D = content.world
	var player: CharacterBody3D = world.player
	var grass: Vector3 = content.registry.position_of("fallen_star")
	var door: Vector3 = content.props.door_front("treehouse")
	player.controls_locked = true
	player.velocity = Vector3.ZERO
	var hidden: Array[Node] = []
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if node.visible and node != layer:
			hidden.append(node)
			node.visible = false
	for tag: Label3D in world.find_children("*", "Label3D", true, false):
		if tag.visible:
			hidden.append(tag)
			tag.visible = false
	world.day_cycle.set_time(2, 0.0)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	layer.visible = true
	veil.color.a = 1
	camera.current = true
	# 1. the island under a full sky
	var high := grass + Vector3(-34, 26, 48)
	camera.look_at_from_position(high, grass + Vector3(10, 22, -40))
	create_tween().tween_property(veil, "color:a", 0.0, 2.0)
	var drift := create_tween()
	drift.tween_property(camera, "global_position", high + Vector3(10, 4, -6), 14.0)
	_start_shower(grass)
	await _caption(0)
	await _caption(1)
	# 2. one small star breaks away and falls
	var star := _falling_star()
	world.add_child(star)
	var start := grass + Vector3(-26, 38, -46)
	star.global_position = start
	_caption(2)
	await _hold(1.2)
	# watch it come down from the grass by the tree house, looking up
	drift.kill()
	var watch := grass + Vector3(4, 3, 7)   # clear of lamps and the garden (checked by rays)
	camera.global_position = watch
	var fall := 0.0
	var seconds := 4.6
	var trail: Array[Vector3] = []
	while fall < seconds and not skip:
		fall += get_process_delta_time()
		var k := clampf(fall / seconds, 0, 1)
		var p := start.lerp(grass + Vector3.UP * .2, k * k) + Vector3(0, sin(k * PI) * 6.0, 0)
		star.global_position = p
		trail.push_front(p)
		if trail.size() > 24:trail.pop_back()
		_draw_trail(star, trail)
		camera.look_at(p, Vector3.UP)
		await get_tree().process_frame
	# 3. it lands: a flash, sparks, then a small steady glow
	star.global_position = grass + Vector3.UP * .2
	_draw_trail(star, [])
	if world.get("audio"):world.audio.play_sfx("objective")
	var light: OmniLight3D = star.get_node("Light")
	light.light_energy = 9.0
	create_tween().tween_property(light, "light_energy", 1.2, 1.6)
	var sparks := _sparks()
	star.add_child(sparks)
	sparks.emitting = true
	var shake := 0.0
	while shake < .6 and not skip:
		shake += get_process_delta_time()
		camera.look_at(grass + Vector3(randf_range(-.15, .15), randf_range(-.1, .1), 0) * (1.0 - shake / .6), Vector3.UP)
		await get_tree().process_frame
	await _caption(3)
	# 4. the player wakes at the tree-house door and looks over
	player.global_position = door + Vector3.UP * .05
	var to_grass := grass - door
	player.model.rotation.y = atan2(-to_grass.x, -to_grass.z)
	player.cam_yaw = player.model.rotation.y
	var side := to_grass.cross(Vector3.UP).normalized()
	# over the shoulder towards the glow in the grass: the player small, the light the subject
	camera.look_at_from_position(door - to_grass.normalized() * 3.4 + side * 1.5 + Vector3.UP * 2.4, door.lerp(grass, .6) + Vector3.UP * .5)
	var perf = world.get("performance")
	if perf:
		player.model.set_performing(true)
		player.model.set_pose(perf.pose("look"), 3.0)
	await _caption(4)
	if perf:player.model.set_performing(false)
	# back to play
	playing_scenes_done()
	var fade := create_tween()
	fade.tween_property(veil, "color:a", 1.0, .5)
	await fade.finished
	_stop_shower()
	star.queue_free()
	player.arm.get_child(0).current = true
	player.controls_locked = false
	for node in hidden:
		if is_instance_valid(node):node.visible = true
	fade = create_tween()
	fade.tween_property(veil, "color:a", 0.0, .8)
	await fade.finished
	layer.visible = false
	playing = false
	content.ui.whisper("……有人吗？我好像，掉下来了。")

func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

func _falling_star() -> Node3D:
	var root := Node3D.new()
	root.name = "FallingStar"
	var core := MeshInstance3D.new()
	core.mesh = preload("res://scripts/actor_visual.gd")._soft_star()
	core.scale = Vector3.ONE * .55
	core.material_override = _glow(Color("fff1c4"), 3.0)
	root.add_child(core)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color("ffe0a4")
	light.light_energy = 4.0
	light.omni_range = 9.0
	root.add_child(light)
	var trail := Node3D.new()
	trail.name = "Trail"
	trail.top_level = true
	root.add_child(trail)
	for i in 24:
		var dot := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = .42 * (1.0 - i / 20.0)
		ball.height = ball.radius * 2
		ball.radial_segments = 8
		ball.rings = 4
		dot.mesh = ball
		dot.material_override = _glow(Color(1, .88, .55, .6 * (1.0 - i / 24.0)), 2.2)
		dot.visible = false
		trail.add_child(dot)
	return root

func _draw_trail(star: Node3D, points: Array) -> void:
	var trail := star.get_node("Trail")
	for i in trail.get_child_count():
		var dot: MeshInstance3D = trail.get_child(i)
		dot.visible = i < points.size()
		if dot.visible:dot.global_position = points[i]

func _sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 48
	p.lifetime = 1.4
	p.explosiveness = .95
	p.direction = Vector3.UP
	p.spread = 80
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -2.5, 0)
	p.scale_amount_min = .5
	p.scale_amount_max = 1.0
	var dot := SphereMesh.new()
	dot.radius = .035
	dot.height = .07
	dot.radial_segments = 6
	dot.rings = 3
	dot.material = _glow(Color(1, .9, .6, .9), 3.0)
	p.mesh = dot
	return p

## A dozen thin streaks crossing the sky, each relaunched after it fades; moved in
## _process so stopping the shower just frees them.
func _start_shower(centre: Vector3) -> void:
	_shower_centre = centre
	for i in 12:
		var streak := MeshInstance3D.new()
		var bar := BoxMesh.new()
		bar.size = Vector3(.12, .12, randf_range(5.0, 9.0))
		streak.mesh = bar
		streak.material_override = _glow(Color(.9, .92, 1.0, .7), 2.5)
		streak.visible = false
		content.world.add_child(streak)
		_streaks.append(streak)
		_flights.append({"wait": randf() * 3.0, "t": 0.0, "time": 1.0, "from": Vector3.ZERO, "to": Vector3.ZERO})

func _move_shower(delta: float) -> void:
	for i in _streaks.size():
		var streak: MeshInstance3D = _streaks[i]
		var f: Dictionary = _flights[i]
		if f.wait > 0:
			f.wait -= delta
			if f.wait <= 0:
				var from := _shower_centre + Vector3(randf_range(-60, 40), randf_range(55, 80), randf_range(-120, -60))
				var dir := Vector3(randf_range(.4, .9), -randf_range(.35, .6), randf_range(.1, .4)).normalized()
				f.from = from
				f.to = from + dir * randf_range(30, 50)
				f.t = 0.0
				f.time = randf_range(.9, 1.6)
				streak.global_position = from
				streak.look_at(f.to, Vector3.UP)
				streak.visible = true
			continue
		f.t += delta
		streak.global_position = (f.from as Vector3).lerp(f.to, minf(f.t / f.time, 1.0))
		if f.t >= f.time:
			streak.visible = false
			f.wait = randf_range(.2, 1.4)

func _stop_shower() -> void:
	for streak in _streaks:
		if is_instance_valid(streak):streak.queue_free()
	_streaks.clear()
	_flights.clear()
