extends CanvasLayer

const CREAM := Color("fff4dc")
const GOLD := Color("e2bd78")

var world
var font: Font
var root_control: Control
var controls: Control
var menu_panel: PanelContainer
var joy_base: Panel
var joy_knob: Panel
var joy_id := -1
var look_id := -1
var joy_center := Vector2.ZERO
var run_button: Button
var _js_clock := 0.0

## Phone wording for texts written with keys in mind ("走近按 E", "X 拨风铃 · L 放愿望灯"):
## the quest box and the corner hints pass their text through words() before showing it.
## On a computer it returns the text untouched.
static var _touch := -1
static var _key_word: RegEx
static func touch() -> bool:
	if _touch < 0:
		var web := OS.has_feature("web") and bool(JavaScriptBridge.eval("window.starworldMobile === true"))
		_touch = 1 if web or "--touch-preview" in OS.get_cmdline_user_args() else 0
	return _touch == 1

static func words(text: String) -> String:
	if text == "" or not touch():return text
	for pair in [["按 H 看看今天能做些什么", "点“玩法”看看今天能做些什么"], ["按住 Shift", "点“奔跑”"], ["按空格", "点“跳跃”"], ["按 E", "点“互动”"]]:
		text = text.replace(pair[0], pair[1])
	# corner hints like "X 拨风铃 · L 放一盏愿望灯": no letters, and say where the buttons are
	if _key_word == null:
		_key_word = RegEx.new()
		_key_word.compile("(^|· )[A-Z] +")
	var plain := _key_word.sub(text, "$1", true)
	if plain != text:plain += "（在“玩法”里）"
	return plain

func _enabled() -> bool:
	if "--touch-preview" in OS.get_cmdline_user_args():return true
	if not OS.has_feature("web"):return false
	# one decision for the whole page (web_shell.html sets it): touch controls, touch help and
	# the page's camera helper must never disagree (an iPad in landscape used to get touch
	# help without the joystick)
	return bool(JavaScriptBridge.eval("window.starworldMobile === true"))

func _ready() -> void:
	layer = 8
	if not _enabled():
		set_process(false)
		return
	font = preload("res://assets/fonts/LXGWWenKai-Regular.ttf")
	_build()

func _box(bg: Color, border: Color, radius: int, width := 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	box.shadow_color = Color(0, 0, 0, 0.22)
	box.shadow_size = 8
	box.shadow_offset = Vector2(0, 3)
	return box

func _button(text: String, size: Vector2, font_size := 24) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _box(Color(0.07, 0.11, 0.22, 0.78), Color(0.86, 0.70, 0.43, 0.70), 22))
	button.add_theme_stylebox_override("hover", _box(Color(0.15, 0.21, 0.34, 0.92), GOLD, 22))
	button.add_theme_stylebox_override("pressed", _box(Color(0.24, 0.29, 0.39, 0.96), Color("ffe2a4"), 22))
	button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), Color("ffe2a4"), 22, 2))
	return button

func _place_bottom(button: Control, right: float, bottom: float, size: Vector2) -> void:
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	button.offset_left = -right - size.x
	button.offset_right = -right
	button.offset_top = -bottom - size.y
	button.offset_bottom = -bottom

func _build() -> void:
	root_control = Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)
	controls = Control.new()
	controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(controls)
	joy_base = Panel.new()
	joy_base.custom_minimum_size = Vector2(220, 220)
	joy_base.size = Vector2(220, 220)
	joy_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_base.add_theme_stylebox_override("panel", _box(Color(0.07, 0.11, 0.22, 0.48), Color(0.86, 0.70, 0.43, 0.50), 110))
	controls.add_child(joy_base)
	joy_knob = Panel.new()
	joy_knob.custom_minimum_size = Vector2(92, 92)
	joy_knob.size = Vector2(92, 92)
	joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_knob.add_theme_stylebox_override("panel", _box(Color(0.88, 0.75, 0.51, 0.70), Color("f5dfad"), 46))
	controls.add_child(joy_knob)
	var interact := _button("互动", Vector2(116, 116), 28)
	_place_bottom(interact, 28, 28, Vector2(116, 116))
	interact.pressed.connect(func():_tap_key(KEY_E))
	controls.add_child(interact)
	var jump := _button("跳跃", Vector2(104, 104), 25)
	_place_bottom(jump, 162, 32, Vector2(104, 104))
	jump.pressed.connect(func():_tap_key(KEY_SPACE))
	controls.add_child(jump)
	run_button = _button("奔跑", Vector2(104, 92), 24)
	run_button.toggle_mode = true
	_place_bottom(run_button, 162, 150, Vector2(104, 92))
	run_button.toggled.connect(func(on):world.player.touch_run = on)
	controls.add_child(run_button)
	var more := _button("玩法", Vector2(104, 76), 23)
	more.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	more.offset_left = -132
	more.offset_right = -28
	more.offset_top = 24
	more.offset_bottom = 100
	more.pressed.connect(_show_menu)
	controls.add_child(more)
	_build_menu()

