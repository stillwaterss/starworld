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
var _playable := false
var _seated := false
var _last_size := Vector2.ZERO
var _context_key := 0
var _second_key := 0
var _hint_clock := 0.0
var _last_hint := ""
var _hint_keys: Array[int] = []
var _button_fingers := {}
var _button_callbacks := {}
var jump_button: Button
var interact_button: Button
var context_button: Button
var second_button: Button
var more_button: Button
var seat_button: Button
var seat_sky_button: Button
const ACTIONS := {"R": "种花", "U": "浇水", "K": "打水漂", "C": "坐下", "T": "换天色", "X": "风铃", "L": "愿望灯", "V": "萤火虫", "F": "手灯", "G": "招手", "O": "摄影", "J": "手记", "Q": "指引", "N": "地图", "H": "帮助", "P": "故事", "Y": "设置", "M": "音乐", "E": "互动"}
static var _press_word: RegEx

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
	for pair in [["按住 Shift", "点“奔跑”"], ["按空格", "点“跳跃”"], ["滚轮变焦", "点＋或－变焦"]]:
		text = text.replace(pair[0], pair[1])
	if _press_word == null:
		_press_word = RegEx.new()
		_press_word.compile("(?:按|用) *([A-Z])(?![A-Za-z])")
	var presses := _press_word.search_all(text)
	for i in range(presses.size() - 1, -1, -1):
		var hit := presses[i]
		var key := hit.get_string(1)
		if ACTIONS.has(key):
			text = text.substr(0, hit.get_start()) + "点“" + ACTIONS[key] + "”" + text.substr(hit.get_end())
	if _key_word == null:
		_key_word = RegEx.new()
		_key_word.compile("(^|· )[A-Z] +")
	var plain := _key_word.sub(text, "$1", true)
	if plain != text:plain += "（在菜单里）"
	return plain.replace("地图 N", "地图").replace("（E）", "（点互动）")

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
	button.focus_mode = Control.FOCUS_NONE
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
	interact_button = _pad_button("互动", Vector2(130, 106), 30, func():_tap_key(KEY_E))
	interact_button.add_theme_stylebox_override("normal", _box(Color("#f2d397"), Color("#fff1c5"), 43, 2))
	interact_button.add_theme_color_override("font_color", Color("#392940"))
	jump_button = _pad_button("跳跃", Vector2(106, 94), 29, func():world.player.jump())
	run_button = _pad_button("奔跑", Vector2(106, 82), 27, _toggle_run)
	context_button = _pad_button("", Vector2(134, 80), 27, func():_tap_key(_context_key))
	second_button = _pad_button("", Vector2(134, 80), 27, func():_tap_key(_second_key))
	more_button = _pad_button("菜单", Vector2(112, 82), 27, _show_menu)
	more_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	more_button.offset_left = -142
	more_button.offset_right = -30
	more_button.offset_top = 26
	more_button.offset_bottom = 108
	seat_button = _pad_button("起身", Vector2(130, 94), 29, func():_tap_key(KEY_C))
	seat_sky_button = _pad_button("换天色", Vector2(134, 88), 27, func():_tap_key(KEY_T))
	_build_menu()

func _pad_button(label: String, size: Vector2, font_size: int, callback: Callable) -> Button:
	var button := _button(label, size, font_size)
	controls.add_child(button)
	button.pressed.connect(callback)
	_button_callbacks[button] = callback
	return button

func _toggle_run() -> void:
	world.player.touch_run = not world.player.touch_run
	run_button.text = "奔跑中" if world.player.touch_run else "奔跑"

func _layout() -> void:
	_last_size = root_control.size
	# Godot uses a 720-high layout on phones; keep the thumb area out of navigation margins.
	var edge := 42.0
	var bottom := 40.0
	_place_bottom(interact_button, edge, bottom, Vector2(130, 106))
	_place_bottom(jump_button, edge + 148, bottom + 5, Vector2(106, 94))
	_place_bottom(run_button, edge + 148, bottom + 111, Vector2(106, 82))
	_place_bottom(context_button, edge, bottom + 119, Vector2(134, 80))
	_place_bottom(second_button, edge, bottom + 210, Vector2(134, 80))
	_place_bottom(seat_button, edge, bottom, Vector2(130, 94))
	_place_bottom(seat_sky_button, edge, bottom + 108, Vector2(134, 88))
	joy_center = Vector2(edge + 114, _last_size.y - bottom - 116)
	joy_base.position = joy_center - Vector2(110, 110)
	joy_knob.position = joy_center - Vector2(46, 46)
	menu_panel.pivot_offset = menu_panel.size * .5
	menu_panel.scale = Vector2.ONE * (1.38 if _last_size.y > _last_size.x else 1.0)

func _context_actions() -> void:
	var tracked: Dictionary = world.content.director.tracked()
	var hint := String(tracked.get("hint", ""))
	if hint != _last_hint:
		_last_hint = hint
		_hint_keys.clear()
		if _press_word == null:words(hint)
		if _press_word != null:
			for hit in _press_word.search_all(hint):
				var key := hit.get_string(1)
				if key in ["R", "U", "K", "C", "T", "X", "L", "V", "F", "G", "O"]:
					var code := key.unicode_at(0)
					if not _hint_keys.has(code):_hint_keys.append(code)
	var keys := _hint_keys
	if keys.is_empty():
		var activity = world.activities
		if activity.near(activity.GARDEN, 4.0):keys = [KEY_R, KEY_U]
		elif activity.near(activity.WATER, 4.8):keys = [KEY_K]
		elif activity.near(activity.TREE, 4.0):keys = [KEY_X, KEY_L]
		elif activity.near(activity.CHAIR, 3.2):keys = [KEY_C]
	_context_key = keys[0] if not keys.is_empty() else 0
	_second_key = keys[1] if keys.size() >= 2 else 0
	context_button.visible = _context_key != 0
	second_button.visible = _second_key != 0
	if _context_key:context_button.text = ACTIONS[char(_context_key)]
	if _second_key:second_button.text = ACTIONS[char(_second_key)]

