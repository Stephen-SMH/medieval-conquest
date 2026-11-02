extends RefCounted
## Armies, orders and resolution (PRD A, B, C, D, 8.3, 8.4): mixed armies,
## one army per region, merges up to the cap, swaps, blocked moves, several
## attackers, support orders, per-type splits, cavalry's two steps, ranged
## fire that only wounds, per-faction turns, determinism, healing and
## reinforcements.

const Helpers := preload("res://tests/helpers.gd")


func run(t) -> void:
	_test_armies(t)
	_test_wounds(t)
	_test_one_per_region(t)
	_test_merge_swap_block(t)
	_test_attacks(t)
	_test_support(t)
	_test_split_attacks(t)
	_test_cavalry(t)
	_test_ranged(t)
	_test_faction_turns(t)
	_test_determinism(t)
	_test_healing_and_recruits(t)


func _test_armies(t) -> void:
	var unit := Unit.new("spearmen", "blue", "greywater")
	t.check(unit.soldiers() == 20 and unit.max_hp() == 100.0 and unit.health() == 1.0, "a new army of 20 spearmen has full health")
	unit.add("archers", 2)
	unit.add("militia", 8)
	t.check(unit.composition() == {"militia": 8, "spearmen": 20, "archers": 2} and unit.soldiers() == 30,
		"an army mixes soldier types: %s" % [unit.composition()])
	t.check(unit.type_id == "spearmen" and unit.type_count() == 3, "its dominant type is the one with most soldiers")
	unit.add("archers", 3)
	t.check(unit.troop("archers").soldiers == 5 and unit.troops.size() == 3, "more of a type joins the troop already there")
	var part := unit.split({"spearmen": 5, "archers": 5})
	t.check(part.composition() == {"spearmen": 5, "archers": 5} and unit.composition() == {"militia": 8, "spearmen": 15},
		"splitting takes soldiers per type")
	t.check(Orders.pick({"militia": 8, "archers": 2}, 5) == {"militia": 4, "archers": 1}, "a count spreads over the types in proportion")
	t.check(Unit.CAP == 30, "a region's army holds up to 30 soldiers")
	t.check(not ("xp" in unit) and not ("general" in unit), "armies have no experience, ranks or generals")


func _test_wounds(t) -> void:
	var troop := Troop.new("spearmen", 5)
	troop.wound(troop.soldier_hp() * 0.8)
	t.check(troop.soldiers == 5 and troop.health() < 1.0, "a volley wears health down without killing (5 soldiers, health %d%%)" % roundi(troop.health() * 100))
	for i in 20:
		troop.wound(troop.soldier_hp() * 3.0)
	t.check(troop.soldiers == 1 and troop.hp > 0.0, "fire never takes the last soldier")
	troop = Troop.new("spearmen", 5)
	troop.hit(troop.soldier_hp() * 1.5)
	t.check(troop.soldiers == 4, "melee kills: 1.5 soldiers' worth of damage leaves 4")
	troop.hit(troop.soldier_hp() * 10.0)
	t.check(troop.is_destroyed(), "melee can destroy a troop")

	# The example from the reference game: 6 archers shoot 5 defenders.
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "archers", 6], ["red", "kingsvale", "spearmen", 5]], 5)
	Helpers.order(state, state.unit_in("greywater"), "attack", "kingsvale")
	Helpers.resolve_faction(state, "blue")
	var defender := state.unit_in("kingsvale")
	t.check(defender != null and defender.soldiers() == 5 and defender.health() < 1.0 and state.owners.kingsvale == "red",
		"6 archers shooting 5 spearmen leave them at 5 soldiers with a damaged bar (%d%%)" % roundi(defender.health() * 100 if defender != null else 0))
	var survived := true
	for game_seed in 12:
		state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "crossbowmen", 30], ["red", "kingsvale", "militia", 2]], game_seed)
		for turn in 3:
			Helpers.order(state, state.unit_in("greywater"), "attack", "kingsvale")
			Helpers.resolve(state)
		survived = survived and state.unit_in("kingsvale") != null and state.unit_in("kingsvale").soldiers() >= 1 and state.owners.kingsvale == "red"
	t.check(survived, "30 crossbowmen shooting 2 militia for 3 turns never destroy them or take the region")


