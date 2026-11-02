extends Control
## The menus (PRD M): the title along the top, the chosen screen in the
## middle, and a bottom row of square wooden buttons: Tutorial, Campaigns
## (with briefings, CP-4, CP-7), Scenarios (a parchment table with a map
## preview), Skirmish and Hotseat (CP-5, CP-6), Continue (the autosave and
## the save slots), Records, Settings and Credits.

const GAME_SCENE := "res://scenes/main.tscn"
const DIFFICULTIES := ["easy", "normal", "hard"]
const CREDIT_LINE := "Unit figures rendered from CC0 3D models by Quaternius. Icons by Lorc, Delapouite and " \
	+ "Guard13007 from game-icons.net (CC BY 3.0). Fonts: Cinzel, IM FELL English, Grenze Gotisch and Noto (SIL Open Font License). " \
	+ "Music by RandomMind, cynicmusic and Emma_MA (CC0). Sounds by Kenney and by freesound.org users HebronTheatre, " \
	+ "mcaseydesign, craigsmith, el_boss and freefire66 (CC0). See CREDITS.md."

var _content: VBoxContainer
var _forge: ForgeWindow
var _skirmish := {"map": "heartlands", "civ": "norse", "opponents": 2, "difficulty": "normal"}
var _hotseat := {"map": "heartlands", "civs": ["norse", "anglish"], "ai": 0}


