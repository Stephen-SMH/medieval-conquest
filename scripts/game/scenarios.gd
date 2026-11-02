class_name Scenarios
extends RefCounted
## The standalone scenarios in data/scenarios/ (PRD M): each a scenario file
## with a "listing" ({"difficulty": 1-3, "order": n, "unlock_after": wins}),
## shown in the Scenarios table in order. A scenario opens once that many
## scenarios have been won.

const DIR := "res://data/scenarios"
const SIZES := [["S", 25], ["M", 45]]  # Up to this many regions; more is "L".

static var _cache := {}


## Every listed scenario, in order.
static func all() -> Array:
	if _cache.is_empty():
		for file in DirAccess.get_files_at(DIR):
			if file.ends_with(".json"):
				var data = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(file)))
				if data is Dictionary and data.has("listing"):
					_cache[data.id] = data
	var list := _cache.values()
	list.sort_custom(func(a, b): return [int(a.listing.order), a.id] < [int(b.listing.order), b.id])
	return list


static func get_scenario(id: String) -> Dictionary:
	all()
	return _cache.get(id, {}).duplicate(true)


## "S", "M" or "L" by the map's number of regions.
static func size_class(scenario: Dictionary) -> String:
	var regions := MapData.load_map(scenario.map).province_order.size()
	for entry in SIZES:
		if regions <= int(entry[1]):
			return entry[0]
	return "L"


static func unlocked(scenario: Dictionary) -> bool:
	return Progress.scenarios_won() >= int(scenario.listing.get("unlock_after", 0))
