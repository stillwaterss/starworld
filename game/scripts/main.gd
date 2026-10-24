extends Node3D
## 星星人世界 - 可玩白模
## 场景几何来自 Blender 导出的 assets/island.glb; 灯光、环境、碰撞、角色都在这里搭。
## Blender 坐标 (x, y, z) 对应 Godot 坐标 (x, z, -y)。

const ISLAND := preload("res://assets/island.glb")
const PlayerScript := preload("res://scripts/player.gd")

const SPAWN := Vector3(1.5, 1.0, 4.0)   # 略偏右, 身后正好有一根灯柱
## 名字以这些前缀开头的网格不生成碰撞 (云、星空、花、灌木可以穿过去)
const NO_COLLIDE := ["Clouds", "Stars", "Canopy_", "Garden_flower", "Vegetation_bush", "Decor_"]
## 只做碰撞、不显示的网格 (楼梯上的隐形坡道)
const COLLISION_ONLY := ["StairRamps", "Physics_"]
## 细小的障碍物 (灯柱、树、围栏) 放在碰撞层 2
const THIN_PROPS := ["Lamps", "Vegetation", "TreeTrunks", "StarTreeCore", "Decor_WishingTree_trunk", "Telescope", "Dock", "Bridge", "Railings", "Solid_V8", "Solid_V10", "Solid_V11", "Solid_V13", "Physics_"]

var player: CharacterBody3D
var fps_label: Label
var interactions: CanvasLayer
var day_cycle: Node
var activities: CanvasLayer
var audio: Node      # content: day/dusk/night music, ambience, settings
var content: Node    # content: story, guide, map, story UI
var scene_actions: Node3D
var performance: Node3D   # staged moments for everyday actions

func get_scene_location(id: String) -> Vector3:
	var value=meta.get("locations_v11",{}).get(id,[])
	return Vector3(value[0],value[1],value[2]) if value.size()==3 else Vector3.INF
var occlusion_materials: Array[ShaderMaterial] = []
var autotest := "--autotest" in OS.get_cmdline_user_args()
## Blender 导出的场景数据: 楼梯、桥、点光源 (都是 Blender 坐标)
var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/island_meta.json"))


static func from_blender(x: float, y: float, z := 0.0) -> Vector3:
	return Vector3(x, z, -y)


func _ready() -> void:
	_setup_input()
	_setup_environment()
	_setup_lights()

	var island := ISLAND.instantiate()
	add_child(island)
	_add_collisions(island)
	occlusion_materials = preload("res://scripts/scenery_effects.gd").apply(island)
	add_child(preload("res://scripts/world_details.gd").new())

	player = PlayerScript.new()
	player.spawn_point = SPAWN
	player.capture_mouse = not (autotest or "--visual-review" in OS.get_cmdline_user_args())
	add_child(player)
	player.global_position = SPAWN

	_setup_hud()
	interactions = preload("res://scripts/town_interactions.gd").new()
	interactions.world = self
	add_child(interactions)
	day_cycle=preload("res://scripts/day_cycle.gd").new()
	day_cycle.world=self
	add_child(day_cycle)
	var clouds:=preload("res://scripts/sky_clouds.gd").new()
	clouds.world=self
	add_child(clouds)
	audio=preload("res://scripts/content/audio_director.gd").new()
	audio.world=self
	add_child(audio)
	activities=preload("res://scripts/cozy_activities.gd").new()
	activities.world=self
	add_child(activities)
	performance=preload("res://scripts/performance.gd").new()
	performance.world=self
	add_child(performance)
	_setup_content_anchors()
	content=preload("res://scripts/content/content_root.gd").new()
	content.world=self
	add_child(content)
	if autotest:
		_autotest()

func _setup_content_anchors() -> void:
	var points := {
		"tree_house": [Vector3(0,.1,1.4),Vector3.FORWARD],
		"star_roof_shop": [Vector3(-15.5,.1,7.4),Vector3.BACK],
		"garden": [Vector3(-3,.1,8.2),Vector3.FORWARD],
		"remote_chair": [scene_actions.approach+Vector3.UP*.1,-scene_actions.FACING],
		"telescope": [interactions.SCOPE_POSITION+Vector3(0,.1,1.9),Vector3.FORWARD],
		"fountain": [Vector3(6.5,.1,4.0),Vector3.FORWARD],
		"dock": [Vector3(-22.5,.1,4.8),Vector3.LEFT]
	}
	for id in points:
		var marker:=Marker3D.new();marker.name="Anchor_"+id;add_child(marker)
		marker.position=points[id][0];marker.look_at(marker.position+points[id][1])


func _process(_delta: float) -> void:
	fps_label.text = "FPS %d" % Engine.get_frames_per_second()
	for material in occlusion_materials:
		material.set_shader_parameter("player_position", player.global_position + Vector3.UP*.95)


