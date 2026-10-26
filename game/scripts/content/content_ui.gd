extends CanvasLayer
## Story entry, objective chip, story book, map, sound settings and help.
## Panels are light cards over the scenery; one at a time; Esc closes.
## Keys: P 故事本 · N 地图 · Y 设置 · H 帮助 · Q 指引开关 · E 看看（小摊等）
const MapView := preload("res://scripts/content/map_view.gd")
const INK := Color("fff4dc")
const SOFT := Color("d8d2c4")
const ACCENT := Color("ffd27d")
## Shown from the title card and the help panel ("关于与免责声明"); the same text is in
## 免责声明.md at the project root.
const ABOUT := """[b]关于这个游戏[/b]
《星星人的小世界》是密斯特李发起的[b]非商业、免费、开源[/b]的爱好者作品，仅供学习与交流。

[b]免责声明[/b]
· 游戏中“星星人”相关的名称与形象，其权利归原权利人所有。本作是爱好者自发制作的作品，与原权利人没有任何关联，也没有得到其授权或认可。
· 本作不出售、不收费、不含广告、不接受打赏，也不用于任何商业用途。转载或分享时请保持免费，并保留这段说明。
· 故事、文字、程序和音乐由作者与 AI 助手（Claude、GPT / Codex）共同创作。字体“霞鹜文楷”采用 SIL Open Font License 1.1；其余素材的授权见游戏目录 docs 中的说明。
· 如果权利人或任何人认为本作有不妥之处，请通过本作的发布页面联系作者，我们会第一时间修改或下架。

[b]制作[/b]
作者 · 游戏设计：密斯特李
剧本 · 程序 · 音乐：Claude
场景 · 角色 · 镜头：GPT（Codex）"""
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
var font: Font
var chip: PanelContainer
var chip_heading: Label
var chip_title: Label
var chip_route: Label
var chip_arrow: Control
var chip_hint: RichTextLabel
## 小光's brightness, one star per warm deed (xiaoguang.gd DEEDS); a toast when it grows.
var glow_meter: Label
var _glow_level := -1
var _glow_clock := 0.0
var toast_panel: PanelContainer
var toast_label: Label
var banner: PanelContainer
var banner_title: Label
var banner_body: Label
var prompt: Button
var menu: HBoxContainer
var title_card: PanelContainer
var about_panel: PanelContainer
var name_edit: LineEdit
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
var _whisper_total := 6.0
var _pending_card := -1
var _pending_finished := -1
var _banner_time := 0.0
var _hint_time := 0.0

func _ready() -> void:
	name = "ContentUI"
	layer = 3
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = preload("res://assets/fonts/LXGWWenKai-Regular.ttf")
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.starworldFontCheck = " + JSON.stringify({"bundledPrimary": font is FontFile, "playerName":font.has_char(0x4ed4), "filledStar":font.has_char(0x2605), "emptyStar":font.has_char(0x2606)}))
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
	_build_title_backdrop()
	_build_story()
	_build_map()
	_build_settings()
	_build_help()
	_build_about()
	_build_note()
	_build_whisper()
	content.director.objective_changed.connect(refresh)
	content.director.stage_completed.connect(_on_stage_completed)
	content.director.chapter_completed.connect(_on_chapter_completed)
	content.director.message.connect(func(text):toast(text))
	content.guide.arrived.connect(_on_arrived)
	refresh()
	_boot_card()
	if bool(content.state.data.get("autostart", false)):
		content.state.data.autostart = false
		start_story.call_deferred()
	elif not "--visual-review" in OS.get_cmdline_user_args():
		_open("title")
	elif content.state.data.mode == "":
		title_card.visible = true

## The loading screen: the name, a short disclaimer and "正在准备小岛" while the island
## settles (the walk grid bakes in the first frames); fades out after about four seconds.
func _boot_card() -> void:
	# The HTML shell already owns the web loading cover.
	if OS.has_feature("web"):return
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--visual-review" in args or "--test-session" in args or "--autotest" in args:return
	var veil := ColorRect.new()
	veil.name = "BootVeil"
	veil.color = Color(.05, .06, .12, 1)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(veil)
	var picture := _art("loading_screen.jpg")
	if picture:
		veil.add_child(picture)
		var shade := ColorRect.new()
		shade.color = Color(.04, .03, .08, .35)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		veil.add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 14)
	veil.add_child(box)
	var logo := _logo(Vector2(560, 280))
	if logo:box.add_child(logo)
	else:
		var title := _label("星星人的小世界", 40, ACCENT)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(title)
	var loading := _label("正在准备小岛……", 18, SOFT)
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(loading)
	var gap := Control.new()
	gap.custom_minimum_size.y = 30
	box.add_child(gap)
	var legal := _label("非商业、免费的爱好者作品，仅供学习与交流。\n“星星人”相关名称与形象归原权利人所有，本作与原权利人无关，也未获授权。\n完整说明见 帮助（H）→ 关于与免责声明。", 14, Color(.8, .78, .72))
	legal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legal.custom_minimum_size.x = 640
	legal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(legal)
	var t := create_tween()
	t.tween_interval(4.0)
	t.tween_property(veil, "modulate:a", 0.0, 1.2)
	t.tween_callback(veil.queue_free)

## The painted art (assets/ui): a picture filling the screen, cropped to keep its aspect.
const ART := "res://assets/ui/"

