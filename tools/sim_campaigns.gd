extends SceneTree
## Balance check for the campaigns: the AI plays the mission player's side
## (as a "balanced" computer faction) in every mission, several times with
## different seeds, up to the hard turn limit, and prints how often it wins
## and how fast. It plays each mission three ways: "free", the plain
## balanced AI; "garrison", which never sends the capital's unit out (it may
## still shoot), as a careful person wouldn't; and "bold", the aggressive AI,
## which attacks on closer odds, as a person pressing an offensive does. A
## rough stand-in for a human: missions every style wins easily are easy,
## ones no style wins need a look.
##   godot --headless -s tools/sim_campaigns.gd [-- --seeds=N --only=campaign_id]

var seeds := 6
var only := ""


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = int(arg.trim_prefix("--seeds="))
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	Rules.ensure_loaded()
	for campaign in Campaigns.all():
		if only != "" and campaign.id != only:
			continue
		print("== %s (%s)" % [campaign.name, campaign.civ])
		for i in campaign.missions.size():
			var line := "  %d. %-26s par %2d" % [i + 1, campaign.missions[i].name, int(campaign.missions[i].mission.par)]
			for style in ["free", "garrison", "bold"]:
				var wins := 0
				var turns := 0
				for s in seeds:
					var state := _play(campaign.id, i, 100 + s, style)
					if state.result.result == "won":
						wins += 1
						turns += state.turn
				line += "  | %s %d/%d, turn %s" % [style, wins, seeds,
					"%4.1f" % (turns / float(wins)) if wins > 0 else "   -"]
			print(line)
	quit()


func _play(campaign_id: String, index: int, game_seed: int, style: String) -> GameState:
	var state := GameState.from_scenario(Campaigns.mission(campaign_id, index), game_seed)
	var player := Mission.player(state)
	state.factions[player].human = false
	state.factions[player].ai = "aggressive" if style == "bold" else "balanced"
	while not state.is_over():
		var planning := state.current_faction()
		AI.play_turn(state)
		if style == "garrison" and planning == player and state.capitals.has(player):
			var unit := state.unit_in(state.capitals[player])
			if unit != null and unit.owner == player:
				if Orders.orders_of(state, unit).any(func(o): return o.steps[0].type == "move" or int(o.size) > 0):
					Orders.cancel(state, unit)
		state.end_faction_turn()
	return state
