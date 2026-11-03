class_name TutorialBox
extends PanelContainer
## The tutorial's parchment hint box in the lower-left corner: the step
## number and title, the hint, and buttons to skip the step or leave the
## tutorial (on the last step, to finish it).

signal skip_pressed
signal leave_pressed

const INK := Color("#2f2012")
const WIDTH := 292.0  # Narrow enough to stay clear of the selection strip at the bottom centre.
const MARGIN := 10.0

var _heading: Label
var _text: RichTextLabel
var _skip: Button
var _leave: Button


func _init() -> void:
	theme_type_variation = "Parchment"
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	_heading = Label.new()
	_heading.add_theme_font_override("font", load("res://assets/fonts/Cinzel.ttf"))
	_heading.add_theme_font_size_override("font_size", 18)
	_heading.add_theme_color_override("font_color", Color("#6a2a14"))
	column.add_child(_heading)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(WIDTH - 24.0, 0)
	_text.add_theme_color_override("default_color", INK)
	_text.add_theme_font_size_override("normal_font_size", 15)
	_text.add_theme_font_size_override("bold_font_size", 15)
	column.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	_skip = Button.new()
	_skip.text = "Skip step"
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.pressed.connect(func(): skip_pressed.emit())
	row.add_child(_skip)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	_leave = Button.new()
	_leave.text = "Leave tutorial"
	_leave.focus_mode = Control.FOCUS_NONE
	_leave.pressed.connect(func(): leave_pressed.emit())
	row.add_child(_leave)


## Shows a step: `index` counts from 0 of `count`.
func show_step(step: Dictionary, index: int, count: int) -> void:
	var last := index >= count - 1
	_heading.text = "%d / %d   %s" % [index + 1, count, step.get("title", "")]
	_text.text = step.get("text", "")
	_skip.visible = not last
	_skip.text = "Next" if step.get("info", false) else "Skip step"
	_leave.text = "Finish tutorial" if last else "Leave tutorial"
	visible = true
	reset_size()
	_place()
	Hud.pop_in(self)
	# The wrapped hint knows its height a frame later.
	await get_tree().process_frame
	reset_size()
	_place()


## Keeps the box in the lower-left corner, whatever its height.
func _place() -> void:
	var screen := get_viewport_rect().size
	position = Vector2(MARGIN, screen.y - size.y - MARGIN)
	pivot_offset = size / 2.0