func _art(file: String) -> TextureRect:
	if not ResourceLoader.exists(ART + file):return null
	var rect := TextureRect.new()
	rect.texture = load(ART + file)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _logo(size: Vector2) -> TextureRect:
	if not ResourceLoader.exists(ART + "game_logo.png"):return null
	var rect := TextureRect.new()
	rect.texture = load(ART + "game_logo.png")
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

## The home screen: the painted island behind the title card, the logo above it.
var title_backdrop: Control

func _build_title_backdrop() -> void:
	title_backdrop = Control.new()
	title_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_backdrop.visible = false
	root.add_child(title_backdrop)
	root.move_child(title_backdrop, 0)
	var picture := _art("home_key_visual.jpg")
	if picture:title_backdrop.add_child(picture)
	var logo := _logo(Vector2(560, 280))
	if logo:
		# in the middle of the screen, the card right under it
		logo.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		logo.offset_left = -280
		logo.offset_right = 280
		logo.offset_top = -250
		logo.offset_bottom = 30
		title_backdrop.add_child(logo)

## Between chapters, at the player's pace: first the end of the chapter just finished
## (its name and closing words on a cream card, "翻开下一章"), then the next chapter's
## painting with its name, its first line and a "开始" button. Nothing moves on by itself.
## index is the chapter about to begin; finished = the one that just ended (-1: none).
var chapter_card: Control
var _card_skip := false
signal chapter_card_done
const CHAPTER_NUMBERS := ["一", "二", "三", "四", "五"]

func show_chapter_card(index: int, finished := -1) -> void:
	var director = content.director
	if index < 0 or index >= director.main.size() or content.test_session:return
	if is_instance_valid(chapter_card):chapter_card.queue_free()
	var player: CharacterBody3D = content.world.player
	var was_locked: bool = player.controls_locked
	player.controls_locked = true
	var mouse := Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	chapter_card = Control.new()
	chapter_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chapter_card.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(chapter_card)
	if finished >= 0 and finished < director.main.size():
		var dim := ColorRect.new()
		dim.color = Color(.06, .05, .12, .55)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		chapter_card.add_child(dim)
		var done: Dictionary = director.main[finished]
		var page := _chapter_page(String(done.title).replace("第", "").split(" · ")[0], "第%s章 · 完" % CHAPTER_NUMBERS[finished], String(done.outro), "翻开下一章")
		chapter_card.add_child(page)
		await _fade_page(page)
		page.queue_free()
		dim.queue_free()
	var file := "chapter_%02d.jpg" % (index + 1)
	var art := _art(file)
	if art:chapter_card.add_child(art)
	var shade := ColorRect.new()
	shade.color = Color(.05, .04, .1, .18)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chapter_card.add_child(shade)
	var chapter: Dictionary = director.main[index]
	var opening := _chapter_page("", String(chapter.title), content.named(String(chapter.intro)), "开始第%s章" % CHAPTER_NUMBERS[index])
	opening.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	opening.offset_top = -250
	opening.offset_bottom = -40
	opening.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chapter_card.add_child(opening)
	await _fade_page(opening, chapter_card)
	chapter_card.queue_free()
	player.controls_locked = was_locked
	Input.mouse_mode = mouse
	chapter_card_done.emit()

## A cream card with a title, a line of story and one button; returned unparented.
func _chapter_page(_kicker: String, title: String, line: String, button_text: String) -> PanelContainer:
	var page := PanelContainer.new()
	page.add_theme_stylebox_override("panel", Cozy.card(.95, 26, 36))
	page.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	page.grow_horizontal = Control.GROW_DIRECTION_BOTH
	page.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size.x = 600
	page.add_child(box)
	box.add_child(Cozy.label(title, 36))
	box.add_child(Cozy.StarRow.new(3))
	var words := Cozy.label(line, 21, Cozy.INK_SOFT)
	words.custom_minimum_size.x = 560
	box.add_child(words)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var go := Cozy.button(button_text + "  →", func():_card_skip = true, true, 21)
	go.custom_minimum_size.x = 220
	row.add_child(go)
	return page

## Fades `node` (or `fade`) in, waits for the button (or E / Enter / Space), fades out.
func _fade_page(node: Control, fade: Control = null) -> void:
	var target: Control = fade if fade else node
	target.modulate.a = 0
	_card_skip = false
	var t := create_tween()
	t.tween_property(target, "modulate:a", 1.0, .6)
	while not _card_skip:
		await get_tree().process_frame
	t = create_tween()
	t.tween_property(target, "modulate:a", 0.0, .45)
	await t.finished

## First steps: the basic controls one at a time in a small card above the bottom edge.
## Each waits until the player has tried it (or a few seconds for the ones you only need
## to know), ticks, fades, and the next comes. Shown once (flag "tutorial_done").
const TUTORIAL := [
	["W A S D 或 方向键  走一走", "move"],
	["点一下画面，再移动鼠标  转动视角 · 滚轮  拉近拉远", "look"],
	["按住 Shift  跑起来", "run"],
	["空格  跳一下（矮台阶要跳上去）", "jump"],
	["E  和人说话、看看发光的东西", "wait"],
	["N  地图 · P  故事本 · H  全部按键 · T  换天色", "wait"],
]
var tutorial_card: PanelContainer
var tutorial_label: RichTextLabel
var _tutorial := -1
var _tutorial_clock := 0.0
var _tutorial_start := Vector3.ZERO
var _tutorial_yaw := 0.0
var _tutorial_done := false

