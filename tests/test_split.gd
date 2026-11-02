extends RefCounted
## Splitting a unit across several orders in one turn (PRD OR-1..OR-3, BR-1):
## planning detachments with sliders, editing and cancelling them, the red X
## and the soldiers left home, and how detachments resolve: new units in empty
## regions, merges, attacks that win or fail, generals, HP, cavalry paths, the
## one-unit-per-region rule, the AI, playback events and saves.
## Heartlands: greywater borders northmarch, highcrag, ashford and kingsvale.

const Helpers := preload("res://tests/helpers.gd")


func run(t) -> void:
	_test_planning(t)
	_test_editing_and_cancelling(t)
	_test_red_x(t)
	_test_friendly_regions(t)
	_test_example_turn(t)
	_test_new_unit_keeps_hp(t)
	_test_merge(t)
	_test_attack_wins(t)
	_test_attack_fails(t)
	_test_attack_fails_home_empty(t)
	_test_home_stays_owned(t)
	_test_same_region(t)
	_test_cavalry(t)
	_test_ranged(t)
	_test_blocked_and_crowding(t)
	_test_one_per_region(t)
	_test_ai(t)
	_test_saves(t)
	_test_tutorial_cancel(t)


func _one_per_region(state: GameState) -> bool:
	var seen := {}
	for unit in state.units:
		if seen.has(unit.province):
			return false
		seen[unit.province] = true
	return true


func _test_planning(t) -> void:
	var state := Helpers.game({"greywater": "blue"}, [["blue", "greywater", "swordsmen"], ["red", "kingsvale", "militia", 4]])
	var unit: Unit = state.unit_in("greywater")
	t.check(Helpers.order(state, unit, "attack", "kingsvale", {"soldiers": 14}) == "", "a unit can send 14 of 20 to attack")
	t.check(Orders.unassigned(state, unit) == 6, "6 soldiers are left unassigned")
	t.check(Orders.total(Orders.available(state, unit, "highcrag")) == 6, "the next arrow's slider offers the 6 still free")
	t.check(Helpers.order(state, unit, "move", "highcrag", {"soldiers": 4}) == "", "and send 4 of them to march to another region")
	var list := Orders.orders_of(state, unit)
	t.check(list.size() == 2 and list[0].size == 14 and list[1].size == 4 and Orders.unassigned(state, unit) == 2,
		"two orders: 14 attack, 4 march, 2 stay home")
	t.check(Orders.describe(state, unit) == "14 attack Kingsvale; 4 march to Highcrag; 2 stay home",
		"the orders read as: %s" % Orders.describe(state, unit))
	t.check(Helpers.order(state, unit, "move", "northmarch", {"soldiers": 9}) == "" and Orders.orders_of(state, unit).back().size == 2,
		"a third arrow can take at most the 2 still free")
	t.check(Helpers.order(state, unit, "move", "ashford") == "every soldier already has orders", "with everyone sent, no more arrows")
	var reach := Orders.reachable(state, unit)
	t.check(reach.get("kingsvale") == "attack" and reach.get("highcrag") == "move" and reach.get("ashford") == "blocked",
		"the map still lights the regions with orders (to change them) and greys the rest")

	state = Helpers.game({"greywater": "blue"}, [["blue", "greywater", "swordsmen"]])
	unit = state.unit_in("greywater")
	Helpers.order(state, unit, "move", "highcrag")
	t.check(Orders.orders_of(state, unit)[0].size == 20, "a march sends every free soldier by default")
	t.check(Helpers.order(state, unit, "move", "ashford", {"soldiers": 5}) == "" and Orders.orders_of(state, unit).size() == 1
		and Orders.orders_of(state, unit)[0].steps[0].target == "ashford" and Orders.orders_of(state, unit)[0].size == 5,
		"a new arrow replaces an order that sent the whole unit")


