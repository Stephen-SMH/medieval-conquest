extends RefCounted
## Every map is consistent (shapes, neighbours, borders, picking) and every
## scenario fits its map.


func run(t) -> void:
	var maps := MapData.list_maps()
	t.check(not maps.is_empty(), "maps found: %s" % [maps])
	for map_id in maps:
		_check_map(t, MapData.load_map(map_id))

	var scenario := (load("res://scripts/session.gd") as GDScript).call("load_scenario", "heartlands") as Dictionary
	_check_scenario(t, scenario)

	var missing_actions := []
	for action in ["pan_left", "pan_right", "pan_up", "pan_down", "zoom_in", "zoom_out", "map_mode_political",
			"map_mode_terrain", "map_mode_resources", "deselect", "end_turn", "undo"]:
		if not InputMap.has_action(action):
			missing_actions.append(action)
	t.check(missing_actions.is_empty(), "input actions are defined %s" % [missing_actions])


func _check_map(t, map: MapData) -> void:
	var name := map.id
	var bad := []
	for region in map.province_order:
		if not Rules.terrains.has(map.provinces[region].terrain):
			bad.append(region)
		for other in map.neighbours(region):
			if not map.provinces.has(other) or other == region or not map.are_neighbours(other, region):
				bad.append("%s->%s" % [region, other])
	t.check(bad.is_empty(), "%s: terrains known, neighbours symmetric %s" % [name, bad])

	var mismatched := []
	for a in map.province_order:
		for b in map.province_order:
			var by_land := map.are_neighbours(a, b) and map.border_type(a, b) != "sea"
			if a < b and by_land != not map.shared_edges(a, b).is_empty():
				mismatched.append("%s|%s" % [a, b])
	t.check(mismatched.is_empty(), "%s: neighbours are exactly the regions sharing a border %s" % [name, mismatched])

	var mispicked := []
	var total := 0.0
	for region in map.province_order:
		if map.province_at(map.provinces[region].centroid) != region:
			mispicked.append(region)
		total += MapData.polygon_area(map.provinces[region].polygon)
	t.check(mispicked.is_empty(), "%s: clicking each region's centre picks it %s" % [name, mispicked])
	if MapDecor.map_extras(map).is_empty():
		t.check(absf(total - map.size.x * map.size.y) < map.size.x * map.size.y * 0.001, "%s: regions tile the map with no gaps" % name)
	else:
		# Real geography has sea and scenery between the regions.
		t.check(total < map.size.x * map.size.y, "%s: regions fit inside the map" % name)

	var bad_borders := []
	for key in map.borders:
		var pair: PackedStringArray = key.split("|")
		if not map.are_neighbours(pair[0], pair[1]):
			bad_borders.append(key)
	t.check(bad_borders.is_empty(), "%s: rivers and roads only between neighbours %s" % [name, bad_borders])
	t.check(map.starts.size() >= 2 and map.starts.all(func(r): return map.provinces.has(r)), "%s: start regions exist %s" % [name, map.starts])
	# Real-geography maps have islands reached by sea links; test_real_maps checks those.
	if MapDecor.map_extras(map).is_empty():
		var reachable := map.distances_from(map.province_order[0]).size()
		t.check(reachable == map.province_order.size(), "%s: every region can be reached (%d regions)" % [name, reachable])


func _check_scenario(t, scenario: Dictionary) -> void:
	var state := GameState.from_scenario(scenario, 1)
	var problems := []
	for region in state.owners:
		var owner: String = state.owners[region]
		if not (state.factions.has(owner) or GameState.NON_PLAYABLE.has(owner)):
			problems.append("%s owned by %s" % [region, owner])
	for faction in state.capitals:
		if state.owners[state.capitals[faction]] != faction:
			problems.append("%s doesn't own its capital" % faction)
	for region in state.map.province_order:
		for faction in state.factions:
			if state.space_in(region, faction) < 0:
				problems.append("%s has more than 4 %s units" % [region, faction])
	t.check(problems.is_empty(), "scenario %s: owners, capitals and stacks are valid %s" % [scenario.id, problems])
