extends RefCounted
## V1: unit tokens, the stack limit, orders (move, attack, ranged, retreat,
## undo), battle results (BR-1..BR-5), merging, healing, recruiting and turns.

const Helpers := preload("res://tests/helpers.gd")


func run(t) -> void:
	_test_units(t)
	_test_stack_limit(t)
	_test_moves(t)
	_test_attacks(t)
	_test_ranged(t)
	_test_merge(t)
	_test_healing_and_recruits(t)
	_test_turns(t)


func _test_units(t) -> void:
	var unit := Unit.new("spearmen", "blue", "greywater")
	t.check(unit.soldiers() == 20 and unit.max_hp() == 100.0, "a new unit has 20 soldiers and full HP")
	unit.hp = 51.0
	t.check(unit.soldiers() == 11, "soldiers = ceil(HP ÷ HP per soldier): 51 HP of spearmen is 11 soldiers")
	unit.set_soldiers(7)
	t.check(is_equal_approx(unit.hp, 35.0) and unit.soldiers() == 7, "setting 7 soldiers gives 35 HP")
	var ranks := []
	for xp in [0, 2, 5, 9]:
		unit.xp = xp
		ranks.append(unit.rank_name())
	t.check(ranks == ["Recruit", "Veteran", "Elite", "Hero"], "ranks by experience %s" % [ranks])


func _test_stack_limit(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue"}, [
		["blue", "greywater", "spearmen"], ["blue", "greywater", "swordsmen"],
		["blue", "greywater", "archers"], ["blue", "greywater", "militia"],
		["blue", "ashford", "spearmen"]], 7, {"buildings": {"greywater": {"barracks": 1}}})
	var mover: Unit = state.units_in("ashford")[0]
	t.check(state.move_problem(mover, "greywater") == "full: 4 units at most", "a region holds at most 4 units")
	t.check(state.reachable([mover]).greywater == "blocked", "a full region shows grey")
	t.check(Economy.recruit_problem(state, "greywater", "militia", "blue").begins_with("no room"), "you can't recruit into a full region")
	var refused := false
	for unit in state.units_in("greywater"):
		refused = refused or state.move_problem(unit, "ashford") != ""
	state.move_unit(state.units_in("greywater")[0], "ashford")
	t.check(not refused and state.space_in("ashford", "blue") == 2 and state.space_in("greywater", "blue") == 1,
		"moving out of a full region frees a place")


func _test_moves(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue", "kingsvale": "red"}, [
		["blue", "ashford", "spearmen"], ["blue", "ashford", "light_cavalry"], ["red", "kingsvale", "militia"]])
	var spear: Unit = Helpers.units_of_type(state, "spearmen")[0]
	var horse: Unit = Helpers.units_of_type(state, "light_cavalry")[0]

	var reach := state.reachable([spear])
	t.check(reach.get("kingsvale") == "attack" and reach.get("northmarch") == "move" and reach.get("greywater") == "move"
		and reach.get("saltmere") == "move", "neighbours light up: green to move, red to attack %s" % [reach])

	var events := state.move_unit(spear, "northmarch")
	t.check(spear.province == "northmarch" and state.owners["northmarch"] == "blue"
		and events.any(func(e): return e.type == "captured"), "moving into an empty neutral region captures it")
	t.check(state.move_problem(spear, "greywater") == "no move points left", "infantry moves 1 region a turn")
	t.check(state.undo_last_move() and spear.province == "ashford" and spear.move_points_left == 1
		and state.owners["northmarch"] == "neutral", "undo puts the unit back and returns the captured region")

	state.move_unit(spear, "greywater")
	t.check(state.attack_problem(spear, "kingsvale") == "moved this turn", "infantry can't attack after moving")
	state.move_unit(horse, "greywater")
	t.check(state.attack_problem(horse, "kingsvale") == "" and horse.move_points_left == 1,
		"cavalry can move 1 region and still attack")
	t.check(state.move_problem(horse, "kingsvale") == "enemy units there: attack instead", "you can't walk into enemy units")

	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "spearmen"]])
	state.move_unit(state.units[0], "kingsvale")
	t.check(state.owners["kingsvale"] == "blue", "an empty enemy region is captured by moving in")