func _test_editing_and_cancelling(t) -> void:
	var state := Helpers.game({"greywater": "blue"}, [["blue", "greywater", "swordsmen"], ["red", "kingsvale", "militia", 4]])
	var unit: Unit = state.unit_in("greywater")
	Helpers.order(state, unit, "attack", "kingsvale", {"soldiers": 14})
	Helpers.order(state, unit, "move", "highcrag", {"soldiers": 4})
	t.check(Orders.total(Orders.available(state, unit, "kingsvale")) == 16, "re-drawing to Kingsvale offers its 14 plus the 2 free")
	t.check(Helpers.order(state, unit, "attack", "kingsvale", {"soldiers": 10}) == "" and Orders.orders_of(state, unit).size() == 2
		and Orders.orders_of(state, unit)[0].size == 10 and Orders.unassigned(state, unit) == 6,
		"re-drawing to the same region edits that order's count (14 -> 10), with no second order")
	Helpers.order(state, unit, "attack", "kingsvale", {"soldiers": 30})
	t.check(Orders.orders_of(state, unit)[0].size == 16, "an edit can't take more than its own soldiers plus the free ones")
	Orders.cancel_order(state, unit, 0)
	t.check(Orders.orders_of(state, unit).size() == 1 and Orders.orders_of(state, unit)[0].steps[0].target == "highcrag"
		and Orders.unassigned(state, unit) == 16, "cancelling one arrow frees its soldiers and keeps the other order")
	Orders.cancel(state, unit)
	t.check(not state.orders.has(unit) and Orders.unassigned(state, unit) == 20, "cancel all clears every order")


func _test_red_x(t) -> void:
	var state := Helpers.game({"greywater": "blue"}, [["blue", "greywater", "swordsmen"], ["blue", "ashford", "light_cavalry"]])
	var unit: Unit = state.unit_in("greywater")
	Helpers.order(state, unit, "move", "highcrag", {"soldiers": 6})
	t.check(not Orders.is_spent(state, unit), "a partly ordered unit has no red X (14 still free)")
	Helpers.order(state, unit, "move", "kingsvale", {"soldiers": 14})
	t.check(Orders.is_spent(state, unit), "once every soldier has an order, the red X shows")
	var horse: Unit = state.unit_in("ashford")
	Helpers.order(state, horse, "move", "saltmere")
	t.check(not Orders.is_spent(state, horse), "a cavalry detachment with a step left has no red X yet")
	Helpers.order(state, horse, "move", "redfield")
	t.check(Orders.is_spent(state, horse), "after its second step it does")


func _test_friendly_regions(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue"}, [["blue", "greywater", "swordsmen"], ["blue", "ashford", "archers"]])
	var unit: Unit = state.unit_in("greywater")
	Helpers.order(state, unit, "move", "highcrag", {"soldiers": 5})
	t.check(Helpers.order(state, unit, "move", "ashford", {"soldiers": 5}) == "", "a detachment may march into your army of another type")
	Helpers.resolve(state)
	t.check(state.unit_in("ashford").composition() == {"swordsmen": 5, "archers": 20} and unit.soldiers() == 10,
		"and joins it as a mixed army (%s)" % [state.unit_in("ashford").composition()])


func _test_example_turn(t) -> void:
	var state := Helpers.game({"greywater": "blue", "highcrag": "blue"}, [["blue", "greywater", "swordsmen"], ["red", "kingsvale", "militia", 3]], 4)
	var unit: Unit = state.unit_in("greywater")
	Helpers.order(state, unit, "attack", "kingsvale", {"soldiers": 14})
	Helpers.order(state, unit, "move", "highcrag", {"soldiers": 4})
	var events := Helpers.resolve(state)
	var split: Array = Helpers.events_of(events, "split")
	t.check(split.size() == 1 and split[0].unit == unit and split[0].parts.size() == 2, "the unit splits into two detachments for playback")
	t.check(events.find(split[0]) < events.find(Helpers.events_of(events, "battle")[0]), "the split shows before the battle")
	var garrison := state.unit_in("highcrag")
	var victors := state.unit_in("kingsvale")
	t.check(unit.province == "greywater" and unit.soldiers() == 2, "2 stay home in the original unit")
	t.check(garrison != null and garrison != unit and garrison.type_id == "swordsmen" and garrison.soldiers() == 4 and garrison.owner == "blue",
		"4 swordsmen hold Highcrag as a new unit")
	t.check(victors != null and victors.owner == "blue" and victors.type_id == "swordsmen" and state.owners.kingsvale == "blue",
		"the 14 took Kingsvale and hold it as a new unit (%d left)" % (victors.soldiers() if victors != null else 0))
	t.check(_one_per_region(state), "one army per region after the turn")


func _test_new_unit_keeps_hp(t) -> void:
	var state := Helpers.game({"greywater": "blue"}, [["blue", "greywater", "spearmen"]])
	var unit: Unit = state.unit_in("greywater")
	unit.troops[0].wound(unit.troops[0].full_hp() * 0.25)  # Down to 75% health, still 20 soldiers.
	var before := unit.hp
	Helpers.order(state, unit, "move", "highcrag", {"soldiers": 6})
	Helpers.resolve_faction(state, "blue")
	var part := state.unit_in("highcrag")
	t.check(part != null and part.type_id == "spearmen", "the new army keeps its type")
	t.check(part.soldiers() == 6 and unit.soldiers() == 14, "6 march and 14 stay")
	t.check(is_equal_approx(part.hp, before * 6.0 / 20.0) and is_equal_approx(unit.hp + part.hp, before),
		"HP is shared per soldier and none is lost or made (%.1f + %.1f = %.1f)" % [unit.hp, part.hp, before])
	t.check(state.owners.highcrag == "blue", "the empty neutral region is captured")


func _test_merge(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue"}, [["blue", "greywater", "swordsmen"], ["blue", "ashford", "swordsmen", 12]])
	var unit: Unit = state.unit_in("greywater")
	var other: Unit = state.unit_in("ashford")
	t.check(Helpers.order(state, unit, "move", "ashford", {"soldiers": 20}) == "", "a detachment may march into a region held by your army")
	Helpers.resolve(state)
	t.check(other.soldiers() == 30 and unit.soldiers() == 2 and unit.province == "greywater" and _one_per_region(state),
		"it merges up to 30; the 2 who don't fit stay home")


func _test_attack_wins(t) -> void:
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "heavy_cavalry"], ["red", "kingsvale", "militia", 2]], 4)
	var unit: Unit = state.unit_in("greywater")
	Helpers.order(state, unit, "attack", "kingsvale", {"soldiers": 12})
	Helpers.order(state, unit, "move", "highcrag", {"soldiers": 5})
	Helpers.resolve(state)
	var victors := state.unit_in("kingsvale")
	t.check(state.owners.kingsvale == "blue" and victors != null and victors != unit and victors.type_id == "heavy_cavalry",
		"an attack detachment that wins occupies the region as a new unit")
	t.check(unit.soldiers() == 3 and state.unit_in("highcrag").soldiers() == 5 and _one_per_region(state), "3 home, 5 in Highcrag")


