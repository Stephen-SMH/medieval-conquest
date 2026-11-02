class_name Mission
extends RefCounted
## Missions as in S&T (PRD H): a PRIMARY objective (every part of it must be
## done to win), ADDITIONAL objectives (optional, for points), DEFEAT
## conditions, gold, silver and bronze crowns for finishing within so many
## turns, and scripted events. Also the win condition for skirmish and
## hotseat (conquest).
##
## A scenario's "mission" holds:
##   "player": the faction the mission is for,
##   "primary": [objective, ...] and "additional": [objective, ...], where an
##     objective is one of
##       {"type": "capture", "regions": [...]}, {"type": "hold", "region": "...", "turns": N},
##       {"type": "destroy", "faction": "..."},
##       {"type": "destroy_units", "faction": "...", "unit_type": "...", "count": N},
##       {"type": "survive", "turns": N}, {"type": "conquest"},
##     each with optional "points" (score) and "text" (its own wording),
##   "defeat": [condition, ...], each one of
##       {"type": "time", "turns": N}: the primary objective isn't done by the end of turn N,
##       {"type": "lose_army"}: no soldiers left and none on the way,
##       {"type": "lose_region", "region": "...", "before": N}: losing it before turn N
##         (any time without "before"),
##   "crowns": [gold, silver, bronze]: finish by the end of these turns for a crown,
##   "events": [{"turn": N, "type": "reinforcements", "faction", "region", "unit", "soldiers"},
##              {"turn": N, "type": "message", "text": "..."}],
##   "history" (the briefing's intro), "briefing", "victory_text", "defeat_text".
## An older mission ({"objectives", "par", "lose_capital"}) reads as primary =
## objectives, crowns at par, under 1.5 × par and 2 × par, and defeat after
## 2 × par turns or when the capital falls.
## Without a mission, the last faction standing wins.

const PRIMARY_POINTS := 300
const ADDITIONAL_POINTS := 150
const CROWN_POINTS := [0, 100, 200, 300]  # None, bronze, silver, gold.
const CROWN_NAMES := ["", "bronze", "silver", "gold"]
## Development points (G) for a win: this many, one per additional objective
## done, and one for a bronze crown, two for silver, three for gold.
const DEVELOPMENT_FOR_WIN := 2


static func is_mission(state: GameState) -> bool:
	return not state.mission.is_empty()


static func player(state: GameState) -> String:
	return state.mission.get("player", state.viewer())


## The mission in the current format, converting an older one.
static func normalized(mission: Dictionary, capitals := {}) -> Dictionary:
	if mission.is_empty() or not mission.has("objectives"):
		return mission
	var result := mission.duplicate(true)
	result.erase("objectives")
	result.erase("par")
	result.erase("lose_capital")
	result["primary"] = mission.objectives.duplicate(true)
	result["additional"] = mission.get("additional", [])
	# Numbers stay floats, as JSON gives them, so a converted mission saves and loads unchanged.
	var par := float(mission.get("par", 0))
	var defeat := []
	if par > 0:
		result["crowns"] = [par, ceilf(par * 1.5) - 1.0, par * 2.0]
		defeat.append({"type": "time", "turns": par * 2.0})
	var player_id: String = mission.get("player", "")
	if mission.get("lose_capital", true) and capitals.has(player_id):
		defeat.append({"type": "lose_region", "region": capitals[player_id]})
	result["defeat"] = defeat
	return result


static func _spec(state: GameState) -> Dictionary:
	return normalized(state.mission, state.capitals)


## [gold, silver, bronze] turn limits, or [] for a mission without crowns.
static func crowns(state: GameState) -> Array:
	return _spec(state).get("crowns", []).map(func(turns): return int(turns))


## 3 for gold, 2 silver, 1 bronze, 0 for none: the crown for finishing on `turn`.
static func crown_for(turn: int, limits: Array) -> int:
	for i in limits.size():
		if turn <= int(limits[i]):
			return 3 - i
	return 0


## The crown still to be had and the turns left for it, counting this one:
## {"crown": 3, "turns_left": 6}; crown 0 once the bronze one has gone.
static func crown_now(state: GameState) -> Dictionary:
	var limits := crowns(state)
	var crown := crown_for(state.turn, limits)
	if crown == 0:
		return {"crown": 0, "turns_left": 0}
	return {"crown": crown, "turns_left": int(limits[3 - crown]) - state.turn + 1}


