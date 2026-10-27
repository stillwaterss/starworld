extends RefCounted
## The warm storybook look shared by the home screen, the chapter pages, letters and the
## end page: cream paper cards with a soft brown edge and shadow, rounded pill buttons,
## the handwriting font for words that are read, the round sans for small print.
const PAPER := Color("fbf4e6")
const PAPER_EDGE := Color("e3c99d")
const INK := Color("5b3f2c")
const INK_SOFT := Color("8a6c55")
const ACCENT := Color("e98f5a")
const HAND_FONT := "res://assets/fonts/LXGWWenKai-Regular.ttf"
static var _hand: Font
static var _sans: Font

static func hand() -> Font:
	if _hand == null:
		_hand = load(HAND_FONT) if ResourceLoader.exists(HAND_FONT) else sans()
	return _hand

static func sans() -> Font:
	if _sans == null:
		_sans = preload("res://assets/fonts/LXGWWenKai-Regular.ttf")
	return _sans

## A cream card: rounded, a warm edge, a soft shadow below.
static func card(alpha := .96, radius := 26, pad := 34) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(PAPER, alpha)
	s.border_color = PAPER_EDGE
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * .8
	s.content_margin_bottom = pad * .8
	s.shadow_color = Color(.25, .15, .3, .28)
	s.shadow_size = 18
	s.shadow_offset = Vector2(0, 6)
	return s

static func _pill(bg: Color, edge: Color, width := 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(width)
	s.set_corner_radius_all(24)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	return s

## Button states in the colours of the star-theme SVGs (assets/ui/star/buttons): cream with
## a gold edge; hover warmer, pressed deeper, a blue ring for keyboard focus, grey when
## off. "main" buttons get a thicker gold edge and the warm accent for their words.
static func style_button(b: Button, main := false) -> void:
	var edge := 4 if main else 3
	b.add_theme_stylebox_override("normal", _pill(Color("fff6e4"), Color("b28a39") if main else Color("c6a35e"), edge))
	b.add_theme_stylebox_override("hover", _pill(Color("fff0c9"), Color("b28a39"), edge))
	b.add_theme_stylebox_override("pressed", _pill(Color("ecd39b"), Color("947333"), edge))
	b.add_theme_stylebox_override("disabled", _pill(Color("e8e3d9"), Color("c8c1b3"), 3))
	b.add_theme_stylebox_override("focus", _pill(Color(0, 0, 0, 0), Color("56749b"), 5))
	var fg := Color("9a4f1f") if main else INK
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, fg)
	b.add_theme_color_override("font_disabled_color", Color("a59e90"))

## A rounded button: cream pill, gold edge, keyboard focus kept (Tab / arrows / Enter).
static func button(text: String, callback: Callable, main := false, size := 20) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", hand())
	b.add_theme_font_size_override("font_size", size)
	style_button(b, main)
	b.custom_minimum_size = Vector2(150, 46)
	b.pressed.connect(callback)
	return b

## The star-theme pictures (assets/ui/star): backgrounds and frames.
const ART := "res://assets/ui/star/"

static func art(name: String) -> Texture2D:
	for ext in [".png", ".jpg"]:
		if ResourceLoader.exists(ART + name + ext):return load(ART + name + ext)
	return null

## A frame picture as a panel style. margins (left, top, right, bottom) are the parts of
## the picture kept unstretched (its ornamented corners); [] stretches the whole picture,
## for panels sized to the picture's own proportions. pad is where the content starts.
static func frame(name: String, margins: Array, pad: Array) -> StyleBox:
	var tex := art(name)
	if tex == null:return card()
	var s := StyleBoxTexture.new()
	s.texture = tex
	if margins.size() == 4:
		s.texture_margin_left = margins[0]
		s.texture_margin_top = margins[1]
		s.texture_margin_right = margins[2]
		s.texture_margin_bottom = margins[3]
	s.content_margin_left = pad[0]
	s.content_margin_top = pad[1]
	s.content_margin_right = pad[2]
	s.content_margin_bottom = pad[3]
	return s

static func label(text: String, size := 18, color := INK, use_hand := true) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", hand() if use_hand else sans())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## A small row of drawn stars, the ornament under titles (fonts may lack ★).
class StarRow extends Control:
	var count := 3
	var color := Color("f2b766")
	func _init(n := 3, tint := Color("f2b766")) -> void:
		count = n
		color = tint
		custom_minimum_size = Vector2(26 * n + 40, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var mid := size / 2
		draw_line(Vector2(4, mid.y), Vector2(mid.x - 13 * count, mid.y), Color(color, .6), 1.5)
		draw_line(Vector2(mid.x + 13 * count, mid.y), Vector2(size.x - 4, mid.y), Color(color, .6), 1.5)
		for i in count:
			var c := Vector2(mid.x + (i - (count - 1) / 2.0) * 22, mid.y)
			var r := 8.0 if i == count / 2 else 5.5
			var pts := PackedVector2Array()
			for k in 10:
				var a := -PI / 2 + k * PI / 5
				pts.append(c + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * .45))
			draw_colored_polygon(pts, color)
