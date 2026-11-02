extends RefCounted
## V4: the Forge (which replaced research), hotseat, touch gestures, settings
## and export presets.

const Helpers := preload("res://tests/helpers.gd")


func run(t) -> void:
	_test_forge(t)
	_test_hotseat(t)
	_test_touch(t)
	_test_settings_and_exports(t)


## The Forge between missions (G) replaces research: development points buy
## attack, defense and health levels for a line of soldiers.
func _test_forge(t) -> void:
	t.check(not ResourceLoader.exists("res://scripts/game/research.gd") and not ("techs" in FactionState.new())
		and Rules.units.values().all(func(u): return not ("required_tech" in u)), "research is gone: every soldier type can be bought")
	var owned := {}
	t.check(Forge.problem(owned, "bow", "attack", 0) == "needs 1 point" and Forge.problem(owned, "bow", "attack", 1) == "", "a first level costs 1 point")
	Forge.raise(owned, "bow", "attack")
	Forge.raise(owned, "bow", "attack")
	t.check(Forge.spent(owned) == 3 and Forge.problem(owned, "bow", "attack", 2) == "needs 3 points", "the next 2, then 3")
	Forge.raise(owned, "bow", "attack")
	Forge.raise(owned, "horse", "health")
	t.check(Forge.spent(owned) == 7 and Forge.problem(owned, "bow", "attack", 99) == "fully upgraded", "up to level 3")
	t.check(Forge.families("norse") == TypeIcons.FAMILIES and Forge.families("") == TypeIcons.FAMILIES, "every civilization fields all seven lines")

	# In battle: +10% a level, for that line only.
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
	t.check(is_equal_approx(bows.attack_mod, 1.3) and bows.defense_mod == 1.0, "3 attack levels: archers' line attacks 30% harder (longbows too)")
	t.check(is_equal_approx(horse.toughness, 1.1) and horse.attack_mod == 1.0, "1 health level: cavalry take 10% less damage")
	t.check(theirs.attack_mod == 1.0 and not state.is_upgraded("red", "archers") and state.is_upgraded("blue", "archers")
		and state.is_upgraded("blue", "knight") and not state.is_upgraded("blue", "spearmen"), "only the owner's upgraded lines get the star")
	var saved := SaveGame.from_dict(JSON.parse_string(JSON.stringify(SaveGame.to_dict(state))))
	t.check(saved.upgrades == state.upgrades, "upgrades survive save and load")

	# Points come from missions and stay with the campaign.
	Progress.path = "user://test_forge_progress.json"
	Progress.reset()
	Progress.record("norse", 0, 3, 5)
	Progress.record("norse", 0, 1, 3)
	Progress.record("norse", 1, 2, 4)
	t.check(Progress.mission_points("norse", 0) == 5 and Progress.development_points("norse") == 9 and Progress.development_points("anglish") == 0,
		"each mission keeps its best points; a campaign's points are its own")
	t.check(Progress.buy_upgrade("norse", "spears", "defense") and Progress.buy_upgrade("norse", "spears", "defense")
		and Progress.development_points("norse") == 6 and Progress.upgrades("norse") == {"spears": {"defense": 2}}, "the Forge spends them")
	t.check(not Progress.buy_upgrade("anglish", "spears", "defense"), "with no points nothing can be bought")
	var scenario := Forge.equip(Campaigns.mission("norse", 1), Progress.upgrades("norse"))
	var game := GameState.from_scenario(scenario, 1)
	t.check(game.upgrades == {scenario.mission.player: {"spears": {"defense": 2}}}, "a campaign mission starts with the campaign's upgrades")
	DirAccess.remove_absolute(Progress.path)
	Progress.path = Progress.PATH

	var won := Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "spearmen"]], 7)
	won.mission = {"player": "blue", "objectives": [{"type": "capture", "regions": ["greywater"]}], "par": 5}
	won.update_result()
	t.check(won.result.result == "won" and won.result.development == Mission.DEVELOPMENT_FOR_WIN + 3, "a won mission earns development points (%s)" % [won.result])


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
