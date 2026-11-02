extends RefCounted
## V5: the campaign expansion. The Crusader Orders and their bonus, the three
## new unit types (21 in all) and their counters, the new mission objectives,
## and the 25 missions in 6 campaigns: valid starts, reachable objectives and
## AI play.

const Helpers := preload("res://tests/helpers.gd")
const SEEDS := 20


func run(t) -> void:
	_test_roster(t)
	_test_pikemen_counters(t)
	_test_crusader_units(t)
	_test_crusader_bonus(t)
	_test_new_objectives(t)
	_test_missions(t)
	_test_unlocks(t)


func _test_roster(t) -> void:
	Rules.ensure_loaded()
	t.check(Rules.units.size() == 21, "21 unit types in all (%d)" % Rules.units.size())
	var pikemen := Rules.unit("pikemen")
	t.check(pikemen.civilization == "" and pikemen.unit_class == "infantry", "pikemen are base-roster infantry")
	t.check(Rules.civilization("crusader").special_units == ["brother_knight", "mounted_sergeant"]
		and Rules.unit("brother_knight").civilization == "crusader" and Rules.unit("mounted_sergeant").civilization == "crusader",
		"the Crusader Orders have the Brother Knight and the Mounted Sergeant")
	# Every unit's counter id has a full row and column in the counter table.
	var ids := {}
	for unit_id in Rules.units:
		ids[Rules.unit(unit_id).counter_id()] = true
	var missing := []
	for a in ids:
		for b in ids:
			if not Rules.counters.multipliers.get(a, {}).has(b):
				missing.append("%s>%s" % [a, b])
	t.check(missing.is_empty(), "the counter table covers every pair of unit types %s" % [missing])


func _units(_faction: String, type_id: String, copies: int) -> Array[Troop]:
	var made: Array[Troop] = []
	for i in copies:
		made.append(Troop.new(type_id, UnitType.SOLDIERS))
	return made


func _battle(attacking: String, defending: String, seed_value: int, terrain := "plains", copies := 1) -> Battle:
	var battle := Battle.new(Battle.Force.new("a", true, _units("a", attacking, copies)),
		Battle.Force.new("d", false, _units("d", defending, copies)), Rules.terrains[terrain], false, seed_value)
	battle.resolve()
	return battle


func _win_rate(attacking: String, defending: String, terrain := "plains") -> float:
	var wins := 0
	for s in SEEDS:
		if _battle(attacking, defending, s, terrain).attacker_won():
			wins += 1
	return float(wins) / SEEDS


func _attacker_survival(attacking: String, defending: String) -> float:
	var kept := 0.0
	for s in SEEDS:
		var battle := _battle(attacking, defending, s)
		kept += battle.survival(battle.attacker)
	return kept / SEEDS


## Average share of the defender lost to a ranged-only attack (two volleys).
func _volley_loss(shooter: String, target: String) -> float:
	var lost := 0.0
	for s in SEEDS:
		var battle := _battle(shooter, target, s)
		lost += 1.0 - battle.survival(battle.defender)
	return lost / SEEDS


