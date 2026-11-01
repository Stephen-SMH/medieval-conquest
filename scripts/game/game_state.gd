class_name GameState
extends RefCounted
## Everything that changes during a campaign: who owns each province, the
## armies, the turn, and the random number generator. The geography is fixed
## and lives in MapData.

const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]
const GENERAL_NAMES := [
	"Aldric", "Berengar", "Cedric", "Dagny", "Eadwine", "Freya", "Godfrey", "Hilda",
	"Isolde", "Jorund", "Leofric", "Matilda", "Osric", "Rowena", "Sigrun", "Wulfric",
]

var map: MapData
var player := "aldmere"
var turn := 1
var owners := {}  # province id -> faction id
var armies: Array[Army] = []
var rng := RandomNumberGenerator.new()

var _graph: ProvinceGraph
var _next_army_id := 1


static func new_game(game_map: MapData, game_seed := 1) -> GameState:
	var state := GameState.new()
	state.map = game_map
	state.rng.seed = game_seed
	state._graph = ProvinceGraph.new(game_map)
	for id in game_map.province_order:
		state.owners[id] = game_map.provinces[id].owner
	for entry in game_map.start_armies:
		var general: General = null
		if entry.get("general") != null:
			general = General.new(entry.general.name, int(entry.general.command), int(entry.general.logistics))
		state.add_army(entry.owner, entry.province, general, entry.regiments)
	return state


func season() -> String:
	return SEASONS[(turn - 1) % 4]


func year() -> int:
	return floori((turn - 1) / 4.0) + 1


func date_text() -> String:
	return "%s, Year %d (turn %d)" % [season(), year(), turn]


# --- Armies ---------------------------------------------------------------

func add_army(owner: String, province: String, general: General, regiment_types: Array) -> Army:
	var army := Army.new()
	army.id = _next_army_id
	_next_army_id += 1
	army.owner = owner
	army.province = province
	army.general = general
	for type_id in regiment_types:
		army.regiments.append(Regiment.new(type_id))
	army.reset_movement()
	armies.append(army)
	return army


func remove_army(army: Army) -> void:
	armies.erase(army)


func army_by_id(id: int) -> Army:
	for army in armies:
		if army.id == id:
			return army
	return null


func armies_in(province: String) -> Array[Army]:
	var found: Array[Army] = []
	for army in armies:
		if army.province == province:
			found.append(army)
	return found


func enemy_armies_in(province: String, faction: String) -> Array[Army]:
	var found: Array[Army] = []
	for army in armies:
		if army.province == province and is_enemy(faction, army.owner):
			found.append(army)
	return found


## Every other faction is an enemy until diplomacy exists.
func is_enemy(faction: String, other: String) -> bool:
	return faction != other


## An enemy army next to (or in) the province stops movement there (MV-6).
func in_enemy_zone_of_control(province: String, faction: String) -> bool:
	if not enemy_armies_in(province, faction).is_empty():
		return true
	for neighbour in map.neighbours(province):
		if not enemy_armies_in(neighbour, faction).is_empty():
			return true
	return false


## Provinces a faction can see armies in: its own provinces, provinces its
## armies stand in, and every neighbour of those (MP-5).
func visible_provinces(faction: String) -> Dictionary:
	var seen := {}
	var sources := []
	for id in map.province_order:
		if owners[id] == faction:
			sources.append(id)
	for army in armies:
		if army.owner == faction:
			sources.append(army.province)
	for id in sources:
		seen[id] = true
		for neighbour in map.neighbours(id):
			seen[neighbour] = true
	return seen


# --- Movement -------------------------------------------------------------

func find_path(from: String, to: String) -> Array[String]:
	return _graph.province_path(from, to)


