class_name ResearchPanel
extends PanelContainer
## The two research trees (PRD 8.7): pick one tech at a time.

signal research_requested(tech: String)
signal closed

@onready var _rows: VBoxContainer = $Margin/Rows


func open(state: GameState, faction: String) -> void:
	for child in _rows.get_children():
		child.queue_free()
	var me: FactionState = state.factions[faction]
	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	var status := "Nothing being researched." if me.researching == "" else "Researching [b]%s[/b]: %d turn%s left." % [
		Rules.tech_name(me.researching), me.research_turns_left, "" if me.research_turns_left == 1 else "s"]
	title.text = "[font_size=24][b]Research[/b][/font_size]\n%s Gold: %d." % [status, roundi(me.resources.gold)]
	_rows.add_child(title)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	_rows.add_child(columns)
	for tree in ["economy", "military"]:
		var column := VBoxContainer.new()
		column.custom_minimum_size = Vector2(330, 0)
		column.add_theme_constant_override("separation", 4)
		columns.add_child(column)
		var heading := Label.new()
		heading.text = tree.capitalize()
		heading.add_theme_font_size_override("font_size", 19)
		column.add_child(heading)
		for tech_id in Rules.techs:
			var tech := Rules.tech(tech_id)
			if tech.tree != tree:
				continue
			var problem := Research.problem(state, faction, tech_id)
			var state_text := "known" if me.has_tech(tech_id) else ("researching" if me.researching == tech_id else "")
			var button := Button.new()
			button.text = "Tier %d  %s — %dg, %d turns%s" % [tech.tier, tech.display_name, tech.cost_gold, tech.turns,
				"  (%s)" % state_text if state_text != "" else ""]
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.add_theme_font_size_override("font_size", 14)
			button.focus_mode = Control.FOCUS_NONE
			button.disabled = problem != ""
			button.tooltip_text = tech.description + ("" if problem == "" else "\nCan't: %s." % problem)
			button.pressed.connect(func(): research_requested.emit(tech_id))
			column.add_child(button)
			var effect := Label.new()
			effect.text = "    " + tech.description
			effect.add_theme_font_size_override("font_size", 12)
			effect.modulate = Color(1, 1, 1, 0.7)
			effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			column.add_child(effect)
	var close := Button.new()
	close.text = "Close [Esc]"
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func(): closed.emit())
	_rows.add_child(close)
	visible = true
