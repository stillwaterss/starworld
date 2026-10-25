extends RefCounted
## Things the player can look at, open or touch with E (data/content/examines.json).
## An entry has a place ("loc:<id>" or [x, y, z]), a radius, a prompt and variants;
## the first variant whose "when" matches is used. A variant may show a toast ("text")
## or a note card ("note"), set flags, emit an event, play a short pose, open a door,
## let 小光 say something, or start a special sequence (airship, lighthouse, ending).
const DATA := "res://data/content/examines.json"

var content
var entries: Array = []

func setup(owner) -> void:
	content = owner
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
	if parsed is Dictionary:entries = parsed.get("examines", [])
	else:push_warning("examines missing or broken: " + DATA)

func position_of(entry: Dictionary) -> Vector3:
	var at = entry.get("at", [0, 0, 0])
	if at is String:return content.registry.target_position(at)
	return Vector3(at[0], at[1], at[2])

func available(entry: Dictionary) -> bool:
	return content.director._check(entry.get("when", {}), "")

## Nearest usable entry within its radius of `p`, or {}.
func nearest(p: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for entry in entries:
		var at := position_of(entry)
		var d := Vector2(p.x - at.x, p.z - at.z).length()
		if d > float(entry.get("radius", 2.0)) or absf(p.y - at.y) > float(entry.get("height", 3.0)):continue
		if not available(entry):continue
		if d < best_d:
			best_d = d
			best = entry
	return best

func variant(entry: Dictionary) -> Dictionary:
	for v in entry.get("variants", []):
		if content.director._check(v.get("when", {}), ""):return v
	return {}

func prompt(entry: Dictionary) -> String:
	var v := variant(entry)
	return "E  " + String(v.get("prompt", entry.get("prompt", "看看")))

## A doorway conversation: {"talk": {"title": "面包师", "lines": [...]}}. The door (the
## variant's or the entry's "door") stays open while it lasts, its resident in view.
func _talk(entry: Dictionary, v: Dictionary, at: Vector3) -> void:
	var props = content.props
	var door := String(v.get("door", entry.get("door", "")))
	var focus: Vector3 = at + Vector3.UP * .9
	var front: Vector3 = content.world.player.global_position - at
	if props.doors.has(door):
		props.open_door(door, false, true)
		props.doors[door].hold = true
		var c: Vector3 = props._v(props.doors[door].info.centre)
		front = props.doors[door].front
		focus = c + front * .45 + Vector3.DOWN * .25
	front.y = 0
	front = front.normalized() if front.length() > .01 else Vector3.BACK
	var side: Vector3 = front.cross(Vector3.UP)
	var eye: Vector3 = focus + front * 4.4 + side * 1.9 + Vector3.UP * 1.3
	var space: PhysicsDirectSpaceState3D = content.world.get_world_3d().direct_space_state
	for s: float in [1.9, -1.9, 3.0, -3.0, 0.0]:
		var candidate: Vector3 = focus + front * 4.4 + side * s + Vector3.UP * 1.3
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(focus, candidate, 1)).is_empty():
			eye = candidate
			break
	var talk = content.world.interactions
	var lines: Array = []
	for line in v.talk.get("lines", []):lines.append(String(line))
	if talk.show_talk(String(v.talk.get("title", "")), lines, focus, eye):
		await talk.talk_closed
	if props.doors.has(door):props.doors[door].hold = false

## Runs an entry; returns false if nothing applies right now.
func use(entry: Dictionary) -> bool:
	var v := variant(entry)
	if v.is_empty():return false
	var state = content.state
	var once_key := "examined:" + String(entry.id) + ":" + String(v.get("id", "default"))
	var first: bool = not state.flag(once_key)
	state.set_flag(once_key)
	for f in v.get("sets", []):state.set_flag(f)
	var at := position_of(entry)
	var pose := String(v.get("perform", ""))
	var performance = content.world.get("performance")
	if pose != "" and performance and performance.can_start():
		await _perform(performance, pose, at, float(v.get("seconds", 2.0)), v)
	elif v.has("door"):
		content.props.open_door(String(v.door))
	if v.has("talk"):
		await _talk(entry, v, at)
	if v.has("note"):
		await content.ui.show_note(String(v.note.get("title", "")), v.note.get("lines", []))
	elif v.has("text"):
		content.ui.toast(content.named(String(v.text)), float(v.get("text_seconds", 5.0)))
	if v.has("whisper") and (first or bool(v.get("whisper_always", false))):content.ui.whisper(String(v.whisper))
	if v.has("event"):content.events.emit(String(v.event), {"place": entry.id, "first": first})
	if v.has("special"):
		# a lighting is awaited, so what the resident says afterwards follows it
		if String(v.special).begins_with("light:"):
			await content.special(String(v.special), entry, v)
			if v.has("after_talk"):await _talk(entry, {"talk": v.after_talk, "door": v.get("door", "")}, at)
		else:
			content.special(String(v.special), entry, v)
	state.save()
	content.director.evaluate()
	return true

func _perform(performance, pose: String, at: Vector3, seconds: float, v: Dictionary) -> void:
	var player: CharacterBody3D = content.world.player
	if not performance.begin("examine", at, {"distance": float(v.get("cam_distance", 3.0)), "height": float(v.get("cam_height", 1.35)), "look_height": float(v.get("look_height", .9)), "mix": .55}):return
	await performance.turn_to(Vector3(at.x, player.global_position.y, at.z))
	if pose == "polish":performance.hold_prop(performance.cloth())
	if v.has("door"):
		performance.set_pose("knock")
		await performance.animate_pose("knock", .9)
		content.props.open_door(String(v.door))
		performance.set_pose("admire", 4.0)
		await performance.wait(1.0)
	else:
		await performance.animate_pose(pose, seconds)
	if v.has("after"):content.special(String(v.after), {}, v)
	await performance.finish(.7)
