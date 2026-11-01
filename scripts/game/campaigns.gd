class_name Campaigns
extends RefCounted
## The campaigns in data/campaigns/ (PRD CP-1): one per open civilization,
## each a list of mission scenarios.

const CAMPAIGN_DIR := "res://data/campaigns"

static var _cache := {}


## Every campaign, ordered like the civilizations.
static func all() -> Array:
	if _cache.is_empty():
		for file in DirAccess.get_files_at(CAMPAIGN_DIR):
			if file.ends_with(".json"):
				var data = JSON.parse_string(FileAccess.get_file_as_string(CAMPAIGN_DIR.path_join(file)))
				if data is Dictionary:
					_cache[data.id] = data
	Rules.ensure_loaded()
	var list := _cache.values()
	list.sort_custom(func(a, b): return Rules.civilization(a.civ).order < Rules.civilization(b.civ).order)
	return list


static func get_campaign(id: String) -> Dictionary:
	all()
	return _cache.get(id, {})


## A mission's scenario, ready for GameState.from_scenario().
static func mission(campaign_id: String, index: int) -> Dictionary:
	return get_campaign(campaign_id).missions[index].duplicate(true)
