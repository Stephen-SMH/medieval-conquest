extends RefCounted
## Orders and resolution (PRD 8.3, 8.4): one unit per region, merges, swaps,
## blocked moves, head-on attacks, contested moves, several attackers, split
## attacks, cavalry's two steps, retreats, ranged attacks, determinism, and
## mercenaries.

const Helpers := preload("res://tests/helpers.gd")


func run(t) -> void:
	_test_units(t)
	_test_one_per_region(t)
	_test_merge_swap_block(t)
	_test_head_on_and_contest(t)
	_test_attacks(t)
	_test_split_attacks(t)
	_test_cavalry(t)
	_test_ranged(t)
	_test_determinism_and_turns(t)
	_test_mercenaries(t)
	_test_healing_and_recruits(t)


func _test_units(t) -> void:
	var unit := Unit.new("spearmen", "blue", "greywater")
	t.check(unit.soldiers() == 20 and unit.max_hp() == 100.0, "a new unit has 20 soldiers and full HP")
	unit.hp = 51.0
	t.check(unit.soldiers() == 11, "soldiers = ceil(HP ÷ HP per soldier): 51 HP of spearmen is 11 soldiers")
	var ranks := []
	for xp in [0, 2, 5, 9]:
		unit.xp = xp
		ranks.append(unit.rank_name())
	t.check(ranks == ["Recruit", "Veteran", "Elite", "Hero"], "ranks by experience %s" % [ranks])


func _test_one_per_region(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue"}, [["blue", "greywater", "spearmen"], ["blue", "ashford", "archers"]], 7,
		{"buildings": {"greywater": {"barracks": 1}}, "resources": {"blue": {"gold": 1000, "wood": 200, "manpower": 200}}})
	t.check(GameState.STACK_LIMIT == 1 and state.space_in("greywater") == 0 and state.space_in("northmarch") == 1, "a region holds one unit")
	var archers: Unit = state.unit_in("ashford")
	Helpers.order(state, archers, "move", "greywater")
	var blocked := Helpers.resolve(state)
	t.check(archers.province == "ashford" and state.units_in("greywater").size() == 1 and Helpers.events_of(blocked, "blocked").size() == 1,
		"a unit can't join a region held by a different unit type that stays")
	t.check(Economy.recruit_problem(state, "greywater", "swordsmen", "blue").begins_with("no room"), "you can't recruit a different type into an occupied region")
	t.check(Economy.recruit_problem(state, "greywater", "spearmen", "blue").begins_with("no room"), "a full-strength unit can't be reinforced")
	state.unit_in("greywater").set_soldiers(12)
	state.unit_in("greywater").moved = true
	t.check(Economy.recruit_problem(state, "greywater", "spearmen", "blue") == "", "a weakened unit of the same type can be reinforced")
	Economy.recruit(state, "greywater", "spearmen")
	Helpers.resolve(state)
	t.check(state.unit_in("greywater").soldiers() == 20 and state.units_in("greywater").size() == 1, "reinforcements fill the unit up instead of adding one")


