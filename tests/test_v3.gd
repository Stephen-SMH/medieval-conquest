extends RefCounted
## V3: civilizations and their special units and bonuses, campaigns and
## missions, unlocks, and skirmish.

const Helpers := preload("res://tests/helpers.gd")


func run(t) -> void:
	_test_civilizations(t)
	_test_special_units(t)
	_test_bonuses(t)
	_test_campaigns(t)
	_test_progress(t)
	_test_skirmish(t)


func _test_civilizations(t) -> void:
	Rules.ensure_loaded()
	t.check(Rules.civilizations.keys() == ["norse", "anglish", "frankish", "byzantine", "saracen"], "five civilizations %s" % [Rules.civilizations.keys()])
	var open := Rules.civilizations.keys().filter(func(c): return Rules.civilization(c).unlock_after_campaigns == 0)
	t.check(open == ["norse", "anglish", "frankish"], "Norse, Anglish and Frankish are open from the start")
	t.check(Rules.civilization("byzantine").unlock_after_campaigns == 1 and Rules.civilization("saracen").unlock_after_campaigns == 2,
		"Byzantine unlocks after one campaign, Saracen after two")
	t.check(Rules.units.size() == 18, "18 unit types in all (%d)" % Rules.units.size())
	var specials_ok := true
	for civ_id in Rules.civilizations:
		for unit_id in Rules.civilization(civ_id).special_units:
			specials_ok = specials_ok and Rules.unit(unit_id).civilization == civ_id
	t.check(specials_ok, "every civilization's special units belong to it")


func _test_special_units(t) -> void:
	# Berserkers never rout: they fight to the end or hold.
	var never_routed := true
	var fought_on := false
	for s in 20:
		var attackers: Array[Unit] = []
		for i in 3:
			attackers.append(Unit.new("berserker", "a", "x"))
		var defenders: Array[Unit] = []
		for i in 4:
			defenders.append(Unit.new("heavy_cavalry", "d", "x"))
		var battle := Battle.new(Battle.Force.new("a", true, attackers), Battle.Force.new("d", false, defenders), Rules.terrains.plains, false, s)
		battle.resolve()
		never_routed = never_routed and not battle.attacker.routed
		fought_on = fought_on or battle.attacker.morale <= Battle.ROUT_MORALE
	t.check(never_routed and fought_on, "berserkers never rout, even with their morale broken")
	var mixed: Array[Unit] = [Unit.new("berserker", "a", "x"), Unit.new("militia", "a", "x")]
	t.check(not Battle.Force.new("a", true, mixed).all_berserkers(), "a mixed force can still rout")

	# Longbowmen shoot 2 regions away; ordinary archers don't.
	var state := Helpers.game({"greywater": "blue", "redfield": "red"}, [
		["blue", "greywater", "longbowman"], ["blue", "greywater", "archers"], ["red", "redfield", "militia"]], 7, {"blue_civ": "anglish"})
	t.check(state.map.distance("greywater", "redfield") == 2, "Redfield is 2 regions from Greywater")
	t.check(state.attack_problem(state.units[0], "redfield") == "" and state.attack_problem(state.units[1], "redfield") == "out of range",
		"longbowmen reach 2 regions, archers only 1")
	t.check(state.reachable([state.units[0]]).get("redfield") == "attack", "the target 2 regions away lights up red")
	var result := state.attack([state.units[0]], "redfield")
	t.check(result.battle.ranged_only() and state.units[0].province == "greywater" and state.owners.redfield == "red",
		"the longbow volley flies 2 regions and takes nothing")

	# Mamluks move and then shoot.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "ashford", "mamluk"], ["red", "kingsvale", "militia"]], 7, {"blue_civ": "saracen"})
	state.move_unit(state.units[0], "greywater")
	t.check(state.attack_problem(state.units[0], "kingsvale") == "", "mamluks can shoot after moving")

	t.check(Rules.unit("knight").charge_bonus == 1.25, "knights charge at +25%")


