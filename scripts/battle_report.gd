class_name BattleReport
extends PanelContainer
## After a battle: who won, why, and each regiment's losses (PRD BT-6).

signal closed

@onready var _body: RichTextLabel = $Margin/Rows/Body
@onready var _close_button: Button = $Margin/Rows/CloseButton


func _ready() -> void:
	_close_button.pressed.connect(func(): closed.emit())


func show_battle(state: GameState, battle: Battle, region: String, viewer: String) -> void:
	var names := {}
	for id in state.factions:
		names[id] = state.faction_name(id)
	for id in GameState.NON_PLAYABLE:
		names[id] = state.faction_name(id)
	var player_side := battle.attacker if battle.attacker.faction == viewer else battle.defender
	var involved := player_side.faction == viewer
	var player_won := (battle.attacker_won() and player_side == battle.attacker) \
		or (not battle.attacker_won() and player_side == battle.defender)
	var where := state.map.region_name(region)

	var lines := PackedStringArray()
	var title := ("Victory at %s" if player_won else "Defeat at %s") % where
	if battle.ending == "ranged":
		title = "Volleys at %s" % where
		player_won = true
	elif not involved:
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
		for i in side.units.size():
			var unit := side.units[i]
			var after := "destroyed" if unit.is_destroyed() else "%d" % unit.soldiers
			var note := " (shot from its own region)" if side.standoff.has(unit) else ""
			lines.append("    %s: %d → %s soldiers%s" % [unit.type().display_name, side.before[i][1], after, note])
	_body.text = "\n".join(lines)
	visible = true
