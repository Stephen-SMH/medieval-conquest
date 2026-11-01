class_name ProvincePanel
extends PanelContainer
## Side panel: details of the selected province, building and recruiting for
## your own provinces, and the legend for the map mode.

signal build_requested(province: String, building: String)
signal recruit_requested(province: String, unit: String)

@onready var _body: RichTextLabel = $Margin/Content/Scroll/Inner/Body
@onready var _actions: VBoxContainer = $Margin/Content/Scroll/Inner/Actions
@onready var _legend_title: Label = $Margin/Content/LegendTitle
@onready var _legend: VBoxContainer = $Margin/Content/Legend


func show_province(state: GameState, id: String) -> void:
	for child in _actions.get_children():
		child.queue_free()
	var map := state.map
	if id == "":
		_body.text = "[font_size=20][b]No province selected[/b][/font_size]\n\n" \
			+ "Click a province to see who owns it, its terrain and its neighbours."
		return

	var province: Dictionary = map.provinces[id]
	var province_state: ProvinceState = state.provinces[id]
	var terrain := map.terrain(id)
	var faction: Dictionary = map.factions[state.owners[id]]
	var own: bool = state.owners[id] == state.player
	var lines := PackedStringArray()
	lines.append("[font_size=22][b]%s[/b][/font_size]" % province.name)
	var owner_line := "[color=#%s]%s[/color]" % [faction.color.lightened(0.35).to_html(false), faction.name]
	if province.capital:
		owner_line += " (capital)"
	lines.append(owner_line)
	lines.append("")
	lines.append("[b]Terrain:[/b] %s, move cost %d" % [terrain.display_name, terrain.move_cost])
	lines.append("[b]Population:[/b] %s" % thousands(province.population))
	lines.append("[b]Food:[/b] +%d this turn (%s)" % [roundi(Economy.province_food(state, id)), state.season()])
	lines.append("[b]In battle:[/b] %s" % terrain.battle_text)
	if own:
		lines.append("[b]Happiness:[/b] %d / 100%s" % [roundi(province_state.happiness),
			"  [color=#f08070](may revolt)[/color]" if province_state.happiness < Economy.REVOLT_BELOW else ""])
		lines.append("[b]Taxes:[/b] +%d gold" % roundi(Economy.province_taxes(state, id)))
		var built := PackedStringArray()
		for building_id in province_state.buildings:
			var building := Rules.building(building_id)
			var level: int = province_state.buildings[building_id]
			built.append(building.display_name + (" %d" % level if building.max_level > 1 else ""))
		lines.append("[b]Buildings (%d/%d slots):[/b] %s" % [Economy.used_slots(state, id), Economy.slots(state, id),
			", ".join(built) if not built.is_empty() else "none"])
		if province_state.construction != "":
			lines.append("[b]Building:[/b] %s, %d turn%s left" % [Rules.building(province_state.construction).display_name,
				province_state.construction_turns, "" if province_state.construction_turns == 1 else "s"])
		if not province_state.recruits.is_empty():
			var names := PackedStringArray()
			for unit_id in province_state.recruits:
				names.append(Rules.unit(unit_id).display_name)
			lines.append("[b]Training:[/b] %s (ready next turn)" % ", ".join(names))
		if Economy.blockaded(state, id):
			lines.append("[color=#f08070]An enemy army is here: no income, building or recruiting.[/color]")
	lines.append("")
	lines.append("[b]Neighbours[/b] (move cost from here)")
	for neighbour_id in map.neighbours(id):
		var line := "•  %s — %d" % [map.provinces[neighbour_id].name, map.move_cost(id, neighbour_id)]
		var border := map.border_type(id, neighbour_id)
		if border != "":
			line += " (%s)" % border
		lines.append(line)

	var seen := state.visible_provinces(state.player)
	var armies_here := state.armies_in(id)
	if seen.has(id) and not armies_here.is_empty():
		lines.append("")
		lines.append("[b]Armies here[/b]")
		for army in armies_here:
			lines.append("•  %s — %d regiments" % [army.display_name(), army.regiments.size()])
	_body.text = "\n".join(lines)

	if own:
		_add_actions(state, id)


func _add_actions(state: GameState, id: String) -> void:
	var province_state: ProvinceState = state.provinces[id]
	_add_heading("Build")
	for building_id in Rules.buildings:
		var building := Rules.building(building_id)
		var level := province_state.level(building_id)
		var wrong_terrain: bool = not building.allowed_terrains.is_empty() \
			and not (state.map.provinces[id].terrain in building.allowed_terrains)
		if level >= building.max_level or wrong_terrain:
			continue
		var title := building.display_name if level == 0 else "%s → %d" % [building.display_name, level + 1]
		var problem := Economy.build_problem(state, id, building_id, state.player)
		_add_button("%s  (%s, %d turn%s)" % [title, cost_text(Economy.building_cost(building)), building.build_turns,
			"" if building.build_turns == 1 else "s"], building.description, problem,
			func(): build_requested.emit(id, building_id))

	_add_heading("Recruit (ready next turn)")
	for unit_id in Rules.units:
		var unit := Rules.unit(unit_id)
		var problem := Economy.recruit_problem(state, id, unit_id, state.player)
		var details := "HP %d, attack %d, defense %d, speed %d. Upkeep %d gold, %d food." % [
			unit.hp, unit.attack, unit.defense, unit.speed, unit.upkeep_gold, unit.upkeep_food]
		_add_button("%s  (%s)" % [unit.display_name, cost_text(Economy.unit_cost(unit))], details, problem,
			func(): recruit_requested.emit(id, unit_id))


func _add_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	_actions.add_child(HSeparator.new())
	_actions.add_child(label)


func _add_button(text: String, description: String, problem: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	button.disabled = problem != ""
	button.tooltip_text = description if problem == "" else "%s\nCan't: %s." % [description, problem]
	button.pressed.connect(on_pressed)
	_actions.add_child(button)


## Shows the legend; `entries` is a list of [Color, String] pairs.
func show_legend(title: String, entries: Array) -> void:
	_legend_title.text = title
	for child in _legend.get_children():
		child.queue_free()
	for entry in entries:
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = entry[0]
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var label := Label.new()
		label.text = entry[1]
		row.add_child(swatch)
		row.add_child(label)
		_legend.add_child(row)


## "60g 10w 100 men" for a cost dictionary.
static func cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	var short := {"gold": "g", "wood": "w", "iron": "i", "manpower": " men"}
	for resource in ["gold", "wood", "iron", "manpower"]:
		if cost.get(resource, 0.0) > 0.0:
			parts.append("%d%s" % [roundi(cost[resource]), short[resource]])
	return " ".join(parts)


static func thousands(value: int) -> String:
	var digits := str(value)
	var result := ""
	while digits.length() > 3:
		result = "," + digits.right(3) + result
		digits = digits.left(digits.length() - 3)
	return digits + result
