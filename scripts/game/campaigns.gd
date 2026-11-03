class_name Campaigns
extends RefCounted
## The campaigns in data/campaigns/ (PRD CP-1), as S&T lists them: England,
## France, Crusades and Vikings, each a list of real-history mission
## scenarios (tools/make_history_campaigns.py).

const CAMPAIGN_DIR := "res://data/campaigns"

static var _cache := {}


## Every campaign, in S&T's order.
static func all() -> Array:
	if _cache.is_empty():
		for file in DirAccess.get_files_at(CAMPAIGN_DIR):
			if file.ends_with(".json"):
				var data = JSON.parse_string(FileAccess.get_file_as_string(CAMPAIGN_DIR.path_join(file)))
				if data is Dictionary:
					_cache[data.id] = data
	Rules.ensure_loaded()
	var list := _cache.values()
	list.sort_custom(func(a, b): return int(a.get("order", 99)) < int(b.get("order", 99)))
	return list


static func get_campaign(id: String) -> Dictionary:
	all()
	return _cache.get(id, {})


## A mission's scenario, ready for GameState.from_scenario().
static func mission(campaign_id: String, index: int) -> Dictionary:
	return get_campaign(campaign_id).missions[index].duplicate(true)
