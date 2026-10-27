extends Node3D
## The townsfolk behind the doors: nine slots, one per door, each standing on its threshold
## while the door is open (knocking opens it), facing out. A slot uses its model
## res://assets/characters/npc/npc_<id>.glb when that file exists (scaled to the slot's
## height, idle animation looping); until then a simple coloured figure stands there.
## Swapping models in later is only a matter of dropping the files into that folder.
const MODEL_DIR := "res://assets/characters/npc/"
const SLOTS := [
	# the baker stands on the doorstep: a table stands right in front of the bakery door
	{"id": "baker", "door": "baker", "name": "面包师", "height": 1.45, "tint": Color("c9874a"), "out": .12, "aside": .05},
	{"id": "grandma", "door": "grandma", "name": "写信的奶奶", "height": 1.3, "tint": Color("8f7fb8")},
	{"id": "child", "door": "child", "name": "数星星的孩子", "height": 1.05, "tint": Color("4f86c9")},
	{"id": "lamplighter", "door": "lamplighter", "name": "修灯的邻居", "height": 1.6, "tint": Color("c99a2e")},
	# the stall has a counter right outside its door: the keeper stands behind it, in the doorway
	{"id": "shopkeeper", "door": "shop", "name": "小摊店主", "height": 1.4, "tint": Color("c4566e"), "out": -.05, "aside": 0.0},
	{"id": "islet_nw", "door": "islet_nw", "name": "做椅子的木匠", "height": 1.5, "tint": Color("8a6a44")},
	{"id": "islet_e", "door": "islet_e", "name": "信箱看守人", "height": 1.4, "tint": Color("4a6fb0")},
	{"id": "islet_sw", "door": "islet_sw", "name": "摇铃人", "height": 1.35, "tint": Color("3f9a72")},
	{"id": "isle_south_r", "door": "isle_south_r", "name": "守小灯的人", "height": 1.45, "tint": Color("b8962e")},
	# 老星, the lighthouse keeper (the old man with the lantern), stands beside his door,
	# clear of the doorway the player walks through
	{"id": "keeper", "door": "keeper", "name": "老星", "height": 1.45, "tint": Color("6a5aa8"), "out": .9, "aside": 1.25},
]

var content
var actors := {}       # slot id -> {node, door, shown}
var clock := 0.0

func _ready() -> void:
	name = "NpcCast"
	_setup.call_deferred()

func _setup() -> void:
	# the doors are found by world_props after the scene settles
	var props = content.props
	var guard := 0
	while props.doors.is_empty() and guard < 600:
		await get_tree().physics_frame
		guard += 1
	for slot in SLOTS:
		if not props.doors.has(slot.door):continue
		var door: Dictionary = props.doors[slot.door]
		var info: Dictionary = door.info
		var front: Vector3 = door.front
		var centre := Vector3(info.centre[0], info.centre[1], info.centre[2])
		var floor := centre - Vector3.UP * float(info.height) / 2.0
		var root := Node3D.new()
		root.name = "Npc_" + slot.id
		add_child(root)
		# a step out of the doorway, toward the latch side: the open door leaf swings out
		# from the hinge and would hide someone standing in the middle
		var hinge := Vector3(info.hinge[0], info.hinge[1], info.hinge[2])
		var latch := Vector3(centre.x - hinge.x, 0, centre.z - hinge.z)
		latch = latch.normalized() if latch.length() > .05 else Vector3.ZERO
		root.global_position = floor + front * float(slot.get("out", .7)) + latch * float(info.width) * float(slot.get("aside", .55))
		# where they come out from: just inside the doorway, hidden by the wall
		var inside := floor - front * .7
		root.rotation.y = atan2(-front.x, -front.z)
		var body := _model(slot)
		if body == null:body = _silhouette(slot)
		root.add_child(body)
		root.visible = false
		# a body the player bumps into once the resident stands outside (off while walking)
		var bump := StaticBody3D.new()
		bump.collision_layer = 1
		bump.collision_mask = 0
		var cap := CollisionShape3D.new()
		var capsule_shape := CapsuleShape3D.new()
		capsule_shape.radius = .26
		capsule_shape.height = float(slot.height)
		cap.shape = capsule_shape
		cap.position.y = float(slot.height) / 2
		cap.disabled = true
		bump.add_child(cap)
		root.add_child(bump)
		actors[slot.id] = {"node": root, "door": slot.door, "shown": false, "model": body.name != "Silhouette", "rest": root.global_position, "inside": inside, "facing": root.rotation.y, "bump": cap}

