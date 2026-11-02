class_name PauseMenu
extends ColorRect
## The pause screen (PRD K): the map dimmed under "Paused", a few plain
## buttons (save or load, the last battle report, the map mode) and a wooden
## bar along the bottom with round buttons: restart, resume, objectives,
## surrender, info and exit.

signal resume
signal restart
signal objectives
signal surrender
signal info
signal exit
signal saves
signal report
signal map_mode

var _middle: VBoxContainer
var _bar: HBoxContainer


func _init() -> void:
	color = Color(0, 0, 0, 0.2)  # Over the game's own dimming.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_middle = VBoxContainer.new()
	_middle.set_anchors_preset(Control.PRESET_CENTER)
	_middle.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_middle.grow_vertical = Control.GROW_DIRECTION_BOTH
	_middle.add_theme_constant_override("separation", 12)
	add_child(_middle)
	var strip := PanelContainer.new()
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(strip)
	_bar = HBoxContainer.new()
	_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_bar.add_theme_constant_override("separation", 34)
	strip.add_child(_bar)


## Shows the pause screen. `can_restart`: the game can be started again;
## `has_report`: there is a battle report; `mission`: the objectives button
## is offered; `map_label`: the map-mode button's text.
func open(can_restart: bool, has_report: bool, mission: bool, map_label: String) -> void:
	for child in _middle.get_children() + _bar.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", load("res://assets/fonts/Cinzel.ttf"))
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color("#e2bd5a"))
	_middle.add_child(title)
	for entry in [["Save or load", saves, true], ["Last battle report", report, has_report], [map_label, map_mode, true]]:
		var button := Button.new()
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(260, 40)
		button.disabled = not entry[2]
		var on_pressed: Signal = entry[1]
		button.pressed.connect(func(): on_pressed.emit())
		Hud.react(button)
		_middle.add_child(button)
	for entry in [["restart", "Restart", restart, can_restart], ["resume", "Resume", resume, true], ["objectives", "Objectives", objectives, mission],
			["surrender", "Surrender", surrender, true], ["info", "Info", info, true], ["exit", "Exit", exit, true]]:
		var on_pressed: Signal = entry[2]
		var column := RoundButton.with_caption(entry[0], entry[1], func(): on_pressed.emit(), 62)
		(column.get_child(0) as Button).disabled = not entry[3]
		_bar.add_child(column)
	visible = true
	Hud.pop_in(_middle)