func _test_attack_fails(t) -> void:
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "swordsmen"], ["red", "kingsvale", "spearmen"]], 4)
	var unit: Unit = state.unit_in("greywater")
	Helpers.order(state, unit, "attack", "kingsvale", {"soldiers": 8})
	Helpers.order(state, unit, "move", "highcrag", {"soldiers": 4})
	var events := Helpers.resolve(state)
	t.check(not Helpers.events_of(events, "battle")[0].battle.attacker_won(), "the 8 swordsmen fail against 20 spearmen")
	var rejoined := Helpers.events_of(events, "rejoined").filter(func(e): return e.unit == unit)
	t.check(not rejoined.is_empty() and state.units_in("greywater").size() == 1 and state.unit_in("greywater") == unit,
		"the survivors return and re-merge with the home unit")
	t.check(unit.soldiers() > 8 and unit.soldiers() <= 16 and state.unit_in("highcrag").soldiers() == 4,
		"home holds 8 plus the survivors (%d); 4 hold Highcrag" % unit.soldiers())


func _test_attack_fails_home_empty(t) -> void:
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "swordsmen"], ["red", "kingsvale", "spearmen"]], 4)
	var unit: Unit = state.unit_in("greywater")
	Helpers.order(state, unit, "attack", "kingsvale", {"soldiers": 8})
	Helpers.order(state, unit, "move", "highcrag", {"soldiers": 12})
	Helpers.resolve(state)
	var home := state.unit_in("greywater")
	t.check(unit.province == "highcrag" and unit.soldiers() == 12, "the unit itself led the larger detachment to Highcrag")
	t.check(home != null and home != unit and home.owner == "blue" and state.units_in("greywater").size() == 1,
		"the failed attackers form the unit at home (%d soldiers)" % (home.soldiers() if home != null else 0))


func _test_home_stays_owned(t) -> void:
	var state := Helpers.game({"greywater": "blue"}, [["blue", "greywater", "swordsmen"]])
	var unit: Unit = state.unit_in("greywater")
	Helpers.order(state, unit, "move", "highcrag", {"soldiers": 10})
	Helpers.order(state, unit, "move", "ashford", {"soldiers": 10})
	Helpers.resolve(state)
	t.check(state.unit_in("greywater") == null and state.owners.greywater == "blue", "when every soldier leaves, the home region stays yours")
	t.check(state.unit_in("highcrag").soldiers() == 10 and state.unit_in("ashford").soldiers() == 10, "10 and 10 in the two new regions")