func _build_menu() -> void:
	menu_panel = PanelContainer.new()
	menu_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu_panel.offset_left = -390
	menu_panel.offset_right = 390
	menu_panel.offset_top = -300
	menu_panel.offset_bottom = 300
	menu_panel.add_theme_stylebox_override("panel", _box(Color(0.045, 0.07, 0.15, 0.97), GOLD, 28))
	menu_panel.visible = false
	root_control.add_child(menu_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	menu_panel.add_child(content)
	var title := Label.new()
	title.text = "选择一个小动作"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", CREAM)
	content.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	content.add_child(grid)
	var actions := [
		["故事 P", KEY_P], ["地图 N", KEY_N], ["设置 Y", KEY_Y], ["帮助 H", KEY_H],
		["换天色 T", KEY_T], ["种花 R", KEY_R], ["浇水 U", KEY_U], ["风铃 X", KEY_X],
		["愿望灯 L", KEY_L], ["打水漂 K", KEY_K], ["萤火虫 V", KEY_V], ["坐下 C", KEY_C],
		["手持灯 F", KEY_F], ["摄影 O", KEY_O], ["音乐 M", KEY_M], ["招手 G", KEY_G],
		["快速存档", KEY_F5], ["选择存档", KEY_F9], ["回到首页", KEY_B]
	]
	for action in actions:
		var button := _button(action[0], Vector2(174, 66), 21)
		button.pressed.connect(func():
			_tap_key(action[1])
			_close_menu()
		)
		grid.add_child(button)
	var close := _button("继续旅行", Vector2(240, 66), 23)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_close_menu)
	content.add_child(close)

func _show_menu() -> void:
	menu_panel.visible = true
	controls.visible = false
	_reset_touch()

func _close_menu() -> void:
	menu_panel.visible = false

func _tap_key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	var release := func():
		var up := InputEventKey.new()
		up.physical_keycode = code
		up.keycode = code
		up.pressed = false
		Input.parse_input_event(up)
	get_tree().create_timer(0.09).timeout.connect(release)

func _reset_touch() -> void:
	joy_id = -1
	look_id = -1
	if is_instance_valid(world.player):
		world.player.touch_move = Vector2.ZERO
		world.player.touch_run = false
	if is_instance_valid(run_button):run_button.button_pressed = false
	if is_instance_valid(joy_knob):joy_knob.position = joy_center - Vector2(46, 46)

func _process(_delta: float) -> void:
	if not is_instance_valid(world) or not is_instance_valid(world.content) or not is_instance_valid(world.content.ui):return
	joy_center = Vector2(142, root_control.size.y - 142)
	joy_base.position = joy_center - Vector2(110, 110)
	if joy_id < 0:joy_knob.position = joy_center - Vector2(46, 46)
	var ui = world.content.ui
	controls.visible = ui.menu.visible and ui.open_panel == "" and not menu_panel.visible
	if not controls.visible and (joy_id >= 0 or look_id >= 0):_reset_touch()
	_js_clock += _delta
	if OS.has_feature("web") and _js_clock >= 0.2:
		_js_clock = 0.0
		JavaScriptBridge.eval("window.starworldTouch = " + JSON.stringify({"controlsVisible": controls.visible, "menuOpen": menu_panel.visible, "move": [world.player.touch_move.x, world.player.touch_move.y], "yaw": world.player.cam_yaw}))

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(controls) or not controls.visible:return
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < root_control.size.x * 0.44 and event.position.y > root_control.size.y * 0.32 and joy_id < 0:
				joy_id = event.index
				_update_joystick(event.position)
				get_viewport().set_input_as_handled()
			elif event.position.x > root_control.size.x * 0.42 and look_id < 0:
				look_id = event.index
				get_viewport().set_input_as_handled()
		else:
			if event.index == joy_id:
				joy_id = -1
				world.player.touch_move = Vector2.ZERO
				joy_knob.position = joy_center - Vector2(46, 46)
				get_viewport().set_input_as_handled()
			elif event.index == look_id:
				look_id = -1
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == joy_id:
			_update_joystick(event.position)
			get_viewport().set_input_as_handled()
		elif event.index == look_id:
			world.player.cam_yaw -= event.relative.x * 0.004
			world.player.cam_pitch = clampf(world.player.cam_pitch - event.relative.y * 0.004, -1.25, 0.4)
			get_viewport().set_input_as_handled()

func _update_joystick(position: Vector2) -> void:
	var offset := (position - joy_center) / 82.0
	if offset.length() > 1.0:offset = offset.normalized()
	world.player.touch_move = offset
	joy_knob.position = joy_center + offset * 68.0 - Vector2(46, 46)
