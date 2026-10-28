extends Node
## Main story (3 chapters) and side stories. Stages complete from real state
## (flowers, stars, sky blend, seat) or from events while the stage is active,
## so early, repeated or out-of-order actions never stall or pay twice.
signal objective_changed
signal stage_completed(quest: String, title: String)
signal chapter_completed(title: String, outro: String)
signal message(text: String)
signal stage_started(quest: String, stage: Dictionary)

const STORY := "res://data/content/story.json"
const DIALOGUE := "res://data/content/dialogue.json"

var world: Node3D
var registry
var events
var state                         # story_state.gd
var main: Array = []
var sides: Dictionary = {}        # id -> definition
var side_order: Array = []
var lines: Dictionary = {}        # npc -> {title, entries}
var served: Dictionary = {}       # npc -> entry the open dialogue came from
var _evaluating := false

func setup(owner_world: Node3D, location_registry, content_events, story_state) -> void:
	name = "StoryDirector"
	world = owner_world
	registry = location_registry
	events = content_events
	state = story_state
	var story = _json(STORY)
	main = story.get("main", [])
	for entry in story.get("side", []):
		sides[entry.id] = entry
		side_order.append(entry.id)
	lines = _json(DIALOGUE)
	lines.erase("version")
	lines.erase("note")
	events.content_event.connect(_on_event)

func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if parsed is Dictionary:return parsed
	push_warning("content data missing or broken: " + path)
	return {}

# ------------------------------------------------------------------ quests
func start_story() -> void:
	state.data.mode = "story"
	if not state.data.started:
		state.data.started = true
		state.add_log(main[0].title + " —— " + main[0].intro)
		message.emit(main[0].title)
	state.data.track = "main" if not state.data.main.done else state.data.track
	evaluate()
	state.save()
	objective_changed.emit()

func choose_free_roam() -> void:
	state.data.mode = "free"
	state.save()
	objective_changed.emit()

func main_done() -> bool:return bool(state.data.main.done)

func chapter() -> Dictionary:
	var index: int = state.data.main.chapter
	return main[index] if index < main.size() else {}

func main_stage() -> Dictionary:
	if not state.data.started or main_done():return {}
	var stages: Array = chapter().get("stages", [])
	var index: int = state.data.main.stage
	return stages[index] if index < stages.size() else {}

func side_stage(id: String) -> Dictionary:
	if not sides.has(id):return {}
	var entry: Dictionary = state.side(id)
	var stages: Array = sides[id].stages
	return stages[entry.stage] if entry.state in ["active", "paused"] and entry.stage < stages.size() else {}

func side_state(id: String) -> String:
	if not sides.has(id):return "locked"
	var entry: Dictionary = state.side(id)
	if entry.state == "locked" and _check(sides[id].get("unlock", {}), "") and state.flag("offered_" + id):
		entry.state = "available"
	return entry.state

func start_side(id: String) -> bool:
	if not side_state(id) in ["available", "paused"]:return false
	state.side(id).state = "active"
	state.data.track = id
	state.data.stage_events[id] = state.data.stage_events.get(id, [])
	if state.claim("side_start:" + id):state.add_log("小故事 · " + sides[id].title + " —— " + sides[id].intro)
	evaluate()
	state.save()
	objective_changed.emit()
	return true

func pause_side(id: String) -> bool:
	if side_state(id) != "active":return false
	state.side(id).state = "paused"
	if state.data.track == id:state.data.track = "main"
	state.save()
	objective_changed.emit()
	return true

func track(quest: String) -> void:
	if quest == "main" or side_state(quest) == "active":
		state.data.track = quest
		state.data.guide_target = ""
		state.save()
		objective_changed.emit()

## What the HUD and guide show: {quest, heading, title, hint, target, progress}
func tracked() -> Dictionary:
	var quest: String = state.data.track
	if quest != "main" and side_state(quest) != "active":quest = "main"
	if quest == "main":
		var stage := main_stage()
		if stage.is_empty():return {}
		var out_main := {"quest": "main", "heading": chapter().title, "title": stage.title, "hint": stage.hint, "target": _target_of(stage), "progress": _progress_text(stage)}
		var next := checklist_step(stage)
		if not next.is_empty():
			out_main.hint = next.text
			out_main.target = next.target
		return out_main
	var stage := side_stage(quest)
	var out := {"quest": quest, "heading": "小故事 · " + sides[quest].title, "title": stage.title, "hint": stage.hint, "target": _target_of(stage), "progress": _progress_text(stage)}
	var step := checklist_step(stage)
	if not step.is_empty():
		out.hint = step.text
		out.target = step.target
	return out

