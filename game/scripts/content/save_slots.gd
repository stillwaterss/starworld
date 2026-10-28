extends RefCounted
## Saved games the player can pick on the title card. F5 copies the three live save
## files (story, cozy, journal) into save/slots/slot_N/ with a meta.json (when, which
## chapter, the name); at most SLOTS are kept, the oldest one is reused. Loading copies a
## slot back over the live files; the caller then reloads the island.
const SLOTS := 6
const FILES := ["story.json", "cozy.json", "journal.json"]

## Newest first: [{id, unix, when, chapter, name, mode}].
static func list(base := "user://") -> Array:
	var out: Array = []
	var dir := DirAccess.open(base.path_join("slots"))
	if dir == null:return out
	for id in dir.get_directories():
		var meta_path := base.path_join("slots").path_join(id).path_join("meta.json")
		var meta = JSON.parse_string(FileAccess.get_file_as_string(meta_path)) if FileAccess.file_exists(meta_path) else null
		if not meta is Dictionary:continue
		meta.id = id
		out.append(meta)
	out.sort_custom(func(a, b):return float(a.get("unix", 0)) > float(b.get("unix", 0)))
	return out

## Copies the live files into a slot (a new one, or the oldest when all are used).
## Returns the slot's meta.
static func save_now(content, base := "user://") -> Dictionary:
	content.state.save()
	var talk = content.world.interactions
	if talk and talk.has_method("_save_journal"):talk._save_journal()
	var slots := list(base)
	var id := "slot_%d" % (slots.size() + 1)
	if slots.size() >= SLOTS:id = String(slots[-1].id)
	var dir := base.path_join("slots").path_join(id)
	DirAccess.make_dir_recursive_absolute(dir)
	for file in FILES:
		if FileAccess.file_exists(base.path_join(file)):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(base.path_join(file)), ProjectSettings.globalize_path(dir.path_join(file)))
		elif FileAccess.file_exists(dir.path_join(file)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(file)))
	var now := Time.get_datetime_dict_from_system()
	var data: Dictionary = content.state.data
	var chapter := "随便走走" if data.mode == "free" else ("故事完结" if content.director.main_done() else String(content.director.chapter().get("title", "")))
	var meta := {
		"unix": Time.get_unix_time_from_system(),
		"when": "%d月%d日 %02d:%02d" % [now.month, now.day, now.hour, now.minute],
		"chapter": chapter,
		"name": String(data.get("player_name", "星仔")),
		"mode": String(data.mode),
	}
	var file := FileAccess.open(dir.path_join("meta.json"), FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(meta, "  "))
	meta.id = id
	return meta

## Puts a slot's files back as the live save. False when the slot is missing.
static func load_slot(id: String, base := "user://") -> bool:
	var dir := base.path_join("slots").path_join(id)
	if not FileAccess.file_exists(dir.path_join("story.json")):return false
	for file in FILES:
		var from := dir.path_join(file)
		var to := base.path_join(file)
		if FileAccess.file_exists(from):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))
		elif FileAccess.file_exists(to):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(to))
	return true
