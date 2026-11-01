class_name Rules
extends RefCounted
## Game rules loaded from the .tres files under data/: terrains and, later,
## unit types, counters and buildings. Loaded once and shared.

const TERRAIN_DIR := "res://data/terrains"

static var terrains := {}  # terrain id -> TerrainType

static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	terrains = _load_dir(TERRAIN_DIR)
	_loaded = true


## Loads every resource in a folder into a dictionary keyed by its `id`.
static func _load_dir(path: String) -> Dictionary:
	var result := {}
	for file in ResourceLoader.list_directory(path):
		if file.ends_with(".tres"):
			var resource: Resource = load(path.path_join(file))
			result[resource.get("id")] = resource
	return result
