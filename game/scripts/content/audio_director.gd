extends Node
## Day / dusk / night music and ambience that follow day_cycle.weights (the real
## six-second blend), plus a small fixed pool for feedback sounds.
## All players are created once in _ready: re-pressing T only moves volumes.
## Settings (volumes, mute) live in res://save/settings.json, separate from progress.
const SETTINGS_PATH := "user://settings.json"
const SETTINGS_VERSION := 1
const DIR := "res://assets/audio/v11/"
const MUSIC := ["music_day", "music_dusk", "music_night"]
const AMBIENCE := ["amb_day", "amb_dusk", "amb_night"]
const SFX := ["sfx_windchime", "sfx_objective", "sfx_arrive", "sfx_page", "sfx_shutter", "sfx_plant", "sfx_bloom", "sfx_water_show", "sfx_fireflies", "sfx_door", "sfx_lighthouse"]
const BUSES := ["Music", "Ambience", "SFX"]
const SMOOTH := 6.0          # 1/s, how fast gains chase the sky weights (no jumps on instant set_time)
const DUCK_DB := -4.0

var world: Node3D
var settings := {"version": SETTINGS_VERSION, "music": .8, "ambience": .7, "sfx": .9, "muted": false, "guide": true, "breadcrumbs": true, "prompts": true}
var settings_path := SETTINGS_PATH
var persistent := true
var music: Array[AudioStreamPlayer] = []
var ambience: Array[AudioStreamPlayer] = []
var fountain: AudioStreamPlayer3D
var pool: Array[AudioStreamPlayer] = []
var sfx_streams := {}
var gains := Vector3(0, 0, 1)
var duck := 0.0
var _next := 0
var missing: Array[String] = []

func _ready() -> void:
	name = "AudioDirector"
	persistent = not "--test-session" in OS.get_cmdline_user_args()
	load_settings()
	if OS.has_feature("web"):
		_web_sound_callback = JavaScriptBridge.create_callback(_enable_web_sound)
		JavaScriptBridge.get_interface("window").starworldEnableSound = _web_sound_callback
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, "Master")
	for i in 3:
		music.append(_player(MUSIC[i], "Music"))
		ambience.append(_player(AMBIENCE[i], "Ambience"))
	for i in 6:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		pool.append(player)
	for id in SFX:
		var stream := _stream(id)
		if stream:sfx_streams[id] = stream
	var cycle = world.get("day_cycle") if world else null
	if cycle:gains = _target(cycle.weights)
	_apply_gains()
	apply_settings()
	# Start every loop on the same frame: the three music pieces share length and tempo
	for player in music + ambience:
		if player.stream:player.play()

func bind_scene() -> void:
	## Called by content_root once the scene's own sound nodes exist.
	var talk = world.get("interactions")
	if talk and talk.get("chime"):talk.chime.bus = "SFX"
	var cozy = world.get("activities")
	if cozy and cozy.get("notes"):cozy.notes.bus = "SFX"
	var registry = world.content.registry if world.get("content") else null
	if registry and registry.has("fountain") and not fountain:
		fountain = AudioStreamPlayer3D.new()
		fountain.stream = _stream("amb_fountain")
		fountain.bus = "Ambience"
		fountain.unit_size = 3.0
		fountain.max_distance = 16.0
		fountain.volume_db = -2.0
		world.add_child(fountain)
		fountain.global_position = registry.info("fountain").get("anchor_hint", registry.position_of("fountain") + Vector3(0, .6, -3.4))
		if fountain.stream:fountain.play()

