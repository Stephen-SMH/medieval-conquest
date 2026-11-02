class_name GameState
extends RefCounted
## Everything that changes during a game: who owns each region, the regions'
## buildings, the factions' treasuries, the armies, the orders planned this
## turn, and the random number generator. The geography is fixed and lives in
## MapData; the economy rules are in Economy.
##
## Turns go faction by faction (PRD C): the current faction plans all its
## arrows, presses the hourglass, and only its orders resolve (Resolver) and
## play out; then the next faction takes its turn. When every faction has
## played, the turn number goes up.

const STACK_LIMIT := 1  # UT-3: one army per region.
const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]
## Factions that hold regions but never take turns.
const NON_PLAYABLE := {
	"neutral": {"name": "Independent", "color": Color("#8a8478")},
	"rebels": {"name": "Rebels", "color": Color("#4a4a4a")},
}

var map: MapData
var scenario_id := ""
var turn := 1
var factions := {}  # faction id -> FactionState, playable factions only
var turn_order: Array[String] = []
## Index into turn_order of the faction whose turn it is.
var current := 0
var owners := {}  # region id -> faction id
var provinces := {}  # region id -> ProvinceState
var capitals := {}  # faction id -> region id
var units: Array[Unit] = []
var rng := RandomNumberGenerator.new()
## Orders planned by the current faction: Unit -> Array of orders (see Orders).
var orders := {}
## The scenario's mission (objectives, crowns...); empty for skirmish and hotseat.
var mission := {}
## Mission bookkeeping: turns held, events fired...
var mission_progress := {}
## The mission's scripted notes so far: [{"turn": n, "text": "..."}] (PRD H).
var mission_log := []
## Soldiers each faction has lost, by unit type: faction -> {type: soldiers}.
var losses := {}
## Armies each faction has destroyed: faction -> count.
var kills := {}
## {} while the game goes on; see Mission.evaluate().
var result := {}
## Forge upgrades for factions: faction -> {upgrade family: {"attack": level, ...}}.
var upgrades := {}

var _next_unit_id := 1


## Builds a game from a scenario (data/scenarios/*.json or a mission): the map,
## factions, owners, capitals, buildings, armies and starting gold. An army
## entry is {"owner", "region", "type", "soldiers"} or {"owner", "region",
## "troops": {type: soldiers}}.
static func from_scenario(scenario: Dictionary, game_seed := 1) -> GameState:
	var state := GameState.new()
	state.map = MapData.load_map(scenario.map)
	state.scenario_id = scenario.get("id", "")
	state.mission = scenario.get("mission", {}).duplicate(true)
	if scenario.has("campaign") and not state.mission.is_empty():
		state.mission["campaign"] = scenario.campaign
		state.mission["mission_index"] = scenario.mission_index
	state.rng.seed = game_seed
	for entry in scenario.factions:
		var faction := FactionState.new()
		faction.id = entry.id
		faction.display_name = entry.name
		faction.color = Color(entry.color)
		faction.civ = entry.get("civ", "")
		faction.human = entry.get("human", false)
		faction.ai = entry.get("ai", "balanced")
		faction.resources = Economy.START_RESOURCES.duplicate()
		for resource in scenario.get("resources", {}).get(faction.id, {}):
			faction.resources[resource] = float(scenario.resources[faction.id][resource])
		state.factions[faction.id] = faction
		state.turn_order.append(faction.id)
	state.capitals = scenario.get("capitals", {}).duplicate()
	state.mission = Mission.normalized(state.mission, state.capitals)
	state.upgrades = scenario.get("upgrades", {}).duplicate(true)
	for region in state.map.province_order:
		state.owners[region] = scenario.get("owners", {}).get(region, "neutral")
		var province := ProvinceState.new()
		for building_id in scenario.get("buildings", {}).get(region, {}):
			if Rules.buildings.has(building_id):  # Archery ranges, stables and siege workshops are gone (PRD E).
				province.buildings[building_id] = int(scenario.buildings[region][building_id])
		state.provinces[region] = province
	for entry in scenario.get("units", []):
		var army := state.unit_in(entry.region)
		if army != null and army.owner != entry.owner:
			push_error("Scenario %s puts two factions' armies in %s" % [state.scenario_id, entry.region])
			continue
		if army == null:
			army = state.add_unit("", entry.owner, entry.region)
		if entry.has("troops"):
			for troop_type in entry.troops:
				army.add(troop_type, int(entry.troops[troop_type]))
		else:
			army.add(entry.type, int(entry.get("soldiers", UnitType.SOLDIERS)))
		army.reset_turn()
	state.update_alive()
	state.begin_turn()
	return state