func start_tutorial() -> void:
	if content.state.flag("tutorial_done") or content.test_session or _tutorial >= 0:return
	if not is_instance_valid(tutorial_card):
		tutorial_card = PanelContainer.new()
		tutorial_card.add_theme_stylebox_override("panel", Cozy.card(.9, 22, 18))
		tutorial_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		tutorial_card.offset_left = -330
		tutorial_card.offset_right = 330
		tutorial_card.offset_top = -168
		tutorial_card.offset_bottom = -110
		tutorial_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
		tutorial_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
		tutorial_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tutorial_card)
		tutorial_label = RichTextLabel.new()
		tutorial_label.bbcode_enabled = true
		tutorial_label.fit_content = true
		tutorial_label.scroll_active = false
		tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tutorial_label.custom_minimum_size.x = 620
		tutorial_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tutorial_label.add_theme_font_override("normal_font", Cozy.hand())
		tutorial_label.add_theme_font_override("bold_font", Cozy.hand())
		tutorial_label.add_theme_font_size_override("normal_font_size", 21)
		tutorial_label.add_theme_font_size_override("bold_font_size", 21)
		tutorial_label.add_theme_color_override("default_color", Cozy.INK)
		tutorial_card.add_child(tutorial_label)
	_tutorial = 0
	_tutorial_next()

func _tutorial_next() -> void:
	if _tutorial >= TUTORIAL.size():
		content.state.set_flag("tutorial_done")
		content.state.save()
		create_tween().tween_property(tutorial_card, "modulate:a", 0.0, .8)
		_tutorial = TUTORIAL.size()
		return
	var player: CharacterBody3D = content.world.player
	_tutorial_start = player.global_position
	_tutorial_yaw = player.cam_yaw
	_tutorial_clock = 0.0
	_tutorial_done = false
	tutorial_label.text = "[center]" + _key_caps(String(TUTORIAL[_tutorial][0])) + "[/center]"
	tutorial_card.modulate.a = 0
	create_tween().tween_property(tutorial_card, "modulate:a", 1.0, .6)

## Key names drawn as small warm key caps.
func _key_caps(text: String) -> String:
	var out := text
	for key in ["W A S D", "Shift", "空格", "方向键", "滚轮"]:
		out = out.replace(key, "[bgcolor=#f3d7ae][color=#5b3f2c] " + key + " [/color][/bgcolor]")
	var caps := RegEx.new()
	caps.compile("(?<![A-Za-z])([ENPHT])(?![A-Za-z])")
	return caps.sub(out, "[bgcolor=#f3d7ae][color=#5b3f2c] $1 [/color][/bgcolor]", true)

func _tutorial_process(delta: float) -> void:
	if _tutorial < 0 or _tutorial >= TUTORIAL.size():return
	tutorial_card.visible = content.world.interactions.mode == "idle" and open_panel == "" and not showing_card()
	if not tutorial_card.visible:return
	_tutorial_clock += delta
	var player: CharacterBody3D = content.world.player
	var kind := String(TUTORIAL[_tutorial][1])
	var done := false
	match kind:
		"move":done = player.global_position.distance_to(_tutorial_start) > 3.0
		"look":done = absf(angle_difference(player.cam_yaw, _tutorial_yaw)) > .7 or _tutorial_clock > 14.0
		"run":done = Input.is_action_pressed("run") and Vector2(player.velocity.x, player.velocity.z).length() > 3.0 or _tutorial_clock > 14.0
		"jump":done = Input.is_action_pressed("jump") or not player.is_on_floor() or _tutorial_clock > 12.0
		"wait":done = _tutorial_clock > 6.0
	if done and not _tutorial_done:
		_tutorial_done = true
		tutorial_label.text = "[center]" + _key_caps(String(TUTORIAL[_tutorial][0])) + "  [color=#5aa06a]✓[/color][/center]"
		var t := create_tween()
		t.tween_interval(.8)
		t.tween_property(tutorial_card, "modulate:a", 0.0, .6)
		t.tween_callback(func():
			_tutorial += 1
			_tutorial_next())

