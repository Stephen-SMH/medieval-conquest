extends RefCounted
## M1: the province map data is consistent and picking works.


func run(t) -> void:
	var map := MapData.load_default()

	t.check(map.province_order.size() == 10, "the map has 10 provinces (got %d)" % map.province_order.size())

	var bad_terrain := []
	var bad_owner := []
	for id in map.province_order:
		if not Rules.terrains.has(map.provinces[id].terrain):
			bad_terrain.append(id)
		if not map.factions.has(map.provinces[id].owner):
			bad_owner.append(id)
	t.check(bad_terrain.is_empty(), "every province has a known terrain %s" % [bad_terrain])
	t.check(bad_owner.is_empty(), "every province has a known owner %s" % [bad_owner])

	var asymmetric := []
	for id in map.province_order:
		for other in map.neighbours(id):
			if not map.provinces.has(other) or other == id or not map.are_neighbours(other, id):
				asymmetric.append("%s->%s" % [id, other])
	t.check(asymmetric.is_empty(), "neighbour lists are symmetric %s" % [asymmetric])

	# Neighbours must be exactly the provinces that share a border edge.
	var mismatched := []
	for a in map.province_order:
		for b in map.province_order:
			if a < b and map.are_neighbours(a, b) != not map.shared_edges(a, b).is_empty():
				mismatched.append("%s|%s" % [a, b])
	t.check(mismatched.is_empty(), "neighbour lists match the shared borders %s" % [mismatched])

	var bad_borders := []
	for key in map.borders:
		var pair: PackedStringArray = key.split("|")
		if not map.are_neighbours(pair[0], pair[1]) or not (map.borders[key] in ["river", "road"]):
			bad_borders.append(key)
	t.check(bad_borders.is_empty(), "rivers and roads are only between neighbours %s" % [bad_borders])

	var mispicked := []
	for id in map.province_order:
		var picked := map.province_at(map.provinces[id].centroid)
		if picked != id:
			mispicked.append("%s picked %s" % [id, picked])
	t.check(mispicked.is_empty(), "clicking each province's centre picks that province %s" % [mispicked])
	t.check(map.province_at(Vector2(-50, -50)) == "", "clicking off the map picks nothing")

	# No gaps or overlaps: the province areas add up to the map's area.
	var total := 0.0
	for id in map.province_order:
		total += MapData.polygon_area(map.provinces[id].polygon)
	var map_area := map.size.x * map.size.y
	t.check(absf(total - map_area) < map_area * 0.001, "provinces tile the map (%.0f of %.0f)" % [total, map_area])

	t.check(map.move_cost("greywater", "ashford") == 1, "a road lowers the move cost (plains 1, min 1)")
	t.check(map.move_cost("kingsvale", "thornwood") == 3, "a river raises the move cost (forest 2 + 1)")
	t.check(map.move_cost("greywater", "highcrag") == 3, "mountains cost 3")

	var capitals := {}
	for id in map.province_order:
		if map.provinces[id].capital:
			capitals[map.provinces[id].owner] = capitals.get(map.provinces[id].owner, 0) + 1
	var one_capital_each := capitals.size() == map.factions.size()
	for count in capitals.values():
		one_capital_each = one_capital_each and count == 1
	t.check(one_capital_each, "each faction has exactly one capital")

	var missing_actions := []
	for action in ["pan_left", "pan_right", "pan_up", "pan_down", "zoom_in", "zoom_out",
			"map_mode_political", "map_mode_terrain", "map_mode_resources", "deselect"]:
		if not InputMap.has_action(action):
			missing_actions.append(action)
	t.check(missing_actions.is_empty(), "input actions are defined %s" % [missing_actions])
