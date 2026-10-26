extends CanvasLayer
## Small unhurried interactions. Test sessions never write real progress/photos.
const SAVE := "user://cozy.json"   # = D:/claude/starworld/game/save/cozy.json
## Content events for the story/guide layer (ids in content/content_events.gd).
signal content_event(id: String, data: Dictionary)
const CHAIR := Vector3(-43.8,6,-19.5)
const TREE := Vector3(0,0,-.2)
const GARDEN := Vector3(-3,0,8.2)
const WATER := Vector3(6.5,0,1)
const HELP := "T  晴日 / 傍晚 / 夜晚，6 秒渐变\nC  左侧观景椅：走近、落座 / 起身（坐下仍可 T）\nF  手持小灯，陪你散步\nG  招手，附近伙伴会回应\nV  邀来萤火虫，陪你散步 18 秒\nR  花园种花（最多 3 株）\nU  花园浇水，让花长高并开花\nX  树下拨风铃，听一小段和弦\nL  树下放愿望灯，缓缓飞向云海\nK  喷泉旁打水漂，看三圈涟漪\nM  音乐开关\nO  摄影取景 / 返回，方向键构图，滚轮变焦\nEnter  摄影时保存画面到 renders/photos\nJ  原有星图手记 · E  交谈 / 望远镜\nH  收起玩法 · Esc 返回"
var world: Node3D
var player: CharacterBody3D
var ui: Control
var hint: Label
var toast: Label
var guide: PanelContainer
var guide_text: Label
var progress_label: Label
var music: AudioStreamPlayer
var notes: AudioStreamPlayer
var lantern: Node3D
var photo_camera: Camera3D
var sitting := false
var photo := false
var photo_hud: Label
var photo_mouse := 0
var photo_saved := false
var studio: CanvasLayer
const Flora := preload("res://scripts/garden_flora.gd")
const CHIME_SPOT := Vector3(-1.55,2.62,-.05)   # beside the tree-house door
var water_show: Node3D
var swarm: Node3D
var chime_prop: Node3D
var seat_return := Vector3.ZERO
var wave_time := 0.0
var clock := 0.0
var progress: Dictionary = {"flowers":0,"watered":false,"moments":[]}
var flowers: Array[Node3D] = []
var cooldowns: Dictionary = {}
var music_enabled := true
var photo_ui: Array[CanvasLayer] = []
var fireflies: MultiMeshInstance3D
var firefly_time := 0.0
var timed: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	name="CozyActivities"
	player=world.player
	rng.seed=102310
	if not "--test-session" in OS.get_cmdline_user_args() and FileAccess.file_exists(SAVE):
		var loaded=JSON.parse_string(FileAccess.get_file_as_string(SAVE))
		if loaded is Dictionary:
			progress.flowers=clampi(int(loaded.get("flowers",0)),0,3)
			progress.watered=bool(loaded.get("watered",false))
			if loaded.get("moments") is Array:
				for entry in loaded.moments:
					if entry is String and entry.length()<40 and not entry in progress.moments:progress.moments.append(entry)
	_build_ui()
	_build_lantern()
	for i in int(progress.flowers):_flower(i).scale=Vector3.ONE
	if progress.watered:
		for flower in flowers:
			flower.scale=Vector3.ONE*1.6
			Flora.set_open(flower,1.0)
	water_show=preload("res://scripts/water_show.gd").new();water_show.world=world;world.add_child(water_show)
	swarm=preload("res://scripts/fireflies.gd").new();swarm.world=world;swarm.player=player;world.add_child(swarm)
	chime_prop=preload("res://scripts/wind_chime.gd").new();world.add_child(chime_prop);chime_prop.position=CHIME_SPOT
	music=AudioStreamPlayer.new()
	music.volume_db=-15
	add_child(music)
	# The audio director (main.gd) owns day/dusk/night music; the old loop only plays without it
	if not world.get("audio"):
		music.stream=load("res://assets/audio/cloud_rest.wav")
		if DisplayServer.get_name()!="headless":music.play()
	else:
		music_enabled=world.audio.is_music_on()
	notes=AudioStreamPlayer.new()
	notes.volume_db=-19
	add_child(notes)
	photo_camera=Camera3D.new()
	photo_camera.far=1500
	world.add_child(photo_camera)
	studio=preload("res://scripts/photo_studio.gd").new()
	studio.cozy=self
	add_child(studio)
	_update_progress()

