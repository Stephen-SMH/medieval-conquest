extends RefCounted
## V4: the Forge (which replaced research), hotseat, touch gestures, settings
## and export presets.

const Helpers := preload("res://tests/helpers.gd")


func run(t) -> void:
	_test_forge(t)
	_test_hotseat(t)
	_test_touch(t)
	_test_settings_and_exports(t)


## The Forge between missions (G), as S&T's: rows of cards bought left to
## right with the campaign's mission score.
func _test_forge(t) -> void:
	t.check(not ResourceLoader.exists("res://scripts/game/research.gd") and not ("techs" in FactionState.new())
		and Rules.units.values().all(func(u): return not ("required_tech" in u)), "research is gone: every soldier type can be bought")
	t.check(Forge.rows("military").map(func(r): return r.id) == ["infantry", "archers", "cavalry", "engines"]
		and Forge.rows("economy").map(func(r): return r.id) == ["builders", "treasury", "armouries"], "S&T's rows: three of soldiers and engines, three of economy")
	t.check(TypeIcons.FAMILIES.all(func(f): return Forge.row_of(f) != ""), "every line of soldiers has a row")
	t.check(Forge.describe("infantry", 0) == "Field Training (infantry lvl.2): defense bonus" and Forge.describe("archers", 0) == "Reorganization (archers lvl.2): defense bonus"
		and Forge.describe("builders", 2) == "Upgrade costs decreased by 5%" and Forge.describe("treasury", 0) == "5% more gold per turn",
		"the line under the cards, as S&T words it")
	var owned := {}
	t.check(Forge.problem(owned, "archers", 0, 299) == "needs 300 points" and Forge.problem(owned, "archers", 0, 300) == "", "the first card costs 300")
	t.check(Forge.problem(owned, "archers", 1, 9999) == "the card before it comes first", "a row is bought from left to right")
	Forge.raise(owned, "archers")
	Forge.raise(owned, "archers")
	Forge.raise(owned, "archers")
	Forge.raise(owned, "cavalry")
	Forge.raise(owned, "cavalry")
	t.check(Forge.problem(owned, "archers", 0, 9999) == "already bought" and Forge.problem(owned, "archers", 3, 900) == "", "then the next one")
	Forge.raise(owned, "builders")
	Forge.raise(owned, "builders")
	t.check(Forge.price(owned, "archers", 3) == 810 and Forge.price({}, "archers", 3) == 900, "each builders' card takes 5% off the Forge's prices")
	t.check(Forge.normalized({"spears": {"defense": 2}, "archers": 3.0, "nonsense": 1}) == {"archers": 3}, "older {line: {stat: level}} upgrades no longer count")

	# In battle: +10% a card, for that row's soldiers only.
	var state := Helpers.game({"greywater": "blue", "kingsvale": "blue", "ashford": "red"}, [
		["blue", "greywater", "longbowman"], ["blue", "kingsvale", "knight"], ["red", "ashford", "archers"]], 7,
		{"blue_civ": "frankish"})
	state.upgrades = {"blue": owned}
	var bows: Troop = state.unit_in("greywater").troops[0]
	var horse: Troop = state.unit_in("kingsvale").troops[0]
	var theirs: Troop = state.unit_in("ashford").troops[0]
	state.prepare_for_battle(bows, "blue", false, "ashford")
	state.prepare_for_battle(horse, "blue", true, "kingsvale")
	state.prepare_for_battle(theirs, "red", true, "ashford")
	t.check(is_equal_approx(bows.attack_mod, 1.2) and is_equal_approx(bows.defense_mod, 1.1), "archers' reorganization: +10% defense; volley drill and keen eyes: +20% attack (longbows too)")
	t.check(is_equal_approx(horse.toughness, 1.1) and is_equal_approx(horse.defense_mod, 1.1) and horse.attack_mod == 1.0, "cavalry's saddles and remounts")
	t.check(theirs.attack_mod == 1.0 and not state.is_upgraded("red", "archers") and state.is_upgraded("blue", "archers")
		and state.is_upgraded("blue", "knight") and not state.is_upgraded("blue", "spearmen"), "only the owner's upgraded rows get the star")
	var saved := SaveGame.from_dict(JSON.parse_string(JSON.stringify(SaveGame.to_dict(state))))
	t.check(saved.upgrades == state.upgrades, "upgrades survive save and load")

	# The economy tab: income and reinforcements.
	var town := Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "militia"]], 7)
	var before := Economy.region_income(town, "greywater")
	var price_before := Economy.soldier_price(town, "blue", Rules.unit("spearmen"))
	town.upgrades = {"blue": {"treasury": 2, "armouries": 4}}
	t.check(is_equal_approx(Bonuses.income(town, "blue", "gold"), 1.1) and is_equal_approx(Bonuses.income(town, "red", "gold"), 1.0),
		"two treasury cards: +10% income, for their owner only")
	t.check(is_equal_approx(Bonuses.recruit_cost(town, "blue", Rules.unit("spearmen")), 0.8), "four armouries cards: reinforcements 20% cheaper")
	t.check(Economy.region_income(town, "greywater") > before and is_equal_approx(Economy.soldier_price(town, "blue", Rules.unit("spearmen")), price_before * 0.8),
		"so regions bring in more and soldiers cost less")

	# Points are the campaign's best mission scores, less what the Forge cost.
	Progress.path = "user://test_forge_progress.json"
	Progress.reset()
	Progress.record("norse", 0, 3, 500)
	Progress.record("norse", 0, 1, 300)
	Progress.record("norse", 1, 2, 400)
	t.check(Progress.forge_points("norse") == 900 and Progress.forge_points("anglish") == 0,
		"each mission's best score counts; a campaign's points are its own")
	t.check(Progress.buy_upgrade("norse", "infantry") and Progress.buy_upgrade("norse", "infantry")
		and Progress.forge_points("norse") == 150 and Progress.upgrades("norse") == {"infantry": 2}, "the Forge spends them: 300, then 450")
	t.check(not Progress.buy_upgrade("norse", "infantry") and not Progress.buy_upgrade("anglish", "infantry"), "with too few points nothing can be bought")
	var scenario := Forge.equip(Campaigns.mission("norse", 1), Progress.upgrades("norse"))
	var game := GameState.from_scenario(scenario, 1)
	t.check(game.upgrades == {scenario.mission.player: {"infantry": 2}}, "a campaign mission starts with the campaign's upgrades")
	DirAccess.remove_absolute(Progress.path)
	Progress.path = Progress.PATH

	# The screen: rows of cards, the next one bold, a bought one with a chevron.
	var screen := ForgeScreen.new()
	t.check(screen.has_method("show_campaign") and ForgeCard.SKETCHES.has("tent") and Forge.TABS.values().all(func(rows):
		return rows.all(func(r): return r.cards.all(func(c): return ForgeCard.SKETCHES.has(c[2]))))
		and ForgeCard.SKETCHES.values().all(func(parts): return parts.all(func(p): return ResourceLoader.exists("res://assets/forge/%s.svg" % p[0]))),
		"every card has a sketch, and every sketch its shapes")
	screen.free()