## The turn after which an unfinished primary objective loses, or 0 for none.
static func time_limit(state: GameState) -> int:
	for condition in _spec(state).get("defeat", []):
		if condition.type == "time":
			return int(condition.turns)
	return 0


## The primary objective's parts: [{"text": "Capture Eastwold", "done": false, "points": 300}, ...].
static func primary(state: GameState) -> Array:
	return _describe(state, _spec(state).get("primary", []), PRIMARY_POINTS, "primary")


static func additional(state: GameState) -> Array:
	return _describe(state, _spec(state).get("additional", []), ADDITIONAL_POINTS, "additional")


## Primary then additional objectives, each with "primary": true or false.
static func objectives(state: GameState) -> Array:
	var list := []
	for entry in primary(state):
		entry["primary"] = true
		list.append(entry)
	for entry in additional(state):
		entry["primary"] = false
		list.append(entry)
	return list


## How many parts of the primary objective are still to do (the HUD's crossed swords).
static func primary_left(state: GameState) -> int:
	return primary(state).filter(func(o): return not o.done).size()


static func _describe(state: GameState, list: Array, default_points: int, kind: String) -> Array:
	var faction := player(state)
	var result := []
	for i in list.size():
		var objective: Dictionary = list[i]
		var entry := _objective(state, objective, faction, "%s/%d" % [kind, i])
		entry["points"] = int(objective.get("points", default_points))
		if objective.has("text"):
			entry.text = objective.text
		result.append(entry)
	return result


static func _objective(state: GameState, objective: Dictionary, faction: String, key: String) -> Dictionary:
	match objective.type:
		"capture":
			var names := PackedStringArray()
			var all_held := true
			for region in objective.regions:
				names.append(state.map.region_name(region))
				all_held = all_held and state.owners[region] == faction
			return {"text": "Capture %s" % ", ".join(names), "done": all_held}
		"hold":
			var held: int = state.mission_progress.get(key, 0)
			return {"text": "Hold %s for %d turns (%d so far)" % [state.map.region_name(objective.region), int(objective.turns), held],
				"done": held >= int(objective.turns)}
		"destroy":
			var target: String = objective.faction
			return {"text": "Destroy %s" % state.faction_name(target), "done": state.factions.has(target) and not state.factions[target].alive}
		"destroy_units":
			var killed := soldiers_killed(state, objective.faction, objective.unit_type)
			return {"text": "Destroy %d %s of %s (%d so far)" % [int(objective.count), Rules.unit(objective.unit_type).plural_name().to_lower(),
				state.faction_name(objective.faction), mini(killed, int(objective.count))], "done": killed >= int(objective.count)}
		"survive":
			var survived := mini(state.turn - 1, int(objective.turns))
			return {"text": "Hold out for %d turns (%d so far)" % [int(objective.turns), survived], "done": survived >= int(objective.turns)}
		"conquest":
			var rivals := state.living_factions().filter(func(f): return f != faction)
			return {"text": "Defeat every rival", "done": rivals.is_empty()}
	return {"text": objective.type, "done": false}


## An objective's words without its running count: "Hold X for 3 turns".
static func plain(text: String) -> String:
	return text.left(text.rfind(" (")) if text.ends_with("so far)") else text


## The defeat conditions in words, for the briefing and the objectives list.
static func defeats(state: GameState) -> Array:
	return describe_defeats(_spec(state).get("defeat", []), state.map)


static func describe_defeats(conditions: Array, map: MapData) -> Array:
	var lines := []
	for condition in conditions:
		match condition.type:
			"time":
				lines.append("The primary objective isn't done in %d turns" % int(condition.turns))
			"lose_army":
				lines.append("You lose all your troops")
			"lose_region":
				if condition.has("before"):
					lines.append("You lose %s before turn %d" % [map.region_name(condition.region), int(condition.before)])
				else:
					lines.append("You lose %s" % map.region_name(condition.region))
	return lines


## Soldiers of a type a faction has lost since the mission began.
static func soldiers_killed(state: GameState, faction: String, unit_type: String) -> int:
	return int(state.losses.get(faction, {}).get(unit_type, 0))


