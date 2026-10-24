extends Node
## Route hint toward the tracked objective or a place picked on the map.
## Shows a short run of small light dots on the walkable path ahead (not a big
## arrow) and a little star over the target. Off when the player turns it off.
signal arrived(target: String)

const DOTS := 12
const SPACING := 1.3
const AHEAD := 1.6
const REPATH := .6

var content
var route := PackedVector3Array()
var target := ""
var remaining := 0.0
var straight := false           # true when no walkable route is known (shown as such)
var dots: MultiMeshInstance3D
var marker: MeshInstance3D
var _timer := 0.0
var _arrived_for := ""
var _clock := 0.0

func _ready() -> void:
	name = "Guide"
	dots = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var mesh := SphereMesh.new()
	mesh.radius = .1
	mesh.height = .2
	mesh.radial_segments = 8
	mesh.rings = 4
	mm.mesh = mesh
	mm.instance_count = DOTS
	dots.multimesh = mm
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = false
	dots.material_override = material
	dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dots.custom_aabb = AABB(Vector3(-200, -60, -200), Vector3(400, 160, 400))
	content.world.add_child.call_deferred(dots)
	marker = MeshInstance3D.new()
	var star := PrismMesh.new()
	star.size = Vector3(.32, .42, .08)
	marker.mesh = star
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color("ffe3a3")
	marker.material_override = glow
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	content.world.add_child.call_deferred(marker)

func enabled() -> bool:
	var audio = content.world.get("audio")
	return audio == null or bool(audio.settings.get("guide", true))

func current_target() -> String:
	var manual: String = content.state.data.guide_target
	if manual != "":return manual
	return String(content.director.tracked().get("target", ""))

## Picked on the map; "" goes back to the tracked objective.
func set_manual(target_id: String) -> void:
	content.state.data.guide_target = target_id
	content.state.save()
	refresh_route(true)

func refresh_route(force := false) -> void:
	var next := current_target()
	if next != target:
		target = next
		_arrived_for = ""
		force = true
	if target == "" or not content.grid.ready:
		route = PackedVector3Array()
		remaining = 0.0
		return
	var from: Vector3 = content.world.player.global_position
	var goal: Vector3 = content.registry.target_position(target)
	# The keeper's island is only reachable by airship: lead to the right dock first
	via = ""
	if _on_keeper(from) != _on_keeper(goal) and content.registry.has("keeper_isle"):
		via = "乘飞艇"
		goal = content.registry.position_of("keeper_dock" if _on_keeper(from) else "dock")
	if not force and route.size() > 1 and _distance_to_route(from) < 2.5:
		_trim(from)
		return
	route = content.grid.path(from, goal)
	straight = route.is_empty()
	if straight:route = PackedVector3Array([from, goal])
	_trim(from)

var via := ""

## "up"/"down" when a low ledge the player jumps (Space) lies within the next few metres.
func hop_ahead(reach := 8.0) -> String:
	var walked := 0.0
	for i in range(route.size() - 1):
		if walked > reach:break
		if content.grid.is_hop(route[i], route[i + 1]):return "up" if route[i + 1].y > route[i].y else "down"
		walked += route[i].distance_to(route[i + 1])
	return ""

func _on_keeper(p: Vector3) -> bool:
	if not content.registry.has("keeper_isle"):return false
	var c: Vector3 = content.registry.position_of("keeper_isle")
	return Vector2(p.x - c.x, p.z - c.z).length() < 15.0 and p.y > c.y - 4.0

func _distance_to_route(p: Vector3) -> float:
	var best := INF
	for i in range(mini(route.size(), 8)):best = minf(best, p.distance_to(route[i]))
	return best

func _trim(from: Vector3) -> void:
	var closest := 0
	var best := INF
	for i in range(mini(route.size(), 12)):
		var d := from.distance_to(route[i])
		if d < best:
			best = d
			closest = i
	if closest > 0:route = route.slice(closest)
	remaining = content.grid.length_of(route) + from.distance_to(route[0]) if route.size() > 0 else 0.0

func _process(delta: float) -> void:
	_clock += delta
	_timer -= delta
	if _timer <= 0:
		_timer = REPATH
		refresh_route()
	var show: bool = enabled() and target != "" and content.world.interactions.mode == "idle" and not _photo()
	var trail: bool = show and bool(content.world.audio.settings.get("breadcrumbs", true)) if content.world.get("audio") else show
	_draw_dots(trail and not straight)
	marker.visible = show
	if show:
		var goal: Vector3 = content.registry.target_position(target)
		marker.global_position = goal + Vector3(0, 2.55 + sin(_clock * 2) * .08, 0)
		marker.rotation.y = _clock * 1.2
		var near: bool = content.world.player.global_position.distance_to(goal) < content.registry.target_radius(target)
		if near and _arrived_for != target:
			_arrived_for = target
			arrived.emit(target)
			if content.state.data.guide_target == target:
				content.state.data.guide_target = ""
				content.state.save()

func _photo() -> bool:
	var cozy = content.world.get("activities")
	return cozy != null and bool(cozy.photo)

func _draw_dots(visible_now: bool) -> void:
	var mm := dots.multimesh
	if not visible_now or route.size() < 2:
		dots.visible = false
		return
	dots.visible = true
	var player: Vector3 = content.world.player.global_position
	var walked := 0.0
	var segment := 0
	var along := 0.0
	var placed := 0
	var want := AHEAD + fmod(_clock * .9, SPACING)
	while placed < DOTS and segment < route.size() - 1:
		var a := route[segment]
		var b := route[segment + 1]
		var length := a.distance_to(b)
		if walked + length - along >= want:
			along += want - walked
			walked = want
			var p := a.lerp(b, along / maxf(length, .001))
			var fade := 1.0 - float(placed) / DOTS
			var lift := .22 + sin(_clock * 3 + placed) * .03
			mm.set_instance_transform(placed, Transform3D(Basis.IDENTITY, p + Vector3.UP * lift))
			mm.set_instance_color(placed, Color(1, .86, .5, .95 * fade * clampf(p.distance_to(player) - .8, 0, 1)))
			placed += 1
			want += SPACING
		else:
			walked += length - along
			along = 0.0
			segment += 1
	for i in range(placed, DOTS):
		mm.set_instance_color(i, Color(1, 1, 1, 0))

## Angle (radians) of the next route point relative to the camera, 0 = straight ahead.
func screen_heading() -> float:
	if route.size() < 1:return 0.0
	var camera: Camera3D = content.world.get_viewport().get_camera_3d()
	if not camera:return 0.0
	var player: Vector3 = content.world.player.global_position
	var aim := route[mini(route.size() - 1, 3)]
	var to := Vector3(aim.x - player.x, 0, aim.z - player.z)
	var forward: Vector3 = -camera.global_basis.z
	forward.y = 0
	if to.length_squared() < .01 or forward.length_squared() < .01:return 0.0
	return forward.normalized().signed_angle_to(to.normalized(), Vector3.DOWN)
