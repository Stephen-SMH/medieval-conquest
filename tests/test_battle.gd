extends RefCounted
## The battle engine on troops: counters, determinism, terrain, morale, ranged
## attacks, walls and forecasts.

const SEEDS := 30
const Helpers := preload("res://tests/helpers.gd")


func run(t) -> void:
	Rules.ensure_loaded()
	t.check(Rules.counters.multiplier("spearmen", "heavy_cavalry") == 2.0, "counter table: spearmen vs heavy cavalry ×2.0")
	t.check(Rules.counters.multiplier("light_cavalry", "archers") == 2.0, "counter table: light cavalry vs archers ×2.0")
	t.check(Rules.counters.multiplier("archers", "spearmen") == 1.25, "counter table: archers vs spearmen ×1.25")
	t.check(Rules.counters.multiplier("yeoman", "knight") == 2.0, "special units use their base unit's row and column: yeoman vs knight ×2.0")

	var first := _battle(["swordsmen", "archers", "light_cavalry"], ["spearmen", "militia", "heavy_cavalry"], "plains", 1, 42)
	var second := _battle(["swordsmen", "archers", "light_cavalry"], ["spearmen", "militia", "heavy_cavalry"], "plains", 1, 42)
	t.check(_fingerprint(first) == _fingerprint(second), "the same seed gives the same battle, HP for HP")
	var differs := false
	for s in range(1, 10):
		differs = differs or _fingerprint(_battle(["swordsmen", "archers", "light_cavalry"], ["spearmen", "militia", "heavy_cavalry"], "plains", 1, 42 + s)) != _fingerprint(first)
	t.check(differs, "different seeds give different battles")

	t.check(_win_rate(["spearmen"], ["heavy_cavalry"], "plains") == 1.0, "4 spearmen attacking beat 4 heavy cavalry on plains every time")
	t.check(_win_rate(["heavy_cavalry"], ["spearmen"], "plains") == 0.0, "4 heavy cavalry attacking lose to 4 spearmen every time")
	t.check(_win_rate(["light_cavalry"], ["archers"], "plains") == 1.0, "4 light cavalry beat 4 archers every time")
	t.check(_win_rate(["spearmen"], ["archers"], "plains") == 0.0, "archers defending beat spearmen")
	t.check(_win_rate(["swordsmen"], ["spearmen"], "plains") >= 0.9, "swordsmen beat spearmen")
	t.check(_win_rate(["light_cavalry"], ["swordsmen"], "plains") <= 0.1, "light cavalry don't beat swordsmen")

	var open_field := _survival(["swordsmen"], ["swordsmen"], "plains", false)
	t.check(_survival(["swordsmen"], ["swordsmen"], "mountains", false) < open_field, "attacking into mountains costs more")
	t.check(_survival(["swordsmen"], ["swordsmen"], "plains", true) < open_field, "attacking across a river costs more")

	var rout := _battle(["light_cavalry"], ["archers"], "plains", 4, 7)
	t.check(rout.ending == "rout" and rout.defender.routed and rout.defender.morale <= Battle.ROUT_MORALE,
		"a side routs when its morale falls to %d" % Battle.ROUT_MORALE)

	var ranged := _battle(["archers", "crossbowmen"], ["spearmen"], "plains", 2, 3)
	t.check(ranged.ranged_only() and ranged.ending == "ranged" and not ranged.attacker_won()
		and ranged.survival(ranged.attacker) == 1.0 and ranged.survival(ranged.defender) < 1.0,
		"a ranged-only attack: volleys only, melee defenders can't reply, nobody wins the region")

	var walled_a := Battle.Force.new("a", true, _units("a", ["swordsmen", "swordsmen"]))
	var walled_d := Battle.Force.new("d", false, _units("d", ["spearmen", "spearmen"]))
	walled_d.wall_bonus = 1.0
	var walled := Battle.new(walled_a, walled_d, Rules.terrains.plains, false, 5)
	walled.resolve()
	var open := _battle(["swordsmen"], ["spearmen"], "plains", 2, 5)
	t.check(walled.survival(walled.defender) > open.survival(open.defender), "walls protect defenders")

	var reasons := _battle(["spearmen"], ["heavy_cavalry"], "plains", 4, 3).explain("a", {"a": "A", "d": "D"})
	t.check(reasons.size() >= 3 and "×2.00" in "\n".join(reasons), "the report explains the result, naming the ×2.00 counter")

	var state := Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "heavy_cavalry"], ["red", "kingsvale", "militia"]])
	var hp_before := state.units[1].hp
	var forecast := state.forecast_attack(state.units_in("greywater"), "kingsvale")
	t.check(state.units[1].hp == hp_before and forecast.rating == "Decisive win", "a forecast rates the attack and changes nothing (%s)" % forecast.rating)
	t.check(state.forecast_attack(state.units_in("greywater"), "kingsvale") == forecast, "the same forecast twice gives the same answer")


func _units(_faction: String, types: Array, copies := 1) -> Array[Troop]:
	var made: Array[Troop] = []
	for i in copies:
		for type_id in types:
			made.append(Troop.new(type_id, UnitType.SOLDIERS))
	return made


func _battle(attacking: Array, defending: Array, terrain: String, copies: int, seed_value: int, river := false) -> Battle:
	var battle := Battle.new(Battle.Force.new("a", true, _units("a", attacking, copies)),
		Battle.Force.new("d", false, _units("d", defending, copies)), Rules.terrains[terrain], river, seed_value)
	battle.resolve()
	return battle


func _win_rate(attacking: Array, defending: Array, terrain: String) -> float:
	var wins := 0
	for s in SEEDS:
		if _battle(attacking, defending, terrain, 4, s).attacker_won():
			wins += 1
	return float(wins) / SEEDS


func _survival(attacking: Array, defending: Array, terrain: String, river: bool) -> float:
	var total := 0.0
	for s in SEEDS:
		var battle := _battle(attacking, defending, terrain, 4, s, river)
		total += battle.survival(battle.attacker)
	return total / SEEDS


func _fingerprint(battle: Battle) -> String:
	var parts := [battle.winner, battle.ending, battle.rounds_fought]
	for force in [battle.attacker, battle.defender]:
		for unit in force.units:
			parts.append("%.6f" % unit.hp)
	return str(parts)
