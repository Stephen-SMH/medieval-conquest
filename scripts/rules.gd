class_name Rules
extends RefCounted
## Game rules loaded from the .tres files under data/: terrains, unit types,
## the counter table, buildings and civilizations. Loaded once and shared.

const TERRAIN_DIR := "res://data/terrains"
const UNIT_DIR := "res://data/units"
const COUNTERS_PATH := "res://data/counters.tres"
const BUILDING_DIR := "res://data/buildings"
const CIVILIZATION_DIR := "res://data/civilizations"

static var terrains := {}  # terrain id -> TerrainType
static var units := {}     # unit type id -> UnitType, in display order
static var counters: CounterTable
static var buildings := {}  # building id -> BuildingType, in display order
static var civilizations := {}  # civilization id -> Civilization, in display order

static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	terrains = _load_dir(TERRAIN_DIR)
	units = _sorted(_load_dir(UNIT_DIR))
	buildings = _sorted(_load_dir(BUILDING_DIR))
	civilizations = _sorted(_load_dir(CIVILIZATION_DIR))
	counters = load(COUNTERS_PATH)
	_loaded = true


static func unit(id: String) -> UnitType:
	return units[id]


static func building(id: String) -> BuildingType:
	return buildings[id]


static func civilization(id: String) -> Civilization:
	return civilizations.get(id)


static func tech_name(id: String) -> String:
	return id.capitalize()


## The same dictionary, re-inserted in the resources' `order`.
static func _sorted(by_id: Dictionary) -> Dictionary:
	var ids := by_id.keys()
	ids.sort_custom(func(a, b): return by_id[a].order < by_id[b].order)
	var result := {}
	for id in ids:
		result[id] = by_id[id]
	return result


## Loads every resource in a folder into a dictionary keyed by its `id`.
static func _load_dir(path: String) -> Dictionary:
	var result := {}
	for file in ResourceLoader.list_directory(path):
		if file.ends_with(".tres"):
			var resource: Resource = load(path.path_join(file))
			result[resource.get("id")] = resource
	return result
