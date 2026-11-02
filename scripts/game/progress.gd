class_name Progress
extends RefCounted
## Campaign progress kept between games in user://progress.json: each
## mission's best crown (kept as "stars": 3 gold, 2 silver, 1 bronze), score
## and development points, which missions are won and open (CP-4), which
## civilizations are unlocked by finishing campaigns (8.5), each campaign's
## Forge upgrades (G), and the player's rank from their total score (H).

const PATH := "user://progress.json"
## Ranks by total score, lowest first: [name, score needed].
const RANKS := [["Serf", 0], ["Peasant", 500], ["Militiaman", 1200], ["Man-at-arms", 2000], ["Sergeant", 3000],
	["Squire", 4500], ["Knight", 6500], ["Baron", 9000], ["Count", 12000], ["Duke", 16000], ["King", 21000]]

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
	var data := _load()
	return not data.get("stars", {}).is_empty() or not data.get("won", {}).is_empty()


## Whether a mission has been won (with or without a crown).
static func won(campaign_id: String, index: int) -> bool:
	var key := "%s/%d" % [campaign_id, index]
	var data := _load()
	return data.get("won", {}).has(key) or int(data.stars.get(key, 0)) > 0


## Keeps the best result of a won mission: its crown, the development points
## and the score it earned (replaying a mission only adds what it beats).
static func record(campaign_id: String, index: int, crown: int, points := 0, score := 0) -> void:
	var data := _load()
	var key := "%s/%d" % [campaign_id, index]
	data.stars[key] = maxi(int(data.stars.get(key, 0)), crown)
	for field in ["won", "development", "score"]:
		if not data.has(field):
			data[field] = {}
	data.won[key] = true
	data.development[key] = maxi(int(data.development.get(key, 0)), points)
	data.score[key] = maxi(int(data.score.get(key, 0)), score)
	_store(data)


## The best scores of every mission added up.
static func total_score() -> int:
	var total := 0
	var scores: Dictionary = _load().get("score", {})
	for key in scores:
		total += int(scores[key])
	return total


## The rank a total score earns: {"name", "index", "next" (the next rank's
## name, "" at the top), "progress" (0-1 of the way to it)}.
static func rank(score: int) -> Dictionary:
	var index := 0
	for i in RANKS.size():
		if score >= int(RANKS[i][1]):
			index = i
	if index == RANKS.size() - 1:
		return {"name": RANKS[index][0], "index": index, "next": "", "progress": 1.0}
	var low: int = RANKS[index][1]
	var high: int = RANKS[index + 1][1]
	return {"name": RANKS[index][0], "index": index, "next": RANKS[index + 1][0], "progress": float(score - low) / (high - low)}


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
	return index == 0 or won(campaign_id, index - 1)


## A campaign opens with its civilization.
static func campaign_unlocked(campaign_id: String) -> bool:
	var campaign := Campaigns.get_campaign(campaign_id)
	return not campaign.is_empty() and civilization_unlocked(campaign.civ)


static func campaign_finished(campaign_id: String) -> bool:
	var campaign := Campaigns.get_campaign(campaign_id)
	if campaign.is_empty():
		return false
	for i in campaign.missions.size():
		if not won(campaign_id, i):
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
