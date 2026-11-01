extends RefCounted
## V2: sieges, missions and stars, save/load, and the AI (including a full
## AI-only game).

const Helpers := preload("res://tests/helpers.gd")


func run(t) -> void:
	_test_sieges(t)
	_test_missions(t)
	_test_saves(t)
	_test_ai(t)


func _test_sieges(t) -> void:
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red"}, [
		["blue", "greywater", "swordsmen"], ["blue", "greywater", "catapult"], ["red", "kingsvale", "spearmen"]], 7,
		{"buildings": {"kingsvale": {"walls": 2}}})
	var swords: Array[Unit] = [state.units[0]]
	var with_catapult: Array[Unit] = [state.units[0], state.units[1]]
	t.check(Sieges.wall_bonus(state, "kingsvale", swords) == 1.0, "stone walls: defenders take half damage (bonus +100%)")
	t.check(Sieges.wall_bonus(state, "kingsvale", with_catapult) == 0.75, "each attacking catapult cuts the wall bonus by 25 points")
	t.check(Sieges.duration(state, "kingsvale", "blue") == 4, "stone walls hold out 4 turns")
	t.check(Sieges.besiege_problem(state, [state.units[1]], "kingsvale") != "", "catapults alone can't besiege")
	t.check(Sieges.besiege_problem(state, state.units_in("greywater"), "redfield") == "no walls to besiege", "only walled regions can be besieged")
	t.check(Sieges.besiege(state, state.units_in("greywater"), "kingsvale") and state.units[0].attacked, "besieging uses the units' attack")
	var hp_before: float = state.units[2].hp
	for i in 4:
		state.end_faction_turn()
		state.end_faction_turn()
	t.check(Sieges.breached(state, "kingsvale") and state.provinces.kingsvale.siege_turns == 4, "after 4 turns next to the walls they are breached")
	t.check(state.units[2].hp < hp_before, "breached walls starve the defenders")
	t.check(Sieges.wall_bonus(state, "kingsvale", swords) == 0.0, "breached walls give no bonus against the besieger")
	state.units[0].province = "northmarch"
	state.units[1].province = "northmarch"
	state.end_faction_turn()
	t.check(state.provinces.kingsvale.siege_faction == "", "the siege is lifted when the besiegers leave")

	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "swordsmen"]], 7,
		{"buildings": {"kingsvale": {"walls": 3}}})
	state.move_unit(state.units[0], "kingsvale")
	t.check(state.owners.kingsvale == "blue", "empty walls are taken by walking in")


func _test_missions(t) -> void:
	t.check(Mission.stars_for(8, 8) == 3 and Mission.stars_for(11, 8) == 2 and Mission.stars_for(12, 8) == 1 and Mission.stars_for(15, 8) == 1,
		"stars: at par 3, under 1.5 × par 2, otherwise 1")
	var mission := {"player": "blue", "par": 4, "objectives": [{"type": "capture", "regions": ["kingsvale"]}]}
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red", "eastwold": "red"},
		[["blue", "greywater", "swordsmen"], ["red", "eastwold", "militia"]], 7, {"capitals": {"blue": "greywater"}})
	state.mission = mission.duplicate(true)
	t.check(not state.is_over() and not Mission.objectives(state)[0].done, "the objective starts open")
	state.move_unit(state.units[0], "kingsvale")
	t.check(state.is_over() and state.result.result == "won" and state.result.stars == 3, "capturing the target on turn 1 (par 4) wins with 3 stars")

	state = Helpers.game({"greywater": "blue", "kingsvale": "red", "eastwold": "red"},
		[["blue", "greywater", "militia"], ["red", "kingsvale", "militia"]], 7, {"capitals": {"blue": "greywater"}})
	state.mission = mission.duplicate(true)
	for i in 7:
		state.end_faction_turn()
		state.end_faction_turn()
	t.check(not state.is_over() and state.turn == 8 and Mission.hard_limit(state) == 8,
		"the hard limit is par × 2: turn 8 of 8 is still playable")
	state.end_faction_turn()
	state.end_faction_turn()
	t.check(state.is_over() and state.result.result == "lost" and "Out of time" in state.result.reason,
		"passing the hard limit loses the mission")

	state = Helpers.game({"greywater": "blue", "kingsvale": "blue", "eastwold": "red"}, [["red", "eastwold", "militia"]], 7)
	state.mission = {"player": "blue", "par": 10, "objectives": [{"type": "hold", "region": "kingsvale", "turns": 2}]}
	state.end_faction_turn()
	t.check(Mission.objectives(state)[0].text.ends_with("(1 so far)"), "holding a region counts your turns")
	state.end_faction_turn()
	state.end_faction_turn()
	t.check(state.is_over() and state.result.result == "won", "holding it for 2 turns wins")

	state = Helpers.game({"greywater": "blue", "ashford": "blue", "kingsvale": "red"},
		[["blue", "ashford", "militia"], ["red", "kingsvale", "swordsmen"]], 7, {"capitals": {"blue": "greywater"}})
	state.mission = {"player": "blue", "par": 10, "objectives": [{"type": "destroy", "faction": "red"}]}
	state.end_faction_turn()
	state.move_unit(state.units[1], "greywater")
	t.check(state.is_over() and state.result.result == "lost" and "capital" in state.result.reason, "losing your capital loses the mission")

	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "heavy_cavalry"], ["red", "kingsvale", "militia", 1]], 7)
	state.attack([state.units[0]], "kingsvale")
	t.check(state.is_over() and state.result.winner == "blue" and not state.factions.red.alive, "without a mission, the last faction standing wins")


