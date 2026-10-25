extends CanvasLayer
## Photo mode presentation: curated framings near photo spots (Tab cycles, the last
## one is "free"), a light colour filter (1/2/3), thirds grid (G), a shutter flash and
## a thumbnail of the saved picture. cozy_activities keeps the photo flag and camera.
## Shutter keys: Enter, keypad Enter, Space or left click; on Windows an IME can eat
## Enter, so the others always work too.
const SPOTS := "res://data/content/photo_spots.json"
const FILTERS := [
	{"name": "自然", "tint": Color(1, 1, 1, 0), "vignette": .18},
	{"name": "暖阳", "tint": Color(1.0, .82, .55, .12), "vignette": .26},
	{"name": "晚风", "tint": Color(.62, .66, 1.0, .12), "vignette": .30},
]

var cozy
var spots: Array = []
var framings: Array = []        # [{name, eye, target, fov}] for the current shot
var framing := 0
var filter := 0
var grid_on := false
var overlay: ColorRect
var grid: Control
var flash: ColorRect
var hud: Label
var thumb: TextureRect
var thumb_time := 0.0
var flash_time := 0.0
var glide: Tween
var last_saved := ""

func _ready() -> void:
	name = "PhotoStudio"
	layer = 6
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SPOTS)) if FileAccess.file_exists(SPOTS) else null
	if parsed is Dictionary:spots = parsed.get("spots", [])
	overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/photo_grade.gdshader")
	overlay.material = material
	add_child(overlay)
	grid = Control.new()
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.draw.connect(_draw_grid)
	add_child(grid)
	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(1, .98, .92, 0)
	add_child(flash)
	hud = Label.new()
	hud.add_theme_font_size_override("font_size", 17)
	hud.add_theme_color_override("font_color", Color("fff1d7"))
	hud.add_theme_color_override("font_outline_color", Color("20293d"))
	hud.add_theme_constant_override("outline_size", 5)
	hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hud.offset_left = -470
	hud.offset_right = 470
	hud.offset_top = -46
	hud.offset_bottom = -14
	hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var font := preload("res://assets/fonts/LXGWWenKai-Regular.ttf")
	hud.add_theme_font_override("font", font)
	add_child(hud)
	thumb = TextureRect.new()
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	thumb.offset_left = -300
	thumb.offset_right = -24
	thumb.offset_top = 24
	thumb.offset_bottom = 180
	thumb.visible = false
	add_child(thumb)
	visible = false

## Called by cozy when photo mode opens: finds framings for where the player stands.
func begin(from: Transform3D, fov: float) -> void:
	framings.clear()
	var at: Vector3 = cozy.player.global_position
	for spot in spots:
		var center := _v(spot.center)
		if at.distance_to(center) <= float(spot.get("radius", 12)):
			for f in spot.framings:
				framings.append({"name": spot.name + " · " + f.name, "eye": _v(f.eye), "target": _v(f.target), "fov": float(f.get("fov", 45))})
			break
	framings.append({"name": "自由取景", "transform": from, "fov": fov})
	framing = 0
	visible = true
	var lantern: Node3D = cozy.world.scene_actions.lantern
	_lantern_was = is_instance_valid(lantern) and lantern.visible
	# name tags float in the picture; they come back when the camera is put away
	_hidden_tags.clear()
	for tag: Label3D in cozy.world.find_children("*", "Label3D", true, false):
		if tag.visible:
			_hidden_tags.append(tag)
			tag.visible = false
	_apply_framing(false)
	_refresh()

func end() -> void:
	visible = false
	if glide:glide.kill()
	for tag in _hidden_tags:
		if is_instance_valid(tag):tag.visible = true
	_hidden_tags.clear()
	cozy.player.model.visible = true
	var lantern: Node3D = cozy.world.scene_actions.lantern
	if is_instance_valid(lantern):lantern.visible = _lantern_was

func _v(raw) -> Vector3:return Vector3(raw[0], raw[1], raw[2])

func _apply_framing(animate := true) -> void:
	var f: Dictionary = framings[framing]
	var camera: Camera3D = cozy.photo_camera
	var goal: Transform3D = f.transform if f.has("transform") else Transform3D(Basis.looking_at(f.target - f.eye), f.eye)
	if glide:glide.kill()
	if animate:
		glide = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		glide.tween_property(camera, "global_transform", goal, .9)
		glide.tween_property(camera, "fov", f.fov, .9)
	else:
		camera.global_transform = goal
		camera.fov = f.fov

