extends RefCounted
## The gold economy (PRD 8.9): region income, upkeep, desertion, healing,
## buildings, recruiting and mercenary prices.

const Helpers := preload("res://tests/helpers.gd")


func run(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue", "northmarch": "blue"},
		[["blue", "greywater", "spearmen"], ["blue", "ashford", "archers"]], 5,
		{"capitals": {"blue": "greywater"}, "buildings": {"greywater": {"market": 1}}})
	t.check(FactionState.RESOURCES == ["gold"] and Economy.START_RESOURCES == {"gold": 300.0}, "gold is the only resource")
	t.check(Economy.region_income(state, "northmarch") == 10.0, "a plain region pays 10 gold a turn")
	t.check(Economy.region_income(state, "ashford") == 15.0, "a town pays 15")
	t.check(Economy.region_income(state, "greywater") == 28.0, "a capital with a market pays 10 + 10 + 8 = 28")
	var blue: FactionState = state.factions.blue
	var before: float = blue.resources.gold
	var change: float = Economy.deltas(state, "blue").gold
	t.check(is_equal_approx(change, 53.0 - Economy.unit_upkeep(state, state.unit_in("greywater")) - Economy.unit_upkeep(state, state.unit_in("ashford"))),
		"the change is the regions' gold minus unit upkeep (%+d)" % roundi(change))
	Helpers.resolve(state)
	t.check(is_equal_approx(blue.resources.gold, before + change), "ending the turn applies exactly the shown change")
	var labels: Array = Economy.breakdown(state, "blue").gold.map(func(l): return l[0])
	t.check("Unit upkeep" in labels and "Market regions" in labels and "Towns" in labels, "the treasury lists where the gold comes from %s" % [labels])

	state = Helpers.game({"greywater": "blue"}, [["blue", "greywater", "heavy_cavalry"]], 5, {"resources": {"blue": {"gold": -500}}})
	Helpers.resolve(state)
	t.check(state.factions.blue.resources.gold == 0.0 and state.unit_in("greywater").soldiers() == 19,
		"when gold would go negative, 5% of every unit deserts")

	state = Helpers.game({"greywater": "blue"}, [["blue", "greywater", "spearmen", 10]], 5)
	var gold: float = state.factions.blue.resources.gold + Economy.deltas(state, "blue").gold
	Helpers.resolve(state)
	t.check(state.unit_in("greywater").soldiers() == 12 and is_equal_approx(state.factions.blue.resources.gold, gold - 2 * Economy.heal_cost(Rules.unit("spearmen"))),
		"healing 2 soldiers costs gold (%.1f each for spearmen)" % Economy.heal_cost(Rules.unit("spearmen")))

	# Buildings cost gold only.
	state = Helpers.game({"greywater": "blue", "northmarch": "blue", "ashford": "blue"}, [], 5,
		{"capitals": {"blue": "greywater"}, "resources": {"blue": {"gold": 2000}}})
	t.check(Economy.building_cost(Rules.building("barracks")) == {"gold": 190.0}, "a barracks costs 190 gold (wood folded into gold)")
	t.check(Economy.start_building(state, "greywater", "market") and state.factions.blue.resources.gold == 2000.0 - 180.0, "a market costs 180 gold")
	t.check(Economy.build_problem(state, "greywater", "barracks", "blue").begins_with("already building:"), "one building at a time")
	Helpers.resolve(state)
	t.check(state.provinces.greywater.level("market") == 1 and Economy.region_income(state, "greywater") == 28.0,
		"once built, the market adds 8 gold a turn")
	t.check(Economy.building_cost(Rules.building("walls"), 3).gold == 840.0, "a castle (walls level 3) costs 6 × 140 gold")
	state.provinces.ashford.buildings = {"market": 1, "barracks": 1, "archery_range": 1, "stable": 1}
	t.check(Economy.build_problem(state, "ashford", "siege_workshop", "blue") == "no free building slots"
		and Economy.slots(state, "greywater") == 6, "4 slots, 6 in a capital")

	# Recruiting.
	t.check(Economy.recruit_problem(state, "northmarch", "spearmen", "blue") == "needs: barracks", "spearmen need a barracks")
	t.check(Economy.recruit_problem(state, "ashford", "berserker", "blue").begins_with("only the Norse"), "special units belong to one civilization")
	t.check(Economy.unit_cost(state, "blue", Rules.unit("swordsmen")) == {"gold": 120.0}, "swordsmen cost 120 gold (90 + iron folded in)")
	t.check(Economy.mercenary_price(Rules.unit("spearmen")) == 105.0, "mercenaries cost 1.5 × the unit's gold price")
