class_name Forge
extends RefCounted
## The Forge between campaign missions (PRD G), which replaces research:
## development points earned in missions buy permanent upgrades for a line of
## soldiers (the TypeIcons families: militia, spearmen, men-at-arms, archers,
## crossbowmen, cavalry, engines). Each line has three upgrades, attack,
## defense and health, up to level 3, each level adding 10%. A level costs 1,
## 2, then 3 points. Upgrades belong to a campaign (kept by Progress) and go
## into each of its missions as the player's GameState.upgrades; a line with
## any upgrade shows a ★ on its icon.

const STATS := ["attack", "defense", "health"]
const STAT_NAMES := {"attack": "Attack", "defense": "Defense", "health": "Health"}
const MAX_LEVEL := 3
const BONUS := 0.1  # Per level.


## Points the next level costs, from `level`: 1, then 2, then 3.
static func cost(level: int) -> int:
	return level + 1


static func level(upgrades: Dictionary, family: String, stat: String) -> int:
	return int(upgrades.get(family, {}).get(stat, 0))


## Points spent on a set of upgrades: {family: {stat: level}}.
static func spent(upgrades: Dictionary) -> int:
	var total := 0
	for family in upgrades:
		for stat in upgrades[family]:
			for done in int(upgrades[family][stat]):
				total += cost(done)
	return total


## "" if the next level of a line's stat can be bought with `points`, else why not.
static func problem(upgrades: Dictionary, family: String, stat: String, points: int) -> String:
	var now := level(upgrades, family, stat)
	if now >= MAX_LEVEL:
		return "fully upgraded"
	if points < cost(now):
		return "needs %d point%s" % [cost(now), "" if cost(now) == 1 else "s"]
	return ""


## Upgrades read back from JSON, with whole-number levels: {family: {stat: level}}.
static func normalized(upgrades: Dictionary) -> Dictionary:
	var result := {}
	for family in upgrades:
		result[family] = {}
		for stat in upgrades[family]:
			result[family][stat] = int(upgrades[family][stat])
	return result


## Raises a line's stat by a level in `upgrades` (the caller pays).
static func raise(upgrades: Dictionary, family: String, stat: String) -> void:
	if not upgrades.has(family):
		upgrades[family] = {}
	upgrades[family][stat] = level(upgrades, family, stat) + 1


## The lines a civilization fields, in icon order.
static func families(civ: String) -> Array:
	Rules.ensure_loaded()
	var found := {}
	for unit_id in Rules.units:
		var unit_type := Rules.unit(unit_id)
		if unit_type.civilization == "" or unit_type.civilization == civ:
			found[TypeIcons.family(unit_id)] = true
	return TypeIcons.FAMILIES.filter(func(family): return found.has(family))


## Gives a troop its faction's upgrades before a battle.
static func apply(upgrades: Dictionary, troop: Troop) -> void:
	var lines: Dictionary = upgrades.get(TypeIcons.family(troop.type_id), {})
	troop.attack_mod *= 1.0 + BONUS * int(lines.get("attack", 0))
	troop.defense_mod *= 1.0 + BONUS * int(lines.get("defense", 0))
	troop.toughness *= 1.0 + BONUS * int(lines.get("health", 0))


## A mission scenario with the campaign's upgrades given to its player.
static func equip(scenario: Dictionary, upgrades: Dictionary) -> Dictionary:
	var player: String = scenario.get("mission", {}).get("player", "")
	if player != "" and not upgrades.is_empty():
		scenario["upgrades"] = {player: upgrades.duplicate(true)}
	return scenario