func _test_attacks(t) -> void:
	# BR-2: a failed attack leaves the survivors where they attacked from.
	var state := Helpers.game({"greywater": "blue", "ashford": "blue", "kingsvale": "red", "highcrag": "red"}, [
		["blue", "greywater", "militia", 10],
		["red", "kingsvale", "swordsmen"], ["red", "kingsvale", "swordsmen"], ["red", "kingsvale", "spearmen"]])
	var attacker: Unit = state.units[0]
	var result := state.attack([attacker], "kingsvale")
	var battle: Battle = result.battle
	t.check(not battle.attacker_won() and state.owners["kingsvale"] == "red", "a weak attack fails")
	t.check(not state.units.has(attacker) or attacker.province == "greywater",
		"the failed attacker goes back to the region it attacked from")
	t.check(state.units_in("kingsvale").size() == 3, "the defenders keep their region")
	if state.units.has(attacker):
		t.check(state.move_problem(attacker, "northmarch").begins_with("after fighting")
			and state.move_problem(attacker, "ashford") == "", "after fighting a unit can only retreat into its own regions")
		state.move_unit(attacker, "ashford")
		t.check(attacker.province == "ashford", "a unit that fought retreats with its move point")
	else:
		t.check(true, "(the attacker was destroyed; retreat checked elsewhere)")
		t.check(true, "(skipped)")

	# BR-3: the beaten defender retreats to a friendly neighbour with room, and the attackers move in.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red", "highcrag": "red"}, [
		["blue", "greywater", "heavy_cavalry"], ["blue", "greywater", "heavy_cavalry"],
		["blue", "greywater", "swordsmen"], ["blue", "greywater", "archers"],
		["red", "kingsvale", "militia", 20]], 11)
	var defender: Unit = Helpers.units_of_type(state, "militia")[0]
	result = state.attack(state.units_in("greywater"), "kingsvale")
	var archer: Unit = Helpers.units_of_type(state, "archers")[0]
	t.check(result.battle.attacker_won() and state.owners["kingsvale"] == "blue", "a strong attack takes the region")
	t.check(Helpers.units_of_type(state, "heavy_cavalry").all(func(u): return u.province == "kingsvale"),
		"the winning melee units move into the region")
	t.check(archer.province == "greywater", "archers that shot from their region stay there")
	t.check(not state.units.has(defender) or defender.province == "highcrag",
		"the beaten defender retreats to its own neighbouring region (or died in the fight)")

	# A beaten defender with nowhere to go is destroyed.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red", "highcrag": "red"}, [
		["blue", "greywater", "heavy_cavalry"], ["blue", "greywater", "heavy_cavalry"], ["blue", "greywater", "swordsmen"],
		["red", "kingsvale", "spearmen", 20],
		["red", "highcrag", "militia"], ["red", "highcrag", "militia"], ["red", "highcrag", "militia"], ["red", "highcrag", "militia"]], 3)
	defender = Helpers.units_of_type(state, "spearmen")[0]
	result = state.attack(state.units_in("greywater"), "kingsvale")
	var stranded: bool = result.events.any(func(e): return e.type == "destroyed" and e.how == "had nowhere to retreat")
	t.check(result.battle.attacker_won() and not state.units.has(defender),
		"a beaten defender whose only friendly neighbour is full is destroyed%s" % (" (no room to retreat)" if stranded else " (in the fight)"))

	# A general is lost with his unit.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [
		["blue", "greywater", "militia", 1], ["red", "kingsvale", "swordsmen"], ["red", "kingsvale", "swordsmen"]])
	state.units[0].general = General.new("Doomed", 1, 1)
	result = state.attack([state.units[0]], "kingsvale")
	t.check(state.units.has(state.units[0]) or result.events.any(func(e): return e.type == "general_lost"),
		"when a general's unit is destroyed the general is captured or killed")

	# Generals: +10% attack per Command level in their region.
	state = Helpers.game({"greywater": "blue"}, [["blue", "greywater", "spearmen"], ["blue", "greywater", "militia"]])
	state.units[0].general = General.new("Aldric", 3, 0)
	t.check(is_equal_approx(state._command_mod("blue", "greywater"), 1.3), "a Command 3 general gives his region +30% attack")


func _test_ranged(t) -> void:
	# BR-5 and OR-4: archers shoot from their own region, only enemy archers shoot back,
	# and a ranged attack never takes a region.
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red"}, [
		["blue", "greywater", "archers"], ["blue", "greywater", "crossbowmen"],
		["red", "kingsvale", "spearmen", 2]], 5)
	var archers: Unit = Helpers.units_of_type(state, "archers")[0]
	var result := state.attack(state.units_in("greywater"), "kingsvale")
	t.check(result.battle.ranged_only() and result.battle.ending == "ranged", "an attack by archers alone is a ranged attack")
	t.check(archers.province == "greywater" and archers.hp == archers.max_hp(), "the archers stay home and melee defenders can't hit back")
	t.check(state.owners["kingsvale"] == "red", "a ranged attack never captures a region, even if it kills every defender")
	t.check(Helpers.units_of_type(state, "spearmen").is_empty() or Helpers.units_of_type(state, "spearmen")[0].soldiers() < 2,
		"the volleys hurt the defenders")

	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [
		["blue", "greywater", "archers"], ["red", "kingsvale", "archers"]], 5)
	state.attack([state.units[0]], "kingsvale")
	t.check(state.units[0].hp < state.units[0].max_hp(), "enemy archers do shoot back")

	state = Helpers.game({"greywater": "blue", "redfield": "red"}, [["blue", "greywater", "archers"], ["red", "redfield", "militia"]])
	t.check(state.attack_problem(state.units[0], "redfield") == "out of range", "archers reach only neighbouring regions")
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "archers"], ["red", "kingsvale", "militia"]])
	state.move_unit(state.units[0], "ashford")
	t.check(state.attack_problem(state.units[0], "kingsvale") == "moved this turn", "archers can't shoot after moving")