## The slot's model if its file is there, standing on the origin and slot.height tall.
func _model(slot: Dictionary) -> Node3D:
	var model := String(slot.get("model", slot.id))
	if model == "-":return null
	var path: String = MODEL_DIR + "npc_" + model + ".glb"
	if not ResourceLoader.exists(path):return null
	var packed := load(path) as PackedScene
	if packed == null:return null
	var holder := Node3D.new()
	holder.name = "Model"
	var imported := packed.instantiate() as Node3D
	holder.add_child(imported)
	imported.rotation.y = PI
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in imported.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.transform * mesh.get_aabb()
		var node := mesh.get_parent()
		while node != imported and node is Node3D:
			box = (node as Node3D).transform * box
			node = node.get_parent()
		box = imported.transform * box
		bounds = box if first else bounds.merge(box)
		first = false
	if not first and bounds.size.y > .01:
		var factor := float(slot.height) / bounds.size.y
		holder.scale = Vector3.ONE * factor
		holder.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * factor
	var players := imported.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var player: AnimationPlayer = players[0]
		var names := {}
		for key in player.get_animation_list():
			for state in ["idle", "talk", "wave", "walk"]:
				if String(key).to_lower().contains(state):names[state] = key
		for state in ["idle", "talk"]:
			if names.has(state):player.get_animation(names[state]).loop_mode = Animation.LOOP_LINEAR
		holder.set_meta("anim", player)
		holder.set_meta("anims", names)
		if names.has("idle"):player.play(names.idle)
	return holder

## Opening the door: a wave, then talking while it stays open; shut: back to idle.
func _greet(body: Node3D, open: bool) -> void:
	if not body.has_meta("anim"):return
	var player: AnimationPlayer = body.get_meta("anim")
	var names: Dictionary = body.get_meta("anims")
	if not open:
		if names.has("idle"):player.play(names.idle, .3)
		return
	if names.has("wave"):
		player.play(names.wave, .2)
		if names.has("talk"):player.queue(names.talk)
	elif names.has("talk"):
		player.play(names.talk, .2)

## A stand-in figure in the slot's colour: round body, round head, a small star on top.
func _silhouette(slot: Dictionary) -> Node3D:
	var h: float = slot.height
	var root := Node3D.new()
	root.name = "Silhouette"
	var tint: Color = slot.tint
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = .18
	mat.roughness = .6
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = h * .2
	capsule.height = h * .55
	capsule.radial_segments = 12
	capsule.rings = 4
	body.mesh = capsule
	body.material_override = mat
	body.position.y = h * .28
	root.add_child(body)
	var head := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = h * .2
	ball.height = h * .4
	ball.radial_segments = 12
	ball.rings = 6
	head.mesh = ball
	head.material_override = mat
	head.position.y = h * .72
	root.add_child(head)
	var star := MeshInstance3D.new()
	star.mesh = preload("res://scripts/actor_visual.gd")._soft_star()
	star.scale = Vector3.ONE * h * .09
	star.position.y = h * .97
	var glow := mat.duplicate() as StandardMaterial3D
	glow.albedo_color = Color(1, .92, .65)
	glow.emission = Color(1, .86, .5)
	glow.emission_energy_multiplier = 1.4
	star.material_override = glow
	root.add_child(star)
	return root

func _process(delta: float) -> void:
	clock += delta
	if actors.is_empty():return
	_bark_process(delta)
	var doors: Dictionary = content.props.doors
	for id in actors:
		var a: Dictionary = actors[id]
		var open: bool = doors.has(a.door) and bool(doors[a.door].open)
		var node: Node3D = a.node
		if open != a.shown:
			a.shown = open
			_walk(node, a, open)
		if node.visible and not a.model:
			node.get_child(0).position.y = sin(clock * 2.0 + node.position.x) * .025