func _test_pikemen_counters(t) -> void:
	var c := Rules.counters
	t.check(c.multiplier("pikemen", "heavy_cavalry") > c.multiplier("spearmen", "heavy_cavalry")
		and c.multiplier("heavy_cavalry", "pikemen") < c.multiplier("heavy_cavalry", "spearmen")
		and c.multiplier("light_cavalry", "pikemen") < c.multiplier("light_cavalry", "spearmen"),
		"pikemen counter cavalry harder than spearmen do")
	t.check(c.multiplier("archers", "pikemen") > c.multiplier("archers", "spearmen")
		and c.multiplier("swordsmen", "pikemen") > c.multiplier("swordsmen", "spearmen")
		and c.multiplier("pikemen", "archers") < 1.0,
		"but archers and swordsmen punish pikemen harder")

	# Cavalry charging pikemen loses; pikemen charging into... they don't, they hold.
	var vs_heavy := 1.0 - _win_rate("heavy_cavalry", "pikemen")
	var vs_knight := 1.0 - _win_rate("knight", "pikemen")
	var vs_light := 1.0 - _win_rate("light_cavalry", "pikemen")
	t.check(vs_heavy >= 0.8 and vs_knight >= 0.7 and vs_light >= 0.9,
		"pikemen beat cavalry charging them: heavy cavalry %d%%, knights %d%%, light cavalry %d%% of battles" % [
			roundi(vs_heavy * 100), roundi(vs_knight * 100), roundi(vs_light * 100)])
	t.check(_win_rate("pikemen", "light_cavalry") >= 0.8, "and win when they attack light cavalry (%d%%)" % roundi(_win_rate("pikemen", "light_cavalry") * 100))

	# Archers shoot them to pieces without a reply, and swordsmen cut through them.
	var pike_loss := _volley_loss("archers", "pikemen")
	var spear_loss := _volley_loss("archers", "spearmen")
	t.check(pike_loss > spear_loss * 1.15, "archer volleys hurt pikemen more than spearmen (%d%% vs %d%% lost)" % [
		roundi(pike_loss * 100), roundi(spear_loss * 100)])
	var pike_kept := _attacker_survival("pikemen", "archers")
	var spear_kept := _attacker_survival("spearmen", "archers")
	t.check(_win_rate("pikemen", "archers") <= 0.2 and pike_kept < spear_kept,
		"pikemen lose attacking archers, and bleed more than spearmen doing it (%d%% vs %d%% left)" % [
			roundi(pike_kept * 100), roundi(spear_kept * 100)])
	t.check(_win_rate("swordsmen", "pikemen") >= 0.7, "swordsmen beat pikemen (%d%%)" % roundi(_win_rate("swordsmen", "pikemen") * 100))


func _test_crusader_units(t) -> void:
	var knight := Rules.unit("brother_knight")
	t.check(knight.is_cavalry() and knight.counter_id() == "heavy_cavalry" and knight.charge_bonus > 1.0,
		"Brother Knights are heavy cavalry with a charge bonus")
	var vs_heavy := _win_rate("brother_knight", "heavy_cavalry")
	t.check(vs_heavy >= 0.6, "Brother Knights beat ordinary heavy cavalry (%d%%)" % roundi(vs_heavy * 100))
	t.check(_win_rate("brother_knight", "pikemen") <= 0.3 and _win_rate("brother_knight", "spearmen") <= 0.6,
		"but still break on pikes (%d%%) and struggle against spears (%d%%)" % [
			roundi(_win_rate("brother_knight", "pikemen") * 100), roundi(_win_rate("brother_knight", "spearmen") * 100)])

	var sergeant := Rules.unit("mounted_sergeant")
	t.check(sergeant.is_cavalry() and sergeant.counter_id() == "light_cavalry"
		and sergeant.hp > Rules.unit("light_cavalry").hp and sergeant.cost_gold > Rules.unit("light_cavalry").cost_gold,
		"Mounted Sergeants are tougher, dearer light cavalry")
	t.check(_win_rate("mounted_sergeant", "archers") >= 0.9 and _win_rate("mounted_sergeant", "light_cavalry") >= 0.6,
		"Mounted Sergeants ride down archers (%d%%) and beat light cavalry (%d%%)" % [
			roundi(_win_rate("mounted_sergeant", "archers") * 100), roundi(_win_rate("mounted_sergeant", "light_cavalry") * 100)])
	t.check(_win_rate("mounted_sergeant", "spearmen") <= 0.2, "and lose to spearmen (%d%%)" % roundi(_win_rate("mounted_sergeant", "spearmen") * 100))


