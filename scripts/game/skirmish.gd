class_name Skirmish
extends RefCounted
## Builds a skirmish or hotseat scenario (PRD CP-5, CP-6): each player starts in
## one of the map's start regions with its neighbours, a small army and a
## capital; the other regions are independent. Win by conquest.

const DIFFICULTY := {
	"easy": {"ai": "defensive", "gold": 200.0},
	"normal": {"ai": "balanced", "gold": 300.0},
	"hard": {"ai": "aggressive", "gold": 500.0},
}
const STARTING_UNITS := ["spearmen", "archers", "light_cavalry"]


## `players` is a list of {"civ": id, "human": bool}. Returns a scenario.
static func build(map_id: String, players: Array, difficulty := "normal", game_seed := 1) -> Dictionary:
	Rules.ensure_loaded()
	var map := MapData.load_map(map_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = game_seed
	var starts: Array[String] = map.starts.duplicate()
	var scenario := {"id": "skirmish_" + map_id, "name": "Skirmish: " + map.display_name, "map": map_id,
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
		scenario.buildings[capital] = {"farm": 1, "market": 1, "barracks": 1, "archery_range": 1}
		var taken := 0
		for neighbour in map.neighbours(capital):
			if taken < 2 and not scenario.owners.has(neighbour) and not (neighbour in starts):
				scenario.owners[neighbour] = id
				taken += 1
		var specials := civ.special_units
		var army: Array = STARTING_UNITS + [specials[0] if not specials.is_empty() else "swordsmen"]
		for k in army.size():
			var unit := {"owner": id, "region": capital, "type": army[k]}
			if k == 0:
				unit["general"] = {"name": GameState.GENERAL_NAMES[rng.randi() % GameState.GENERAL_NAMES.size()], "command": 2, "logistics": 2}
			scenario.units.append(unit)
	for region in map.province_order:
		if not scenario.owners.has(region) and rng.randf() < 0.5:
			scenario.units.append({"owner": "neutral", "region": region, "type": "militia", "soldiers": 10})
	return scenario


## The civilization's colour; a second player of the same civilization gets a shifted hue.
static func _color(civ: Civilization, copies: int) -> Color:
	if copies == 0:
		return civ.color
	return Color.from_hsv(fmod(civ.color.h + 0.13 * copies, 1.0), civ.color.s, civ.color.v)
