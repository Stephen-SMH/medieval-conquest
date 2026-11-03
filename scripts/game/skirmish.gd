class_name Skirmish
extends RefCounted
## Builds a skirmish or hotseat scenario (PRD CP-5, CP-6): each player starts in
## one of the map's start regions and two of its neighbours, with a unit in each
## and a capital; the other regions are independent. Win by conquest.

const DIFFICULTY := {
	"easy": {"ai": "defensive", "gold": 200.0},
	"normal": {"ai": "balanced", "gold": 300.0},
	"hard": {"ai": "aggressive", "gold": 500.0},
}


## `players` is a list of {"civ": id, "human": bool}. Returns a scenario.
static func build(map_id: String, players: Array, difficulty := "normal", game_seed := 1) -> Dictionary:
	Rules.ensure_loaded()
	var map := MapData.load_map(map_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = game_seed
	var starts: Array[String] = map.starts.duplicate()
	var scenario := {"id": "skirmish_" + map_id, "name": "Skirmish: " + map.display_name, "map": map_id, "difficulty": difficulty,
		"factions": [], "owners": {}, "capitals": {}, "buildings": {}, "units": [], "resources": {}}
	var used_ids := {}
	for i in players.size():
		var civ := Rules.civilization(players[i].civ)
		var id := civ.id
		var copies := 0
		while used_ids.has(id):
			copies += 1
			id = "%s_%d" % [civ.id, copies + 1]
		used_ids[id] = true
		var human: bool = players[i].get("human", false)
		var settings: Dictionary = DIFFICULTY.get(difficulty, DIFFICULTY.normal)
		var name := civ.faction_name if not human or players.filter(func(p): return p.get("human", false)).size() < 2 \
			else "%s (Player %d)" % [civ.faction_name, i + 1]
		scenario.factions.append({"id": id, "name": name, "civ": civ.id, "color": "#" + _color(civ, copies).to_html(false),
			"human": human, "ai": "balanced" if human else settings.ai})
		if not human:
			scenario.resources[id] = {"gold": settings.gold}
		var capital: String = starts[i]
		scenario.capitals[id] = capital
		scenario.owners[capital] = id
		scenario.buildings[capital] = {"market": 1, "barracks": 1}
	# Each player takes up to two neighbouring regions, one at a time in turn, so nobody is left out.
	var held := {}
	for faction in scenario.factions:
		held[faction.id] = [scenario.capitals[faction.id]] as Array[String]
	for pass_number in 2:
		for faction in scenario.factions:
			for neighbour in map.neighbours(scenario.capitals[faction.id]):
				if not scenario.owners.has(neighbour) and not (neighbour in starts):
					scenario.owners[neighbour] = faction.id
					held[faction.id].append(neighbour)
					break
	# One unit in each starting region: the civilization's special unit, archers, light cavalry.
	for faction in scenario.factions:
		var specials := Rules.civilization(faction.civ).special_units
		var army: Array = [specials[0] if not specials.is_empty() else "spearmen", "archers", "light_cavalry"]
		for k in mini(army.size(), held[faction.id].size()):
			scenario.units.append({"owner": faction.id, "region": held[faction.id][k], "type": army[k]})
	for region in map.province_order:
		if not scenario.owners.has(region) and rng.randf() < 0.5:
			scenario.units.append({"owner": "neutral", "region": region, "type": "militia", "soldiers": 10})
	return scenario


## The civilization's colour; a second player of the same civilization gets a shifted hue.
static func _color(civ: Civilization, copies: int) -> Color:
	if copies == 0:
		return civ.color
	return Color.from_hsv(fmod(civ.color.h + 0.13 * copies, 1.0), civ.color.s, civ.color.v)
