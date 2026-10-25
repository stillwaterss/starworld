extends CanvasLayer
signal star_recorded(index: int)
## Emitted when a conversation is read to the end (or skipped to the end); Esc does not count.
signal dialogue_finished(npc_id: String)
const SAVE_PATH := "user://journal.json"   # = D:/claude/starworld/game/save/journal.json
const SCOPE_POSITION := Vector3(43,10,-29)
var world: Node3D
var player: CharacterBody3D
var npcs: Array[CharacterBody3D]=[]
var mode := "idle"
var journal: Dictionary={"stars":[],"friends":[]}
## Loaded from data/content/constellations.json; the order is the save index.
var constellations: Array[Dictionary]=[]
var scope_tabs: VBoxContainer
var root_ui: Control
var prompt: Button
var status: Label
var dialogue_panel: PanelContainer
var dialogue_title: Label
var dialogue_body: Label
var dialogue_next: Button
var dialogue_skip: Button
var scope_ui: Control
var scope_title: Label
var scope_story: Label
var record_button: Button
var zoom_label: Label
var scope_camera: Camera3D
var dialogue_camera: Camera3D
var current_npc: CharacterBody3D
var dialogue_lines: Array[String]=[]
var dialogue_index := 0
var scope_yaw := 0.0
var scope_pitch := .4
var candidate := -1
var mouse_before := Input.MOUSE_MODE_VISIBLE
var active_target := ""
var save_path := SAVE_PATH
var scope_tween: Tween
var chime: AudioStreamPlayer
var journal_panel: PanelContainer
var journal_rows: VBoxContainer

func _ready() -> void:
	name="TownInteractions"
	player=world.player
	_load_constellations()
	_spawn_npc("gardener","芽芽",Vector3(-3,.15,8.2))
	_spawn_npc("astronomer","眠眠",Vector3(40.5,10.15,-30.0))
	if not "--test-session" in OS.get_cmdline_user_args():load_journal()
	_build_ui()
	scope_camera=Camera3D.new()
	scope_camera.fov=26
	scope_camera.far=1500
	scope_camera.position=SCOPE_POSITION+Vector3(1.4,2.7,-1.2)
	world.add_child(scope_camera)
	dialogue_camera=Camera3D.new()
	dialogue_camera.fov=56
	world.add_child(dialogue_camera)
	chime=AudioStreamPlayer.new()
	chime.volume_db=-17
	add_child(chime)
	_update_status()

func _spawn_npc(id: String,label: String,where: Vector3) -> void:
	var npc:=preload("res://scripts/town_npc.gd").new()
	npc.profile_id=id
	npc.display_name=label
	npc.home=where
	npc.player=player
	npc.position=where
	world.add_child(npc)
	npcs.append(npc)

func _panel() -> StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(.065,.085,.15,.96)
	style.border_color=Color("8c826e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.content_margin_left=24
	style.content_margin_right=24
	style.content_margin_top=18
	style.content_margin_bottom=18
	return style

func _label(text: String,size := 18) -> Label:
	var label:=Label.new()
	label.text=text
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color("eee3cf"))
	return label

func _button(text: String,callback: Callable) -> Button:
	var button:=Button.new()
	button.text=text
	button.custom_minimum_size=Vector2(0,42)
	button.add_theme_font_size_override("font_size",18)
	button.pressed.connect(callback)
	return button