func label(text: String,size := 17) -> Label:
	var node:=Label.new()
	node.text=text
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",Color("fff1d7"))
	node.add_theme_color_override("font_outline_color",Color("20293d"))
	node.add_theme_constant_override("outline_size",5)
	return node

func _build_ui() -> void:
	ui=Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var font:=preload("res://assets/fonts/LXGWWenKai-Regular.ttf")
	ui.add_theme_font_override("font",font)
	add_child(ui)
	hint=label("")
	hint.position=Vector2(20,630)
	ui.add_child(hint)
	toast=label("按 H 看看今天能做些什么。",19)
	toast.position=Vector2(20,588)
	ui.add_child(toast)
	progress_label=label("",15)
	progress_label.position=Vector2(20,68)
	ui.add_child(progress_label)
	guide=PanelContainer.new()
	guide.position=Vector2(24,110)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(.13,.18,.25,.96)
	style.set_corner_radius_all(14)
	style.content_margin_left=20;style.content_margin_right=20
	style.content_margin_top=16;style.content_margin_bottom=16
	guide.add_theme_stylebox_override("panel",style)
	guide_text=label(HELP,17)
	guide.add_child(guide_text)
	ui.add_child(guide)
	guide.visible=false
	photo_hud=label("摄影 · 方向键构图 / 滚轮变焦 / Enter 保存 / O 返回",17)
	photo_hud.position=Vector2(20,680)
	photo_hud.visible=false
	ui.add_child(photo_hud)

func _build_lantern() -> void:
	var actions=preload("res://scripts/scene_actions.gd").new()
	actions.world=world;actions.activities=self
	world.scene_actions=actions;world.add_child(actions)
	lantern=actions.lantern

func ball(parent: Node3D,where: Vector3,size: Vector3,color: Color,glow := false) -> MeshInstance3D:
	var mesh:=MeshInstance3D.new()
	var sphere:=SphereMesh.new()
	sphere.radial_segments=8;sphere.rings=4;sphere.radius=1;sphere.height=2
	mesh.mesh=sphere
	mesh.scale=size;mesh.position=where
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=color
	mat.roughness=.85
	if glow:mat.emission_enabled=true;mat.emission=color;mat.emission_energy_multiplier=1.3
	mesh.material_override=mat
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	return mesh

