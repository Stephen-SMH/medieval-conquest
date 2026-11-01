extends RefCounted
## The economy on units: resources, seasons, food and supply, buildings,
## storage, taxes, happiness and revolts.

const Helpers := preload("res://tests/helpers.gd")


func run(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue", "northmarch": "blue"},
		[["blue", "greywater", "spearmen"], ["blue", "greywater", "archers"]], 5,
		{"capitals": {"blue": "greywater"}, "buildings": {"greywater": {"farm": 1, "market": 1}}})
	var blue: FactionState = state.factions.blue
	var before := blue.resources.duplicate()
	var change := Economy.deltas(state, "blue")
	state.end_faction_turn()
	var matches := true
	for resource in ["gold", "wood", "iron", "manpower"]:
		matches = matches and is_equal_approx(blue.resources[resource], before[resource] + change[resource])
	t.check(matches, "ending the turn applies the shown changes (gold %+d, food %+d)" % [roundi(change.gold), roundi(change.food)])
	var labels := []
	for resource in Economy.breakdown(state, "blue"):
		for line in Economy.breakdown(state, "blue")[resource]:
			labels.append(line[0])
	t.check("Unit upkeep" in labels and "Units eat" in labels and "Markets" in labels, "the breakdown lists unit upkeep %s" % [labels])

	state.turn = 1
	var spring := Economy.province_food(state, "greywater")
	state.turn = 3
	var autumn := Economy.province_food(state, "greywater")
	state.turn = 4
	t.check(is_equal_approx(autumn, spring * 1.5) and is_equal_approx(Economy.province_food(state, "greywater"), spring * 0.25),
		"food ×1.5 in autumn, ×0.25 in winter")

	# Starvation, spoilage, desertion.
	state = Helpers.game({"greywater": "blue"}, [["blue", "greywater", "heavy_cavalry"]], 5, {"resources": {"blue": {"food": -500}}})
	var events := state.end_faction_turn()
	t.check(state.factions.blue.resources.food == 0.0 and state.units[0].soldiers() == 18 and events.any(func(e): return "Starvation" in e.get("text", "")),
		"starvation: food stops at 0 and units lose 10% of their soldiers")
	state = Helpers.game({"greywater": "blue"}, [], 5, {"resources": {"blue": {"food": 900}}})
	state.end_faction_turn()
	t.check(state.factions.blue.resources.food == Economy.FOOD_CAP, "food above the storage cap spoils")
	state.provinces.greywater.buildings["granary"] = 1
	t.check(Economy.food_cap(state, "blue") == Economy.FOOD_CAP + 500.0, "a granary stores 500 more food")

	# Supply and winter.
	state = Helpers.game({"greywater": "blue"}, [["blue", "kingsvale", "spearmen"], ["blue", "stonehelm", "spearmen"]], 5)
	t.check(Economy.is_supplied(state, state.units[0]) and not Economy.is_supplied(state, state.units[1]),
		"units within 2 regions of home are supplied; further away they forage")
	state.provinces.stonehelm.forage = 0.0
	state.end_faction_turn()
	t.check(state.units[1].soldiers() == 19 and state.units[0].soldiers() == 20, "when the forage runs out a unit loses 5%")
	state = Helpers.game({"greywater": "blue"}, [["blue", "greywater", "spearmen"], ["blue", "kingsvale", "spearmen"], ["blue", "highcrag", "spearmen"]], 5)
	state.turn = 4
	for unit in state.units:
		unit.moved = true  # So nobody heals.
	state.end_faction_turn()
	t.check(state.units[0].soldiers() == 20 and is_equal_approx(state.units[1].strength(), 0.95) and is_equal_approx(state.units[2].strength(), 0.9),
		"winter: no loss at home, 5% abroad, 10% in mountains")

	# Buildings.
	state = Helpers.game({"greywater": "blue", "northmarch": "blue", "ashford": "blue"}, [], 5,
		{"capitals": {"blue": "greywater"}, "resources": {"blue": {"gold": 2000, "wood": 500}}})
	t.check(Economy.start_building(state, "greywater", "farm") and state.factions.blue.resources.gold == 1900.0, "a farm costs 100 gold")
	t.check(Economy.build_problem(state, "greywater", "market", "blue").begins_with("already building:"), "one building at a time")
	state.end_faction_turn()
	t.check(state.provinces.greywater.level("farm") == 1, "it's finished after its build time")
	t.check(Economy.build_problem(state, "greywater", "lumber_camp", "blue") == "needs forest"
		and Economy.build_problem(state, "northmarch", "lumber_camp", "blue") == "", "lumber camps need forest")
	state.provinces.ashford.buildings = {"farm": 1, "market": 1, "granary": 1, "stable": 1}
	t.check(Economy.build_problem(state, "ashford", "barracks", "blue") == "no free building slots"
		and Economy.slots(state, "greywater") == 6, "4 slots, 6 in a capital")

	# Recruiting.
	t.check(Economy.recruit_problem(state, "ashford", "spearmen", "blue") == "needs: barracks", "spearmen need a barracks")
	t.check(Economy.recruit_problem(state, "ashford", "light_cavalry", "blue") == "", "the stable allows cavalry")
	t.check(Economy.recruit_problem(state, "ashford", "berserker", "blue").begins_with("only the Norse"), "special units belong to one civilization")

	# Taxes, happiness, revolts.
	state = Helpers.game({"greywater": "blue", "northmarch": "blue"}, [], 5)
	var normal: float = Economy.deltas(state, "blue").gold
	state.factions.blue.tax = "high"
	t.check(Economy.deltas(state, "blue").gold > normal, "high taxes bring more gold")
	var revolted := false
	for i in 30:
		state.provinces.northmarch.happiness = 5.0
		var turn_events := state.end_faction_turn()
		state.end_faction_turn()
		if turn_events.any(func(e): return "Revolt in Northmarch" in e.get("text", "")):
			revolted = true
			break
	t.check(revolted and state.units_in("northmarch").all(func(u): return u.owner == "rebels" and u.type_id == "militia"),
		"an unhappy region without units revolts and rebel militia appear")
	t.check(Economy.blockaded(state, "northmarch"), "a region with rebels in it produces nothing")