func showing_card() -> bool:
	return is_instance_valid(chapter_card)

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
## The quest box, the one thing a player must always be able to read: the chapter in
## small type, the objective large and bold, the distance, and how to do it with its
## keys picked out. It sits apart from every other text at the top centre.
func _build_chip() -> void:
	chip = PanelContainer.new()
	var style := _box(Color(.10, .12, .22, .84), 14, 22, 10)
	style.border_color = Color(1, .84, .5, .75)
	style.border_width_left = 5
	style.border_width_bottom = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.shadow_color = Color(0, 0, 0, .25)
	style.shadow_size = 8
	chip.add_theme_stylebox_override("panel", style)
	chip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	chip.offset_left = -300
	chip.offset_right = 300
	chip.offset_top = 10
	chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:toggle_panel("story"))
	root.add_child(chip)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	chip.add_child(box)
	chip_heading = _label("", 14, SOFT)
	chip_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(chip_heading)
	chip_title = _label("", 25, ACCENT)
	var bold := preload("res://assets/fonts/LXGWWenKai-Regular.ttf")
	chip_title.add_theme_font_override("font", bold)
	chip_title.add_theme_constant_override("outline_size", 6)
	chip_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chip_title.custom_minimum_size.x = 540
	box.add_child(chip_title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	chip_arrow = Control.new()
	chip_arrow.custom_minimum_size = Vector2(20, 20)
	chip_arrow.draw.connect(_draw_arrow)
	row.add_child(chip_arrow)
	chip_route = _label("", 16, ACCENT)
	row.add_child(chip_route)
	chip_hint = RichTextLabel.new()
	chip_hint.bbcode_enabled = true
	chip_hint.fit_content = true
	chip_hint.scroll_active = false
	chip_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chip_hint.custom_minimum_size.x = 540
	chip_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_hint.add_theme_font_size_override("normal_font_size", 17)
	chip_hint.add_theme_font_size_override("bold_font_size", 17)
	chip_hint.add_theme_font_override("bold_font", bold)
	chip_hint.add_theme_color_override("default_color", Color("f2ead8"))
	chip_hint.add_theme_color_override("font_outline_color", Color(.08, .1, .18, .85))
	chip_hint.add_theme_constant_override("outline_size", 4)
	box.add_child(chip_hint)
	glow_meter = _label("", 15, Color("ffd98a"))
	glow_meter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glow_meter.visible = false
	box.add_child(glow_meter)

## "按 T 换天色" -> the T drawn as a gold key cap, so the key to press stands out.
var _key_pattern: RegEx

func keys_bbcode(text: String) -> String:
	if _key_pattern == null:
		_key_pattern = RegEx.new()
		_key_pattern.compile("(?<![A-Za-z])(Esc|Tab|Enter|Shift|空格|[A-Z])(?![A-Za-z])")
	var safe := text.replace("[", "［").replace("]", "］")
	return _key_pattern.sub(safe, "[bgcolor=#5a4520][color=#ffd27d][b] $1 [/b][/color][/bgcolor]", true)

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

## The home screen: the logo in the middle of the painting, and right under it a cream
## card with the usual entries: continue, new game (asks for the name; over a story in
## progress it asks once more), wander, settings, about, quit.
const Cozy := preload("res://scripts/content/cozy_style.gd")
var title_menu: VBoxContainer
var title_naming: VBoxContainer
var title_new_button: Button
var _new_confirm := false

func _build_title_card() -> void:
	title_card = PanelContainer.new()
	title_card.add_theme_stylebox_override("panel", Cozy.card(.93, 28, 30))
	title_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title_card.offset_left = -250
	title_card.offset_right = 250
	title_card.offset_top = 40
	title_card.offset_bottom = 300
	title_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title_card.grow_vertical = Control.GROW_DIRECTION_END
	title_card.visible = false
	root.add_child(title_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	title_card.add_child(box)
	box.add_child(Cozy.label("云海上的星星岛。一颗小星星，今晚要掉下来了。", 19, Cozy.INK_SOFT))
	box.add_child(Cozy.StarRow.new(3))
	title_menu = VBoxContainer.new()
	title_menu.add_theme_constant_override("separation", 10)
	box.add_child(title_menu)
	title_naming = VBoxContainer.new()
	title_naming.add_theme_constant_override("separation", 12)
	title_naming.visible = false
	box.add_child(title_naming)
	var naming := HBoxContainer.new()
	naming.alignment = BoxContainer.ALIGNMENT_CENTER
	naming.add_theme_constant_override("separation", 12)
	title_naming.add_child(naming)
	var ask := Cozy.label("你的星星人叫", 21)
	ask.autowrap_mode = TextServer.AUTOWRAP_OFF
	naming.add_child(ask)
	name_edit = LineEdit.new()
	name_edit.text = content.player_name()
	name_edit.max_length = 8
	name_edit.custom_minimum_size = Vector2(170, 44)
	name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.add_theme_font_override("font", Cozy.hand())
	name_edit.add_theme_font_size_override("font_size", 22)
	name_edit.add_theme_color_override("font_color", Cozy.INK)
	var field := StyleBoxFlat.new()
	field.bg_color = Color("fffdf7")
	field.border_color = Cozy.PAPER_EDGE
	field.set_border_width_all(2)
	field.set_corner_radius_all(14)
	field.content_margin_left = 12
	field.content_margin_right = 12
	name_edit.add_theme_stylebox_override("normal", field)
	name_edit.add_theme_stylebox_override("focus", field)
	name_edit.text_submitted.connect(func(_t):_begin_new_game())
	naming.add_child(name_edit)
	var go := HBoxContainer.new()
	go.alignment = BoxContainer.ALIGNMENT_CENTER
	go.add_theme_constant_override("separation", 14)
	title_naming.add_child(go)
	go.add_child(Cozy.button("出发吧", _begin_new_game, true))
	go.add_child(Cozy.button("返回", func():_show_title_menu()))
	panels["title"] = title_card
	_show_title_menu()

func _show_title_menu() -> void:
	_new_confirm = false
	title_naming.visible = false
	title_menu.visible = true
	for child in title_menu.get_children():child.queue_free()
	var started: bool = content.state.data.started or content.state.data.mode == "free"
	var rows := [
		[["继续游戏", _continue_game, true]] if started else [],
		[["新游戏", _ask_new_game, not started], ["先随便走走", free_roam, false]],
		[["设置", _title_settings, false], ["关于与声明", show_about, false], ["退出游戏", func():preload("res://scripts/web_platform.gd").exit_game(get_tree()), false]],
	]
	for row_spec in rows:
		if row_spec.is_empty():continue
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		title_menu.add_child(row)
		for spec in row_spec:
			var b := Cozy.button(spec[0], spec[1], spec[2], 22 if spec[2] else 19)
			if spec[0] == "新游戏":title_new_button = b
			if row_spec.size() == 1:b.custom_minimum_size.x = 320
			row.add_child(b)
	if started:
		var where := Cozy.label("上次停在：" + String(content.director.chapter().get("title", "")), 15, Cozy.INK_SOFT, false)
		title_menu.add_child(where)

func _continue_game() -> void:
	if content.state.data.started:start_story()
	else:free_roam()

func _ask_new_game() -> void:
	# over a story in progress, the first press asks again
	if content.state.data.started and not _new_confirm:
		_new_confirm = true
		title_new_button.text = "从头开始？再点一次"
		return
	title_menu.visible = false
	title_naming.visible = true
	name_edit.grab_focus()

## A fresh story: the save starts over (name kept), flowers and star charts too, and the
## island is reloaded so everything lit goes dark again; then the story begins at once.
func _begin_new_game() -> void:
	var typed := name_edit.text.strip_edges()
	if not content.state.data.started:
		start_story()
		return
	content.state.reset()
	content.state.data.player_name = typed if not typed.is_empty() else "星仔"
	content.state.data.autostart = true
	content.state.save()
	var cozy = content.world.get("activities")
	if cozy:
		cozy.progress = {"flowers": 0, "watered": false, "moments": []}
		cozy.mark("新的故事")
	var talk = content.world.interactions
	talk.journal.stars.clear()
	talk._save_journal()
	get_tree().reload_current_scene()

var _settings_from_title := false

func _title_settings() -> void:
	_settings_from_title = true
	_open("settings")

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
	var box := _panel("settings", "声音与指引", 520, 480)
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
	var naming := HBoxContainer.new()
	naming.add_theme_constant_override("separation", 10)
	naming.add_child(_label("名字", 17))
	naming.get_child(0).custom_minimum_size.x = 90
	var field := LineEdit.new()
	field.text = content.player_name()
	field.max_length = 8
	field.custom_minimum_size.x = 160
	field.text_submitted.connect(func(t):rename(t))
	naming.add_child(field)
	naming.add_child(_button("改名", func():rename(field.text), 15))
	box.add_child(naming)
	box.add_child(_label("设置单独保存，不影响故事进度。", 13, SOFT))

func _set_option(key: String, on: bool) -> void:
	var audio = content.world.get("audio")
	if not audio:return
	if key == "muted":
		if bool(audio.settings.muted) != on:audio.toggle_mute()
	else:
		audio.set_option(key, on)
	refresh()

## The about / disclaimer card: an overlay with its own close button, so opening it from
## the title card leaves the title card where it was.
func _build_about() -> void:
	about_panel = PanelContainer.new()
	about_panel.add_theme_stylebox_override("panel", _card())
	about_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	about_panel.offset_left = -330
	about_panel.offset_right = 330
	about_panel.offset_top = -250
	about_panel.offset_bottom = 250
	about_panel.visible = false
	root.add_child(about_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	about_panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_child(_label("关于与免责声明", 22))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(_button("关闭", func():about_panel.visible = false))
	box.add_child(head)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.scroll_active = true
	text.custom_minimum_size = Vector2(610, 410)
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_font_size_override("bold_font_size", 16)
	text.add_theme_color_override("default_color", INK)
	text.text = ABOUT
	box.add_child(text)

func show_about() -> void:
	about_panel.visible = true
	about_panel.move_to_front()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

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
	box.add_child(_button("关于与免责声明", show_about, 14))

## Letter paper for letters, signs and things written down; E / Enter / click turns the
## page. A letter (a title with 信 or 封 in it) first arrives in an envelope: it slides up,
## the star seal breaks, the flap opens and the paper unfolds; E skips that.
const HAND_FONT := "res://assets/fonts/LXGWWenKai-Regular.ttf"
var envelope
var _note_anim: Tween

func _hand_font() -> Font:
	var font: Font = load(HAND_FONT) if ResourceLoader.exists(HAND_FONT) else null
	if font == null:
		var system := preload("res://assets/fonts/LXGWWenKai-Regular.ttf")
		return system
	return font

func _build_note() -> void:
	note_panel = PanelContainer.new()
	note_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	note_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	# a portrait page from the painted notebook, a fountain pen resting beside it
	note_panel.offset_left = -250
	note_panel.offset_right = 250
	note_panel.offset_top = -330
	note_panel.offset_bottom = 330
	note_panel.visible = false
	note_panel.resized.connect(func():note_panel.pivot_offset = note_panel.size / 2)
	note_panel.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:_turn_note())
	root.add_child(note_panel)
	var shadow := Panel.new()
	var soft := StyleBoxFlat.new()
	soft.bg_color = Color(0, 0, 0, 0)
	soft.shadow_color = Color(.2, .12, .25, .35)
	soft.shadow_size = 22
	soft.shadow_offset = Vector2(4, 10)
	soft.set_corner_radius_all(10)
	shadow.add_theme_stylebox_override("panel", soft)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_panel.add_child(shadow)
	var paper: Control
	if ResourceLoader.exists(ART + "letter_page.jpg"):
		var page := TextureRect.new()
		page.texture = load(ART + "letter_page.jpg")
		page.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		page.stretch_mode = TextureRect.STRETCH_SCALE
		paper = page
	else:
		var plain := ColorRect.new()
		var shader := ShaderMaterial.new()
		shader.shader = load("res://shaders/letter_paper.gdshader")
		plain.material = shader
		paper = plain
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_panel.add_child(paper)
	var decor := Control.new()
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_panel.add_child(decor)
	var pen := FountainPen.new()
	pen.position = Vector2(468, 470)
	pen.rotation = -.62
	decor.add_child(pen)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 54)
	margin.add_theme_constant_override("margin_right", 46)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 44)
	note_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	var hand := _hand_font()
	note_title = Label.new()
	note_title.add_theme_font_override("font", hand)
	note_title.add_theme_font_size_override("font_size", 28)
	note_title.add_theme_color_override("font_color", Color("7a4a26"))
	box.add_child(note_title)
	note_body = Label.new()
	note_body.add_theme_font_override("font", hand)
	note_body.add_theme_font_size_override("font_size", 23)
	note_body.add_theme_color_override("font_color", Color("33261b"))
	note_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_body.custom_minimum_size = Vector2(390, 420)
	note_body.add_theme_constant_override("line_spacing", 9)
	note_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(note_body)
	note_hint = Label.new()
	note_hint.add_theme_font_size_override("font_size", 14)
	note_hint.add_theme_color_override("font_color", Color("9a8668"))
	note_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(note_hint)
	panels["note"] = note_panel
	envelope = preload("res://scripts/content/letter_envelope.gd").new()
	envelope.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	envelope.offset_left = -210
	envelope.offset_right = 210
	envelope.offset_top = -130
	envelope.offset_bottom = 130
	envelope.pivot_offset = Vector2(210, 130)
	envelope.visible = false
	root.add_child(envelope)