func _build_ui() -> void:
	root_ui=Control.new()
	root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var font:=SystemFont.new()
	font.font_names=PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Source Han Sans SC", "WenQuanYi Zen Hei"])
	font.fallbacks = [preload("res://assets/fonts/NotoSansSC.ttf"), preload("res://assets/fonts/LXGWWenKai-Regular.ttf")]
	root_ui.add_theme_font_override("font",font)
	add_child(root_ui)
	status=_label("")
	status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	status.position=Vector2(-280,18)
	root_ui.add_child(status)
	journal_button=_button("打开手记  J",toggle_journal)
	root_ui.add_child(journal_button)
	journal_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	journal_button.offset_left=-220
	journal_button.offset_right=-30
	journal_button.offset_top=80
	journal_button.offset_bottom=122
	prompt=_button("",_interact_nearest)
	root_ui.add_child(prompt)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left=-165
	prompt.offset_right=165
	prompt.offset_top=-90
	prompt.offset_bottom=-44
	prompt.visible=false
	dialogue_panel=PanelContainer.new()
	var card:=_panel()
	card.bg_color=Color(.12,.15,.25,.78)
	card.border_color=Color(1,.92,.78,.28)
	card.content_margin_top=12
	card.content_margin_bottom=12
	dialogue_panel.add_theme_stylebox_override("panel",card)
	dialogue_card=card
	# 小光 speaks on a night-blue card with a soft glow, in the handwriting font
	xiaoguang_card=card.duplicate()
	xiaoguang_card.bg_color=Color(.10,.16,.34,.88)
	xiaoguang_card.border_color=Color(.75,.86,1.0,.85)
	xiaoguang_card.set_border_width_all(2)
	xiaoguang_card.shadow_color=Color(.6,.78,1.0,.35)
	xiaoguang_card.shadow_size=14
	root_ui.add_child(dialogue_panel)
	dialogue_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	dialogue_panel.offset_left=-320
	dialogue_panel.offset_right=320
	dialogue_panel.offset_top=-176
	dialogue_panel.offset_bottom=-24
	dialogue_panel.grow_vertical=Control.GROW_DIRECTION_BEGIN
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",8)
	dialogue_panel.add_child(box)
	dialogue_title=_label("",19)
	dialogue_title.add_theme_color_override("font_color",Color("ffd27d"))
	dialogue_body=_label("",19)
	dialogue_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	dialogue_body.custom_minimum_size=Vector2(590,52)
	box.add_child(dialogue_title)
	box.add_child(dialogue_body)
	var buttons:=HBoxContainer.new()
	buttons.alignment=BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation",10)
	box.add_child(buttons)
	dialogue_skip=_button("跳过",skip_dialogue)
	dialogue_skip.custom_minimum_size=Vector2(90,36)
	dialogue_skip.add_theme_font_size_override("font_size",15)
	buttons.add_child(dialogue_skip)
	dialogue_next=_button("继续  E",next_dialogue)
	dialogue_next.custom_minimum_size=Vector2(150,36)
	dialogue_next.add_theme_font_size_override("font_size",16)
	buttons.add_child(dialogue_next)
	dialogue_panel.visible=false
	scope_ui=Control.new()
	scope_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scope_ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root_ui.add_child(scope_ui)
	var vignette:=ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var material:=ShaderMaterial.new()
	material.shader=preload("res://shaders/scope_vignette.gdshader")
	vignette.material=material
	scope_ui.add_child(vignette)
	var chart:=preload("res://scripts/star_chart.gd").new()
	chart.observatory=self
	chart.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scope_ui.add_child(chart)
	var panel:=PanelContainer.new()
	panel.position=Vector2(24,90)
	panel.custom_minimum_size=Vector2(215,0)
	panel.add_theme_stylebox_override("panel",_panel())
	scope_ui.add_child(panel)
	var tabs:=VBoxContainer.new()
	tabs.add_theme_constant_override("separation",10)
	panel.add_child(tabs)
	tabs.add_child(_label("今晚的星图",22))
	scope_tabs=VBoxContainer.new()
	scope_tabs.add_theme_constant_override("separation",8)
	tabs.add_child(scope_tabs)
	tabs.add_child(_label("拖动转向 · 滚轮变焦",14))
	zoom_label=_label("",15)
	tabs.add_child(zoom_label)
	_rebuild_scope_tabs()
	var close:=_button("退出观星  Esc",close_modal)
	close.position=Vector2(24,24)
	scope_ui.add_child(close)
	scope_title=_label("",28)
	scope_ui.add_child(scope_title)
	scope_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	scope_title.offset_left=-220
	scope_title.offset_right=220
	scope_title.offset_top=24
	scope_title.offset_bottom=66
	scope_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	scope_story=_label("",17)
	scope_ui.add_child(scope_story)
	scope_story.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	scope_story.offset_left=-350
	scope_story.offset_right=350
	scope_story.offset_top=-126
	scope_story.offset_bottom=-86
	scope_story.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	scope_story.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	record_button=_button("记录星图",record_current)
	scope_ui.add_child(record_button)
	record_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	record_button.offset_left=-130
	record_button.offset_right=130
	record_button.offset_top=-76
	record_button.offset_bottom=-32
	scope_ui.visible=false
	journal_panel=PanelContainer.new()
	journal_panel.add_theme_stylebox_override("panel",_panel())
	root_ui.add_child(journal_panel)
	journal_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	journal_panel.offset_left=-400
	journal_panel.offset_right=400
	journal_panel.offset_top=-250
	journal_panel.offset_bottom=250
	journal_panel.custom_minimum_size=Vector2(800,500)
	var journal_box:=VBoxContainer.new()
	journal_box.add_theme_constant_override("separation",16)
	journal_panel.add_child(journal_box)
	journal_box.add_child(_label("小镇手记",28))
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size=Vector2(740,340)
	journal_box.add_child(scroll)
	journal_rows=VBoxContainer.new()
	journal_rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	journal_rows.add_theme_constant_override("separation",18)
	scroll.add_child(journal_rows)
	journal_box.add_child(_button("合上手记  J / Esc",close_modal))
	journal_panel.visible=false

