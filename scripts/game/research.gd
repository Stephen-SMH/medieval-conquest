class_name Research
extends RefCounted
## Research (PRD 8.7): two trees, Economy and Military, of 6 techs in 3 tiers.
## One tech at a time, paid in gold when started, done after 2-4 turns.


## "" if the faction can start researching `tech_id` now, else why not.
static func problem(state: GameState, faction: String, tech_id: String) -> String:
	var me: FactionState = state.factions[faction]
	var tech := Rules.tech(tech_id)
	if me.has_tech(tech_id):
		return "already known"
	if me.researching != "":
		return "already researching %s" % Rules.tech_name(me.researching)
	for needed in tech.requires:
		if not me.has_tech(needed):
			return "needs %s" % Rules.tech_name(needed)
	if me.resources.gold < tech.cost_gold:
		return "needs %d gold" % tech.cost_gold
	return ""


static func start(state: GameState, faction: String, tech_id: String) -> bool:
	if problem(state, faction, tech_id) != "":
		return false
	var me: FactionState = state.factions[faction]
	var tech := Rules.tech(tech_id)
	me.resources.gold -= tech.cost_gold
	me.researching = tech_id
	me.research_turns_left = tech.turns
	return true


## Moves a faction's research on by a turn. Returns events.
static func advance(state: GameState, faction: String) -> Array:
	var me: FactionState = state.factions[faction]
	if me.researching == "":
		return []
	me.research_turns_left -= 1
	if me.research_turns_left > 0:
		return []
	var done := me.researching
	me.techs.append(done)
	me.researching = ""
	return [{"type": "economy", "faction": faction, "kind": "good",
		"text": "Research complete: %s. %s" % [Rules.tech_name(done), Rules.tech(done).description]}]


## Picks something to research for a computer faction: the cheapest tech it can
## start, military first for aggressive factions and economy first otherwise.
static func choose_for_ai(state: GameState, faction: String) -> void:
	var me: FactionState = state.factions[faction]
	if me.researching != "":
		return
	var first_tree := "military" if me.ai == "aggressive" else "economy"
	var best := ""
	var best_score := 1 << 30
	for tech_id in Rules.techs:
		var tech := Rules.tech(tech_id)
		if problem(state, faction, tech_id) != "" or me.resources.gold - tech.cost_gold < 100.0:
			continue
		var score := tech.cost_gold + (0 if tech.tree == first_tree else 50)
		if score < best_score:
			best_score = score
			best = tech_id
	if best != "":
		start(state, faction, best)


static func _known(state: GameState, faction: String) -> Array:
	if not state.factions.has(faction):
		return []
	return state.factions[faction].techs.map(func(id): return Rules.tech(id))


static func income(state: GameState, faction: String, kind: String) -> float:
	var multiplier := 1.0
	for tech: TechType in _known(state, faction):
		multiplier *= tech.income.get(kind, 1.0)
	return multiplier


## Extra gold a region pays its owner from research.
static func region_bonus(state: GameState, faction: String, region: String) -> float:
	var bonus := 0.0
	var terrain: String = state.map.provinces[region].terrain
	for tech: TechType in _known(state, faction):
		bonus += tech.region_bonus + tech.terrain_income.get(terrain, 0)
	return bonus


static func upkeep_mod(state: GameState, faction: String) -> float:
	var multiplier := 1.0
	for tech: TechType in _known(state, faction):
		multiplier *= tech.upkeep
	return multiplier


static func battle(state: GameState, unit: Troop, owner: String) -> void:
	var unit_class := unit.type().unit_class
	var melee := not unit.type().is_ranged()
	for tech: TechType in _known(state, owner):
		unit.attack_mod *= tech.attack.get(unit_class, 1.0) * (tech.attack.get("melee", 1.0) if melee else 1.0)
		unit.defense_mod *= tech.defense.get(unit_class, 1.0)
		if unit.type().is_cavalry():
			unit.charge_mod *= tech.charge