func _test_merge_swap_block(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue", "northmarch": "blue"}, [
		["blue", "ashford", "spearmen", 8], ["blue", "greywater", "spearmen", 9], ["blue", "northmarch", "archers"]])
	var a: Unit = state.unit_in("ashford")
	var b: Unit = state.unit_in("greywater")
	t.check(Helpers.order(state, a, "move", "greywater") == "", "a unit may move into a region held by the same type")
	var events := Helpers.resolve(state)
	t.check(not state.units.has(a) and b.soldiers() == 17 and Helpers.events_of(events, "merged").size() == 1, "moving in merges them: 8 + 9 = 17")

	state = Helpers.game({"greywater": "blue", "ashford": "blue"}, [["blue", "ashford", "spearmen", 15], ["blue", "greywater", "spearmen", 10]])
	a = state.unit_in("ashford")
	Helpers.order(state, a, "move", "greywater")
	Helpers.resolve(state)
	t.check(state.unit_in("greywater").soldiers() == 20 and a.province == "ashford" and a.soldiers() == 5, "a merge stops at 20; the other 5 stay behind")

	state = Helpers.game({"greywater": "blue", "ashford": "blue"}, [["blue", "ashford", "spearmen"], ["blue", "greywater", "archers"]])
	a = state.unit_in("ashford")
	b = state.unit_in("greywater")
	Helpers.order(state, b, "move", "ashford")
	t.check(Helpers.order(state, a, "move", "greywater") == "", "a unit may move where its own unit is leaving")
	events = Helpers.resolve(state)
	t.check(a.province == "greywater" and b.province == "ashford" and Helpers.events_of(events, "swapped").size() == 1, "two units can swap regions")

	state = Helpers.game({"greywater": "blue", "ashford": "blue", "northmarch": "blue"}, [["blue", "ashford", "spearmen"], ["blue", "greywater", "archers"],
		["blue", "northmarch", "militia"]])
	a = state.unit_in("ashford")
	b = state.unit_in("greywater")
	Helpers.order(state, b, "move", "ashford")
	Helpers.order(state, a, "move", "greywater")
	Orders.cancel(state, b)
	events = Helpers.resolve(state)
	t.check(a.province == "ashford" and Helpers.events_of(events, "blocked").size() == 1, "a move into a region whose unit stays put is blocked")


func _test_head_on_and_contest(t) -> void:
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "swordsmen"], ["red", "kingsvale", "swordsmen"]])
	var blue: Unit = state.unit_in("greywater")
	var red: Unit = state.unit_in("kingsvale")
	Helpers.order(state, blue, "attack", "kingsvale")
	Helpers.order(state, red, "attack", "greywater")
	var events := Helpers.resolve(state)
	var battles := Helpers.events_of(events, "battle")
	t.check(battles.size() == 1 and battles[0].kind == "head_on", "two units attacking each other fight one field battle")
	t.check(state.units_in("greywater").size() + state.units_in("kingsvale").size() <= 2, "no region ends up with two units")

	state = Helpers.game({"greywater": "blue", "eastwold": "red"}, [["blue", "greywater", "spearmen"], ["red", "eastwold", "militia"]])
	blue = state.unit_in("greywater")
	red = state.unit_in("eastwold")
	Helpers.order(state, blue, "move", "highcrag")
	Helpers.order(state, red, "move", "highcrag")
	events = Helpers.resolve(state)
	var contest := Helpers.events_of(events, "battle")
	t.check(contest.size() == 1 and contest[0].kind == "contest", "two factions moving into the same empty region fight for it")
	var holder := state.unit_in("highcrag")
	t.check(holder != null and state.units_in("highcrag").size() == 1 and state.owners.highcrag == holder.owner,
		"one of them takes it (%s); the loser stays home" % [holder.owner if holder != null else "nobody"])
	t.check((not state.units.has(red) or red.province == "eastwold") if holder == blue else (not state.units.has(blue) or blue.province == "greywater"),
		"the loser of the contest is back in its own region")


