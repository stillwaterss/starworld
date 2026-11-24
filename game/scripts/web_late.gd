extends Node
## v36 (web only): the "late" pack. The page's loader (play/starloader.js) starts the game
## as soon as the core pack is in, then keeps downloading chapter pictures and the full
## font in the background and drops them into the engine's file system. This
## node notices, mounts the pack and lets the few users of those files pick them up:
##   - the full font becomes the fallback of the core font (rare characters in names);
## Every user of a late file already checks ResourceLoader.exists() first, so until then
## the game simply goes without (no chapter picture behind the card yet).
## Off the web (desktop, Android) everything is in the one pack and this node is never made.

signal arrived

const CORE_FONT := "res://assets/fonts/LXGWWenKai-Regular.ttf"
const FULL_FONT := "res://assets/fonts/LXGWWenKai-Full.ttf"
var world: Node
var ready_now := false
var _clock := 0.0

static func wanted() -> bool:
	return OS.has_feature("web")

func _process(delta: float) -> void:
	if ready_now:return
	_clock -= delta
	if _clock > 0:return
	_clock = 1.0
	var raw = JavaScriptBridge.eval("JSON.stringify(window.starworldLate || {state: 'none'})", true)
	if not raw is String:return
	var info = JSON.parse_string(raw)
	if not info is Dictionary:return
	match String(info.get("state", "")):
		"ready":_mount(String(info.get("path", "")))
		"error":set_process(false)   # (the game goes on without; "none" = not started yet)

func _mount(path: String) -> void:
	ready_now = true
	set_process(false)
	if path == "" or not ProjectSettings.load_resource_pack(path, false):
		push_warning("late pack could not be mounted: " + path)
		return
	if ResourceLoader.exists(FULL_FONT):
		var core: FontFile = load(CORE_FONT)
		var full: Font = load(FULL_FONT)
		if core and full and not full in core.fallbacks:
			var list := core.fallbacks.duplicate()
			list.append(full)
			core.fallbacks = list
	print("WEB_LATE mounted ", path, " full_font=", ResourceLoader.exists(FULL_FONT), " chapter_art=", ResourceLoader.exists("res://assets/ui/chapter_02.jpg"))
	arrived.emit()

## True once the late pack is in (or always, off the web).
static func has_all(tree: SceneTree) -> bool:
	var node := tree.root.find_child("WebLate", true, false)
	return node == null or bool(node.ready_now)
