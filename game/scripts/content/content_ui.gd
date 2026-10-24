extends CanvasLayer
## Story entry, objective chip, story book, map, sound settings and help.
## Panels are light cards over the scenery; one at a time; Esc closes.
## Keys: P 故事本 · N 地图 · Y 设置 · H 帮助 · Q 指引开关 · E 看看（小摊等）
const MapView := preload("res://scripts/content/map_view.gd")
const INK := Color("fff4dc")
const SOFT := Color("d8d2c4")
const ACCENT := Color("ffd27d")
const HELP := """[b]走一走[/b]
WASD / 方向键 移动 · 空格 跳 · Shift 跑 · 鼠标转视角
E 交谈 / 看看 / 推门 / 用望远镜 · Esc 关闭窗口 · 演出中按 E 加快

[b]找方向[/b]
N 地图：点地点就会亮起路线 · Q 打开或关掉路线
P 故事本：主线、小故事和手记 · J 星图手记

[b]小事[/b]
T 换天色（晴日 → 傍晚 → 夜晚，约六秒）
R 种花 · U 浇水（花园） · X 风铃 · L 愿望灯（树屋门前）
K 打水漂（喷泉，水会跳舞） · V 萤火虫（傍晚和夜里）
C 走到观景椅坐下 / 起身（西北小岛）；坐着时 ←/→ 换角度
F 手持小灯 · G 招手 · O 摄影：Tab 换取景、1/2/3 滤镜、G 三分线、Enter/空格/左键 拍照
M 音乐开关 · Y 声音与指引设置"""

var content
var root: Control
var font: SystemFont
var chip: PanelContainer
var chip_heading: Label
var chip_title: Label
var chip_route: Label
var chip_arrow: Control
var chip_hint: Label
var toast_panel: PanelContainer
var toast_label: Label
var banner: PanelContainer
var banner_title: Label
var banner_body: Label
var prompt: Button
var menu: HBoxContainer
var title_card: PanelContainer
var panels := {}
var open_panel := ""
var map_view
var map_list: VBoxContainer
var story_box: VBoxContainer
var log_box: VBoxContainer
var settings_rows := {}
var _restore := {}
var _toast_time := 0.0
var _toasts: Array = []          # waiting [text, seconds]; an examine text is not cut off by "完成"
signal note_closed
var note_panel: PanelContainer
var note_title: Label
var note_body: Label
var note_hint: Label
var note_lines: Array = []
var note_index := 0
var whisper_panel: PanelContainer
var whisper_label: Label
var _whispers: Array = []
var _whisper_time := 0.0
var _banner_time := 0.0
var _hint_time := 0.0

func _ready() -> void:
	name = "ContentUI"
	layer = 3
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans CJK SC", "Source Han Sans SC", "WenQuanYi Zen Hei", "Microsoft YaHei"])
	font.fallbacks = [preload("res://assets/fonts/NotoSansSC.ttf")]
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_color", "CheckBox", INK)
	theme.set_stylebox("normal", "Button", _box(Color(1, 1, 1, .10), 10, 12, 6))
	theme.set_stylebox("hover", "Button", _box(Color(1, .9, .7, .22), 10, 12, 6))
	theme.set_stylebox("pressed", "Button", _box(Color(1, .9, .7, .32), 10, 12, 6))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_stylebox("disabled", "Button", _box(Color(1, 1, 1, .04), 10, 12, 6))
	root.theme = theme
	add_child(root)
	_build_chip()
	_build_toast()
	_build_banner()
	_build_prompt()
	_build_menu()
	_build_title_card()
	_build_story()
	_build_map()
	_build_settings()
	_build_help()
	_build_note()
	_build_whisper()
	content.director.objective_changed.connect(refresh)
	content.director.stage_completed.connect(_on_stage_completed)
	content.director.chapter_completed.connect(_on_chapter_completed)
	content.director.message.connect(func(text):toast(text))
	content.guide.arrived.connect(_on_arrived)
	refresh()
	if content.state.data.mode == "" and not "--visual-review" in OS.get_cmdline_user_args():
		_open("title")
	elif content.state.data.mode == "":
		title_card.visible = true