func _test_one_per_region(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue"}, [["blue", "greywater", "spearmen"], ["blue", "ashford", "archers", 6]], 7,
		{"resources": {"blue": {"gold": 1000}}})
	t.check(GameState.STACK_LIMIT == 1 and state.space_in("greywater") == 0 and state.space_in("northmarch") == 1, "a region holds one army")
	var archers: Unit = state.unit_in("ashford")
	Helpers.order(state, archers, "move", "greywater")
	Helpers.resolve(state)
	var army := state.unit_in("greywater")
	t.check(not state.units.has(archers) and army.composition() == {"spearmen": 20, "archers": 6} and state.units_in("greywater").size() == 1,
		"marching into your own army merges the types into one army: %s" % [army.composition()])


func _test_merge_swap_block(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue"}, [["blue", "ashford", "spearmen", 15], ["blue", "greywater", "militia", 20]])
	var a: Unit = state.unit_in("ashford")
	Helpers.order(state, a, "move", "greywater")
	var events := Helpers.resolve(state)
	t.check(state.unit_in("greywater").soldiers() == 30 and a.province == "ashford" and a.soldiers() == 5 and Helpers.events_of(events, "merged").size() == 1,
		"a merge stops at 30; the other 5 stay behind")

	state = Helpers.game({"greywater": "blue", "ashford": "blue"}, [["blue", "ashford", "spearmen"], ["blue", "greywater", "archers"]])
	a = state.unit_in("ashford")
	var b: Unit = state.unit_in("greywater")
	Helpers.order(state, b, "move", "ashford")
	t.check(Helpers.order(state, a, "move", "greywater") == "", "an army may move where another of yours is leaving")
	events = Helpers.resolve(state)
	t.check(a.province == "greywater" and b.province == "ashford" and Helpers.events_of(events, "swapped").size() == 1, "two whole armies can swap regions")

	state = Helpers.game({"greywater": "blue", "ashford": "blue"}, [["blue", "ashford", "spearmen", 30], ["blue", "greywater", "archers", 30]])
	t.check(Orders.problem(state, state.unit_in("greywater"), "move", "ashford").contains("30"), "you can't march into a full army that stays")


func _test_attacks(t) -> void:
	# Several plain attacks on one region fight one after another, strongest first.
	var state := Helpers.game({"greywater": "blue", "ashford": "blue", "kingsvale": "red"}, [
		["blue", "greywater", "militia"], ["blue", "ashford", "heavy_cavalry"], ["red", "kingsvale", "spearmen", 6]], 3)
	var weak: Unit = state.unit_in("greywater")
	var strong: Unit = state.unit_in("ashford")
	Helpers.order(state, weak, "attack", "kingsvale")
	Helpers.order(state, strong, "attack", "kingsvale")
	var events := Helpers.resolve_faction(state, "blue")
	var battles := Helpers.events_of(events, "battle")
	t.check(not battles.is_empty() and battles[0].unit == strong, "several attackers on one region: the strongest fights first")
	t.check(state.owners.kingsvale == "blue" and state.units_in("kingsvale").size() == 1, "later attackers face whatever is left, and the region holds one army")

	# A failed attacker stays at its origin.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "militia", 10], ["red", "kingsvale", "swordsmen"]])
	var attacker: Unit = state.unit_in("greywater")
	Helpers.order(state, attacker, "attack", "kingsvale")
	events = Helpers.resolve_faction(state, "blue")
	t.check(not Helpers.events_of(events, "battle")[0].battle.attacker_won() and state.owners.kingsvale == "red", "a weak attack fails")
	t.check(not state.units.has(attacker) or attacker.province == "greywater", "the failed attacker ends the turn in its origin region")

	# A beaten defender retreats to a free friendly region, or is destroyed.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red", "highcrag": "red"}, [["blue", "greywater", "heavy_cavalry"], ["red", "kingsvale", "militia", 20]], 11)
	var defender: Unit = state.unit_in("kingsvale")
	Helpers.order(state, state.unit_in("greywater"), "attack", "kingsvale")
	Helpers.resolve_faction(state, "blue")
	t.check(state.owners.kingsvale == "blue" and (not state.units.has(defender) or defender.province == "highcrag"),
		"a beaten defender retreats to its free neighbouring region (or died in the fight)")
	state = Helpers.game({"greywater": "blue", "kingsvale": "red", "highcrag": "red"}, [["blue", "greywater", "heavy_cavalry"],
		["red", "kingsvale", "militia", 20], ["red", "highcrag", "militia"]], 3)
	defender = state.unit_in("kingsvale")
	Helpers.order(state, state.unit_in("greywater"), "attack", "kingsvale")
	Helpers.resolve_faction(state, "blue")
	t.check(not state.units.has(defender) and int(state.kills.get("blue", 0)) == 1, "a beaten defender with no free region of its own is destroyed, and counted")

	# Mixed armies fight with every type's stats against the enemy's mix.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [], 5)
	var mixed := state.add_unit("spearmen", "blue", "greywater", 10)
	mixed.add("archers", 6)
	var riders := state.add_unit("light_cavalry", "red", "kingsvale", 12)
	riders.add("militia", 4)
	Helpers.order(state, mixed, "attack", "kingsvale")
	events = Helpers.resolve_faction(state, "blue")
	var battle: Battle = Helpers.events_of(events, "battle")[0].battle
	t.check(battle.attacker.units.size() == 2 and battle.defender.units.size() == 2 and battle.attacker.standoff.size() == 1,
		"a mixed army fights as its troops: the archers shoot from home, the spearmen go in")
	t.check(battle.counter_damage.has("spearmen>light_cavalry"), "spearmen pick out the cavalry (the counter table)")
	var lost := 0
	for type_id in state.losses.get("red", {}):
		lost += state.losses.red[type_id]
	t.check(lost > 0, "losses are spread over the enemy's types (%s)" % [state.losses.get("red", {})])


func _test_support(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue", "kingsvale": "red"}, [
		["blue", "greywater", "swordsmen", 10], ["blue", "ashford", "spearmen", 10], ["red", "kingsvale", "swordsmen", 16]], 6)
	var main: Unit = state.unit_in("greywater")
	var helper: Unit = state.unit_in("ashford")
	Helpers.plan_as(state, "blue")
	t.check(not Orders.can_support(state, helper, "kingsvale"), "with no attack ordered, there's nothing to support")
	t.check(Helpers.order(state, helper, "attack", "kingsvale", {"support": true}) != "", "and a support order is refused")
	Helpers.order(state, main, "attack", "kingsvale")
	t.check(Orders.can_support(state, helper, "kingsvale") and not Orders.can_support(state, main, "kingsvale"),
		"once another army attacks, the others can support it")
	t.check(Helpers.order(state, helper, "attack", "kingsvale", {"support": true}) == "" and state.orders[helper][0].support,
		"a support order joins that attack")
	var events := Helpers.resolve_faction(state, "blue")
	var battles := Helpers.events_of(events, "battle")
	t.check(battles.size() == 1 and battles[0].soldiers == 20 and battles[0].supports.size() == 1,
		"both armies fight the defender as one battle of 20 soldiers")
	var forecast_alone := Helpers.game({"greywater": "blue", "ashford": "blue", "kingsvale": "red"}, [
		["blue", "greywater", "swordsmen", 10], ["blue", "ashford", "spearmen", 10], ["red", "kingsvale", "swordsmen", 16]], 6)
	var one: Dictionary = forecast_alone.forecast_attack([forecast_alone.unit_in("greywater")], "kingsvale")
	var two: Dictionary = forecast_alone.forecast_attack([forecast_alone.unit_in("greywater"), forecast_alone.unit_in("ashford")], "kingsvale")
	t.check(two.wins >= one.wins, "together they win more often (%d vs %d of %d)" % [two.wins, one.wins, one.runs])


