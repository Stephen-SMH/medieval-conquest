class_name Progress
extends RefCounted
## Campaign progress kept between games in user://progress.json: stars per
## mission, which missions are open (CP-4), and which civilizations are
## unlocked by finishing campaigns (8.5).

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


## Keeps the best result for a mission.
static func record(campaign_id: String, index: int, earned: int) -> void:
	var data := _load()
	var key := "%s/%d" % [campaign_id, index]
	data.stars[key] = maxi(int(data.stars.get(key, 0)), earned)
	_store(data)


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
