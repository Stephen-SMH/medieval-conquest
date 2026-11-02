class_name ActionRing
extends Control
## The small ring of round wooden buttons that opens when you click an enemy
## region your army can reach (PRD B): X to cancel, crossed swords to attack
## and crossed swords with a plus to support another army's attack there.
## Support only shows when one of your other armies already attacks it.

signal chosen(action: String)

const RADIUS := 34.0
const SPREAD := 84.0
const WOOD := Color("#6b4524")
const GOLD := Color("#e2bd5a")
const INK := Color("#1d130a")

var _actions: Array = []
var _hover := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## Opens the ring centred on `at` (screen point) with these actions:
## "cancel", "attack" and "support".
func open_at(at: Vector2, actions: Array) -> void:
	_actions = actions
	var span := (actions.size() - 1) * SPREAD
	size = Vector2(span + RADIUS * 2.0 + 8.0, RADIUS * 2.0 + 30.0)
	var screen := get_viewport_rect().size
	position = (at - Vector2(size.x / 2.0, RADIUS + 4.0)).clamp(Vector2(4, 4), screen - size - Vector2(4, 4))
	visible = true
	_hover = -1
	queue_redraw()
	Hud.pop_in(self)


func button_centre(index: int) -> Vector2:
	return Vector2(RADIUS + 4.0 + index * SPREAD, RADIUS + 4.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var over := _index_at(event.position)
		if over != _hover:
			_hover = over
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var index := _index_at(event.position)
		accept_event()
		if index >= 0:
			visible = false
			AudioManager.sfx("click")
			chosen.emit(_actions[index])


func _index_at(point: Vector2) -> int:
	for i in _actions.size():
		if point.distance_to(button_centre(i)) <= RADIUS:
			return i
	return -1


func _draw() -> void:
	var font: Font = load("res://assets/fonts/Cinzel.ttf")
	for i in _actions.size():
		var c := button_centre(i)
		var r := RADIUS * (1.06 if i == _hover else 1.0)
		draw_circle(c + Vector2(0, 3), r, Color(0, 0, 0, 0.4))
		draw_circle(c, r, WOOD.darkened(0.35))
		draw_circle(c, r * 0.88, WOOD)
		for k in 4:  # Wood grain.
			draw_arc(c + Vector2(0, r * 0.9), r * (0.5 + k * 0.18), PI + 0.5, TAU - 0.5, 12, Color(WOOD.darkened(0.25), 0.6), 1.2, true)
		draw_arc(c, r * 0.9, 0.0, TAU, 32, GOLD, 2.5, true)
		var glyph := GOLD.lightened(0.15)
		match _actions[i]:
			"cancel":
				for d in [Vector2(1, 1), Vector2(1, -1)]:
					draw_line(c - d * r * 0.35, c + d * r * 0.35, INK, 7.0, true)
					draw_line(c - d * r * 0.35, c + d * r * 0.35, Color("#e05a3a"), 4.0, true)
			"attack", "support":
				var shift := Vector2(-r * 0.12, 0) if _actions[i] == "support" else Vector2.ZERO
				for side in [-1.0, 1.0]:
					var a := c + shift + Vector2(side * r * 0.42, r * 0.42)
					var b := c + shift + Vector2(-side * r * 0.42, -r * 0.42)
					draw_line(a, b, INK, 6.0, true)
					draw_line(a, b, glyph, 3.5, true)
					var hilt := a.lerp(b, 0.25)
					var across := (b - a).orthogonal().normalized() * r * 0.18
					draw_line(hilt - across, hilt + across, glyph, 3.0, true)
				if _actions[i] == "support":
					var p := c + Vector2(r * 0.48, r * 0.3)
					draw_line(p - Vector2(r * 0.18, 0), p + Vector2(r * 0.18, 0), INK, 6.0, true)
					draw_line(p - Vector2(0, r * 0.18), p + Vector2(0, r * 0.18), INK, 6.0, true)
					draw_line(p - Vector2(r * 0.18, 0), p + Vector2(r * 0.18, 0), glyph, 3.5, true)
					draw_line(p - Vector2(0, r * 0.18), p + Vector2(0, r * 0.18), glyph, 3.5, true)
		var label: String = {"cancel": "Cancel", "attack": "Attack", "support": "Support"}[_actions[i]]
		if label != "":
			draw_string_outline(font, c + Vector2(-40, r + 18), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, 4, INK)
			draw_string(font, c + Vector2(-40, r + 18), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, GOLD.lightened(0.2))
