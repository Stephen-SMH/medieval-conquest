class_name ForgeWindow
extends WoodPopup
## The Forge (PRD G), opened with the anvil on a mission briefing: one row per
## line of soldiers the campaign's civilization fields, with its round icon (★
## once upgraded) and its attack, defense and health levels as gold pips. A
## button beside each buys the next level with development points, which the
## campaign's missions earn.

signal changed

const PIP := Color("#e2bd5a")
const PIP_EMPTY := Color(0.1, 0.06, 0.03, 0.6)

var _campaign := ""


func show_campaign(campaign_id: String) -> void:
	_campaign = campaign_id
	var civ: String = Campaigns.get_campaign(campaign_id).civ
	var owned := Progress.upgrades(campaign_id)
	var points := Progress.development_points(campaign_id)
	open("The Forge")
	add_text("[center]Development points: [b][color=#f3d77e]%d[/color][/b][/center]" % points, 24)
	add_text("[center][i]Missions earn development points. Each level makes every soldier of a line 10% stronger for the rest of this campaign; a level costs 1, then 2, then 3 points.[/i][/center]", 15)

	var grid := GridContainer.new()
	grid.columns = 2 + Forge.STATS.size()
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)
	grid.add_child(Control.new())
	grid.add_child(Control.new())
	for stat in Forge.STATS:
		var heading := Label.new()
		heading.text = Forge.STAT_NAMES[stat]
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.add_theme_color_override("font_color", PIP)
		grid.add_child(heading)
	for family in Forge.families(civ):
		var upgraded: bool = owned.get(family, {}).values().any(func(level): return int(level) > 0)
		grid.add_child(TypeIcons.family_control(family, 44, upgraded))
		var name := Label.new()
		name.text = TypeIcons.FAMILY_NAMES[family]
		name.add_theme_font_size_override("font_size", 19)
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(name)
		for stat in Forge.STATS:
			grid.add_child(_cell(owned, family, stat, points))
	add_close()
	reset_size()


## A stat's pips and the button that buys the next level.
func _cell(owned: Dictionary, family: String, stat: String, points: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var level := Forge.level(owned, family, stat)
	var pips := Control.new()
	pips.custom_minimum_size = Vector2(16 * Forge.MAX_LEVEL, 18)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pips.draw.connect(func():
		for i in Forge.MAX_LEVEL:
			var at := Vector2(8 + i * 16, 9)
			pips.draw_circle(at, 6.0, Color(0, 0, 0, 0.5))
			pips.draw_circle(at, 5.0, PIP if i < level else PIP_EMPTY)
			if i < level:
				pips.draw_circle(at - Vector2(1.5, 1.5), 1.8, Color(1, 0.97, 0.8, 0.8)))
	row.add_child(pips)
	var problem := Forge.problem(owned, family, stat, points)
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(64, 36)
	button.text = "max" if level >= Forge.MAX_LEVEL else "+%d" % Forge.cost(level)
	button.disabled = problem != ""
	button.tooltip_text = "%s %s: level %d of %d%s" % [TypeIcons.FAMILY_NAMES[family], Forge.STAT_NAMES[stat].to_lower(), level,
		Forge.MAX_LEVEL, "" if problem == "" else " (%s)" % problem]
	button.set_meta("sfx", "clash")
	button.pressed.connect(func():
		if Progress.buy_upgrade(_campaign, family, stat):
			changed.emit()
			show_campaign(_campaign))
	Hud.react(button)
	row.add_child(button)
	return row
