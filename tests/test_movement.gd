extends RefCounted
## M2: armies, pathfinding, movement points, zone of control, merge and split.


func run(t) -> void:
	var map := MapData.load_default()
	var state := GameState.new_game(map, 1)

	var field_armies := {}
	for army in state.armies:
		if not army.is_garrison():
			field_armies[army.owner] = true
	t.check(field_armies.size() == 4, "each of the 4 factions starts with a field army")

	var player_army := state.armies_in("greywater")[0]
	t.check(player_army.max_movement() == 2, "movement points are the lowest speed (spearmen 2, light cavalry 4)")

	var path := state.find_path("greywater", "stonehelm")
	t.check(path == (["kingsvale", "redfield", "stonehelm"] as Array[String]),
		"A* takes the cheapest route by move cost (roads, then the river) %s" % [path])
	var turns := state.path_turns(player_army, path)
	t.check(turns == ([0, 0, 1] as Array[int]), "turns needed: 2 road steps this turn, the river into hills next turn %s" % [turns])
	t.check(state.find_path("greywater", "greywater").is_empty(), "a path to where you stand is empty")

	var garrison := state.armies_in("kingsvale")[0]
	var refused := state.order_move(garrison, "highcrag")
	t.check(garrison.is_garrison() and refused[0].type == "cannot_move" and garrison.province == "kingsvale",
		"a garrison without a general can't leave its province")

	var blocked := state.order_move(player_army, "kingsvale")
	t.check(player_army.province == "greywater" and blocked.back().type == "blocked",
		"moving into an enemy army stops before it (battles come in M3)")

	player_army.reset_movement()
	var events := state.order_move(player_army, "saltmere")
	t.check(player_army.province == "ashford" and events.back().type == "zone_of_control" and player_army.movement_left == 0,
		"zone of control: entering Ashford, next to the Kingsvale garrison, stops the march")

	# Multi-turn march on an empty map: Northmarch -> Greywater (1) -> Highcrag (mountains 3).
	state.armies.clear()
	var marcher := state.add_army("aldmere", "northmarch", General.new("Test"), ["spearmen", "swordsmen"])
	state.order_move(marcher, "highcrag")
	t.check(marcher.province == "greywater" and marcher.path == (["highcrag"] as Array[String]) and marcher.movement_left == 1,
		"a march stops when the next step costs more than the points left")
	state.end_turn()
	t.check(state.turn == 2 and state.season() == "Summer", "ending the turn advances to turn 2, summer")
	t.check(marcher.province == "highcrag" and marcher.path.is_empty(),
		"next turn the army keeps marching; full points can always enter one province")

	var slow := state.add_army("aldmere", "greywater", General.new("Slow"), ["spearmen", "catapult"])
	t.check(slow.max_movement() == 1, "a catapult slows the whole army to 1")
	t.check(state.path_turns(slow, state.find_path("greywater", "highcrag")) == ([0] as Array[int]),
		"an army with full points can enter terrain costing more than its speed")

	# Merge and split.
	var big := state.add_army("aldmere", "ashford", General.new("Big"),
		["spearmen", "spearmen", "swordsmen", "archers", "archers", "light_cavalry", "militia"])
	var count := state.armies.size()
	var split_off := state.split(big, [0, 5])
	t.check(split_off != null and split_off.regiments.size() == 2 and big.regiments.size() == 5 and not split_off.is_garrison(),
		"splitting 2 regiments makes a new army with its own general")
	t.check(split_off.max_movement() == 2 and state.armies.size() == count + 1, "the split army moves at its own slowest speed")
	t.check(state.split(big, [0, 1, 2, 3, 4]) == null, "a split must leave at least one regiment behind")
	t.check(state.merge(big, split_off) and big.regiments.size() == 7 and state.armies.size() == count,
		"merging puts the regiments back and removes the other army")
	var full := state.add_army("aldmere", "ashford", General.new("Full"), ["militia", "militia", "militia", "militia", "militia", "militia"])
	t.check(not state.can_merge(big, full), "armies can't merge past 12 regiments")
	var other_place := state.add_army("aldmere", "northmarch", General.new("Far"), ["militia"])
	t.check(not state.can_merge(big, other_place), "armies in different provinces can't merge")

	var garrison2 := state.add_army("aldmere", "ashford", null, ["militia"])
	state.appoint_general(garrison2)
	t.check(garrison2.can_move(), "appointing a general lets a garrison march")

	# Fog of war.
	var fresh := GameState.new_game(map, 1)
	var seen := fresh.visible_provinces("aldmere")
	t.check(seen.has("kingsvale") and seen.has("highcrag") and seen.has("saltmere") and not seen.has("stonehelm") and not seen.has("eastwold"),
		"Aldmere sees its own provinces and their neighbours only")
