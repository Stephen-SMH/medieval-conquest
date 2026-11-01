extends RefCounted
## M3: counters, auto-resolved battles, forecasts, retreat and occupation.

const SEEDS := 30


func run(t) -> void:
	Rules.ensure_loaded()

	t.check(Rules.counters.multiplier("spearmen", "heavy_cavalry") == 2.0, "counter table: spearmen vs heavy cavalry ×2.0")
	t.check(Rules.counters.multiplier("light_cavalry", "archers") == 2.0, "counter table: light cavalry vs archers ×2.0")
	t.check(Rules.counters.multiplier("archers", "spearmen") == 1.25, "counter table: archers vs spearmen ×1.25")
	t.check(Rules.counters.multiplier("heavy_cavalry", "spearmen") == 0.6, "counter table: heavy cavalry vs spearmen ×0.6")
	t.check(Rules.counters.multiplier("catapult", "light_cavalry") == 0.5, "counter table: catapult vs light cavalry ×0.5")

	# Determinism: the same seed gives exactly the same battle.
	var first := _battle(["swordsmen", "archers", "light_cavalry"], ["spearmen", "militia", "heavy_cavalry"], "plains", 3, 42)
	var second := _battle(["swordsmen", "archers", "light_cavalry"], ["spearmen", "militia", "heavy_cavalry"], "plains", 3, 42)
	t.check(_fingerprint(first) == _fingerprint(second), "the same seed gives the same battle, man for man")
	var differs := false
	for s in range(1, 10):
		differs = differs or _fingerprint(_battle(["swordsmen", "archers", "light_cavalry"], ["spearmen", "militia", "heavy_cavalry"], "plains", 3, 42 + s)) != _fingerprint(first)
	t.check(differs, "different seeds give different battles")

	# Sanity checks from the PRD counter table, over many seeds, both as attacker and defender.
	t.check(_win_rate(["spearmen"], ["heavy_cavalry"], "plains") == 1.0, "6 spearmen attacking beat 6 heavy cavalry on plains every time")
	t.check(_win_rate(["heavy_cavalry"], ["spearmen"], "plains") == 0.0, "6 heavy cavalry attacking lose to 6 spearmen on plains every time")
	t.check(_win_rate(["archers"], ["light_cavalry"], "plains") == 0.0, "6 archers attacking lose to 6 light cavalry on plains every time")
	t.check(_win_rate(["light_cavalry"], ["archers"], "plains") == 1.0, "6 light cavalry attacking beat 6 archers on plains every time")
	t.check(_win_rate(["archers"], ["spearmen"], "plains") >= 0.9, "archers beat spearmen")
	t.check(_win_rate(["swordsmen"], ["spearmen"], "plains") >= 0.9, "swordsmen beat spearmen")

	# Terrain and rivers.
	var open_field := _survival(["swordsmen"], ["swordsmen"], "plains", false)
	var mountains := _survival(["swordsmen"], ["swordsmen"], "mountains", false)
	var river := _survival(["swordsmen"], ["swordsmen"], "plains", true)
	t.check(mountains < open_field, "attacking into mountains costs the attacker more (%.2f vs %.2f left)" % [mountains, open_field])
	t.check(river < open_field, "crossing a river costs the attacker more (%.2f vs %.2f left)" % [river, open_field])
	var cavalry_plains := _survival(["light_cavalry"], ["swordsmen"], "plains", false)
	var cavalry_mountains := _survival(["light_cavalry"], ["swordsmen"], "mountains", false)
	t.check(cavalry_mountains < cavalry_plains, "cavalry loses more men attacking in mountains (%.2f vs %.2f left)" % [cavalry_mountains, cavalry_plains])

	# Morale and rout.
	var rout := _battle(["light_cavalry"], ["archers"], "plains", 6, 7)
	t.check(rout.ending == "rout" and rout.defender.routed and rout.defender.morale <= Battle.ROUT_MORALE,
		"a side routs when its morale falls to %d" % Battle.ROUT_MORALE)
	var endings := {}
	for s in SEEDS:
		endings[_battle(["swordsmen", "militia"], ["spearmen", "archers"], "hills", 4, s).ending] = true
	t.check(endings.keys().all(func(e): return e in ["rout", "destroyed", "held"]), "every battle ends in a rout, destruction or the defenders holding %s" % [endings.keys()])

	# Regiments scale with the men left.
	var full := Regiment.new("swordsmen")
	var half := Regiment.new("swordsmen", 50.0)
	t.check(is_equal_approx(half.hp(), full.hp() / 2.0), "a half-strength regiment has half the HP")
	var weak := _battle(["swordsmen"], ["swordsmen"], "plains", 6, 1, 50.0)
	t.check(not weak.attacker_won() and weak.survival(weak.defender) > 0.6, "half-strength regiments hit softer and lose")

	var names := {"a": "Attackers", "d": "Defenders"}
	var reasons := _battle(["spearmen"], ["heavy_cavalry"], "plains", 6, 3).explain("a", names)
	t.check(reasons.size() >= 3 and "×2.00" in "\n".join(reasons), "the report explains the result, naming the ×2.00 counter")

	_test_game_battles(t)


