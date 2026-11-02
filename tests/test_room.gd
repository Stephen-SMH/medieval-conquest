extends RefCounted
## A region holds at most Unit.CAP (20) soldiers, as in S&T: an order into a
## region gets only the room left by the army there (less those ordered out)
## and the soldiers already ordered in. Supporters and archer volleys don't go
## in, attacks resolve before moves, and no region ever ends a turn over the cap.

const Helpers := preload("res://tests/helpers.gd")


func run(t) -> void:
	_test_full_region(t)
	_test_ordered_out(t)
	_test_shared_room(t)
	_test_attackers_come_home_first(t)
	_test_supporters_stay_home(t)
	_test_archers_need_no_room(t)
	_test_ai_and_starts(t)


func _test_full_region(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue"}, [["blue", "greywater", "swordsmen", 20], ["blue", "ashford", "spearmen", 10]])
	var mover: Unit = state.unit_in("ashford")
	Helpers.plan_as(state, "blue")
	t.check(Unit.CAP == 20 and Orders.room(state, "blue", "greywater") == 0, "a region holds 20 soldiers at most: Greywater's 20 leave no room")
	t.check(Orders.problem(state, mover, "move", "greywater").contains("full") and Orders.reachable(state, mover).get("greywater") == "blocked",
		"so another army can't march in (the region shows as blocked)")
	t.check(Helpers.order(state, mover, "move", "greywater") != "" and not state.orders.has(mover), "and the order is refused")


func _test_ordered_out(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue"}, [["blue", "greywater", "swordsmen", 20], ["blue", "ashford", "spearmen", 10]])
	var home: Unit = state.unit_in("greywater")
	var mover: Unit = state.unit_in("ashford")
	Helpers.order(state, home, "move", "highcrag", {"soldiers": 8})
	t.check(Orders.room(state, "blue", "greywater") == 8, "8 of the 20 ordered out leave room for 8")
	t.check(Helpers.order(state, mover, "move", "greywater") == "" and Orders.orders_of(state, mover)[0].size == 8 and Orders.unassigned(state, mover) == 2,
		"a march of 10 into Greywater takes only the 8 who fit; 2 stay home")
	t.check(Orders.room_for(state, mover, "greywater") == 8, "re-opening that order offers its own 8 again")
	Helpers.resolve(state)
	t.check(state.unit_in("greywater").soldiers() == 20 and state.unit_in("highcrag").soldiers() == 8 and state.unit_in("ashford").soldiers() == 2,
		"after the turn: Greywater 12 + 8 = 20, Highcrag 8, Ashford 2")


func _test_shared_room(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue", "northmarch": "blue"}, [
		["blue", "greywater", "swordsmen", 15], ["blue", "northmarch", "spearmen", 10], ["blue", "ashford", "archers", 10]])
	var first: Unit = state.unit_in("northmarch")
	var second: Unit = state.unit_in("ashford")
	Helpers.order(state, first, "move", "greywater")
	t.check(Orders.orders_of(state, first)[0].size == 5 and Orders.room(state, "blue", "greywater") == 0,
		"15 in Greywater leave room for 5: Northmarch sends 5 and fills it")
	t.check(Helpers.order(state, second, "move", "greywater") != "", "soldiers already ordered in count: Ashford's march is refused")
	t.check(Helpers.order(state, first, "move", "greywater", {"soldiers": 3}) == "" and Orders.orders_of(state, first)[0].size == 3
		and Orders.room(state, "blue", "greywater") == 2, "an order changed to 3 frees 2 places")
	t.check(Helpers.order(state, second, "move", "greywater") == "" and Orders.orders_of(state, second)[0].size == 2, "which the next army may take")


func _test_attackers_come_home_first(t) -> void:
	# 10 of Greywater's 20 militia attack strong swordsmen and are beaten back;
	# Ashford's 10 spearmen were ordered into their places.
	var ok := true
	var merged_after_battle := true
	for game_seed in 6:
		var state := Helpers.game({"greywater": "blue", "ashford": "blue", "kingsvale": "red"}, [
			["blue", "greywater", "militia", 20], ["blue", "ashford", "spearmen", 10], ["red", "kingsvale", "swordsmen", 20]], game_seed)
		var home: Unit = state.unit_in("greywater")
		Helpers.order(state, home, "attack", "kingsvale", {"soldiers": 10})
		ok = ok and Orders.room(state, "blue", "greywater") == 10
		Helpers.order(state, state.unit_in("ashford"), "move", "greywater")
		var events := Helpers.resolve_faction(state, "blue")
		var kinds: Array = events.map(func(e): return e.type)
		if kinds.has("battle") and kinds.has("merged"):
			merged_after_battle = merged_after_battle and kinds.find("battle") < kinds.find("merged")
		for unit: Unit in state.units:
			ok = ok and unit.soldiers() <= Unit.CAP
		ok = ok and state.units_in("greywater").size() == 1
	t.check(ok, "attacking frees places too, and no region ends over 20 even when the attack fails")
	t.check(merged_after_battle, "attacks resolve before marches, so beaten attackers are home before others move in")


func _test_supporters_stay_home(t) -> void:
	var state := Helpers.game({"greywater": "blue", "ashford": "blue", "kingsvale": "red"}, [
		["blue", "greywater", "swordsmen", 16], ["blue", "ashford", "spearmen", 12], ["red", "kingsvale", "militia", 4]], 3)
	var main: Unit = state.unit_in("greywater")
	var helper: Unit = state.unit_in("ashford")
	Helpers.order(state, main, "attack", "kingsvale")
	t.check(Helpers.order(state, helper, "attack", "kingsvale", {"support": true}) == "" and Orders.room(state, "blue", "ashford") == 8,
		"a support order doesn't free places at home (12 there, room for 8)")
	Helpers.resolve_faction(state, "blue")
	var holder := state.unit_in("kingsvale")
	t.check(holder != null and holder.owner == "blue" and state.units.has(helper) and helper.province == "ashford" and helper.soldiers() > 0,
		"after the win the attackers hold Kingsvale and the supporters are still home in Ashford")


func _test_archers_need_no_room(t) -> void:
	var state := Helpers.game({"greywater": "blue", "highcrag": "blue", "ashford": "blue", "kingsvale": "red"}, [
		["blue", "greywater", "swordsmen", 20], ["blue", "highcrag", "archers", 10], ["blue", "ashford", "spearmen", 10],
		["red", "kingsvale", "swordsmen", 20]])
	Helpers.order(state, state.unit_in("greywater"), "attack", "kingsvale")
	t.check(Orders.room(state, "blue", "kingsvale") == 0, "20 attackers would fill Kingsvale")
	var archers: Unit = state.unit_in("highcrag")
	t.check(Helpers.order(state, archers, "attack", "kingsvale") == "" and Orders.orders_of(state, archers)[0].size == 10,
		"archers who only shoot need no room: all 10 may shoot")
	var spears: Unit = state.unit_in("ashford")
	t.check(Helpers.order(state, spears, "attack", "kingsvale") != "", "a second plain attack has no room to go in")
	t.check(Helpers.order(state, spears, "attack", "kingsvale", {"support": true}) == "" and Orders.orders_of(state, spears)[0].size == 10,
		"but it may support with everyone")


func _test_ai_and_starts(t) -> void:
	var over := []
	for scenario in Scenarios.all():
		var state := GameState.from_scenario(scenario, 1)
		for unit: Unit in state.units:
			if unit.soldiers() > Unit.CAP:
				over.append("%s %s %d" % [scenario.id, unit.province, unit.soldiers()])
	for campaign in Campaigns.all():
		for i in campaign.missions.size():
			var state := GameState.from_scenario(Campaigns.mission(campaign.id, i), 1)
			for unit: Unit in state.units:
				if unit.soldiers() > Unit.CAP:
					over.append("%s/%d %s %d" % [campaign.id, i, unit.province, unit.soldiers()])
	t.check(over.is_empty(), "no scenario or campaign starts with an army over 20 %s" % [over])

	var crowded := []
	for scenario in Scenarios.all().slice(0, 3):
		var state := GameState.from_scenario(scenario, 2)
		for step in 6 * state.turn_order.size():
			if state.is_over():
				break
			if not state.factions[state.current_faction()].human:
				AI.play_turn(state)
				for region in state.map.province_order:
					if Orders.room(state, state.current_faction(), region) < 0:
						crowded.append("%s turn %d %s planned" % [scenario.id, state.turn, region])
			state.end_faction_turn()
			for unit: Unit in state.units:
				if unit.soldiers() > Unit.CAP:
					crowded.append("%s turn %d %s %d" % [scenario.id, state.turn, unit.province, unit.soldiers()])
	t.check(crowded.is_empty(), "the AI never fills a region past 20 %s" % [crowded])
