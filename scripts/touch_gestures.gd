class_name TouchGestures
extends RefCounted
## Turns touch-screen fingers into map gestures (PRD V4): one finger taps and
## drags (Godot turns it into mouse events), two fingers pinch to zoom and
## drag to pan.

var _points := {}  # finger index -> screen position


## Updates the tracked fingers. Returns {"zoom": factor, "pan": screen delta,
## "center": screen point} when two fingers moved, else {}.
func handle(event: InputEvent) -> Dictionary:
	if event is InputEventScreenTouch:
		if event.pressed:
			_points[event.index] = event.position
		else:
			_points.erase(event.index)
		return {}
	if not (event is InputEventScreenDrag) or not _points.has(event.index):
		return {}
	var before := _two_fingers()
	_points[event.index] = event.position
	var after := _two_fingers()
	if before.is_empty() or after.is_empty():
		return {}
	var old_spread: float = before[0].distance_to(before[1])
	var new_spread: float = after[0].distance_to(after[1])
	var old_center: Vector2 = (before[0] + before[1]) / 2.0
	var new_center: Vector2 = (after[0] + after[1]) / 2.0
	return {"zoom": new_spread / maxf(old_spread, 1.0), "pan": new_center - old_center, "center": new_center}


## True while two or more fingers are down; single-finger taps are ignored then.
func is_multi_touch() -> bool:
	return _points.size() >= 2


func _two_fingers() -> Array:
	if _points.size() < 2:
		return []
	var keys := _points.keys()
	keys.sort()
	return [_points[keys[0]], _points[keys[1]]]
