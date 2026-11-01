extends Control
## The menus: campaigns with briefings (PRD CP-4, CP-7), skirmish setup
## (CP-5), hotseat (CP-6), loading a saved game, and settings.

const GAME_SCENE := "res://scenes/main.tscn"
const DIFFICULTIES := ["easy", "normal", "hard"]
const CREDIT_LINE := "Unit figures rendered from CC0 3D models by Quaternius. Icons by Lorc, Delapouite, HeavenlyDog and " \
	+ "Guard13007 from game-icons.net (CC BY 3.0). Fonts: Cinzel and IM FELL English (SIL Open Font License). " \
	+ "Music by RandomMind, cynicmusic and Emma_MA (CC0). Sounds by Kenney and by freesound.org users HebronTheatre, " \
	+ "mcaseydesign, craigsmith, el_boss and freefire66 (CC0). See CREDITS.md."

var _content: VBoxContainer
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

	var columns := HBoxContainer.new()
	columns.set_anchors_preset(Control.PRESET_FULL_RECT)
	columns.add_theme_constant_override("separation", 0)
	add_child(columns)

	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(300, 0)
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
	AudioManager.music("menu")
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


func _menu_entries() -> Array:
	var entries := [
		["Tutorial", start_tutorial],
		["Campaigns", show_campaigns],
		["Skirmish", show_skirmish],
		["Hotseat", show_hotseat],
		["Load game", show_load],
		["Settings", show_settings],
	]
	if not OS.has_feature("web"):
		entries.append(["Quit", func(): get_tree().quit()])
	return entries


# --- Title ---------------------------------------------------------------------------

func show_title() -> void:
	_clear()
	_add_label(_content, "Medieval Conquest", 48, Color("#f2d16b"))
	_add_text("Every region holds one unit. Click it, then a neighbouring region: a [color=#7fa8f0]blue arrow[/color] marches there, " \
		+ "a [color=#f07060]red arrow[/color] attacks. Plan every unit, then turn the hourglass: all sides move at once. " \
		+ "Spears beat horse, horse beats bows, bows beat spears.")
	var autosave := SaveGame.describe("auto")
	if autosave != "":
		_add_text("[b]Last game:[/b] " + autosave)
		_add_button(_content, "Continue", func(): _start({"save": SaveGame.load_slot("auto")}))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_content.add_child(row)
	_add_button(row, "Tutorial", start_tutorial)
	_add_button(row, "Campaigns", show_campaigns)
	_add_button(row, "Skirmish", show_skirmish)
	_add_button(row, "Hotseat", show_hotseat)
	var done := Progress.campaigns_finished()
	_add_text("[i]Campaigns finished: %d of %d.[/i]" % [done, Campaigns.all().size()])
	_content.add_child(Muster.new())
	_content.add_child(HSeparator.new())
	_add_text("[font_size=13]" + CREDIT_LINE + "[/font_size]")


# --- Hotseat ---------------------------------------------------------------------------

func show_hotseat() -> void:
	_clear()
	_add_label(_content, "Hotseat", 30)
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
	var forecast := CheckBox.new()
	forecast.text = "Show the battle forecast before attacking"
	forecast.button_pressed = Settings.show_forecast
	forecast.toggled.connect(func(on): Settings.show_forecast = on; Settings.save())
	_content.add_child(forecast)
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
	_add_text("Each civilization has a campaign of three to five missions. Finish a mission to open the next; finish under par for 3 stars. "
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
			unlock_lines.append("%s: %s" % [civ.display_name, "unlocked: campaign, skirmish and hotseat" if Progress.civilization_unlocked(civ_id)
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
	if others.is_empty():
		others = ["norse"]
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


func _stars_text(count: int) -> String:
	return "%d/3 stars" % count if count > 0 else "not played"


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