func _test_split_attacks(t) -> void:
	# Send 5 of 20; when it fails, they come back and rejoin.
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "swordsmen"], ["red", "kingsvale", "swordsmen"]], 4)
	var unit: Unit = state.unit_in("greywater")
	Helpers.order(state, unit, "attack", "kingsvale", {"soldiers": 5})
	t.check(state.orders[unit][0].size == 5, "an attack can send part of the army (5 of 20)")
	var events := Helpers.resolve_faction(state, "blue")
	var battle: Battle = Helpers.events_of(events, "battle")[0].battle
	t.check(battle.attacker.before[0][1] == 5, "only the 5 sent fight")
	t.check(state.units_in("greywater").size() == 1 and unit.soldiers() >= 15 and unit.soldiers() <= 20,
		"the detachment comes back and rejoins: one army, %d soldiers" % unit.soldiers())

	# A mixed army splits per type.
	state = Helpers.game({"greywater": "blue"}, [], 4)
	unit = state.add_unit("militia", "blue", "greywater", 8)
	unit.add("archers", 2)
	Helpers.order(state, unit, "move", "highcrag", {"troops": {"archers": 2, "militia": 3}})
	Helpers.order(state, unit, "move", "ashford", {"troops": {"militia": 4}})
	t.check(Orders.free_troops(state, unit) == {"militia": 1}, "each order takes so many of each type; 1 militia is left")
	Helpers.resolve(state)
	t.check(state.unit_in("highcrag").composition() == {"militia": 3, "archers": 2} and state.unit_in("ashford").composition() == {"militia": 4}
		and unit.composition() == {"militia": 1}, "the detachments march off with their types")

	# A detachment that takes the region stays there; the rest stay home.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "heavy_cavalry"], ["red", "kingsvale", "militia", 2]], 4)
	unit = state.unit_in("greywater")
	Helpers.order(state, unit, "attack", "kingsvale", {"soldiers": 12})
	Helpers.resolve_faction(state, "blue")
	t.check(state.owners.kingsvale == "blue" and unit.province == "greywater" and unit.soldiers() == 8
		and state.unit_in("kingsvale") != null and state.unit_in("kingsvale").type_id == "heavy_cavalry",
		"a detachment that wins keeps the region; 8 stay at home")


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
		"infantry gets one step: a second click replaces a whole-army order")
	Orders.cancel(state, foot)
	Helpers.resolve(state)
	t.check(horse.province == "redfield" and state.owners.kingsvale == "blue" and state.owners.redfield == "blue",
		"cavalry rides 2 regions in one turn, capturing both")

	state = Helpers.game({"greywater": "blue"}, [], 2)
	var mixed := state.add_unit("light_cavalry", "blue", "greywater", 6)
	mixed.add("spearmen", 6)
	Helpers.order(state, mixed, "move", "kingsvale")
	t.check(Orders.chain_index(state, mixed) < 0, "a detachment with foot soldiers gets one step")
	Orders.cancel(state, mixed)
	Helpers.order(state, mixed, "move", "kingsvale", {"troops": {"light_cavalry": 6}})
	t.check(Orders.chain_index(state, mixed) == 0, "a detachment of its riders alone may ride on")

	state = Helpers.game({"greywater": "blue", "redfield": "red"}, [["blue", "greywater", "heavy_cavalry"], ["red", "redfield", "militia", 4]], 2)
	horse = state.unit_in("greywater")
	Helpers.order(state, horse, "move", "kingsvale")
	t.check(Helpers.order(state, horse, "attack", "redfield") == "", "cavalry can move and then attack")
	Helpers.resolve_faction(state, "blue")
	t.check(state.owners.redfield == "blue", "and win the region it attacked after moving")


