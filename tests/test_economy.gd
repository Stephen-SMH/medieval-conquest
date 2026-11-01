extends RefCounted
## M4: resources, seasons, food and supply, buildings, recruiting, storage, taxes and revolts.


func run(t) -> void:
	var map := MapData.load_default()
	var state := GameState.new_game(map, 5)
	var aldmere: FactionState = state.factions["aldmere"]

	t.check(state.factions.size() == 4 and not state.factions.has("rebels"), "the 4 playable factions have stockpiles; rebels don't")
	t.check(aldmere.resources.gold == Economy.START_RESOURCES.gold, "factions start with %d gold" % Economy.START_RESOURCES.gold)

	# The bar's numbers are exactly what the end of the turn applies.
	var before := aldmere.resources.duplicate()
	var change := Economy.deltas(state, "aldmere")
	state.end_turn()
	var matches := true
	for resource in ["gold", "wood", "iron", "manpower"]:
		matches = matches and is_equal_approx(aldmere.resources[resource], before[resource] + change[resource])
	matches = matches and is_equal_approx(aldmere.resources.food, minf(before.food + change.food, Economy.food_cap(state, "aldmere")))
	t.check(matches, "ending the turn applies the shown changes (gold %+d, food %+d)" % [roundi(change.gold), roundi(change.food)])
	var lines := Economy.breakdown(state, "aldmere")
	var labels := []
	for resource in lines:
		for line in lines[resource]:
			labels.append(line[0])
	t.check("Army upkeep" in labels and "Population eats" in labels and "Armies eat" in labels and "Markets" in labels,
		"the breakdown names taxes, markets, farmland, population, armies %s" % [labels])

	# Seasons (FD-2).
	state.turn = 1
	var spring := Economy.province_food(state, "greywater")
	state.turn = 3
	var autumn := Economy.province_food(state, "greywater")
	state.turn = 4
	var winter := Economy.province_food(state, "greywater")
	t.check(is_equal_approx(autumn, spring * 1.5) and is_equal_approx(winter, spring * 0.25),
		"farms grow ×1.5 in autumn and ×0.25 in winter (%d, %d, %d)" % [roundi(spring), roundi(autumn), roundi(winter)])

	_test_food(t, map)
	_test_supply(t, map)
	_test_buildings(t, map)
	_test_recruiting(t, map)
	_test_happiness(t, map)


func _test_food(t, map: MapData) -> void:
	# Starvation (FD-3).
	var state := GameState.new_game(map, 5)
	var faction: FactionState = state.factions["aldmere"]
	state.turn = 4  # Winter.
	var horde := state.add_army("aldmere", "greywater", General.new("Hungry", 0, 0),
		["heavy_cavalry", "heavy_cavalry", "heavy_cavalry", "heavy_cavalry", "heavy_cavalry", "heavy_cavalry"])
	faction.resources.food = 0.0
	var events := state.end_turn()
	t.check(faction.resources.food == 0.0 and is_equal_approx(horde.regiments[0].men, 100.0 * (1.0 - Economy.STARVATION_LOSS)),
		"starvation: food can't go below 0 and armies lose 10% of their men")
	t.check(events.any(func(e): return e.type == "economy" and "Starvation" in e.text), "starvation is reported")

	# Spoilage and granaries (ST-1).
	state = GameState.new_game(map, 5)
	faction = state.factions["aldmere"]
	faction.resources.food = 900.0
	state.end_turn()
	t.check(faction.resources.food == Economy.FOOD_CAP, "food above the %d storage cap spoils" % Economy.FOOD_CAP)
	state.provinces["ashford"].buildings["granary"] = 1
	t.check(Economy.food_cap(state, "aldmere") == Economy.FOOD_CAP + 500.0, "a granary stores 500 more food")
	faction.resources.wood = 5000.0
	state.end_turn()
	t.check(faction.resources.wood == Economy.material_cap(state, "aldmere") and Economy.material_cap(state, "aldmere") == 1500.0,
		"wood is capped at 1,000 + 500 per capital")

	# Unpaid troops desert.
	state = GameState.new_game(map, 5)
	faction = state.factions["aldmere"]
	faction.resources.gold = -1000.0
	var army: Army = state.armies_in("greywater")[0]
	state.end_turn()
	t.check(faction.resources.gold == 0.0 and is_equal_approx(army.regiments[0].men, 100.0 * (1.0 - Economy.DESERTION_LOSS)),
		"without gold to pay them, 5% of every army deserts")


