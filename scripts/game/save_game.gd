class_name SaveGame
extends RefCounted
## Saves and loads a whole game as JSON in user://saves/, including the
## random number generator, so a loaded game plays on exactly as it would have.
## Version 3 saves each unit's list of orders (detachments, PRD OR-3); older
## saves held one order per unit and are converted when loaded.

const VERSION := 3
const SAVE_DIR := "user://saves"
const SLOTS := ["auto", "1", "2", "3"]


static func to_dict(state: GameState) -> Dictionary:
	var factions := []
	for id in state.turn_order:
		var faction: FactionState = state.factions[id]
		factions.append({"id": id, "name": faction.display_name, "color": faction.color.to_html(), "civ": faction.civ,
			"human": faction.human, "ai": faction.ai, "alive": faction.alive, "resources": faction.resources.duplicate(),
			"techs": Array(faction.techs), "researching": faction.researching,
			"research_turns_left": faction.research_turns_left})
	var provinces := {}
	for region in state.provinces:
		var province: ProvinceState = state.provinces[region]
		provinces[region] = {"buildings": province.buildings.duplicate(), "construction": province.construction,
			"construction_turns": province.construction_turns, "recruits": Array(province.recruits),
			"siege_faction": province.siege_faction, "siege_turns": province.siege_turns,
			"mercenaries": province.mercenaries.duplicate()}
	var units := []
	for unit in state.units:
		var entry := {"id": unit.id, "type": unit.type_id, "owner": unit.owner, "region": unit.province, "hp": unit.hp,
			"move_points_left": unit.move_points_left, "attacked": unit.attacked, "moved": unit.moved,
			"coastal_moves": unit.coastal_moves}
		units.append(entry)
	return {
		"version": VERSION, "map": state.map.id, "scenario": state.scenario_id, "turn": state.turn, "current": state.current,
		"factions": factions, "owners": state.owners.duplicate(), "capitals": state.capitals.duplicate(),
		"provinces": provinces, "units": units, "next_unit_id": state._next_unit_id,
		"rng_seed": str(state.rng.seed), "rng_state": str(state.rng.state),
		"orders": _orders_to_list(state),
		"mission": state.mission.duplicate(true), "mission_progress": state.mission_progress.duplicate(),
		"losses": state.losses.duplicate(true),
		"result": state.result.duplicate(),
	}


static func from_dict(data: Dictionary) -> GameState:
	var state := GameState.new()
	state.map = MapData.load_map(data.map)
	state.scenario_id = data.scenario
	state.turn = int(data.turn)
	state.current = int(data.current)
	for entry in data.factions:
		var faction := FactionState.new()
		faction.id = entry.id
		faction.display_name = entry.name
		faction.color = Color(entry.color)
		faction.civ = entry.civ
		faction.human = entry.human
		faction.ai = entry.ai
		faction.alive = entry.alive
		for resource in entry.resources:
			faction.resources[resource] = float(entry.resources[resource])
		faction.techs.assign(entry.techs)
		faction.researching = entry.researching
		faction.research_turns_left = int(entry.research_turns_left)
		state.factions[faction.id] = faction
		state.turn_order.append(faction.id)
	state.owners = data.owners.duplicate()
	state.capitals = data.capitals.duplicate()
	for region in data.provinces:
		var entry: Dictionary = data.provinces[region]
		var province := ProvinceState.new()
		for building_id in entry.buildings:
			province.buildings[building_id] = int(entry.buildings[building_id])
		province.construction = entry.construction
		province.construction_turns = int(entry.construction_turns)
		province.recruits.assign(entry.recruits)
		province.siege_faction = entry.siege_faction
		province.siege_turns = int(entry.siege_turns)
		for unit_id in entry.get("mercenaries", {}):
			province.mercenaries[unit_id] = int(entry.mercenaries[unit_id])
		state.provinces[region] = province
	for entry in data.units:
		var unit := Unit.new(entry.type, entry.owner, entry.region)
		unit.id = int(entry.id)
		unit.hp = float(entry.hp)
		unit.move_points_left = int(entry.move_points_left)
		unit.attacked = entry.attacked
		unit.moved = entry.moved
		unit.coastal_moves = int(entry.get("coastal_moves", 0))
		state.units.append(unit)
	state._next_unit_id = int(data.next_unit_id)
	state.rng.seed = int(data.rng_seed)
	state.rng.state = int(data.rng_state)
	state.mission = data.mission.duplicate(true)
	for key in data.mission_progress:
		state.mission_progress[key] = int(data.mission_progress[key])
	state.result = data.get("result", {}).duplicate()
	for faction in data.get("losses", {}):
		state.losses[faction] = {}
		for type_id in data.losses[faction]:
			state.losses[faction][type_id] = int(data.losses[faction][type_id])
	var version := int(data.get("version", 1))
	for entry in data.get("orders", []):
		var unit := state.unit_by_id(int(entry.unit))
		if unit == null:
			continue
		var list := []
		if version >= 3:
			for order in entry.orders:
				list.append({"steps": order.steps.duplicate(true), "size": int(order.size), "soldiers": int(order.soldiers), "shoot": int(order.shoot)})
		else:
			list.append(_old_order(unit, entry))
		state.orders[unit] = list
	return state


## A version 1-2 order (one per unit, the whole unit moving; an attack sending
## `soldiers` and `shoot`) as a detachment: a single attack sends only those
## soldiers, and anything else takes the whole unit, as it did then.
static func _old_order(unit: Unit, entry: Dictionary) -> Dictionary:
	var soldiers := int(entry.get("soldiers", unit.soldiers()))
	var shoot := int(entry.get("shoot", 0))
	var size := unit.soldiers()
	if entry.steps.size() == 1 and entry.steps[0].type == "attack":
		size = clampi(soldiers + shoot, 1, unit.soldiers())
	elif entry.steps.size() == 1:
		soldiers = size
	return {"steps": entry.steps.duplicate(true), "size": size, "soldiers": mini(soldiers, size), "shoot": mini(shoot, size)}


## Planned orders by unit id, oldest unit first, so saves are stable.
static func _orders_to_list(state: GameState) -> Array:
	var list := []
	for unit in state.units:
		if state.orders.has(unit):
			var orders := []
			for order in state.orders[unit]:
				orders.append({"steps": order.steps.duplicate(true), "size": int(order.size), "soldiers": int(order.soldiers), "shoot": int(order.shoot)})
			list.append({"unit": unit.id, "orders": orders})
	return list


static func path_for(slot: String) -> String:
	return SAVE_DIR.path_join("slot_%s.json" % slot)


static func save(state: GameState, slot: String) -> Error:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var data := to_dict(state)
	data["saved_at"] = Time.get_datetime_string_from_system(false, true)
	# Write to a temporary file first, so a crash can't leave a half-written save.
	var temporary := path_for(slot) + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.close()
	return DirAccess.rename_absolute(temporary, path_for(slot))


static func load_slot(slot: String) -> Dictionary:
	if not FileAccess.file_exists(path_for(slot)):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path_for(slot)))
	return data if data is Dictionary else {}


## A one-line description of a slot for the menus, or "" if it's empty.
static func describe(slot: String) -> String:
	var data := load_slot(slot)
	if data.is_empty():
		return ""
	var player := ""
	for entry in data.factions:
		if entry.human:
			player = entry.name
			break
	return "%s — turn %d — %s" % [player, int(data.turn), str(data.get("saved_at", "")).replace("T", " ")]
