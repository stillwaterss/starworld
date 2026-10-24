extends Node
## One place where content events come from. Stable IDs:
## flower_planted, flower_watered, star_recorded, seat_settled, seat_left,
## wish_released, lantern_enabled, time_settled, npc_talked, chime_rung,
## stones_skipped, photo_taken, waved, shop_visited, place_arrived.
## npc_talked is emitted by content_root after the story director knows which
## quest the finished dialogue belonged to. Adapters connect to the real v10 nodes; where the scene has no signal yet
## (seat), a clearly labelled fallback watches state instead.
signal content_event(id: String, data: Dictionary)

const SKY_NAMES := ["day", "dusk", "night"]
var world: Node3D
var settled_sky := -1           # index whose weight reached 1, -1 while blending
var seat_mode := "none"         # "signal" from scene, "v10_state_fallback", "none"
var lantern_mode := "none"      # only "signal" counts as a real hand lantern
var _was_sitting := false
var history: Array[Dictionary] = []   # last events, for tests and logs

func setup(owner_world: Node3D) -> void:
	world = owner_world
	name = "ContentEvents"
	var talk = world.get("interactions")
	if talk:
		if talk.has_signal("star_recorded"):talk.star_recorded.connect(func(index: int):emit("star_recorded", {"index": index}))
	var cozy = world.get("activities")
	# v11 scene: scene_actions owns the walk-turn-sit process and the hand lantern
	var scene = world.get("scene_actions")
	if scene and scene.has_signal("scene_event"):
		scene.scene_event.connect(_on_scene_event)
		seat_mode = "signal"
		lantern_mode = "signal"
	if cozy:
		if cozy.has_signal("content_event"):cozy.content_event.connect(emit)
		if seat_mode == "signal":pass
		elif cozy.has_signal("seat_settled"):
			cozy.seat_settled.connect(func(data := {}):emit("seat_settled", data))
			seat_mode = "signal"
		elif cozy.get("sitting") != null:
			seat_mode = "v10_state_fallback"
		if not scene and cozy.has_signal("seat_left"):cozy.seat_left.connect(func(data := {}):emit("seat_left", data))
		if not scene and cozy.has_signal("lantern_enabled"):
			cozy.lantern_enabled.connect(func(data := {}):emit("lantern_enabled", data))
			lantern_mode = "signal"

func _on_scene_event(id: String, payload: Dictionary) -> void:
	# lantern_enabled is sent on both switching on and off; only "on" is the content event
	if id == "lantern_enabled" and not bool(payload.get("enabled", true)):return
	emit(id, payload)

func emit(id: String, data := {}) -> void:
	var entry := data.duplicate()
	entry["id"] = id
	entry["sky"] = settled_sky
	history.append(entry)
	if history.size() > 80:history.pop_front()
	content_event.emit(id, entry)

func sky_name() -> String:return SKY_NAMES[settled_sky] if settled_sky >= 0 else "changing"

func is_sitting() -> bool:
	var cozy = world.get("activities")
	return cozy != null and bool(cozy.get("sitting"))

func _process(_delta: float) -> void:
	if not is_instance_valid(world):return
	var cycle = world.get("day_cycle")
	if cycle:
		var weights: Vector3 = cycle.weights
		var index: int = cycle.current
		# time_settled means the blend reached its target, not just that T was pressed
		if weights[index] >= .999:
			if settled_sky != index:
				settled_sky = index
				emit("time_settled", {"index": index, "name": SKY_NAMES[index]})
		elif settled_sky >= 0:
			settled_sky = -1
	if seat_mode == "v10_state_fallback":
		var sitting := is_sitting()
		if sitting != _was_sitting:
			_was_sitting = sitting
			emit("seat_settled" if sitting else "seat_left", {"source": "v10_state_fallback"})