func _test_ranged(t) -> void:
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "archers"], ["red", "kingsvale", "spearmen", 1]], 5)
	var archers: Unit = state.unit_in("greywater")
	Helpers.order(state, archers, "attack", "kingsvale")
	var events := Helpers.resolve_faction(state, "blue")
	t.check(Helpers.events_of(events, "volley").size() == 1 and archers.province == "greywater", "archers shoot from their own region")
	t.check(state.owners.kingsvale == "red" and state.unit_in("kingsvale") != null, "a ranged attack never captures a region or destroys an army")
	t.check(archers.health() == 1.0, "melee defenders can't shoot back")
	state = Helpers.game({"greywater": "blue", "redfield": "red"}, [["blue", "greywater", "archers"], ["red", "redfield", "militia"]])
	t.check(Orders.problem(state, state.unit_in("greywater"), "attack", "redfield") == "out of range", "archers reach only neighbouring regions")
	state = Helpers.game({"greywater": "blue", "redfield": "red"}, [["red", "redfield", "militia"]], 5, {"blue_civ": "anglish"})
	var mixed := state.add_unit("longbowman", "blue", "greywater", 6)
	mixed.add("yeoman", 10)
	Helpers.plan_as(state, "blue")
	t.check(Orders.available(state, mixed, "redfield", "attack") == {"longbowman": 6}, "only longbows can reach 2 regions away")
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "mamluk"], ["red", "kingsvale", "archers"]], 5, {"blue_civ": "saracen"})
	Helpers.order(state, state.unit_in("greywater"), "attack", "kingsvale")
	Helpers.resolve_faction(state, "blue")
	t.check(state.unit_in("greywater").health() == 1.0, "mamluks shoot and ride off: archers can't shoot back")


