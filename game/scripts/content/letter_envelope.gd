extends Control
## The envelope a letter arrives in: kraft paper, a flap that folds open (flap 0 shut,
## 1 open) and a red star seal that breaks (seal 1 whole, 0 gone). content_ui.gd tweens
## both while the letter slides out.
var flap := 0.0:
	set(v):
		flap = v
		queue_redraw()
var seal := 1.0:
	set(v):
		seal = v
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(420, 260)
	size = custom_minimum_size

var _art: Texture2D = preload("res://scripts/content/cozy_style.gd").art("envelope")

func _draw() -> void:
	var w := size.x
	var h := size.y
	# the star-theme envelope (gold star seal, airship postmark): as the seal breaks a
	# warm glow opens from it, and the envelope lifts a little as the flap opens
	if _art:
		var lift := -flap * 10.0
		draw_rect(Rect2(Vector2(6, 10 + lift), size), Color(0, 0, 0, .16))
		draw_texture_rect(_art, Rect2(Vector2(0, lift), size), false)
		var at := Vector2(w * .5, h * .55 + lift)
		var glow := (1.0 - seal)
		if glow > .01:
			for k in 4:
				draw_circle(at, (18.0 + k * 16.0) * glow, Color(1, .85, .5, .22 * (1.0 - k / 4.0) * (1.0 - flap * .6)))
		return
	var kraft := Color("d9b98c")
	var shade := Color("b8935f")
	draw_rect(Rect2(Vector2(4, 6), size), Color(0, 0, 0, .18))
	draw_rect(Rect2(Vector2.ZERO, size), kraft)
	draw_rect(Rect2(Vector2.ZERO, size), shade, false, 2.0)
	# the folds of the back
	draw_line(Vector2(0, h), Vector2(w * .5, h * .5), shade, 2.0)
	draw_line(Vector2(w, h), Vector2(w * .5, h * .5), shade, 2.0)
	# the flap: points down while shut, swings up past the top edge as it opens
	var tip := Vector2(w * .5, lerpf(h * .56, -h * .5, flap))
	var flap_color := Color("e6c99c") if flap < .5 else Color("c9a573")
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), tip]), flap_color)
	draw_polyline(PackedVector2Array([Vector2(0, 0), tip, Vector2(w, 0)]), shade, 2.0)
	if seal > .02:
		var at := Vector2(w * .5, h * .56)
		var r := 26.0 * seal
		draw_circle(at, r, Color("a8322a"))
		draw_circle(at, r * .78, Color("c0473a"))
		var star := PackedVector2Array()
		for i in 10:
			var a := -PI / 2 + i * PI / 5
			star.append(at + Vector2(cos(a), sin(a)) * (r * .55 if i % 2 == 0 else r * .24))
		draw_colored_polygon(star, Color("f3c9a0"))
