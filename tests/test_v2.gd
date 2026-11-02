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
	var state := Helpers.game({"greywater": "blue", "ashford": "blue", "kingsvale": "red"}, [
		["blue", "greywater", "swordsmen"], ["blue", "ashford", "catapult"], ["red", "kingsvale", "spearmen"]], 7,
		{"buildings": {"kingsvale": {"walls": 2}}})
	var swords: Unit = state.unit_in("greywater")
	var catapult: Unit = state.unit_in("ashford")
	var defender: Unit = state.unit_in("kingsvale")
	t.check(Sieges.wall_bonus(state, "kingsvale", [swords] as Array[Unit]) == 1.0, "stone walls: defenders take half damage (bonus +100%)")
	t.check(Sieges.wall_bonus(state, "kingsvale", [swords, catapult] as Array[Unit]) == 0.75, "each attacking catapult cuts the wall bonus by 25 points")
	t.check(Sieges.duration(state, "kingsvale", "blue") == 4, "stone walls hold out 4 turns")
	t.check(Orders.problem(state, catapult, "besiege", "kingsvale") != "", "catapults alone can't besiege")
	t.check(Orders.problem(state, swords, "besiege", "redfield") == "no walls to besiege", "only walled regions can be besieged")
	t.check(Helpers.order(state, swords, "besiege", "kingsvale") == "", "a melee unit next to the walls can besiege them")
	var hp_before: float = defender.hp
	for i in 4:
		Helpers.resolve(state)
	t.check(Sieges.breached(state, "kingsvale") and state.provinces.kingsvale.siege_turns == 4, "after 4 turns next to the walls they are breached")
	t.check(defender.hp < hp_before, "breached walls starve the defenders")
	t.check(Sieges.wall_bonus(state, "kingsvale", [swords] as Array[Unit]) == 0.0, "breached walls give no bonus against the besieger")
	Helpers.order(state, swords, "move", "northmarch")
	Helpers.resolve(state)
	t.check(state.provinces.kingsvale.siege_faction == "", "the siege is lifted when the besiegers leave")

	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "swordsmen"]], 7, {"buildings": {"kingsvale": {"walls": 3}}})
	Helpers.order(state, state.unit_in("greywater"), "move", "kingsvale")
	Helpers.resolve(state)
	t.check(state.owners.kingsvale == "blue", "empty walls are taken by walking in")


func _test_missions(t) -> void:
	t.check(Mission.stars_for(8, 8) == 3 and Mission.stars_for(11, 8) == 2 and Mission.stars_for(12, 8) == 1 and Mission.stars_for(15, 8) == 1,
		"stars: at par 3, under 1.5 × par 2, otherwise 1")
	var mission := {"player": "blue", "par": 4, "objectives": [{"type": "capture", "regions": ["kingsvale"]}]}
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red", "eastwold": "red"},
		[["blue", "greywater", "swordsmen"], ["red", "eastwold", "militia"]], 7, {"capitals": {"blue": "greywater"}})
	state.mission = mission.duplicate(true)
	t.check(not state.is_over() and not Mission.objectives(state)[0].done, "the objective starts open")
	Helpers.order(state, state.unit_in("greywater"), "move", "kingsvale")
	Helpers.resolve(state)
	t.check(state.is_over() and state.result.result == "won" and state.result.stars == 3, "capturing the target in turn 1 (par 4) wins with 3 stars")

	state = Helpers.game({"greywater": "blue", "kingsvale": "red", "eastwold": "red"},
		[["blue", "greywater", "militia"], ["red", "kingsvale", "militia"]], 7, {"capitals": {"blue": "greywater"}})
	state.mission = mission.duplicate(true)
	for i in 7:
		Helpers.resolve(state)
	t.check(not state.is_over() and state.turn == 8 and Mission.hard_limit(state) == 8, "the hard limit is par × 2: turn 8 of 8 is still playable")
	Helpers.resolve(state)
	t.check(state.is_over() and state.result.result == "lost" and "Out of time" in state.result.reason, "passing the hard limit loses the mission")

	state = Helpers.game({"greywater": "blue", "kingsvale": "blue", "eastwold": "red"}, [["red", "eastwold", "militia"]], 7)
	state.mission = {"player": "blue", "par": 10, "objectives": [{"type": "hold", "region": "kingsvale", "turns": 2}]}
	Helpers.resolve(state)
	t.check(Mission.objectives(state)[0].text.ends_with("(1 so far)"), "holding a region counts the turns")
	Helpers.resolve(state)
	t.check(state.is_over() and state.result.result == "won", "holding it for 2 turns wins")

	state = Helpers.game({"greywater": "blue", "ashford": "blue", "kingsvale": "red"},
		[["blue", "ashford", "militia"], ["red", "kingsvale", "swordsmen"]], 7, {"capitals": {"blue": "greywater"}})
	state.mission = {"player": "blue", "par": 10, "objectives": [{"type": "destroy", "faction": "red"}]}
	Helpers.order(state, state.unit_in("kingsvale"), "move", "greywater")
	Helpers.resolve(state)
	t.check(state.is_over() and state.result.result == "lost" and "capital" in state.result.reason, "losing your capital loses the mission")

	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "heavy_cavalry"], ["red", "kingsvale", "militia", 1]], 7,
		{"conquest": true})
	Helpers.order(state, state.unit_in("greywater"), "attack", "kingsvale")
	Helpers.resolve(state)
	t.check(state.is_over() and state.result.winner == "blue" and not state.factions.red.alive, "without a mission, the last faction standing wins")


