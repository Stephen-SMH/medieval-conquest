extends RefCounted
## The gold economy (PRD 8.9, E): region income, upkeep, desertion, healing,
## buildings and reinforcement bundles.

const Helpers := preload("res://tests/helpers.gd")


func run(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue", "northmarch": "blue"},
		[["blue", "greywater", "spearmen"], ["blue", "ashford", "archers"]], 5,
		{"capitals": {"blue": "greywater"}, "buildings": {"greywater": {"market": 1}}})
	t.check(FactionState.RESOURCES == ["gold"] and Economy.START_RESOURCES == {"gold": 300.0}, "gold is the only resource")
	t.check(Economy.region_income(state, "northmarch") == 10.0, "a plain region pays 10 gold a turn")
	t.check(Economy.region_income(state, "ashford") == 15.0, "a town pays 15")
	t.check(Economy.region_income(state, "greywater") == 28.0, "a capital with a market pays 10 + 10 + 8 = 28")
	t.check(Economy.base_income(state, "ashford") == 15.0, "a map's own income would replace these (the real maps set 5, 10 or 15)")
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
	t.check(state.unit_in("greywater").soldiers() == 10 and is_equal_approx(state.factions.blue.resources.gold, gold),
		"resting heals health only, and it's free")

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
	state.provinces.ashford.buildings = {"market": 1, "barracks": 1, "walls": 1}
	t.check(Economy.used_slots(state, "ashford") == 3 and Economy.slots(state, "ashford") == 4 and Economy.slots(state, "greywater") == 6,
		"4 slots, 6 in a capital")
	t.check(not Rules.buildings.has("archery_range") and not Rules.buildings.has("stable") and not Rules.buildings.has("siege_workshop"),
		"no buildings are needed to raise soldiers (PRD E)")

	_test_bundles(t)


## Reinforcements come in fixed bundles, go to the capital, towns and camps,
## and arrive next turn (PRD E).
func _test_bundles(t) -> void:
	var state := Helpers.game({"greywater": "blue", "northmarch": "blue", "ashford": "blue"}, [["blue", "ashford", "spearmen", 15]], 5,
		{"capitals": {"blue": "greywater"}, "resources": {"blue": {"gold": 1000}}})
	var bundles := Economy.bundles(state, "blue")
	var types := bundles.map(func(b): return b.type)
	t.check(types.has("spearmen") and types.has("heavy_cavalry") and not types.has("berserker"),
		"bundles of the base roster, not another civilization's soldiers")
	var small := Economy.bundle_of(state, "blue", "archers")
	var large := Economy.bundle_of(state, "blue", "archers", true)
	t.check(small == {"type": "archers", "soldiers": 5, "price": 45} and large == {"type": "archers", "soldiers": 10, "price": 75},
		"archers come 5 for 45 gold or 10 for 75 (%s, %s)" % [small, large])
	var riders := Economy.bundle_of(state, "blue", "light_cavalry")
	t.check(riders.soldiers < small.soldiers and riders.price >= small.price, "dearer soldiers come in smaller bundles (%s)" % [riders])
	t.check(bundles.all(func(b): return b.soldiers <= Economy.MAX_BUNDLE and int(b.price) % 5 == 0), "a bundle holds at most 10 soldiers; prices are in fives")
	t.check(Economy.recruit_point(state, "greywater", "blue") and Economy.recruit_point(state, "ashford", "blue")
		and not Economy.recruit_point(state, "northmarch", "blue"), "reinforcements go to the capital, towns and camps")
	t.check(Economy.bundle_targets(state, large, "blue") == ["greywater"], "and only where they fit: Ashford's 15 have no room for 10 more")
	t.check(Economy.buy(state, "ashford", small) and state.factions.blue.resources.gold == 955.0, "5 do fit; the price is paid at once")
	t.check(Economy.bundle_problem(state, "ashford", small, "blue").begins_with("this province already") and Economy.recruit_closed(state, "ashford", "blue"),
		"one order per province per turn; the map marks it with a no-sign")
	t.check(Economy.buy(state, "greywater", large) and not Economy.recruit_closed(state, "northmarch", "blue"), "the capital takes another order")
	t.check(state.unit_in("ashford").soldiers() == 15 and state.unit_in("greywater") == null, "they don't arrive this turn")
	var events := Helpers.resolve(state)
	t.check(state.unit_in("ashford").composition() == {"spearmen": 15, "archers": 5} and state.unit_in("greywater").composition() == {"archers": 10},
		"next turn they join the army there, or form a new one")
	var arrived := Helpers.events_of(events, "arrived").map(func(e): return e.text)
	t.check(arrived.size() == 2 and arrived.has("Reinforcements arrived in Ashford: Archers – 5."),
		"each arrival is reported")
	t.check(Economy.recruit_closed(state, "ashford", "blue") and state.provinces.ashford.recruits.is_empty(), "a province whose army is full is closed too")
	state.factions.blue.resources.gold = 10.0
	t.check(Economy.bundle_problem(state, "greywater", small, "blue") == "not enough gold", "bundles cost gold")

	# Soldiers who no longer fit when they arrive are paid back.
	state = Helpers.game({"ashford": "blue"}, [["blue", "ashford", "spearmen", 12]], 5, {"resources": {"blue": {"gold": 1000}}})
	Economy.buy(state, "ashford", small)
	state.unit_in("ashford").add("spearmen", 6)
	var gold: float = state.factions.blue.resources.gold
	Economy.arrivals(state, "blue")
	t.check(state.unit_in("ashford").soldiers() == Unit.CAP and is_equal_approx(state.factions.blue.resources.gold, gold + 27.0),
		"only 2 of 5 fit: the other 3's share of the price comes back")

	# A captured province loses the reinforcements on their way to it.
	state = Helpers.game({"ashford": "blue"}, [], 5, {"resources": {"blue": {"gold": 1000}}})
	Economy.buy(state, "ashford", small)
	state.capture("red", "ashford")
	t.check(state.provinces.ashford.recruits.is_empty() and Economy.arrivals(state, "red").is_empty(), "the new owner doesn't get them")