# ------------------------------------------------------------------ building blocks
func _box(color: Color, radius := 14, h := 18, v := 14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = h
	style.content_margin_right = h
	style.content_margin_top = v
	style.content_margin_bottom = v
	return style

func _card() -> StyleBoxFlat:
	var style := _box(Color(.12, .15, .25, .80), 16, 22, 16)
	style.border_color = Color(1, .92, .78, .28)
	style.set_border_width_all(1)
	return style

func _label(text: String, size := 17, color := INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(.08, .1, .18, .85))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _button(text: String, callback: Callable, size := 16) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", size)
	button.pressed.connect(func():
		_play("page")
		callback.call())
	return button

func _play(id: String) -> void:
	var audio = content.world.get("audio")
	if audio:audio.play_sfx(id)

func _panel(id: String, title: String, width: float, height: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _card())
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -width / 2
	panel.offset_right = width / 2
	panel.offset_top = -height / 2
	panel.offset_bottom = height / 2
	panel.visible = false
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_child(_label(title, 24))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(_button("关闭  Esc", close_panel))
	box.add_child(head)
	panels[id] = panel
	return box

# ------------------------------------------------------------------ HUD pieces
func _build_chip() -> void:
	chip = PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _box(Color(.12, .15, .25, .62), 14, 16, 8))
	chip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	chip.offset_left = -230
	chip.offset_right = 230
	chip.offset_top = 10
	chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:toggle_panel("story"))
	root.add_child(chip)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	chip.add_child(box)
	chip_heading = _label("", 13, SOFT)
	chip_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(chip_heading)
	chip_title = _label("", 18)
	chip_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(chip_title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	chip_arrow = Control.new()
	chip_arrow.custom_minimum_size = Vector2(18, 18)
	chip_arrow.draw.connect(_draw_arrow)
	row.add_child(chip_arrow)
	chip_route = _label("", 14, ACCENT)
	row.add_child(chip_route)
	chip_hint = _label("", 14, SOFT)
	chip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chip_hint.custom_minimum_size.x = 420
	box.add_child(chip_hint)

func _draw_arrow() -> void:
	var c := chip_arrow.size / 2
	var a: float = content.guide.screen_heading()
	var f := Vector2(sin(a), -cos(a))
	var s := Vector2(-f.y, f.x)
	chip_arrow.draw_colored_polygon(PackedVector2Array([c + f * 8, c - f * 5 + s * 6, c - f * 2, c - f * 5 - s * 6]), ACCENT)

func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.add_theme_stylebox_override("panel", _box(Color(.12, .15, .25, .70), 12, 16, 8))
	toast_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toast_panel.offset_left = -300
	toast_panel.offset_right = 300
	toast_panel.offset_top = -170
	toast_panel.offset_bottom = -126
	toast_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.visible = false
	root.add_child(toast_panel)
	toast_label = _label("", 16)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_panel.add_child(toast_label)

func _build_banner() -> void:
	banner = PanelContainer.new()
	banner.add_theme_stylebox_override("panel", _box(Color(.14, .16, .26, .72), 16, 26, 14))
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.offset_left = -300
	banner.offset_right = 300
	banner.offset_top = 150
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.visible = false
	root.add_child(banner)
	var box := VBoxContainer.new()
	banner.add_child(box)
	banner_title = _label("", 24, ACCENT)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(banner_title)
	banner_body = _label("", 16)
	banner_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_body.custom_minimum_size.x = 520
	box.add_child(banner_body)

func _build_prompt() -> void:
	prompt = _button("", func():content.examine(content.examine_target), 18)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left = -130
	prompt.offset_right = 130
	prompt.offset_top = -90
	prompt.offset_bottom = -48
	prompt.visible = false
	root.add_child(prompt)

func _build_menu() -> void:
	menu = HBoxContainer.new()
	menu.add_theme_constant_override("separation", 6)
	menu.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	menu.offset_left = -330
	menu.offset_right = -16
	menu.offset_top = -50
	menu.offset_bottom = -14
	menu.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	menu.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(menu)
	for item in [["故事 P", "story"], ["地图 N", "map"], ["设置 Y", "settings"], ["帮助 H", "help"]]:
		var button := _button(item[0], toggle_panel.bind(item[1]), 15)
		menu.add_child(button)

func _build_title_card() -> void:
	title_card = PanelContainer.new()
	title_card.add_theme_stylebox_override("panel", _card())
	title_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	title_card.offset_left = -270
	title_card.offset_right = 270
	title_card.offset_top = -230
	title_card.offset_bottom = -40
	title_card.visible = false
	root.add_child(title_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	title_card.add_child(box)
	var name := _label("星星人的小世界", 28, ACCENT)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name)
	var line := _label("云海上的小镇，今天多了一位新住户。", 16, SOFT)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(line)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	row.add_child(_button("开始故事", start_story, 18))
	row.add_child(_button("先随便走走", free_roam, 18))
	var tip := _label("之后随时可以按 P 打开故事本。", 13, SOFT)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tip)
	panels["title"] = title_card