func _process(_delta: float) -> void:
	if mode=="scope":
		_update_candidate()
		zoom_label.text="倍率  %.1f×"%(62.0/scope_camera.fov)
		return
	if mode!="idle":return
	active_target=""
	var nearest:=3.1
	if player.global_position.distance_to(SCOPE_POSITION)<nearest:
		active_target="scope"
		nearest=player.global_position.distance_to(SCOPE_POSITION)
	for npc in npcs:
		var distance:=player.global_position.distance_to(npc.global_position)
		if distance<nearest:
			nearest=distance
			active_target=npc.profile_id
	# a story moment marked "first" (lighting 芽芽's flowers with her standing right there)
	# takes E before the person does
	var content=world.get("content")
	if active_target!="" and content and content.has_method("priority_examine") and content.priority_examine(player.global_position):active_target=""
	prompt.visible=not active_target.is_empty()
	if active_target=="scope":prompt.text="E  使用望远镜 · 观星"
	else:
		for npc in npcs:
			if npc.profile_id==active_target:prompt.text="E  交谈 · "+npc.display_name

func _input(event: InputEvent) -> void:
	if is_instance_valid(world.activities) and (world.activities.photo or world.activities.sitting):return
	if is_instance_valid(world.scene_actions) and world.scene_actions.seat_state!="free":return
	if event.is_action_pressed("ui_cancel") and mode!="idle":
		close_modal()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_J:
		toggle_journal()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_E:
		if mode=="dialogue":next_dialogue()
		elif mode=="idle":_interact_nearest()
		get_viewport().set_input_as_handled()
	elif mode=="scope":
		if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT and event.position.x>250 and event.position.y>75 and event.position.y<get_viewport().get_visible_rect().size.y-140:
			if scope_tween:scope_tween.kill()
			scope_yaw-=event.relative.x*.0025*scope_camera.fov/26
			scope_pitch=clampf(scope_pitch-event.relative.y*.0025*scope_camera.fov/26,.12,1.40)
			_update_scope_rotation()
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index==MOUSE_BUTTON_WHEEL_UP:scope_camera.fov=maxf(10,scope_camera.fov-2)
			elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:scope_camera.fov=minf(44,scope_camera.fov+2)