func _test_saves(t) -> void:
	var scenario: Dictionary = (load("res://scripts/session.gd") as GDScript).call("load_scenario", "heartlands")
	var state := GameState.from_scenario(scenario, 3)
	Economy.start_building(state, "greywater", "farm")
	Economy.recruit(state, "greywater", "militia")
	state.move_unit(Helpers.units_of_type(state, "light_cavalry")[0], "northmarch")
	state.factions.aldmere.tax = "high"
	var saved := SaveGame.to_dict(state)
	var loaded := SaveGame.from_dict(JSON.parse_string(JSON.stringify(saved)))
	t.check(_same(SaveGame.to_dict(loaded), saved), "save → JSON → load → save gives the same data")

	# Both copies play on identically, AI and dice included.
	for i in 6:
		for game in [state, loaded]:
			if not game.factions[game.current_faction()].human:
				AI.play_turn(game)
			game.end_faction_turn()
	t.check(_same(SaveGame.to_dict(loaded), SaveGame.to_dict(state)), "a loaded game plays on exactly like the original (6 faction turns, AI and battles)")

	var error := SaveGame.save(state, "3")
	var from_disk := SaveGame.from_dict(SaveGame.load_slot("3"))
	t.check(error == OK and _same(SaveGame.to_dict(from_disk), SaveGame.to_dict(state)), "saving to a slot file and loading it back round-trips")
	t.check(SaveGame.describe("3").contains("turn"), "slots describe what they hold: %s" % SaveGame.describe("3"))
	DirAccess.remove_absolute(SaveGame.path_for("3"))


func _test_ai(t) -> void:
	# The AI attacks when the forecast is good, and takes the region.
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red", "redfield": "red"}, [
		["blue", "greywater", "militia", 6],
		["red", "kingsvale", "heavy_cavalry"], ["red", "kingsvale", "swordsmen"], ["red", "kingsvale", "swordsmen"]], 7)
	state.end_faction_turn()
	AI.play_turn(state)
	t.check(state.owners.greywater == "red", "the AI attacks a weak neighbour and takes it")

	# It doesn't throw units at a fortress.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [
		["blue", "greywater", "spearmen"], ["blue", "greywater", "spearmen"], ["blue", "greywater", "spearmen"], ["blue", "greywater", "spearmen"],
		["red", "kingsvale", "militia"]], 7)
	state.end_faction_turn()
	AI.play_turn(state)
	t.check(state.units_in("kingsvale").size() == 1 and state.owners.greywater == "blue", "the AI won't attack when the forecast is bad")

	# Damaged units pull back.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red", "redfield": "red"}, [
		["blue", "greywater", "swordsmen"], ["blue", "greywater", "swordsmen"], ["blue", "greywater", "heavy_cavalry"],
		["red", "kingsvale", "spearmen", 3], ["red", "kingsvale", "spearmen"]], 7)
	state.end_faction_turn()
	var hurt: Unit = state.units[3]
	AI.play_turn(state)
	t.check(hurt.province == "redfield" or not state.units.has(hurt), "a badly hurt unit pulls back from the front")

	# It recruits units that counter what it sees.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [
		["blue", "greywater", "heavy_cavalry"], ["blue", "greywater", "heavy_cavalry"]], 7,
		{"buildings": {"kingsvale": {"barracks": 1}}, "resources": {"red": {"gold": 500, "wood": 200, "manpower": 200}}})
	state.end_faction_turn()
	AI.play_turn(state)
	t.check("spearmen" in state.provinces.kingsvale.recruits, "facing cavalry, the AI recruits spearmen %s" % [state.provinces.kingsvale.recruits])

	# A whole game with no humans: it must finish with a winner, quickly, without errors.
	var scenario: Dictionary = (load("res://scripts/session.gd") as GDScript).call("load_scenario", "heartlands")
	scenario.erase("mission")
	for faction in scenario.factions:
		faction.human = false
	var game := GameState.from_scenario(scenario, 11)
	var slowest_round := 0
	var started := Time.get_ticks_msec()
	while not game.is_over() and game.turn <= 200:
		var round_start := Time.get_ticks_msec()
		for i in game.living_factions().size():
			if game.is_over():
				break
			AI.play_turn(game)
			game.end_faction_turn()
		slowest_round = maxi(slowest_round, Time.get_ticks_msec() - round_start)
	t.check(game.is_over() and game.result.winner != "",
		"an AI-only Heartlands skirmish ends with a winner: %s on turn %d (%d ms)" % [game.result.get("winner", "nobody"), game.turn, Time.get_ticks_msec() - started])
	t.check(slowest_round < 2000, "every round of AI turns takes under 2 s (slowest %d ms)" % slowest_round)


func _same(a, b) -> bool:
	return JSON.stringify(a, "", true) == JSON.stringify(b, "", true)
