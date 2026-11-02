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
	t.check(Rules.civilizations.keys() == ["norse", "anglish", "frankish", "crusader", "byzantine", "saracen"], "six civilizations %s" % [Rules.civilizations.keys()])
	var open := Rules.civilizations.keys().filter(func(c): return Rules.civilization(c).unlock_after_campaigns == 0)
	t.check(open == ["norse", "anglish", "frankish", "crusader"], "Norse, Anglish, Frankish and the Crusader Orders are open from the start")
	t.check(Rules.civilization("byzantine").unlock_after_campaigns == 1 and Rules.civilization("saracen").unlock_after_campaigns == 2,
		"Byzantine unlocks after one campaign, Saracen after two")
	t.check(Rules.units.size() == 21, "21 unit types in all (%d)" % Rules.units.size())
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
		var attackers: Array[Troop] = []
		for i in 3:
			attackers.append(Troop.new("berserker", 20))
		var defenders: Array[Troop] = []
		for i in 4:
			defenders.append(Troop.new("heavy_cavalry", 20))
		var battle := Battle.new(Battle.Force.new("a", true, attackers), Battle.Force.new("d", false, defenders), Rules.terrains.plains, false, s)
		battle.resolve()
		never_routed = never_routed and not battle.attacker.routed
		fought_on = fought_on or battle.attacker.morale <= Battle.ROUT_MORALE
	t.check(never_routed and fought_on, "berserkers never rout, even with their morale broken")
	var mixed: Array[Troop] = [Troop.new("berserker", 20), Troop.new("militia", 20)]
	t.check(not Battle.Force.new("a", true, mixed).all_berserkers(), "a mixed force can still rout")

	# Longbowmen shoot 2 regions away; ordinary archers don't.
	var state := Helpers.game({"greywater": "blue", "ashford": "blue", "redfield": "red"}, [
		["blue", "greywater", "longbowman"], ["blue", "ashford", "archers"], ["red", "redfield", "militia"]], 7, {"blue_civ": "anglish"})
	var longbow: Unit = state.unit_in("greywater")
	t.check(state.map.distance("greywater", "redfield") == 2, "Redfield is 2 regions from Greywater")
	t.check(Orders.problem(state, longbow, "attack", "redfield") == "" and Orders.problem(state, state.unit_in("ashford"), "attack", "redfield") == "out of range",
		"longbowmen reach 2 regions, archers only 1")
	t.check(Orders.reachable(state, longbow).get("redfield") == "attack", "the target 2 regions away lights up red")
	Helpers.order(state, longbow, "attack", "redfield")
	var events := Helpers.resolve_faction(state, "blue")
	t.check(Helpers.events_of(events, "volley").size() == 1 and longbow.province == "greywater" and state.owners.redfield == "red",
		"the longbow volley flies 2 regions and takes nothing")

	t.check(Rules.unit("knight").charge_bonus == 1.25, "knights charge at +25%")


func _test_bonuses(t) -> void:
	# Norse: sea-wolves attack coastal regions 15% harder (the old coastal raid is gone: sea routes are for everyone).
	var state := Helpers.game({"northmarch": "blue", "greywater": "red"}, [["blue", "northmarch", "berserker"], ["red", "greywater", "militia"]], 7, {"blue_civ": "norse"})
	var raider: Troop = state.unit_in("northmarch").troops[0]
	state.prepare_for_battle(raider, "blue", false, "greywater")
	t.check(state.map.is_coastal("greywater") and is_equal_approx(raider.attack_mod, 1.15), "Norse attacks on a coastal region get +15%")
	state.prepare_for_battle(raider, "blue", false, "kingsvale")
	t.check(not state.map.is_coastal("kingsvale") and raider.attack_mod == 1.0, "but not inland")

	# Anglish: +15% defense at home.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "yeoman"], ["blue", "kingsvale", "yeoman"]], 7, {"blue_civ": "anglish"})
	state.prepare_for_battle(state.units[0].troops[0], "blue", true, "greywater")
	state.prepare_for_battle(state.units[1].troops[0], "blue", true, "kingsvale")
	t.check(is_equal_approx(state.units[0].troops[0].defense_mod, 1.15) and state.units[1].troops[0].defense_mod == 1.0, "Anglish units defend 15% better in their own regions")

	# Frankish: cheaper cavalry.
	state = Helpers.game({"greywater": "blue"}, [], 7, {"blue_civ": "frankish", "red_civ": "norse"})
	t.check(Economy.unit_cost(state, "blue", Rules.unit("knight")).gold == 208.0 and Economy.unit_cost(state, "red", Rules.unit("light_cavalry")).gold == 110.0,
		"Frankish cavalry costs 20% less (knight 260 → 208)")

	# Byzantine: +25% from markets.
	state = Helpers.game({"greywater": "blue", "eastwold": "red"}, [], 7,
		{"blue_civ": "byzantine", "buildings": {"greywater": {"market": 2}, "eastwold": {"market": 2}}})
	t.check(Economy.region_income(state, "greywater") == 30.0 and Economy.region_income(state, "eastwold") == 26.0, "Byzantine markets earn 25% more (20 vs 16)")

	# Saracen: cheaper reinforcements.
	state = Helpers.game({"ashford": "blue", "kingsvale": "red"}, [], 7, {"blue_civ": "saracen", "red_civ": "norse"})
	t.check(is_equal_approx(Economy.soldier_price(state, "blue", Rules.unit("spearmen")), 7.0 * 0.85)
		and is_equal_approx(Economy.soldier_price(state, "red", Rules.unit("spearmen")), 7.0), "Saracen reinforcements cost 15% less")


func _test_campaigns(t) -> void:
	var campaigns := Campaigns.all()
	t.check(campaigns.map(func(c): return c.civ) == ["norse", "anglish", "frankish", "crusader", "byzantine", "saracen"], "one campaign per civilization")
	var maps := {}
	for campaign in campaigns:
		t.check(campaign.missions.size() >= 3, "%s has %d missions" % [campaign.name, campaign.missions.size()])
		for i in campaign.missions.size():
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
	t.check(maps.size() == campaigns.size(), "each campaign has its own map %s" % [maps.keys()])

	# Every mission can be played through by the AI on both sides without errors.
	var crashed := []
	for campaign in campaigns:
		for i in campaign.missions.size():
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
	for i in range(1, Campaigns.get_campaign("norse").missions.size()):
		Progress.record("norse", i, 3 if i == 1 else 1)
	t.check(Progress.campaign_finished("norse") and Progress.civilization_unlocked("byzantine") and not Progress.civilization_unlocked("saracen"),
		"finishing a campaign unlocks Byzantine")
	for i in Campaigns.get_campaign("anglish").missions.size():
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
			ok = ok and state.owners[state.capitals[faction]] == faction and state.units_of(faction).size() >= 2
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
