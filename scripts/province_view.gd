class_name ProvinceView
extends Node2D
## One region on the map: its filled shape, border, name, selection highlight
## and the green / red / grey tint showing what the selected units can do there (OR-1).

const OUTLINE_COLOR := Color(0.15, 0.12, 0.1)
const SELECTED_COLOR := Color(1.0, 0.85, 0.3)
const NEIGHBOUR_COLOR := Color(1.0, 1.0, 1.0, 0.8)
const LABEL_SIZE := Vector2(160, 20)
const REACH_COLORS := {
	"move": Color(0.3, 0.85, 0.35),
	"attack": Color(0.95, 0.25, 0.2),
	"blocked": Color(0.25, 0.25, 0.25),
}

var province_id := ""

var hovered := false:
	set(value):
		hovered = value
		_refresh()
var selected := false:
	set(value):
		selected = value
		_refresh()
var neighbour := false:
	set(value):
		neighbour = value
		_refresh()
## "move", "attack", "blocked" or "" for the selected units.
var reach := "":
	set(value):
		reach = value
		_refresh()

var _base_color := Color.WHITE
var _fill: Polygon2D
var _outline: Line2D
var _highlight: Line2D
var _label: Label


func setup(id: String, polygon: PackedVector2Array, centroid: Vector2, title: String) -> void:
	province_id = id

	_fill = Polygon2D.new()
	_fill.polygon = polygon
	add_child(_fill)

	_outline = _make_line(polygon, OUTLINE_COLOR, 2.0)
	add_child(_outline)

	_highlight = _make_line(polygon, SELECTED_COLOR, 4.0)
	_highlight.visible = false
	add_child(_highlight)

	_label = Label.new()
	_label.text = title
	_label.size = LABEL_SIZE
	_label.position = centroid - LABEL_SIZE / 2.0 + Vector2(0, 16)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.z_index = 6
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	_refresh()


func set_base_color(color: Color) -> void:
	_base_color = color
	_refresh()


func _refresh() -> void:
	if _fill == null:
		return
	var color := _base_color
	if neighbour:
		color = color.lightened(0.1)
	if selected:
		color = color.lightened(0.2)
	if hovered:
		color = color.lightened(0.15)
	if reach != "":
		color = color.lerp(REACH_COLORS[reach], 0.45)
	_fill.color = color

	_highlight.visible = selected or neighbour or reach in ["move", "attack"]
	# The selected border is drawn above neighbour borders where they touch.
	_highlight.z_index = 3 if selected else 2
	_highlight.width = 4.0 if selected else 2.5
	_highlight.default_color = SELECTED_COLOR if selected else NEIGHBOUR_COLOR
	if reach in ["move", "attack"] and not selected:
		_highlight.default_color = REACH_COLORS[reach].lightened(0.3)


func _make_line(points: PackedVector2Array, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.closed = true
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.antialiased = true
	return line
