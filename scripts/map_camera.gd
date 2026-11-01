class_name MapCamera
extends Camera2D
## Campaign map camera: pans with WASD / arrow keys or by dragging, and zooms
## towards the mouse with the wheel (PRD MP-6).

const PAN_SPEED := 700.0  # World pixels per second at zoom 1.
const ZOOM_STEP := 1.15
const MIN_ZOOM := 0.6
const MAX_ZOOM := 3.0

## The camera centre stays inside this rectangle.
var map_rect := Rect2(0, 0, 1200, 700)


func _process(delta: float) -> void:
	var direction := Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down")
	if direction != Vector2.ZERO:
		position += direction * PAN_SPEED * delta / zoom.x
		_clamp_position()


## Moves the map along with a mouse drag of `screen_delta` pixels.
func pan_by_screen(screen_delta: Vector2) -> void:
	position -= screen_delta / zoom.x
	_clamp_position()


## Zooms by `factor`, keeping the map point under `screen_point` in place.
func zoom_at(screen_point: Vector2, factor: float) -> void:
	var offset := screen_point - get_viewport_rect().size / 2.0
	var world_point := position + offset / zoom.x
	var new_zoom := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(new_zoom, new_zoom)
	position = world_point - offset / new_zoom
	_clamp_position()


func _clamp_position() -> void:
	position = position.clamp(map_rect.position, map_rect.end)
