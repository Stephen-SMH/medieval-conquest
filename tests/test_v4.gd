extends RefCounted
## V4: research trees and their effects, hotseat, touch gestures, settings and
## export presets.

const Helpers := preload("res://tests/helpers.gd")


func run(t) -> void:
	_test_trees(t)
	_test_research_flow(t)
	_test_research_effects(t)
	_test_hotseat(t)
	_test_touch(t)
	_test_settings_and_exports(t)


func _test_trees(t) -> void:
	Rules.ensure_loaded()
	for tree in ["economy", "military"]:
		var techs := Rules.techs.values().filter(func(x: TechType): return x.tree == tree)
		var tiers := {}
		for tech: TechType in techs:
			tiers[tech.tier] = true
		t.check(techs.size() == 6 and tiers.keys().size() == 3, "the %s tree has 6 techs in 3 tiers" % tree)
	var turns_ok := Rules.techs.values().all(func(x: TechType): return x.turns >= 2 and x.turns <= 4 and x.cost_gold > 0)
	t.check(turns_ok, "every tech costs gold and takes 2-4 turns")
	var requires_ok := Rules.techs.values().all(func(x: TechType): return x.requires.all(func(r): return Rules.techs.has(r) and Rules.tech(r).tier < x.tier))
	t.check(requires_ok, "every tech needs only techs from lower tiers")


func _test_research_flow(t) -> void:
	var state := Helpers.game({"greywater": "blue"}, [], 7, {"resources": {"blue": {"gold": 1000}}})
	var blue: FactionState = state.factions.blue
	t.check(Research.problem(state, "blue", "mining") == "needs Coinage", "techs need their prerequisites")
	t.check(Research.start(state, "blue", "coinage") and blue.resources.gold == 900.0, "research is paid in gold when it starts")
	t.check(Research.problem(state, "blue", "crop_rotation").begins_with("already researching"), "one tech at a time")
	Helpers.resolve(state)  # Red holds nothing here, so each end of turn is a full turn.
	t.check(not blue.has_tech("coinage") and blue.research_turns_left == 1, "after 1 of 2 turns it isn't done")
	var events := Helpers.resolve(state)
	t.check(blue.has_tech("coinage") and blue.researching == "" and events.any(func(e): return "Research complete" in e.get("text", "")),
		"after 2 turns Coinage is known and reported")
	var saved := SaveGame.from_dict(JSON.parse_string(JSON.stringify(SaveGame.to_dict(state))))
	t.check(saved.factions.blue.has_tech("coinage"), "research survives save and load")

	state = Helpers.game({"greywater": "blue", "eastwold": "red"}, [], 7, {"resources": {"red": {"gold": 600}}})
	Helpers.plan_as(state, "red")
	AI.play_turn(state)
	t.check(state.factions.red.researching != "", "the AI picks research (%s)" % state.factions.red.researching)


func _test_research_effects(t) -> void:
	var state := Helpers.game({"greywater": "blue", "kingsvale": "blue", "highcrag": "blue"}, [
		["blue", "greywater", "spearmen"], ["blue", "kingsvale", "archers"], ["blue", "northmarch", "heavy_cavalry"]], 7,
		{"buildings": {"greywater": {"market": 2, "siege_workshop": 1, "stable": 1, "barracks": 1}, "kingsvale": {"walls": 1}},
			"resources": {"blue": {"gold": 5000}}})
	var blue: FactionState = state.factions.blue
	var plains := Economy.region_income(state, "kingsvale")
	var mountains := Economy.region_income(state, "highcrag")
	var upkeep := Economy.unit_upkeep(state, state.unit_in("greywater"))
	t.check(Economy.recruit_problem(state, "greywater", "catapult", "blue") == "needs research: Siege Engineering"
		and Economy.recruit_problem(state, "greywater", "heavy_cavalry", "blue") == "needs research: Stirrups",
		"catapults need Siege Engineering and heavy cavalry needs Stirrups")
	t.check(Sieges.duration(state, "kingsvale", "blue") == 2, "a palisade holds out 2 turns")

	blue.techs.assign(["crop_rotation"])
	t.check(Economy.region_income(state, "highcrag") == mountains + 1.0, "Crop Rotation: +1 gold from every region")
	blue.techs.assign(["mining"])
	t.check(Economy.region_income(state, "highcrag") == mountains + 5.0, "Mining: +5 gold from mountains")
	blue.techs.assign(["heavy_plough"])
	t.check(Economy.region_income(state, "kingsvale") == plains + 2.0, "Heavy Plough: +2 gold from plains")
	blue.techs.assign(["coinage"])
	t.check(Economy.region_income(state, "highcrag") == roundf(mountains * 1.15), "Coinage: +15% gold")
	blue.techs.assign(["guilds"])
	t.check(Economy.region_income(state, "greywater") == 10.0 + 16.0 * 1.25, "Guilds: +25% from markets")
	blue.techs.assign(["logistics"])
	t.check(is_equal_approx(Economy.unit_upkeep(state, state.unit_in("greywater")), upkeep * 0.8), "Logistics: upkeep costs 20% less")

	blue.techs.assign(Rules.techs.keys())
	t.check(not Economy.recruit_problem(state, "greywater", "catapult", "blue").begins_with("needs research")
		and not Economy.recruit_problem(state, "greywater", "heavy_cavalry", "blue").begins_with("needs research"),
		"the researched units no longer need research")
	t.check(Sieges.duration(state, "kingsvale", "blue") == 1, "Siege Engineering: sieges take 1 turn less")
	state.prepare_for_battle(state.unit_in("greywater"), true, "greywater")
	state.prepare_for_battle(state.unit_in("kingsvale"), false, "greywater")
	state.prepare_for_battle(state.unit_in("northmarch"), false, "greywater")
	t.check(is_equal_approx(state.unit_in("greywater").defense_mod, 1.1) and is_equal_approx(state.unit_in("greywater").attack_mod, 1.1),
		"Chain Mail +10% infantry defense, Tempered Steel +10% melee attack")
	t.check(is_equal_approx(state.unit_in("kingsvale").attack_mod, 1.15), "Composite Bows: +15% ranged attack")
	t.check(is_equal_approx(state.unit_in("northmarch").charge_mod, 1.15), "Stirrups: +15% cavalry charge")
	state.remove_unit(state.unit_in("greywater"))
	Economy.recruit(state, "greywater", "spearmen")
	Helpers.resolve(state)
	t.check(state.unit_in("greywater").rank_name() == "Veteran", "Drill: new units start as Veterans")


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
	var was := Settings.show_forecast
	Settings.show_forecast = false
	Settings.save()
	var config := ConfigFile.new()
	t.check(config.load(Settings.PATH) == OK and config.get_value("game", "show_forecast") == false, "settings are saved to user://settings.cfg")
	Settings.show_forecast = was
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
