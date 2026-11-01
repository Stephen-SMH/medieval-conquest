class_name RecruitWindow
extends WoodPopup
## Recruiting in one region: a grid of parchment cards, each with the unit's
## figure, how many are available (mercenaries at towns and camps) and the gold
## price; locked cards are faded with what they need. On the left, the
## treasury. The footer says reinforcements arrive next turn.

signal recruit_requested(region: String, unit: String, mercenary: bool)

const RED := Color("#a8281c")


func show_region(state: GameState, region: String) -> void:
	open("Recruit in %s" % state.map.region_name(region))
	var faction: String = state.owners[region]
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	body.add_child(columns)

	var treasury := VBoxContainer.new()
	treasury.add_theme_constant_override("separation", 10)
	treasury.custom_minimum_size = Vector2(150, 0)
	columns.add_child(treasury)
	treasury.add_child(WoodPopup.icon_rect("res://assets/icons/ui_coins.svg", 56))
	var gold := Label.new()
	gold.text = _odometer(roundi(state.factions[faction].resources.gold))
	gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold.add_theme_font_override("font", load("res://assets/fonts/Cinzel.ttf"))
	gold.add_theme_font_size_override("font_size", 22)
	treasury.add_child(gold)
	var site := Economy.site(state, region)
	var where := Label.new()
	where.text = {"town": "A town: mercenaries\nfor hire here.", "camp": "A camp: mercenaries\nfor hire here."}.get(site, "No mercenaries here:\nonly towns and camps\nhire them.")
	where.add_theme_font_size_override("font_size", 15)
	treasury.add_child(where)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	columns.add_child(grid)
	for unit_id in state.provinces[region].mercenaries:
		var available: int = state.provinces[region].mercenaries[unit_id]
		var problem := Economy.hire_problem(state, region, unit_id, faction)
		grid.add_child(_card(state, faction, unit_id, Economy.mercenary_price(Rules.unit(unit_id)), str(available), problem,
			func(): recruit_requested.emit(region, unit_id, true)))
	for unit_id in Economy.roster(state, faction):
		var problem := Economy.recruit_problem(state, region, unit_id, faction)
		if problem.begins_with("only the"):
			continue
		grid.add_child(_card(state, faction, unit_id, Economy.unit_cost(state, faction, Rules.unit(unit_id)).gold, "", problem,
			func(): recruit_requested.emit(region, unit_id, false)))

	var footer_note := PanelContainer.new()
	footer_note.theme_type_variation = "Parchment"
	var note := Label.new()
	note.theme_type_variation = "ScriptLabel"
	note.text = "Reinforcements ordered here arrive at the end of the turn."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer_note.add_child(note)
	footer_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_note)
	add_close()
	reset_size()


func _card(state: GameState, faction: String, unit_id: String, price: float, available: String, problem: String, on_pick: Callable) -> Control:
	var unit_type := Rules.unit(unit_id)
	var card := Button.new()
	card.custom_minimum_size = Vector2(124, 128)
	card.focus_mode = Control.FOCUS_NONE
	card.tooltip_text = "%s\n%s%s" % [unit_type.display_name, unit_type.description, "" if problem == "" else "\nCan't: %s." % problem]
	var parchment := load("res://assets/ui/parchment_card.png")
	for style in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxTexture.new()
		box.texture = parchment
		box.texture_margin_left = 10
		box.texture_margin_right = 10
		box.texture_margin_top = 10
		box.texture_margin_bottom = 10
		box.modulate_color = {"normal": Color.WHITE, "hover": Color(1.1, 1.06, 0.95), "pressed": Color(0.9, 0.86, 0.8), "disabled": Color(1, 1, 1, 0.55)}[style]
		card.add_theme_stylebox_override(style, box)
	card.disabled = problem != ""
	card.pressed.connect(on_pick)
	Hud.react(card)
	var figure := TextureRect.new()
	figure.texture = load("res://assets/figures/%s.svg" % TokenLayer.FIGURES.get(unit_id, "pikeman"))
	figure.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	figure.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	figure.position = Vector2(30, 14)
	figure.size = Vector2(64, 64)
	figure.modulate = Color("#3a2a18", 0.4 if problem != "" else 1.0)
	figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(figure)
	var name := Label.new()
	name.theme_type_variation = "InkLabel"
	name.text = unit_type.display_name
	name.add_theme_font_size_override("font_size", 14)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.position = Vector2(0, 76)
	name.size = Vector2(124, 20)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name)
	var count := Label.new()
	count.text = available
	count.add_theme_font_override("font", load("res://assets/fonts/IMFellEnglish-Italic.ttf"))
	count.add_theme_font_size_override("font_size", 24)
	count.add_theme_color_override("font_color", RED)
	count.position = Vector2(10, 94)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(count)
	var cost := HBoxContainer.new()
	cost.position = Vector2(58, 98)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost.add_child(WoodPopup.icon_rect("res://assets/icons/ui_coins.svg", 20, Color("#3a2410")))
	var price_label := Label.new()
	price_label.text = str(roundi(price))
	price_label.add_theme_font_override("font", load("res://assets/fonts/IMFellEnglish-Italic.ttf"))
	price_label.add_theme_font_size_override("font_size", 20)
	price_label.add_theme_color_override("font_color", Color("#2f2012"))
	cost.add_child(price_label)
	card.add_child(cost)
	if problem != "":
		var glass := WoodPopup.icon_rect("res://assets/icons/ui_hourglass.svg", 16, Color("#3a2410"))
		glass.position = Vector2(6, 6)
		glass.size = Vector2(16, 16)
		glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(glass)
		var lock := Label.new()
		lock.text = _short(problem)
		lock.theme_type_variation = "InkLabel"
		lock.add_theme_font_size_override("font_size", 12)
		lock.position = Vector2(24, 4)
		lock.size = Vector2(102, 20)
		lock.clip_text = true
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(lock)
	return card


func _short(problem: String) -> String:
	if problem.begins_with("needs research"):
		return problem.replace("needs research: ", "")
	if problem.begins_with("needs: "):
		return problem.replace("needs: ", "")
	return problem.split(":")[0]


func _odometer(value: int) -> String:
	return " ".join(("%06d" % value).split(""))