func _interact_nearest() -> void:
	interact_with(active_target)

func interact_with(id: String) -> bool:
	if mode!="idle":return false
	if id=="scope":
		if player.position.distance_to(SCOPE_POSITION)>3.1:return false
		_open_modal("scope")
		_rebuild_scope_tabs()
		var content=world.get("content")
		if content:content.state.data.flags.erase("constellation_new")
		scope_ui.visible=true
		scope_camera.current=true
		set_scope_target(0,false)
		return true
	for npc in npcs:
		if npc.profile_id!=id or player.position.distance_to(npc.position)>3.1:continue
		current_npc=npc
		npc.talking=true
		_open_modal("dialogue")
		dialogue_title.text=npc.display_name+"  ·  "+("花园看护人" if id=="gardener" else "观星伙伴")
		speaker_title=dialogue_title.text
		var content=world.get("content")
		if content and content.has_method("dialogue_for"):
			var picked: Dictionary=content.dialogue_for(id)
			dialogue_title.text=picked.title
			speaker_title=picked.title
			dialogue_lines.assign(picked.lines)
		elif id=="gardener":
			dialogue_lines.assign(["我是芽芽。小镇的花到了夜里才慢慢亮起来，你可以沿着花园走一走。","眠眠在右边的观星台等你。走上楼梯，就能找到望远镜。","今晚试着记下三张星图吧。回来时，也告诉我你最喜欢哪一片星空。"])
		elif journal.stars.size()==3:
			dialogue_lines.assign(["三张星图都记下来了！星舟、花铃，还有那盏等人回家的灯。","谢谢你陪我看完今晚的星空。以后带着自己的小星星人，我们再来看新的风景。"])
		else:
			dialogue_lines.assign(["我是眠眠。这架望远镜可以看见云海后面的星群。","靠近镜筒，按 E 开始观星。左边可以选星图，拖动转向，滚轮拉近。","把星群移到视野中央，点击“记录星图”。我会在这里等你的发现。"])
		dialogue_index=0
		_show_line(0)
		dialogue_next.text="收进手记  E" if dialogue_lines.size()==1 else "继续  E"
		dialogue_skip.visible=dialogue_lines.size()>1
		dialogue_panel.visible=true
		_frame_dialogue(npc)
		dialogue_camera.current=true
		return true
	return false

func _frame_dialogue(npc: CharacterBody3D) -> void:
	var toward:=Vector3(player.position.x-npc.position.x,0,player.position.z-npc.position.z).normalized()
	if toward.length_squared()<.01:toward=Vector3.FORWARD
	var target:=npc.position.lerp(player.position,.30)+Vector3.UP*.86
	var space:=world.get_world_3d().direct_space_state
	var exclusions: Array[RID]=[npc.get_rid(),player.get_rid()]
	# Mid shot: try near-wide framings first, then closer ones; keep the least blocked.
	# The speaker's face counts most: the player may stand in the shot but not in front of it.
	var chosen:=npc.position+toward*2.4+Vector3.UP*1.9
	var best_score:=INF
	for distance: float in [6.0,4.6,3.4]:
		for angle: float in [.75,-.75,1.25,-1.25,0.0,1.75,-1.75,PI]:
			var candidate:=npc.position+toward.rotated(Vector3.UP,angle)*distance+Vector3.UP*(1.6+distance*.18)
			var score:=0.0
			for aim in [target,npc.position+Vector3.UP*.5,player.position+Vector3.UP*.8]:
				if not space.intersect_ray(PhysicsRayQueryParameters3D.create(aim,candidate,3,exclusions)).is_empty():score+=1.0
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(npc.position+Vector3.UP*1.15,candidate,3,[npc.get_rid()])).is_empty():score+=4.0
			score+=(6.0-distance)*.05
			if score<best_score:
				best_score=score
				chosen=candidate
		if best_score<1.0:break
	dialogue_camera.near=.08
	dialogue_camera.look_at_from_position(chosen,target)
	npc.dialogue_look_position=chosen