func _build_menu() -> void:
	menu_panel = PanelContainer.new()
	menu_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu_panel.offset_left = -390
	menu_panel.offset_right = 390
	menu_panel.offset_top = -252
	menu_panel.offset_bottom = 252
	menu_panel.add_theme_stylebox_override("panel", _box(Color(0.045, 0.07, 0.15, 0.97), GOLD, 28))
	menu_panel.visible = false
	menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control.add_child(menu_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	menu_panel.add_child(content)
	var title := Label.new()
	title.text = "星岛手记 · 旅行菜单"
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
		["故事", KEY_P], ["地图", KEY_N], ["设置", KEY_Y], ["帮助", KEY_H],
		["换天色", KEY_T], ["种花", KEY_R], ["浇水", KEY_U], ["风铃", KEY_X],
		["愿望灯", KEY_L], ["打水漂", KEY_K], ["萤火虫", KEY_V], ["坐下", KEY_C],
		["手灯", KEY_F], ["摄影", KEY_O], ["音乐", KEY_M], ["招手", KEY_G],
		["快速存档", KEY_F5], ["载入存档", KEY_F9], ["回到首页", KEY_B], ["星岛手记", KEY_J], ["路线指引", KEY_Q]
	]
	for action in actions:
		var button := _button(action[0], Vector2(174, 57), 25)
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
	_button_fingers.clear()
	if is_instance_valid(world.player):
		world.player.touch_move = Vector2.ZERO
		world.player.touch_run = false
	if is_instance_valid(run_button):run_button.text = "奔跑"
	if is_instance_valid(joy_knob):joy_knob.position = joy_center - Vector2(46, 46)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(controls):
		_reset_touch()

func _process(delta: float) -> void:
	if not is_instance_valid(world) or not is_instance_valid(world.content) or not is_instance_valid(world.content.ui):return
	if _last_size != root_control.size:
		_layout()
		_reset_touch()
	var ui = world.content.ui
	var was_playable := _playable
	_playable = ui.menu.visible and ui.open_panel == ""
	_seated = world.scene_actions.in_vista()
	if not _playable:menu_panel.hide()
	controls.visible = (_playable or _seated) and not menu_panel.visible
	if was_playable and not _playable:_reset_touch()
	seat_button.visible = _seated
	seat_sky_button.visible = _seated
	for item in [joy_base, joy_knob, interact_button, jump_button, run_button, more_button]:
		item.visible = _playable
	_hint_clock -= delta
	if _hint_clock <= 0 and _playable:
		_hint_clock = .2
		_context_actions()
	if not _playable:
		context_button.hide()
		second_button.hide()
		_hint_clock = 0.0
	_js_clock += delta
	if OS.has_feature("web") and _js_clock >= 0.25:
		_js_clock = 0.0
		var buttons := {}
		var targets: Array = _button_callbacks.keys()
		if menu_panel.visible:targets.append_array(menu_panel.find_children("*", "Button", true, false))
		for control in targets:
			if control.is_visible_in_tree():
				var center: Vector2 = control.get_global_rect().get_center()
				buttons[control.text] = [center.x, center.y]
		JavaScriptBridge.eval("window.starworldTouch = " + JSON.stringify({"controlsVisible": controls.visible, "menuOpen": menu_panel.visible, "move": [world.player.touch_move.x, world.player.touch_move.y], "yaw": world.player.cam_yaw, "joystick": [joy_center.x, joy_center.y], "buttons": buttons, "fps": Engine.get_frames_per_second()}))

func _input(event: InputEvent) -> void:
	if not is_instance_valid(controls) or not controls.is_visible_in_tree():return
	if event is InputEventScreenTouch:
		if event.pressed:
			for button in _button_callbacks:
				if button.is_visible_in_tree() and button.get_global_rect().has_point(event.position):
					_button_fingers[event.index] = button
					get_viewport().set_input_as_handled()
					return
			if not _playable:return
			if joy_id < 0 and event.position.distance_to(joy_center) <= 125.0:
				joy_id = event.index
				_update_joystick(event.position)
				get_viewport().set_input_as_handled()
			elif look_id < 0 and event.position.x > root_control.size.x * .46 and event.position.y > 120:
				look_id = event.index
				get_viewport().set_input_as_handled()
		elif _button_fingers.has(event.index):
			var button: Button = _button_fingers[event.index]
			_button_fingers.erase(event.index)
			if not event.canceled and button.is_visible_in_tree() and button.get_global_rect().has_point(event.position):
				_button_callbacks[button].call()
			get_viewport().set_input_as_handled()
		elif event.index == joy_id:
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
			var relative: Vector2 = event.relative.limit_length(130)
			world.player.cam_yaw -= relative.x * .0031
			world.player.cam_pitch = clampf(world.player.cam_pitch - relative.y * .0027, -.94, .28)
			get_viewport().set_input_as_handled()
		elif _button_fingers.has(event.index):
			get_viewport().set_input_as_handled()

func _update_joystick(position: Vector2) -> void:
	var delta := position - joy_center
	var strength := clampf((delta.length() - 12.0) / 78.0, 0, 1)
	var offset := delta.normalized() * strength
	world.player.touch_move = offset
	joy_knob.position = joy_center + offset * 68.0 - Vector2(46, 46)
