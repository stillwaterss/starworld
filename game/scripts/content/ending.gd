extends Node
## The last two moments of the story.
## release_at_summit(): on the night flight's highest point the player lifts the lantern
## and 小光 flies up into the empty roof star of 归家座.
## play(): back at the tree house, the round window opens onto the night; narration
## cards and a short credit roll over the town, then free roaming goes on.
const NARRATION := [
	"后来，小镇上的人都说，归家座比以前亮了一点。",
	"没有人知道是哪一颗。",
	"芽芽还是每天低头看花，只是傍晚的时候，会多抬一次头。",
	"眠眠在星图的角落写了一行很小的字：新来的你。",
	"你推开那扇小圆窗。它就在那里。",
	"原来回家，不是回到原来的地方，\n是回到有人记得你的地方。",
]
const CREDITS := [
	"星星人的小世界",
	"谢谢你来过。",
	"故事 · 引导 · 音乐　Claude\n场景 · 角色 · 镜头　Codex\n点灯的人　你",
	"小镇还在。随时可以回来走走。",
]

var content
var layer: CanvasLayer
var card: Label
var veil: ColorRect
var playing := false

func _ready() -> void:
	name = "Ending"
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
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -480
	card.offset_right = 480
	card.offset_top = -90
	card.offset_bottom = 90
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_theme_font_size_override("font_size", 28)
	card.add_theme_color_override("font_color", Color("fff1d7"))
	card.add_theme_color_override("font_outline_color", Color(.05, .05, .12, .9))
	card.add_theme_constant_override("outline_size", 6)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Serif CJK SC", "Noto Sans CJK SC", "Source Han Serif SC"])
	font.fallbacks = [preload("res://assets/fonts/NotoSansSC.ttf")]
	card.add_theme_font_override("font", font)
	card.modulate.a = 0
	layer.add_child(card)

func _show(text: String, hold: float, hurry_check := true) -> void:
	card.text = text
	var t := create_tween()
	t.tween_property(card, "modulate:a", 1.0, 1.2)
	await t.finished
	var left := hold
	while left > 0:
		await get_tree().process_frame
		var perf = content.world.get("performance")
		left -= get_process_delta_time() * (4.0 if (hurry_check and perf and perf.hurry) else 1.0)
	t = create_tween()
	t.tween_property(card, "modulate:a", 0.0, 1.0)
	await t.finished

## Called by the airship at the top of the night flight.
func release_at_summit() -> void:
	var world: Node3D = content.world
	var player: CharacterBody3D = world.player
	var perf = world.get("performance")
	var camera: Camera3D = content.airship.camera
	player.model.set_performing(true)
	player.model.set_pose(perf.pose("hug"), 4.0)
	content.ui.whisper("好高啊。……我看见那个空着的位置了。")
	await get_tree().create_timer(2.5).timeout
	player.model.set_pose(perf.pose("hold_up"), 3.0)
	await get_tree().create_timer(1.6).timeout
	content.state.set_flag("reaction_player_star")
	content._apply_reactions()
	var target: Vector3 = content.home_star_point(camera.global_position)
	content.xiaoguang.leave_for(target, 9.0)
	player.model.set_pose(perf.pose("release"), 4.0)
	content.ui.whisper("谢谢你给我浇过花，擦过窗。我会在那里，每天晚上都在。")
	# the camera turns to follow the little light up
	var t := 0.0
	var from := camera.global_transform
	while t < 9.2:
		t += get_process_delta_time()
		var look: Vector3 = content.xiaoguang.global_position
		var goal := from.looking_at(look, Vector3.UP)
		camera.global_transform = camera.global_transform.interpolate_with(goal, clampf(get_process_delta_time() * 1.5, 0, 1))
		await get_tree().process_frame
	player.model.set_pose(perf.pose("look_up"), 2.0)
	if world.get("audio"):world.audio.play_sfx("objective")
	content.events.emit("xiaoguang_home", {"place": "summit"})
	await get_tree().create_timer(3.0).timeout
	player.model.set_performing(false)

## Called from the tree-house window examine in the last stage.
func play() -> void:
	if playing:return
	playing = true
	var world: Node3D = content.world
	var perf = world.get("performance")
	var window := Vector3(0, 2.8, -.3)
	if not perf.begin("ending", window, {"eye": window + Vector3(.4, -.3, 2.2), "look": window, "fov": 42, "time": 1.6}):
		playing = false
		return
	world.day_cycle.set_time(2, 4.0)
	await perf.wait(1.8)
	layer.visible = true
	# pull back and up until the tree, the town and the sky are all in frame
	perf.glide_to(Transform3D(Basis.looking_at(Vector3(4, 9, -30) - Vector3(-9, 7, 26)), Vector3(-9, 7, 26)), 50.0, 14.0)
	for line in NARRATION:await _show(line, 3.4)
	var t := create_tween()
	t.tween_property(veil, "color:a", .55, 2.0)
	for line in CREDITS:await _show(line, 2.6)
	t = create_tween()
	t.tween_property(veil, "color:a", 0.0, 2.0)
	await t.finished
	layer.visible = false
	content.events.emit("ending_seen", {"place": "tree_house"})
	await perf.finish(1.5)
	playing = false