func _test_attacks(t) -> void:
	# Several attackers on one region, strongest first.
	var state := Helpers.game({"greywater": "blue", "ashford": "blue", "kingsvale": "red"}, [
		["blue", "greywater", "militia"], ["blue", "ashford", "heavy_cavalry"], ["red", "kingsvale", "spearmen", 6]], 3)
	var weak: Unit = state.unit_in("greywater")
	var strong: Unit = state.unit_in("ashford")
	Helpers.order(state, weak, "attack", "kingsvale")
	Helpers.order(state, strong, "attack", "kingsvale")
	var events := Helpers.resolve(state)
	var battles := Helpers.events_of(events, "battle")
	t.check(not battles.is_empty() and battles[0].unit == strong, "several attackers on one region: the strongest fights first")
	t.check(state.owners.kingsvale == "blue" and state.units_in("kingsvale").size() == 1, "later attackers face whatever is left, and the region holds one unit")

	# A failed attacker stays at its origin.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "militia", 10], ["red", "kingsvale", "swordsmen"]])
	var attacker: Unit = state.unit_in("greywater")
	Helpers.order(state, attacker, "attack", "kingsvale")
	events = Helpers.resolve(state)
	t.check(not Helpers.events_of(events, "battle")[0].battle.attacker_won() and state.owners.kingsvale == "red", "a weak attack fails")
	t.check(not state.units.has(attacker) or attacker.province == "greywater", "the failed attacker ends the turn in its origin region")
	t.check(not Helpers.events_of(events, "repulsed").is_empty() or not state.units.has(attacker), "and the turn shows it falling back")

	# A beaten defender retreats to a free friendly region, or is destroyed.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red", "highcrag": "red"}, [["blue", "greywater", "heavy_cavalry"], ["red", "kingsvale", "militia", 20]], 11)
	var defender: Unit = state.unit_in("kingsvale")
	Helpers.order(state, state.unit_in("greywater"), "attack", "kingsvale")
	events = Helpers.resolve(state)
	t.check(state.owners.kingsvale == "blue" and (not state.units.has(defender) or defender.province == "highcrag"),
		"a beaten defender retreats to its free neighbouring region (or died in the fight)")
	state = Helpers.game({"greywater": "blue", "kingsvale": "red", "highcrag": "red"}, [["blue", "greywater", "heavy_cavalry"],
		["red", "kingsvale", "militia", 20], ["red", "highcrag", "militia"]], 3)
	defender = state.unit_in("kingsvale")
	Helpers.order(state, state.unit_in("greywater"), "attack", "kingsvale")
	events = Helpers.resolve(state)
	t.check(not state.units.has(defender), "a beaten defender with no free region of its own is destroyed%s" % (
		" (no room to retreat)" if events.any(func(e): return e.type == "destroyed" and e.how == "had nowhere to retreat") else ""))


func _test_split_attacks(t) -> void:
	# Send 5 of 20; when it fails, they come back and rejoin.
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "swordsmen"], ["red", "kingsvale", "swordsmen"]], 4)
	var unit: Unit = state.unit_in("greywater")
	Helpers.order(state, unit, "attack", "kingsvale", {"soldiers": 5})
	t.check(state.orders[unit][0].size == 5, "an attack can send part of the unit (5 of 20)")
	var events := Helpers.resolve(state)
	var battle: Battle = Helpers.events_of(events, "battle")[0].battle
	t.check(battle.attacker.units[0].soldiers() <= 5 and battle.attacker.before[0][1] == 5, "only the 5 sent fight")
	t.check(state.units_in("greywater").size() == 1 and unit.soldiers() >= 15 and unit.soldiers() <= 20,
		"the detachment comes back and rejoins: one unit, %d soldiers" % unit.soldiers())

	# A detachment that takes the region stays there; the rest stay home.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "heavy_cavalry"], ["red", "kingsvale", "militia", 2]], 4)
	unit = state.unit_in("greywater")
	Helpers.order(state, unit, "attack", "kingsvale", {"soldiers": 12})
	Helpers.resolve(state)
	t.check(state.owners.kingsvale == "blue" and unit.province == "greywater" and unit.soldiers() == 8
		and state.unit_in("kingsvale") != null and state.unit_in("kingsvale").type_id == "heavy_cavalry",
		"a detachment that wins keeps the region; 8 stay at home")

	# Archers split between shooting and melee.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "archers"], ["red", "kingsvale", "militia", 6]], 4)
	unit = state.unit_in("greywater")
	Helpers.order(state, unit, "attack", "kingsvale", {"shoot": 14, "soldiers": 6})
	t.check(state.orders[unit][0].shoot == 14 and state.orders[unit][0].soldiers == 6, "archers can split: 14 shoot and 6 go into melee")
	events = Helpers.resolve(state)
	var volleys := Helpers.events_of(events, "volley")
	t.check(volleys.size() == 1 and volleys[0].shooters == 14, "the 14 shoot first")
	t.check(Helpers.events_of(events, "battle").size() <= 1 and state.units_in("greywater").size() <= 1, "then the 6 fight hand to hand")


