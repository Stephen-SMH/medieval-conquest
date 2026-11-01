class_name Rules
extends RefCounted
## Game rules loaded from the .tres files under data/: terrains, unit types
## and the counter table. Loaded once and shared.

const TERRAIN_DIR := "res://data/terrains"
const UNIT_DIR := "res://data/units"
const COUNTERS_PATH := "res://data/counters.tres"

static var terrains := {}  # terrain id -> TerrainType
static var units := {}     # unit type id -> UnitType, in display order
static var counters: CounterTable

static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	terrains = _load_dir(TERRAIN_DIR)
	var unsorted := _load_dir(UNIT_DIR)
	var unit_ids := unsorted.keys()
	unit_ids.sort_custom(func(a, b): return unsorted[a].order < unsorted[b].order)
	for id in unit_ids:
		units[id] = unsorted[id]
	counters = load(COUNTERS_PATH)
	_loaded = true


static func unit(id: String) -> UnitType:
	return units[id]


## Loads every resource in a folder into a dictionary keyed by its `id`.
static func _load_dir(path: String) -> Dictionary:
	var result := {}
	for file in ResourceLoader.list_directory(path):
		if file.ends_with(".tres"):
			var resource: Resource = load(path.path_join(file))
			result[resource.get("id")] = resource
	return result