## At the start of each turn (before the first faction plays): the mission's
## scripted events for this turn. Reinforcements join the army in their
## region (or form one) if their faction holds it and nobody else is there.
## Each event's note goes into state.mission_log and the returned events.
static func start_of_turn(state: GameState) -> Array:
	var events := []
	for event in state.mission.get("events", []):
		if int(event.get("turn", 0)) != state.turn:
			continue
		var text: String = event.get("text", "")
		if event.type == "reinforcements":
			var region: String = event.region
			var army := state.unit_in(region)
			if not state.factions.has(event.faction) or state.owners.get(region) != event.faction or (army != null and army.owner != event.faction):
				continue
			if army == null:
				army = state.add_unit("", event.faction, region)
			var count := mini(int(event.soldiers), Unit.CAP - army.soldiers())
			if count <= 0:
				continue
			army.add(event.unit, count)
			if text == "":
				text = "%s arrived in the province of %s: %s – %d" % ["Reinforcements" if event.faction == player(state) else "Enemy reinforcements",
					state.map.region_name(region), Rules.unit(event.unit).display_name, count]
		if text != "":
			state.mission_log.append({"turn": state.turn, "text": text})
			events.append({"type": "mission_note", "text": text})
	return events


## At the end of the mission player's turn: counts turns held for "hold" objectives.
static func end_of_turn(state: GameState, faction: String) -> void:
	if not is_mission(state) or faction != player(state):
		return
	var spec := _spec(state)
	for kind in ["primary", "additional"]:
		var list: Array = spec.get(kind, [])
		for i in list.size():
			if list[i].type == "hold":
				var key := "%s/%d" % [kind, i]
				if state.owners[list[i].region] == faction:
					state.mission_progress[key] = state.mission_progress.get(key, 0) + 1
				else:
					state.mission_progress[key] = 0


## Works out whether the game is over. Returns {} while it goes on, else
## {"result": "won"/"lost", "winner": faction, "reason": text} plus, for a
## mission: "stars" (the crown, 3 gold to 0 none), "points", "development",
## "turns" and "objectives" (each with "done" and "points").
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
		return _lost(state, "Your realm has fallen.")
	var main := primary(state)
	var done := not main.is_empty() and main.all(func(o): return o.done)
	if not done:
		for condition in _spec(state).get("defeat", []):
			var reason := _defeat_reason(state, condition, faction)
			if reason != "":
				return _lost(state, reason)
	if done:
		var crown := crown_for(state.turn, crowns(state))
		var list := objectives(state)
		var points: int = CROWN_POINTS[crown]
		var extra := 0
		for objective in list:
			if objective.done:
				points += int(objective.points)
				if not objective.primary:
					extra += 1
		return {"result": "won", "winner": faction, "stars": crown, "points": points, "turns": state.turn,
			"development": DEVELOPMENT_FOR_WIN + extra + crown, "objectives": list,
			"reason": "The primary objective is done on turn %d%s." % [state.turn,
				", for a %s crown" % CROWN_NAMES[crown] if crown > 0 else ""]}
	return {}


## A faction gives up (the pause menu, PRD K). In a mission, or a game one
## person plays, that loses the game; in hotseat the faction leaves it: its
## armies disband and its regions fall neutral, and the others play on.
static func surrender(state: GameState, faction: String) -> void:
	var humans := state.turn_order.filter(func(f): return state.factions[f].human)
	if is_mission(state) or humans.size() <= 1:
		state.result = _lost(state, "%s surrendered." % ("You" if is_mission(state) else state.faction_name(faction)))
		return
	for unit in state.units_of(faction):
		state.remove_unit(unit)
	for region in state.map.province_order:
		if state.owners[region] == faction:
			state.owners[region] = "neutral"
			state.provinces[region].recruits.clear()
	state.capitals.erase(faction)
	state.update_alive()
	state.update_result()


static func _defeat_reason(state: GameState, condition: Dictionary, faction: String) -> String:
	match condition.type:
		"time":
			if state.turn > int(condition.turns):
				return "Out of time: the primary objective wasn't done in %d turns." % int(condition.turns)
		"lose_army":
			var coming := state.map.province_order.any(func(r): return state.owners[r] == faction and not state.provinces[r].recruits.is_empty())
			if state.units_of(faction).is_empty() and not coming:
				return "All your troops are lost."
		"lose_region":
			var region: String = condition.region
			if state.owners[region] != faction and (not condition.has("before") or state.turn < int(condition.before)):
				return "%s has fallen." % state.map.region_name(region)
	return ""


static func _lost(state: GameState, reason: String) -> Dictionary:
	return {"result": "lost", "winner": "", "stars": 0, "points": 0, "development": 0, "turns": state.turn,
		"objectives": objectives(state), "reason": reason}