func _test_hotseat(t) -> void:
	var scenario := Skirmish.build("heartlands", [{"civ": "norse", "human": true}, {"civ": "anglish", "human": true}, {"civ": "frankish"}], "normal", 2)
	var state := GameState.from_scenario(scenario, 2)
	t.check(state.viewer() == "norse" and scenario.factions[0].name.ends_with("(Player 1)"), "hotseat: player 1 goes first and players are numbered")
	var norse_view := state.visible_provinces(state.viewer())
	state.end_faction_turn()
	t.check(state.viewer() == "anglish" and state.visible_provinces(state.viewer()) != norse_view, "then the map is drawn for player 2, with their own fog of war")
	state.end_faction_turn()
	t.check(state.current_faction() == "frankish" and state.viewer() == "norse", "during the computer's turn the view goes back to the first human")
	t.check(state.factions.values().filter(func(f): return f.human).size() == 2, "two humans, one computer")


func _test_touch(t) -> void:
	var touch := TouchGestures.new()
	var finger := func(index: int, at: Vector2, pressed := true) -> InputEventScreenTouch:
		var event := InputEventScreenTouch.new()
		event.index = index
		event.position = at
		event.pressed = pressed
		return event
	var drag := func(index: int, at: Vector2) -> InputEventScreenDrag:
		var event := InputEventScreenDrag.new()
		event.index = index
		event.position = at
		return event
	touch.handle(finger.call(0, Vector2(100, 100)))
	t.check(not touch.is_multi_touch() and touch.handle(drag.call(0, Vector2(120, 100))).is_empty(), "one finger is left to act as the mouse")
	touch.handle(finger.call(1, Vector2(220, 100)))
	var pinch := touch.handle(drag.call(1, Vector2(320, 100)))
	t.check(touch.is_multi_touch() and is_equal_approx(pinch.zoom, 2.0) and pinch.pan == Vector2(50, 0),
		"spreading two fingers from 100 to 200 px apart zooms ×2 and pans by the midpoint's move %s" % [pinch])
	touch.handle(finger.call(1, Vector2(320, 100), false))
	t.check(not touch.is_multi_touch(), "lifting a finger ends the pinch")


func _test_settings_and_exports(t) -> void:
	Settings.ensure_loaded()
	var was := Settings.animation
	Settings.animation = "fast"
	Settings.save()
	var config := ConfigFile.new()
	t.check(config.load(Settings.PATH) == OK and config.get_value("game", "animation") == "fast", "settings are saved to user://settings.cfg")
	Settings.animation = was
	Settings.save()

	var presets := ConfigFile.new()
	t.check(presets.load("res://export_presets.cfg") == OK, "export presets exist")
	var names := {}
	for section in presets.get_sections():
		if presets.has_section_key(section, "platform"):
			names[presets.get_value(section, "platform")] = section
	t.check(names.has("Web") and names.has("Android"), "there are Web and Android presets %s" % [names.keys()])
	t.check(presets.get_value(names.Web + ".options", "variant/thread_support") == false, "the web export has thread support off")
	t.check(presets.get_value(names.Web, "include_filter") == "data/*.json" and presets.get_value(names.Android, "include_filter") == "data/*.json",
		"both exports include the JSON maps, scenarios and campaigns")
	t.check(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch") == true, "taps act as clicks on touch screens")
