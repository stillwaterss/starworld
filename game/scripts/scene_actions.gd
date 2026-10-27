extends Node3D
## Scene-owned movement and prop presentation; content systems consume scene_event.
signal scene_event(id: String, payload: Dictionary)
const CHAIR := Vector3(-43.8,6,-19.5)
const FACING := Vector3(.913,0,.407)
var world: Node3D
var activities: CanvasLayer
var player: CharacterBody3D
var seat_camera: Camera3D
var lantern: Node3D
var socket: BoneAttachment3D
var seat_state := "free"
var phase := 0.0
var blocked := 0.0
var previous_position := Vector3.ZERO
var transition_start := Vector3.ZERO
var saved_yaw := 0.0
var saved_pitch := 0.0
var saved_mouse := 0
var leave_after_settle := false
var approach := CHAIR+FACING*1.05
## Seated view: two slow framings of the island and sky (←/→), HUD stepped aside.
## (A third, close beside the player, showed the model not quite on the seat: dropped.)
const VISTAS := ["整座小镇", "天色"]
var vista := 0
var vista_clock := 0.0
var hint_layer: CanvasLayer
var hint: Label
var _vista_hidden: Array[CanvasLayer] = []
var _vista_views: Array = []
## Stays in the top-right corner while seated: how to leave, and what the story wants next.
var corner: Label
var _corner_clock := 0.0

func _ready() -> void:
	name="SceneActions"
	player=world.player
	seat_camera=Camera3D.new();seat_camera.name="SeatCamera";seat_camera.fov=69;seat_camera.near=.08;seat_camera.far=1500
	add_child(seat_camera)
	var side:=Vector3(-FACING.z,0,FACING.x)
	seat_camera.look_at_from_position(CHAIR-FACING*4.8+side*1.65+Vector3.UP*2.65,Vector3(0,8,-3))
	_build_hand_lantern()
	hint_layer=CanvasLayer.new();hint_layer.layer=5;add_child(hint_layer)
	hint=Label.new();hint_layer.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left=-420;hint.offset_right=420;hint.offset_top=-58;hint.offset_bottom=-22
	hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size",17)
	hint.add_theme_color_override("font_color",Color("fff1d7"))
	hint.add_theme_color_override("font_outline_color",Color(.08,.08,.16,.85))
	hint.add_theme_constant_override("outline_size",5)
	var font:=preload("res://assets/fonts/LXGWWenKai-Regular.ttf")
	hint.add_theme_font_override("font",font)
	hint.modulate.a=0
	corner=Label.new();hint_layer.add_child(corner)
	corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	corner.offset_left=-420;corner.offset_right=-18;corner.offset_top=70;corner.offset_bottom=110
	corner.grow_horizontal=Control.GROW_DIRECTION_BEGIN
	corner.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	corner.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	corner.add_theme_font_size_override("font_size",19)
	corner.add_theme_color_override("font_color",Color("fff1d7"))
	corner.add_theme_color_override("font_outline_color",Color(.08,.08,.16,.85))
	corner.add_theme_constant_override("outline_size",4)
	corner.add_theme_font_override("font",font)
	corner.modulate.a=.92
	corner.visible=false

func vista_transform(index: int) -> Transform3D:
	if _vista_views.size()!=VISTAS.size():_vista_views=_plan_vistas()
	var view: Array=_vista_views[index]
	var eye: Vector3=view[0]
	var look: Vector3=view[1]
	var drift:=Vector3(sin(vista_clock*.07),sin(vista_clock*.05)*.4,cos(vista_clock*.06))*(.35 if index==0 else .12)
	return Transform3D(Basis.looking_at(look+drift*2.0-eye),eye+drift)

## Eye/look pairs for the three framings, each nudged until nothing (fence posts, the
## chair back, the islet's trees) stands between the camera and what it frames.
func _plan_vistas() -> Array:
	var side:=Vector3(-FACING.z,0,FACING.x)
	var town:=Vector3(-3,3.2,-2)
	var views:=[]
	# 0: the whole island from high above and behind the chair, like a bird resting there:
	#    higher than anyone could sit, so the town, the islets and the sea of clouds all fit
	views.append(_first_clear([CHAIR-FACING*7.0+Vector3.UP*13.0-side*2.0,CHAIR-FACING*6.0+Vector3.UP*11.0+side*2.0,CHAIR-FACING*4.0+Vector3.UP*9.0],town+Vector3.DOWN*2.5,town))
	# 1: the sky, from above the chair back, over the fence line
	var sky:=CHAIR+FACING*30+Vector3.UP*12
	views.append(_first_clear([CHAIR-FACING*.5+Vector3.UP*2.3+side*.5,CHAIR-FACING*.2+Vector3.UP*2.6-side*.5,CHAIR+Vector3.UP*2.9],sky,sky))
	return views

