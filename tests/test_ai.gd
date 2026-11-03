extends RefCounted
## The computer's play and the difficulty levels (AI.SKILL): gathered attacks
## with supports, attacks carried out before the marches, several empty
## regions taken at once, a guard left at home, and what easy and hard change.
## Heartlands: greywater borders northmarch, highcrag, ashford and kingsvale;
## kingsvale borders greywater, highcrag, ashford, thornwood and redfield.

const Helpers := preload("res://tests/helpers.gd")


func run(t) -> void:
	_test_gathered_attack(t)
	_test_waves(t)
	_test_captures(t)
	_test_home_guard(t)
	_test_difficulty(t)


## Two armies that would each lose alone attack together: one attacks, the other supports.
func _test_gathered_attack(t) -> void:
	var setup := func(level: String) -> GameState:
		var game := Helpers.game({"greywater": "blue", "kingsvale": "red", "highcrag": "red", "stonehelm": "blue"}, [
			["blue", "greywater", "swordsmen", 14], ["red", "kingsvale", "swordsmen", 10], ["red", "highcrag", "swordsmen", 10],
			["blue", "stonehelm", "militia", 5]], 7)
		game.set_difficulty(level)
		Helpers.plan_as(game, "red")
		return game
	var state: GameState = setup.call("normal")
	var a := state.unit_in("kingsvale")
	var b := state.unit_in("highcrag")
	t.check(state.forecast_attack([a], "greywater", 8).rating == "Decisive loss" and state.forecast_attack([a, b], "greywater", 8).rating in AI.ACCEPT.balanced,
		"alone either army loses; together they win")
	AI.plan_attacks(state)
	var orders := Orders.orders_of(state, a) + Orders.orders_of(state, b)
	t.check(orders.size() == 2 and orders.all(func(o): return o.steps[0].target == "greywater") and orders.filter(func(o): return o.support).size() == 1,
		"on normal they gather: one attacks Greywater and the other supports (%s | %s)" % [Orders.describe(state, a), Orders.describe(state, b)])
	state = setup.call("easy")
	AI.plan_attacks(state)
	t.check(not state.orders.keys().any(func(u: Unit): return u.owner == "red" and Orders.orders_of(state, u).any(func(o): return o.steps[0].type == "attack")),
		"on easy each army thinks alone and nobody attacks")


## Normal and hard carry out their attacks with the "!" before planning the marches.
func _test_waves(t) -> void:
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red", "redfield": "red", "stonehelm": "blue"}, [
		["blue", "greywater", "militia", 6], ["red", "kingsvale", "heavy_cavalry"], ["red", "redfield", "spearmen", 8],
		["blue", "stonehelm", "militia", 5]], 7)
	Helpers.plan_as(state, "red")
	var events := AI.play_turn(state)
	t.check(not Helpers.events_of(events, "battle").is_empty() and state.owners.greywater == "red" and state.turn == 1 and state.current_faction() == "red",
		"the attack on Greywater is carried out at once, and the turn goes on")
	t.check(state.unit_in("greywater").tired() > 0 and not state.orders.has(state.unit_in("greywater")), "the winners are tired and get no more orders")

	state = Helpers.game({"greywater": "blue", "kingsvale": "red", "stonehelm": "blue"}, [
		["blue", "greywater", "militia", 6], ["red", "kingsvale", "heavy_cavalry"], ["blue", "stonehelm", "militia", 5]], 7)
	state.set_difficulty("easy")
	Helpers.plan_as(state, "red")
	t.check(AI.play_turn(state).is_empty() and state.has_orders() and state.owners.greywater == "blue",
		"on easy nothing happens until the hourglass: the orders wait")


## Normal splits an army to take every empty region next to it; easy takes one.
func _test_captures(t) -> void:
	for level in ["normal", "easy"]:
		var state := Helpers.game({"kingsvale": "red", "eastwold": "blue"}, [["red", "kingsvale", "militia", 10], ["blue", "eastwold", "militia", 5]], 7)
		state.set_difficulty(level)
		Helpers.plan_as(state, "red")
		AI.play_turn(state)
		state.end_faction_turn()
		var held := state.map.province_order.filter(func(r): return state.owners[r] == "red")
		if level == "normal":
			t.check(held.size() >= 4 and state.units_of("red").all(func(u: Unit): return u.soldiers() >= 1),
				"normal splits Kingsvale's 10 to take %d empty regions in one turn (%s)" % [held.size() - 1, held])
		else:
			t.check(held.size() == 2, "easy takes one (%s)" % [held])


## An attacker leaves a guard at home when another enemy army could walk in.
func _test_home_guard(t) -> void:
	var state := Helpers.game({"greywater": "blue", "highcrag": "red", "eastwold": "blue"}, [
		["blue", "greywater", "militia", 3], ["red", "highcrag", "swordsmen", 16], ["blue", "eastwold", "militia", 6]], 7)
	Helpers.plan_as(state, "red")
	var army := state.unit_in("highcrag")
	AI.plan_attacks(state)
	var attack: Array = Orders.orders_of(state, army).filter(func(o): return o.steps[0].type == "attack")
	t.check(not attack.is_empty() and Orders.unassigned(state, army) >= 2,
		"Highcrag attacks and keeps %d at home against Eastwold (%s)" % [Orders.unassigned(state, army), Orders.describe(state, army)])


func _test_difficulty(t) -> void:
	var scenario := {
		"id": "test", "map": "heartlands",
		"factions": [{"id": "blue", "name": "Blue", "color": "#3d6fb6", "human": true}, {"id": "red", "name": "Red", "color": "#b5423a", "human": false}],
		"owners": {"greywater": "blue", "kingsvale": "red", "redfield": "red"}, "capitals": {}, "buildings": {}, "resources": {},
		"units": [{"owner": "blue", "region": "greywater", "type": "militia", "soldiers": 8}, {"owner": "red", "region": "kingsvale", "type": "militia", "soldiers": 8},
			{"owner": "red", "region": "redfield", "type": "militia", "soldiers": 18}],
	}
	var normal := GameState.from_scenario(scenario, 3)
	scenario.difficulty = "hard"
	var hard := GameState.from_scenario(scenario, 3)
	t.check(hard.difficulty == "hard" and hard.unit_in("kingsvale").soldiers() == 10 and hard.unit_in("redfield").soldiers() == 20
		and hard.unit_in("greywater").soldiers() == 8, "on hard the computer's armies start a quarter stronger, 20 at most; yours don't")
	hard.set_difficulty("hard")
	t.check(hard.unit_in("kingsvale").soldiers() == 10, "only once")
	t.check(Economy.deltas(hard, "red").gold > Economy.deltas(normal, "red").gold and Economy.deltas(hard, "blue").gold == Economy.deltas(normal, "blue").gold,
		"hard's computer earns more gold (%+d against %+d); you earn the same" % [Economy.deltas(hard, "red").gold, Economy.deltas(normal, "red").gold])
	var easy := GameState.from_scenario(scenario.merged({"difficulty": "easy"}, true), 3)
	t.check(Economy.deltas(easy, "red").gold < Economy.deltas(normal, "red").gold, "easy's earns less")
	var loaded := SaveGame.from_dict(JSON.parse_string(JSON.stringify(SaveGame.to_dict(hard))))
	t.check(loaded.difficulty == "hard" and loaded.unit_in("kingsvale").soldiers() == 10, "a save keeps the difficulty")
	loaded.set_difficulty("hard")
	t.check(loaded.unit_in("kingsvale").soldiers() == 10, "and a loaded game isn't strengthened again")
