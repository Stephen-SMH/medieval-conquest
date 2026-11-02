class_name ProvincePanel
extends PanelContainer
## Side panel: details of the selected region, building and recruiting for
## your own regions, and the legend for the map mode.

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
		_body.text = "[font_size=20][b]Nothing selected[/b][/font_size]\n\n" \
			+ "Click one of your units to give it orders, or a region to see it. Click your own region to build and recruit."
		return

	var province: Dictionary = map.provinces[id]
	var province_state: ProvinceState = state.provinces[id]
	var terrain := map.terrain(id)
	var owner: String = state.owners[id]
	var own: bool = owner == state.viewer() and owner == state.current_faction()
	var lines := PackedStringArray()
	lines.append("[font_size=22][b]%s[/b][/font_size]" % province.name)
	var owner_line := "[color=#%s]%s[/color]" % [state.faction_color(owner).lightened(0.35).to_html(false), state.faction_name(owner)]
	if state.is_capital(id):
		owner_line += " (capital)"
	if map.is_coastal(id):
		owner_line += ", coast"
	lines.append(owner_line)
	lines.append("")
	lines.append("[b]Terrain:[/b] %s" % terrain.display_name)
	lines.append("[b]Population:[/b] %s" % thousands(province.population))
	lines.append("[b]Gold:[/b] +%d a turn" % roundi(Economy.region_income(state, id)))
	if Economy.site(state, id) != "":
		lines.append("[b]%s:[/b] mercenaries for hire" % Economy.site(state, id).capitalize())
	lines.append("[b]In battle:[/b] %s" % terrain.battle_text)
	var siege: ProvinceState = state.provinces[id]
	if siege.siege_faction != "":
		lines.append("[color=#f0a050][b]Besieged[/b] by %s: %d of %d turns%s[/color]" % [state.faction_name(siege.siege_faction),
			siege.siege_turns, Sieges.duration(state, id, siege.siege_faction),
			" — the walls are breached" if Sieges.breached(state, id) else ""])
	if own:
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
			lines.append("[b]Training:[/b] %s (ready at the end of the turn)" % ", ".join(names))
		if Sieges.walls(state, id) > 0:
			lines.append("[b]Walls:[/b] %s" % Sieges.WALL_NAMES[Sieges.walls(state, id)])
		if Economy.blockaded(state, id):
			lines.append("[color=#f08070]Enemy units are here: no income, building or recruiting.[/color]")
	lines.append("")
	lines.append("[b]Neighbours[/b]")
	for neighbour_id in map.neighbours(id):
		var line := "•  %s" % map.region_name(neighbour_id)
		var border := map.border_type(id, neighbour_id)
		if border != "":
			line += " (%s)" % border
		lines.append(line)

	var seen := state.visible_provinces(state.viewer())
	var units_here := state.units_in(id)
	if seen.has(id) and not units_here.is_empty():
		lines.append("")
		lines.append("[b]Army here[/b]")
		for unit in units_here:
			lines.append("•  %s: %d soldiers (%s)" % [state.faction_name(unit.owner), unit.soldiers(), unit.describe()])
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
		var problem := Economy.build_problem(state, id, building_id, state.owners[id])
		_add_button("%s  (%s, %d turn%s)" % [title, cost_text(Economy.building_cost(building, level + 1)), building.build_turns,
			"" if building.build_turns == 1 else "s"], building.description, problem,
			func(): build_requested.emit(id, building_id))

	_add_heading("Recruit (ready at the end of the turn)")
	var faction_id: String = state.owners[id]
	for unit_id in Economy.roster(state, faction_id):
		var unit := Rules.unit(unit_id)
		var problem := Economy.recruit_problem(state, id, unit_id, faction_id)
		var details := "%s\n20 soldiers, attack %d, defense %d, %s. Upkeep %d gold." % [
			unit.description, unit.attack, unit.defense, "range %d" % unit.attack_range if unit.is_ranged() else "melee", unit.upkeep_gold]
		_add_button("%s  (%s)" % [unit.display_name, cost_text(Economy.unit_cost(state, faction_id, unit))], details, problem,
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


## "60g 10w 20 soldiers" for a cost dictionary.
static func cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	var short := {"gold": " gold"}
	for resource in ["gold"]:
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
