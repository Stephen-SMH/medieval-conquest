extends RefCounted
## The real-history maps (made by tools/make_real_maps.py): 30-60 regions with
## unique names, income of 5, 10 or 15, sea links between ports, every region
## reachable by land or sea, a historical start that loads, and names that
## don't sit on top of each other.

const REAL_MAPS := ["british_isles", "france", "scandinavia", "levant", "holy_roman_empire", "livonia"]


func run(t) -> void:
	for map_id in REAL_MAPS:
		t.check(MapData.list_maps().has(map_id), "%s is offered as a map" % map_id)
		var data = JSON.parse_string(FileAccess.get_file_as_string(MapData.MAP_DIR.path_join(map_id + ".json")))
		_check_map(t, MapData.load_map(map_id), data)


func _check_map(t, map: MapData, data: Dictionary) -> void:
	var name := map.id
	var count := map.province_order.size()
	t.check(count >= 30 and count <= 60, "%s: %d regions (30-60)" % [name, count])

	var names := {}
	var bad_income := []
	for region in map.province_order:
		names[map.region_name(region)] = true
		if not [5, 10, 15].has(int(map.provinces[region].get("income", 0))):
			bad_income.append(region)
	t.check(names.size() == count, "%s: region names are unique" % name)
	t.check(bad_income.is_empty(), "%s: every region pays 5, 10 or 15 gold %s" % [name, bad_income])

	# Sea links join two different ports that both have a boat.
	var bad_links := []
	var seen := {}
	for link in data.get("sea_links", []):
		var a: String = link[0]
		var b: String = link[1]
		var ok: bool = a != b and map.provinces.has(a) and map.provinces.has(b) and not seen.has(MapData.border_key(a, b))
		if ok:
			for region in [a, b]:
				var province: Dictionary = map.provinces[region]
				ok = ok and province.coastal and province.get("port", false) and province.has("port_at") \
					and map.province_at(Vector2(province.port_at[0], province.port_at[1])) == ""
		seen[MapData.border_key(a, b)] = true
		if not ok:
			bad_links.append("%s-%s" % [a, b])
	t.check(bad_links.is_empty(), "%s: sea links join ports, with boats on the water %s" % [name, bad_links])

	# No orphans: everything is reachable over land and sea links.
	var graph := {}
	for region in map.province_order:
		graph[region] = map.neighbours(region).duplicate()
	for link in data.get("sea_links", []):
		graph[link[0]].append(link[1])
		graph[link[1]].append(link[0])
	var reached := {map.province_order[0]: true}
	var frontier := [map.province_order[0]]
	while not frontier.is_empty():
		var current: String = frontier.pop_back()
		for next in graph[current]:
			if not reached.has(next):
				reached[next] = true
				frontier.append(next)
	t.check(reached.size() == count, "%s: every region can be reached by land or sea (%d of %d)" % [name, reached.size(), count])
	var islands := map.province_order.filter(func(r): return map.neighbours(r).is_empty() and not graph[r].is_empty())
	t.check(map.province_order.all(func(r): return not graph[r].is_empty()), "%s: no region is cut off (islands %s)" % [name, islands])

	# Neighbouring regions don't overlap.
	var overlaps := []
	for a in map.province_order:
		for b in map.neighbours(a):
			if a < b:
				var shared := 0.0
				for piece in Geometry2D.intersect_polygons(map.provinces[a].polygon, map.provinces[b].polygon):
					shared += MapData.polygon_area(piece)
				if shared > 50.0:
					overlaps.append("%s|%s %d" % [a, b, shared])
	t.check(overlaps.is_empty(), "%s: neighbouring regions don't overlap %s" % [name, overlaps])

	# Names are readable: no two region names overlap.
	var crowded := []
	for a in map.province_order:
		for b in map.province_order:
			if a < b and _name_box(map, a).intersects(_name_box(map, b)):
				crowded.append("%s/%s" % [a, b])
	t.check(crowded.is_empty(), "%s: region names don't overlap %s" % [name, crowded])

	# The historical start loads: every region has an owner, every faction its capital.
	var history: Dictionary = data.history
	var scenario := {"id": "history_" + name, "map": name, "factions": history.factions, "owners": history.owners,
		"capitals": history.capitals, "buildings": history.buildings, "units": []}
	var state := GameState.from_scenario(scenario, 1)
	var problems := []
	for region in map.province_order:
		var owner: String = history.owners.get(region, "")
		if not (state.factions.has(owner) or GameState.NON_PLAYABLE.has(owner)):
			problems.append(region)
	for faction in history.capitals:
		if history.owners[history.capitals[faction]] != faction:
			problems.append(faction)
	t.check(problems.is_empty() and state.factions.size() == history.factions.size(),
		"%s: the %d start (%s) gives every region an owner and every faction its capital %s" % [name, history.year, history.title, problems])
	t.check(map.starts.size() >= 4, "%s: four start regions for skirmish" % name)


## The name plus the gold line under it.
func _name_box(map: MapData, region: String) -> Rect2:
	var label := OrdersLayer.name_rect(map, region)
	return Rect2(label.position + Vector2(4, 2), label.size - Vector2(8, 4))