func _test_supply(t, map: MapData) -> void:
	var state := GameState.new_game(map, 5)
	var distance := Economy.distance_from_territory(state, "aldmere")
	t.check(distance.greywater == 0 and distance.kingsvale == 1 and distance.thornwood == 2 and distance.stonehelm == 3,
		"distance from Aldmere's territory: Kingsvale 1, Thornwood 2, Stonehelm 3")
	var near := state.add_army("aldmere", "thornwood", General.new("Near", 0, 0), ["spearmen"])
	var far := state.add_army("aldmere", "stonehelm", General.new("Far", 0, 0), ["spearmen"])
	t.check(Economy.is_supplied(state, near) and not Economy.is_supplied(state, far), "armies within 2 provinces are supplied; beyond that they are not")
	var quartermaster := state.add_army("aldmere", "stonehelm", General.new("Quartermaster", 0, 3), ["spearmen"])
	t.check(Economy.is_supplied(state, quartermaster), "a general with logistics 3 extends the supply range by 1")
	state.armies.erase(quartermaster)

	var supplied_food: float = Economy.deltas(state, "aldmere").food
	state.armies.erase(far)
	t.check(is_equal_approx(Economy.deltas(state, "aldmere").food, supplied_food), "an army out of supply doesn't eat from the stockpile")
	state.armies.append(far)

	var forage_before: float = state.provinces["stonehelm"].forage
	state.end_turn()
	t.check(state.provinces["stonehelm"].forage < forage_before + Economy.land_food(state, "stonehelm") and far.regiments[0].men == 100.0,
		"an army out of supply forages from the province it stands in")
	state.provinces["stonehelm"].forage = 0.0
	state.end_turn()
	t.check(is_equal_approx(far.regiments[0].men, 100.0 * (1.0 - Economy.FORAGE_LOSS)), "when the forage runs out the army loses 5% a turn")

	# Winter attrition (FD-5).
	state = GameState.new_game(map, 5)
	state.armies = state.armies.filter(func(a): return a.owner == "aldmere")
	state.turn = 4
	var home := state.add_army("aldmere", "ashford", General.new("Home", 0, 0), ["spearmen"])
	var abroad := state.add_army("aldmere", "kingsvale", General.new("Abroad", 0, 0), ["spearmen"])
	var peaks := state.add_army("aldmere", "highcrag", General.new("Peaks", 0, 0), ["spearmen"])
	state.end_turn()
	t.check(home.regiments[0].men == 100.0 and is_equal_approx(abroad.regiments[0].men, 95.0) and is_equal_approx(peaks.regiments[0].men, 90.0),
		"winter: no loss at home, 5% abroad, 10% in mountains")


func _test_buildings(t, map: MapData) -> void:
	var state := GameState.new_game(map, 5)
	var faction: FactionState = state.factions["aldmere"]
	faction.resources = {"gold": 2000.0, "food": 300.0, "wood": 500.0, "iron": 200.0, "manpower": 1000.0}
	var food_before := Economy.province_food(state, "greywater")
	t.check(Economy.start_building(state, "greywater", "farm") and faction.resources.gold == 1900.0 and faction.resources.wood == 480.0,
		"upgrading a farm costs 100 gold and 20 wood")
	t.check(Economy.build_problem(state, "greywater", "market", "aldmere").begins_with("already building:"),
		"one building at a time per province")
	state.end_turn()
	t.check(state.provinces["greywater"].level("farm") == 2 and Economy.province_food(state, "greywater") > food_before,
		"after its build time the farm reaches level 2 and grows more food")
	t.check(Economy.build_problem(state, "greywater", "lumber_camp", "aldmere") == "needs forest", "lumber camps need forest")
	t.check(Economy.build_problem(state, "greywater", "mine", "aldmere") == "needs hills or mountains", "mines need hills or mountains")
	t.check(Economy.build_problem(state, "northmarch", "lumber_camp", "aldmere") == "", "a forest province can build a lumber camp")
	t.check(Economy.build_problem(state, "kingsvale", "farm", "aldmere") == "not your province", "you can't build in other factions' provinces")

	state.provinces["ashford"].buildings = {"farm": 1, "market": 1, "granary": 1, "stable": 1}
	t.check(Economy.build_problem(state, "ashford", "barracks", "aldmere") == "no free building slots"
		and Economy.build_problem(state, "ashford", "farm", "aldmere") == "", "4 slots in a province; upgrades don't take a slot")
	t.check(Economy.slots(state, "greywater") == 6, "a capital has 6 slots")
	faction.resources.gold = 10.0
	t.check(Economy.build_problem(state, "ashford", "farm", "aldmere") == "not enough resources", "buildings need the resources")


