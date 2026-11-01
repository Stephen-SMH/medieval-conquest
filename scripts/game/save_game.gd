class_name SaveGame
extends RefCounted
## Saves and loads a whole game as JSON in user://saves/, including the
## random number generator, so a loaded game plays on exactly as it would have.

const SAVE_DIR := "user://saves"
const SLOTS := ["auto", "1", "2", "3"]


static func to_dict(state: GameState) -> Dictionary:
	var factions := []
	for id in state.turn_order:
		var faction: FactionState = state.factions[id]
		factions.append({"id": id, "name": faction.display_name, "color": faction.color.to_html(), "civ": faction.civ,
			"human": faction.human, "ai": faction.ai, "alive": faction.alive, "resources": faction.resources.duplicate(),
			"tax": faction.tax, "techs": Array(faction.techs), "researching": faction.researching,
			"research_turns_left": faction.research_turns_left})
	var provinces := {}
	for region in state.provinces:
		var province: ProvinceState = state.provinces[region]
		provinces[region] = {"buildings": province.buildings.duplicate(), "construction": province.construction,
			"construction_turns": province.construction_turns, "recruits": Array(province.recruits),
			"happiness": province.happiness, "forage": province.forage,
			"siege_faction": province.siege_faction, "siege_turns": province.siege_turns}
	var units := []
	for unit in state.units:
		var entry := {"id": unit.id, "type": unit.type_id, "owner": unit.owner, "region": unit.province, "hp": unit.hp,
			"xp": unit.xp, "move_points_left": unit.move_points_left, "attacked": unit.attacked, "moved": unit.moved}
		if unit.general != null:
			entry["general"] = {"name": unit.general.name, "command": unit.general.command, "logistics": unit.general.logistics}
		units.append(entry)
	return {
		"version": 2, "map": state.map.id, "scenario": state.scenario_id, "turn": state.turn, "current": state.current,
		"factions": factions, "owners": state.owners.duplicate(), "capitals": state.capitals.duplicate(),
		"provinces": provinces, "units": units, "next_unit_id": state._next_unit_id,
		"rng_seed": str(state.rng.seed), "rng_state": str(state.rng.state),
		"mission": state.mission.duplicate(true), "mission_progress": state.mission_progress.duplicate(),
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
		faction.tax = entry.tax
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
		province.happiness = float(entry.happiness)
		province.forage = float(entry.forage)
		province.siege_faction = entry.siege_faction
		province.siege_turns = int(entry.siege_turns)
		state.provinces[region] = province
	for entry in data.units:
		var unit := Unit.new(entry.type, entry.owner, entry.region)
		unit.id = int(entry.id)
		unit.hp = float(entry.hp)
		unit.xp = int(entry.xp)
		unit.move_points_left = int(entry.move_points_left)
		unit.attacked = entry.attacked
		unit.moved = entry.moved
		if entry.has("general"):
			unit.general = General.new(entry.general.name, int(entry.general.command), int(entry.general.logistics))
		state.units.append(unit)
	state._next_unit_id = int(data.next_unit_id)
	state.rng.seed = int(data.rng_seed)
	state.rng.state = int(data.rng_state)
	state.mission = data.mission.duplicate(true)
	for key in data.mission_progress:
		state.mission_progress[key] = int(data.mission_progress[key])
	state.result = data.get("result", {}).duplicate()
	return state


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
