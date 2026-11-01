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


func show_forecast(state: GameState, army: Army, province: String, forecast: Dictionary) -> void:
	var defenders := state.enemy_armies_in(province, army.owner)
	var enemy_men := 0.0
	for defender in defenders:
		enemy_men += defender.total_men()
	var enemy: Dictionary = state.map.factions[defenders[0].owner]
	var lines := PackedStringArray()
	lines.append("[font_size=22][b]Attack %s?[/b][/font_size]" % state.map.provinces[province].name)
	lines.append("%s (%d men) against [color=#%s]%s[/color] (%d men) on %s." % [
		army.display_name(), roundi(army.total_men()), enemy.color.lightened(0.35).to_html(false),
		enemy.name, roundi(enemy_men), state.map.terrain(province).display_name.to_lower()])
	lines.append("")
	lines.append("[font_size=20]Forecast: [b][color=%s]%s[/color][/b][/font_size]" % [
		RATING_COLORS.get(forecast.rating, "#ffffff"), forecast.rating])
	lines.append("You won %d of %d simulated battles." % [forecast.wins, forecast.runs])
	lines.append("Expected men left: yours %d%%, theirs %d%%." % [
		roundi(forecast.attacker_survival * 100), roundi(forecast.defender_survival * 100)])
	_body.text = "\n".join(lines)
	visible = true
