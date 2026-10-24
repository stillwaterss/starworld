extends Node
## Sky, cloud sea, stars and world lighting share the same six-second blend.
const TITLES := ["晴日 · 云海", "傍晚 · 桃色晚风", "夜晚 · 银河"]
var world: Node3D
var sky: ShaderMaterial
var env: Environment
var key: DirectionalLight3D
var clouds: Array[ShaderMaterial] = []
var stars: ShaderMaterial
var current := 2
var weights := Vector3(0,0,1)
var transition: Tween
var sun_colors := [Color("fff2d7"),Color("ffc79e"),Color("bdcdf7")]
var ambient_colors := [Color("c8e1ee"),Color("e2c1df"),Color("aabce9")]

func _ready() -> void:
	name="DayCycle"
	for node in world.get_children():
		if node is WorldEnvironment:env=node.environment
		if node is DirectionalLight3D and not is_instance_valid(key):key=node
	sky=env.sky.sky_material
	for mesh: MeshInstance3D in world.find_children("Clouds*","MeshInstance3D",true,false):
		if mesh.material_override is ShaderMaterial and not mesh.material_override in clouds:clouds.append(mesh.material_override)
	var star_mesh := world.find_child("SkyStars",true,false) as MultiMeshInstance3D
	if star_mesh:stars=star_mesh.material_override
	_apply(weights)

func cycle() -> void:set_time((current+1)%3)

func set_time(index: int,seconds := 6.0) -> void:
	if index<0 or index>2:return
	current=index
	if transition:transition.kill()
	var target:=Vector3.ZERO
	target[index]=1
	if seconds<=0:_apply(target);return
	transition=create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	transition.tween_method(_apply,weights,target,seconds)

func _apply(value: Vector3) -> void:
	weights=value
	sky.set_shader_parameter("time_weights",weights)
	for cloud in clouds:cloud.set_shader_parameter("time_weights",weights)
	if stars:stars.set_shader_parameter("night_amount",weights.z)
	env.ambient_light_color=sun_color(ambient_colors)
	env.ambient_light_energy=Vector3(.48,.39,.34).dot(weights)
	env.fog_light_color=sun_color([Color("c3dce6"),Color("c8a3c2"),Color("7d85ba")])
	key.light_color=sun_color(sun_colors)
	key.light_energy=Vector3(1.25,.95,.88).dot(weights)
	env.fog_density=Vector3(.00065,.00085,.0010).dot(weights)
	key.rotation_degrees=Vector3(-48,-38,0)*weights.x+Vector3(-13,-66,0)*weights.y+Vector3(-46,-34,0)*weights.z

func sun_color(colors: Array) -> Color:
	return colors[0]*weights.x+colors[1]*weights.y+colors[2]*weights.z