func _first_clear(eyes: Array,look: Vector3,must_see: Vector3) -> Array:
	var space:=world.get_world_3d().direct_space_state
	var skip:=[player.get_rid()]
	for eye: Vector3 in eyes:
		var towards:=(must_see-eye).normalized()
		var reach:=minf(eye.distance_to(must_see)-.35,8.0)
		var q:=PhysicsRayQueryParameters3D.create(eye,eye+towards*reach,3,skip)
		if not space.intersect_ray(q).is_empty():continue
		var room:=PhysicsShapeQueryParameters3D.new()
		var ball:=SphereShape3D.new();ball.radius=.35
		room.shape=ball;room.transform=Transform3D(Basis(),eye);room.collision_mask=3;room.exclude=skip
		if not space.intersect_shape(room,1).is_empty():continue
		return [eye,look]
	return [eyes[0],look]

func vista_fov(index: int) -> float:
	return [50.0,58.0,46.0][index]

func _enter_vista() -> void:
	# Hide the close foreground silhouette in both seated vistas.
	player.model.visible=false
	vista=0;vista_clock=0.0;_vista_views=_plan_vistas()
	# (from the host's V17.1) the player's own hat right under the high camera showed as a
	# pale triangle: the seated views leave the player out of the picture
	player.model.visible=false
	var cycle=world.get("day_cycle")
	if cycle and "fog_scale" in cycle:cycle.fog_scale=.3;cycle._apply(cycle.weights)
	_vista_hidden.clear()
	for node in world.get_children():
		if node is CanvasLayer and node.visible:_vista_hidden.append(node);node.visible=false
	hint.text="←/→ 换个角度看（%s） · T 换天色 · O 拍照 · C 起身"%VISTAS[vista]
	var t:=create_tween();t.tween_property(hint,"modulate:a",1.0,.8);t.tween_interval(5.0);t.tween_property(hint,"modulate:a",0.0,1.5)
	_corner_clock=0.0;_update_corner();corner.visible=true

## Only the keys that move the story on stay in the corner: T while the story waits for
## a change of sky, and C to get up. Everything else was shown once, at the bottom.
func _update_corner() -> void:
	var keys:=[]
	var content=world.get("content")
	if content and content.director and content.director.state.data.started and not content.director.main_done():
		var stage: Dictionary=content.director.main_stage()
		if JSON.stringify(stage.get("done",{})).contains("\"sky\""):keys.append("T 换天色")
	keys.append("C 起身")
	corner.text="  ·  ".join(keys)

func _leave_vista() -> void:
	player.model.visible=true
	corner.visible=false
	player.model.visible=true
	var cycle=world.get("day_cycle")
	if cycle and "fog_scale" in cycle:cycle.fog_scale=1.0;cycle._apply(cycle.weights)
	for node in _vista_hidden:
		if is_instance_valid(node):node.visible=true
	_vista_hidden.clear()
	hint.modulate.a=0

func in_vista() -> bool:return seat_state=="seated"

func _input(event: InputEvent) -> void:
	if seat_state!="seated" or activities.photo:return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_LEFT,KEY_RIGHT,KEY_A,KEY_D]:
		vista=(vista+(1 if event.physical_keycode in [KEY_RIGHT,KEY_D] else VISTAS.size()-1))%VISTAS.size()
		hint.text="%s · ←/→ 换角度 · T 换天色 · C 起身"%VISTAS[vista]
		var t:=create_tween();t.tween_property(hint,"modulate:a",1.0,.3);t.tween_interval(2.5);t.tween_property(hint,"modulate:a",0.0,1.2)
		get_viewport().set_input_as_handled()

