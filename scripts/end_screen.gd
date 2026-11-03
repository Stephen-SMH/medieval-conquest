class_name EndScreen
extends PanelContainer
## Victory and defeat (PRD H, CP-7). For a mission: the objectives with ✓ or
## ✗ and their points, the score (which the Forge spends), the
## decorations (the gold, silver and bronze crowns and their turn limits,
## the one won lit) with the turns taken, your losses and the enemy's by
## soldier type, and your rank with how far it is to the next. Round
## buttons: back to the menu, the map, restart and, after a won campaign
## mission, the next mission's briefing. Skirmish and hotseat show the
## result, the losses and the buttons.

signal play_again
signal closed
signal menu
signal next_mission

const GREEN := Color("#8fe08f")
const RED := Color("#f08070")
const TEXT := Color("#f1e3bd")
const WIDTH := 720.0

@onready var _rows: VBoxContainer = $Margin/Rows


func show_result(state: GameState, viewer: String) -> void:
	for child in _rows.get_children():
		child.queue_free()
	var result := state.result
	var won: bool = result.result == "won" and result.winner == viewer
	var mission := Mission.is_mission(state)
	var title := "Victory" if won else "Defeat"
	var humans := state.turn_order.filter(func(f): return state.factions[f].human)
	if humans.size() != 1 and result.winner != "":
		title = "%s wins!" % state.faction_name(result.winner)  # Hotseat or an all-AI game.
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_override("font", load("res://assets/fonts/Cinzel.ttf"))
	heading.add_theme_font_size_override("font_size", 38)
	heading.add_theme_color_override("font_color", GREEN if won else RED)
	_rows.add_child(heading)
	var story: String = state.mission.get("victory_text" if won else "defeat_text", "") if mission else ""
	_text(("[center][i]%s[/i]\n%s[/center]" % [story, result.reason]) if story != "" else "[center]%s[/center]" % result.reason, 17)

	if mission and result.has("objectives"):
		_rows.add_child(_objectives(result))
		if won:
			_text("[center][b]%d points[/b]%s[/center]" % [int(result.get("points", 0)),
				"   ·   [color=#f3d77e]to spend in the Forge[/color]" if state.mission.get("campaign", "") != "" else ""], 18)
		if Mission.crowns(state).size() == 3:
			_rows.add_child(_decorations(state, int(result.stars) if won else 0, int(result.get("turns", state.turn))))
	_rows.add_child(_losses(state, viewer))
	if mission and (state.mission.has("campaign") or state.mission.has("scenario")):
		_rows.add_child(_rank())

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 26)
	_rows.add_child(buttons)
	buttons.add_child(RoundButton.with_caption("back", "Menu", func(): menu.emit(), 64))
	buttons.add_child(RoundButton.with_caption("map", "Map", func(): closed.emit(), 64))
	buttons.add_child(RoundButton.with_caption("restart", "Restart", func(): play_again.emit(), 64))
	if won and state.mission.has("campaign"):
		var campaign := Campaigns.get_campaign(state.mission.campaign)
		if int(state.mission.mission_index) + 1 < campaign.get("missions", []).size():
			buttons.add_child(RoundButton.with_caption("next", "Next", func(): next_mission.emit(), 64))
	visible = true
	_refit()
	Hud.pop_in(self)


## Shrinks the panel to its content once wrapped text knows its height, and centres it.
func _refit() -> void:
	for i in 2:
		reset_size()
		position = ((get_viewport_rect().size - size) / 2.0).max(Vector2(8, 8))
		await get_tree().process_frame


func _text(bbcode: String, size := 18) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.custom_minimum_size = Vector2(WIDTH, 0)
	label.add_theme_color_override("default_color", TEXT)
	label.add_theme_font_size_override("normal_font_size", size)
	label.add_theme_font_size_override("bold_font_size", size)
	label.text = bbcode
	_rows.add_child(label)
	return label


