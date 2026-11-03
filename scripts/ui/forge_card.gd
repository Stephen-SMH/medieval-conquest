class_name ForgeCard
extends Control
## A card of the Forge (PRD G), as in S&T: a square of parchment with a pencil
## sketch (shaders/sketch.gdshader over the shapes in assets/forge/) inside a
## frame. The card its row offers next has a bold black frame; a bought card
## keeps the bold frame and gets an orange chevron in its corner; the rest are
## faint, in a thin grey frame. The selected card has red brackets round its
## corners, drawn outside the card.

enum Look { LOCKED, NEXT, BOUGHT }

const PAPER := Color("#e3d3a2")
const BOLD := Color("#17110b")
const FAINT := Color("#a89d84")
const BRACKET := Color("#c4412a")
const CHEVRON := Color("#e8722c")
const BRACKET_GAP := 9.0  # Between the card and its brackets.
## The shapes each sketch is drawn from, back to front: [icon, centre x,
## centre y, size], as fractions of the drawing area.
const SKETCHES := {
	"tent": [["pavilion", 0.5, 0.5, 1.0]],
	"men": [["swordman", 0.25, 0.52, 0.7], ["swordman", 0.75, 0.52, 0.7], ["swordman", 0.5, 0.5, 0.74]],
	"swords": [["crossed_swords", 0.5, 0.5, 0.95]],
	"fist": [["fist", 0.5, 0.5, 0.88]],
	"tents": [["pavilion", 0.29, 0.36, 0.58], ["pavilion", 0.72, 0.4, 0.58], ["pavilion", 0.46, 0.66, 0.64]],
	"hands": [["shaking_hands", 0.5, 0.5, 1.0]],
	"bow": [["bow_arrow", 0.5, 0.5, 0.95]],
	"archers": [["archer", 0.25, 0.52, 0.68], ["archer", 0.75, 0.52, 0.68], ["archer", 0.5, 0.5, 0.72]],
	"eye": [["eye", 0.5, 0.5, 0.95]],
	"draw": [["bow_string", 0.5, 0.5, 0.95]],
	"saddle": [["saddle", 0.5, 0.5, 0.95]],
	"horses": [["cavalry", 0.36, 0.42, 0.72], ["cavalry", 0.62, 0.6, 0.76]],
	"horse": [["horse_head", 0.5, 0.5, 0.95]],
	"charge": [["charged_arrow", 0.5, 0.5, 0.95]],
	"saw": [["hand_saw", 0.5, 0.5, 0.92]],
	"trebuchet": [["trebuchet", 0.5, 0.5, 0.95]],
	"palisade": [["palisade", 0.5, 0.52, 0.92]],
	"catapult": [["catapult", 0.5, 0.5, 0.95]],
	"ram": [["siege_ram", 0.5, 0.5, 0.95]],
	"house1": [["house", 0.5, 0.55, 0.72]],
	"house2": [["family_house", 0.5, 0.52, 0.86]],
	"houses2": [["house", 0.32, 0.42, 0.58], ["house", 0.68, 0.6, 0.62]],
	"houses3": [["house", 0.28, 0.36, 0.52], ["house", 0.72, 0.36, 0.52], ["house", 0.5, 0.66, 0.56]],
	"houses4": [["house", 0.28, 0.32, 0.46], ["house", 0.72, 0.32, 0.46], ["house", 0.3, 0.7, 0.5], ["house", 0.7, 0.7, 0.5]],
	"coin": [["crown_coin", 0.5, 0.5, 0.78]],
	"coins2": [["two_coins", 0.5, 0.5, 0.9]],
	"coins3": [["coins", 0.5, 0.5, 0.9]],
	"purse": [["swap_bag", 0.5, 0.52, 0.82]],
	"sack": [["coins_pile", 0.5, 0.5, 0.95]],
	"helmets1": [["crested_helmet", 0.5, 0.5, 0.78]],
	"helmets2": [["crested_helmet", 0.33, 0.5, 0.62], ["crested_helmet", 0.67, 0.5, 0.62]],
	"helmets3": [["crested_helmet", 0.22, 0.48, 0.52], ["crested_helmet", 0.78, 0.48, 0.52], ["crested_helmet", 0.5, 0.54, 0.56]],
	"helmets4": [["crested_helmet", 0.3, 0.3, 0.46], ["crested_helmet", 0.7, 0.3, 0.46], ["crested_helmet", 0.3, 0.72, 0.46],
		["crested_helmet", 0.7, 0.72, 0.46]],
	"helmets5": [["crested_helmet", 0.27, 0.3, 0.42], ["crested_helmet", 0.73, 0.3, 0.42], ["crested_helmet", 0.2, 0.72, 0.42],
		["crested_helmet", 0.8, 0.72, 0.42], ["crested_helmet", 0.5, 0.56, 0.46]],
}

var sketch := ""
var look := Look.LOCKED:
	set(value):
		look = value
		queue_redraw()
		if _art != null:
			_art.queue_redraw()
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var _art: Control

static var _shader: Shader
static var _icons := {}


func _init(sketch_name := "", card_size := 119.0) -> void:
	sketch = sketch_name
	custom_minimum_size = Vector2(card_size, card_size)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art = Control.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	var inset := card_size * 0.1
	_art.offset_left = inset
	_art.offset_top = inset
	_art.offset_right = -inset
	_art.offset_bottom = -inset
	if _shader == null:
		_shader = load("res://shaders/sketch.gdshader")
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("paper", PAPER)
	material.set_shader_parameter("texels", 256.0 / (card_size * 0.8 * 0.75))
	_art.material = material
	_art.draw.connect(_draw_sketch)
	add_child(_art)


static func icon(name: String) -> Texture2D:
	if not _icons.has(name):
		_icons[name] = load("res://assets/forge/%s.svg" % name)
	return _icons[name]


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, PAPER)
	if look == Look.LOCKED:
		draw_rect(rect.grow(-1.0), FAINT, false, 2.0)
	else:
		draw_rect(rect.grow(-1.5), BOLD, false, 3.0)
	if look == Look.BOUGHT:
		var s := size.x * 0.12
		var at := Vector2(size.x - s * 1.1, s * 1.15)
		for k in 2:
			var c := at + Vector2(0, k * s * 0.55)
			draw_polyline(PackedVector2Array([c + Vector2(-s, s * 0.45), c + Vector2(0, -s * 0.35), c + Vector2(s, s * 0.45)]), CHEVRON, s * 0.32)
	if selected:
		draw_brackets(self, rect.grow(BRACKET_GAP), size.x * 0.26)


## Red L-shaped brackets round `rect`'s four corners.
static func draw_brackets(canvas: CanvasItem, rect: Rect2, arm: float) -> void:
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var sx := 1.0 if corner.x == rect.position.x else -1.0
		var sy := 1.0 if corner.y == rect.position.y else -1.0
		canvas.draw_polyline(PackedVector2Array([corner + Vector2(0, sy * arm), corner, corner + Vector2(sx * arm, 0)]), BRACKET, 3.0)


func _draw_sketch() -> void:
	var area := _art.size
	var fade := 1.0 if look != Look.LOCKED else 0.42
	for part in SKETCHES.get(sketch, []):
		var side: float = area.x * part[3]
		var rect := Rect2(Vector2(area.x * part[1], area.y * part[2]) - Vector2(side, side) / 2.0, Vector2(side, side))
		var texture := icon(part[0])
		_art.draw_texture_rect(texture, rect, false, Color(0, 0, 0, 1))
		_art.draw_texture_rect(texture, rect, false, Color(1, 1, 1, fade))