func _test_recruiting(t, map: MapData) -> void:
	var state := GameState.new_game(map, 5)
	var faction: FactionState = state.factions["aldmere"]
	faction.resources = {"gold": 2000.0, "food": 300.0, "wood": 500.0, "iron": 200.0, "manpower": 1000.0}
	t.check(Economy.recruit_problem(state, "ashford", "spearmen", "aldmere") == "needs: barracks", "spearmen need a barracks")
	t.check(Economy.recruit_problem(state, "greywater", "light_cavalry", "aldmere") == "needs: stable", "cavalry needs a stable")
	t.check(Economy.recruit_problem(state, "ashford", "militia", "aldmere") == "", "militia can be raised anywhere")
	t.check(Economy.recruit(state, "greywater", "spearmen") and faction.resources.gold == 1940.0 and faction.resources.wood == 490.0
		and faction.resources.manpower == 900.0, "a spearmen regiment costs 60 gold, 10 wood and 100 men")
	t.check(Economy.recruit(state, "greywater", "swordsmen") and faction.resources.iron == 185.0, "swordsmen cost iron")
	t.check(Economy.recruit_problem(state, "greywater", "militia", "aldmere").ends_with("a turn at most"), "2 recruits per province per turn")
	var armies_before := state.armies_in("greywater").size()
	state.end_turn()
	var garrison: Array = state.armies_in("greywater").filter(func(a): return a.is_garrison())
	t.check(garrison.size() == 1 and garrison[0].regiments.size() == 2 and state.armies_in("greywater").size() == armies_before + 1,
		"recruits join a new garrison in the province at the end of the turn")
	faction.resources.manpower = 50.0
	t.check(Economy.recruit_problem(state, "greywater", "militia", "aldmere") == "not enough resources", "recruiting needs manpower")

	var gold_before: float = faction.resources.gold
	t.check(state.appoint_general(garrison[0]) and faction.resources.gold == gold_before - 100.0, "appointing a general costs 100 gold")
	faction.resources.gold = 0.0
	t.check(state.split(state.armies_in("greywater")[0], [0]) == null, "splitting needs 100 gold for the new general")


func _test_happiness(t, map: MapData) -> void:
	var state := GameState.new_game(map, 5)
	var faction: FactionState = state.factions["aldmere"]
	var normal_gold: float = Economy.deltas(state, "aldmere").gold
	faction.tax = "high"
	var high_gold: float = Economy.deltas(state, "aldmere").gold
	faction.tax = "low"
	var low_gold: float = Economy.deltas(state, "aldmere").gold
	t.check(high_gold > normal_gold and normal_gold > low_gold, "high taxes bring more gold (%+d / %+d / %+d)" % [roundi(low_gold), roundi(normal_gold), roundi(high_gold)])
	var low_target := Economy.target_happiness(state, "ashford", false)
	faction.tax = "high"
	t.check(Economy.target_happiness(state, "ashford", false) == low_target - 35.0, "high taxes make provinces 35 points less happy than low taxes")
	t.check(Economy.target_happiness(state, "ashford", true) < Economy.target_happiness(state, "ashford", false), "starvation makes provinces unhappy")
	state.add_army("aldmere", "ashford", null, ["militia"])
	t.check(Economy.target_happiness(state, "ashford", false) == Economy.target_happiness(state, "northmarch", false) + Economy.GARRISON_HAPPINESS,
		"a garrison makes a province happier")

	# Revolts (PV-3): an unhappy province with no garrison eventually rises.
	state = GameState.new_game(map, 5)
	state.factions["aldmere"].tax = "high"
	var revolted := false
	for i in 30:
		state.provinces["northmarch"].happiness = 5.0
		var events := state.end_turn()
		if events.any(func(e): return e.type == "economy" and "Revolt in Northmarch" in e.text):
			revolted = true
			break
	var rebels: Array = state.armies_in("northmarch").filter(func(a): return a.owner == "rebels")
	t.check(revolted and rebels.size() == 1 and rebels[0].regiments.all(func(r): return r.type_id == "militia"),
		"an unhappy province without a garrison revolts and rebel militia appear")
	t.check(Economy.blockaded(state, "northmarch"), "a province held by rebels produces nothing for its owner")

	# Conquest leaves a province unhappy.
	state = GameState.new_game(map, 5)
	var raider := state.add_army("aldmere", "greywater", General.new("Raider"), ["light_cavalry"])
	state.armies = state.armies.filter(func(a): return a.province != "highcrag")
	state.order_move(raider, "highcrag")
	t.check(state.owners["highcrag"] == "aldmere" and state.provinces["highcrag"].happiness == Economy.CONQUERED_HAPPINESS,
		"a conquered province starts at %d happiness" % Economy.CONQUERED_HAPPINESS)