# ------------------------------------------------------------------ 输入
func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"run": [KEY_SHIFT],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	# 手柄: 左摇杆移动, A 跳
	var axes := {
		"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0],
	}
	for action in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = axes[action][0]
		jm.axis_value = axes[action][1]
		InputMap.action_add_event(action, jm)
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_A
	InputMap.action_add_event("jump", jb)


# ------------------------------------------------------------------ 环境与灯光
func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/twilight_sky.gdshader")
	sky_material.set_shader_parameter("web_color_space",true)
	sky_material.set_shader_parameter("panorama",preload("res://assets/night_sky_2k_web.png"))
	sky_material.set_shader_parameter("galaxy_detail",preload("res://assets/galaxy_detail_2k_web.png"))
	env.sky.sky_material = sky_material
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.72, 0.91)
	env.ambient_light_energy = 0.34
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.015
	env.glow_hdr_threshold = 1.35
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.44, 0.38, 0.65)
	env.fog_density = 0.0018
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _setup_lights() -> void:
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.78, 0.84, 1.0)
	moon.light_energy = 0.95
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 90.0
	add_child(moon)
	moon.look_at_from_position(Vector3(-30, 50, -40), Vector3.ZERO)

	for d in [[Vector3(30, 40, 40), 0.17], [Vector3(5, -50, 15), 0.18]]:   # 正面补光 + 云海反光
		var fill := DirectionalLight3D.new()
		fill.light_color = Color(0.86, 0.79, 1.0)
		fill.light_energy = d[1]
		add_child(fill)
		fill.look_at_from_position(d[0], Vector3.ZERO)

	# 点光源来自 Blender (许愿树、喷泉、窗户、灯塔……), 瓦数换算成 Godot 的能量和范围
	for l: Array in meta["lights"]:
		var omni := OmniLight3D.new()
		omni.position = from_blender(l[0], l[1], l[2])
		omni.light_energy = clampf(l[3] / 160.0, 0.4, 5.0)
		omni.omni_range = 2.7 + sqrt(l[3]) / 5.0
		omni.distance_fade_enabled = true
		omni.distance_fade_begin = 85.0
		omni.distance_fade_length = 30.0
		omni.light_color = Color(l[4], l[5], l[6])
		add_child(omni)


# ------------------------------------------------------------------ 碰撞
func _add_collisions(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var n := String(mi.name)
		if COLLISION_ONLY.any(func(p): return n.begins_with(p)):
			mi.visible = false
		elif n.begins_with("Decor_WishingTree_trunk"):
			pass # Solid exposed roots are walk obstacles, with camera corridor fading.
		elif NO_COLLIDE.any(func(p): return n.begins_with(p)):
			continue
		mi.create_trimesh_collision()
		if THIN_PROPS.any(func(p): return n.begins_with(p)):
			var body: StaticBody3D = mi.get_child(mi.get_child_count() - 1)
			body.collision_layer = 2   # 角色会撞到, 但相机弹簧臂忽略, 免得镜头被细杆子顶近


# ------------------------------------------------------------------ HUD
func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.visible = not "--clean-shots" in OS.get_cmdline_user_args()
	var help := Label.new()
	help.text = "WASD 移动 · E 交谈 · N 地图 · P 故事 · H 帮助"
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Source Han Sans SC", "WenQuanYi Zen Hei"])
	font.fallbacks = [preload("res://assets/fonts/NotoSansSC.ttf")]
	help.add_theme_font_override("font",font)
	help.position = Vector2(16, 12)
	help.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.2))
	help.add_theme_constant_override("outline_size", 6)
	layer.add_child(help)
	fps_label = Label.new()
	fps_label.position = Vector2(16, 40)
	fps_label.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	layer.add_child(fps_label)