func _ready() -> void:
	Rules.ensure_loaded()
	Settings.apply(get_tree())
	var background := TextureRect.new()
	background.texture = load("res://assets/ui/wood.png")
	background.stretch_mode = TextureRect.STRETCH_TILE
	background.modulate = Color(0.55, 0.5, 0.45)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)

	# The title along the top; a quit button on the right where quitting makes sense.
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_child(_margin(header, 14))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(50, 0)
	header.add_child(spacer)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", -4)
	header.add_child(titles)
	var title := _add_label(titles, "Medieval Conquest", 38, Color("#f2d16b"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", load("res://assets/fonts/Cinzel.ttf"))
	_add_label(titles, "Regions, banners and steel", 15, Color("#c8b48a")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		var quit := RoundButton.new("exit", 48)
		quit.tooltip_text = "Quit"
		quit.pressed.connect(func(): get_tree().quit())
		header.add_child(quit)
	else:
		header.add_child(spacer.duplicate())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	var content_margin := _margin(_content, 32)
	content_margin.add_theme_constant_override("margin_top", 6)
	scroll.add_child(content_margin)

	# The bottom row of square wooden buttons.
	var bar := PanelContainer.new()
	layout.add_child(bar)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	for entry in _menu_entries():
		var button := SquareButton.new(entry[0], entry[1])
		button.pressed.connect(entry[2])
		row.add_child(button)
	_forge = ForgeWindow.new()
	add_child(_forge)
	AudioManager.music("menu")
	var session := get_node_or_null("/root/Session")
	var target: Dictionary = session.menu_target if session != null else {}
	if session != null:
		session.menu_target = {}
	if target.has("briefing") and Progress.mission_unlocked(target.briefing[0], int(target.briefing[1])):
		show_briefing(target.briefing[0], int(target.briefing[1]))
	else:
		show_title()
	if should_offer_tutorial():
		_offer_tutorial()


## The one-time "First time here?" prompt: only before any campaign progress, and only once.
static func should_offer_tutorial() -> bool:
	Settings.ensure_loaded()
	return not Settings.tutorial_offered and not Progress.any_progress()


func start_tutorial() -> void:
	_start({"scenario": Tutorial.scenario(), "seed": 1})


func _offer_tutorial() -> void:
	Settings.tutorial_offered = true
	Settings.save()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var card := PanelContainer.new()
	card.theme_type_variation = "Parchment"
	card.custom_minimum_size = Vector2(460, 0)
	shade.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	card.add_child(column)
	var title := Label.new()
	title.text = "First time here?"
	title.add_theme_font_override("font", load("res://assets/fonts/Cinzel.ttf"))
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("#6a2a14"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.add_theme_color_override("default_color", Color("#2f2012"))
	text.add_theme_font_size_override("normal_font_size", 17)
	text.text = "The [b]tutorial[/b] is a short mission on a small map that shows you, step by step, how to march, attack, " \
		+ "end the turn, earn gold and raise troops. It takes about five minutes."
	column.add_child(text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	_add_button(row, "Play the tutorial", start_tutorial)
	_add_button(row, "Not now", shade.queue_free)
	# Centre the card once it knows its size.
	await get_tree().process_frame
	card.reset_size()
	card.position = (shade.size - card.size) / 2.0


## The bottom row: [glyph, caption, screen].
func _menu_entries() -> Array:
	return [
		["tutorial", "Tutorial", start_tutorial],
		["campaigns", "Campaigns", show_campaigns],
		["scenarios", "Scenarios", show_scenarios],
		["skirmish", "Skirmish", show_skirmish],
		["continue", "Continue", show_continue],
		["records", "Records", show_records],
		["settings", "Settings", show_settings],
		["credits", "Credits", show_credits],
	]


# --- Title ---------------------------------------------------------------------------

func show_title() -> void:
	_clear()
	_content.add_child(Muster.new())
	_add_text("[center]Every region holds one army. Click it, then a neighbouring region (or drag onto it): a [color=#7fa8f0]blue arrow[/color] " \
		+ "marches there, a [color=#f07060]red arrow[/color] attacks. Plan your orders, then turn the hourglass: your orders play out, " \
		+ "then each rival takes its turn. Spears beat horse, horse beats bows, bows beat spears.[/center]")
	var rank := Progress.rank(Progress.total_score())
	var autosave := SaveGame.describe("auto")
	_add_text("[center][color=#f3d77e]Your rank: %s[/color]%s[/center]" % [rank.name,
		"   ·   [b]Last game:[/b] %s" % autosave if autosave != "" else ""])


# --- Hotseat ---------------------------------------------------------------------------

func show_hotseat() -> void:
	_clear()
	_add_label(_content, "Hotseat", 30)
	_add_button(_content, "Play against the computer instead", show_skirmish)
	_add_text("2 to 4 players take turns on this device. Between turns the map is hidden until the next player is ready.")
	var maps := MapData.list_maps()
	_add_option("Map", maps.map(func(m): return MapData.load_map(m).display_name), maps.find(_hotseat.map),
		func(i): _hotseat.map = maps[i]; show_hotseat())
	var seats := MapData.load_map(_hotseat.map).starts.size()
	_add_option("Players", range(2, mini(4, seats) + 1).map(func(n): return str(n)), _hotseat.civs.size() - 2, func(i):
		var count: int = i + 2
		while _hotseat.civs.size() < count:
			_hotseat.civs.append(Rules.civilizations.keys()[_hotseat.civs.size() % 3])
		_hotseat.civs.resize(count)
		_hotseat.ai = mini(_hotseat.ai, seats - count)
		show_hotseat())
	var civs := Rules.civilizations.keys()
	for p in _hotseat.civs.size():
		var option := _add_option("Player %d" % (p + 1), civs.map(func(c): return Rules.civilization(c).display_name + ("" if Progress.civilization_unlocked(c) else " (locked)")),
			civs.find(_hotseat.civs[p]), func(i): _hotseat.civs[p] = civs[i])
		for i in civs.size():
			option.set_item_disabled(i, not Progress.civilization_unlocked(civs[i]))
	var free_seats: int = seats - _hotseat.civs.size()
	if free_seats > 0:
		_add_option("Computer opponents", range(0, free_seats + 1).map(func(n): return str(n)), _hotseat.ai, func(i): _hotseat.ai = i)
	_add_button(_content, "Start hotseat game", func():
		var players: Array = _hotseat.civs.map(func(c): return {"civ": c, "human": true})
		players.append_array(opponent_civs("", _hotseat.ai).map(func(c): return {"civ": c, "human": false}))
		_start({"scenario": Skirmish.build(_hotseat.map, players, "normal", randi()), "seed": randi()}))


# --- Settings ---------------------------------------------------------------------------

func show_settings() -> void:
	Settings.ensure_loaded()
	_clear()
	_add_label(_content, "Settings", 30)
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		var fullscreen := CheckBox.new()
		fullscreen.text = "Full screen"
		fullscreen.button_pressed = Settings.fullscreen
		fullscreen.toggled.connect(func(on): Settings.fullscreen = on; Settings.save(); Settings.apply(get_tree()))
		_content.add_child(fullscreen)
	var speeds := ["normal", "fast", "off"]
	_add_option("Turn animations", ["Normal", "Fast", "Off"], speeds.find(Settings.animation),
		func(i): Settings.animation = speeds[i]; Settings.save())
	_add_text("[i]Click during a turn's animation to skip it. Computer factions' moves always play faster.[/i]")
	_add_option("Interface size", Settings.UI_SCALES.map(func(x): return "%d%%" % roundi(x * 100)), Settings.UI_SCALES.find(Settings.ui_scale),
		func(i): Settings.ui_scale = Settings.UI_SCALES[i]; Settings.save(); Settings.apply(get_tree()))
	_add_volume("Music", Settings.music_volume, func(v): Settings.music_volume = v)
	_add_volume("Sound", Settings.sfx_volume, func(v): Settings.sfx_volume = v, true)
	_content.add_child(HSeparator.new())
	_add_text("Campaign progress: %d of %d campaigns finished." % [Progress.campaigns_finished(), Campaigns.all().size()])
	_add_button(_content, "Reset campaign progress", func(): Progress.reset(); show_settings())


# --- Campaigns ---------------------------------------------------------------------

func show_campaigns() -> void:
	_clear()
	_add_label(_content, "Campaigns", 30)
	_add_text("Each civilization has a campaign of three to five missions. Finish a mission to open the next; finish fast for a gold, silver or bronze crown. "
		+ "The Byzantine and Saracen campaigns open when those civilizations are unlocked.")
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
			var button := Button.new()
			button.text = "%d. %s   %s" % [i + 1, mission.name, _crown_text(campaign.id, i) if unlocked else "(locked)"]
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.disabled = not unlocked
			button.pressed.connect(show_briefing.bind(campaign.id, i))
			_content.add_child(button)
	_content.add_child(HSeparator.new())
	var unlock_lines := PackedStringArray()
	for civ_id in Rules.civilizations:
		var civ := Rules.civilization(civ_id)
		if civ.unlock_after_campaigns > 0:
			unlock_lines.append("%s: %s" % [civ.display_name, "unlocked: campaign, skirmish and hotseat" if Progress.civilization_unlocked(civ_id)
				else "finish %d campaign%s to unlock" % [civ.unlock_after_campaigns, "" if civ.unlock_after_campaigns == 1 else "s"]])
	_add_text("[b]More civilizations[/b]\n" + "\n".join(unlock_lines))


## The briefing (PRD H): a parchment scroll with the history, the primary
## and additional objectives, the defeat conditions and the crowns, and
## round buttons for back, the Forge (the anvil) and start.
func show_briefing(campaign_id: String, index: int) -> void:
	var scenario := Campaigns.mission(campaign_id, index)
	_briefing(scenario, "%s — Mission %d" % [Campaigns.get_campaign(campaign_id).name, index + 1], show_campaigns, campaign_id)


## A standalone scenario's briefing (PRD M): no Forge, back to the table.
func show_scenario_briefing(scenario_id: String) -> void:
	var scenario := Scenarios.get_scenario(scenario_id)
	_briefing(scenario, "Scenario — %s" % ["★".repeat(int(scenario.listing.difficulty)) + "☆".repeat(3 - int(scenario.listing.difficulty))],
		show_scenarios.bind(scenario_id), "")


func _briefing(scenario: Dictionary, heading: String, back: Callable, campaign_id: String) -> void:
	var preview := GameState.from_scenario(scenario, 1)
	var mission: Dictionary = preview.mission
	_clear()
	var scroll := BriefingScroll.new()
	scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content.add_child(scroll)
	var lines := PackedStringArray()
	lines.append("[center][font_size=16][color=#6b5a40]%s[/color][/font_size]" % heading)
	lines.append("[font_size=34][color=#6a2a14]%s[/color][/font_size][/center]" % scenario.name)
	for text in [mission.get("history", ""), mission.get("briefing", "")]:
		if text != "":
			lines.append("[i]%s[/i]\n" % text)
	lines.append(_section("Primary objective", Mission.primary(preview).map(func(o): return Mission.plain(o.text))))
	var extra := Mission.additional(preview)
	if not extra.is_empty():
		lines.append(_section("Additional objectives", extra.map(func(o): return "%s  [i](%d points)[/i]" % [Mission.plain(o.text), o.points])))
	var defeats := Mission.defeats(preview)
	if not defeats.is_empty():
		lines.append(_section("Defeat", defeats))
	var limits := Mission.crowns(preview)
	if limits.size() == 3:
		lines.append("[b]Crowns:[/b] [color=#9a7a10]gold[/color] by turn %d, [color=#6f7377]silver[/color] by %d, [color=#8a5226]bronze[/color] by %d." % limits)
	var factions := PackedStringArray()
	for faction in scenario.factions:
		var civ := Rules.civilization(faction.get("civ", ""))
		factions.append("[color=%s]%s[/color]%s" % [Color(faction.color).darkened(0.25).to_html(false), faction.name,
			" (%s%s)" % [civ.display_name if civ != null else "", ", you" if faction.get("human", false) else ""] if civ != null or faction.get("human", false) else ""])
	lines.append("[b]Map:[/b] %s, %d regions.  [b]Factions:[/b] %s" % [preview.map.display_name, preview.map.province_order.size(), ", ".join(factions)])
	scroll.set_text("\n".join(lines))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	_content.add_child(row)
	row.add_child(RoundButton.with_caption("back", "Back", back))
	if campaign_id != "":
		var forge := RoundButton.with_caption("forge", "Forge (%d)" % Progress.development_points(campaign_id), func(): _forge.show_campaign(campaign_id))
		row.add_child(forge)
		_forge.changed.connect(func():
			if is_instance_valid(forge):
				forge.get_child(1).text = "Forge (%d)" % Progress.development_points(campaign_id))
	row.add_child(RoundButton.with_caption("start", "Start", func():
		var upgrades := Progress.upgrades(campaign_id) if campaign_id != "" else {}
		_start({"scenario": Forge.equip(scenario, upgrades), "seed": randi()})))


func _section(title: String, items: Array) -> String:
	return "[b][color=#6a2a14]%s[/color][/b]\n%s\n" % [title.to_upper(), "\n".join(items.map(func(item): return "  •  " + item))]


# --- Skirmish ---------------------------------------------------------------------

func show_skirmish() -> void:
	_clear()
	_add_label(_content, "Skirmish", 30)
	_add_text("Pick a map and a civilization, and conquer every rival.")
	_add_button(_content, "Hotseat: several players on this device", show_hotseat)
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
	if others.is_empty():
		others = ["norse"]
	var picked := []
	for i in count:
		picked.append(others[i % others.size()])
	return picked


# --- Loading ----------------------------------------------------------------------

## Continue (PRD M): the autosave first, then the save slots.
func show_continue() -> void:
	_clear()
	_add_label(_content, "Continue", 30)
	var autosave := SaveGame.describe("auto")
	if autosave != "":
		_add_text("[b]Last game:[/b] %s" % autosave)
		_add_button(_content, "Resume the last game", func(): _start({"save": SaveGame.load_slot("auto")}))
	else:
		_add_text("[i]No game to resume yet. Start one from Campaigns, Scenarios or Skirmish.[/i]")
	_content.add_child(HSeparator.new())
	_add_label(_content, "Saved games", 20)
	for slot in SaveGame.SLOTS:
		if slot == "auto":
			continue
		var description := SaveGame.describe(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_content.add_child(row)
		var button := _add_button(row, "Load", func(): _start({"save": SaveGame.load_slot(slot)}))
		button.disabled = description == ""
		_add_label(row, "Slot %s: %s" % [slot, description if description != "" else "empty"], 16)


# --- Scenarios ---------------------------------------------------------------------

## The Scenarios table (PRD M): on parchment, one row per scenario with a ✓
## when won (or a padlock while locked), the player's flag, the map size
## (S, M, L), the difficulty in stars and the name; the chosen one's map
## beside it, with a button to its briefing.
func show_scenarios(selected := "") -> void:
	_clear()
	_add_label(_content, "Scenarios", 30)
	var list := Scenarios.all()
	if selected == "" or Scenarios.get_scenario(selected).is_empty():
		selected = list[0].id
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	_content.add_child(columns)
	var paper := PanelContainer.new()
	paper.theme_type_variation = "Parchment"
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(paper)
	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 2)
	paper.add_child(table)
	table.add_child(_scenario_row({}, false, false))
	for scenario in list:
		table.add_child(_scenario_row(scenario, scenario.id == selected, Scenarios.unlocked(scenario)))

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	columns.add_child(side)
	var chosen := Scenarios.get_scenario(selected)
	var preview := MapPreview.new()
	preview.custom_minimum_size = Vector2(380, 250)
	side.add_child(preview)
	preview.show_scenario(chosen)
	# The Briefing button sits beside the text, so a long history can't push it below the menu bar.
	var below := HBoxContainer.new()
	below.add_theme_constant_override("separation", 10)
	side.add_child(below)
	var about := RichTextLabel.new()
	about.bbcode_enabled = true
	about.fit_content = true
	about.custom_minimum_size = Vector2(290, 0)
	about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	about.add_theme_font_size_override("normal_font_size", 15)
	var history: String = chosen.mission.get("history", chosen.mission.get("briefing", ""))
	about.text = "[b]%s[/b]\n[i]%s[/i]" % [chosen.name, history]
	below.add_child(about)
	if Scenarios.unlocked(chosen):
		var start := RoundButton.with_caption("start", "Briefing", show_scenario_briefing.bind(selected))
		start.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		below.add_child(start)
	else:
		about.text += "\n[color=#c8b48a]Locked: win %d scenario%s to open it.[/color]" % [int(chosen.listing.unlock_after),
			"" if int(chosen.listing.unlock_after) == 1 else "s"]


## One row of the table, or its heading row for an empty scenario.
func _scenario_row(scenario: Dictionary, selected: bool, open: bool) -> Control:
	var ink := Color("#2f2012")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var widths := [26, 30, 40, 70]
	if scenario.is_empty():
		for entry in [["", widths[0]], ["", widths[1]], ["Size", widths[2]], ["Difficulty", widths[3]], ["Scenario", 0]]:
			var label := Label.new()
			label.text = entry[0]
			label.custom_minimum_size = Vector2(entry[1], 0)
			label.add_theme_color_override("font_color", Color("#6a2a14"))
			label.add_theme_font_size_override("font_size", 14)
			label.add_theme_font_override("font", load("res://assets/fonts/Cinzel.ttf"))
			row.add_child(label)
		return row
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(show_scenarios.bind(scenario.id))
	var shade := ColorRect.new()
	shade.color = Color("#6a2a14", 0.16) if selected else Color(0, 0, 0, 0)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(shade)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	var player: String = scenario.mission.player
	var faction: Dictionary = scenario.factions.filter(func(f): return f.id == player)[0]
	var mark := Control.new()
	mark.custom_minimum_size = Vector2(widths[0], 36)
	mark.draw.connect(func():
		var c := mark.size / 2.0
		if not open:  # A padlock.
			mark.draw_arc(c + Vector2(0, -3), 6.0, PI, TAU, 12, ink, 2.5, true)
			mark.draw_rect(Rect2(c + Vector2(-8, -3), Vector2(16, 12)), ink)
		elif Progress.scenario_won(scenario.id):
			mark.draw_polyline(PackedVector2Array([c + Vector2(-7, 0), c + Vector2(-2, 6), c + Vector2(8, -7)]), Color("#2e7d32"), 3.5, true))
	row.add_child(mark)
	var flag := Control.new()
	flag.custom_minimum_size = Vector2(widths[1], 36)
	flag.draw.connect(func():
		var foot := Vector2(6, 34)
		flag.draw_line(foot, foot + Vector2(0, -30), ink, 2.0)
		flag.draw_colored_polygon(PackedVector2Array([foot + Vector2(1, -30), foot + Vector2(20, -27), foot + Vector2(15, -21),
			foot + Vector2(20, -15), foot + Vector2(1, -16)]), Color(faction.color)))
	row.add_child(flag)
	var size_label := Label.new()
	size_label.text = Scenarios.size_class(scenario)
	size_label.custom_minimum_size = Vector2(widths[2], 0)
	size_label.add_theme_color_override("font_color", ink)
	row.add_child(size_label)
	var stars := Control.new()
	stars.custom_minimum_size = Vector2(widths[3], 36)
	var difficulty := int(scenario.listing.difficulty)
	stars.draw.connect(func():
		for i in 3:
			TypeIcons.draw_star(stars, Vector2(10 + i * 22, 18), 8.0, 1.0 if i < difficulty else 0.25))
	row.add_child(stars)
	var name := Label.new()
	name.text = scenario.name
	name.add_theme_color_override("font_color", ink if open else ink.lightened(0.4))
	row.add_child(name)
	return button


# --- Records and credits ------------------------------------------------------------

## Records (PRD M): your rank and score, each campaign's crowns and
## development points, and the scenarios won.
func show_records() -> void:
	_clear()
	_add_label(_content, "Records", 30)
	var score := Progress.total_score()
	var rank := Progress.rank(score)
	_add_text("[font_size=22][color=#f3d77e]Your rank: %s[/color][/font_size]   %d points%s" % [rank.name, score,
		"  ·  %d more for %s" % [int(Progress.RANKS[rank.index + 1][1]) - score, rank.next] if rank.next != "" else ""])
	for campaign in Campaigns.all():
		var crowns := PackedStringArray()
		for i in campaign.missions.size():
			crowns.append(_crown_text(campaign.id, i) if Progress.mission_unlocked(campaign.id, i) else "locked")
		_add_text("[b]%s[/b] — %s\n[i]%s.[/i]  Development points to spend: %d" % [campaign.name, Rules.civilization(campaign.civ).display_name,
			", ".join(crowns), Progress.development_points(campaign.id)])
	var won := Scenarios.all().filter(func(s): return Progress.scenario_won(s.id))
	_add_text("[b]Scenarios won:[/b] %d of %d%s" % [won.size(), Scenarios.all().size(),
		"\n" + "\n".join(won.map(func(s): return "  •  %s (%s)" % [s.name, Mission.CROWN_NAMES[Progress.scenario_crown(s.id)] + " crown" if Progress.scenario_crown(s.id) > 0 else "won"])) if not won.is_empty() else ""])


func show_credits() -> void:
	_clear()
	_add_label(_content, "Credits", 30)
	_add_text("Medieval Conquest is a turn-based strategy game in the spirit of [i]Strategy & Tactics: Medieval Wars[/i]. " \
		+ "Its maps, region names, campaigns, art and text are its own.")
	_add_text(CREDIT_LINE)
	_add_text("Version %s. Downloads and source: github.com/Stephen-SMH/medieval-conquest" \
		% ProjectSettings.get_setting("application/config/version", "dev"))


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


## A volume slider (0 to 100%) that applies and saves at once. The Sound
## slider jingles coins when let go, to hear the new level.
func _add_volume(title: String, value: float, set_value: Callable, test_sound := false) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_content.add_child(row)
	var label := _add_label(row, title, 17)
	label.custom_minimum_size = Vector2(220, 0)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = roundf(value * 100.0)
	slider.custom_minimum_size = Vector2(280, 32)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var percent := _add_label(row, "%d%%" % roundi(slider.value), 17)
	percent.custom_minimum_size = Vector2(60, 0)
	slider.value_changed.connect(func(v):
		set_value.call(v / 100.0)
		percent.text = "%d%%" % roundi(v)
		AudioManager.apply_volumes()
		Settings.save())
	slider.drag_ended.connect(func(_changed):
		if test_sound:
			AudioManager.sfx("coins"))
	return slider


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


func _crown_text(campaign_id: String, index: int) -> String:
	if not Progress.won(campaign_id, index):
		return "not won yet"
	var crown := Progress.stars(campaign_id, index)
	return "%s crown" % Mission.CROWN_NAMES[crown] if crown > 0 else "won"


func _specials_text(civ: Civilization) -> String:
	return "Special units: %s." % ", ".join(civ.special_units.map(func(u): return Rules.unit(u).display_name))


## Two armies facing each other under their banners, on the title screen.
class Muster:
	extends Control
	const LEFT := [["knight", Color("#3d6fb6")], ["spearmen", Color("#3d6fb6")], ["archers", Color("#3d6fb6")]]
	const RIGHT := [["huscarl", Color("#b5423a")], ["berserker", Color("#b5423a")], ["catapult", Color("#b5423a")]]
	var _textures := {}

	func _init() -> void:
		custom_minimum_size = Vector2(0, 190)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		# Keep the textures alive: draw calls only hold their RIDs.
		for entry in LEFT + RIGHT:
			_textures[entry[0]] = TokenLayer.figure_textures(entry[0])

	func _draw() -> void:
		var ground := size.y - 18.0
		var sprite := 150.0
		var groups := [[LEFT, 70.0, "frankish", 1.0], [RIGHT, size.x - 430.0, "norse", -1.0]]
		for group in groups:
			var x: float = group[1]
			var color: Color = group[0][0][1]
			TokenLayer.draw_banner(self, Vector2(x + 330.0, ground - 4.0), 150.0, color, group[2])
			for entry in group[0]:
				var feet := Vector2(x, ground)
				var textures: Array = _textures[entry[0]]
				draw_set_transform(feet + Vector2(0, 4), 0.0, Vector2(1.0, 0.25))
				draw_circle(Vector2.ZERO, 48.0, Color(0, 0, 0, 0.3))
				draw_set_transform(Vector2.ZERO)
				# The right-hand army is mirrored so the two face each other.
				draw_set_transform(feet, 0.0, Vector2(group[3], 1.0))
				var rect := Rect2(-Vector2(sprite * 0.5, sprite * TokenLayer.FIGURE_FEET), Vector2(sprite, sprite))
				draw_texture_rect(textures[0], rect, false)
				if textures[1] != null:
					draw_texture_rect(textures[1], rect, false, color.lightened(0.12))
				draw_set_transform(Vector2.ZERO)
				x += 105.0