func _test_game_battles(t) -> void:
	var map := MapData.load_default()
	var state := GameState.new_game(map, 99)
	var army := state.armies_in("greywater")[0]
	var men_before := army.total_men()

	var forecast := state.forecast_battle(army, "kingsvale")
	t.check(army.total_men() == men_before and state.armies_in("kingsvale").size() == 1, "a forecast changes nothing")
	t.check(forecast.rating in ["Decisive win", "Win", "Close", "Loss", "Decisive loss"] and forecast.runs == Battle.FORECAST_RUNS,
		"forecast rating: %s (%d of %d won)" % [forecast.rating, forecast.wins, forecast.runs])
	t.check(state.forecast_battle(army, "kingsvale") == forecast, "the same forecast twice gives the same answer")
	t.check(forecast.rating == "Decisive win", "7 regiments against a 3-regiment garrison forecasts a decisive win")

	var events := state.order_move(army, "kingsvale")
	var battle_events := events.filter(func(e): return e.type == "battle")
	t.check(battle_events.size() == 1, "marching into an enemy army starts a battle")
	t.check(army.province == "kingsvale" and state.owners["kingsvale"] == "aldmere",
		"the winner moves in and takes the province")
	t.check(events.any(func(e): return e.type == "occupied"), "taking the province is reported")
	var garrison_left := state.armies.filter(func(a): return a.owner == "brennwald" and a.is_garrison())
	t.check(garrison_left.is_empty() or garrison_left[0].province == "highcrag",
		"the beaten garrison retreats to a neighbouring Brennwald province or is destroyed")
	t.check(army.total_men() < men_before and army.movement_left == 0, "the winner takes losses and stops for the turn")

	# Marching into an empty enemy province takes it without a fight.
	var raider := state.add_army("aldmere", "kingsvale", General.new("Raider"), ["light_cavalry"])
	state.armies = state.armies.filter(func(a): return a.province != "highcrag" or a.owner == "aldmere")
	var occupy := state.order_move(raider, "highcrag")
	t.check(state.owners["highcrag"] == "aldmere" and occupy.any(func(e): return e.type == "occupied"),
		"an undefended enemy province is occupied")

	# A beaten attacker stays where it was.
	var weak := state.add_army("aldmere", "greywater", General.new("Weak"), ["militia"])
	state.add_army("corvane", "northmarch", null, ["spearmen", "spearmen", "spearmen", "swordsmen"])
	state.order_move(weak, "northmarch")
	t.check(not state.armies.has(weak) or weak.province == "greywater", "a beaten attacker stays in its own province")
	t.check(state.owners["northmarch"] == "aldmere", "a defending army does not take the province it stands in")


func _force(faction: String, attacking: bool, types: Array, copies: int, men: float) -> Battle.Force:
	var regiments: Array[Regiment] = []
	for i in copies:
		for type_id in types:
			regiments.append(Regiment.new(type_id, men))
	return Battle.Force.new(faction, attacking, regiments, 1.0)


func _battle(attacking: Array, defending: Array, terrain: String, copies: int, seed_value: int,
		attacker_men := 100.0, river := false) -> Battle:
	var battle := Battle.new(_force("a", true, attacking, copies, attacker_men), _force("d", false, defending, copies, 100.0),
		Rules.terrains[terrain], river, seed_value)
	battle.resolve()
	return battle


func _win_rate(attacking: Array, defending: Array, terrain: String) -> float:
	var wins := 0
	for s in SEEDS:
		if _battle(attacking, defending, terrain, 6, s).attacker_won():
			wins += 1
	return float(wins) / SEEDS


func _survival(attacking: Array, defending: Array, terrain: String, river: bool) -> float:
	var total := 0.0
	for s in SEEDS:
		var battle := _battle(attacking, defending, terrain, 6, s, 100.0, river)
		total += battle.survival(battle.attacker)
	return total / SEEDS


func _fingerprint(battle: Battle) -> String:
	var parts := [battle.winner, battle.ending, battle.rounds_fought]
	for force in [battle.attacker, battle.defender]:
		for regiment in force.regiments:
			parts.append("%.6f" % regiment.men)
	return str(parts)