func _process(delta: float) -> void:
	clock+=delta
	if not is_instance_valid(player):return
	ui.visible=world.interactions.mode=="idle" and not _performing()
	var night: float=world.day_cycle.weights.z+world.day_cycle.weights.y*.4
	for flower in flowers:Flora.set_glow(flower,night)
	if wave_time>0:
		wave_time-=delta
		if wave_time<=0:player.model.waving=false
	if sitting:
		player.pivot.rotation=Vector3(player.cam_pitch,player.cam_yaw,0)
	if photo:
		photo_camera.rotation.y+=Input.get_axis("move_right","move_left")*delta*.45
		photo_camera.rotation.x=clampf(photo_camera.rotation.x+Input.get_axis("move_back","move_forward")*delta*.35,-1.2,.6)
	if firefly_time>0:
		firefly_time-=delta
		fireflies.position=player.position
		for i in 36:
			var a:=float(i)*2.399+clock*.22
			var pos:=Vector3(cos(a)*(1.2+float(i%4)*.3),.4+float(i%7)*.23+sin(clock+i)*.17,sin(a)*(1.2+float(i%4)*.3))
			fireflies.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*.022),pos))
		if firefly_time<=0:fireflies.queue_free()
	for i in range(timed.size()-1,-1,-1):
		var entry: Dictionary=timed[i]
		entry.time+=delta
		var node: Node3D=entry.node
		if entry.time<0:continue
		node.visible=true
		if entry.kind=="wish":node.position.y+=delta*.68;node.position.x+=sin(clock*.5)*delta*.10
		else:
			node.scale=Vector3.ONE*(1+float(entry.time)*1.9)
			node.position.y=.39
		if entry.time>entry.life:node.queue_free();timed.remove_at(i)
	if not photo and world.interactions.mode=="idle":
		if sitting:hint.text="C 起身 · T 看三种天色 · O 摄影"
		elif near(CHAIR,3.2):hint.text="C 走近观景椅，坐看整座小镇"
		elif near(GARDEN,4):hint.text="R 种花 · U 浇水 · G 向芽芽招手"
		elif near(WATER,4.8):hint.text="K 打水漂，看涟漪散开"
		elif near(TREE,4):hint.text="X 拨风铃 · L 放一盏愿望灯"
		elif _story_mode():hint.text=""
		else:hint.text="H 帮助 · N 地图 · F 小灯 · O 摄影"
	else:hint.text=""

## In the story the quest box says what to do; the corner texts step aside.
func _story_mode() -> bool:
	var content=world.get("content")
	return content!=null and content.state!=null and content.state.data.mode=="story"

func near(place: Vector3,distance: float) -> bool:return player.position.distance_to(place)<distance

func say(text: String) -> void:toast.text=text

func mark(text: String) -> void:
	if not text in progress.moments:progress.moments.append(text)
	_update_progress()
	if "--test-session" in OS.get_cmdline_user_args():return
	DirAccess.make_dir_recursive_absolute(SAVE.get_base_dir())
	var file:=FileAccess.open(SAVE,FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(progress,"  "))

func _update_progress() -> void:progress_label.text="悠闲手记 · %d 段小事 · 花苗 %d / 3"%[progress.moments.size(),progress.flowers]

func ready_action(id: String,seconds: float) -> bool:
	if clock<float(cooldowns.get(id,-100)):say("慢一点，让刚才的小事做完。");return false
	cooldowns[id]=clock+seconds
	return true

func _input(event: InputEvent) -> void:
	if photo and event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:photo_camera.fov=maxf(25,photo_camera.fov-3)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:photo_camera.fov=minf(85,photo_camera.fov+3)
		elif event.button_index==MOUSE_BUTTON_LEFT:save_photo()
		get_viewport().set_input_as_handled();return
	if not event is InputEventKey or not event.pressed or event.echo:return
	var keycode: int=event.physical_keycode
	if photo:
		# keycode as well as physical_keycode: some Windows layouts/IMEs only fill one of them
		var logical: int=event.keycode
		if keycode==KEY_O or keycode==KEY_ESCAPE:toggle_photo()
		elif keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE] or logical in [KEY_ENTER,KEY_KP_ENTER]:save_photo()
		elif keycode==KEY_TAB:studio.cycle_framing()
		elif keycode in [KEY_1,KEY_2,KEY_3]:studio.set_filter(keycode-KEY_1)
		elif keycode==KEY_G:studio.toggle_grid()
		get_viewport().set_input_as_handled();return
	if world.interactions.mode!="idle":
		if keycode==KEY_M:perform(KEY_M);get_viewport().set_input_as_handled()
		return
	if keycode==KEY_ESCAPE and world.scene_actions.seat_state!="free":toggle_seat();get_viewport().set_input_as_handled();return
	if perform(keycode):get_viewport().set_input_as_handled()