## Out through the opening door (walking, then a wave and talk), or back in and gone.
func _walk(node: Node3D, a: Dictionary, out: bool) -> void:
	var body: Node3D = node.get_child(0)
	if a.has("tween") and a.tween is Tween and a.tween.is_valid():a.tween.kill()
	var t := create_tween()
	a.tween = t
	var from: Vector3 = a.inside if out else node.global_position
	var to: Vector3 = a.rest if out else a.inside
	a.bump.disabled = true
	if out:
		# someone standing right at the door: stop on the threshold instead of walking into them
		var player: Vector3 = content.world.player.global_position
		if Vector2(player.x - to.x, player.z - to.z).length() < .9:to = a.inside.lerp(a.rest, .55)
		node.global_position = from
		node.rotation.y = float(a.facing)
		node.visible = true
		_play(body, "walk")
		t.tween_interval(.35)
	else:
		_play(body, "walk")
		var face := (to - from)
		node.rotation.y = atan2(-face.x, -face.z) if face.length() > .05 else node.rotation.y
	t.tween_property(node, "global_position", to, 1.1 if out else .9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if out:
		t.tween_callback(func():
			a.bump.disabled = false
			_greet(body, true))
	else:
		t.tween_callback(func():
			node.visible = false
			node.rotation.y = float(a.facing)
			_greet(body, false))

func _play(body: Node3D, state: String) -> void:
	if not body.has_meta("anim"):return
	var player: AnimationPlayer = body.get_meta("anim")
	var names: Dictionary = body.get_meta("anims")
	if names.has(state):
		player.get_animation(names[state]).loop_mode = Animation.LOOP_LINEAR
		player.play(names[state], .2)

## Who stands at this door (for tests and later dialogue), or "".
func at_door(door: String) -> String:
	for slot in SLOTS:
		if slot.door == door:return slot.id
	return ""

## The send-off on the last night: every village door opens and its resident waves
## (looping) until the story ends; 芽芽 and 眠眠 wave too.
func cheer() -> void:
	for id in actors:
		var actor: Dictionary = actors[id]
		if not String(actor.door) in ["baker", "grandma", "child", "lamplighter", "shop"]:continue
		content.props.open_door(String(actor.door), true, false)
		var body: Node3D = actor.node.get_child(0) if actor.node.get_child_count() > 0 else null
		if body and body.has_meta("anim"):
			var player: AnimationPlayer = body.get_meta("anim")
			var names: Dictionary = body.get_meta("anims")
			if names.has("wave"):
				player.get_animation(names.wave).loop_mode = Animation.LOOP_LINEAR
				player.play(names.wave, .2)
	for npc in content.world.interactions.npcs:
		if is_instance_valid(npc.visual) and "waving" in npc.visual:npc.visual.waving = true

# ------------------------------------------------------------------ after the story
## Once the story is over, walking up to someone gets a line from them in a bubble over
## their head (a door opens for it): two or three each, about life after 小光 went home.
## One every few seconds at most, never the same line twice running, never during a
## talk, a staged moment or the ending.
const BARKS := {
	"baker": ["今天的面包烤得有点焦。……火太旺了，像有人在天上替我看着炉子。", "眠眠每天早上都来拿面包了。她说，熬夜的人也要好好吃早饭。", "面团要等，人也要等。等到了，就香了。"],
	"grandma": ["他回信了，就一句：“我看得见。”够我读一辈子了。", "窗台的灯我还是每天点。从前是怕他看不见，现在是想让小光也看得见。"],
	"child": ["我现在敢关灯睡觉了。……就关一小会儿。", "我数到第一百颗的时候，最小的那颗眨了一下。我知道是谁。"],
	"lamplighter": ["灯都亮着，我反而不知道干什么了。……那就擦一擦吧，亮着的灯也要擦。", "以前修灯是怕它们坏。现在修灯，是想让晚归的人走得慢一点也不怕。"],
	"shopkeeper": ["信纸卖得比以前快了。大家好像忽然都有话想说。", "要一张星星邮票吗？寄到天上的，邮费免了。"],
	"islet_nw": ["椅子我又多做了一把。一个人看天，和两个人看天，是不一样的。", "木头记得每一个坐过它的人。"],
	"islet_e": ["信箱空了，我还挺不习惯。……不过空着，才装得下新的。", "今天有人寄了一封信给小光，地址写的是：头顶。"],
	"islet_sw": ["风大的时候，小铃还是会自己响。现在我觉得，那是有人在回答。", "离云最近的地方最安静，也最容易听见想念。"],
	"isle_south_r": ["小灯和大灯塔其实是一样的，都是不想让谁一个人摸黑。", "老星来信说，他学会了做饭。灯塔岛上，第一次有了饭香。"],
	"keeper": ["见到她的第一句话，我还没想好。……不急，灯亮着。", "她窗台闪三下，我现在回她四下。多出来的那一下，是给小光的。"],
	"gardener": ["我抬头的次数比以前多了。花没意见。", "眠眠送了我一张星图，我把它贴在花圃旁的墙上了。"],
	"astronomer": ["归家座最小的那颗，今晚眨了三下。你也看见了吧？", "我跟芽芽说好了，下次一起去喷泉打水漂。我已经很多年没输过了。"],
}
var _bark_clock := 0.0
var _bark_last := {}             # who -> last line index
var _bark_ready := {}            # who -> time it may speak again
var _bubble: Label3D

func _bark_process(delta: float) -> void:
	_bark_clock += delta
	if not content.director.main_done():return
	var world: Node3D = content.world
	if world.interactions.mode != "idle" or (world.performance and world.performance.busy) or content.ending.playing:return
	if _bark_clock < float(_bark_ready.get("_any", 0.0)):return
	var player: Vector3 = world.player.global_position
	var best := ""
	var best_d := 3.2
	var where := Vector3.ZERO
	for id in actors:
		var d: float = player.distance_to(actors[id].rest)
		if d < best_d and _bark_clock >= float(_bark_ready.get(id, 0.0)):
			best = id
			best_d = d
			where = actors[id].rest
	for npc in world.interactions.npcs:
		var d: float = player.distance_to(npc.global_position)
		if d < best_d and _bark_clock >= float(_bark_ready.get(npc.profile_id, 0.0)):
			best = npc.profile_id
			best_d = d
			where = npc.global_position
	if best == "" or not BARKS.has(best):return
	var lines: Array = BARKS[best]
	var pick := randi() % lines.size()
	if lines.size() > 1 and pick == int(_bark_last.get(best, -1)):pick = (pick + 1) % lines.size()
	_bark_last[best] = pick
	_bark_ready[best] = _bark_clock + 35.0
	_bark_ready["_any"] = _bark_clock + 7.0
	if actors.has(best):content.props.open_door(String(actors[best].door))
	_say(where + Vector3.UP * 2.0, String(lines[pick]))

func _say(at: Vector3, text: String) -> void:
	if not is_instance_valid(_bubble):
		_bubble = Label3D.new()
		_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bubble.no_depth_test = true
		_bubble.font = preload("res://scripts/content/cozy_style.gd").hand()
		_bubble.font_size = 44
		_bubble.pixel_size = .0042
		_bubble.modulate = Color("5b3f2c")
		_bubble.outline_modulate = Color("fff6e4")
		_bubble.outline_size = 14
		_bubble.width = 520
		_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_bubble)
	_bubble.text = text
	_bubble.global_position = at
	_bubble.modulate.a = 0.0
	_bubble.outline_modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_bubble, "modulate:a", 1.0, .5)
	t.parallel().tween_property(_bubble, "outline_modulate:a", 1.0, .5)
	t.tween_interval(clampf(2.5 + text.length() * .12, 4.0, 7.0))
	t.tween_property(_bubble, "modulate:a", 0.0, .8)
	t.parallel().tween_property(_bubble, "outline_modulate:a", 0.0, .8)
