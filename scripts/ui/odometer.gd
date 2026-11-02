class_name Odometer
extends Control
## The treasury as a row of digit wheels, e.g. 000600 (PRD E): each wheel a
## little dark drum with a gold digit, rolling to the new number when it
## changes.

const DIGITS := 6
const ROLL_SECONDS := 0.45

var value := 0
var _shown := 0.0
var _font: Font
var _tween: Tween


func _init(digit_height := 30.0) -> void:
	custom_minimum_size = Vector2(digit_height * 0.72 * DIGITS + 4, digit_height)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _ready() -> void:
	_font = load("res://assets/fonts/Cinzel.ttf")


func set_value(new_value: int, animate := true) -> void:
	new_value = clampi(new_value, 0, 999999)
	if new_value == value and not animate:
		_shown = value
		queue_redraw()
		return
	value = new_value
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not animate or not is_inside_tree():
		_shown = value
		queue_redraw()
		return
	_tween = create_tween()
	_tween.tween_method(func(v: float):
		_shown = v
		queue_redraw(), _shown, float(value), ROLL_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## The text the wheels show when they're still: "000600".
static func text_for(number: int) -> String:
	return str(clampi(number, 0, 999999)).pad_zeros(DIGITS)


func _draw() -> void:
	var h := size.y
	var w := (size.x - 4) / DIGITS
	var font_size := int(h * 0.72)
	for i in DIGITS:
		var rect := Rect2(Vector2(2 + i * w, 0), Vector2(w - 2, h))
		draw_rect(rect, Color("#140c06"))
		# The drum's shading: darker at the top and bottom edge.
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, h * 0.18)), Color(0, 0, 0, 0.45))
		draw_rect(Rect2(rect.position + Vector2(0, h * 0.82), Vector2(rect.size.x, h * 0.18)), Color(0, 0, 0, 0.45))
		draw_rect(rect, Color("#e2bd5a", 0.55), false, 1.0)
		# The wheel rolls: this place's value with the fraction of the place below it.
		var place := pow(10.0, DIGITS - 1 - i)
		var turning := fmod(_shown / place, 10.0)
		var digit := floori(turning)
		var below := fmod(_shown, place) / place if i < DIGITS - 1 else turning - digit
		var frac := 0.0 if i < DIGITS - 1 and below < 0.9 else (below - 0.9) * 10.0 if i < DIGITS - 1 else turning - digit
		frac = clampf(frac, 0.0, 1.0)
		for k in 2:
			var d := (digit + k) % 10
			var y := h * 0.78 - frac * h + k * h
			if y < -h * 0.1 or y > h * 1.6:
				continue
			draw_string(_font, Vector2(rect.position.x, rect.position.y + y), str(d), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size,
				Color("#f3d77e"))
	# The glass over the wheels.
	draw_rect(Rect2(Vector2(2, h * 0.08), Vector2(size.x - 4, h * 0.14)), Color(1, 1, 1, 0.08))