func perform(keycode: int) -> bool:
	if world.scene_actions.seat_state in ["walking","turning","lowering","rising"] and not keycode in [KEY_C,KEY_T,KEY_H]:return false
	match keycode:
		KEY_T:
			world.day_cycle.cycle();say(world.day_cycle.TITLES[world.day_cycle.current]+" · 正在慢慢变化");mark("看天色变化")
		KEY_H:guide.visible=not guide.visible
		KEY_C:toggle_seat()
		KEY_F:
			if world.scene_actions.toggle_lantern():
				say("握好小灯，继续散步。" if lantern.visible else "收起小灯。")
				mark("提灯散步")
		KEY_G:
			player.model.waving=true;wave_time=2.4
			for npc in world.interactions.npcs:
				if player.position.distance_to(npc.position)<6:npc.visual.waving=true
			say("向朋友轻轻挥手。");mark("和朋友招手")
			var waved_to:=[]
			for npc in world.interactions.npcs:
				if player.position.distance_to(npc.position)<6:waved_to.append(npc.profile_id)
			content_event.emit("waved",{"near":waved_to})
		KEY_V:call_fireflies()
		KEY_R:plant()
		KEY_U:water()
		KEY_X:
			if not near(TREE,4):say("到树屋门前拨响风铃。");return true
			if ready_action("chime",3):
				mark("树下听风铃");say("风铃响了，余音慢慢散开。")
				content_event.emit("chime_rung",{})
				if _perf_ok():_perform_chime()
				else:chime_prop.ring();play_chime(true)
		KEY_L:release_wish()
		KEY_K:skip_stone()
		KEY_M:
			if world.get("audio"):music_enabled=not world.audio.toggle_mute()
			else:
				music_enabled=not music_enabled
				if music_enabled and DisplayServer.get_name()!="headless":music.play()
				else:music.stop()
			say("轻音乐已开启。" if music_enabled else "轻音乐已关闭。");mark("听一段音乐")
		KEY_O:toggle_photo()
		_:return false
	return true

func toggle_seat() -> bool:
	return world.scene_actions.toggle_seat()

## The player's flower; starts tiny (a performance grows it from the soil).
func _flower(index: int) -> Node3D:
	var flower:=_web_flower(index)
	flower.position=GARDEN+Vector3(-1.3+index*.72,.06,1.7)
	flower.rotation.y=index*1.9
	flower.scale=Vector3.ONE*.01
	world.add_child(flower)
	flowers.append(flower)
	return flower

func _performing() -> bool:
	var perf=world.get("performance")
	return perf!=null and perf.busy

func _perf_ok() -> bool:
	var perf=world.get("performance")
	return perf!=null and perf.can_start()

