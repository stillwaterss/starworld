extends RefCounted
## Stable location IDs -> where the player should stand, facing and radius.
## Order of truth: register() from scene code > Marker3D "Anchor_<id>" (or group
## content_anchor with meta location_id) > script constant named in "bind" > JSON default.
## Story, map and guide only ever ask this object, never hold coordinates themselves.
const DATA := "res://data/content/locations.json"

var world: Node3D
var entries: Dictionary = {}     # id -> {name, short, position, anchor, radius, facing, source, ...}
var npc_homes: Dictionary = {}
var overrides: Dictionary = {}   # id -> {position, radius, facing} from register()

func setup(owner_world: Node3D) -> void:
	world = owner_world
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
	if not data is Dictionary:
		push_warning("location data missing: " + DATA)
		data = {"locations": {}, "npcs": {}}
	for id in data.get("locations", {}):
		var raw: Dictionary = data.locations[id]
		entries[id] = raw.duplicate(true)
	npc_homes = data.get("npcs", {})
	refresh()

## Scene side (Codex) can call this after moving a chair/door; content follows at once.
func register(id: String, position: Vector3, radius := -1.0, facing := Vector3.ZERO) -> void:
	overrides[id] = {"position": position, "radius": radius, "facing": facing}
	if not entries.has(id):
		entries[id] = {"name": id, "short": id, "kind": "place"}
	refresh()

func refresh() -> void:
	var anchors := {}
	if is_instance_valid(world):
		for node in world.get_tree().get_nodes_in_group("content_anchor"):
			if node is Node3D and node.has_meta("location_id"):anchors[String(node.get_meta("location_id"))] = node
		for node in world.find_children("Anchor_*", "Node3D", true, false):
			anchors[String(node.name).trim_prefix("Anchor_")] = node
	for id in entries:
		var entry: Dictionary = entries[id]
		var fallback := _vec(entry.get("position", [0, 0, 0]))
		var position := fallback
		var source := "json_default"
		var scene_point = _scene_meta(id)
		if scene_point != null:
			position = scene_point + _vec(entry.get("meta_offset", entry.get("bind_offset", [0, 0, 0])))
			source = "scene_meta:locations_v11"
		var bound = _bound(String(entry.get("bind", "")))
		if bound != null:
			position = bound + _vec(entry.get("bind_offset", [0, 0, 0]))
			source = "bind:" + String(entry.bind)
		if anchors.has(id):
			var anchor: Node3D = anchors[id]
			position = anchor.global_position
			entry["facing"] = -anchor.global_basis.z
			source = "anchor:" + String(anchor.name)
		if overrides.has(id):
			position = overrides[id].position
			if overrides[id].radius > 0:entry["radius"] = overrides[id].radius
			if overrides[id].facing != Vector3.ZERO:entry["facing"] = overrides[id].facing
			source = "register()"
		entry["resolved"] = position
		entry["source"] = source

## island_meta.json "locations_v11" written by the Blender scene script (object positions).
func _scene_meta(id: String):
	if not is_instance_valid(world) or not world.has_method("get_scene_location"):return null
	var point: Vector3 = world.get_scene_location(id)
	return null if point == Vector3.INF else point

func _bound(path: String):
	if path.is_empty() or not is_instance_valid(world):return null
	var parts := path.split(".")
	var holder = world.get(parts[0])
	if holder == null or not is_instance_valid(holder):return null
	var value = holder.get(parts[1])
	if value == null and holder.get_script():value = holder.get_script().get_script_constant_map().get(parts[1])
	return value if value is Vector3 else null

func _vec(raw) -> Vector3:
	return Vector3(raw[0], raw[1], raw[2]) if raw is Array and raw.size() == 3 else Vector3.ZERO

func has(id: String) -> bool:return entries.has(id)
func ids() -> Array:return entries.keys()
func position_of(id: String) -> Vector3:return entries[id].get("resolved", Vector3.ZERO) if entries.has(id) else Vector3.ZERO
func radius_of(id: String) -> float:return float(entries[id].get("radius", 3.0)) if entries.has(id) else 3.0
func name_of(id: String) -> String:return String(entries[id].get("name", id)) if entries.has(id) else id
func short_of(id: String) -> String:return String(entries[id].get("short", name_of(id))) if entries.has(id) else id
func info(id: String) -> Dictionary:return entries.get(id, {})
func on_map(id: String) -> bool:return bool(entries.get(id, {}).get("map", true))

## Live NPC position; falls back to the NPC's home location.
func npc_position(id: String) -> Vector3:
	if is_instance_valid(world) and world.get("interactions") and is_instance_valid(world.interactions):
		for npc in world.interactions.npcs:
			if npc.profile_id == id:return npc.global_position
	var home := String(npc_homes.get(id, {}).get("home", ""))
	return position_of(home)

func npc_name(id: String) -> String:return String(npc_homes.get(id, {}).get("name", id))

## Target strings used everywhere: "loc:garden", "npc:gardener".
func target_position(target: String) -> Vector3:
	if target.begins_with("npc:"):return npc_position(target.substr(4))
	return position_of(target.trim_prefix("loc:"))

func target_name(target: String) -> String:
	if target.begins_with("npc:"):return npc_name(target.substr(4))
	return name_of(target.trim_prefix("loc:"))

func target_radius(target: String) -> float:
	return 2.6 if target.begins_with("npc:") else radius_of(target.trim_prefix("loc:"))

func report() -> Dictionary:
	var out := {}
	for id in entries:
		var p: Vector3 = entries[id].get("resolved", Vector3.ZERO)
		out[id] = {"position": [snappedf(p.x, .01), snappedf(p.y, .01), snappedf(p.z, .01)], "source": entries[id].get("source", ""), "radius": radius_of(id)}
	return out