## For a stage with a "checklist" (several people, each wanting one thing): the first
## unfinished item, as {text, target}: what to do for it, or, once that is done, to go
## back and tell them. {} when the stage has no checklist or every item is done.
func checklist_step(stage: Dictionary) -> Dictionary:
	var items: Array = stage.get("checklist", [])
	var left := 0
	for item in items:left += 0 if state.flag(item.done) else 1
	for item in items:
		if state.flag(item.done):continue
		var ready := _check(item.get("ready", {}), "")
		var text := String(item.back if ready else item.todo)
		if left > 1:text += "（还有 %d %s）" % [left - 1, String(stage.get("unit", "位"))]
		return {"text": text, "target": String(item.back_target if ready else item.todo_target)}
	return {}

## A stage that asks to visit several places points at the nearest one not seen yet.
func _target_of(stage: Dictionary) -> String:
	var target := String(stage.get("target", ""))
	var places: Array = stage.get("visit", stage.get("done", {}).get("discovered", []))
	if target != "" or places.is_empty():return target
	# "visit" pairs each place with the progress flag of the same index
	var flags: Array = stage.get("progress", {}).get("flags", [])
	var best := ""
	var best_distance := INF
	for i in places.size():
		var id: String = places[i]
		if i < flags.size() and state.flag(flags[i]):continue
		if flags.is_empty() and id in state.data.discovered:continue
		if not registry.has(id):continue
		var d := _player_position().distance_to(registry.position_of(id))
		if d < best_distance:
			best_distance = d
			best = "loc:" + id
	return best

func _progress_text(stage: Dictionary) -> String:
	var spec: Dictionary = stage.get("progress", {})
	if spec.has("count"):return "%d / %d" % [mini(_value(spec.count), int(spec.of)), int(spec.of)]
	if spec.has("discovered"):
		var seen := 0
		for id in spec.discovered:seen += 1 if id in state.data.discovered else 0
		return "%d / %d" % [seen, spec.discovered.size()]
	if spec.has("star_ids"):
		var got := 0
		for sid in spec.star_ids:got += 1 if _star_known(sid) else 0
		return "%d / %d" % [got, spec.star_ids.size()]
	if spec.has("flags"):
		var have := 0
		for name in spec.flags:have += 1 if state.flag(name) else 0
		return "%d / %d" % [have, spec.flags.size()]
	return ""

# ------------------------------------------------------------------ events
func _on_event(id: String, data: Dictionary) -> void:
	state.set_flag("ev_" + id)
	if id == "chime_rung" and data.get("sky", -1) >= 0:state.set_flag("chime_" + events.SKY_NAMES[data.sky])
	# facts other conditions read, recorded before this event is evaluated
	if id == "star_recorded":
		var talk = world.get("interactions")
		if talk and talk.has_method("constellation_id"):state.set_flag("star_" + talk.constellation_id(int(data.get("index", -1))))
	if id == "time_settled" and int(data.get("index", -1)) == 1:
		var scene = world.get("scene_actions")
		if (scene and scene.seat_state == "seated") or _player_position().distance_to(registry.position_of("remote_chair")) < 9:state.set_flag("dusk_watched")
	var record := {"id": id, "sky": events.sky_name(), "npc": String(data.get("npc", "")), "quest": String(data.get("quest", "")), "place": String(data.get("place", ""))}
	var where := _player_position()
	record["pos"] = [where.x, where.y, where.z]
	for quest in _active_quests():
		var list: Array = state.data.stage_events.get(quest, [])
		list.append(record)
		if list.size() > 24:list.pop_front()
		state.data.stage_events[quest] = list
	evaluate()
	state.save()

func _active_quests() -> Array:
	var out := []
	if state.data.started and not main_done():out.append("main")
	for id in side_order:
		if side_state(id) == "active":out.append(id)
	return out

## Advances every active quest as far as its conditions already allow.
func evaluate() -> void:
	if _evaluating:return
	_evaluating = true
	var guard := 0
	var moved := true
	while moved and guard < 24:
		moved = false
		guard += 1
		var stage := main_stage()
		if not stage.is_empty() and _check(stage.done, "main"):
			_complete_main(stage)
			moved = true
		for id in side_order:
			if side_state(id) != "active":continue
			var side := side_stage(id)
			if side.is_empty():continue
			if _check(side.done, id):
				_complete_side(id, side)
				moved = true
	_evaluating = false