func _process_vista(delta: float) -> void:
	vista_clock+=delta
	_corner_clock+=delta
	if _corner_clock>1.0:_corner_clock=0.0;_update_corner()
	var goal:=vista_transform(vista)
	var k:=1.0-exp(-delta*.9)
	seat_camera.global_transform=seat_camera.global_transform.interpolate_with(goal,k)
	seat_camera.fov=lerpf(seat_camera.fov,vista_fov(vista),k)

func _material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new();m.albedo_color=color;m.roughness=.65
	if emission>0:m.emission_enabled=true;m.emission=color;m.emission_energy_multiplier=emission
	return m

func _piece(mesh: Mesh, where: Vector3, material: Material) -> MeshInstance3D:
	var node:=MeshInstance3D.new();node.mesh=mesh;node.position=where;node.material_override=material;lantern.add_child(node)
	return node

func _cylinder(where: Vector3,radius: float,height: float,mat: Material,top := -1.0) -> void:
	var m:=CylinderMesh.new();m.bottom_radius=radius;m.top_radius=radius if top<0 else top;m.height=height;m.radial_segments=16;m.rings=1
	_piece(m,where,mat)

func _build_hand_lantern() -> void:
	var skeletons: Array[Node]=player.model.find_children("*","Skeleton3D",true,false)
	lantern=Node3D.new();lantern.name="HandheldLantern";world.add_child(lantern)
	if skeletons.is_empty():lantern.visible=false;return
	socket=BoneAttachment3D.new();socket.bone_name="hand.R";socket.name="LanternHandSocket";skeletons[0].add_child(socket)
	var bronze:=_material(Color("71553b"));var gold:=_material(Color("b8975c"))
	var ring:=TorusMesh.new();ring.inner_radius=.068;ring.outer_radius=.087;ring.rings=20;ring.ring_segments=8
	var handle:=_piece(ring,Vector3(0,-.075,0),bronze);handle.rotation.x=PI/2
	_cylinder(Vector3(0,-.19,0),.135,.075,bronze,.075)
	_cylinder(Vector3(0,-.425,0),.125,.045,bronze)
	_cylinder(Vector3(0,-.45,0),.10,.025,gold)
	var glass:=_material(Color(.97,.78,.37,.20));glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;glass.cull_mode=BaseMaterial3D.CULL_DISABLED
	_cylinder(Vector3(0,-.31,0),.105,.20,glass)
	for i in 4:
		var a:=i*TAU/4+PI/4;_cylinder(Vector3(cos(a)*.10,-.31,sin(a)*.10),.012,.23,gold)
	var flame:=SphereMesh.new();flame.radius=.045;flame.height=.13;flame.radial_segments=12;flame.rings=6
	_piece(flame,Vector3(0,-.31,0),_material(Color("ffd994"),1.5))
	var light:=OmniLight3D.new();light.light_color=Color("ffe0a4");light.light_energy=.65;light.omni_range=3.4;light.position.y=-.31;lantern.add_child(light)
	lantern.visible=false

func toggle_lantern() -> bool:
	if not is_instance_valid(socket):return false
	lantern.visible=not lantern.visible
	player.model.holding_lantern=lantern.visible
	scene_event.emit("lantern_enabled",{"enabled":lantern.visible,"handheld":true})
	return true

func _process(_delta: float) -> void:
	if not is_instance_valid(socket):return
	lantern.global_position=socket.global_position+player.model.global_basis*Vector3(0,-.01,-.025)
	lantern.global_rotation=Vector3(0,player.model.global_rotation.y,.035*sin(Time.get_ticks_msec()*.003))

func toggle_seat() -> bool:
	if activities.photo or world.interactions.mode!="idle":return false
	if seat_state=="walking" or seat_state=="turning":
		_finish_standing();activities.say("先继续走走。");return true
	if seat_state=="seated":
		seat_state="rising";phase=0;transition_start=player.position;_leave_vista();return true
	if seat_state=="lowering":leave_after_settle=true;return true
	if seat_state!="free":return false
	if player.position.distance_to(CHAIR)>3.2:activities.say("观景椅在左侧高桥尽头的小岛，面向整座小镇。");return false
	# Refuse to cut through furniture or a house to reach the chair's front.
	var query:=PhysicsRayQueryParameters3D.create(player.position+Vector3.UP*.6,approach+Vector3.UP*.6,3,[player.get_rid()])
	if not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty():activities.say("从椅子前面靠近，给自己留一条路。");return false
	saved_yaw=player.cam_yaw;saved_pitch=player.cam_pitch;saved_mouse=Input.mouse_mode
	seat_state="walking";phase=0;blocked=0;previous_position=player.position;leave_after_settle=false
	player.controls_locked=true;player.scripted_active=true;player.scripted_speed=1.65
	activities.say("走到椅子前，准备坐下。C 或 Esc 可取消。")
	return true