func _test_crusader_bonus(t) -> void:
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red"}, [
		["blue", "greywater", "spearmen", 10], ["red", "kingsvale", "spearmen", 10]], 7, {"blue_civ": "crusader", "red_civ": "frankish"})
	var crusader: Unit = state.unit_in("greywater")
	var other: Unit = state.unit_in("kingsvale")
	crusader.moved = true
	other.moved = true
	t.check(Economy.heal_share(state, crusader) > 0.0 and Economy.heal_share(state, other) == 0.0,
		"Crusader hospitals heal armies at home even after they marched or fought")
	t.check(Economy.roster(state, "blue").has("brother_knight") and not Economy.roster(state, "red").has("brother_knight")
		and Economy.roster(state, "red").has("pikemen"), "only the Crusader Orders recruit Brother Knights; everyone can field pikemen")
	t.check(not Economy.bundle_of(state, "blue", "pikemen").is_empty(), "pikemen can be bought from the start")


func _test_new_objectives(t) -> void:
	# Destroy N soldiers of a type (replaces "kill or capture a general").
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red", "redfield": "red"}, [
		["blue", "greywater", "swordsmen"], ["red", "kingsvale", "militia"], ["red", "redfield", "militia"]], 7)
	state.mission = {"player": "blue", "primary": [{"type": "destroy_units", "faction": "red", "unit_type": "militia", "count": 15}], "crowns": [5, 7, 10]}
	t.check(not Mission.objectives(state)[0].done and Mission.objectives(state)[0].text.contains("15 militia"), "the destroy objective names the type and starts open")
	state.losses["red"] = {"militia": 15}
	t.check(Mission.objectives(state)[0].done, "it's done once 15 of them have fallen")
	state.update_result()
	t.check(state.is_over() and state.result.result == "won", "and that wins the mission while their faction lives on")

	# Survive N turns.
	state = Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "spearmen"]], 7)
	state.mission = {"player": "blue", "primary": [{"type": "survive", "turns": 3}], "crowns": [4, 5, 8]}
	var turns_to_win := 0
	for i in 6:
		Helpers.resolve(state)
		if state.is_over():
			turns_to_win = i + 1
			break
	t.check(turns_to_win == 3 and state.result.result == "won" and state.result.stars == 3,
		"surviving 3 turns wins on time with a gold crown (won after %d)" % turns_to_win)


## Regions reachable from `from` over the map's neighbour graph.
func _reachable(map: MapData, from: Array) -> Dictionary:
	var seen := {}
	var queue := from.duplicate()
	for region in from:
		seen[region] = true
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for next in map.neighbours(current):
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen


func _test_missions(t) -> void:
	var campaigns := Campaigns.all()
	t.check(campaigns.map(func(c): return c.civ) == ["norse", "anglish", "frankish", "crusader", "byzantine", "saracen"],
		"six campaigns, one per civilization")
	var total := 0
	var maps := {}
	var kinds := {}
	for campaign in campaigns:
		total += campaign.missions.size()
		t.check(campaign.missions.size() >= 3 and campaign.missions.size() <= 5, "%s has %d missions" % [campaign.name, campaign.missions.size()])
		var campaign_maps := {}
		for mission in campaign.missions:
			campaign_maps[mission.map] = true
		t.check(campaign_maps.size() == 1, "%s is fought on one map" % campaign.name)
		maps[campaign_maps.keys()[0]] = true
	t.check(total == 25, "25 missions in all (%d)" % total)
	t.check(maps.size() == 6, "every campaign has its own map %s" % [maps.keys()])

	for campaign in campaigns:
		for i in campaign.missions.size():
			var scenario := Campaigns.mission(campaign.id, i)
			var state := GameState.from_scenario(scenario, 1)
			var map := state.map
			var player := Mission.player(state)
			var problems := []
			var own: Array = map.province_order.filter(func(r): return state.owners[r] == player)
			var reach := _reachable(map, own)
			for faction in state.turn_order:
				if not state.capitals.has(faction) or state.owners[state.capitals[faction]] != faction:
					problems.append("%s doesn't hold its capital" % faction)
				if state.units_of(faction).is_empty():
					problems.append("%s has no army" % faction)
			for objective in state.mission.primary:
				kinds[objective.type] = true
				match objective.type:
					"capture":
						for region in objective.regions:
							if not map.provinces.has(region) or not reach.has(region):
								problems.append("can't reach " + region)
							elif state.owners[region] == player:
								problems.append("already holds " + region)
					"hold":
						if state.owners.get(objective.region) != player:
							problems.append("doesn't start with " + objective.region)
						if int(objective.turns) + 1 > Mission.time_limit(state):
							problems.append("hold longer than the limit")
					"survive":
						if int(objective.turns) + 1 > Mission.crowns(state)[0]:
							problems.append("survive past the gold crown")
					"destroy", "destroy_units":
						if not state.factions.has(objective.faction) or objective.faction == player:
							problems.append("bad target faction " + objective.faction)
						elif objective.type == "destroy_units" and not state.units_of(objective.faction).any(func(u): return u.type_id == objective.unit_type):
							problems.append("no %s to destroy" % objective.unit_type)
						elif not state.units_of(objective.faction).any(func(u): return reach.has(u.province)):
							problems.append("can't reach " + objective.faction)
			if Mission.objectives(state).any(func(o): return o.done):
				problems.append("an objective is done at the start")
			if scenario.mission.victory_text == "" or scenario.mission.defeat_text == "" or scenario.mission.briefing.length() < 40:
				problems.append("missing texts")
			t.check(problems.is_empty(), "%s %d \"%s\": valid start and reachable objectives %s" % [campaign.id, i + 1, scenario.name, problems])
	t.check(kinds.has("capture") and kinds.has("hold") and kinds.has("destroy") and kinds.has("destroy_units")
		and kinds.has("survive") and kinds.has("conquest"), "the missions use every kind of objective %s" % [kinds.keys()])

	# Each mission of the new content plays 12 AI-driven turns on both sides.
	var failed := []
	var turns := {}
	for campaign in campaigns:
		for i in campaign.missions.size():
			var state := GameState.from_scenario(Campaigns.mission(campaign.id, i), 11)
			state.factions[Mission.player(state)].human = false
			while not state.is_over() and state.turn <= 12:
				AI.play_turn(state)
				state.end_faction_turn()
			turns["%s_%d" % [campaign.id, i + 1]] = state.turn
			if state.units.is_empty() or (not state.is_over() and state.turn <= 12):
				failed.append(campaign.id + str(i + 1))
	t.check(failed.is_empty(), "the AI plays every mission for 12 turns (or to its end) without stalling %s" % [failed])


func _test_unlocks(t) -> void:
	Progress.path = "user://test_progress_v5.json"
	Progress.reset()
	t.check(Progress.campaign_unlocked("crusader") and Progress.mission_unlocked("crusader", 0), "the Crusader campaign is open from the start")
	t.check(not Progress.campaign_unlocked("byzantine") and not Progress.mission_unlocked("byzantine", 0)
		and not Progress.mission_unlocked("saracen", 0), "the Byzantine and Saracen campaigns start locked")
	for i in Campaigns.get_campaign("crusader").missions.size():
		Progress.record("crusader", i, 2)
	t.check(Progress.mission_unlocked("byzantine", 0) and not Progress.mission_unlocked("byzantine", 1) and not Progress.mission_unlocked("saracen", 0),
		"finishing one campaign opens the Byzantine campaign")
	for i in Campaigns.get_campaign("norse").missions.size():
		Progress.record("norse", i, 1)
	t.check(Progress.mission_unlocked("saracen", 0), "finishing two opens the Saracen campaign")
	DirAccess.remove_absolute(Progress.path)
	Progress.path = Progress.PATH
