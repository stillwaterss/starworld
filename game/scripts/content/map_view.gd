extends Control
## Top-down sketch map from the baked walk grid: walkable ground in greens by
## height, unreachable surfaces faint, the current route, places and the player.
## North (-Z) is up. Clicking a place picks it as the guide target.
signal picked(location_id: String)

var content
var texture: ImageTexture
var view := Rect2()              # walkable area shown, in grid cells
var hover := ""
var _rects := {}                 # location id -> Rect2 in local pixels
var font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = get_theme_default_font()

func rebuild() -> void:
	var grid = content.grid
	if not grid.ready:return
	var image := Image.create(grid.width, grid.depth, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var low := Vector2(grid.width, grid.depth)
	var high := Vector2.ZERO
	for z in grid.depth:
		for x in grid.width:
			var s: int = grid.shown_slot(x, z)
			var h: float = grid.heights[s]
			if is_nan(h):continue
			var band := clampf((h + 1.0) / 12.0, 0, 1)
			if grid.walkable[s] and grid.component[s] == grid.main_component:
				image.set_pixel(x, z, Color(.55, .74, .58).lerp(Color(.93, .86, .64), band))
				low = low.min(Vector2(x, z))
				high = high.max(Vector2(x, z))
			elif grid.walkable[s]:
				image.set_pixel(x, z, Color(.55, .58, .62, .55))
			else:
				image.set_pixel(x, z, Color(.80, .74, .70, .45))
	texture = ImageTexture.create_from_image(image)
	view = Rect2(low - Vector2(6, 6), high - low + Vector2(13, 13)) if high.x > low.x else Rect2(0, 0, grid.width, grid.depth)
	queue_redraw()

func _scale() -> float:
	return minf(size.x / view.size.x, size.y / view.size.y) if view.size.x > 0 else 1.0

func _offset() -> Vector2:
	return (size - view.size * _scale()) * .5 - view.position * _scale()

func to_map(p: Vector3) -> Vector2:
	var grid = content.grid
	return _offset() + Vector2((p.x - grid.MIN_X) / grid.CELL, (p.z - grid.MIN_Z) / grid.CELL) * _scale()

func _process(_delta: float) -> void:
	if is_visible_in_tree():queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(.10, .14, .22, .55), true)
	if view.size.x <= 0 and texture == null:view = Rect2(0, 0, content.grid.width, content.grid.depth)
	if texture == null:
		draw_string(font, Vector2(20, 40), "地图正在根据场景生成……", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("eee3cf"))
		return
	var s := _scale()
	draw_texture_rect(texture, Rect2(_offset(), Vector2(content.grid.width, content.grid.depth) * s), false)
	var placed: Array[Rect2] = []
	var route: PackedVector3Array = content.guide.route
	if route.size() > 1 and content.guide.enabled():
		var pts := PackedVector2Array()
		for p in route:pts.append(to_map(p))
		draw_polyline(pts, Color(1, .86, .5, .95), 2.5, true)
	_rects.clear()
	var registry = content.registry
	var target: String = content.guide.target
	for id in registry.ids():
		if not registry.on_map(id):continue
		var at := to_map(registry.position_of(id))
		var reachable: bool = content.grid.reachable(registry.position_of(id), 3.5)
		var found: bool = id in content.state.data.discovered
		var chosen: bool = target == "loc:" + id
		var color := Color("ffd27d") if chosen else (Color("fff4dc") if found else Color("c9d3e6"))
		if not reachable:color = Color(.7, .7, .75, .6)
		draw_circle(at, 7.5 if chosen else 6.0, Color(.12, .14, .22, .9))
		draw_circle(at, 5.0 if chosen else 4.0, color)
		var label: String = registry.short_of(id) + ("" if reachable else "（远景）")
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		# right, left, below, above: first spot that does not cover another label
		var text_at := at + Vector2(9, 5)
		for spot in [at + Vector2(9, 5), at + Vector2(-9 - text_size.x, 5), at + Vector2(-text_size.x / 2, 22), at + Vector2(-text_size.x / 2, -10)]:
			var box := Rect2(spot - Vector2(0, 14), text_size + Vector2(0, 2))
			if box.position.x < 2 or box.end.x > size.x - 2:continue
			if placed.all(func(r):return not r.intersects(box)):
				text_at = spot
				break
		placed.append(Rect2(text_at - Vector2(0, 14), text_size + Vector2(0, 2)))
		draw_string_outline(font, text_at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(.1, .12, .2, .9))
		draw_string(font, text_at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		_rects[id] = Rect2(at - Vector2(10, 10), Vector2(20, 20)).merge(placed[-1]).grow(2)
		if hover == id:draw_arc(at, 11, 0, TAU, 24, Color(1, .9, .6), 1.5, true)
	for npc in ["gardener", "astronomer"]:
		var at := to_map(registry.npc_position(npc))
		draw_circle(at, 4.0, Color("8fc8ff") if npc == "astronomer" else Color("ffd94d"))
	var player: CharacterBody3D = content.world.player
	var at := to_map(player.global_position)
	var yaw: float = player.cam_yaw
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(forward.y, -forward.x)
	draw_colored_polygon(PackedVector2Array([at + forward * 11, at + side * 6 - forward * 5, at - side * 6 - forward * 5]), Color(1, .55, .45))
	draw_polyline(PackedVector2Array([at + forward * 11, at + side * 6 - forward * 5, at - side * 6 - forward * 5, at + forward * 11]), Color(.15, .1, .1), 1.2, true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover = ""
		for id in _rects:
			if _rects[id].has_point(event.position):hover = id
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for id in _rects:
			if _rects[id].has_point(event.position):
				picked.emit(id)
				accept_event()
				return