func _test_cavalry(t) -> void:
	var state := Helpers.game({"greywater": "blue"}, [["blue", "greywater", "light_cavalry"], ["blue", "ashford", "spearmen"]])
	var horse: Unit = state.unit_in("greywater")
	var foot: Unit = state.unit_in("ashford")
	t.check(Helpers.order(state, horse, "move", "kingsvale") == "" and Helpers.order(state, horse, "move", "redfield") == "",
		"cavalry plans two moves")
	t.check(state.orders[horse][0].steps.size() == 2, "both steps are kept")
	Helpers.order(state, foot, "move", "saltmere")
	Helpers.order(state, foot, "move", "northmarch")
	t.check(state.orders[foot].size() == 1 and state.orders[foot][0].steps.size() == 1 and state.orders[foot][0].steps[0].target == "northmarch",
		"infantry gets one step: a second click replaces a whole-unit order")
	Orders.cancel(state, foot)
	Helpers.resolve(state)
	t.check(horse.province == "redfield" and state.owners.kingsvale == "blue" and state.owners.redfield == "blue",
		"cavalry rides 2 regions in one turn, capturing both")

	state = Helpers.game({"greywater": "blue", "redfield": "red"}, [["blue", "greywater", "heavy_cavalry"], ["red", "redfield", "militia", 4]], 2)
	horse = state.unit_in("greywater")
	Helpers.order(state, horse, "move", "kingsvale")
	t.check(Helpers.order(state, horse, "attack", "redfield") == "", "cavalry can move and then attack")
	Helpers.resolve(state)
	t.check(state.owners.redfield == "blue", "and win the region it attacked after moving")


func _test_ranged(t) -> void:
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "archers"], ["red", "kingsvale", "spearmen", 1]], 5)
	var archers: Unit = state.unit_in("greywater")
	Helpers.order(state, archers, "attack", "kingsvale")
	var events := Helpers.resolve(state)
	t.check(Helpers.events_of(events, "volley").size() == 1 and archers.province == "greywater", "archers shoot from their own region")
	t.check(state.owners.kingsvale == "red", "a ranged attack never captures a region, even when it kills the defender")
	t.check(archers.hp == archers.max_hp(), "melee defenders can't shoot back")
	state = Helpers.game({"greywater": "blue", "redfield": "red"}, [["blue", "greywater", "archers"], ["red", "redfield", "militia"]])
	t.check(Orders.problem(state, state.unit_in("greywater"), "attack", "redfield") == "out of range", "archers reach only neighbouring regions")
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "mamluk"], ["red", "kingsvale", "archers"]], 5, {"blue_civ": "saracen"})
	Helpers.order(state, state.unit_in("greywater"), "attack", "kingsvale")
	Helpers.resolve(state)
	t.check(state.unit_in("greywater").hp == state.unit_in("greywater").max_hp(), "mamluks shoot and ride off: archers can't shoot back")


