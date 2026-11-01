extends Control
## The menus: campaigns with briefings (PRD CP-4, CP-7), skirmish setup
## (CP-5), hotseat (CP-6), loading a saved game, and settings.

const GAME_SCENE := "res://scenes/main.tscn"
const DIFFICULTIES := ["easy", "normal", "hard"]

var _content: VBoxContainer
var _skirmish := {"map": "heartlands", "civ": "norse", "opponents": 2, "difficulty": "normal"}


func _ready() -> void:
	Rules.ensure_loaded()
	var background := ColorRect.new()
	background.color = Color("#1d2630")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var columns := HBoxContainer.new()
	columns.set_anchors_preset(Control.PRESET_FULL_RECT)
	columns.add_theme_constant_override("separation", 0)
	add_child(columns)

	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(300, 0)
	side.add_theme_stylebox_override("panel", _panel_style(Color("#141b22")))
	columns.add_child(side)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	side.add_child(_margin(buttons, 28))
	_add_label(buttons, "Medieval\nConquest", 40, Color("#f2d16b"))
	_add_label(buttons, "Regions, banners and steel", 15, Color("#a8b4bf"))
	buttons.add_child(_spacer(24))
	for entry in _menu_entries():
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(0, 44)
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(entry[1])
		buttons.add_child(button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_margin(_content, 32))
	show_campaigns()


func _menu_entries() -> Array:
	return [
		["Campaigns", show_campaigns],
		["Skirmish", show_skirmish],
		["Load game", show_load],
		["Quit", func(): get_tree().quit()],
	]


# --- Campaigns ---------------------------------------------------------------------

func show_campaigns() -> void:
	_clear()
	_add_label(_content, "Campaigns", 30)
	_add_text("Each civilization has a campaign of three missions. Finish a mission to open the next; finish under par for 3 stars.")
	for campaign in Campaigns.all():
		var civ := Rules.civilization(campaign.civ)
		_content.add_child(HSeparator.new())
		_add_text("[font_size=22][b][color=#%s]%s[/color] — %s[/b][/font_size]%s\n%s\n[i]%s %s[/i]" % [
			civ.color.lightened(0.3).to_html(false), civ.display_name, campaign.name,
			"   [color=#8fe08f](finished)[/color]" if Progress.campaign_finished(campaign.id) else "",
			campaign.description, civ.bonus_text, _specials_text(civ)])
		for i in campaign.missions.size():
			var mission: Dictionary = campaign.missions[i]
			var unlocked := Progress.mission_unlocked(campaign.id, i)
			var stars := Progress.stars(campaign.id, i)
			var button := Button.new()
			button.text = "%d. %s   %s" % [i + 1, mission.name, _stars_text(stars) if unlocked else "(locked)"]
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.disabled = not unlocked
			button.pressed.connect(show_briefing.bind(campaign.id, i))
			_content.add_child(button)
	_content.add_child(HSeparator.new())
	var unlock_lines := PackedStringArray()
	for civ_id in Rules.civilizations:
		var civ := Rules.civilization(civ_id)
		if civ.unlock_after_campaigns > 0:
			unlock_lines.append("%s: %s" % [civ.display_name, "unlocked for skirmish and hotseat" if Progress.civilization_unlocked(civ_id)
				else "finish %d campaign%s to unlock" % [civ.unlock_after_campaigns, "" if civ.unlock_after_campaigns == 1 else "s"]])
	_add_text("[b]More civilizations[/b]\n" + "\n".join(unlock_lines))


func show_briefing(campaign_id: String, index: int) -> void:
	var scenario := Campaigns.mission(campaign_id, index)
	var mission: Dictionary = scenario.mission
	var map := MapData.load_map(scenario.map)
	_clear()
	_add_label(_content, "%s — Mission %d" % [Campaigns.get_campaign(campaign_id).name, index + 1], 18, Color("#a8b4bf"))
	_add_label(_content, scenario.name, 32)
	_add_text(mission.briefing)
	var lines := PackedStringArray()
	for objective in mission.objectives:
		match objective.type:
			"capture":
				lines.append("Capture %s" % ", ".join(objective.regions.map(func(r): return map.region_name(r))))
			"hold":
				lines.append("Hold %s for %d turns" % [map.region_name(objective.region), int(objective.turns)])
			"destroy":
				lines.append("Destroy %s" % scenario.factions.filter(func(f): return f.id == objective.faction)[0].name)
			"conquest":
				lines.append("Defeat every rival")
	_add_text("[b]Objectives[/b]\n•  " + "\n•  ".join(lines))
	_add_text("[b]Par:[/b] %d turns for 3 stars. [b]Limit:[/b] %d turns. Map: %s (%d regions)." % [
		int(mission.par), int(mission.par) * 2, map.display_name, map.province_order.size()])
	var factions := PackedStringArray()
	for faction in scenario.factions:
		factions.append("[color=%s]%s[/color] (%s%s)" % [faction.color, faction.name, Rules.civilization(faction.civ).display_name,
			", you" if faction.human else ""])
	_add_text("[b]Factions:[/b] " + ", ".join(factions))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_content.add_child(row)
	_add_button(row, "Start mission", func(): _start({"scenario": scenario, "seed": randi()}))
	_add_button(row, "Back", show_campaigns)