func _test_bonuses(t) -> void:
	# Norse: a free move between coastal regions.
	var state := Helpers.game({"northmarch": "blue"}, [["blue", "northmarch", "berserker"], ["red", "eastwold", "militia"]], 7, {"blue_civ": "norse"})
	var raider: Unit = state.units[0]
	t.check(state.map.is_coastal("northmarch") and state.map.is_coastal("greywater") and state.map.is_coastal("highcrag"), "the north coast is coastal")
	state.move_unit(raider, "greywater")
	t.check(raider.province == "greywater" and raider.move_points_left == 1, "Norse units sail along the coast without spending a move")
	state.move_unit(raider, "highcrag")
	t.check(raider.province == "highcrag" and raider.move_points_left == 0, "then use their normal move")
	t.check(state.undo_last_move() and state.undo_last_move() and raider.province == "northmarch" and raider.coastal_moves == 1,
		"undo gives the coastal move back")
	state = Helpers.game({"northmarch": "blue"}, [["blue", "northmarch", "spearmen"]], 7, {"blue_civ": "anglish"})
	state.move_unit(state.units[0], "greywater")
	t.check(state.units[0].move_points_left == 0, "other civilizations get no coastal move")

	# Anglish: +15% defense at home.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "yeoman"], ["blue", "kingsvale", "yeoman"]], 7, {"blue_civ": "anglish"})
	state.prepare_for_battle(state.units[0], true, "greywater")
	state.prepare_for_battle(state.units[1], true, "kingsvale")
	t.check(is_equal_approx(state.units[0].defense_mod, 1.15) and state.units[1].defense_mod == 1.0, "Anglish units defend 15% better in their own regions")

	# Frankish: cheaper cavalry.
	state = Helpers.game({"greywater": "blue"}, [], 7, {"blue_civ": "frankish", "red_civ": "norse"})
	t.check(Economy.unit_cost(state, "blue", Rules.unit("knight")).gold == 160.0 and Economy.unit_cost(state, "red", Rules.unit("light_cavalry")).gold == 110.0,
		"Frankish cavalry costs 20% less (knight 200 → 160)")

	# Byzantine: +25% from markets.
	state = Helpers.game({"greywater": "blue", "eastwold": "red"}, [], 7,
		{"blue_civ": "byzantine", "buildings": {"greywater": {"market": 2}, "eastwold": {"market": 2}}})
	var markets := func(faction: String) -> float:
		return Economy.breakdown(state, faction).gold.filter(func(l): return l[0] == "Markets")[0][1]
	t.check(is_equal_approx(markets.call("blue"), 20.0) and is_equal_approx(markets.call("red"), 16.0), "Byzantine markets earn 25% more")

	# Saracen: no winter attrition.
	state = Helpers.game({"greywater": "blue"}, [["blue", "kingsvale", "ghazi"]], 7, {"blue_civ": "saracen"})
	state.turn = 4
	state.units[0].moved = true
	state.end_faction_turn()
	t.check(state.units[0].soldiers() == 20, "Saracen units don't suffer winter attrition")


