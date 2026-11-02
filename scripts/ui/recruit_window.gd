class_name RecruitWindow
extends WoodPopup
## Reinforcements (PRD E): parchment cards, each a fixed bundle of one soldier
## type — its painted figure, the round type icon (a star if upgraded), how
## many soldiers and the gold price. Clicking a card asks "Buy the selected
## reinforcements?"; then you pick one of your provinces with a town or camp
## (or your capital) on the map, and the bundle arrives there next turn,
## joining the army there. On the left, the treasury as digit wheels.

signal bundle_chosen(bundle: Dictionary)

const RED := Color("#a8281c")

var _confirm: WoodPopup


func show_faction(state: GameState, faction: String) -> void:
	open("Reinforcements")
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	body.add_child(columns)

	var treasury := VBoxContainer.new()
	treasury.add_theme_constant_override("separation", 10)
	treasury.custom_minimum_size = Vector2(170, 0)
	columns.add_child(treasury)
	treasury.add_child(WoodPopup.icon_rect("res://assets/icons/ui_coins.svg", 56))
	var gold := Odometer.new(30)
	gold.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	treasury.add_child(gold)
	gold.set_value(roundi(state.factions[faction].resources.gold), false)
	var where := Label.new()
	where.text = "Reinforcements go to\nyour provinces with a\ntown or camp, or your\ncapital: one order each\nper turn."
	where.add_theme_font_size_override("font_size", 15)
	treasury.add_child(where)

	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(6 * 134, 3 * 138)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(grid)
	columns.add_child(scroll)
	for bundle in Economy.bundles(state, faction):
		var problem := ""
		if state.factions[faction].resources.gold < float(bundle.price):
			problem = "not enough gold"
		elif Economy.bundle_targets(state, bundle, faction).is_empty():
			problem = "no province can take them"
		grid.add_child(_card(state, faction, bundle, problem, func(): _ask(bundle)))

	var footer_note := PanelContainer.new()
	footer_note.theme_type_variation = "Parchment"
	var note := Label.new()
	note.theme_type_variation = "ScriptLabel"
	note.text = "Reinforcements ordered here arrive next turn."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer_note.add_child(note)
	footer_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_note)
	add_close()
	reset_size()


## "Buy the selected reinforcements? Price N" with the check and the X.
func _ask(bundle: Dictionary) -> void:
	if _confirm == null:
		_confirm = WoodPopup.new()
		get_parent().add_child(_confirm)
	_confirm.open("Reinforcements")
	_confirm.add_text("[center]Buy the selected reinforcements?\n%d %s\n[b]Price %d[/b][/center]" % [
		int(bundle.soldiers), Rules.unit(bundle.type).display_name.to_lower(), int(bundle.price)], 22)
	_confirm.add_check_and_close(func():
		_confirm.visible = false
		visible = false
		bundle_chosen.emit(bundle))
	_confirm.reset_size()


func _card(state: GameState, faction: String, bundle: Dictionary, problem: String, on_pick: Callable) -> Control:
	var unit_id: String = bundle.type
	var unit_type := Rules.unit(unit_id)
	var card := Button.new()
	card.custom_minimum_size = Vector2(124, 128)
	card.focus_mode = Control.FOCUS_NONE
	card.tooltip_text = "%d %s\n%s%s" % [int(bundle.soldiers), unit_type.display_name, unit_type.description, "" if problem == "" else "\nCan't: %s." % problem]
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
	card.set_meta("sfx", "")  # Hiring jingles coins instead of clicking.
	card.pressed.connect(on_pick)
	Hud.react(card)
	# The painted figure in the faction's colours, cropped to fit the card.
	var textures := TokenLayer.figure_textures(unit_id)
	var crop := TokenLayer.figure_bounds(unit_id)
	var team_color := state.faction_color(faction).lightened(0.12)
	card.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var shade := Color(0.55, 0.55, 0.55, 0.6) if problem != "" else Color.WHITE
	card.draw.connect(func():
		var box := Rect2(14, 6, 96, 70)
		var scale := minf(box.size.x / crop.size.x, box.size.y / crop.size.y)
		var shown := crop.size * scale
		var rect := Rect2(box.position + Vector2((box.size.x - shown.x) / 2.0, box.size.y - shown.y), shown)
		card.draw_texture_rect_region(textures[0], rect, crop, shade)
		if textures[1] != null:
			card.draw_texture_rect_region(textures[1], rect, crop, team_color * shade))
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
	count.text = "×%d" % int(bundle.soldiers)
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
	price_label.text = str(int(bundle.price))
	price_label.add_theme_font_override("font", load("res://assets/fonts/IMFellEnglish-Italic.ttf"))
	price_label.add_theme_font_size_override("font_size", 20)
	price_label.add_theme_color_override("font_color", Color("#2f2012"))
	cost.add_child(price_label)
	card.add_child(cost)
	var icon := TypeIcons.control(unit_id, 26, state.is_upgraded(faction, unit_id))
	icon.position = Vector2(94, 4)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)
	if problem != "":
		# Why not, on a pale strip across the figure.
		var strip := ColorRect.new()
		strip.color = Color("#f1e3bd", 0.85)
		strip.position = Vector2(8, 46)
		strip.size = Vector2(108, 22)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(strip)
		var glass := WoodPopup.icon_rect("res://assets/icons/ui_hourglass.svg", 14, Color("#3a2410"))
		glass.position = Vector2(12, 50)
		glass.size = Vector2(14, 14)
		glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(glass)
		var lock := Label.new()
		lock.text = _short(problem)
		lock.theme_type_variation = "InkLabel"
		lock.add_theme_font_size_override("font_size", 13)
		lock.position = Vector2(28, 47)
		lock.size = Vector2(86, 20)
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock.clip_text = true
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(lock)
	return card


func _short(problem: String) -> String:
	match problem:
		"not enough gold":
			return "Not enough gold"
		"no province can take them":
			return "No room"
	return problem.split(":")[0].capitalize()


## The treasury as shown in the window: "300", "1,250"; no leading zeros.
static func gold_text(value: int) -> String:
	return ("-" if value < 0 else "") + ProvincePanel.thousands(absi(value))
