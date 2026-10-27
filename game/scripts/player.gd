extends CharacterBody3D
## Third-person controller with replaceable visual model and locomotion animation.

const WALK_SPEED := 4.5
const RUN_SPEED := 8.0
const JUMP_VELOCITY := 7.5
const GRAVITY := 22.0
const GROUND_ACCEL := 40.0
const AIR_ACCEL := 15.0
const MOUSE_SENS := 0.0035
const COYOTE_TIME := 0.12      # 走出平台边缘后仍可起跳的时间
const JUMP_BUFFER := 0.12      # 落地前提前按跳也算数
const FALL_LIMIT := -45.0

var spawn_point := Vector3.ZERO
var capture_mouse := true
var controls_locked := false
var scripted_active := false
var scripted_direction := Vector3.ZERO
var scripted_speed := 1.65
var test_dir := Vector3.ZERO   # 自动测试用, 非零时覆盖键盘输入
var cam_yaw := 0.0
var cam_pitch := -0.32

var model: Node3D
var pivot: Node3D
var arm: SpringArm3D
var _coyote := 0.0
var _jump_buf := 0.0
var _was_on_floor := true


func _ready() -> void:
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.3
	floor_constant_speed = true   # 上下楼梯/坡道时水平速度不打折
	safe_margin = 0.035
	max_slides = 8
	collision_mask = 1 | 2        # 地形 + 细小障碍物都要撞

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.58
	shape.shape = cap
	shape.position.y = 0.79
	add_child(shape)

	_build_model()

	pivot = Node3D.new()
	pivot.position.y = 1.1
	add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = 5.5
	arm.margin = 0.2
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	arm.shape = probe
	arm.add_excluded_object(get_rid())
	arm.collision_mask = 1        # 相机只躲大块地形
	pivot.add_child(arm)
	var cam := Camera3D.new()
	cam.fov = 62
	cam.far = 1500
	arm.add_child(cam)
	cam.current = true

	if capture_mouse and not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_model() -> void:
	model = preload("res://scripts/actor_visual.gd").new()
	model.profile_id = "player"
	add_child(model)


func _unhandled_input(event: InputEvent) -> void:
	if controls_locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * MOUSE_SENS
		cam_pitch = clampf(cam_pitch - event.relative.y * MOUSE_SENS, -1.25, 0.4)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				arm.spring_length = maxf(arm.spring_length - 0.5, 2.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				arm.spring_length = minf(arm.spring_length + 0.5, 12.0)
			_:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func jump() -> void:
	_jump_buf = JUMP_BUFFER


## A fall puts the player back on the island they fell from (content sets respawn_hook:
## the lighthouse island's pier while the ship is moored there), else the square.
var respawn_hook: Callable

func respawn() -> void:
	global_position = respawn_hook.call() if respawn_hook.is_valid() else spawn_point
	velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = COYOTE_TIME
	else:
		_coyote -= delta
		velocity.y -= GRAVITY * delta

	_jump_buf -= delta
	if not controls_locked and Input.is_action_just_pressed("jump"):
		jump()
	if _jump_buf > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buf = 0.0
		_coyote = 0.0
		if model.using_fallback: model.scale = Vector3(0.8, 1.25, 0.8)

	var dir := test_dir
	if controls_locked:
		dir = scripted_direction if scripted_active else Vector3.ZERO
		_jump_buf = 0.0
	elif dir == Vector3.ZERO:
		var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		dir = Basis(Vector3.UP, cam_yaw) * Vector3(iv.x, 0, iv.y)
	var speed := RUN_SPEED if Input.is_action_pressed("run") else WALK_SPEED
	if scripted_active:speed=scripted_speed
	var accel := GROUND_ACCEL if on_floor else AIR_ACCEL
	var hv := Vector2(velocity.x, velocity.z).move_toward(Vector2(dir.x, dir.z) * speed, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.y

	_step_up(delta)
	move_and_slide()

	if dir.length() > 0.1:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-dir.x, -dir.z), 12.0 * delta)
	model.set_locomotion(Vector2(velocity.x, velocity.z).length(), is_on_floor())
	if is_on_floor() and not _was_on_floor and model.using_fallback:
		model.scale = Vector3(1.25, 0.75, 1.25)   # 落地压扁一下
	_was_on_floor = is_on_floor()
	model.scale = model.scale.lerp(Vector3.ONE, 10.0 * delta)

	if global_position.y < FALL_LIMIT:
		respawn()
	pivot.rotation = Vector3(cam_pitch, cam_yaw, 0)


func _step_up(delta: float) -> void:
	# Cross shallow paving and bridge thresholds, without teleporting through walls.
	if not is_on_floor() or velocity.y > 0.0:
		return
	var motion := Vector3(velocity.x,0,velocity.z)*delta
	if motion.length_squared() < .000001 or not test_move(global_transform,motion):
		return
	var up := Vector3.UP*.23
	if test_move(global_transform,up):
		return
	var raised := global_transform
	raised.origin += up
	if test_move(raised,motion):
		return
	# A floor must exist immediately after the step; edges remain ordinary gravity.
	raised.origin += motion
	var hit := KinematicCollision3D.new()
	if test_move(raised,-up*1.2,hit) and hit.get_normal().y > .65:
		global_position.y += maxf(.0,.23-hit.get_travel().length())


static func _mat(color: Color, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


## 五角星棱柱, 正面朝 -Z, 中心在原点。Godot 以顺时针为正面。
static func _star_mesh(r_out: float, r_in: float, depth: float, points := 5) -> ArrayMesh:
	var ring: Array[Vector2] = []
	for i in points * 2:
		var a := PI / 2 + i * PI / points
		ring.append(Vector2(cos(a), sin(a)) * (r_out if i % 2 == 0 else r_in))
	var zf := -depth / 2
	var zb := depth / 2
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := ring.size()
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		st.set_normal(Vector3(0, 0, -1))
		for v in [Vector3(0, 0, zf), Vector3(a.x, a.y, zf), Vector3(b.x, b.y, zf)]:
			st.add_vertex(v)
		st.set_normal(Vector3(0, 0, 1))
		for v in [Vector3(0, 0, zb), Vector3(b.x, b.y, zb), Vector3(a.x, a.y, zb)]:
			st.add_vertex(v)
		var e := b - a
		st.set_normal(Vector3(e.y, -e.x, 0).normalized())
		var af := Vector3(a.x, a.y, zf)
		var ab := Vector3(a.x, a.y, zb)
		var bf := Vector3(b.x, b.y, zf)
		var bb := Vector3(b.x, b.y, zb)
		for v in [af, ab, bb, af, bb, bf]:
			st.add_vertex(v)
	return st.commit()