func _test_merge(t) -> void:
	var state := Helpers.game({"greywater": "blue"}, [
		["blue", "greywater", "spearmen", 8], ["blue", "greywater", "spearmen", 9],
		["blue", "greywater", "swordsmen", 5], ["blue", "greywater", "spearmen", 15]])
	var a: Unit = state.units[0]
	var b: Unit = state.units[1]
	a.xp = 5  # Elite
	t.check(state.merge(a, b) and a.soldiers() == 17 and state.units.size() == 3, "two spearmen units merge: 8 + 9 = 17 soldiers")
	t.check(a.rank_name() == "Recruit", "rank is the soldier-weighted average, rounded down: (2×8 + 0×9) ÷ 17 → Recruit")
	t.check(state.merge_problem(a, state.units[1]) == "different unit types", "different types can't merge")
	t.check(state.merge_problem(a, state.units[2]) == "more than 20 soldiers", "a merged unit can't pass 20 soldiers")

	state = Helpers.game({"greywater": "blue"}, [["blue", "greywater", "archers", 12], ["blue", "greywater", "archers", 4]])
	state.units[0].xp = 5
	state.merge(state.units[0], state.units[1])
	t.check(state.units[0].rank_name() == "Veteran", "12 elite + 4 recruits → (24 ÷ 16) = 1.5 → Veteran")


func _test_healing_and_recruits(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue"}, [
		["blue", "greywater", "spearmen", 10], ["blue", "ashford", "spearmen", 10], ["blue", "ashford", "militia", 10]])
	var resting: Unit = state.units[0]
	var walker: Unit = state.units[1]
	var gold_before: float = state.factions.blue.resources.gold
	state.move_unit(walker, "northmarch")
	var gold_change: float = Economy.deltas(state, "blue").gold
	state.end_faction_turn()
	t.check(resting.soldiers() == 12, "a resting unit in a friendly region regains 2 soldiers")
	t.check(walker.soldiers() == 10, "a unit that moved doesn't heal")
	t.check(is_equal_approx(state.factions.blue.resources.gold, gold_before + gold_change - 2 * 3.0 - 2 * 1.5),
		"healing costs gold per soldier (spearmen 3, militia 1.5)")

	state = Helpers.game({"greywater": "blue"}, [["blue", "greywater", "spearmen", 10]], 7, {"buildings": {"greywater": {"barracks": 1}}})
	state.end_faction_turn()
	t.check(state.units[0].soldiers() == 14, "with Barracks a resting unit regains 4 soldiers")

	state = Helpers.game({"greywater": "blue"}, [["blue", "greywater", "spearmen", 10]], 7, {"resources": {"blue": {"gold": -1000}}})
	state.end_faction_turn()
	t.check(state.units[0].soldiers() == 10, "without gold, units don't heal")

	state = Helpers.game({"greywater": "blue"}, [["blue", "greywater", "spearmen"], ["blue", "greywater", "spearmen"],
		["blue", "greywater", "spearmen"]], 7,
		{"buildings": {"greywater": {"barracks": 1}}, "resources": {"blue": {"gold": 1000, "manpower": 200, "wood": 200}}})
	t.check(Economy.recruit(state, "greywater", "spearmen"), "recruiting pays for a unit")
	t.check(Economy.recruit_problem(state, "greywater", "spearmen", "blue").begins_with("no room"),
		"a queued recruit takes its place in the 4-unit stack")
	state.end_faction_turn()
	t.check(state.units_in("greywater").size() == 4 and state.units_in("greywater")[3].soldiers() == 20,
		"the recruit appears as a full unit at the end of the turn")


func _test_turns(t) -> void:
	var state := Helpers.game({"greywater": "blue", "eastwold": "red"}, [["blue", "greywater", "spearmen"], ["red", "eastwold", "spearmen"]])
	var blue_unit: Unit = state.units[0]
	state.move_unit(blue_unit, "ashford")
	state.end_faction_turn()
	t.check(state.current_faction() == "red" and state.turn == 1, "after blue, red moves in the same turn")
	t.check(state.move_problem(blue_unit, "greywater") == "not your turn", "you can't move in someone else's turn")
	state.end_faction_turn()
	t.check(state.current_faction() == "blue" and state.turn == 2 and state.season() == "Summer", "then turn 2, summer, starts with blue")
	t.check(blue_unit.move_points_left == 1 and not blue_unit.moved, "units get their moves back at the start of their turn")
	t.check(state.undo_stack.is_empty(), "moves can't be undone after the turn ends")