## For each step of `path`, the turn it is reached on: 0 for this turn, 1 for
## next turn, and so on. An army with full movement points can always take one
## step, even into terrain that costs more than its speed.
func path_turns(army: Army, path: Array[String]) -> Array[int]:
	var turns: Array[int] = []
	var full := army.max_movement()
	var left := army.movement_left
	var current_turn := 0
	var from := army.province
	for step in path:
		var cost := map.move_cost(from, step)
		if cost > left and left < full:
			current_turn += 1
			left = full
		left = maxi(left - cost, 0)
		turns.append(current_turn)
		from = step
	return turns


## Sets the army's path to `destination` and moves it as far as it can this turn.
## Returns the events that happened, for the UI (see advance_army).
func order_move(army: Army, destination: String) -> Array:
	if not army.can_move():
		return [{"type": "cannot_move", "army": army}]
	army.path = find_path(army.province, destination)
	return advance_army(army)


## Moves the army along its path until it runs out of movement points or has
## to stop. Events, each with "army" and "province":
##   "moved", "occupied" (took an undefended enemy province),
##   "zone_of_control" (stopped next to an enemy army),
##   "battle" (marched into an enemy army; also has "battle": Battle).
func advance_army(army: Army) -> Array:
	var events := []
	while not army.path.is_empty():
		var next: String = army.path[0]
		var cost := map.move_cost(army.province, next)
		if army.movement_left == 0 or (cost > army.movement_left and army.movement_left < army.max_movement()):
			break
		if not enemy_armies_in(next, army.owner).is_empty():
			army.path.clear()
			army.movement_left = 0
			var battle := fight(army, next)
			events.append({"type": "battle", "army": army, "province": next, "battle": battle})
			if battle.attacker_won() and armies.has(army):
				army.province = next
				events.append_array(_occupy_if_enemy(army, next))
			break
		army.movement_left = maxi(army.movement_left - cost, 0)
		army.path.pop_front()
		army.province = next
		events.append({"type": "moved", "army": army, "province": next})
		events.append_array(_occupy_if_enemy(army, next))
		if in_enemy_zone_of_control(next, army.owner):
			army.movement_left = 0
			army.path.clear()
			events.append({"type": "zone_of_control", "army": army, "province": next})
			break
	return events


func _occupy_if_enemy(army: Army, province: String) -> Array:
	if is_enemy(army.owner, owners[province]) and enemy_armies_in(province, army.owner).is_empty():
		var previous: String = owners[province]
		owners[province] = army.owner
		return [{"type": "occupied", "army": army, "province": province, "previous_owner": previous}]
	return []


# --- Battles (PRD 3.9) ------------------------------------------------------

## Fights `army` against every enemy army in `province` and applies the result:
## destroyed regiments are removed, and a beaten defender retreats to a
## neighbouring province of its own, or is destroyed if it has nowhere to go.
## A beaten attacker stays where it was.
func fight(army: Army, province: String) -> Battle:
	var defenders := enemy_armies_in(province, army.owner)
	var sides := _battle_sides(army, defenders, false)
	var battle := Battle.new(sides[0], sides[1], map.terrain(province),
		map.border_type(army.province, province) == "river", rng.randi())
	battle.resolve()

	for involved in [army] + defenders:
		_remove_destroyed_regiments(involved)
	if battle.attacker_won():
		for defender in defenders:
			if not armies.has(defender):
				continue
			var refuge := _retreat_province(defender, province)
			if refuge == "":
				remove_army(defender)
			else:
				defender.province = refuge
				defender.path.clear()
				defender.movement_left = 0
	return battle


## Rates an attack by `army` on `province`, coming from `from` (default: where
## the army stands), without changing anything (BT-7).
func forecast_battle(army: Army, province: String, from := "") -> Dictionary:
	if from == "":
		from = army.province
	var defenders := enemy_armies_in(province, army.owner)
	return Battle.forecast(
		func(): return _battle_sides(army, defenders, true)[0],
		func(): return _battle_sides(army, defenders, true)[1],
		map.terrain(province), map.border_type(from, province) == "river",
		hash([army.id, province, turn]))


