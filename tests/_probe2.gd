extends SceneTree
func force(f, att, t, n):
	var regs: Array[Regiment] = []
	for i in n: regs.append(Regiment.new(t))
	return Battle.Force.new(f, att, regs, 1.0)
func _init():
	Rules.ensure_loaded()
	var b := Battle.new(force("a", true, "spearmen", 6), force("d", false, "heavy_cavalry", 6), Rules.terrains["plains"], false, 1)
	b.resolve()
	for f in [b.attacker, b.defender]:
		print(f.faction, " morale ", f.morale, " men ", f.regiments.map(func(r): return roundi(r.men)))
	print(b.counter_damage)
	quit()
