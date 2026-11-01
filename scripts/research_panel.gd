class_name ResearchPanel
extends PanelContainer
## The research screen (PRD 8.7): a parchment board in the wood frame, one row
## per tree of ink-drawn tech cards joined by arrows, gold chevrons for the tier
## (a crown for the last), and an italic line describing the tech under the mouse.

signal research_requested(tech: String)
signal closed

const ICONS := {
	"crop_rotation": "res_food", "coinage": "res_gold", "mining": "res_iron", "logistics": "ui_hourglass",
	"heavy_plough": "res_wood", "guilds": "map_town", "chain_mail": "knight", "composite_bows": "archers",
	"stirrups": "light_cavalry", "siege_engineering": "catapult", "drill": "spearmen", "tempered_steel": "ui_swords",
}
const INK := Color("#2f2012")
const GOLD := Color("#e2bd5a")

var _description: Label

@onready var _rows: VBoxContainer = $Margin/Rows


func open(state: GameState, faction: String) -> void:
	for child in _rows.get_children():
		child.queue_free()
	var me: FactionState = state.factions[faction]
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	_rows.add_child(header)
	header.add_child(WoodPopup.icon_rect("res://assets/icons/research.svg", 48))
	var title := Label.new()
	title.theme_type_variation = "HeadingLabel"
	title.text = "Research"
	header.add_child(title)
	var status := Label.new()
	status.text = "Gold %d   —   %s" % [roundi(me.resources.gold), "nothing being researched" if me.researching == "" else
		"researching %s, %d turn%s left" % [Rules.tech_name(me.researching), me.research_turns_left, "" if me.research_turns_left == 1 else "s"]]
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(status)

	var board := PanelContainer.new()
	board.theme_type_variation = "Parchment"
	_rows.add_child(board)
	var trees := VBoxContainer.new()
	trees.add_theme_constant_override("separation", 18)
	board.add_child(trees)
	for tree in ["economy", "military"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		trees.add_child(row)
		var name := Label.new()
		name.theme_type_variation = "InkLabel"
		name.text = tree.capitalize()
		name.custom_minimum_size = Vector2(96, 0)
		name.add_theme_font_override("font", load("res://assets/fonts/Cinzel.ttf"))
		row.add_child(name)
		var first := true
		for tech_id in Rules.techs:
			var tech := Rules.tech(tech_id)
			if tech.tree != tree:
				continue
			if not first:
				var arrow := Label.new()
				arrow.theme_type_variation = "InkLabel"
				arrow.text = "→"
				arrow.add_theme_font_size_override("font_size", 26)
				row.add_child(arrow)
			first = false
			row.add_child(_card(state, me, faction, tech))

	var footer := HBoxContainer.new()
	_rows.add_child(footer)
	var line := PanelContainer.new()
	line.theme_type_variation = "Parchment"
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(line)
	_description = Label.new()
	_description.theme_type_variation = "ScriptLabel"
	_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_description.text = "Choose one tech at a time; it is paid when started and done after a few turns."
	line.add_child(_description)
	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(70, 50)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): closed.emit())
	footer.add_child(close)
	visible = true
	Hud.pop_in(self)


func _card(state: GameState, me: FactionState, faction: String, tech: TechType) -> Control:
	var problem := Research.problem(state, faction, tech.id)
	var known := me.has_tech(tech.id)
	var card := Button.new()
	card.custom_minimum_size = Vector2(112, 112)
	card.focus_mode = Control.FOCUS_NONE
	for style in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("#efe3c4") if style != "hover" else Color("#fbf1d4")
		box.border_color = INK if me.researching != tech.id else Color("#b02a1c")
		box.set_border_width_all(3 if me.researching != tech.id else 5)
		if style == "disabled" and not known:
			box.bg_color = Color("#e3d7b8", 0.55)
		card.add_theme_stylebox_override(style, box)
	card.disabled = problem != ""
	card.pressed.connect(func(): research_requested.emit(tech.id))
	card.mouse_entered.connect(func(): _description.text = "%s (%d gold, %d turns): %s%s" % [tech.display_name, tech.cost_gold, tech.turns,
		tech.description, "" if problem == "" or known else "  —  %s" % problem])
	var icon := WoodPopup.icon_rect("res://assets/icons/%s.svg" % ICONS.get(tech.id, "research"), 72, Color(INK, 0.45 if problem != "" and not known else 0.9))
	icon.position = Vector2(14, 18)
	icon.size = Vector2(72, 72)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)
	var badge := Control.new()
	badge.position = Vector2(70, 4)
	badge.size = Vector2(38, 34)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.draw.connect(func():
		if tech.tier >= 3:
			var points := PackedVector2Array([Vector2(4, 28), Vector2(4, 10), Vector2(12, 18), Vector2(19, 6), Vector2(26, 18), Vector2(34, 10), Vector2(34, 28)])
			badge.draw_colored_polygon(points, GOLD if known else Color(GOLD, 0.55))
			points.append(points[0])
			badge.draw_polyline(points, Color("#8a2a18"), 2.0)
		else:
			for i in tech.tier:
				var y := 8.0 + i * 9.0
				badge.draw_polyline(PackedVector2Array([Vector2(6, y + 9), Vector2(19, y), Vector2(32, y + 9)]), Color("#8a2a18"), 6.0)
				badge.draw_polyline(PackedVector2Array([Vector2(6, y + 9), Vector2(19, y), Vector2(32, y + 9)]), GOLD if known else Color(GOLD, 0.6), 3.5))
	card.add_child(badge)
	if known:
		var tick := WoodPopup.icon_rect("res://assets/icons/ui_check.svg", 28, Color("#2f6b26"))
		tick.position = Vector2(4, 78)
		tick.size = Vector2(28, 28)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(tick)
	return card
