extends Control
var observatory: Node
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
func _process(_delta: float) -> void:
	queue_redraw()
func _draw() -> void:
	if not is_instance_valid(observatory) or observatory.mode!="scope":return
	var camera: Camera3D=observatory.scope_camera
	for index in observatory.constellations.size():
		if not observatory.is_unlocked(index):continue
		var entry: Dictionary=observatory.constellations[index]
		var missing: int=-1 if observatory.is_complete(index) else int(entry.get("missing",-1))
		var points: Array[Vector2]=[]
		var direction: Vector3=entry.direction
		var right:=direction.cross(Vector3.UP).normalized()
		var up:=right.cross(direction).normalized()
		for point: Vector2 in entry.points:
			var world: Vector3=camera.global_position+(direction+right*point.x+up*point.y).normalized()*200
			if camera.is_position_behind(world):points.clear();break
			var pixel:=camera.unproject_position(world)
			if pixel.distance_to(size*.5)>size.y*.405:points.clear();break
			points.append(pixel)
		if points.is_empty():continue
		var known: bool=index in observatory.journal.stars
		var color:=Color("ead7a8") if known else Color("9db5d8")
		for j in range(points.size()-1):draw_line(points[j],points[j+1],Color(color,.48),1.2,true)
		for k in points.size():
			var point: Vector2=points[k]
			if k==missing:
				# the empty place in the roof: a faint ring with no star in it
				draw_arc(point,6,0,TAU,24,Color(color,.55),1.0,true)
				continue
			draw_circle(point,7,Color(color,.10),true,-1,true)
			draw_circle(point,2.5,color,true,-1,true)
			draw_line(point-Vector2(5,0),point+Vector2(5,0),Color(color,.65),.8,true)
			draw_line(point-Vector2(0,5),point+Vector2(0,5),Color(color,.65),.8,true)
	var center:=size*.5
	for sign in [-1,1]:
		draw_line(center+Vector2(sign*10,0),center+Vector2(sign*22,0),Color("a7a5a0"),1,true)
		draw_line(center+Vector2(0,sign*10),center+Vector2(0,sign*22),Color("a7a5a0"),1,true)