func _open_modal(next_mode: String) -> void:
	mouse_before=Input.mouse_mode
	mode=next_mode
	player.controls_locked=true
	player.velocity.x=0
	player.velocity.z=0
	prompt.visible=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

## A conversation at a doorway (story examines): the same dialogue box, the camera on
## `eye` looking at `focus`. Emits talk_closed when read to the end, skipped or closed.
signal talk_closed
var _talking := false

func show_talk(title: String, lines: Array, focus: Vector3, eye: Vector3) -> bool:
	if mode!="idle" or lines.is_empty():return false
	_open_modal("dialogue")
	current_npc=null
	_talking=true
	dialogue_title.text=title
	speaker_title=title
	dialogue_lines.assign(lines)
	dialogue_index=0
	_show_line(0)
	dialogue_next.text="好的  E" if dialogue_lines.size()==1 else "继续  E"
	dialogue_skip.visible=dialogue_lines.size()>1
	dialogue_panel.visible=true
	dialogue_camera.near=.08
	dialogue_camera.look_at_from_position(eye,focus)
	dialogue_camera.current=true
	return true

func next_dialogue() -> void:
	if mode!="dialogue":return
	dialogue_index+=1
	if _talking and dialogue_index>=dialogue_lines.size():
		close_modal()
		return
	if dialogue_index>=dialogue_lines.size():
		if not current_npc.profile_id in journal.friends:journal.friends.append(current_npc.profile_id)
		_save_journal()
		var finished: String=current_npc.profile_id
		close_modal()
		dialogue_finished.emit(finished)
	else:
		_show_line(dialogue_index)
		dialogue_next.text=("好的  E" if _talking else "收进手记  E") if dialogue_index==dialogue_lines.size()-1 else "继续  E"

var speaker_title := ""
var journal_button: Button
var dialogue_card: StyleBoxFlat
var xiaoguang_card: StyleBoxFlat
var _hand_font: Font
## Who else may speak inside one conversation: a line "芽芽：……" switches the name shown.
const SPEAKERS := ["小光", "芽芽", "眠眠", "老星", "奶奶", "面包师", "孩子", "修灯的邻居", "大家"]

## A line starting with "小光：" is the little star speaking: its own blue card and the
## handwriting font, so it never reads like the person you are talking to. "{name}" is
## the player's name.
func _show_line(index: int) -> void:
	var line: String=dialogue_lines[index]
	var content=world.get("content")
	if content and content.has_method("named"):line=content.named(line)
	if speaker_title=="":speaker_title=dialogue_title.text
	var speaker:=""
	var cut:=line.find("：")
	var me:String=content.player_name() if content and content.has_method("player_name") else ""
	if cut>0 and (line.substr(0,cut) in SPEAKERS or line.substr(0,cut)==me):
		speaker=line.substr(0,cut)
		line=line.substr(cut+1)
	if speaker=="小光":
		if _hand_font==null and ResourceLoader.exists("res://assets/fonts/LXGWWenKai-Regular.ttf"):_hand_font=load("res://assets/fonts/LXGWWenKai-Regular.ttf")
		dialogue_panel.add_theme_stylebox_override("panel",xiaoguang_card)
		dialogue_title.text="✦ 小光"
		dialogue_title.add_theme_color_override("font_color",Color("cfe0ff"))
		if _hand_font:dialogue_body.add_theme_font_override("font",_hand_font)
		dialogue_body.add_theme_font_size_override("font_size",22)
		dialogue_body.add_theme_color_override("font_color",Color("e6efff"))
	else:
		dialogue_panel.add_theme_stylebox_override("panel",dialogue_card)
		dialogue_title.text=speaker if speaker!="" else speaker_title
		dialogue_title.add_theme_color_override("font_color",Color("ffd27d"))
		dialogue_body.remove_theme_font_override("font")
		dialogue_body.add_theme_font_size_override("font_size",19)
		dialogue_body.add_theme_color_override("font_color",Color("eee3cf"))
	dialogue_body.text=line