func _physics_process(delta: float) -> void:
	if seat_state=="seated" and seat_camera.current:_process_vista(delta)
	if seat_state=="free" or seat_state=="seated":return
	phase+=delta
	if seat_state=="walking":
		var difference:=approach-player.position;difference.y=0
		if difference.length()<.13:
			player.scripted_active=false;player.velocity=Vector3.ZERO;player.model.set_locomotion(0,true)
			seat_state="turning";phase=0;return
		player.scripted_direction=difference.normalized()
		blocked=blocked+delta if player.position.distance_to(previous_position)<delta*.15 else 0.0
		previous_position=player.position
		if blocked>.7 or phase>5:
			_finish_standing();activities.say("前面有东西挡着，换个方向靠近椅子。");return
	elif seat_state=="turning":
		player.model.rotation.y=lerp_angle(player.model.rotation.y,atan2(-FACING.x,-FACING.z),minf(1,delta*7))
		if phase>.55:
			player.set_physics_process(false);player.model.set_seated(true);player.model.seat_blend=0
			transition_start=player.position;seat_state="lowering";phase=0;seat_camera.current=true
	elif seat_state=="lowering":
		var t:=smoothstep(0.0,1.0,minf(phase/.85,1.0))
		player.position=transition_start.lerp(_seat_point(),t)
		player.model.seat_blend=t
		if phase>=.85:
			seat_state="seated";activities.sitting=true
			activities.mark("坐看云海");activities.say("坐看小镇与云海。T 换天色，C 或 Esc 起身。")
			scene_event.emit("seat_settled",{"location_id":"remote_chair"})
			_enter_vista()
			if leave_after_settle:seat_state="rising";phase=0;transition_start=player.position;_leave_vista()
	elif seat_state=="rising":
		var t:=smoothstep(0.0,1.0,minf(phase/.8,1.0))
		player.position=transition_start.lerp(approach+Vector3.UP*.05,t);player.model.seat_blend=1-t
		if phase>=.8:
			_finish_standing();activities.say("起身了，继续走走。")
			scene_event.emit("seat_left",{"location_id":"remote_chair"})

## Where the player's root rests when seated: on the seat's top surface, found by rays
## (the seat is slatted, so the highest of several), a little back toward the backrest.
var _seat_cache := Vector3.INF
func _seat_point() -> Vector3:
	if _seat_cache!=Vector3.INF:return _seat_cache
	var space:=world.get_world_3d().direct_space_state
	var side:=Vector3(-FACING.z,0,FACING.x)
	var top:=-INF
	for along: float in [-.25,-.15,-.05,.05]:
		for across: float in [-.1,0.0,.1]:
			var probe:=CHAIR+FACING*along+side*across
			var q:=PhysicsRayQueryParameters3D.create(probe+Vector3.UP*.95,probe+Vector3.DOWN*.5,0xFFFFFFFF,[player.get_rid()])
			var hit:=space.intersect_ray(q)
			if not hit.is_empty():top=maxf(top,hit.position.y)
	_seat_cache=(CHAIR-FACING*.08)+Vector3.UP*(top-CHAIR.y+.005 if top>CHAIR.y+.2 else .16)
	return _seat_cache

func _finish_standing() -> void:
	seat_state="free";activities.sitting=false;player.scripted_active=false;player.scripted_direction=Vector3.ZERO
	player.model.set_seated(false);player.model.rotation.x=0;player.model.set_locomotion(0,true)
	player.controls_locked=false;player.velocity=Vector3.ZERO;player.set_physics_process(true)
	player.cam_yaw=saved_yaw;player.cam_pitch=saved_pitch;player.arm.get_child(0).current=true
	Input.mouse_mode=saved_mouse
