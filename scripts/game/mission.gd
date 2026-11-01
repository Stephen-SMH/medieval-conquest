class_name Mission
extends RefCounted
## Mission objectives, par and turn limits, stars (PRD CP-2, CP-3), and the
## win condition for skirmish and hotseat (conquest).
##
## A scenario's "mission" holds:
##   "player": the faction the mission is for,
##   "objectives": [{"type": "capture", "regions": [...]},
##                  {"type": "hold", "region": "...", "turns": N},
##                  {"type": "destroy", "faction": "..."},
##                  {"type": "destroy_general", "faction": "...", "general": "name"},
##                  {"type": "survive", "turns": N},
##                  {"type": "conquest"}],
##   "par": turns for 3 stars (the hard limit is twice that),
##   "briefing", "victory_text", "defeat_text".
## Without a mission, the last faction standing wins.


static func is_mission(state: GameState) -> bool:
	return not state.mission.is_empty()


static func player(state: GameState) -> String:
	return state.mission.get("player", state.viewer())


static func par(state: GameState) -> int:
	return int(state.mission.get("par", 0))


static func hard_limit(state: GameState) -> int:
	return par(state) * 2


## 3 stars at or under par, 2 under 1.5 × par, otherwise 1 (CP-3).
static func stars_for(turns: int, par_turns: int) -> int:
	if turns <= par_turns:
		return 3
	if turns < par_turns * 1.5:
		return 2
	return 1


## Each objective with a description and whether it's done:
## [{"text": "Capture Eastwold", "done": false}, ...].
static func objectives(state: GameState) -> Array:
	var faction := player(state)
	var list := []
	for i in state.mission.get("objectives", []).size():
		var objective: Dictionary = state.mission.objectives[i]
		match objective.type:
			"capture":
				var names := PackedStringArray()
				var all_held := true
				for region in objective.regions:
					names.append(state.map.region_name(region))
					all_held = all_held and state.owners[region] == faction
				list.append({"text": "Capture %s" % ", ".join(names), "done": all_held})
			"hold":
				var held: int = state.mission_progress.get(str(i), 0)
				list.append({"text": "Hold %s for %d turns (%d so far)" % [state.map.region_name(objective.region),
					int(objective.turns), held], "done": held >= int(objective.turns)})
			"destroy":
				var target: String = objective.faction
				list.append({"text": "Destroy %s" % state.faction_name(target),
					"done": state.factions.has(target) and not state.factions[target].alive})
			"destroy_general":
				list.append({"text": "Kill or capture %s of %s" % [objective.general, state.faction_name(objective.faction)],
					"done": general_unit(state, objective.faction, objective.general) == null})
			"survive":
				var survived := mini(state.turn - 1, int(objective.turns))
				list.append({"text": "Hold out for %d turns (%d so far)" % [int(objective.turns), survived],
					"done": survived >= int(objective.turns)})
			"conquest":
				var rivals := state.living_factions().filter(func(f): return f != faction)
				list.append({"text": "Defeat every rival", "done": rivals.is_empty()})
	return list


## The unit leading a faction's named general, or null once he is killed or captured.
static func general_unit(state: GameState, faction: String, general_name: String) -> Unit:
	for unit in state.units:
		if unit.owner == faction and unit.general != null and unit.general.name == general_name:
			return unit
	return null


## At the end of the mission player's turn: counts turns held for "hold" objectives.
static func end_of_turn(state: GameState, faction: String) -> void:
	if not is_mission(state) or faction != player(state):
		return
	for i in state.mission.get("objectives", []).size():
		var objective: Dictionary = state.mission.objectives[i]
		if objective.type == "hold":
			var key := str(i)
			if state.owners[objective.region] == faction:
				state.mission_progress[key] = state.mission_progress.get(key, 0) + 1
			else:
				state.mission_progress[key] = 0


## Works out whether the game is over. Returns {} while it goes on, else
## {"result": "won"/"lost", "winner": faction, "stars": n, "reason": text}.
static func evaluate(state: GameState) -> Dictionary:
	var living := state.living_factions()
	if not is_mission(state):
		if living.size() <= 1:
			var winner: String = living[0] if not living.is_empty() else ""
			return {"result": "won", "winner": winner, "stars": 0,
				"reason": "%s has conquered every rival." % state.faction_name(winner)}
		return {}

	var faction := player(state)
	if not (faction in living):
		return {"result": "lost", "winner": "", "stars": 0, "reason": "Your realm has fallen."}
	if state.mission.get("lose_capital", true) and state.capitals.has(faction) and state.owners[state.capitals[faction]] != faction:
		return {"result": "lost", "winner": "", "stars": 0, "reason": "Your capital has fallen."}
	var list := objectives(state)
	if not list.is_empty() and list.all(func(o): return o.done):
		return {"result": "won", "winner": faction, "stars": stars_for(state.turn, par(state)),
			"reason": "Every objective complete on turn %d (par %d)." % [state.turn, par(state)]}
	if par(state) > 0 and state.turn > hard_limit(state):
		return {"result": "lost", "winner": "", "stars": 0,
			"reason": "Out of time: the limit was %d turns." % hard_limit(state)}
	return {}
