extends RefCounted
## V2: sieges, missions (now in the S&T style, H), save/load, and the AI (including a full
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


## Missions as in S&T (PRD H): primary and additional objectives, defeat
## conditions, crowns, points and scripted events.
func _test_missions(t) -> void:
	t.check(Mission.crown_for(8, [8, 10, 12]) == 3 and Mission.crown_for(10, [8, 10, 12]) == 2 and Mission.crown_for(12, [8, 10, 12]) == 1
		and Mission.crown_for(13, [8, 10, 12]) == 0, "crowns: gold by turn 8, silver by 10, bronze by 12, then none")
	var mission := {"player": "blue", "primary": [{"type": "capture", "regions": ["kingsvale"]}],
		"additional": [{"type": "capture", "regions": ["eastwold"], "points": 200}, {"type": "hold", "region": "greywater", "turns": 5}],
		"defeat": [{"type": "time", "turns": 8}, {"type": "lose_region", "region": "greywater"}], "crowns": [4, 6, 8]}
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red", "eastwold": "red"},
		[["blue", "greywater", "swordsmen"], ["red", "eastwold", "militia"]], 7, {"capitals": {"blue": "greywater"}})
	state.mission = mission.duplicate(true)
	t.check(not state.is_over() and Mission.primary_left(state) == 1 and Mission.objectives(state).size() == 3
		and Mission.objectives(state)[0].primary and not Mission.objectives(state)[1].primary, "the primary objective comes first, then the additional ones")
	t.check(Mission.crown_now(state) == {"crown": 3, "turns_left": 4}, "turn 1: the gold crown, 4 turns left")
	t.check(Mission.defeats(state) == ["Fail to complete the main objective in 8 turns", "Lose Greywater"], "the defeat conditions in words")
	Helpers.order(state, state.unit_in("greywater"), "move", "kingsvale")
	Helpers.resolve(state)
	var result := state.result
	t.check(state.is_over() and result.result == "won" and result.stars == 3 and result.turns == 1, "capturing the target in turn 1 wins a gold crown")
	t.check(result.points == Mission.PRIMARY_POINTS + Mission.CROWN_POINTS[3]
		and result.objectives.map(func(o): return o.done) == [true, false, false], "points for what was done and the crown (%s)" % [result])

	state = Helpers.game({"greywater": "blue", "kingsvale": "red", "eastwold": "red"},
		[["blue", "greywater", "militia"], ["red", "kingsvale", "militia"]], 7, {"capitals": {"blue": "greywater"}})
	state.mission = mission.duplicate(true)
	for i in 4:
		Helpers.resolve(state)
	t.check(Mission.crown_now(state) == {"crown": 2, "turns_left": 2}, "turn 5: the gold crown has gone; silver, 2 turns left")
	for i in 3:
		Helpers.resolve(state)
	t.check(not state.is_over() and state.turn == 8 and Mission.time_limit(state) == 8, "turn 8 of 8 is still playable")
	Helpers.resolve(state)
	t.check(state.is_over() and state.result.result == "lost" and "Out of time" in state.result.reason, "after turn 8 the mission is lost")

	# Additional objectives add points.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red", "eastwold": "red"},
		[["blue", "greywater", "swordsmen"], ["blue", "highcrag", "swordsmen"]], 7, {"capitals": {"blue": "greywater"}})
	state.mission = mission.duplicate(true)
	Helpers.order(state, state.unit_in("greywater"), "move", "kingsvale")
	Helpers.order(state, state.unit_in("highcrag"), "move", "eastwold")
	Helpers.resolve(state)
	t.check(state.result.points == Mission.PRIMARY_POINTS + 200 + Mission.CROWN_POINTS[3],
		"an additional objective done on the way counts (%d points)" % state.result.points)

	state = Helpers.game({"greywater": "blue", "kingsvale": "blue", "eastwold": "red"}, [["red", "eastwold", "militia"]], 7)
	state.mission = {"player": "blue", "primary": [{"type": "hold", "region": "kingsvale", "turns": 2}], "crowns": [10, 12, 14]}
	Helpers.resolve(state)
	t.check(Mission.objectives(state)[0].text.ends_with("(1 so far)"), "holding a region counts the turns")
	Helpers.resolve(state)
	t.check(state.is_over() and state.result.result == "won", "holding it for 2 turns wins")

	state = Helpers.game({"greywater": "blue", "ashford": "blue", "kingsvale": "red"},
		[["blue", "ashford", "militia"], ["red", "kingsvale", "swordsmen"]], 7, {"capitals": {"blue": "greywater"}})
	state.mission = {"player": "blue", "primary": [{"type": "destroy", "faction": "red"}], "defeat": [{"type": "lose_region", "region": "greywater", "before": 5}]}
	Helpers.order(state, state.unit_in("kingsvale"), "move", "greywater")
	Helpers.resolve(state)
	t.check(state.is_over() and state.result.result == "lost" and state.result.reason == "Greywater has fallen.", "losing Greywater before turn 5 loses")

	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "militia", 2], ["red", "kingsvale", "heavy_cavalry"]], 7)
	state.mission = {"player": "blue", "primary": [{"type": "destroy", "faction": "red"}], "defeat": [{"type": "lose_army"}]}
	Helpers.order(state, state.unit_in("greywater"), "attack", "kingsvale")
	Helpers.resolve(state)
	t.check(state.is_over() and state.result.result == "lost" and state.result.reason == "All your troops are lost.", "losing every soldier loses")

	# Scripted events: reinforcements for a faction, with a note.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["red", "kingsvale", "militia", 5]], 7)
	state.mission = {"player": "blue", "primary": [{"type": "destroy", "faction": "red"}],
		"events": [{"turn": 2, "type": "reinforcements", "faction": "red", "region": "kingsvale", "unit": "spearmen", "soldiers": 8},
			{"turn": 2, "type": "message", "text": "Scouts report movement in the east."}]}
	var events := Helpers.resolve(state)
	t.check(state.unit_in("kingsvale").composition() == {"militia": 5, "spearmen": 8}, "on turn 2 the enemy army in Kingsvale grows by 8 spearmen")
	t.check(Helpers.events_of(events, "mission_note").map(func(e): return e.text) == [
		"Enemy reinforcements arrived in the province of Kingsvale: Spearmen – 8", "Scouts report movement in the east."]
		and state.mission_log.size() == 2, "each event leaves a note (%s)" % [state.mission_log])

	# Surrender (PRD K): a mission is lost; in hotseat the realm leaves the war.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "spearmen"]], 7)
	state.mission = {"player": "blue", "primary": [{"type": "destroy", "faction": "red"}]}
	Mission.surrender(state, "blue")
	t.check(state.is_over() and state.result.result == "lost" and state.result.reason == "You surrendered.", "surrendering loses the mission")
	var hotseat := GameState.from_scenario(Skirmish.build("heartlands", [{"civ": "norse", "human": true}, {"civ": "anglish", "human": true},
		{"civ": "frankish", "human": true}], "normal", 2), 2)
	var quitter := hotseat.current_faction()
	Mission.surrender(hotseat, quitter)
	t.check(not hotseat.is_over() and not hotseat.factions[quitter].alive and hotseat.units_of(quitter).is_empty()
		and not hotseat.owners.values().has(quitter), "in hotseat the realm that surrenders leaves; the others play on")

	# Older missions still load.
	var old := Mission.normalized({"player": "blue", "par": 8, "objectives": [{"type": "conquest"}]}, {"blue": "greywater"})
	t.check(old.primary == [{"type": "conquest"}] and old.crowns == [8.0, 11.0, 16.0]
		and old.defeat == [{"type": "time", "turns": 16.0}, {"type": "lose_region", "region": "greywater"}], "an older mission converts (%s)" % [old])

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
	var attacks := Helpers.events_of(AI.play_turn(state), "battle")
	t.check(attacks.size() == 1 and attacks[0].province == "greywater", "the AI attacks a weak neighbour first, with the \"!\"")
	Helpers.resolve(state)
	t.check(state.owners.greywater == "red", "and takes it")

	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "spearmen"], ["red", "kingsvale", "light_cavalry", 8]], 7)
	Helpers.plan_as(state, "red")
	var fought := Helpers.events_of(AI.play_turn(state), "battle")
	var orders: Array = state.orders.get(state.unit_in("kingsvale"), [])
	t.check(fought.is_empty() and orders.all(func(o): return o.steps[0].type != "attack"), "the AI won't attack when the forecast is bad")

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
