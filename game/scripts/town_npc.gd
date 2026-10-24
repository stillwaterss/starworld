extends CharacterBody3D
var profile_id := "gardener"
var display_name := "芽芽"
var home := Vector3.ZERO
var talking := false
var visual: Node3D
var player: CharacterBody3D
var clock := 0.0
var dialogue_look_position := Vector3.ZERO

func _ready() -> void:
	collision_layer=2
	collision_mask=3
	floor_snap_length=.35
	var shape:=CollisionShape3D.new()
	var capsule:=CapsuleShape3D.new()
	capsule.radius=.30
	capsule.height=1.45
	shape.shape=capsule
	shape.position.y=.725
	add_child(shape)
	visual=preload("res://scripts/actor_visual.gd").new()
	visual.profile_id=profile_id
	add_child(visual)
	var label:=Label3D.new()
	label.text=display_name
	var font:=SystemFont.new()
	font.font_names=PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Source Han Sans SC", "WenQuanYi Zen Hei"])
	font.fallbacks = [preload("res://assets/fonts/NotoSansSC.ttf")]
	label.font=font
	label.position.y=1.84
	label.font_size=36
	label.outline_size=4
	label.outline_modulate=Color(.10,.12,.20,.8)
	label.visibility_range_end=18
	label.pixel_size=.006
	label.modulate=Color("fff0cf")
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test=false
	add_child(label)

func _physics_process(delta: float) -> void:
	clock+=delta
	velocity.y-=22*delta
	var close:=is_instance_valid(player) and player.global_position.distance_to(global_position)<3.8
	var target:=home+Vector3(sin(clock*.22)*.5,0,cos(clock*.22)*.35)
	var direction:=Vector3(target.x-position.x,0,target.z-position.z)
	if talking or close:
		velocity.x=0
		velocity.z=0
		if close:
			direction=Vector3(player.position.x-position.x,0,player.position.z-position.z)
		if talking:
			direction=Vector3(dialogue_look_position.x-position.x,0,dialogue_look_position.z-position.z)
	else:
		var move:=direction.normalized()*.35 if direction.length()>.12 else Vector3.ZERO
		velocity.x=move.x
		velocity.z=move.z
	if direction.length()>.1:
		visual.rotation.y=lerp_angle(visual.rotation.y,atan2(-direction.x,-direction.z),delta*3)
	visual.waving=close and not talking
	move_and_slide()
	visual.set_locomotion(Vector2(velocity.x,velocity.z).length(),is_on_floor())
