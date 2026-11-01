extends SceneTree
func force(f, att, types, n):
	var regs: Array[Regiment] = []
	for i in n:
		for t in types: regs.append(Regiment.new(t))
	return Battle.Force.new(f, att, regs, 1.0)
func duel(a, d, terrain, n := 6, river := false):
	Rules.ensure_loaded()
	var wins := 0; var endings := {}; var rounds := 0.0; var asurv := 0.0; var dsurv := 0.0
	for s in 50:
		var b := Battle.new(force("a", true, a, n), force("d", false, d, n), Rules.terrains[terrain], river, s)
		b.resolve()
		if b.attacker_won(): wins += 1
		endings[b.ending] = endings.get(b.ending, 0) + 1
		rounds += b.rounds_fought; asurv += b.survival(b.attacker); dsurv += b.survival(b.defender)
	print("%s vs %s on %s: att wins %d/50 %s rounds %.1f surv a %.2f d %.2f" % [a, d, terrain, wins, endings, rounds/50, asurv/50, dsurv/50])
func _init():
	duel(["spearmen"], ["heavy_cavalry"], "plains")
	duel(["heavy_cavalry"], ["spearmen"], "plains")
	duel(["archers"], ["light_cavalry"], "plains")
	duel(["light_cavalry"], ["archers"], "plains")
	duel(["swordsmen"], ["swordsmen"], "plains")
	duel(["swordsmen"], ["swordsmen"], "mountains")
	duel(["swordsmen"], ["swordsmen"], "plains", 6, true)
	duel(["spearmen"], ["spearmen"], "plains")
	duel(["militia"], ["militia"], "hills")
	duel(["archers"], ["spearmen"], "plains")
	duel(["swordsmen"], ["spearmen"], "plains")
	duel(["spearmen","spearmen","swordsmen","swordsmen","archers","archers","light_cavalry"], ["militia","militia","spearmen"], "plains", 1)
	quit()
