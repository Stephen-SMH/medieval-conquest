class_name Forge
extends RefCounted
## The Forge between campaign missions (PRD G), as in S&T: the score a
## campaign's missions earned buys upgrade cards, laid out in rows that are
## bought from left to right. On the military tab each row upgrades one kind
## of soldier (infantry, archers, cavalry, engines) and each card makes it
## 10% better at attack, defense or health. On the economy tab each card
## makes the Forge's own prices, reinforcements or the treasury's income 5%
## better. Upgrades belong to a campaign (Progress keeps {row: cards bought}
## and what was spent) and go into each of its missions as the player's
## GameState.upgrades; a soldier type whose row has a card shows a ★.

const BONUS := 0.1  # A military card's bonus.
const ECONOMY_BONUS := 0.05  # An economy card's.
const STATS := ["attack", "defense", "health"]
## The rows of each tab. A row's cards are [name, effect, sketch]: the effect
## is a stat on the military tab, and "prices" (the Forge's), "income" or
## "reinforcements" (their price) on the economy tab. The sketch names the
## drawing on the card (ForgeCard).
const TABS := {
	"military": [
		{"id": "infantry", "families": ["pitchfork", "spears", "shield"], "cards": [
			["Field Training", "defense", "tent"], ["Drill", "attack", "men"], ["Swordsmanship", "attack", "swords"],
			["Mail Gauntlets", "defense", "fist"], ["Winter Quarters", "health", "tents"], ["Brothers in Arms", "health", "hands"]]},
		{"id": "archers", "families": ["bow", "crossbow"], "cards": [
			["Reorganization", "defense", "bow"], ["Volley Drill", "attack", "archers"], ["Keen Eyes", "attack", "eye"],
			["Bracers", "defense", "fist"], ["Heavy Draw", "attack", "draw"], ["Brothers in Arms", "health", "hands"]]},
		{"id": "cavalry", "families": ["horse"], "cards": [
			["War Saddles", "defense", "saddle"], ["Remounts", "health", "horses"], ["Destriers", "attack", "horse"],
			["Mail Gauntlets", "defense", "fist"], ["Breakthrough", "attack", "charge"], ["Brothers in Arms", "health", "hands"]]},
		{"id": "engines", "families": ["siege"], "cards": [
			["Carpenters", "health", "saw"], ["Counterweights", "attack", "trebuchet"], ["Mantlets", "defense", "palisade"],
			["Siege Crews", "attack", "catapult"], ["Iron-shod Rams", "attack", "ram"], ["Brothers in Arms", "health", "hands"]]},
	],
	"economy": [
		{"id": "builders", "cards": [
			["Workshop", "prices", "house1"], ["Guild Hall", "prices", "house2"], ["Builders' Yard", "prices", "houses2"],
			["Craftsmen's Row", "prices", "houses3"], ["Town Quarter", "prices", "houses4"]]},
		{"id": "treasury", "cards": [
			["Mint", "income", "coin"], ["Tolls", "income", "coins2"], ["Markets", "income", "coins3"],
			["Tithes", "income", "purse"], ["Royal Treasury", "income", "sack"]]},
		{"id": "armouries", "cards": [
			["Swordsmith", "reinforcements", "sword1"], ["Smithy", "reinforcements", "swords2"],
			["Armoury", "reinforcements", "swords3"], ["Arsenal", "reinforcements", "swords4"],
			["Royal Armoury", "reinforcements", "shield"]]},
	],
}
## What each card costs before the economy tab's discount, by its place in its row.
const PRICES := {"military": [300, 450, 650, 900, 1200, 1500], "economy": [250, 400, 600, 850, 1150]}


static func rows(tab: String) -> Array:
	return TABS[tab]


static func row(row_id: String) -> Dictionary:
	for tab in TABS:
		for entry in TABS[tab]:
			if entry.id == row_id:
				return entry
	return {}


static func tab_of(row_id: String) -> String:
	for tab in TABS:
		if TABS[tab].any(func(entry): return entry.id == row_id):
			return tab
	return ""


