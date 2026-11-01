class_name ForecastPopup
extends PanelContainer
## Asks the player to confirm an attack, showing the battle forecast (PRD BT-7).

signal confirmed
signal cancelled

const RATING_COLORS := {
	"Decisive win": "#6fd36f", "Win": "#a8e07a", "Close": "#f0d060", "Loss": "#f0a050", "Decisive loss": "#f06050",
}

@onready var _body: RichTextLabel = $Margin/Rows/Body
@onready var _attack_button: Button = $Margin/Rows/Buttons/AttackButton
@onready var _cancel_button: Button = $Margin/Rows/Buttons/CancelButton


func _ready() -> void:
	_attack_button.pressed.connect(func(): confirmed.emit())
	_cancel_button.pressed.connect(func(): cancelled.emit())


func show_forecast(state: GameState, attackers: Array[Unit], region: String, forecast: Dictionary) -> void:
	var attacking_soldiers := 0
	for unit in attackers:
		attacking_soldiers += unit.soldiers()
	var defenders := state.enemy_units_in(region, attackers[0].owner)
	var defending_soldiers := 0
	for unit in defenders:
		defending_soldiers += unit.soldiers()
	var enemy := defenders[0].owner
	var lines := PackedStringArray()
	var verb := "Shoot at" if forecast.ranged else "Attack"
	lines.append("[font_size=22][b]%s %s?[/b][/font_size]" % [verb, state.map.region_name(region)])
	lines.append("%d unit%s (%d soldiers) against [color=#%s]%s[/color] (%d unit%s, %d soldiers) on %s." % [
		attackers.size(), "" if attackers.size() == 1 else "s", attacking_soldiers,
		state.faction_color(enemy).lightened(0.35).to_html(false), state.faction_name(enemy),
		defenders.size(), "" if defenders.size() == 1 else "s", defending_soldiers,
		state.map.terrain(region).display_name.to_lower()])
	if forecast.ranged:
		lines.append("[i]A ranged attack: your archers shoot from their own region, only enemy archers shoot back, and the region can't be taken.[/i]")
	lines.append("")
	lines.append("[font_size=20]Forecast: [b][color=%s]%s[/color][/b][/font_size]" % [
		RATING_COLORS.get(forecast.rating, "#ffffff"), forecast.rating])
	if not forecast.ranged:
		lines.append("You won %d of %d simulated battles." % [forecast.wins, forecast.runs])
	lines.append("Expected strength left: yours %d%%, theirs %d%%." % [
		roundi(forecast.attacker_survival * 100), roundi(forecast.defender_survival * 100)])
	_body.text = "\n".join(lines)
	_attack_button.text = "Shoot!" if forecast.ranged else "Attack!"
	visible = true
