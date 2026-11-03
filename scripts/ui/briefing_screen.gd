class_name BriefingScreen
extends Control
## The mission briefing (PRD H), laid out as S&T's: wood all round; the red
## crown banner and loose map sheets on the left; a tall scroll with the
## mission's name on its top roll, and under it the history, the briefing,
## MAIN OBJECTIVE, ADDITIONAL OBJECTIVE, DEFEAT CONDITIONS and the turns for
## each crown; and on the right S&T's rail of round buttons: the anvil (the
## Forge, for a campaign mission), the arrow (start) and the castle (back).

signal forge_pressed
signal start_pressed
signal back_pressed

const SCROLL := Rect2(278, 70, 842, 640)  # The sheet, under its top roll.
const ROLL := Rect2(262, 20, 874, 66)
const BANNER := Rect2(40, 26, 150, 236)
const RAIL_X := 1203.0
const CROWN := preload("res://assets/icons/map_crown.svg")

var _text: RichTextLabel
var _title: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_title = Label.new()
	_title.position = ROLL.position
	_title.size = ROLL.size
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", load("res://assets/fonts/GrenzeGotisch.ttf"))
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", StScroll.TITLE)
	add_child(_title)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.position = SCROLL.position + Vector2(34, 34)
	_text.size = SCROLL.size - Vector2(64, 50)
	_text.scroll_active = true
	_text.add_theme_font_override("normal_font", load("res://assets/fonts/IMFellEnglish-Italic.ttf"))
	_text.add_theme_font_override("italics_font", load("res://assets/fonts/IMFellEnglish-Italic.ttf"))
	_text.add_theme_font_size_override("normal_font_size", 22)
	_text.add_theme_font_size_override("italics_font_size", 22)
	_text.add_theme_color_override("default_color", StScroll.INK)
	_text.add_theme_constant_override("line_separation", 4)
	add_child(_text)


## Fills the scroll for a mission scenario. `forge` adds the anvil (a
## campaign mission; standalone scenarios have no Forge).
func show_mission(scenario: Dictionary, forge: bool, forge_points := 0) -> void:
	var preview := GameState.from_scenario(scenario, 1)
	var mission: Dictionary = preview.mission
	_title.text = scenario.name
	var lines := PackedStringArray()
	for part in [mission.get("history", ""), mission.get("briefing", "")]:
		if part != "":
			lines.append(part)
	lines.append(_section("Main objective", Mission.primary(preview).map(func(o): return Mission.plain(o.text)), ". "))
	var extra := Mission.additional(preview)
	if not extra.is_empty():
		lines.append(_section("Additional objective", extra.map(func(o): return Mission.plain(o.text)), ". "))
	var defeats := Mission.defeats(preview)
	if not defeats.is_empty():
		lines.append(_section("Defeat conditions", defeats, ", or "))
	var limits := Mission.crowns(preview)
	if limits.size() == 3:
		for level in [3, 2, 1]:
			lines.append("To get [img color=#%s height=22]%s[/img] complete the main objective in %d turns." % [
				Hud.CROWN_COLORS[level].to_html(false), CROWN.resource_path, int(limits[3 - level])])
	_text.text = "\n\n".join(lines)
	_text.scroll_to_line(0)
	var buttons := [["arrow", "Start the mission", start_pressed], ["castle", "Back", back_pressed]]
	if forge:
		buttons.push_front(["forge", "The Forge (%d points)" % forge_points, forge_pressed])
	var top := 360.0 - (buttons.size() - 1) * 137.0 / 2.0
	for i in buttons.size():
		var button := RoundButton.new(buttons[i][0], 116)
		button.disc = true
		button.tooltip_text = buttons[i][1]
		button.pressed.connect(buttons[i][2].emit)
		button.position = Vector2(RAIL_X - 58, top + i * 137.0 - 58)
		add_child(button)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)


## "DEFEAT CONDITIONS: Fail to complete the main objective in 9 turns, or
## lose all of your troops.", as S&T writes it: the items joined by `glue`,
## each after the first in lower case when they read as one sentence.
func _section(heading: String, items: Array, glue: String) -> String:
	var parts := PackedStringArray()
	for i in items.size():
		var item: String = items[i]
		parts.append(item if i == 0 or glue == ". " else item.left(1).to_lower() + item.substr(1))
	var body := glue.join(parts)
	return "%s: %s%s" % [heading.to_upper(), body, "" if body.ends_with(".") else "."]


func _draw() -> void:
	StScroll.draw_screen(self, size)
	StScroll.draw_banner(self, BANNER)
	StScroll.draw_maps(self, Vector2(70, 690), Vector2(170, 250))
	StScroll.draw_sheet(self, SCROLL)
	StScroll.draw_roll(self, ROLL, false)