# --- Factions and turns ---------------------------------------------------------

## The faction planning its orders now.
func current_faction() -> String:
	return turn_order[current]


## The human whose eyes the map is drawn for: the one planning, or the first human.
func viewer() -> String:
	if factions[current_faction()].human:
		return current_faction()
	for id in turn_order:
		if factions[id].human:
			return id
	return current_faction()


func faction_name(id: String) -> String:
	if factions.has(id):
		return factions[id].display_name
	return NON_PLAYABLE.get(id, {"name": id}).name


func faction_color(id: String) -> Color:
	if factions.has(id):
		return factions[id].color
	return NON_PLAYABLE.get(id, {"color": Color.GRAY}).color


func is_enemy(faction: String, other: String) -> bool:
	return faction != other


func is_capital(region: String) -> bool:
	return capitals.has(owners.get(region, "")) and capitals[owners[region]] == region


func season() -> String:
	return SEASONS[(turn - 1) % 4]


func year() -> int:
	return floori((turn - 1) / 4.0) + 1


func date_text() -> String:
	return "%s, Year %d (turn %d)" % [season(), year(), turn]


## Starts a round: the first living faction takes its turn.
func begin_turn() -> void:
	current = 0
	_skip_fallen()
	begin_faction_turn()


## The current faction's turn starts: its armies are fresh and
## reinforcements ordered last turn arrive.
func begin_faction_turn() -> Array:
	var faction := current_faction()
	for unit in units_of(faction):
		unit.reset_turn()
	var events := Economy.arrivals(self, faction)
	if current == living_index(0):
		events.append_array(Mission.start_of_turn(self))
	return events


## Ends the current faction's turn: its orders are resolved and played out
## (PRD C), then the next living faction's turn starts; after the last one,
## the turn number goes up. Returns the events, for the animations.
func end_faction_turn() -> Array:
	if is_over():
		return []
	var events := Resolver.resolve(self, current_faction())
	update_result()
	if is_over():
		orders.clear()
		return events
	var wrapped := true
	for step in turn_order.size():
		current += 1
		if current >= turn_order.size():
			break
		if factions[current_faction()].alive:
			wrapped = false
			break
	if wrapped:
		turn += 1
		current = 0
		_skip_fallen()
		update_result()
	events.append_array(begin_faction_turn() if not is_over() else [])
	return events


## The index in turn_order of the `n`th living faction.
func living_index(n: int) -> int:
	var seen := 0
	for i in turn_order.size():
		if factions[turn_order[i]].alive:
			if seen == n:
				return i
			seen += 1
	return 0


func _skip_fallen() -> void:
	while current < turn_order.size() - 1 and not factions[current_faction()].alive:
		current += 1


## Checks objectives and conquest; once the game is decided, `result` stays set.
func update_result() -> void:
	if not result.is_empty():
		return
	update_alive()
	result = Mission.evaluate(self)


func is_over() -> bool:
	return not result.is_empty()


func update_alive() -> void:
	for id in factions:
		var holds_land := owners.values().has(id)
		factions[id].alive = holds_land or not units_of(id).is_empty()


