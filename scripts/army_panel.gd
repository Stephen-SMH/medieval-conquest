class_name ArmyPanel
extends PanelContainer
## Side panel for the selected army: general, movement, regiments, and the
## split / merge / appoint-general actions for the player's own armies.

signal split_requested(indices: Array)
signal merge_requested(other: Army)
signal appoint_requested

var _checks: Array[CheckBox] = []

@onready var _content: VBoxContainer = $Margin/Scroll/Content


func show_army(state: GameState, army: Army) -> void:
	for child in _content.get_children():
		child.queue_free()
	_checks.clear()
	var own := army.owner == state.player
	var faction: Dictionary = state.map.factions[army.owner]

	_add_text("[font_size=22][b]%s[/b][/font_size]\n[color=#%s]%s[/color]" % [
		army.display_name(), faction.color.lightened(0.35).to_html(false), faction.name])
	var lines := PackedStringArray()
	lines.append("[b]In:[/b] %s" % state.map.provinces[army.province].name)
	if army.is_garrison():
		lines.append("[b]General:[/b] none — a garrison can't leave its province")
	else:
		lines.append("[b]General:[/b] %s (Command %d, Logistics %d)" % [
			army.general.name, army.general.command, army.general.logistics])
		lines.append("[b]Movement:[/b] %d / %d" % [army.movement_left, army.max_movement()])
	if not army.path.is_empty():
		lines.append("[b]Marching to:[/b] %s" % state.map.provinces[army.path.back()].name)
	lines.append("[b]Men:[/b] %d in %d / %d regiments" % [
		roundi(army.total_men()), army.regiments.size(), Army.MAX_REGIMENTS])
	_add_text("\n".join(lines))

	_content.add_child(HSeparator.new())
	for regiment in army.regiments:
		var unit := regiment.type()
		var text := "%s: %d men, speed %d" % [unit.display_name, roundi(regiment.men), unit.speed]
		if own:
			var check := CheckBox.new()
			check.text = text
			check.focus_mode = Control.FOCUS_NONE
			_content.add_child(check)
			_checks.append(check)
		else:
			var label := Label.new()
			label.text = text
			_content.add_child(label)

	if not own:
		return
	_content.add_child(HSeparator.new())
	_add_button("Split ticked into a new army", _on_split_pressed)
	if army.is_garrison():
		_add_button("Appoint a general", func(): appoint_requested.emit())
	for other in state.armies_in(army.province):
		if other != army and state.can_merge(army, other):
			_add_button("Merge in %s" % other.display_name(), func(): merge_requested.emit(other))
	if army.can_move():
		_add_text("[i]Right-click a province to march there, or click it twice. Esc to cancel.[/i]")


func _on_split_pressed() -> void:
	var indices := []
	for i in _checks.size():
		if _checks[i].button_pressed:
			indices.append(i)
	split_requested.emit(indices)


func _add_text(bbcode: String) -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.text = bbcode
	_content.add_child(label)


func _add_button(text: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	_content.add_child(button)