## The military row that upgrades a line of soldiers (a TypeIcons family).
static func row_of(family: String) -> String:
	for entry in TABS.military:
		if family in entry.families:
			return entry.id
	return ""


## How many of a row's cards are bought.
static func bought(upgrades: Dictionary, row_id: String) -> int:
	return int(upgrades.get(row_id, 0))


## Cards bought, across every row, that have this effect.
static func count(upgrades: Dictionary, effect: String) -> int:
	var total := 0
	for row_id in upgrades:
		var cards: Array = row(row_id).get("cards", [])
		for i in mini(bought(upgrades, row_id), cards.size()):
			if cards[i][1] == effect:
				total += 1
	return total


## What a card costs now: its price, less 5% for each builders' card bought,
## rounded to tens.
static func price(upgrades: Dictionary, row_id: String, index: int) -> int:
	var base: int = PRICES[tab_of(row_id)][index]
	return int(roundf(base * (1.0 - ECONOMY_BONUS * count(upgrades, "prices")) / 10.0) * 10)


## The line under the cards: "Field Training (infantry lvl.2): defense bonus",
## or what an economy card does.
static func describe(row_id: String, index: int) -> String:
	var card: Array = row(row_id).cards[index]
	match card[1]:
		"prices":
			return "Upgrade costs decreased by 5%"
		"income":
			return "5% more gold per turn"
		"reinforcements":
			return "Reinforcement costs decreased by 5%"
	return "%s (%s lvl.%d): %s bonus" % [card[0], row_id, index + 2, card[1]]


## "" if the card can be bought with `points`, else why not.
static func problem(upgrades: Dictionary, row_id: String, index: int, points: int) -> String:
	var done := bought(upgrades, row_id)
	if index < done:
		return "already bought"
	if index > done:
		return "the card before it comes first"
	if points < price(upgrades, row_id, index):
		return "needs %d points" % price(upgrades, row_id, index)
	return ""


## Buys a row's next card in `upgrades` (the caller pays).
static func raise(upgrades: Dictionary, row_id: String) -> void:
	upgrades[row_id] = bought(upgrades, row_id) + 1


## Upgrades read back from JSON: {row: cards bought}, whole numbers, known
## rows only (older saves kept {line: {stat: level}}, which no longer counts).
static func normalized(upgrades: Dictionary) -> Dictionary:
	var result := {}
	for row_id in upgrades:
		var value = upgrades[row_id]
		if tab_of(row_id) != "" and (value is float or value is int) and int(value) > 0:
			result[row_id] = mini(int(value), row(row_id).cards.size())
	return result


## A row's bonus to one stat: 10% for each of its cards bought that has it.
static func multiplier(upgrades: Dictionary, row_id: String, stat: String) -> float:
	var cards: Array = row(row_id).get("cards", [])
	var levels := 0
	for i in mini(bought(upgrades, row_id), cards.size()):
		if cards[i][1] == stat:
			levels += 1
	return 1.0 + BONUS * levels


## Gives a troop its faction's upgrades before a battle.
static func apply(upgrades: Dictionary, troop: Troop) -> void:
	var row_id := row_of(TypeIcons.family(troop.type_id))
	troop.attack_mod *= multiplier(upgrades, row_id, "attack")
	troop.defense_mod *= multiplier(upgrades, row_id, "defense")
	troop.toughness *= multiplier(upgrades, row_id, "health")


## The treasury's income, times this.
static func income(upgrades: Dictionary) -> float:
	return 1.0 + ECONOMY_BONUS * count(upgrades, "income")


## Reinforcements' price, times this.
static func reinforcements(upgrades: Dictionary) -> float:
	return 1.0 - ECONOMY_BONUS * count(upgrades, "reinforcements")


## A mission scenario with the campaign's upgrades given to its player.
static func equip(scenario: Dictionary, upgrades: Dictionary) -> Dictionary:
	var player: String = scenario.get("mission", {}).get("player", "")
	if player != "" and not upgrades.is_empty():
		scenario["upgrades"] = {player: upgrades.duplicate(true)}
	return scenario