## [attacking Force, defending Force]. With `copy`, the sides fight copies of
## the regiments so a forecast leaves the real ones untouched.
func _battle_sides(army: Army, defenders: Array[Army], copy: bool) -> Array:
	var attacking: Array[Regiment] = []
	for regiment in army.regiments:
		attacking.append(regiment.copy() if copy else regiment)
	var defending: Array[Regiment] = []
	var defender_mod := 1.0
	for defender in defenders:
		for regiment in defender.regiments:
			defending.append(regiment.copy() if copy else regiment)
		if defender.general != null:
			defender_mod = maxf(defender_mod, defender.general.attack_mod())
	var attacker_mod := army.general.attack_mod() if army.general != null else 1.0
	var defender_faction: String = defenders[0].owner if not defenders.is_empty() else owners[army.province]
	return [Battle.Force.new(army.owner, true, attacking, attacker_mod),
		Battle.Force.new(defender_faction, false, defending, defender_mod)]


func _remove_destroyed_regiments(army: Army) -> void:
	var standing: Array[Regiment] = []
	for regiment in army.regiments:
		if regiment.men >= Battle.DESTROYED_BELOW:
			standing.append(regiment)
	army.regiments = standing
	if standing.is_empty():
		remove_army(army)
	else:
		army.movement_left = mini(army.movement_left, army.max_movement())


## A neighbouring province the army's faction owns with no enemy army in it.
func _retreat_province(army: Army, from: String) -> String:
	for neighbour in map.neighbours(from):
		if owners[neighbour] == army.owner and enemy_armies_in(neighbour, army.owner).is_empty():
			return neighbour
	return ""


# --- Merge and split (AR-5) -----------------------------------------------

func can_merge(target: Army, source: Army) -> bool:
	return target != source and target.owner == source.owner and target.province == source.province \
		and target.regiments.size() + source.regiments.size() <= Army.MAX_REGIMENTS


## Moves all of `source`'s regiments into `target` and removes `source`.
## The merged army keeps the lower movement points left of the two.
func merge(target: Army, source: Army) -> bool:
	if not can_merge(target, source):
		return false
	target.regiments.append_array(source.regiments)
	target.movement_left = mini(target.movement_left, source.movement_left)
	if target.general == null:
		target.general = source.general
	remove_army(source)
	return true


## Moves the regiments at `indices` into a new army in the same province, led
## by a newly appointed general. At least one regiment must stay behind.
func split(army: Army, indices: Array) -> Army:
	if indices.is_empty() or indices.size() >= army.regiments.size():
		return null
	var moving: Array[Regiment] = []
	var staying: Array[Regiment] = []
	for i in army.regiments.size():
		if i in indices:
			moving.append(army.regiments[i])
		else:
			staying.append(army.regiments[i])
	army.regiments = staying
	var new_army := add_army(army.owner, army.province, new_general(), [])
	new_army.regiments = moving
	new_army.movement_left = mini(army.movement_left, new_army.max_movement())
	army.movement_left = mini(army.movement_left, army.max_movement())
	return new_army


## Gives a garrison a general so it can leave its province.
func appoint_general(army: Army) -> void:
	if army.general == null:
		army.general = new_general()


func new_general() -> General:
	return General.new(GENERAL_NAMES[rng.randi() % GENERAL_NAMES.size()], rng.randi_range(0, 3), rng.randi_range(0, 3))


# --- Turns ------------------------------------------------------------------

## Ends the player's turn. Other factions don't act yet. At the start of the
## next turn every army gets its movement back and armies with an unfinished
## path keep walking it. Returns the movement events.
func end_turn() -> Array:
	turn += 1
	for army in armies:
		army.reset_movement()
	var events := []
	for army in armies.duplicate():
		if not army.path.is_empty():
			events.append_array(advance_army(army))
	return events