func _test_same_region(t) -> void:
	var state := Helpers.game({"greywater": "blue"}, [["blue", "greywater", "light_cavalry"]])
	var horse: Unit = state.unit_in("greywater")
	Helpers.order(state, horse, "move", "highcrag", {"soldiers": 10})
	t.check(Orders.problem(state, horse, "move", "highcrag") == "", "re-drawing to the same region is allowed (it edits)")
	Helpers.order(state, horse, "move", "highcrag", {"soldiers": 8})
	t.check(Orders.orders_of(state, horse).size() == 1, "so two orders never go to the same region")
	# The detachment's second step to Thornwood; a new detachment can't then head there.
	Helpers.order(state, horse, "move", "thornwood")
	t.check(Orders.orders_of(state, horse)[0].steps.size() == 2, "the cavalry detachment rides on to Thornwood")
	t.check(Orders.problem(state, horse, "move", "kingsvale") == "", "another detachment may ride to Kingsvale")
	Helpers.order(state, horse, "move", "kingsvale", {"soldiers": 6})
	t.check(Orders.problem(state, horse, "move", "thornwood", 1, "kingsvale") == "another detachment already goes there",
		"but not on to Thornwood, where the first detachment ends")
	t.check(Helpers.order(state, horse, "move", "thornwood") != "" and Orders.orders_of(state, horse)[1].steps.size() == 1,
		"so that second step is refused")
	t.check(Orders.problem(state, horse, "move", "highcrag", 1, "kingsvale") == "another detachment already goes there",
		"nor through the first detachment's waypoint")
	Helpers.resolve(state)
	t.check(_one_per_region(state) and state.unit_in("thornwood").soldiers() == 8 and state.unit_in("kingsvale").soldiers() == 6
		and horse.soldiers() == 6 and horse.province == "greywater", "8 in Thornwood, 6 in Kingsvale, 6 at home")


func _test_cavalry(t) -> void:
	var state := Helpers.game({"greywater": "blue", "redfield": "red"}, [["blue", "greywater", "heavy_cavalry"], ["red", "redfield", "militia", 3]], 2)
	var horse: Unit = state.unit_in("greywater")
	Helpers.order(state, horse, "move", "kingsvale", {"soldiers": 12})
	t.check(Orders.intent(state, horse, "redfield").get("order") == 0 and Orders.intent(state, horse, "redfield").get("type") == "attack",
		"a click next to the detachment's waypoint gives it a second step")
	t.check(Helpers.order(state, horse, "attack", "redfield") == "" and Orders.orders_of(state, horse)[0].size == 12,
		"the 12 move to Kingsvale and then attack Redfield")
	Helpers.order(state, horse, "move", "highcrag", {"soldiers": 8})
	Helpers.order(state, horse, "move", "thornwood")
	var list := Orders.orders_of(state, horse)
	t.check(list.size() == 2 and list[1].steps.size() == 2 and list[1].steps[1].target == "thornwood",
		"the second detachment gets its own two-step path, Highcrag then Thornwood")
	Helpers.resolve(state)
	t.check(state.owners.redfield == "blue" and state.owners.kingsvale == "blue" and state.owners.highcrag == "blue" and state.owners.thornwood == "blue",
		"both detachments ride two regions and capture everything they pass")
	t.check(state.unit_in("thornwood") != null and state.unit_in("thornwood").soldiers() == 8 and state.unit_in("redfield") != null
		and state.unit_in("greywater") == null and _one_per_region(state), "and each ends as its own unit")


func _test_ranged(t) -> void:
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "archers"], ["red", "kingsvale", "militia", 10]], 5)
	var archers: Unit = state.unit_in("greywater")
	Helpers.order(state, archers, "attack", "kingsvale", {"soldiers": 12})
	t.check(Orders.orders_of(state, archers)[0].size == 12 and Orders.unassigned(state, archers) == 8, "12 shoot; their order holds 12")
	Helpers.order(state, archers, "move", "highcrag", {"soldiers": 5})
	var events := Helpers.resolve(state)
	var volleys := Helpers.events_of(events, "volley")
	t.check(volleys.size() == 1 and volleys[0].soldiers == 12, "the 12 shoot")
	t.check(archers.province == "greywater" and archers.soldiers() == 15 and state.unit_in("highcrag").soldiers() == 5 and _one_per_region(state),
		"the shooters rejoin the 3 at home (15); 5 hold Highcrag")