func cycle_framing() -> void:
	framing = (framing + 1) % framings.size()
	_apply_framing()
	_refresh()

func set_filter(index: int) -> void:
	filter = clampi(index, 0, FILTERS.size() - 1)
	_refresh()

func toggle_grid() -> void:
	grid_on = not grid_on
	grid.queue_redraw()

func _refresh() -> void:
	var f: Dictionary = FILTERS[filter]
	overlay.material.set_shader_parameter("tint", f.tint)
	overlay.material.set_shader_parameter("vignette", f.vignette)
	var name_text: String = framings[framing].name if not framings.is_empty() else ""
	hud.text = "取景：%s（Tab 换）· 滤镜：%s（1/2/3）· G 三分线 · 方向键微调 · Enter/空格/左键 拍照 · O 返回" % [name_text, f.name]
	grid.queue_redraw()

func _draw_grid() -> void:
	if not grid_on:return
	var s := grid.size
	for i in [1, 2]:
		grid.draw_line(Vector2(s.x * i / 3.0, 0), Vector2(s.x * i / 3.0, s.y), Color(1, 1, 1, .28), 1.0)
		grid.draw_line(Vector2(0, s.y * i / 3.0), Vector2(s.x, s.y * i / 3.0), Color(1, 1, 1, .28), 1.0)

## Takes the picture: hides the hints, saves (not in test sessions), flashes, shows a thumbnail.
func shoot(write_file: bool) -> String:
	hud.visible = false
	grid.visible = false
	thumb.visible = false
	var image: Image
	if DisplayServer.get_name() == "headless":
		# no frames are drawn headless: a blank card keeps the shutter flow testable
		image = Image.create(64, 36, false, Image.FORMAT_RGBA8)
	else:
		await RenderingServer.frame_post_draw
		image = cozy.get_viewport().get_texture().get_image()
	var path := ""
	if write_file:
		var filename := Time.get_datetime_string_from_system().replace(":", "-") + ".png"
		if OS.has_feature("web"):
			JavaScriptBridge.download_buffer(image.save_png_to_buffer(),filename,"image/png")
			path=filename
		else:
			var folder: String = preload("res://scripts/project_paths.gd").renders("photos")
			DirAccess.make_dir_recursive_absolute(folder)
			path=folder+filename
			image.save_png(path)
	last_saved = path
	hud.visible = true
	grid.visible = true
	thumb.texture = ImageTexture.create_from_image(image)
	thumb.visible = true
	thumb_time = 3.0
	flash_time = .35
	hud.text = ("已保存：" + path.get_file() + "（renders/photos）" if path != "" else "咔嚓！（测试会话不写文件）") + " · 继续拍或 O 返回"
	return path

var _hidden_tags: Array[Label3D] = []
var _lantern_was := false     # the hand lantern hangs off the skeleton, outside the model

func _process(delta: float) -> void:
	# a body right beside the lens only shows up as a blurry edge: step it out of the shot
	# and in a preset framing, out of the line to the subject (the free framing keeps the player)
	if visible:
		var camera: Camera3D = cozy.photo_camera
		var chest: Vector3 = cozy.player.global_position + Vector3.UP * .9
		var to_chest := chest - camera.global_position
		var hide := to_chest.length() < 1.3
		if not framings.is_empty() and framings[framing].has("eye"):
			var ahead := -camera.global_basis.z
			var along := to_chest.dot(ahead)
			# close in front of a composed shot the body is only a cut-off shape at the edge
			hide = hide or (along > 0 and along < 4.0)
		cozy.player.model.visible = not hide
		var lantern: Node3D = cozy.world.scene_actions.lantern
		if is_instance_valid(lantern):lantern.visible = _lantern_was and not hide
	if flash_time > 0:
		flash_time -= delta
		flash.color.a = clampf(flash_time / .35, 0, 1) * .85
	if thumb_time > 0:
		thumb_time -= delta
		thumb.modulate.a = clampf(thumb_time / .6, 0, 1)
		if thumb_time <= 0:
			thumb.visible = false
			_refresh()