func _test_saves(t) -> void:
	var scenario: Dictionary = (load("res://scripts/session.gd") as GDScript).call("load_scenario", "heartlands")
	var state := GameState.from_scenario(scenario, 3)
	Economy.start_building(state, "greywater", "market")
	Economy.buy(state, "ashford", Economy.bundle_of(state, state.owners.ashford, "crossbowmen"))
	Orders.give(state, state.unit_in("northmarch"), "move", "ashford")
	Orders.give(state, state.unit_in("ashford"), "attack", "kingsvale", {"soldiers": 12})
	var saved := SaveGame.to_dict(state)
	var loaded := SaveGame.from_dict(JSON.parse_string(JSON.stringify(saved)))
	t.check(_same(SaveGame.to_dict(loaded), saved), "save → JSON → load → save gives the same data, planned orders included")

	# Both copies play on identically, AI and dice included.
	for i in 3 * state.turn_order.size():
		for game in [state, loaded]:
			if not game.factions[game.current_faction()].human:
				AI.play_turn(game)
			game.end_faction_turn()
	t.check(_same(SaveGame.to_dict(loaded), SaveGame.to_dict(state)), "a loaded game plays on exactly like the original (3 turns, AI and battles)")

	var error := SaveGame.save(state, "3")
	var from_disk := SaveGame.from_dict(SaveGame.load_slot("3"))
	t.check(error == OK and _same(SaveGame.to_dict(from_disk), SaveGame.to_dict(state)), "saving to a slot file and loading it back round-trips")
	t.check(SaveGame.describe("3").contains("turn"), "slots describe what they hold: %s" % SaveGame.describe("3"))
	DirAccess.remove_absolute(SaveGame.path_for("3"))


func _test_ai(t) -> void:
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red", "redfield": "red"}, [
		["blue", "greywater", "militia", 6], ["red", "kingsvale", "heavy_cavalry"]], 7)
	Helpers.plan_as(state, "red")
	AI.play_turn(state)
	t.check(state.orders.get(state.unit_in("kingsvale"), [{"steps": [{}]}])[0].steps[0].get("type") == "attack", "the AI plans an attack on a weak neighbour")
	Helpers.resolve(state)
	t.check(state.owners.greywater == "red", "and takes it when the turn resolves")

	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "spearmen"], ["red", "kingsvale", "light_cavalry", 8]], 7)
	Helpers.plan_as(state, "red")
	AI.play_turn(state)
	var orders: Array = state.orders.get(state.unit_in("kingsvale"), [])
	t.check(orders.all(func(o): return o.steps[0].type != "attack"), "the AI won't attack when the forecast is bad")

	state = Helpers.game({"greywater": "blue", "kingsvale": "red", "redfield": "red"}, [
		["blue", "greywater", "heavy_cavalry"], ["red", "kingsvale", "spearmen", 3]], 7, {"resources": {"red": {"gold": 0}}})
	Helpers.plan_as(state, "red")
	var hurt: Unit = state.unit_in("kingsvale")
	AI.play_turn(state)
	Helpers.resolve(state)
	t.check(hurt.province == "redfield" or not state.units.has(hurt), "a small army pulls back from the front")

	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "heavy_cavalry"]], 7,
		{"buildings": {"kingsvale": {"barracks": 1}}, "resources": {"red": {"gold": 500, "wood": 200, "manpower": 200}}})
	Helpers.plan_as(state, "red")
	AI.play_turn(state)
	t.check(state.provinces.kingsvale.recruits.any(func(b): return b.type in ["spearmen", "pikemen"]), "facing cavalry, the AI buys spears %s" % [state.provinces.kingsvale.recruits])

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
		var turn := game.turn
		while game.turn == turn and not game.is_over():
			AI.play_turn(game)
			game.end_faction_turn()
		slowest_round = maxi(slowest_round, Time.get_ticks_msec() - round_start)
	t.check(game.is_over() and game.result.winner != "",
		"an AI-only Heartlands skirmish ends with a winner: %s on turn %d (%d ms)" % [game.result.get("winner", "nobody"), game.turn, Time.get_ticks_msec() - started])
	t.check(slowest_round < 2000, "a whole turn of AI planning and resolution takes under 2 s (slowest %d ms)" % slowest_round)


func _same(a, b) -> bool:
	return JSON.stringify(a, "", true) == JSON.stringify(b, "", true)