func _test_blocked_and_crowding(t) -> void:
	# Two of your detachments heading for the same empty region join up there.
	var state := Helpers.game({"greywater": "blue", "ashford": "blue"}, [["blue", "greywater", "swordsmen"], ["blue", "ashford", "archers"]], 5)
	var unit: Unit = state.unit_in("greywater")
	Helpers.order(state, unit, "move", "northmarch", {"soldiers": 6})
	Helpers.order(state, unit, "move", "highcrag", {"soldiers": 6})
	Helpers.order(state, state.unit_in("ashford"), "move", "northmarch")
	var events := Helpers.resolve(state)
	t.check(state.unit_in("northmarch").composition() == {"swordsmen": 6, "archers": 20} and _one_per_region(state),
		"the archers and 6 swordsmen meet in Northmarch as one army (%s)" % [state.unit_in("northmarch").composition()])

	# Another unit can't merge into a unit that split this turn, so returning
	# detachments always fit (no region ends up with two units).
	state = Helpers.game({"greywater": "blue", "northmarch": "blue", "kingsvale": "red"}, [["blue", "greywater", "militia"],
		["blue", "northmarch", "militia", 10], ["red", "kingsvale", "swordsmen"]], 4)
	unit = state.unit_in("greywater")
	Helpers.order(state, unit, "attack", "kingsvale", {"soldiers": 12})
	Helpers.order(state, state.unit_in("northmarch"), "move", "greywater")
	events = Helpers.resolve_faction(state, "blue")
	t.check(not Helpers.events_of(events, "blocked").is_empty() and state.unit_in("northmarch") != null, "the merge into a splitting unit is blocked")
	t.check(_one_per_region(state) and unit.soldiers() <= 20 and events.all(func(e): return not e.get("crowded", false)),
		"the failed attackers fit back home: one unit, %d soldiers" % unit.soldiers())


## Random splits for both sides over many seeds: no region ever holds two units.
func _test_one_per_region(t) -> void:
	var broken := 0
	var crowded := 0
	var turns := 0
	for game_seed in 25:
		var scenario := Skirmish.build("heartlands", [{"civ": "norse", "human": false}, {"civ": "anglish", "human": false}, {"civ": "frankish"}], "hard", game_seed)
		var state := GameState.from_scenario(scenario, game_seed)
		var rng := RandomNumberGenerator.new()
		rng.seed = game_seed
		for turn in 6:
			if state.is_over():
				break
			for f in state.turn_order.size():
				var faction := state.current_faction()
				if f == 0:
					_random_splits(state, faction, rng)
				else:
					AI.play_turn(state)
				var events := state.end_faction_turn()
				crowded += events.filter(func(e): return e.get("crowded", false)).size()
				if state.current == 0:
					break
			turns += 1
			if not _one_per_region(state):
				broken += 1
	t.check(broken == 0 and crowded == 0, "random split orders over %d turns never leave two armies in a region (%d broken, %d fixed by the guard)" % [turns, broken, crowded])


func _random_splits(state: GameState, faction: String, rng: RandomNumberGenerator) -> void:
	for unit in state.units_of(faction):
		for attempt in 4:
			var regions := state.map.neighbours(unit.province)
			var target: String = regions[rng.randi() % regions.size()]
			var plan := Orders.intent(state, unit, target)
			if plan.is_empty():
				continue
			var free := Orders.total(Orders.available(state, unit, target))
			Orders.give(state, unit, plan.type, target, {"soldiers": rng.randi_range(1, maxi(free, 1))})
			if Orders.is_spent(state, unit):
				break


func _test_ai(t) -> void:
	# A big unit sure of its attack leaves a garrison in a threatened empty region.
	var state := Helpers.game({"kingsvale": "red", "highcrag": "red", "greywater": "blue", "eastwold": "blue"}, [
		["red", "kingsvale", "heavy_cavalry"], ["blue", "greywater", "militia", 3], ["blue", "eastwold", "militia", 4]], 7)
	Helpers.plan_as(state, "red")
	AI.play_turn(state)
	var list := Orders.orders_of(state, state.unit_in("kingsvale"))
	t.check(list.size() == 2 and list[0].steps[0].type == "attack" and list[1].steps[0].target == "highcrag" and list[1].size == 4,
		"the AI attacks with 16 and leaves 4 to hold threatened Highcrag (%s)" % Orders.describe(state, state.unit_in("kingsvale")))
	Helpers.resolve(state)
	t.check(_one_per_region(state) and state.unit_in("highcrag") != null and state.unit_in("highcrag").owner == "red", "and both orders resolve")

	# AI-only games keep running with the new orders.
	var scenario := Skirmish.build("heartlands", [{"civ": "norse"}, {"civ": "anglish"}, {"civ": "frankish"}], "hard", 9)
	var game := GameState.from_scenario(scenario, 9)
	var ok := true
	for i in 12 * game.turn_order.size():
		if game.is_over():
			break
		AI.play_turn(game)
		game.end_faction_turn()
		ok = ok and _one_per_region(game)
	t.check(ok and game.turn > 5, "AI-only games play on (turn %d) with one army per region" % game.turn)