func _complete_main(stage: Dictionary) -> void:
	if state.claim("stage:" + stage.id):
		state.add_log("完成 · " + stage.title)
		stage_completed.emit("main", stage.title)
	state.data.stage_events["main"] = []
	state.data.main.stage += 1
	call_deferred("_announce", "main")
	var current := chapter()
	if state.data.main.stage >= current.stages.size():
		if state.claim("chapter:" + current.id):
			state.add_log(current.title + " · 完 —— " + current.outro)
			if String(current.get("reaction", "")) != "":state.set_flag("reaction_" + current.reaction)
			if String(current.get("constellation", "")) != "":
				state.set_flag("constellation_" + current.constellation)
				state.set_flag("constellation_new")
			chapter_completed.emit(current.title, current.outro)
		state.data.main.chapter += 1
		state.data.main.stage = 0
		if state.data.main.chapter >= main.size():
			state.data.main.done = true
			state.data.main.chapter = main.size() - 1
			state.data.main.stage = main[-1].stages.size()
			state.add_log("主线完结。小镇还在，随时可以回来走走。")
		else:
			state.add_log(chapter().title + " —— " + chapter().intro)
	objective_changed.emit()

func _complete_side(id: String, stage: Dictionary) -> void:
	if state.claim("stage:" + stage.id):
		state.add_log(sides[id].title + " · " + stage.title)
		stage_completed.emit(id, stage.title)
	state.data.stage_events[id] = []
	var entry: Dictionary = state.side(id)
	entry.stage += 1
	call_deferred("_announce", id)
	if entry.stage >= sides[id].stages.size():
		entry.state = "done"
		if state.claim("side_done:" + id):
			state.add_log("小故事完成 · " + sides[id].title + " —— " + sides[id].outro)
			if String(sides[id].get("constellation", "")) != "":
				state.set_flag("constellation_" + sides[id].constellation)
				state.set_flag("constellation_new")
			chapter_completed.emit("小故事 · " + sides[id].title, sides[id].outro)
		if state.data.track == id:state.data.track = "main"
	objective_changed.emit()

func _announce(quest: String) -> void:
	var stage := main_stage() if quest == "main" else side_stage(quest)
	if not stage.is_empty():stage_started.emit(quest, stage)

# ------------------------------------------------------------------ conditions
func _player_position() -> Vector3:
	return world.player.global_position if is_instance_valid(world) and is_instance_valid(world.player) else Vector3.ZERO

func _value(name: String) -> int:
	match name:
		"flowers":
			var cozy = world.get("activities")
			return int(cozy.progress.flowers) if cozy else 0
		"stars":
			var talk = world.get("interactions")
			return talk.journal.stars.size() if talk else 0
	return 0

## quest is whose stage_events "talk"/"event" look at ("" = none).
func _check(cond: Dictionary, quest: String) -> bool:
	for key in cond:
		var want = cond[key]
		var ok := true
		match key:
			"all":
				for c in want:ok = ok and _check(c, quest)
			"any":
				ok = false
				for c in want:ok = ok or _check(c, quest)
			"not":ok = not _check(want, quest)
			"flowers", "stars":ok = _value(key) >= int(want)
			"watered":
				var cozy = world.get("activities")
				ok = cozy != null and bool(cozy.progress.watered) == bool(want)
			"sky":
				if cond.has("event"):continue
				ok = events.sky_name() == want
			"seated":ok = events.is_sitting() == bool(want)
			"near":
				if cond.has("event"):continue
				ok = _player_position().distance_to(registry.position_of(want)) <= float(cond.get("r", registry.radius_of(want)))
			"r", "is", "of":continue
			"flag":ok = state.flag(want)
			"discovered":
				for id in want:ok = ok and id in state.data.discovered
			"stage":ok = not main_stage().is_empty() and main_stage().id == want
			"side_stage":ok = _side_stage_is(want)
			"side_state":ok = side_state(want) == String(cond.get("is", "active"))
			"chapter_done":ok = _chapter_done(want)
			"main_done":ok = main_done() == bool(want)
			"talk":ok = _happened(quest, {"id": "npc_talked", "npc": want})
			"event":ok = _happened(quest, {"id": want, "sky": cond.get("sky", ""), "near": cond.get("near", ""), "r": cond.get("r", 0), "place": cond.get("place", "")})
			"place":continue
			"star_ids":
				for sid in want:ok = ok and _star_known(sid)
			_:ok = false
		if not ok:return false
	return true