## Jumps to the end of the conversation; counts as read.
func skip_dialogue() -> void:
	if mode!="dialogue":return
	dialogue_index=dialogue_lines.size()-1
	next_dialogue()

func close_modal() -> void:
	if mode=="idle":return
	if scope_tween:scope_tween.kill()
	if is_instance_valid(current_npc):current_npc.talking=false
	dialogue_panel.visible=false
	scope_ui.visible=false
	journal_panel.visible=false
	mode="idle"
	if _talking:
		_talking=false
		talk_closed.emit.call_deferred()
	player.controls_locked=false
	var camera:=player.arm.get_child(0) as Camera3D
	camera.current=true
	Input.mouse_mode=mouse_before
	_update_status()

func toggle_journal() -> void:
	if mode=="journal":close_modal();return
	if mode!="idle":return
	_open_modal("journal")
	for child in journal_rows.get_children():
		journal_rows.remove_child(child)
		child.queue_free()
	for i in constellations.size():
		if not is_unlocked(i):continue
		var known: bool=i in journal.stars
		var row:=_label(("已记录  ·  " if known else "待发现  ·  ")+constellations[i].title,21)
		journal_rows.add_child(row)
		var description:=_label(story_of(i) if known else "去观星台，用望远镜寻找这张星图。",17)
		description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		description.custom_minimum_size.x=700
		journal_rows.add_child(description)
	for item in [["gardener","芽芽","在花园相识，带着一株小小的嫩芽。"],["astronomer","眠眠","观星台的伙伴，等你一起看完三张星图。"]]:
		var known: bool=item[0] in journal.friends
		journal_rows.add_child(_label(("已相识  ·  " if known else "待相识  ·  ")+item[1],21))
		journal_rows.add_child(_label(item[2] if known else "靠近交谈，把新朋友记在手记里。",17))
	journal_panel.visible=true

func _load_constellations() -> void:
	constellations.clear()
	var parsed=JSON.parse_string(FileAccess.get_file_as_string("res://data/content/constellations.json")) if FileAccess.file_exists("res://data/content/constellations.json") else null
	for raw in (parsed.get("constellations",[]) if parsed is Dictionary else []):
		var entry: Dictionary=raw.duplicate(true)
		entry.direction=Vector3(raw.direction[0],raw.direction[1],raw.direction[2]).normalized()
		var points: Array[Vector2]=[]
		for p in raw.points:points.append(Vector2(p[0],p[1]))
		entry.points=points
		constellations.append(entry)

func constellation_id(index: int) -> String:
	return String(constellations[index].get("id","")) if index>=0 and index<constellations.size() else ""

## Unlocked by a story flag; the first three are always in the sky.
func is_unlocked(index: int) -> bool:
	if index<0 or index>=constellations.size():return false
	var flag:=String(constellations[index].get("unlock",""))
	if flag=="":return true
	var content=world.get("content")
	# "story_gate": waits for its moment in the story only; free roaming sees it at once
	if content!=null and bool(constellations[index].get("story_gate",false)) and content.state.data.mode!="story":return true
	return content!=null and content.state.flag(flag)

func is_complete(index: int) -> bool:
	var flag:=String(constellations[index].get("complete_flag",""))
	var content=world.get("content")
	return flag=="" or (content!=null and content.state.flag(flag))

func story_of(index: int) -> String:
	var entry: Dictionary=constellations[index]
	return String(entry.get("story_complete",entry.story)) if entry.has("story_complete") and is_complete(index) else String(entry.story)