func living_factions() -> Array[String]:
	var alive: Array[String] = []
	for id in turn_order:
		if factions[id].alive:
			alive.append(id)
	return alive


# --- Armies ----------------------------------------------------------------------

## A new army with `soldiers` of `type_id` (none if the type is "").
func add_unit(type_id: String, owner: String, region: String, soldiers := UnitType.SOLDIERS) -> Unit:
	var unit := Unit.new(type_id, owner, region, soldiers)
	register(unit)
	unit.reset_turn()
	return unit


## Gives an army made elsewhere (a detachment) an id and puts it on the map.
func register(unit: Unit) -> void:
	unit.id = _next_unit_id
	_next_unit_id += 1
	units.append(unit)


func remove_unit(unit: Unit) -> void:
	units.erase(unit)
	orders.erase(unit)


func unit_by_id(id: int) -> Unit:
	for unit in units:
		if unit.id == id:
			return unit
	return null


## The army in a region, or null (one per region, UT-3).
func unit_in(region: String) -> Unit:
	for unit in units:
		if unit.province == region:
			return unit
	return null


func units_in(region: String) -> Array[Unit]:
	var found: Array[Unit] = []
	for unit in units:
		if unit.province == region:
			found.append(unit)
	return found


func units_of(faction: String) -> Array[Unit]:
	var found: Array[Unit] = []
	for unit in units:
		if unit.owner == faction:
			found.append(unit)
	return found


func enemy_units_in(region: String, faction: String) -> Array[Unit]:
	var found: Array[Unit] = []
	for unit in units_in(region):
		if is_enemy(faction, unit.owner):
			found.append(unit)
	return found


## Free places in a region for an army: 1 if empty, else 0.
func space_in(region: String, _faction := "") -> int:
	return STACK_LIMIT - units_in(region).size()


## Regions a faction can see armies in: its own regions, regions its armies
## stand in, and every neighbour of those (MP-5).
func visible_provinces(faction: String) -> Dictionary:
	var seen := {}
	var sources := []
	for region in map.province_order:
		if owners[region] == faction:
			sources.append(region)
	for unit in units_of(faction):
		sources.append(unit.province)
	for region in sources:
		seen[region] = true
		for neighbour in map.neighbours(region):
			seen[neighbour] = true
	return seen


func attack_range(unit: Unit) -> int:
	return unit.max_range()


# --- Battles ----------------------------------------------------------------------

## Rates an attack by these armies (or detachments) on the army in `region`
## without changing anything (OR-6).
func forecast_attack(stack: Array, region: String, runs := Battle.FORECAST_RUNS) -> Dictionary:
	if stack.is_empty() or enemy_units_in(region, stack[0].owner).is_empty():
		return {}
	var attacking: Array[Unit] = []
	attacking.assign(stack)
	var defending: Array[Unit] = [enemy_units_in(region, stack[0].owner)[0]]
	return Battle.forecast(
		func(): return forces(attacking, defending, region, true)[0],
		func(): return forces(attacking, defending, region, true)[1],
		map.terrain(region), crosses_river(attacking, region),
		hash([stack[0].id, region, turn]), runs)


## [attacking Force, defending Force] for armies fighting over `region`. With
## `copy`, the forces fight copies so a forecast leaves the real ones untouched.
func forces(attacking: Array[Unit], defenders: Array[Unit], region: String, copy: bool, field := false) -> Array:
	var attack_troops: Array[Troop] = []
	for unit in attacking:
		for troop in unit.troops:
			prepare_for_battle(troop, unit.owner, false, region, unit.province)
			attack_troops.append(troop.copy() if copy else troop)
	var defend_troops: Array[Troop] = []
	for unit in defenders:
		for troop in unit.troops:
			prepare_for_battle(troop, unit.owner, not field, region, unit.province)
			defend_troops.append(troop.copy() if copy else troop)
	var attacking_force := Battle.Force.new(attacking[0].owner, true, attack_troops)
	var defending_force := Battle.Force.new(defenders[0].owner, false, defend_troops)
	if not field:
		defending_force.wall_bonus = Sieges.wall_bonus(self, region, attacking)
	return [attacking_force, defending_force]