func _player(id: String, bus: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = id
	if OS.has_feature("web"):player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	player.bus = bus
	player.stream = _stream(id)
	player.volume_db = -80
	add_child(player)
	return player

func _stream(id: String) -> AudioStream:
	var path := DIR + id + ".ogg"
	if not ResourceLoader.exists(path):
		missing.append(path)
		return null
	var stream: AudioStream = load(path)
	# Loop flags are in the .import files; set them again so a lost import setting can't break the loop
	if stream is AudioStreamOggVorbis:stream.loop = id.begins_with("music") or id.begins_with("amb")
	return stream

func _target(weights: Vector3) -> Vector3:
	var total := maxf(weights.x + weights.y + weights.z, .0001)
	var w := weights / total
	return Vector3(sqrt(w.x), sqrt(w.y), sqrt(w.z))   # equal-power crossfade

func _process(delta: float) -> void:
	_web_meter_time += delta
	if OS.has_feature("web") and _web_meter_time >= 1.0:
		_web_meter_time = 0.0
		var peak_db := AudioServer.get_bus_peak_volume_left_db(AudioServer.get_bus_index("Music"), 0)
		JavaScriptBridge.eval("window.starworldMusicPeakDb = Math.max(window.starworldMusicPeakDb ?? -200, " + str(peak_db) + ")")
	var cycle = world.get("day_cycle") if world else null
	if cycle:
		var target := _target(cycle.weights)
		gains = gains.lerp(target, clampf(delta * SMOOTH, 0, 1))
	duck = move_toward(duck, 0.0, delta * 1.5)
	_apply_gains()

func _apply_gains() -> void:
	for i in 3:
		var g := clampf(gains[i], 0, 1)
		music[i].volume_db = linear_to_db(maxf(g, .0001)) + DUCK_DB * duck
		ambience[i].volume_db = linear_to_db(maxf(g, .0001))

## Plays a feedback sound from the fixed pool; returns false when the file is missing.
func play_sfx(id: String) -> bool:
	var key := id if id.begins_with("sfx_") else "sfx_" + id
	if not sfx_streams.has(key):return false
	# an idle player if there is one; a stream is never swapped under a playing one,
	# whose playback the audio thread may still be mixing
	var player := pool[_next]
	for candidate in pool:
		if not candidate.playing:
			player = candidate
			break
	_next = (pool.find(player) + 1) % pool.size()
	player.stop()
	player.stream = sfx_streams[key]
	player.play()
	duck = 1.0
	return true

func toggle_mute() -> bool:
	settings.muted = not settings.muted
	apply_settings()
	save_settings()
	return settings.muted

func set_volume(kind: String, value: float) -> void:
	if not kind in ["music", "ambience", "sfx"]:return
	settings[kind] = clampf(value, 0, 1)
	apply_settings()
	save_settings()

func set_option(key: String, value) -> void:
	settings[key] = value
	save_settings()

func apply_settings() -> void:
	var levels := {"Music": settings.music, "Ambience": settings.ambience, "SFX": settings.sfx}
	for bus in levels:
		var index := AudioServer.get_bus_index(bus)
		if index < 0:continue
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(float(levels[bus]), .0001)))
		# M mutes music and ambience; feedback sounds stay so actions still answer
		AudioServer.set_bus_mute(index, bool(settings.muted) and bus != "SFX")

func is_music_on() -> bool:return not bool(settings.muted)

func load_settings() -> void:
	if not persistent or not FileAccess.file_exists(settings_path):return
	var loaded = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	if not loaded is Dictionary:return
	for key in settings:
		if key == "version" or not loaded.has(key):continue
		if typeof(loaded[key]) == TYPE_BOOL and typeof(settings[key]) == TYPE_BOOL:settings[key] = loaded[key]
		elif (loaded[key] is float or loaded[key] is int) and settings[key] is float:settings[key] = clampf(float(loaded[key]), 0, 1)

func save_settings() -> void:
	if not persistent:return
	DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir())
	var file := FileAccess.open(settings_path, FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(settings, "  "))

func report() -> Dictionary:
	var out := {"gains": [snappedf(gains.x, .001), snappedf(gains.y, .001), snappedf(gains.z, .001)], "players": music.size() + ambience.size() + pool.size() + (1 if fountain else 0), "missing": missing, "settings": settings.duplicate()}
	out["music_db"] = music.map(func(p): return snappedf(p.volume_db, .1))
	out["playing"] = music.map(func(p): return p.playing)
	return out

# The browser must receive an actual gesture after initialization to unlock audio.
# This callback also handles the explicit HTML sound button without touching story saves.
var _web_sound_callback: JavaScriptObject
var _web_meter_time := 0.0

func _enable_web_sound(_args: Array) -> void:
	settings.muted = false
	if settings.music <= 0.0:settings.music = .8
	if settings.ambience <= 0.0:settings.ambience = .7
	apply_settings()
	for player in music + ambience:
		if player.stream and not player.playing:player.play()