func _rebuild_scope_tabs() -> void:
	if not is_instance_valid(scope_tabs):return
	for child in scope_tabs.get_children():child.queue_free()
	for i in constellations.size():
		if is_unlocked(i):scope_tabs.add_child(_button(constellations[i].title,set_scope_target.bind(i)))

func set_scope_target(index: int,animate := true) -> void:
	if index<0 or index>=constellations.size():return
	if scope_tween:scope_tween.kill()
	var direction: Vector3=constellations[index].direction
	var yaw:=atan2(-direction.x,-direction.z)
	var pitch:=asin(direction.y)
	if animate:
		scope_tween=create_tween().set_parallel(true)
		scope_tween.tween_property(self,"scope_yaw",yaw,.7).set_trans(Tween.TRANS_SINE)
		scope_tween.tween_property(self,"scope_pitch",pitch,.7).set_trans(Tween.TRANS_SINE)
		scope_tween.tween_method(func(_t):_update_scope_rotation(),0.0,1.0,.7)
	else:
		scope_yaw=yaw
		scope_pitch=pitch
		_update_scope_rotation()

func _update_scope_rotation() -> void:
	scope_camera.rotation=Vector3(scope_pitch,scope_yaw,0)

func _update_candidate() -> void:
	candidate=-1
	var forward: Vector3=-scope_camera.global_basis.z
	for i in constellations.size():
		if not is_unlocked(i):continue
		if forward.dot(constellations[i].direction)>cos(deg_to_rad(minf(scope_camera.fov*.22,6))):candidate=i;break
	if candidate<0:
		scope_title.text="云海上的夜空"
		scope_story.text="缓缓转动望远镜，或从左侧选择一张星图。"
		record_button.disabled=true
		record_button.text="寻找星群"
	else:
		scope_title.text=constellations[candidate].title
		scope_story.text=story_of(candidate)
		record_button.disabled=candidate in journal.stars
		record_button.text="已收进手记" if candidate in journal.stars else "记录这张星图"

func record_current() -> bool:
	if mode!="scope":return false
	_update_candidate()
	if candidate<0 or candidate in journal.stars:return false
	journal.stars.append(candidate)
	_save_journal()
	_play_chime()
	star_recorded.emit(candidate)
	_update_candidate()
	return true

func _save_journal() -> void:
	_update_status()
	if "--test-session" in OS.get_cmdline_user_args() and save_path==SAVE_PATH:return
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var file:=FileAccess.open(save_path,FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(journal,"  "))

func load_journal(path := SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):return false
	var loaded=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (loaded is Dictionary and loaded.get("stars") is Array and loaded.get("friends") is Array):return false
	var stars: Array=[]
	var friends: Array=[]
	for index in loaded.stars:
		if (index is int or index is float) and index==int(index) and int(index)>=0 and int(index)<maxi(constellations.size(),3) and not int(index) in stars:stars.append(int(index))
	for id in loaded.friends:
		if id in ["gardener","astronomer"] and not id in friends:friends.append(id)
	journal={"stars":stars,"friends":friends}
	if is_instance_valid(status):_update_status()
	return true

func _update_status() -> void:
	var open_count:=0
	for i in constellations.size():open_count+=1 if is_unlocked(i) else 0
	status.text="小镇手记\n星图 %d / %d · 朋友 %d / 2"%[journal.stars.size(),open_count,journal.friends.size()]

func _play_chime() -> void:
	if DisplayServer.get_name()=="headless":return
	var data:=PackedByteArray()
	data.resize(6615*2)
	for i in 6615:
		var t:=float(i)/22050
		var sample:=sin(TAU*659.25*t)*exp(-t*12)+sin(TAU*987.77*t)*exp(-t*9)*.4
		data.encode_s16(i*2,int(sample*9000))
	var sound:=AudioStreamWAV.new()
	sound.format=AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate=22050
	sound.data=data
	chime.stop()   # stop first: the audio thread may still mix the old one
	chime.stream=sound
	chime.play()