func _test_faction_turns(t) -> void:
	var state := Helpers.game({"greywater": "blue", "eastwold": "red"}, [["blue", "greywater", "spearmen"], ["red", "eastwold", "spearmen"]])
	var blue: Unit = state.unit_in("greywater")
	var red: Unit = state.unit_in("eastwold")
	Orders.give(state, blue, "move", "ashford")
	t.check(Orders.problem(state, red, "move", "highcrag") == "not your army to command", "only the faction whose turn it is gives orders")
	state.end_faction_turn()
	t.check(blue.province == "ashford" and state.current_faction() == "red" and state.turn == 1,
		"pressing the hourglass resolves only that faction's orders; then it's the next faction's turn")
	Orders.give(state, red, "move", "highcrag")
	state.end_faction_turn()
	t.check(red.province == "highcrag" and state.turn == 2 and state.season() == "Summer" and state.current_faction() == "blue",
		"after the last faction, turn 2 begins")
	t.check(state.orders.is_empty(), "orders are gone once resolved")

	# The AI and humans in hotseat take their turns one after another.
	var scenario := Skirmish.build("heartlands", [{"civ": "norse", "human": true}, {"civ": "anglish", "human": true}, {"civ": "frankish"}], "hard", 5)
	var game := GameState.from_scenario(scenario, 5)
	var first: Unit = game.units_of("norse")[0]
	var target := ""
	for neighbour in game.map.neighbours(first.province):
		if target == "" and Orders.problem(game, first, "move", neighbour) == "":
			target = neighbour
			if game.unit_in(neighbour) != null:
				game.remove_unit(game.unit_in(neighbour))  # Make room, so the march shows.
	Orders.give(game, first, "move", target)
	game.end_faction_turn()
	t.check(first.province == target and game.current_faction() == "anglish", "the first human's orders play out before the second plans (%s to %s)" % [first.province, target])
	game.end_faction_turn()
	AI.play_turn(game)
	var ai_orders := game.orders.keys().filter(func(u: Unit): return u.owner == "frankish").size()
	game.end_faction_turn()
	t.check(ai_orders > 0 and game.turn == 2 and game.current_faction() == "norse", "then the computer plans and plays its turn (%d orders)" % ai_orders)


func _test_determinism(t) -> void:
	var setup := func() -> GameState:
		var game := Helpers.game({"greywater": "blue", "ashford": "blue", "kingsvale": "red", "highcrag": "red"}, [
			["blue", "greywater", "swordsmen"], ["blue", "ashford", "archers"], ["red", "kingsvale", "spearmen"], ["red", "highcrag", "light_cavalry"]], 21)
		Helpers.order(game, game.unit_in("greywater"), "attack", "kingsvale")
		Helpers.order(game, game.unit_in("ashford"), "attack", "kingsvale")
		Helpers.resolve_faction(game, "blue")
		AI.play_turn(game)
		Helpers.resolve_faction(game, "red")
		return game
	t.check(JSON.stringify(SaveGame.to_dict(setup.call())) == JSON.stringify(SaveGame.to_dict(setup.call())),
		"the same orders with the same seed give the same result")


func _test_healing_and_recruits(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue"}, [["blue", "greywater", "spearmen", 10], ["blue", "ashford", "spearmen", 10]])
	for unit in state.units:
		unit.troops[0].wound(unit.troops[0].soldier_hp() * 3.0)
	Helpers.order(state, state.unit_in("ashford"), "move", "northmarch")
	Helpers.resolve(state)
	var rested := state.unit_in("greywater")
	var marched := state.unit_in("northmarch")
	t.check(rested.soldiers() == 10 and rested.health() > marched.health(), "a resting army heals its health (%d%% vs %d%%), not its soldiers" % [
		roundi(rested.health() * 100), roundi(marched.health() * 100)])

	state = Helpers.game({"greywater": "blue"}, [["blue", "greywater", "spearmen", 10]], 7,
		{"resources": {"blue": {"gold": 1000}}, "capitals": {"blue": "greywater"}})
	Helpers.plan_as(state, "blue")
	t.check(Economy.buy(state, "greywater", Economy.bundle_of(state, "blue", "archers", true)), "you can order reinforcements of another type for your army")
	t.check(state.unit_in("greywater").composition() == {"spearmen": 10}, "they don't arrive this turn")
	Helpers.resolve(state)
	t.check(state.unit_in("greywater").composition() == {"spearmen": 10, "archers": 10}, "next turn they join the army there")