func _test_determinism_and_turns(t) -> void:
	var setup := func() -> GameState:
		var game := Helpers.game({"greywater": "blue", "ashford": "blue", "kingsvale": "red", "highcrag": "red"}, [
			["blue", "greywater", "swordsmen"], ["blue", "ashford", "archers"], ["red", "kingsvale", "spearmen"], ["red", "highcrag", "light_cavalry"]], 21)
		Helpers.order(game, game.unit_in("greywater"), "attack", "kingsvale")
		Helpers.order(game, game.unit_in("ashford"), "attack", "kingsvale")
		Helpers.order(game, game.unit_in("highcrag"), "attack", "greywater")
		Helpers.resolve(game)
		return game
	t.check(JSON.stringify(SaveGame.to_dict(setup.call())) == JSON.stringify(SaveGame.to_dict(setup.call())),
		"resolving the same orders with the same seed gives the same result")

	var state := Helpers.game({"greywater": "blue", "eastwold": "red"}, [["blue", "greywater", "spearmen"], ["red", "eastwold", "spearmen"]])
	var blue: Unit = state.unit_in("greywater")
	Orders.give(state, blue, "move", "ashford")
	t.check(blue.province == "greywater" and state.end_faction_turn().is_empty() and state.current_faction() == "red",
		"orders wait: after blue plans, red plans, and nothing has moved yet")
	t.check(Orders.problem(state, blue, "move", "northmarch") == "not your unit to command", "you can't order another faction's units")
	state.end_faction_turn()
	t.check(blue.province == "ashford" and state.turn == 2 and state.season() == "Summer" and state.current_faction() == "blue",
		"when the last faction ends planning, everything resolves and turn 2 begins")
	t.check(state.orders.is_empty(), "orders are cleared for the new turn")

	# The AI and humans in hotseat plan through the same Orders and resolve together.
	var scenario := Skirmish.build("heartlands", [{"civ": "norse", "human": true}, {"civ": "anglish", "human": true}, {"civ": "frankish"}], "hard", 5)
	var game := GameState.from_scenario(scenario, 5)
	var first: Unit = game.units_of("norse")[0]
	var target := ""
	for neighbour in game.map.neighbours(first.province):
		if Orders.problem(game, first, "move", neighbour) == "":
			target = neighbour
	Orders.give(game, first, "move", target)
	game.end_faction_turn()
	var second: Unit = game.units_of("anglish")[0]
	for neighbour in game.map.neighbours(second.province):
		if Orders.problem(game, second, "move", neighbour) == "":
			Orders.give(game, second, "move", neighbour)
			break
	game.end_faction_turn()
	AI.play_turn(game)
	var ai_orders := game.orders.keys().filter(func(u: Unit): return u.owner == "frankish").size()
	var events := game.end_faction_turn()
	t.check(ai_orders > 0 and game.turn == 2 and not events.is_empty() and (first.province == target or not Helpers.events_of(events, "battle").is_empty()),
		"two humans and an AI plan in turn, then all their orders resolve together (%d AI orders)" % ai_orders)


func _test_mercenaries(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue"}, [], 7, {"resources": {"blue": {"gold": 1000}}})
	t.check(Economy.site(state, "ashford") == "town" and Economy.site(state, "greywater") == "", "Ashford is a town, Greywater isn't")
	t.check(Economy.hire_problem(state, "greywater", "spearmen", "blue") == "mercenaries are only hired in towns and camps",
		"you can't hire mercenaries outside towns and camps")
	var stock: int = state.provinces.ashford.mercenaries.spearmen
	t.check(Economy.hire(state, "ashford", "spearmen") and state.factions.blue.resources.gold == 1000.0 - 105.0
		and state.provinces.ashford.mercenaries.spearmen == stock - 1, "hiring in a town costs gold (105 for spearmen) and uses up stock")
	t.check(Economy.hire_problem(state, "ashford", "crossbowmen", "blue") == "one recruit per region per turn", "one hire per region per turn")
	t.check(Economy.hire_problem(state, "ashford", "light_cavalry", "blue") != "", "a town doesn't offer what a camp does")
	Helpers.resolve(state)
	t.check(state.unit_in("ashford") != null and state.unit_in("ashford").type_id == "spearmen", "the mercenaries arrive at the end of the turn")
	state.provinces.ashford.mercenaries.spearmen = 0
	t.check(Economy.hire_problem(state, "ashford", "spearmen", "blue") != "", "with no stock left, nobody can be hired")


func _test_healing_and_recruits(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue"}, [["blue", "greywater", "spearmen", 10], ["blue", "ashford", "spearmen", 10]])
	Helpers.order(state, state.unit_in("ashford"), "move", "northmarch")
	Helpers.resolve(state)
	t.check(state.unit_in("greywater").soldiers() == 12 and state.unit_in("northmarch").soldiers() == 10, "a resting unit heals 2 soldiers; a moving one doesn't")
