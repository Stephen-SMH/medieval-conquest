class_name Progress
extends RefCounted
## Campaign progress kept between games in user://progress.json: stars per
## mission, which missions are open (CP-4), which civilizations are unlocked
## by finishing campaigns (8.5), and each campaign's development points and
## Forge upgrades (G).

const PATH := "user://progress.json"

## Where progress is stored; tests point this somewhere else.
static var path := PATH


static func _load() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"stars": {}}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {"stars": {}}


static func _store(data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))


static func stars(campaign_id: String, index: int) -> int:
	return int(_load().stars.get("%s/%d" % [campaign_id, index], 0))


## True once any mission has been finished.
static func any_progress() -> bool:
	return not _load().get("stars", {}).is_empty()


## Keeps the best result for a mission: its stars and the development
## points it earned (replaying a mission only adds what it beats).
static func record(campaign_id: String, index: int, earned: int, points := 0) -> void:
	var data := _load()
	var key := "%s/%d" % [campaign_id, index]
	data.stars[key] = maxi(int(data.stars.get(key, 0)), earned)
	if not data.has("development"):
		data.development = {}
	data.development[key] = maxi(int(data.development.get(key, 0)), points)
	_store(data)


## The development points a mission has earned at best.
static func mission_points(campaign_id: String, index: int) -> int:
	return int(_load().get("development", {}).get("%s/%d" % [campaign_id, index], 0))


## Development points a campaign's missions have earned, less what the Forge spent.
static func development_points(campaign_id: String) -> int:
	var total := 0
	var development: Dictionary = _load().get("development", {})
	for key in development:
		if key.begins_with(campaign_id + "/"):
			total += int(development[key])
	return total - Forge.spent(upgrades(campaign_id))


## A campaign's Forge upgrades: {family: {stat: level}}.
static func upgrades(campaign_id: String) -> Dictionary:
	return Forge.normalized(_load().get("forge", {}).get(campaign_id, {}))


## Buys the next level of a line's stat with the campaign's development points.
static func buy_upgrade(campaign_id: String, family: String, stat: String) -> bool:
	var owned := upgrades(campaign_id)
	if Forge.problem(owned, family, stat, development_points(campaign_id)) != "":
		return false
	Forge.raise(owned, family, stat)
	var data := _load()
	if not data.has("forge"):
		data.forge = {}
	data.forge[campaign_id] = owned
	_store(data)
	return true


## Missions open in order: the first, then each one after a finished mission.
## A locked civilization's campaign stays shut until it is unlocked (8.5).
static func mission_unlocked(campaign_id: String, index: int) -> bool:
	if not campaign_unlocked(campaign_id):
		return false
	return index == 0 or stars(campaign_id, index - 1) > 0


## A campaign opens with its civilization.
static func campaign_unlocked(campaign_id: String) -> bool:
	var campaign := Campaigns.get_campaign(campaign_id)
	return not campaign.is_empty() and civilization_unlocked(campaign.civ)


static func campaign_finished(campaign_id: String) -> bool:
	var campaign := Campaigns.get_campaign(campaign_id)
	if campaign.is_empty():
		return false
	for i in campaign.missions.size():
		if stars(campaign_id, i) == 0:
			return false
	return true


static func campaigns_finished() -> int:
	var count := 0
	for campaign in Campaigns.all():
		if campaign_finished(campaign.id):
			count += 1
	return count


static func civilization_unlocked(civ_id: String) -> bool:
	var civ := Rules.civilization(civ_id)
	return civ != null and campaigns_finished() >= civ.unlock_after_campaigns


static func reset() -> void:
	_store({"stars": {}})
