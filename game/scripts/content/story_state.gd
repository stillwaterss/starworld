extends RefCounted
## Story progress, stored apart from journal.json / cozy.json. Version 1.
## Unknown or broken files never block the game: broken ones are kept beside
## as *.broken and a fresh state starts; missing fields are filled from defaults.
const VERSION := 1
const PATH := "user://story.json"
const SIDE_STATES := ["locked", "available", "active", "paused", "done"]

var path := PATH
var persistent := true          # false in --test-session unless a test path is given
var data: Dictionary = {}
var load_note := ""             # what happened on load, for logs/tests

static func defaults() -> Dictionary:
	return {
		"version": VERSION,
		"started": false,
		"mode": "",              # "" not chosen yet, "story", "free"
		"main": {"chapter": 0, "stage": 0, "done": false},
		"side": {},              # id -> {state, stage}
		"flags": {},             # permanent facts, e.g. met_gardener, chime_dusk, ev_wish_released
		"stage_events": {},      # quest id -> [events while its current stage was active]
		"rewards": [],           # reward ids already given (never twice)
		"log": [],               # [{t, text}]
		"discovered": [],        # location ids seen up close
		"heard": {},             # dialogue entry id -> times heard
		"heard_order": [],       # recent entry ids, oldest first
		"track": "main",         # quest the guide follows
		"guide_target": "",      # manual map target, "" follows the tracked quest
		"player_name": "星仔",   # the player's star person; renamed on the title card or in settings
		"story_rev": STORY_REV,  # which story the chapter/stage numbers belong to
		"autostart": false,      # set by 新游戏 just before the island reloads
	}

## The v16 story has different stages: a save from an older one keeps its chapter but
## starts that chapter again from its first stage.
const STORY_REV := 16

func reset() -> void:
	data = defaults()

func load_state() -> void:
	reset()
	if not persistent:
		load_note = "memory_only"
		return
	if not FileAccess.file_exists(path):
		load_note = "new"
		return
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		_keep_broken(text)
		load_note = "broken_reset"
		return
	data = migrate(parsed)
	load_note = "loaded_v%d" % int(parsed.get("version", 0))
	if int(parsed.get("story_rev", 0)) < STORY_REV:
		data.story_rev = STORY_REV
		if not bool(data.main.done):data.main.stage = 0
		data.stage_events = {}
		load_note += "_story_rev_reset"

## Fills missing fields and drops wrong types; never raises.
static func migrate(raw: Dictionary) -> Dictionary:
	var out := defaults()
	for key in out:
		if not raw.has(key):continue
		var value = raw[key]
		if typeof(value) == typeof(out[key]):out[key] = value
	var main: Dictionary = out.main
	var last_chapter:=4
	var story: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/content/story.json"))
	if story is Dictionary and story.get("main") is Array:last_chapter=maxi(0,story.main.size()-1)
	main["chapter"] = clampi(int(main.get("chapter", 0)), 0, last_chapter)
	main["stage"] = maxi(int(main.get("stage", 0)), 0)
	main["done"] = bool(main.get("done", false))
	var side := {}
	for id in out.side:
		var entry = out.side[id]
		if entry is Dictionary and String(entry.get("state", "")) in SIDE_STATES:
			side[id] = {"state": String(entry.state), "stage": maxi(int(entry.get("stage", 0)), 0)}
	out.side = side
	if out.log.size() > 80:out.log = out.log.slice(out.log.size() - 80)
	out.version = VERSION
	return out

func _keep_broken(text: String) -> void:
	var file := FileAccess.open(path + ".broken", FileAccess.WRITE)
	if file:file.store_string(text)

func save() -> void:
	if not persistent:return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not file:return
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))

func flag(name: String) -> bool:return bool(data.flags.get(name, false))
func set_flag(name: String) -> void:data.flags[name] = true

## Returns true only the first time; used so a reward is never given twice.
func claim(reward: String) -> bool:
	if reward in data.rewards:return false
	data.rewards.append(reward)
	return true

func add_log(text: String) -> void:
	data.log.append({"t": Time.get_datetime_string_from_system(), "text": text})
	if data.log.size() > 80:data.log.pop_front()

func side(id: String) -> Dictionary:
	if not data.side.has(id):data.side[id] = {"state": "locked", "stage": 0}
	return data.side[id]
