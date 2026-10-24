extends Node3D
## Shared visual root: future GLB replacement does not affect controls or dialogue.
var profile_id := "player"
var using_fallback := true
var model_path_override := ""
var left_arm: Node3D
var right_arm: Node3D
var clock := 0.0
var waving := false
var animation_player: AnimationPlayer
var animation_names: Dictionary = {}
var locomotion_speed := 0.0
var grounded := true
var seated := false
var seat_blend := 1.0
var holding_lantern := false
var body_skeleton: Skeleton3D
var idle_rotations: Dictionary = {}
var idle_positions: Dictionary = {}
var animation_state := ""
## Performance pose layer (performance.gd): bone name -> Quaternion in skeleton space,
## applied on top of the bone's rest orientation; other bones keep the idle frame.
var performing := false
var perform_pose: Dictionary = {}
var perform_speed := 7.0
var _perform_current: Dictionary = {}

func _ready() -> void:
	name = "ModelRoot"
	var profiles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/character_profiles.json"))
	var profile: Dictionary = profiles[profile_id]
	var path: String = profile.model if model_path_override.is_empty() else model_path_override
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed:
			var imported := packed.instantiate() as Node3D
			if imported:
				add_child(imported)
				imported.rotation.y += deg_to_rad(float(profile.yaw_degrees))
				var bounds := AABB()
				var first := true
				for mesh: MeshInstance3D in imported.find_children("*","MeshInstance3D",true,false):
					var box: AABB = (global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb()
					bounds = box if first else bounds.merge(box)
					first = false
				if not first and bounds.size.y>.01:
					var factor := float(profile.height)/bounds.size.y
					imported.scale *= factor
					var center := bounds.get_center()
					imported.position = imported.position*factor-Vector3(center.x,bounds.position.y,center.z)*factor
					using_fallback = false
					_setup_animations(imported)
					return
	_build_fallback(Color(profile.color))

func _process(delta: float) -> void:
	clock += delta
	if not using_fallback:
		_update_animation()
		_apply_scene_pose()
	if using_fallback:
		position.y = sin(clock*1.8)*.015
		if left_arm: left_arm.rotation.z = .15+sin(clock*2.0)*.04
		if right_arm: right_arm.rotation.z = (1.7+sin(clock*5.0)*.2) if waving else -.15+sin(clock*2.0+.7)*.04

func _setup_animations(imported: Node3D) -> void:
	var players := imported.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty(): return
	animation_player = players[0]
	for key in animation_player.get_animation_list():
		for state in ["idle", "walk", "run", "jump", "wave"]:
			if str(key).to_lower().ends_with(state):
				animation_names[state] = key
				animation_player.get_animation(key).loop_mode = Animation.LOOP_LINEAR
	_update_animation()
	animation_player.advance(0)
	var skeletons:=find_children("*","Skeleton3D",true,false)
	if not skeletons.is_empty():
		body_skeleton=skeletons[0]
		for i in body_skeleton.get_bone_count():
			idle_rotations[i]=body_skeleton.get_bone_pose_rotation(i)
			idle_positions[i]=body_skeleton.get_bone_pose_position(i)

func set_locomotion(speed: float, on_ground: bool) -> void:
	locomotion_speed = speed
	grounded = on_ground
	_update_animation()

func set_seated(value: bool) -> void:
	seated=value
	seat_blend=1.0 if value else 0.0
	if not is_instance_valid(animation_player):return
	if seated:
		if animation_names.has("idle"):
			animation_player.play(animation_names.idle);animation_player.advance(0);animation_player.pause()
	else:
		animation_state="";_update_animation()
	_apply_scene_pose()

## Starts or ends the performance layer; poses ease in and back out to idle.
func set_performing(value: bool) -> void:
	if value == performing:return
	performing = value
	if value and is_instance_valid(animation_player) and animation_names.has("idle"):
		animation_player.play(animation_names.idle, .2)
		animation_player.advance(0)
		animation_player.pause()
	if not value:
		perform_pose = {}

func set_pose(pose: Dictionary, speed := 7.0) -> void:
	perform_pose = pose
	perform_speed = speed

## Local pose rotation that turns the bone by `q` (skeleton space) from its rest direction.
func _posed_local(bone: int, q: Quaternion) -> Quaternion:
	var parent := body_skeleton.get_bone_parent(bone)
	var p := body_skeleton.get_bone_global_rest(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	return (p.inverse() * q * p) * body_skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()

func _apply_performance(delta: float) -> void:
	var settled := true
	var k := 1.0 - exp(-perform_speed * delta)
	for i in body_skeleton.get_bone_count():
		var name := body_skeleton.get_bone_name(i)
		var target: Quaternion = _posed_local(i, perform_pose[name]) if perform_pose.has(name) else idle_rotations.get(i, Quaternion.IDENTITY)
		var current: Quaternion = _perform_current.get(i, idle_rotations.get(i, Quaternion.IDENTITY))
		current = current.slerp(target, k)
		_perform_current[i] = current
		body_skeleton.set_bone_pose_rotation(i, current)
		if current.angle_to(idle_rotations.get(i, Quaternion.IDENTITY)) > .01:settled = false
	if not performing and settled:
		_perform_current.clear()
		animation_state = ""
		_update_animation()

func _apply_scene_pose() -> void:
	if not is_instance_valid(body_skeleton):return
	if performing or not _perform_current.is_empty():
		_apply_performance(get_process_delta_time())
		return
	if seated:
		for i in idle_rotations:
			body_skeleton.set_bone_pose_rotation(i,idle_rotations[i])
			body_skeleton.set_bone_pose_position(i,idle_positions[i])
		for bone_name in ["foot.L","foot.R"]:
			var i:=body_skeleton.find_bone(bone_name)
			if i>=0:body_skeleton.set_bone_pose_rotation(i,idle_rotations[i]*Quaternion(Vector3.RIGHT,-1.05*seat_blend))
		var spine:=body_skeleton.find_bone("spine")
		if spine>=0:
			body_skeleton.set_bone_pose_position(spine,idle_positions[spine]+Vector3(0,-.035*seat_blend,0))
			body_skeleton.set_bone_pose_rotation(spine,idle_rotations[spine]*Quaternion(Vector3.RIGHT,-.06*seat_blend))
	if holding_lantern:
		var arm:=body_skeleton.find_bone("arm.R")
		if arm>=0:body_skeleton.set_bone_pose_rotation(arm,idle_rotations[arm]*Quaternion(Vector3.UP,.16))

func _update_animation() -> void:
	if seated or performing or not _perform_current.is_empty():return
	if not is_instance_valid(animation_player): return
	var state := "idle"
	if not grounded: state = "jump"
	elif waving: state = "wave"
	elif locomotion_speed > 5.5: state = "run"
	elif locomotion_speed > .15: state = "walk"
	if not animation_names.has(state): state = "idle"
	if not animation_names.has(state): return
	if animation_state != state:
		animation_player.play(animation_names[state], .14)
		animation_state = state
	animation_player.speed_scale = clampf(locomotion_speed / 3.0, .7, 2.8) if state in ["walk", "run"] else 1.0

func _sphere(parent: Node3D,pos: Vector3,size: Vector3,color: Color,glow := 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = .5
	sphere.height = 1
	sphere.radial_segments = 12
	sphere.rings = 6
	mesh.mesh = sphere
	mesh.scale = size
	mesh.position = pos
	mesh.material_override = _material(color,glow)
	parent.add_child(mesh)
	return mesh

func _material(color: Color,glow := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = .83
	if glow>0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	return mat

func _build_fallback(color: Color) -> void:
	_sphere(self,Vector3(0,.48,0),Vector3(.63,.72,.48),color)
	_sphere(self,Vector3(0,.49,-.225),Vector3(.37,.45,.065),Color("f7e6c9"))
	for x in [-.17,.17]:
		_sphere(self,Vector3(x,.14,-.04),Vector3(.25,.25,.39),color.darkened(.08))
	var head := MeshInstance3D.new()
	head.mesh = _soft_star()
	head.material_override = _material(color,.08)
	head.position.y = 1.13
	add_child(head)
	_sphere(self,Vector3(0,1.08,-.16),Vector3(.56,.50,.11),Color("ffe6c1"))
	for x in [-.105,.105]:
		_sphere(self,Vector3(x,1.105,-.222),Vector3(.047,.070,.024),Color("3a2839"))
		_sphere(self,Vector3(x+.006,1.124,-.236),Vector3(.014,.018,.008),Color("fff5df"))
		_sphere(self,Vector3(x*1.7,1.025,-.208),Vector3(.075,.045,.016),Color("e8a4a1"))
	_sphere(self,Vector3(0,1.018,-.225),Vector3(.045,.025,.016),Color("ac6d65"))
	for sign in [-1,1]:
		var arm := Node3D.new()
		arm.position = Vector3(sign*.31,.69,0)
		add_child(arm)
		_sphere(arm,Vector3(0,-.14,0),Vector3(.19,.40,.20),color)
		if sign<0:left_arm=arm
		else:right_arm=arm
	if profile_id=="gardener":
		_sphere(self,Vector3(0,.55,-.32),Vector3(.13,.15,.13),Color("bb9a68"))
		_sphere(self,Vector3(-.04,.68,-.32),Vector3(.16,.08,.06),Color("8ab888"))
		_sphere(self,Vector3(.04,.72,-.32),Vector3(.13,.08,.06),Color("a0c99c"))
	elif profile_id=="astronomer":
		var book := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(.30,.10,.22)
		book.mesh=box
		book.position=Vector3(0,.58,-.32)
		book.rotation.x=-.35
		book.material_override=_material(Color("617aaa"))
		add_child(book)

static func _soft_star() -> ArrayMesh:
	var ring: Array[Vector2]=[]
	for i in 10:
		var a:=PI/2+i*PI/5
		ring.append(Vector2(cos(a),sin(a))*(.46 if i%2==0 else .275))
	var outline: Array[Vector2]=[]
	for i in 10:
		var p: Vector2=ring[i]
		var a: Vector2=p.lerp(ring[(i+9)%10],.22)
		var b: Vector2=p.lerp(ring[(i+1)%10],.22)
		for j in 4:
			var t:=float(j)/3
			outline.append(a*(1-t)*(1-t)+p*2*t*(1-t)+b*t*t)
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in outline.size():
		var a: Vector2=outline[i]
		var b: Vector2=outline[(i+1)%outline.size()]
		for v in [Vector3(0,0,-.18),Vector3(b.x,b.y,-.09),Vector3(a.x,a.y,-.09),Vector3(0,0,.16),Vector3(a.x,a.y,.09),Vector3(b.x,b.y,.09),Vector3(a.x,a.y,-.09),Vector3(b.x,b.y,-.09),Vector3(b.x,b.y,.09),Vector3(a.x,a.y,-.09),Vector3(b.x,b.y,.09),Vector3(a.x,a.y,.09)]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()
