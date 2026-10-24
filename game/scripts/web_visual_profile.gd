extends RefCounted
## Browser-renderer calibration only. Desktop art and lighting remain the source.
static var _profile: Dictionary = {}
static func apply(cycle: Node) -> void:
	if _profile.is_empty():
		_profile = JSON.parse_string(FileAccess.get_file_as_string("res://data/web_visual_profile.json"))
	var a: Array = _profile.ambient_scale
	cycle.env.ambient_light_energy *= Vector3(a[0], a[1], a[2]).dot(cycle.weights)
	var lift: Array = _profile.sky_night_lift
	cycle.sky.set_shader_parameter("web_night_lift", Vector3(lift[0], lift[1], lift[2]))
