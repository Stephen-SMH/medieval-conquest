class_name SaveGame
extends RefCounted
## Saves and loads a whole game as JSON in user://saves/, including the
## random number generator, so a loaded game plays on exactly as it would have.
## Version 4 saves armies as compositions of troops (PRD A) and each order's
## troops per type; older saves held one type per unit and are converted.
## Version 5 saves reinforcements on their way as bundles (PRD E); older
## saves' whole units on their way load as bundles of 20.

const VERSION := 5
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
			"construction_turns": province.construction_turns, "recruits": province.recruits.duplicate(true),
			"siege_faction": province.siege_faction, "siege_turns": province.siege_turns}
	var units := []
	for unit in state.units:
		var troops := []
		for troop in unit.troops:
			troops.append({"type": troop.type_id, "soldiers": troop.soldiers, "hp": troop.hp})
		units.append({"id": unit.id, "owner": unit.owner, "region": unit.province, "troops": troops,
			"move_points_left": unit.move_points_left, "attacked": unit.attacked, "moved": unit.moved})
	return {
		"version": VERSION, "map": state.map.id, "scenario": state.scenario_id, "turn": state.turn, "current": state.current,
		"factions": factions, "owners": state.owners.duplicate(), "capitals": state.capitals.duplicate(),
		"provinces": provinces, "units": units, "next_unit_id": state._next_unit_id,
		"rng_seed": str(state.rng.seed), "rng_state": str(state.rng.state),
		"orders": _orders_to_list(state),
		"mission": state.mission.duplicate(true), "kills": state.kills.duplicate(), "upgrades": state.upgrades.duplicate(true), "mission_progress": state.mission_progress.duplicate(),
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
			if Rules.buildings.has(building_id):
				province.buildings[building_id] = int(entry.buildings[building_id])
		province.construction = entry.construction
		province.construction_turns = int(entry.construction_turns)
		for bundle in entry.recruits:
			if bundle is Dictionary:
				province.recruits.append({"type": bundle.type, "soldiers": int(bundle.soldiers), "price": int(bundle.get("price", 0))})
			else:  # Version 1-3: a whole unit of a type.
				province.recruits.append({"type": bundle, "soldiers": UnitType.SOLDIERS})
		province.siege_faction = entry.siege_faction
		province.siege_turns = int(entry.siege_turns)
		state.provinces[region] = province
	for entry in data.units:
		var unit := Unit.new("", entry.owner, entry.region)
		unit.id = int(entry.id)
		if entry.has("troops"):
			for saved in entry.troops:
				var troop := Troop.new(saved.type, int(saved.soldiers))
				troop.hp = float(saved.hp)
				unit.add_troop(troop)
		else:  # Version 1-3: one type per unit, soldiers from HP.
			var troop := Troop.new(entry.type, 0)
			troop.hp = float(entry.hp)
			troop.soldiers = ceili(troop.hp / troop.soldier_hp() - 0.0001)
			unit.add_troop(troop)
		unit.move_points_left = int(entry.move_points_left)
		unit.attacked = entry.attacked
		unit.moved = entry.moved
		state.units.append(unit)
	state._next_unit_id = int(data.next_unit_id)
	state.rng.seed = int(data.rng_seed)
	state.rng.state = int(data.rng_state)
	state.mission = data.mission.duplicate(true)
	for key in data.mission_progress:
		state.mission_progress[key] = int(data.mission_progress[key])
	state.result = data.get("result", {}).duplicate()
	for key in ["stars", "crown", "points"]:
		if state.result.has(key):
			state.result[key] = int(state.result[key])
	for faction in data.get("kills", {}):
		state.kills[faction] = int(data.kills[faction])
	state.upgrades = data.get("upgrades", {}).duplicate(true)
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
		for order in (entry.orders if version >= 3 else [entry]):
			var troops := {}
			if order.has("troops"):
				for type_id in order.troops:
					troops[type_id] = int(order.troops[type_id])
			else:  # Version 1-3: a count of the unit's one type.
				var size := int(order.get("size", int(order.get("soldiers", unit.soldiers())) + int(order.get("shoot", 0))))
				troops = {unit.type_id: clampi(size, 1, unit.soldiers())}
			var saved := {"steps": order.steps.duplicate(true), "troops": troops, "size": Orders.total(troops),
				"support": order.get("support", false)}
			if order.has("attackers"):
				saved["attackers"] = {}
				for type_id in order.attackers:
					saved.attackers[type_id] = int(order.attackers[type_id])
			list.append(saved)
		state.orders[unit] = list
	return state


## Planned orders by army id, oldest army first, so saves are stable.
static func _orders_to_list(state: GameState) -> Array:
	var list := []
	for unit in state.units:
		if state.orders.has(unit):
			var orders := []
			for order in state.orders[unit]:
				var saved := {"steps": order.steps.duplicate(true), "troops": order.troops.duplicate(), "size": int(order.size),
					"support": order.get("support", false)}
				if order.has("attackers"):
					saved["attackers"] = order.attackers.duplicate()
				orders.append(saved)
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
	file.store_string(JSON.stringify(data, "", true, true))  # Full precision: health is fractional.
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
