class_name BattleReport
extends PanelContainer
## After a battle: who won, why, and each regiment's losses (PRD BT-6).

signal closed

@onready var _body: RichTextLabel = $Margin/Rows/Body
@onready var _close_button: Button = $Margin/Rows/CloseButton


func _ready() -> void:
	_close_button.pressed.connect(func(): closed.emit())


func show_battle(state: GameState, battle: Battle, province: String) -> void:
	var viewer := state.player
	var names := {}
	for id in state.map.factions:
		names[id] = state.map.factions[id].name
	var player_side := battle.attacker if battle.attacker.faction == viewer else battle.defender
	var player_won := (battle.attacker_won() and player_side == battle.attacker) \
		or (not battle.attacker_won() and player_side == battle.defender)
	var where: String = state.map.provinces[province].name

	var lines := PackedStringArray()
	var title := ("Victory at %s" if player_won else "Defeat at %s") % where
	if player_side.faction != viewer:
		title = "Battle of %s" % where
	lines.append("[font_size=22][b][color=%s]%s[/color][/b][/font_size]" % [
		"#8fe08f" if player_won else "#f08070", title])
	lines.append("")
	lines.append("[b]Why[/b]")
	for reason in battle.explain(viewer, names):
		lines.append("•  " + reason)
	for side: Battle.Force in [battle.attacker, battle.defender]:
		lines.append("")
		var role := "Attackers" if side.attacking else "Defenders"
		lines.append("[b]%s — %s[/b] (morale %d%s)" % [role, names.get(side.faction, side.faction),
			roundi(side.morale), ", routed" if side.routed else ""])
		for i in side.regiments.size():
			var regiment := side.regiments[i]
			var before: float = side.before[i][1]
			var after := regiment.men
			var result := "destroyed" if after < Battle.DESTROYED_BELOW else "%d" % roundi(after)
			lines.append("    %s: %d → %s" % [regiment.type().display_name, roundi(before), result])
	_body.text = "\n".join(lines)
	visible = true