# ------------------------------------------------------------------ 自动测试
## 运行: Godot --path game -- --autotest --shots=<目录>
## 依次测试: 出生落地、向前走、跳跃、两段楼梯、掉出岛外重生, 最后截两张图后退出。
func _autotest() -> void:
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
	await _wait(1.5)
	_log("spawn")
	player.test_dir = Vector3(0, 0, -1)
	await _wait(1.0)
	_log("walk_forward")
	player.test_dir = Vector3.ZERO
	await _wait(0.4)
	var y0 := player.global_position.y
	player.jump()
	var peak := y0
	for i in 60:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
	print("TEST jump_height=%.2f" % (peak - y0))
	await _wait(0.5)
	_log("landed")
	var stairs: Array = meta["stairs"]
	for i in stairs.size():
		var s: Array = stairs[i]
		await _stair_test("stairs_%d" % i, Vector2(s[0], s[1]), Vector2(s[2], s[3]), s[4], s[5])
	for i in meta["bridges"].size():
		var b: Array = meta["bridges"][i]
		await _bridge_test("bridge_%d" % i, Vector2(b[0], b[1]), Vector2(b[2], b[3]))
	player.global_position = Vector3(0, 1, 30)    # 岛外, 应该掉下去后重生
	await _wait(3.5)
	_log("fall_respawn")

	player.global_position = SPAWN
	player.velocity = Vector3.ZERO
	player.cam_yaw = 0.0
	player.cam_pitch = -0.32
	await _wait(1.0)
	await _shot(shots.path_join("godot_play_1.png"))
	var top: Array = stairs[0]                            # 住宅台地楼梯口, 回望星星树
	var at := Vector3(top[2], top[5] + 0.5, -top[3])
	player.global_position = at
	player.cam_yaw = atan2(-(0.0 - at.x), -(-3.0 - at.z))
	player.cam_pitch = -0.2
	await _wait(1.0)
	await _shot(shots.path_join("godot_play_2.png"))
	var overview := Camera3D.new()
	add_child(overview)
	overview.fov = 47
	overview.far = 1500
	overview.look_at_from_position(Vector3(-5, 34, 66), Vector3(0, -3.5, -1))
	overview.current = true
	await _wait(0.5)
	await _shot(shots.path_join("godot_overview.png"))
	# Same scene, additional review angles; no UI automation or manual camera setup.
	for shot in [
		["godot_tree.png", Vector3(-10, 8, 16), Vector3(0, 8, -3)],
		["godot_village.png", Vector3(-23, 9, 0), Vector3(-12, 5, -6)],
		["godot_garden.png", Vector3(12, 6, 17), Vector3(1, 1.5, 9)],
		["godot_side.png", Vector3(47, 25, 48), Vector3(0, 2, -2)]
	]:
		overview.look_at_from_position(shot[1], shot[2])
		await _wait(0.6)
		await _shot(shots.path_join(shot[0]))
	var frame_time := 0.0
	for i in 120:
		await get_tree().process_frame
		frame_time += get_process_delta_time()
	print("REVIEW average_fps=%.1f draw_calls=%d triangles=%d" % [120.0 / frame_time, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	get_tree().quit()


func _stair_test(label: String, a: Vector2, b: Vector2, bottom: float, top: float) -> void:
	# 参数是 Blender 平面坐标, 这里换成 Godot 坐标; 从楼梯脚前 0.8m 出发, 走到楼梯顶再往里 1.5m
	var dir := Vector3(b.x - a.x, 0, -(b.y - a.y)).normalized()
	var start := Vector3(a.x, bottom + 0.5, -a.y) - dir * 0.8
	player.global_position = start
	player.velocity = Vector3.ZERO
	await _wait(0.4)
	player.test_dir = dir
	await _wait(((b - a).length() + 2.3) / 4.5 + 0.5)
	player.test_dir = Vector3.ZERO
	await _wait(0.4)
	var p := player.global_position
	var hits := []
	for i in player.get_slide_collision_count():
		var c := player.get_slide_collision(i)
		hits.append("%s n=%.2f,%.2f,%.2f" % [c.get_collider().get_parent().name, c.get_normal().x, c.get_normal().y, c.get_normal().z])
	print("TEST %s y=%.2f expected=%.1f %s at=(%.2f, %.2f) touching=%s" % [label, p.y, top, "PASS" if absf(p.y - top) < 0.35 else "FAIL", p.x, p.z, hits])


func _bridge_test(label: String, start: Vector2, isle: Vector2) -> void:
	# 从主岛桥头往里 1.5m 出发, 一路走到小岛中心, 应该稳稳站在小岛上 (y≈0)
	var a := from_blender(start.x, start.y)
	var c := from_blender(isle.x, isle.y)
	var dir := (c - a).normalized()
	player.global_position = a - dir * 1.5 + Vector3.UP * 0.5
	player.velocity = Vector3.ZERO
	await _wait(0.4)
	player.test_dir = dir
	await _wait((a.distance_to(c) + 1.5) / 4.5 + 0.3)
	player.test_dir = Vector3.ZERO
	await _wait(0.5)
	var p := player.global_position
	var off := Vector2(p.x - c.x, p.z - c.z).length()
	var ok := absf(p.y) < 0.3 and off < 3.0
	print("TEST %s y=%.2f dist_to_isle_center=%.2f %s" % [label, p.y, off, "PASS" if ok else "FAIL"])


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _log(label: String) -> void:
	var p := player.global_position
	print("TEST %s pos=(%.2f, %.2f, %.2f) on_floor=%s" % [label, p.x, p.y, p.z, player.is_on_floor()])


func _shot(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