func _test_campaigns(t) -> void:
	var campaigns := Campaigns.all()
	t.check(campaigns.map(func(c): return c.civ) == ["norse", "anglish", "frankish"], "three campaigns, one per open civilization")
	var maps := {}
	for campaign in campaigns:
		t.check(campaign.missions.size() == 3, "%s has 3 missions" % campaign.name)
		for i in 3:
			var scenario := Campaigns.mission(campaign.id, i)
			maps[scenario.map] = true
			var map := MapData.load_map(scenario.map)
			var state := GameState.from_scenario(scenario, 1)
			var problems := []
			if map.province_order.size() < 12 or map.province_order.size() > 20:
				problems.append("map has %d regions" % map.province_order.size())
			for region in map.province_order:
				for faction in state.factions:
					if state.space_in(region, faction) < 0:
						problems.append("over-full stack in " + region)
			for unit in state.units:
				var civ_ok: bool = unit.type().civilization == "" or (state.factions.has(unit.owner) and state.factions[unit.owner].civ == unit.type().civilization)
				if not civ_ok:
					problems.append("%s can't have %s" % [unit.owner, unit.type_id])
			for objective in scenario.mission.objectives:
				for region in objective.get("regions", []) + ([objective.region] if objective.has("region") else []):
					if not map.provinces.has(region):
						problems.append("objective names unknown region " + region)
			if Mission.player(state) != state.viewer() or not state.factions[Mission.player(state)].human:
				problems.append("the player faction isn't the human one")
			if Mission.par(state) <= 0 or scenario.mission.briefing == "":
				problems.append("missing par or briefing")
			t.check(problems.is_empty(), "%s mission %d \"%s\" is valid %s" % [campaign.civ, i + 1, scenario.name, problems])
	t.check(maps.size() == 3, "each campaign has its own map %s" % [maps.keys()])

	# Every mission can be played through by the AI on both sides without errors.
	var crashed := []
	for campaign in campaigns:
		for i in 3:
			var state := GameState.from_scenario(Campaigns.mission(campaign.id, i), 5)
			for step in 12 * state.turn_order.size():
				if state.is_over():
					break
				AI.play_turn(state)
				state.end_faction_turn()
			if state.units.is_empty():
				crashed.append(campaign.id + str(i))
	t.check(crashed.is_empty(), "every mission plays 12 AI-driven turns cleanly %s" % [crashed])


func _test_progress(t) -> void:
	Progress.path = "user://test_progress.json"
	Progress.reset()
	t.check(Progress.mission_unlocked("norse", 0) and not Progress.mission_unlocked("norse", 1), "only the first mission is open at first")
	t.check(not Progress.civilization_unlocked("byzantine"), "Byzantine starts locked")
	Progress.record("norse", 0, 2)
	Progress.record("norse", 0, 1)
	t.check(Progress.stars("norse", 0) == 2 and Progress.mission_unlocked("norse", 1), "finishing a mission keeps the best stars and opens the next")
	Progress.record("norse", 1, 3)
	Progress.record("norse", 2, 1)
	t.check(Progress.campaign_finished("norse") and Progress.civilization_unlocked("byzantine") and not Progress.civilization_unlocked("saracen"),
		"finishing a campaign unlocks Byzantine")
	for i in 3:
		Progress.record("anglish", i, 1)
	t.check(Progress.civilization_unlocked("saracen"), "finishing two campaigns unlocks Saracen")
	DirAccess.remove_absolute(Progress.path)
	Progress.path = Progress.PATH


func _test_skirmish(t) -> void:
	for map_id in MapData.list_maps():
		var scenario := Skirmish.build(map_id, [{"civ": "norse", "human": true}, {"civ": "anglish"}, {"civ": "frankish"}, {"civ": "norse"}], "hard", 3)
		var state := GameState.from_scenario(scenario, 3)
		var ok: bool = state.turn_order.size() == 4 and state.factions[state.turn_order[0]].human and state.turn_order[3] == "norse_2"
		for faction in state.turn_order:
			ok = ok and state.owners[state.capitals[faction]] == faction and state.units_of(faction).size() == 4
		t.check(ok, "skirmish on %s: 4 factions with capitals and armies, repeated civilizations get their own id" % map_id)

	var players := [{"civ": "norse"}, {"civ": "anglish"}, {"civ": "frankish"}, {"civ": "byzantine"}]
	var game := GameState.from_scenario(Skirmish.build("fjordmark", players, "hard", 9), 9)
	var started := Time.get_ticks_msec()
	while not game.is_over() and game.turn <= 250:
		AI.play_turn(game)
		game.end_faction_turn()
	t.check(game.is_over() and game.result.winner != "",
		"an AI-only 4-player skirmish on the Fjordmark ends with a winner: %s on turn %d (%d ms)" % [
			game.faction_name(game.result.get("winner", "")), game.turn, Time.get_ticks_msec() - started])