func _build_story() -> void:
	var box := _panel("story", "故事本", 820, 520)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(columns)
	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(440, 400)
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(left)
	story_box = VBoxContainer.new()
	story_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story_box.add_theme_constant_override("separation", 8)
	left.add_child(story_box)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 300
	columns.add_child(right)
	right.add_child(_label("手记", 18, ACCENT))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	log_box = VBoxContainer.new()
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(log_box)

func _build_map() -> void:
	var box := _panel("map", "地图", 900, 560)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	box.add_child(columns)
	map_view = MapView.new()
	map_view.content = content
	map_view.custom_minimum_size = Vector2(560, 420)
	map_view.picked.connect(func(id):pick_place(id))
	columns.add_child(map_view)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 270
	columns.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(270, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	map_list = VBoxContainer.new()
	map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_list.add_theme_constant_override("separation", 6)
	scroll.add_child(map_list)
	right.add_child(_button("跟随当前目标", func():pick_place(""), 15))
	box.add_child(_label("地图按场景碰撞自动生成：绿色是能走到的地方，灰色是走不到的远景或屋顶。路线沿桥和台阶走。", 13, SOFT))

func _build_settings() -> void:
	var box := _panel("settings", "声音与指引", 520, 430)
	var audio = content.world.get("audio")
	for item in [["music", "音乐"], ["ambience", "环境声"], ["sfx", "提示音"]]:
		var row := HBoxContainer.new()
		row.add_child(_label(item[1], 17))
		row.get_child(0).custom_minimum_size.x = 90
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 1
		slider.step = .05
		slider.custom_minimum_size.x = 300
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value = float(audio.settings[item[0]]) if audio else .8
		slider.value_changed.connect(func(v):if audio:audio.set_volume(item[0], v))
		row.add_child(slider)
		box.add_child(row)
		settings_rows[item[0]] = slider
	for item in [["muted", "静音音乐和环境声（M）"], ["guide", "显示路线指引（Q）"], ["breadcrumbs", "路面上的小光点"], ["prompts", "靠近时的操作提示"]]:
		var check := CheckBox.new()
		check.text = item[1]
		check.add_theme_font_size_override("font_size", 17)
		check.button_pressed = bool(audio.settings.get(item[0], true)) if audio else true
		check.toggled.connect(func(on):_set_option(item[0], on))
		box.add_child(check)
		settings_rows[item[0]] = check
	box.add_child(_label("设置单独保存，不影响故事进度。", 13, SOFT))

func _set_option(key: String, on: bool) -> void:
	var audio = content.world.get("audio")
	if not audio:return
	if key == "muted":
		if bool(audio.settings.muted) != on:audio.toggle_mute()
	else:
		audio.set_option(key, on)
	refresh()

func _build_help() -> void:
	var box := _panel("help", "帮助", 640, 470)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.custom_minimum_size = Vector2(580, 360)
	text.add_theme_font_size_override("normal_font_size", 16)
	text.add_theme_font_size_override("bold_font_size", 17)
	text.add_theme_color_override("default_color", INK)
	text.text = HELP
	box.add_child(text)

## Paper card for letters, signs and things written down; E / Enter / click turns the page.
func _build_note() -> void:
	note_panel = PanelContainer.new()
	var paper := _box(Color("f4ead6"), 10, 34, 26)
	paper.border_color = Color("c9b48c")
	paper.set_border_width_all(2)
	paper.shadow_color = Color(0, 0, 0, .25)
	paper.shadow_size = 10
	note_panel.add_theme_stylebox_override("panel", paper)
	note_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	note_panel.offset_left = -300
	note_panel.offset_right = 300
	note_panel.offset_top = -150
	note_panel.offset_bottom = 150
	note_panel.visible = false
	note_panel.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:_turn_note())
	root.add_child(note_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	note_panel.add_child(box)
	note_title = Label.new()
	note_title.add_theme_font_size_override("font_size", 20)
	note_title.add_theme_color_override("font_color", Color("7a5a36"))
	box.add_child(note_title)
	note_body = Label.new()
	note_body.add_theme_font_size_override("font_size", 19)
	note_body.add_theme_color_override("font_color", Color("3c3024"))
	note_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_body.custom_minimum_size = Vector2(530, 130)
	box.add_child(note_body)
	note_hint = Label.new()
	note_hint.add_theme_font_size_override("font_size", 13)
	note_hint.add_theme_color_override("font_color", Color("9a8668"))
	note_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(note_hint)
	panels["note"] = note_panel

func show_note(title: String, lines: Array) -> void:
	if lines.is_empty():return
	note_lines = lines
	note_index = 0
	note_title.text = title
	_show_note_line()
	if not _open("note"):
		toast(" ".join(lines), 6.0)
		return
	_play("page")
	await note_closed

func _show_note_line() -> void:
	note_body.text = String(note_lines[note_index])
	note_hint.text = ("E 继续  %d / %d" % [note_index + 1, note_lines.size()]) if note_index < note_lines.size() - 1 else "E 合上"

func _turn_note() -> void:
	note_index += 1
	if note_index >= note_lines.size():
		close_panel()
		note_closed.emit()
		return
	_play("page")
	_show_note_line()

## 小光 speaks from the lantern: a soft line above the toasts, one at a time.
func _build_whisper() -> void:
	whisper_panel = PanelContainer.new()
	whisper_panel.add_theme_stylebox_override("panel", _box(Color(.16, .2, .34, .55), 18, 18, 7))
	whisper_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	whisper_panel.offset_left = -280
	whisper_panel.offset_right = 280
	whisper_panel.offset_top = -224
	whisper_panel.offset_bottom = -186
	whisper_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	whisper_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	whisper_panel.visible = false
	root.add_child(whisper_panel)
	whisper_label = _label("", 16, Color("cfe0ff"))
	whisper_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	whisper_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	whisper_panel.add_child(whisper_label)

var _veil: ColorRect

## Fades the screen to a warm dark (true) or back (false).
func fade(dark: bool, seconds := .5) -> void:
	if not is_instance_valid(_veil):
		_veil = ColorRect.new()
		_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_veil.color = Color(.06, .04, .03, 0)
		root.add_child(_veil)
	var t := create_tween()
	t.tween_property(_veil, "color:a", 1.0 if dark else 0.0, seconds)
	await t.finished

func whisper(text: String) -> void:
	if _whispers.size() < 3:_whispers.append(text)

# ------------------------------------------------------------------ open / close
func _can_open() -> bool:
	var cozy = content.world.get("activities")
	if cozy and cozy.photo:return false
	return content.world.interactions.mode in ["idle", "content"]

func toggle_panel(id: String) -> void:
	if open_panel == id:
		close_panel()
		return
	_open(id)

func _open(id: String) -> bool:
	if not _can_open():return false
	if open_panel != "":
		panels[open_panel].visible = false
	else:
		var player: CharacterBody3D = content.world.player
		_restore = {"locked": player.controls_locked, "mouse": Input.mouse_mode}
		content.world.interactions.mode = "content"
		content.world.interactions.prompt.visible = false
		player.controls_locked = true
		player.velocity.x = 0
		player.velocity.z = 0
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	open_panel = id
	panels[id].visible = true
	if id == "map":
		map_view.rebuild()
		_fill_map_list()
	elif id == "story":
		_fill_story()
	elif id == "settings":
		_sync_settings()
	return true

func close_panel() -> void:
	if open_panel == "":return
	panels[open_panel].visible = false
	open_panel = ""
	if content.world.interactions.mode == "content":content.world.interactions.mode = "idle"
	content.world.player.controls_locked = bool(_restore.get("locked", false))
	Input.mouse_mode = _restore.get("mouse", Input.MOUSE_MODE_VISIBLE)
	refresh()

func start_story() -> void:
	close_panel()
	title_card.visible = false
	content.director.start_story()
	content.guide.refresh_route(true)
	_hint_time = 10.0

func free_roam() -> void:
	close_panel()
	title_card.visible = false
	content.director.choose_free_roam()
	toast("随便走走吧。按 N 打开地图，按 P 随时开始故事。", 6.0)

func pick_place(id: String) -> void:
	content.guide.set_manual("" if id == "" else "loc:" + id)
	var audio = content.world.get("audio")
	if audio and not bool(audio.settings.get("guide", true)):audio.set_option("guide", true)
	_fill_map_list()
	if id != "":toast("路线指向：" + content.registry.name_of(id))
	refresh()

func toggle_guide() -> void:
	var audio = content.world.get("audio")
	if not audio:return
	audio.set_option("guide", not bool(audio.settings.get("guide", true)))
	toast("路线指引已打开。" if audio.settings.guide else "路线指引已关闭，按 Q 再打开。")
	refresh()

# ------------------------------------------------------------------ content of panels
func _fill_story() -> void:
	for child in story_box.get_children():
		child.queue_free()
	var director = content.director
	var data: Dictionary = content.state.data
	if not data.started:
		story_box.add_child(_label("故事还没开始。", 18))
		story_box.add_child(_button("开始故事", start_story, 17))
	for i in director.main.size():
		var chapter: Dictionary = director.main[i]
		var done: bool = director.main_done() or int(data.main.chapter) > i
		var current: bool = data.started and not done and int(data.main.chapter) == i
		var status := "完成" if done else ("进行中" if current else "未开始")
		story_box.add_child(_label(chapter.title + "  ·  " + status, 18, ACCENT if current else INK))
		if current:
			var stage: Dictionary = director.main_stage()
			var line := _label("→ " + stage.title + ("  " + director._progress_text(stage) if director._progress_text(stage) != "" else ""), 16)
			story_box.add_child(line)
			var hint := _label(stage.hint, 14, SOFT)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.custom_minimum_size.x = 400
			story_box.add_child(hint)
			if data.track != "main":story_box.add_child(_button("追踪主线", func():director.track("main"); _fill_story(), 15))
	story_box.add_child(_label("小故事", 18, ACCENT))
	for id in director.side_order:
		var side: Dictionary = director.sides[id]
		var st: String = director.side_state(id)
		var names := {"locked": "还没听说", "available": "可以开始", "active": "进行中", "paused": "暂停中", "done": "完成"}
		story_box.add_child(_label(side.title + "  ·  " + names[st], 16))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		if st == "locked":
			row.add_child(_label("和%s多聊聊。" % content.registry.npc_name(side.giver), 14, SOFT))
		elif st == "available":
			row.add_child(_button("开始", func():director.start_side(id); _fill_story(), 15))
		elif st == "paused":
			row.add_child(_button("继续", func():director.start_side(id); _fill_story(), 15))
		elif st == "active":
			var stage: Dictionary = director.side_stage(id)
			row.add_child(_label("→ " + stage.title + " " + director._progress_text(stage), 14))
			if data.track != id:row.add_child(_button("追踪", func():director.track(id); _fill_story(), 15))
			row.add_child(_button("先放下", func():director.pause_side(id); _fill_story(), 15))
		story_box.add_child(row)
	for child in log_box.get_children():
		child.queue_free()
	var entries: Array = data.log
	for i in range(entries.size() - 1, maxi(-1, entries.size() - 30), -1):
		var row := _label(entries[i].text, 14)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size.x = 280
		log_box.add_child(row)
	if entries.is_empty():log_box.add_child(_label("还没有记下什么。", 14, SOFT))

const ACTIVITIES := {
	"garden": [["种花 R", "ev_flower_planted"], ["浇水 U", "ev_flower_watered"]],
	"tree_house": [["风铃 X", "ev_chime_rung"], ["愿望灯 L", "ev_wish_released"]],
	"fountain": [["打水漂 K", "ev_stones_skipped"]],
	"remote_chair": [["坐看云海 C", "ev_seat_settled"]],
	"telescope": [["观星 E", "ev_star_recorded"]],
	"star_roof_shop": [["看看小摊 E", "ev_shop_visited"]],
	"dock": [["看看飞艇 E", "ev_dock_visited"]],
}

func _fill_map_list() -> void:
	for child in map_list.get_children():
		child.queue_free()
	var registry = content.registry
	var player: Vector3 = content.world.player.global_position
	for id in registry.ids():
		if not registry.on_map(id):continue
		var reachable: bool = content.grid.reachable(registry.position_of(id), 3.5)
		var found: bool = id in content.state.data.discovered
		var pos: Vector3 = registry.position_of(id)
		var route: PackedVector3Array = content.grid.path(player, pos) if reachable else PackedVector3Array()
		var meters: float = content.grid.length_of(route) if route.size() > 1 else player.distance_to(pos)
		var chosen: bool = content.guide.target == "loc:" + id
		var head := _button(("▶ " if chosen else "") + registry.name_of(id) + "  ·  %d 米" % int(round(meters)), pick_place.bind(id), 15)
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.disabled = not reachable
		map_list.add_child(head)
		var notes: Array[String] = []
		if not found:notes.append("还没去过")
		for act in ACTIVITIES.get(id, []):
			notes.append(("✓ " if content.state.flag(act[1]) else "· ") + act[0])
		if not reachable:notes = ["远景，走不到"]
		var info := _label("  " + "  ".join(notes), 13, SOFT)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size.x = 250
		map_list.add_child(info)

func _sync_settings() -> void:
	var audio = content.world.get("audio")
	if not audio:return
	for key in ["music", "ambience", "sfx"]:settings_rows[key].set_value_no_signal(float(audio.settings[key]))
	for key in ["muted", "guide", "breadcrumbs", "prompts"]:settings_rows[key].set_pressed_no_signal(bool(audio.settings.get(key, true)))

# ------------------------------------------------------------------ live HUD
func refresh() -> void:
	if not is_instance_valid(chip):return
	var tracked: Dictionary = content.director.tracked()
	var manual: String = content.state.data.guide_target
	chip.visible = not tracked.is_empty() or manual != ""
	if manual != "":
		chip_heading.text = "地图目标"
		chip_title.text = "前往 " + content.registry.target_name(manual)
	elif not tracked.is_empty():
		chip_heading.text = tracked.heading
		chip_title.text = tracked.title + ("  " + tracked.progress if tracked.progress != "" else "")
	if open_panel == "story":_fill_story()

func toast(text: String, seconds := 3.5) -> void:
	if title_card.visible:return
	if _toast_time > .8 or _performing():
		if _toasts.size() < 3:_toasts.append([text, seconds, Time.get_ticks_msec()])
		return
	toast_label.text = text
	toast_panel.visible = true
	toast_panel.modulate.a = 1
	_toast_time = seconds

func _on_stage_completed(_quest: String, title: String) -> void:
	_play("objective")
	toast("完成：" + title)
	_hint_time = 8.0

func _on_chapter_completed(title: String, outro: String) -> void:
	banner_title.text = title + " · 完"
	banner_body.text = outro
	banner.visible = true
	banner.modulate.a = 1
	_banner_time = 7.0

func _on_arrived(target: String) -> void:
	_play("arrive")
	toast("到了：" + content.registry.target_name(target), 2.5)
	_hint_time = 8.0

func _process(delta: float) -> void:
	var world: Node3D = content.world
	var idle: bool = world.interactions.mode == "idle"
	var cozy = world.get("activities")
	var photo: bool = cozy != null and bool(cozy.photo)
	var scene = world.get("scene_actions")
	var vista: bool = scene != null and scene.has_method("in_vista") and scene.in_vista()
	visible = not photo and not world.interactions.mode in ["dialogue", "scope", "journal"] and not _performing() and not vista
	var audio = world.get("audio")
	var guide_on: bool = audio == null or bool(audio.settings.get("guide", true))
	var prompts_on: bool = audio == null or bool(audio.settings.get("prompts", true))
	chip.visible = idle and (not content.director.tracked().is_empty() or content.state.data.guide_target != "")
	if chip.visible:
		var target: String = content.guide.target
		var has_route: bool = guide_on and target != "" and content.guide.route.size() > 0
		chip_arrow.visible = has_route
		chip_route.text = (("先去码头乘飞艇 · " if content.guide.via != "" else "") + "%d 米" % int(round(content.guide.remaining)) + ("（直线距离）" if content.guide.straight else "")) if has_route else ("路线已关闭 · Q 打开" if target != "" else "")
		var hop: String = content.guide.hop_ahead() if has_route else ""
		if hop != "":chip_route.text += " · 前面的矮台阶按空格跳上去" if hop == "up" else " · 前面有矮台阶，可以直接走下去"
		chip_arrow.queue_redraw()
		var near: bool = target != "" and world.player.global_position.distance_to(content.registry.target_position(target)) < content.registry.target_radius(target) * 1.6
		var tracked: Dictionary = content.director.tracked()
		chip_hint.visible = prompts_on and not tracked.is_empty() and (near or _hint_time > 0) and content.state.data.guide_target == ""
		if chip_hint.visible:chip_hint.text = tracked.hint
	_hint_time = maxf(0, _hint_time - delta)
	prompt.visible = idle and prompts_on and content.examine_target != ""
	if prompt.visible:prompt.text = content.examines.prompt(content.examine_entry)
	_whisper_time = maxf(0, _whisper_time - delta)
	if _whisper_time <= 0 and not _whispers.is_empty() and not _performing() and content.state.flag("xiaoguang") and open_panel == "":
		whisper_label.text = "✦ 小光：" + String(_whispers.pop_front())
		_whisper_time = 5.5
	whisper_panel.visible = _whisper_time > 0 and open_panel == ""
	whisper_panel.modulate.a = clampf(_whisper_time / .8, 0, 1) * clampf((5.5 - _whisper_time) / .4, 0, 1)
	# the flight and the ending are cinematic: only whispers stay on screen
	var cinematic: bool = (content.airship != null and content.airship.flying()) or (content.ending != null and content.ending.playing)
	menu.visible = (idle or open_panel != "") and not cinematic
	if cinematic:chip.visible = false
	if _toast_time > 0:
		_toast_time -= delta
		toast_panel.modulate.a = clampf(_toast_time / .6, 0, 1)
		toast_panel.visible = _toast_time > 0 and open_panel == ""
	elif not _toasts.is_empty() and not _performing():
		var next: Array = _toasts.pop_front()
		# a message that waited too long is about somewhere the player already left
		if Time.get_ticks_msec() - int(next[2]) < 7000:toast(next[0], next[1])
	_banner_time = maxf(0, _banner_time - delta)
	banner.modulate.a = clampf(_banner_time / 1.0, 0, 1)
	banner.visible = _banner_time > 0 and open_panel == ""

func _performing() -> bool:
	var perf = content.world.get("performance")
	return perf != null and perf.busy

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if _performing():return
	var world: Node3D = content.world
	var cozy = world.get("activities")
	if cozy and cozy.photo:return
	var mode: String = world.interactions.mode
	if not mode in ["idle", "content"]:return
	var key: int = event.physical_keycode
	var handled := true
	if open_panel == "note":
		if key in [KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:_turn_note()
		elif key == KEY_ESCAPE:
			close_panel()
			note_closed.emit()
		get_viewport().set_input_as_handled()
		return
	match key:
		KEY_ESCAPE:
			if open_panel == "title":free_roam()
			elif open_panel != "":close_panel()
			else:handled = false
		KEY_P:toggle_panel("story")
		KEY_N:toggle_panel("map")
		KEY_Y:toggle_panel("settings")
		KEY_H:toggle_panel("help")
		KEY_Q:
			if open_panel == "":toggle_guide()
		KEY_E:
			if open_panel == "" and content.examine_target != "" and world.interactions.active_target == "":content.examine(content.examine_target)
			else:handled = open_panel != ""
		_:handled = open_panel != "" and key != KEY_M
	if handled:get_viewport().set_input_as_handled()
