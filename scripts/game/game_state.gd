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


static func new_game(game_map: MapData, seed := 1) -> GameState:
	var state := GameState.new()
	state.map = game_map
	state.rng.seed = seed
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
## to stop. Events: {"type": "moved", "army", "province"},
## {"type": "zone_of_control", "army", "province"},
## {"type": "blocked", "army", "province"} when an enemy army is in the way.
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
			events.append({"type": "blocked", "army": army, "province": next})
			break
		army.movement_left = maxi(army.movement_left - cost, 0)
		army.path.pop_front()
		army.province = next
		events.append({"type": "moved", "army": army, "province": next})
		if in_enemy_zone_of_control(next, army.owner):
			army.movement_left = 0
			army.path.clear()
			events.append({"type": "zone_of_control", "army": army, "province": next})
			break
	return events


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