## A constellation counts once it is in the journal, even when it was recorded in free
## roaming before the story asked for it (the telescope then refuses to record it again).
func _star_known(sid: String) -> bool:
	if state.flag("star_" + sid):return true
	var talk = world.get("interactions")
	if talk and talk.has_method("constellation_id"):
		for index in talk.journal.stars:
			if talk.constellation_id(int(index)) == sid:return true
	return false

func _side_stage_is(stage_id: String) -> bool:
	for id in side_order:
		if side_state(id) == "active" and side_stage(id).get("id", "") == stage_id:return true
	return false

func _chapter_done(chapter_id: String) -> bool:
	for i in main.size():
		if main[i].id == chapter_id:return main_done() or int(state.data.main.chapter) > i
	return false

func _happened(quest: String, want: Dictionary) -> bool:
	if quest == "":return false
	for record in state.data.stage_events.get(quest, []):
		if record.id != want.id:continue
		if want.has("npc") and record.npc != want.npc:continue
		if String(want.get("place", "")) != "" and String(record.get("place", "")) != want.place:continue
		if want.id == "npc_talked" and record.quest != "" and record.quest != quest:continue
		if String(want.get("sky", "")) != "" and record.sky != want.sky:continue
		if String(want.get("near", "")) != "":
			var at := Vector3(record.pos[0], record.pos[1], record.pos[2])
			if at.distance_to(registry.position_of(want.near)) > float(want.r):continue
		return true
	return false

# ------------------------------------------------------------------ dialogue
## Lines for an NPC right now: tracked quest's stage lines first, then by priority,
## ties rotate by least recently heard. A pending side-story offer is appended.
func dialogue_for(npc: String) -> Dictionary:
	var book: Dictionary = lines.get(npc, {})
	var best: Dictionary = {}
	var best_score := -INF
	var offer: Dictionary = {}
	var tracked_quest: String = tracked().get("quest", "")
	var order: Array = state.data.heard_order
	for entry in book.get("entries", []):
		if entry.get("once", false) and state.data.heard.has(entry.id):continue
		if not _check(entry.when, ""):continue
		if entry.has("unlocks"):
			if offer.is_empty():offer = entry
			continue
		var quest := _quest_of(entry)
		var score := float(entry.priority) + (50.0 if quest != "" and quest == tracked_quest else 0.0)
		# recently heard lines sink a little, never below the next priority step
		score -= .01 * float(order.rfind(entry.id) + 1) if order.has(entry.id) else 0.0
		score += .001 if not state.data.heard.has(entry.id) else 0.0
		if score > best_score:
			best_score = score
			best = entry
	var chosen: Array = []
	if not best.is_empty():chosen.append_array(best.lines)
	if not offer.is_empty():chosen.append_array(offer.lines)
	# after the story, small talk gives way to their new lines (quests and offers stay)
	if main_done() and _quest_of(best) == "" and offer.is_empty():
		var content = world.get("content")
		var line: String = content.npcs.after_story_line(npc) if content and content.npcs else ""
		if line != "":chosen = [line]
	if chosen.is_empty():chosen = ["……"]
	served[npc] = {"entry": best.get("id", ""), "offer": offer.get("id", ""), "quest": _quest_of(best), "sets": best.get("sets", ""), "unlocks": offer.get("unlocks", "")}
	return {"title": registry.npc_name(npc) + "  ·  " + String(book.get("title", "")), "lines": chosen, "quest": _quest_of(best)}

func _quest_of(entry: Dictionary) -> String:
	var when: Dictionary = entry.get("when", {})
	if when.has("stage"):return "main"
	if when.has("side_stage"):
		for id in side_order:
			for stage in sides[id].stages:
				if stage.id == when.side_stage:return id
	if when.has("any"):
		for c in when.any:
			if c.has("stage"):return "main"
	if when.has("all"):
		for c in when.all:
			if c.has("stage"):return "main"
	return ""

## Called when the player read the dialogue to its end (or skipped to the end).
func dialogue_finished(npc: String) -> Dictionary:
	var info: Dictionary = served.get(npc, {})
	for id in [info.get("entry", ""), info.get("offer", "")]:
		if id == "":continue
		state.data.heard[id] = int(state.data.heard.get(id, 0)) + 1
		state.data.heard_order.erase(id)
		state.data.heard_order.append(id)
		if state.data.heard_order.size() > 40:state.data.heard_order.pop_front()
	if String(info.get("sets", "")) != "":state.set_flag(info.sets)
	if String(info.get("unlocks", "")) != "":
		state.set_flag("offered_" + info.unlocks)
		if side_state(info.unlocks) == "available":message.emit("新的小故事：" + sides[info.unlocks].title + "（P 打开故事本）")
	return info