## The objectives, each with ✓ or ✗ and the points it earns.
func _objectives(result: Dictionary) -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	for objective in result.objectives:
		var mark := Label.new()
		mark.text = "✓" if objective.done else "✗"
		mark.add_theme_color_override("font_color", GREEN if objective.done else RED)
		mark.add_theme_font_size_override("font_size", 20)
		grid.add_child(mark)
		var text := Label.new()
		text.text = ("" if objective.primary else "Additional: ") + (Mission.plain(objective.text) if objective.done else objective.text)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_color_override("font_color", TEXT if objective.done else TEXT.darkened(0.3))
		grid.add_child(text)
		var points := Label.new()
		points.text = str(int(objective.points)) if objective.done else "0"
		points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		points.add_theme_color_override("font_color", Color("#f3d77e") if objective.done else TEXT.darkened(0.4))
		grid.add_child(points)
	return grid


## The three crowns with their turn limits, the one won lit, and the turns taken.
func _decorations(state: GameState, crown: int, turns: int) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	var limits := Mission.crowns(state)
	for i in 3:
		var level := 3 - i  # Gold first.
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)
		var icon := WoodPopup.icon_rect("res://assets/icons/map_crown.svg", 44,
			Hud.CROWN_COLORS[level] if crown == level else Color(0.35, 0.3, 0.25, 0.7))
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(icon)
		var label := Label.new()
		label.text = "%d turns" % int(limits[i])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", TEXT if crown == level else TEXT.darkened(0.4))
		column.add_child(label)
		row.add_child(column)
	var taken := Label.new()
	taken.text = "Turns taken: %d" % turns
	taken.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	taken.add_theme_color_override("font_color", TEXT)
	row.add_child(taken)
	return row


## Your losses and the enemy's, by soldier type: its round icon and how many fell.
func _losses(state: GameState, viewer: String) -> Control:
	var enemy := {}
	for faction in state.losses:
		if faction != viewer:
			for type_id in state.losses[faction]:
				enemy[type_id] = int(enemy.get(type_id, 0)) + int(state.losses[faction][type_id])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	for entry in [["Your losses", state.losses.get(viewer, {}), viewer], ["Enemy losses", enemy, ""]]:
		var label := Label.new()
		label.text = entry[0]
		label.custom_minimum_size = Vector2(130, 0)
		label.add_theme_color_override("font_color", TEXT)
		grid.add_child(label)
		var icons := HFlowContainer.new()
		icons.custom_minimum_size = Vector2(WIDTH - 150, 0)
		icons.add_theme_constant_override("h_separation", 12)
		var by_type: Dictionary = entry[1]
		if by_type.values().all(func(n): return int(n) == 0):
			var none := Label.new()
			none.text = "none"
			none.add_theme_color_override("font_color", TEXT.darkened(0.4))
			icons.add_child(none)
		for type_id in by_type:
			if int(by_type[type_id]) <= 0 or not Rules.units.has(type_id):
				continue
			var item := HBoxContainer.new()
			item.add_theme_constant_override("separation", 3)
			var upgraded: bool = entry[2] != "" and state.is_upgraded(entry[2], type_id)
			item.add_child(TypeIcons.control(type_id, 30, upgraded))
			var count := Label.new()
			count.text = "×%d" % int(by_type[type_id])
			count.add_theme_color_override("font_color", TEXT)
			item.add_child(count)
			icons.add_child(item)
		grid.add_child(icons)
	return grid


## "Your rank: Serf" and a bar of how far it is to the next rank.
func _rank() -> Control:
	var score := Progress.total_score()
	var rank := Progress.rank(score)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = "Your rank: %s%s" % [rank.name, ("   (next: %s)" % rank.next) if rank.next != "" else ""]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", load("res://assets/fonts/Cinzel.ttf"))
	label.add_theme_color_override("font_color", Color("#f3d77e"))
	column.add_child(label)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(360, 14)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.draw.connect(func():
		var box := Rect2(Vector2.ZERO, bar.size)
		bar.draw_rect(box, Color("#140c06"))
		bar.draw_rect(Rect2(box.position, Vector2(box.size.x * float(rank.progress), box.size.y)), Color("#c9a24a"))
		bar.draw_rect(box, Color("#e2bd5a", 0.8), false, 1.5))
	bar.tooltip_text = "%d points in all" % score
	column.add_child(bar)
	return column