## The paper (and for a letter, its envelope) arriving; E or a click finishes it at once.
func _animate_note(letter: bool) -> void:
	if _note_anim and _note_anim.is_valid():_note_anim.kill()
	note_panel.modulate.a = 0.0
	note_panel.scale = Vector2.ONE * (.55 if letter else .92)
	_note_anim = create_tween()
	if letter:
		envelope.visible = true
		envelope.modulate.a = 1.0
		envelope.flap = 0.0
		envelope.seal = 1.0
		envelope.position.y = envelope.get_parent_area_size().y / 2 - 130 + 420
		var rest: float = envelope.get_parent_area_size().y / 2 - 130
		_note_anim.tween_property(envelope, "position:y", rest, .4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_note_anim.tween_property(envelope, "seal", 0.0, .22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		_note_anim.tween_property(envelope, "flap", 1.0, .28)
		_note_anim.tween_property(note_panel, "modulate:a", 1.0, .35)
		_note_anim.parallel().tween_property(note_panel, "scale", Vector2.ONE, .4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_note_anim.parallel().tween_property(envelope, "modulate:a", 0.0, .3)
		_note_anim.tween_callback(func():envelope.visible = false)
	else:
		_note_anim.tween_property(note_panel, "modulate:a", 1.0, .2)
		_note_anim.parallel().tween_property(note_panel, "scale", Vector2.ONE, .22).set_trans(Tween.TRANS_SINE)

func _finish_note_animation() -> bool:
	if not (_note_anim and _note_anim.is_valid() and _note_anim.is_running()):return false
	_note_anim.kill()
	note_panel.modulate.a = 1.0
	note_panel.scale = Vector2.ONE
	envelope.visible = false
	return true

func show_note(title: String, lines: Array) -> void:
	if lines.is_empty():return
	note_lines = lines
	note_index = 0
	note_title.text = title
	_show_note_line()
	if not _open("note"):
		toast(" ".join(lines), 6.0)
		return
	_animate_note("信" in title or "封" in title)
	_play("page")
	await note_closed

func _show_note_line() -> void:
	# each E brings the next paragraph onto the same page, like reading down a letter
	var shown: Array[String] = []
	for i in note_index + 1:shown.append(content.named(String(note_lines[i])))
	note_body.text = "\n".join(shown)
	note_hint.text = ("E 继续  %d / %d" % [note_index + 1, note_lines.size()]) if note_index < note_lines.size() - 1 else "E 合上"

func _turn_note() -> void:
	if _finish_note_animation():return
	note_index += 1
	if note_index >= note_lines.size():
		close_panel()
		note_closed.emit()
		return
	_play("page")
	_show_note_line()

## 小光 speaks: its own night-blue card with a glowing border and the handwriting font,
## above the toasts; one line at a time, with a short pause between lines so they never
## pile up.
func _build_whisper() -> void:
	whisper_panel = PanelContainer.new()
	var card := _box(Color(.10, .16, .34, .86), 18, 22, 10)
	card.border_color = Color(.75, .86, 1.0, .85)
	card.set_border_width_all(2)
	card.shadow_color = Color(.6, .78, 1.0, .35)
	card.shadow_size = 12
	whisper_panel.add_theme_stylebox_override("panel", card)
	whisper_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	whisper_panel.offset_left = -330
	whisper_panel.offset_right = 330
	whisper_panel.offset_top = -236
	whisper_panel.offset_bottom = -186
	whisper_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	whisper_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	whisper_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	whisper_panel.visible = false
	root.add_child(whisper_panel)
	whisper_label = _label("", 21, Color("e6efff"))
	whisper_label.add_theme_font_override("font", _hand_font())
	whisper_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	whisper_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	whisper_label.custom_minimum_size.x = 600
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
	if _whispers.size() < 3:_whispers.append(content.named(text))

# ------------------------------------------------------------------ open / close
func _can_open() -> bool:
	if content.ending != null and content.ending.playing:return false
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
	_finish_note_animation()
	if open_panel == "settings" and _settings_from_title:
		_settings_from_title = false
		panels.settings.visible = false
		open_panel = "title"
		title_card.visible = true
		return
	panels[open_panel].visible = false
	open_panel = ""
	if content.world.interactions.mode == "content":content.world.interactions.mode = "idle"
	content.world.player.controls_locked = bool(_restore.get("locked", false))
	Input.mouse_mode = _restore.get("mouse", Input.MOUSE_MODE_VISIBLE)
	refresh()

func start_story() -> void:
	close_panel()
	title_card.visible = false
	_take_name()
	var first: bool = not content.state.data.started
	content.director.start_story()
	if first and content.Opening.wanted():await content.opening.play()
	if first:await show_chapter_card(0)
	start_tutorial()
	content.guide.refresh_route(true)
	_hint_time = 10.0

## Keeps the name typed on the title card (empty means the default, 星仔).
func _take_name() -> void:
	if not is_instance_valid(name_edit):return
	var typed := name_edit.text.strip_edges()
	content.state.data.player_name = typed if not typed.is_empty() else "星仔"
	content.state.save()

func rename(typed: String) -> void:
	content.state.data.player_name = typed.strip_edges() if not typed.strip_edges().is_empty() else "星仔"
	content.state.save()
	toast("以后大家都叫你%s。" % content.player_name())

func free_roam() -> void:
	close_panel()
	title_card.visible = false
	_take_name()
	content.director.choose_free_roam()
	start_tutorial()
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
		chip_title.text = "★ " + content.named(String(tracked.title)) + ("  " + tracked.progress if tracked.progress != "" else "")
	if open_panel == "story":_fill_story()

func toast(text: String, seconds := 3.5) -> void:
	text = content.named(text)
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
	if title.begins_with("小故事"):
		banner_title.text = title + " · 完"
		banner_body.text = outro
		banner.visible = true
		banner.modulate.a = 1
		_banner_time = 7.0
		return
	# the main story: the end page and the next chapter wait until the player is free
	var finished: int = int(content.state.data.main.chapter)
	if finished + 1 < content.director.main.size():
		_pending_card = finished + 1
		_pending_finished = finished

func _on_arrived(target: String) -> void:
	_play("arrive")
	toast("到了：" + content.registry.target_name(target), 2.5)
	_hint_time = 8.0

var _web_diag_clock := 0.0
func _process(delta: float) -> void:
	_web_diag_clock += delta
	if OS.has_feature("web") and _web_diag_clock >= .5:
		_web_diag_clock = 0.0
		var buttons: Array = []
		for button in title_card.find_children("*", "Button", true, false):
			if not button.is_visible_in_tree():continue
			var center: Vector2 = button.get_global_rect().get_center()
			buttons.append({"text": button.text, "x": center.x, "y": center.y})
		var controls: Array = []
		for button in root.find_children("*", "Button", true, false):
			if not button.is_visible_in_tree():continue
			var center: Vector2 = button.get_global_rect().get_center()
			controls.append({"text": button.text, "x": center.x, "y": center.y})
		var pos: Vector3 = content.world.player.global_position
		var size: Vector2 = root.size
		JavaScriptBridge.eval("window.starworldUi = " + JSON.stringify({"title": title_card.visible, "booting": is_instance_valid(root.get_node_or_null("BootVeil")), "buttons": buttons, "controls": controls, "about": about_panel.visible, "opening": content.opening.playing, "openingSkip": {"visible": content.opening.skip_button.is_visible_in_tree(), "x": content.opening.skip_button.get_global_rect().get_center().x, "y": content.opening.skip_button.get_global_rect().get_center().y}, "chapter": showing_card(), "locked": content.world.player.controls_locked, "performance": content.world.performance.kind, "performing": content.world.performance.busy, "endingPlaying": content.ending.playing, "endingSky": content.ending.sky_layer.visible, "finale": is_instance_valid(content.ending.finale_panel) and content.ending.finale_panel.visible, "homeReturned": content.state.flag("xiaoguang_home"), "mainDone": content.director.main_done(), "shipAt": content.airship.at, "lanterns": content.ending.lanterns.size(), "width": size.x, "height": size.y, "position": [pos.x, pos.y, pos.z], "panel": open_panel}))
	var world: Node3D = content.world
	var idle: bool = world.interactions.mode == "idle"
	var cozy = world.get("activities")
	var photo: bool = cozy != null and bool(cozy.photo)
	var scene = world.get("scene_actions")
	var vista: bool = scene != null and scene.has_method("in_vista") and scene.in_vista()
	visible = not photo and not world.interactions.mode in ["dialogue", "scope", "journal"] and not _performing() and not vista and not (content.opening != null and content.opening.playing) and not (content.ending != null and content.ending.playing)
	# in the story the quest box is the one thing to read: the journal counters step aside
	var story: bool = content.state.data.mode == "story"
	if cozy and is_instance_valid(cozy.progress_label) and not photo:cozy.progress_label.visible = not story
	if is_instance_valid(world.interactions.status):world.interactions.status.visible = not story
	if is_instance_valid(world.interactions.journal_button):world.interactions.journal_button.visible = not story
	if is_instance_valid(title_backdrop):title_backdrop.visible = title_card.visible or _settings_from_title
	if _pending_card >= 0 and idle and open_panel == "" and not _performing() and not content.airship.flying() and not showing_card():
		var index := _pending_card
		_pending_card = -1
		show_chapter_card(index, _pending_finished)
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
		var tracked: Dictionary = content.director.tracked()
		if not tracked.is_empty() and content.state.data.guide_target == "":
			var title: String = "★ " + content.named(String(tracked.title)) + ("  " + tracked.progress if tracked.progress != "" else "")
			if chip_title.text != title:
				chip_title.text = title
				chip_heading.text = tracked.heading
		chip_hint.visible = not tracked.is_empty() and content.state.data.guide_target == ""
		if chip_hint.visible:
			var shown := keys_bbcode("怎么做：" + content.named(String(tracked.hint)))
			if chip_hint.text != shown:chip_hint.text = shown
	_hint_time = maxf(0, _hint_time - delta)
	_tutorial_process(delta)
	_glow_clock -= delta
	if _glow_clock <= 0:
		_glow_clock = .5
		_update_glow()
	prompt.visible = idle and prompts_on and content.examine_target != ""
	if prompt.visible:prompt.text = content.examines.prompt(content.examine_entry)
	_whisper_time = maxf(0, _whisper_time - delta)
	if _whisper_time <= 0 and not _whispers.is_empty() and not _performing() and content.state.flag("xiaoguang") and open_panel == "":
		var line := String(_whispers.pop_front())
		whisper_label.text = "★ 小光：" + line
		_whisper_time = clampf(3.5 + line.length() * .12, 5.0, 9.0) + 1.2
		_whisper_total = _whisper_time
	# the last 1.2 seconds are a quiet gap before the next line
	whisper_panel.visible = _whisper_time > 1.2 and open_panel == ""
	whisper_panel.modulate.a = clampf((_whisper_time - 1.2) / .8, 0, 1) * clampf((_whisper_total - _whisper_time) / .4, 0, 1)
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

func _update_glow() -> void:
	var light = content.xiaoguang
	var shown: bool = light != null and content.state.flag("xiaoguang") and not content.state.flag("xiaoguang_home")
	glow_meter.visible = shown
	if not shown:return
	var level: int = light.level()
	var total: int = light.DEEDS.size()
	glow_meter.text = "小光的光  " + "★".repeat(level) + "☆".repeat(total - level)
	if _glow_level >= 0 and level > _glow_level:
		toast("★ 小光亮了一点（%d / %d）" % [level, total], 4.0)
	_glow_level = level

func _performing() -> bool:
	var perf = content.world.get("performance")
	return perf != null and perf.busy

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if is_instance_valid(about_panel) and about_panel.visible:
		if event.physical_keycode == KEY_ESCAPE:about_panel.visible = false
		get_viewport().set_input_as_handled()
		return
	if content.ending != null and content.ending.playing:return
	if _performing():return
	var world: Node3D = content.world
	var cozy = world.get("activities")
	if cozy and cozy.photo:return
	var mode: String = world.interactions.mode
	if not mode in ["idle", "content"]:return
	var key: int = event.physical_keycode
	if showing_card():
		if key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:_card_skip = true
		get_viewport().set_input_as_handled()
		return
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
			if open_panel == "title":
				if title_naming.visible:_show_title_menu()
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


## A fountain pen drawn lying on the desk beside the letter: dark lacquer body, gold
## bands and clip, a gold nib with its slit, a little drop of ink.
class FountainPen extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(300, 40)
	func _draw() -> void:
		var body := Color("3b2a4a")
		var shine := Color("6b5480")
		var gold := Color("d9a94e")
		# shadow
		draw_rect(Rect2(14, 16, 232, 18), Color(0, 0, 0, .18))
		# cap end and body
		draw_rect(Rect2(10, 4, 110, 22), body)
		draw_circle(Vector2(10, 15), 11, body)
		draw_rect(Rect2(120, 6, 110, 18), body.darkened(.1))
		draw_rect(Rect2(12, 7, 210, 4), Color(shine, .7))
		# gold bands and clip
		draw_rect(Rect2(112, 4, 8, 22), gold)
		draw_rect(Rect2(30, 4, 5, 22), gold)
		draw_rect(Rect2(36, 0, 60, 5), gold)
		draw_circle(Vector2(96, 3), 3.5, gold)
		# grip and nib
		draw_rect(Rect2(230, 8, 18, 14), Color("2a1f33"))
		var nib := PackedVector2Array([Vector2(248, 7), Vector2(286, 15), Vector2(248, 23)])
		draw_colored_polygon(nib, gold)
		draw_line(Vector2(262, 15), Vector2(285, 15), Color("6e5022"), 1.2)
		draw_circle(Vector2(262, 15), 2.2, Color("6e5022"))
		# a drop of ink
		draw_circle(Vector2(298, 22), 4.0, Color(.18, .16, .35, .8))
