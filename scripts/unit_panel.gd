class_name UnitPanel
extends PanelContainer
## Side panel for the selected unit or stack: soldiers, health, rank, moves,
## general, and the merge / hire-general actions (PRD UT-5..UT-8).

signal select_only(unit: Unit)
signal merge_requested(target: Unit, source: Unit)
signal hire_requested(unit: Unit)
signal region_requested(region: String)

@onready var _content: VBoxContainer = $Margin/Scroll/Content


func show_units(state: GameState, selection: Array[Unit]) -> void:
	for child in _content.get_children():
		child.queue_free()
	if selection.is_empty():
		return
	var first := selection[0]
	var own := first.owner == state.viewer()
	var region := first.province
	var title := first.type().display_name if selection.size() == 1 \
		else "%d units in %s" % [selection.size(), state.map.region_name(region)]
	_add_text("[font_size=22][b]%s[/b][/font_size]\n[color=#%s]%s[/color] — %s" % [title,
		state.faction_color(first.owner).lightened(0.35).to_html(false), state.faction_name(first.owner),
		state.map.region_name(region)])

	for unit in selection:
		_content.add_child(HSeparator.new())
		var unit_type := unit.type()
		var lines := PackedStringArray()
		lines.append("[b]%s[/b]  %d/%d soldiers, %s" % [unit_type.display_name, unit.soldiers(), UnitType.SOLDIERS, unit.rank_name()])
		lines.append("Attack %d, defense %d, %s, %d move%s%s" % [unit_type.attack, unit_type.defense,
			"range %d" % unit_type.attack_range if unit_type.is_ranged() else "melee",
			unit_type.move_points, "" if unit_type.move_points == 1 else "s",
			", never routs" if unit_type.berserker else ""])
		if own and unit.owner == state.current_faction():
			var status := "ready"
			if unit.attacked:
				status = "fought — can still retreat" if unit.move_points_left > 0 else "fought"
			elif unit.moved:
				status = "moved" + (" — can still attack" if unit_type.is_cavalry() and unit.move_points_left > 0 else "")
			lines.append("Moves left %d — %s" % [unit.move_points_left, status])
			var heal := Economy.heal_amount(state, unit)
			if heal > 0:
				lines.append("[color=#8fe08f]Resting heals %d soldiers (%d gold)[/color]" % [heal, roundi(heal * Economy.heal_cost(unit_type))])
		if unit.general != null:
			lines.append("General %s: Command %d (+%d%% attack here), Logistics %d" % [unit.general.name,
				unit.general.command, roundi(unit.general.command * GameState.GENERAL_COMMAND_BONUS * 100), unit.general.logistics])
		_add_text("\n".join(lines))
		if selection.size() > 1:
			_add_button("Select only this %s" % unit_type.display_name.to_lower(), func(): select_only.emit(unit))

	if not own or first.owner != state.current_faction():
		return
	_content.add_child(HSeparator.new())
	var here := state.units_in(region).filter(func(u: Unit): return u.owner == first.owner)
	for target: Unit in here:
		for source: Unit in here:
			if target.id < source.id and state.merge_problem(target, source) == "":
				_add_button("Merge two %s (%d + %d soldiers)" % [target.type().display_name.to_lower(),
					target.soldiers(), source.soldiers()], func(): merge_requested.emit(target, source))
	if selection.size() == 1 and first.general == null:
		_add_button("Hire a general (%dg)" % Economy.GENERAL_COST.gold, func(): hire_requested.emit(first))
	if state.owners[region] == first.owner:
		_add_button("Build and recruit in %s" % state.map.region_name(region), func(): region_requested.emit(region))
	_add_text("[i]Green regions: move. Red: attack (archers shoot from here). " \
		+ "Units that fought can still retreat into your regions. U undoes a move.[/i]")


func _add_text(bbcode: String) -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.text = bbcode
	label.add_theme_font_size_override("normal_font_size", 14)
	label.add_theme_font_size_override("bold_font_size", 14)
	_content.add_child(label)


func _add_button(text: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(on_pressed)
	_content.add_child(button)