func _test_saves(t) -> void:
	var state := Helpers.game({"greywater": "blue"}, [["blue", "greywater", "swordsmen"], ["red", "kingsvale", "militia", 4], ["blue", "ashford", "light_cavalry"]])
	var unit: Unit = state.unit_in("greywater")
	Helpers.order(state, unit, "attack", "kingsvale", {"soldiers": 14})
	Helpers.order(state, unit, "move", "highcrag", {"soldiers": 4})
	var horse: Unit = state.unit_in("ashford")
	Helpers.order(state, horse, "move", "saltmere", {"soldiers": 12})
	Helpers.order(state, horse, "move", "redfield")
	Helpers.plan_as(state, "blue")
	var saved := SaveGame.to_dict(state)
	t.check(saved.version == 6, "saves are version 6")
	var loaded := SaveGame.from_dict(JSON.parse_string(JSON.stringify(saved)))
	var loaded_unit := loaded.unit_by_id(unit.id)
	t.check(Orders.orders_of(loaded, loaded_unit).size() == 2 and Orders.unassigned(loaded, loaded_unit) == 2
		and Orders.orders_of(loaded, loaded.unit_by_id(horse.id))[0].steps.size() == 2, "a save made mid-planning keeps every order and count")
	t.check(_norm(SaveGame.to_dict(loaded)) == _norm(saved), "save -> load -> save is unchanged")
	Helpers.resolve(state)
	Helpers.resolve(loaded)
	t.check(_norm(SaveGame.to_dict(loaded)) == _norm(SaveGame.to_dict(state)), "and the loaded game resolves exactly the same")

	# A version 2 save: one order per unit.
	var old := Helpers.game({"greywater": "blue"}, [["blue", "greywater", "swordsmen"], ["red", "kingsvale", "militia", 4], ["blue", "ashford", "spearmen"]])
	var data := SaveGame.to_dict(old)
	data.version = 2
	data.orders = [{"unit": old.unit_in("greywater").id, "steps": [{"type": "attack", "target": "kingsvale"}], "soldiers": 12, "shoot": 0},
		{"unit": old.unit_in("ashford").id, "steps": [{"type": "move", "target": "saltmere"}], "soldiers": 20, "shoot": 0}]
	var converted := SaveGame.from_dict(JSON.parse_string(JSON.stringify(data)))
	var attack: Array = Orders.orders_of(converted, converted.unit_in("greywater"))
	var march: Array = Orders.orders_of(converted, converted.unit_in("ashford"))
	t.check(attack.size() == 1 and attack[0].size == 12 and attack[0].troops == {"swordsmen": 12} and march.size() == 1 and march[0].size == 20,
		"a version 2 save loads: the attack sends its 12, the march the whole unit")


## The data as JSON, after a trip through JSON (so whole numbers read back as floats compare equal).
func _norm(data: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(data)))


func _test_tutorial_cancel(t) -> void:
	var state := GameState.from_scenario(Tutorial.scenario(), 1)
	var tutorial := Tutorial.new(state.turn)
	var spears: Unit = state.units.filter(func(u): return u.type_id == "spearmen" and u.owner == Tutorial.PLAYER)[0]
	Helpers.plan_as(state, Tutorial.PLAYER)
	tutorial.update(state, spears)
	Orders.give(state, spears, "move", "fernridge", {"soldiers": 6})
	tutorial.update(state, spears)
	t.check(tutorial.current().id == "cancel" and Tutorial.STEPS[2].text.contains("arrow") and Tutorial.STEPS[2].text.contains("right-click"),
		"the cancel step explains arrows cancel one order and right-click cancels all")
	Orders.cancel_order(state, spears, 0)
	tutorial.record("cancel")
	tutorial.update(state, spears)
	t.check(tutorial.current().id == "cancel", "cancelling one arrow counts; it waits for the march again")
	Orders.give(state, spears, "move", "fernridge")
	tutorial.update(state, spears)
	t.check(tutorial.current().id == "attack", "then moves on to the attack")