# --- Skirmish ---------------------------------------------------------------------

func show_skirmish() -> void:
	_clear()
	_add_label(_content, "Skirmish", 30)
	_add_text("Pick a map and a civilization, and conquer every rival.")
	var maps := MapData.list_maps()
	_add_option("Map", maps.map(func(m): return MapData.load_map(m).display_name + " (%d regions)" % MapData.load_map(m).province_order.size()),
		maps.find(_skirmish.map), func(i): _skirmish.map = maps[i]; show_skirmish())
	var civs := Rules.civilizations.keys()
	var civ_labels := civs.map(func(c): return Rules.civilization(c).display_name + ("" if Progress.civilization_unlocked(c) else " (locked)"))
	var civ_option := _add_option("Your civilization", civ_labels, civs.find(_skirmish.civ), func(i):
		if Progress.civilization_unlocked(civs[i]):
			_skirmish.civ = civs[i]
		show_skirmish())
	for i in civs.size():
		civ_option.set_item_disabled(i, not Progress.civilization_unlocked(civs[i]))
	var civ := Rules.civilization(_skirmish.civ)
	_add_text("[i]%s %s %s[/i]" % [civ.description, civ.bonus_text, _specials_text(civ)])
	var most := mini(3, MapData.load_map(_skirmish.map).starts.size() - 1)
	_skirmish.opponents = mini(_skirmish.opponents, most)
	_add_option("Computer opponents", range(1, most + 1).map(func(n): return str(n)), _skirmish.opponents - 1,
		func(i): _skirmish.opponents = i + 1)
	_add_option("Difficulty", DIFFICULTIES.map(func(d): return d.capitalize()), DIFFICULTIES.find(_skirmish.difficulty),
		func(i): _skirmish.difficulty = DIFFICULTIES[i])
	_add_button(_content, "Start skirmish", func():
		var players := [{"civ": _skirmish.civ, "human": true}]
		players.append_array(opponent_civs(_skirmish.civ, _skirmish.opponents).map(func(c): return {"civ": c, "human": false}))
		_start({"scenario": Skirmish.build(_skirmish.map, players, _skirmish.difficulty, randi()), "seed": randi()}))


## Opponents get the other unlocked civilizations in turn.
static func opponent_civs(own: String, count: int) -> Array:
	var others := Rules.civilizations.keys().filter(func(c): return c != own and Progress.civilization_unlocked(c))
	var picked := []
	for i in count:
		picked.append(others[i % others.size()])
	return picked


# --- Loading ----------------------------------------------------------------------

func show_load() -> void:
	_clear()
	_add_label(_content, "Load game", 30)
	for slot in SaveGame.SLOTS:
		var description := SaveGame.describe(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_content.add_child(row)
		_add_label(row, "%s: %s" % ["Autosave" if slot == "auto" else "Slot " + slot, description if description != "" else "empty"], 16)
		var button := _add_button(row, "Load", func(): _start({"save": SaveGame.load_slot(slot)}))
		button.disabled = description == ""


# --- Helpers ----------------------------------------------------------------------

func _start(setup: Dictionary) -> void:
	var session := get_node_or_null("/root/Session")
	if session != null:
		session.setup = setup
	get_tree().change_scene_to_file(GAME_SCENE)


func _clear() -> void:
	for child in _content.get_children():
		child.queue_free()


func _add_label(parent: Control, text: String, size: int, color := Color("#e8e4dc")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _add_text(bbcode: String) -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.text = bbcode
	label.add_theme_font_size_override("normal_font_size", 16)
	label.add_theme_font_size_override("bold_font_size", 16)
	_content.add_child(label)


func _add_button(parent: Control, text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 40)
	button.add_theme_font_size_override("font_size", 17)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(on_pressed)
	parent.add_child(button)
	return button


func _add_option(title: String, labels: Array, selected: int, on_selected: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_content.add_child(row)
	var label := _add_label(row, title, 17)
	label.custom_minimum_size = Vector2(220, 0)
	var option := OptionButton.new()
	for text in labels:
		option.add_item(text)
	option.select(maxi(selected, 0))
	option.custom_minimum_size = Vector2(280, 36)
	option.item_selected.connect(on_selected)
	row.add_child(option)
	return option


func _margin(child: Control, size: int) -> MarginContainer:
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, size)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(child)
	return margin


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style


func _stars_text(count: int) -> String:
	return "%d/3 stars" % count if count > 0 else "not played"


func _specials_text(civ: Civilization) -> String:
	return "Special units: %s." % ", ".join(civ.special_units.map(func(u): return Rules.unit(u).display_name))
