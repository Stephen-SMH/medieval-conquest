class_name ProvinceView
extends Node2D
## One region on the painted map: its faction colour on parchment, a thin dark
## border, a soft glow when hovered, a tint showing what the selected unit
## can do there (OR-1), and the colour sweep when it is captured.

const BORDER_COLOR := Color("#3a2614")
const SELECTED_COLOR := Color(1.0, 0.86, 0.4)
const REACH_COLORS := {
	"move": Color(0.35, 0.55, 0.95),
	"attack": Color(0.95, 0.3, 0.2),
	"blocked": Color(0.2, 0.2, 0.2),
}
const SHADER := preload("res://shaders/region.gdshader")
const PAPER := preload("res://assets/ui/paper.png")

var province_id := ""
var polygon: PackedVector2Array

var hovered := false:
	set(value):
		hovered = value
		_refresh()
var selected := false:
	set(value):
		selected = value
		_refresh()
var neighbour := false
## "move", "attack", "blocked" or "" for the selected unit.
var reach := "":
	set(value):
		reach = value
		_refresh()

var _base_color := Color.WHITE
var _fill: Polygon2D
var _material: ShaderMaterial
var _outline: Line2D
var _highlight: Line2D
var _sweep: Tween


func setup(id: String, points: PackedVector2Array, _centroid: Vector2, _title: String) -> void:
	province_id = id
	polygon = points
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("paper", PAPER)
	_fill = Polygon2D.new()
	_fill.polygon = points
	_fill.material = _material
	add_child(_fill)
	_outline = _make_line(points, BORDER_COLOR, 1.8)
	add_child(_outline)
	_highlight = _make_line(points, SELECTED_COLOR, 4.0)
	_highlight.visible = false
	_highlight.z_index = 3
	add_child(_highlight)
	_refresh()


## Painted colour for a faction: its own colour, a touch towards parchment.
static func paint(color: Color) -> Color:
	return color.lerp(Color("#e8d9b5"), 0.18)


func set_base_color(color: Color) -> void:
	if _sweep != null and _sweep.is_running():
		return
	_base_color = color
	_refresh()


## Sweeps a new colour across the region from `origin` (a capture).
func sweep_to(color: Color, origin: Vector2, seconds: float) -> void:
	var old := _base_color
	_base_color = color
	_material.set_shader_parameter("old_color", _shown(old))
	_material.set_shader_parameter("fill_color", _shown(color))
	_material.set_shader_parameter("sweep_origin", origin)
	var reach_needed := 0.0
	for p in polygon:
		reach_needed = maxf(reach_needed, p.distance_to(origin))
	if _sweep != null:
		_sweep.kill()
	_sweep = create_tween()
	_sweep.tween_method(func(r): _material.set_shader_parameter("sweep_radius", r), 0.0, reach_needed + 30.0, seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sweep.tween_callback(_refresh)


func _shown(color: Color) -> Color:
	if reach != "":
		color = color.lerp(REACH_COLORS[reach], 0.35)
	if selected:
		color = color.lightened(0.12)
	return color


func _refresh() -> void:
	if _fill == null or (_sweep != null and _sweep.is_running()):
		return
	_material.set_shader_parameter("fill_color", _shown(_base_color))
	_material.set_shader_parameter("old_color", _shown(_base_color))
	_material.set_shader_parameter("sweep_radius", 100000.0)
	_material.set_shader_parameter("glow", 1.0 if hovered else 0.0)
	_highlight.visible = selected or hovered or reach in ["move", "attack"]
	_highlight.width = 4.0 if selected else 3.0
	_highlight.default_color = SELECTED_COLOR if selected else Color(1.0, 0.92, 0.7, 0.55)
	if reach in ["move", "attack"] and not selected:
		_highlight.default_color = REACH_COLORS[reach].lightened(0.35)


func _make_line(points: PackedVector2Array, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.closed = true
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.antialiased = true
	return line