func _grow(flower: Node3D,seconds := 1.4) -> void:
	create_tween().tween_property(flower,"scale",Vector3.ONE,seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _bloom(seconds := 2.5) -> void:
	for flower in flowers:
		var t:=create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
		t.tween_property(flower,"scale",Vector3.ONE*1.6,seconds)
		t.tween_method(func(v):Flora.set_open(flower,v),float(flower.get_meta("open",0.0)),1.0,seconds)

# ------------------------------------------------------------------ performances
func _perform_plant(flower: Node3D) -> void:
	var perf=world.performance
	var spot: Vector3=flower.global_position
	var toward:=(player.global_position-spot);toward.y=0
	var mark_at:=spot+(toward.normalized() if toward.length()>.1 else Vector3.BACK)*.62
	if not perf.begin("plant",spot,{"distance":2.6,"height":1.1,"look_height":.35,"mix":.6}):_grow(flower);return
	perf.hold_prop(perf.seed_pouch())
	await perf.approach(mark_at,spot)
	await perf.animate_pose("kneel",1.6)
	perf.drop_prop()
	_grow(flower)
	if world.get("audio"):world.audio.play_sfx("plant")
	await perf.wait(.9)
	perf.set_pose("admire")
	await perf.wait(1.2)
	await perf.finish()

func _perform_water() -> void:
	var perf=world.performance
	var center:=Vector3.ZERO
	for flower in flowers:center+=flower.global_position
	center/=flowers.size()
	var toward:=(player.global_position-center);toward.y=0
	if not perf.begin("water",center,{"distance":3.0,"height":1.2,"look_height":.45,"mix":.55}):_bloom();return
	perf.hold_prop(perf.watering_can())
	await perf.approach(center+(toward.normalized() if toward.length()>.1 else Vector3.BACK)*.95,center)
	perf.set_pose("pour",5.0)
	await perf.wait(.5)
	var stream:=_pour_stream()
	await perf.animate_pose("pour",1.4)
	_bloom()
	if world.get("audio"):world.audio.play_sfx("bloom")
	await perf.wait(.6)
	stream.queue_free()
	perf.drop_prop()
	perf.set_pose("admire")
	await perf.wait(1.9)
	await perf.finish()

## Thin falling drops from the can's spout while pouring.
func _pour_stream() -> Node3D:
	var root:=Node3D.new();world.add_child(root)
	var drops:=CPUParticles3D.new()
	drops.amount=60;drops.lifetime=.55;drops.emitting=true
	drops.direction=Vector3(0,-1,.2);drops.spread=8;drops.initial_velocity_min=.4;drops.initial_velocity_max=.8;drops.gravity=Vector3(0,-6,0)
	var m:=_web_pour_mesh()
	drops.mesh=m
	var mat:=_web_pour_material()
	drops.material_override=mat
	root.add_child(drops)
	var perf=world.performance
	root.set_process(true)
	var follow:=func():
		while is_instance_valid(root) and is_instance_valid(perf.prop):
			root.global_position=perf.prop.global_position+(-player.model.global_basis.z)*.16+Vector3.UP*.02
			await get_tree().process_frame
	follow.call()
	return root

func _perform_chime() -> void:
	var perf=world.performance
	var at:=chime_prop.global_position
	var stand:=Vector3(at.x+.15,player.global_position.y,at.z+.9)
	# fixed side-front angle: the trunk and steps confuse the automatic framing here
	var view:={"eye":at+Vector3(2.3,-.75,2.9),"look":at+Vector3(.15,-.85,.45),"fov":44}
	if not perf.begin("chime",at,view):chime_prop.ring();play_chime(true);return
	await perf.approach(stand,Vector3(at.x,player.global_position.y,at.z))
	await perf.animate_pose("reach_up",.6)
	chime_prop.ring()
	play_chime(true)
	await perf.animate_pose("reach_up",.4)
	perf.set_pose("listen",4.0)
	await perf.wait(2.4)
	await perf.finish()

func _perform_wish(node: Node3D,entry: Dictionary) -> void:
	var perf=world.performance
	var up:=player.global_position+Vector3.UP*2.2
	if not perf.begin("wish",up,{"distance":5.0,"height":.35,"look_height":1.6,"mix":0.0,"fov":50,"low":true}):entry.time=0.0;return
	perf.hold_prop(perf.paper_lantern(),Vector3(0,.02,.05))
	perf.set_pose("hug",5.0)
	await perf.wait(1.0)
	perf.set_pose("hold_up",4.0)
	await perf.wait(1.1)
	node.global_position=perf.prop.global_position if is_instance_valid(perf.prop) else player.global_position+Vector3.UP*1.9
	perf.drop_prop()
	entry.time=0.0
	perf.set_pose("release",5.0)
	# follow the lantern up from low beside the player, so the sky fills the frame
	var side: Vector3=(-player.model.global_basis.x).normalized()
	var low_eye: Vector3=player.global_position+side*2.6+(player.model.global_basis.z)*1.4+Vector3.UP*.5
	var t0:=0.0
	while t0<3.2:
		t0+=get_process_delta_time()
		perf.camera.global_position=perf.camera.global_position.lerp(low_eye,.05)
		if is_instance_valid(node):perf.camera.look_at(node.global_position.lerp(player.global_position+Vector3.UP*1.2,.25),Vector3.UP)
		await get_tree().process_frame
	perf.set_pose("look_up",3.0)
	await perf.wait(1.4)
	await perf.finish(1.0)

func _perform_stone(rings: Array,delay: float) -> void:
	var perf=world.performance
	var aim:=WATER+Vector3(0,.4,0)
	if not perf.begin("stone",aim,{"distance":3.2,"height":1.2,"look_height":.5,"mix":.6}):return
	await perf.turn_to(aim)
	perf.hold_prop(perf.pebble())
	perf.set_pose("windup",6.0)
	await perf.wait(.55)
	perf.set_pose("throw",14.0)
	await perf.wait(.12)
	var stone: Node3D=perf.pebble()
	world.add_child(stone)
	var from: Vector3=perf.prop.global_position if is_instance_valid(perf.prop) else player.global_position+Vector3.UP
	perf.drop_prop()
	var t:=create_tween()
	var hops: Array=[from]
	for ring in rings:hops.append(ring.global_position+Vector3.UP*.03)
	for i in range(1,hops.size()):
		var a: Vector3=hops[i-1];var b: Vector3=hops[i]
		t.tween_method(func(k):stone.global_position=a.lerp(b,k)+Vector3.UP*sin(k*PI)*(.5 if i==1 else .18),0.0,1.0,.32 if i==1 else .22)
	t.tween_callback(stone.queue_free)
	await perf.wait(delay)
	if not water_show.playing():
		water_show.play()
		if world.get("audio"):world.audio.play_sfx("water_show")
		say("水面好像在回应你。")
		await perf.wait(.6)
		# a slow half circle around the basin at water height
		var start: Vector3 =perf.camera.global_position
		var angle0:=atan2(start.z-WATER.z,start.x-WATER.x)
		var elapsed:=0.0
		while water_show.playing() and not perf.hurry:
			elapsed+=get_process_delta_time()
			var a:=angle0+elapsed*.14
			var r:=4.3-sin(elapsed*.2)*.4
			perf.camera.global_position=WATER+Vector3(cos(a)*r,1.75+sin(elapsed*.3)*.3,sin(a)*r)
			perf.camera.look_at(WATER+Vector3(0,1.9,0),Vector3.UP)
			perf.camera.fov=lerpf(perf.camera.fov,48,.02)
			await get_tree().process_frame
	await perf.finish()

func call_fireflies() -> bool:
	var dusk: float=world.day_cycle.weights.y+world.day_cycle.weights.z
	if dusk<.5:say("萤火虫还在草叶下面睡觉，傍晚再来叫它们。");return false
	if swarm.active():say("萤火虫还在你身边。");return false
	mark("和萤火虫散步");say("蹲下来，手心朝上……")
	content_event.emit("fireflies_called",{})
	var perf=world.get("performance")
	var cupped: Vector3 =player.global_position+(-player.model.global_basis.z)*.4+Vector3.UP*.7
	if perf==null or not perf.begin("fireflies",cupped,{"distance":3.0,"height":.55,"look_height":.9,"mix":.4,"fov":52}):
		swarm.gather(cupped);get_tree().create_timer(7.0).timeout.connect(swarm.scatter);return true
	_perform_fireflies(cupped)
	return true

func _perform_fireflies(cupped: Vector3) -> void:
	var perf=world.performance
	perf.set_pose("cup",4.0)
	swarm.gather(cupped)
	if world.get("audio"):world.audio.play_sfx("fireflies")
	await perf.wait(7.5)
	perf.set_pose("look_up",3.0)
	swarm.scatter()
	say("大部分飞回了草丛，有几只想再陪你走一会儿。")
	await perf.wait(2.2)
	await perf.finish(1.0)

func plant() -> bool:
	if not near(GARDEN,4):say("到芽芽的花园里种花。");return false
	if progress.flowers>=3:say("三株花都在这里，按 U 给它们浇水。");return false
	var flower:=_flower(int(progress.flowers));progress.flowers+=1
	progress.watered=false
	mark("种下小花");say("种下一株小花，U 浇水会让它开花。")
	content_event.emit("flower_planted",{"count":int(progress.flowers)})
	if _perf_ok():_perform_plant(flower)
	else:flower.scale=Vector3.ONE
	return true

func water() -> bool:
	if not near(GARDEN,4) or flowers.is_empty():say("先在花园按 R 种一株花。");return false
	if progress.watered:say("土壤还是湿润的，让花慢慢长。");return false
	for flower in flowers:
		if flower.scale.x<.9:flower.scale=Vector3.ONE
	progress.watered=true;mark("浇水看花开");say("花苞慢慢打开了。")
	if _perf_ok():_perform_water()
	else:_bloom();play_chime()
	content_event.emit("flower_watered",{"count":int(progress.flowers)})
	return true

func release_wish() -> bool:
	if not near(TREE,4):say("到许愿树门前放一盏灯。");return false
	if not ready_action("wish",8):return false
	var node: Node3D=world.performance.paper_lantern() if world.get("performance") else Node3D.new()
	world.add_child(node)
	node.position=player.position+Vector3(0,1.8,-1.5)
	var entry:={"node":node,"kind":"wish","time":0.0,"life":15.0}
	timed.append(entry)
	if _perf_ok():
		entry.time=-100.0
		node.visible=false
		_perform_wish(node,entry)
	mark("放走一盏愿望灯");say("愿望灯越飞越高，带着今天的一件小事。")
	content_event.emit("wish_released",{})
	return true

func skip_stone() -> bool:
	if not near(WATER,4.8):say("到喷泉水池旁，试着打个水漂。");return false
	if not ready_action("ripple",6):return false
	var delay:=.85 if _perf_ok() else 0.0
	var rings:=[]
	for i in 3:
		var mesh:=MeshInstance3D.new();var ring:=TorusMesh.new()
		ring.inner_radius=.24;ring.outer_radius=.27;ring.rings=24;ring.ring_segments=4
		mesh.mesh=ring;mesh.position=WATER+Vector3(float(i-1)*.65,.39,0)
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color=Color("c6e6e7");mesh.material_override=material
		world.add_child(mesh);timed.append({"node":mesh,"kind":"ripple","time":-float(i)*.3-delay,"life":2.0})
		if delay>0:mesh.visible=false
		rings.append(mesh)
	mark("水面上的三个圈");say("一、二、三，涟漪散开了。")
	content_event.emit("stones_skipped",{})
	if delay>0:_perform_stone(rings,delay+1.0)
	else:
		play_chime()
		if not water_show.playing():water_show.play()
	return true

func _spawn_fireflies() -> void:
	fireflies=MultiMeshInstance3D.new();var mm:=MultiMesh.new()
	mm.transform_format=MultiMesh.TRANSFORM_3D
	var mesh:=SphereMesh.new();mesh.radial_segments=6;mesh.rings=2;mesh.radius=1;mesh.height=2
	mm.mesh=mesh;mm.instance_count=36
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color("ffe6a5");material.emission_enabled=true;material.emission=Color("ffe6a5");material.emission_energy_multiplier=2
	fireflies.material_override=material;fireflies.multimesh=mm
	mm.custom_aabb=AABB(Vector3(-3,0,-3),Vector3(6,3,6))
	world.add_child(fireflies);firefly_time=18

func play_chime(windchime := false) -> void:
	if windchime and world.get("audio") and world.audio.play_sfx("windchime"):return
	if DisplayServer.get_name()=="headless":return
	var data:=PackedByteArray();var count:=22050*3;data.resize(count*2)
	for i in count:
		var t:=float(i)/22050;var sample:=0.0
		for j in 4:
			var dt:=t-float(j)*.22
			if dt>=0:sample+=sin(TAU*[523.25,659.25,783.99,1046.5][j]*dt)*exp(-dt*3)*.15
		data.encode_s16(i*2,int(clampf(sample,-1,1)*23000))
	var sound:=AudioStreamWAV.new();sound.format=AudioStreamWAV.FORMAT_16_BITS;sound.mix_rate=22050;sound.data=data
	notes.stop();notes.stream=sound;notes.play()   # stop first: the audio thread may still mix the old one

func toggle_photo() -> void:
	if world.interactions.mode!="idle":return
	photo=not photo
	if photo:
		photo_mouse=Input.mouse_mode
		photo_camera.global_transform=get_viewport().get_camera_3d().global_transform
		photo_camera.fov=62;photo_camera.current=true
		studio.begin(photo_camera.global_transform,62)
		player.controls_locked=true;player.velocity=Vector3.ZERO
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		photo_ui.clear()
		for layer in world.get_children():
			if layer is CanvasLayer and layer!=self and layer.visible:photo_ui.append(layer);layer.visible=false
		for child in ui.get_children():child.visible=false
		photo_hud.visible=false
	else:
		studio.end()
		if sitting:world.scene_actions.seat_camera.current=true
		else:player.arm.get_child(0).current=true
		player.controls_locked=sitting
		Input.mouse_mode=photo_mouse
		for layer in photo_ui:layer.visible=true
		for child in [hint,toast,progress_label]:child.visible=true
		photo_hud.visible=false
		mark("给小世界拍照");say("照片保存在 renders/photos；按 H 查看玩法。")
		content_event.emit("photo_taken",{"saved":photo_saved})
		photo_saved=false

## Shutter: test sessions flash and count the photo but never write a file.
func save_photo() -> void:
	if not photo or studio.flash_time>0:return
	await studio.shoot(not "--test-session" in OS.get_cmdline_user_args())
	photo_saved=true
	if world.get("audio"):world.audio.play_sfx("shutter")
	content_event.emit("photo_saved",{"pos":player.global_position})


## Keep flower meshes and drop resources ready without changing game progress.
var _web_flower_pool := {}
var _web_flower_cache: Node3D
var _web_drop_mesh: SphereMesh
var _web_drop_material: StandardMaterial3D

func _web_prepare_flowers() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not is_instance_valid(_web_flower_cache):
		_web_flower_cache = Node3D.new()
		_web_flower_cache.name = "PreparedGardenFlowers"
		world.add_child(_web_flower_cache)
	for i in 3:
		if not is_instance_valid(_web_flower_pool.get(i)):
			var flower := Flora.build(i)
			_web_flower_cache.add_child(flower)
			flower.position = GARDEN + Vector3(-1.3+i*.72,.06,1.7)
			flower.rotation.y = i*1.9
			flower.visible = false
			_web_flower_pool[i] = flower
		result.append(_web_flower_pool[i])
	return result

func _web_flower(index: int) -> Node3D:
	if not OS.has_feature("web"):return Flora.build(index)
	var flower: Node3D = _web_flower_pool.get(index)
	if not is_instance_valid(flower):return Flora.build(index)
	_web_flower_pool.erase(index)
	flower.get_parent().remove_child(flower)
	flower.visible = true
	return flower

func _web_pour_mesh() -> SphereMesh:
	if _web_drop_mesh == null:
		_web_drop_mesh = SphereMesh.new()
		_web_drop_mesh.radius = .012
		_web_drop_mesh.height = .03
		_web_drop_mesh.radial_segments = 4
		_web_drop_mesh.rings = 2
	return _web_drop_mesh

func _web_pour_material() -> StandardMaterial3D:
	if _web_drop_material == null:
		_web_drop_material = StandardMaterial3D.new()
		_web_drop_material.albedo_color = Color(.75,.9,1,.8)
		_web_drop_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _web_drop_material