## Works out a troop's battle multipliers from its civilization and upgrades.
func prepare_for_battle(troop: Troop, owner: String, defending: bool, region: String, from := "") -> void:
	troop.attack_mod = 1.0
	troop.defense_mod = 1.0
	troop.charge_mod = 1.0
	troop.toughness = 1.0
	Bonuses.battle(self, troop, owner, defending, region, from)


func crosses_river(attacking: Array[Unit], region: String) -> bool:
	for unit in attacking:
		if unit.has_melee() and map.border_type(unit.province, region) == "river":
			return true
	return false


## A free neighbouring region the army's faction owns, or "" if there is none.
func retreat_region(unit: Unit, from: String) -> String:
	for neighbour in map.neighbours(from):
		if owners[neighbour] == unit.owner and unit_in(neighbour) == null:
			return neighbour
	return ""


## Whether a faction has a Forge upgrade for this soldier type's line (G).
func is_upgraded(faction: String, type_id: String) -> bool:
	var lines: Dictionary = upgrades.get(faction, {})
	var levels: Dictionary = lines.get(TypeIcons.family(type_id), {})
	return levels.values().any(func(level): return int(level) > 0)


## Adds the soldiers each side lost in a battle to `losses`.
func record_losses(battle: Battle) -> void:
	for side: Battle.Force in [battle.attacker, battle.defender]:
		for i in side.units.size():
			var lost: int = side.before[i][1] - side.units[i].soldiers
			note_loss(side.faction, side.before[i][0], lost)


func note_loss(faction: String, type_id: String, lost: int) -> void:
	if lost > 0:
		var by_type: Dictionary = losses.get_or_add(faction, {})
		by_type[type_id] = int(by_type.get(type_id, 0)) + lost


## Removes an army. `by` is the faction that destroyed it, if any.
func destroy(unit: Unit, how: String, by := "") -> Array:
	for troop in unit.troops:
		note_loss(unit.owner, troop.type_id, troop.soldiers)
	remove_unit(unit)
	if by != "":
		kills[by] = int(kills.get(by, 0)) + 1
	return [{"type": "destroyed", "unit": unit, "province": unit.province, "how": how}]


## Takes a region for a faction. Returns the event, or [] if nothing changed.
func capture(faction: String, region: String, from := "") -> Array:
	if owners[region] == faction:
		return []
	var previous: String = owners[region]
	owners[region] = faction
	var province: ProvinceState = provinces[region]
	province.construction = ""
	province.recruits.clear()
	province.siege_faction = ""
	province.siege_turns = 0
	return [{"type": "captured", "province": region, "faction": faction, "previous_owner": previous, "from": from}]


# --- Merging (UT-8) ----------------------------------------------------------------

## "" if `source` can join `target`, else why not.
func merge_problem(target: Unit, source: Unit) -> String:
	if target == source:
		return "the same army"
	if target.owner != source.owner:
		return "not the same faction"
	if target.soldiers() >= Unit.CAP:
		return "already %d soldiers" % Unit.CAP
	return ""


## Moves soldiers from `source` into `target`, up to Unit.CAP: compositions
## add up. Soldiers that don't fit stay in `source` (taken evenly across its
## types); if none are left, `source` is removed. Returns the soldiers moved.
func merge(target: Unit, source: Unit) -> int:
	if merge_problem(target, source) != "":
		return 0
	var room := Unit.CAP - target.soldiers()
	var moving := mini(source.soldiers(), room)
	if moving >= source.soldiers():
		target.absorb(source)
		remove_unit(source)
	else:
		target.absorb(source.split(Orders.pick(source.composition(), moving)))
	return moving
