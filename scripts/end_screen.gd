class_name EndScreen
extends PanelContainer
## Victory and defeat (PRD CP-7): the result, why, and the stars earned.

signal play_again
signal closed
signal menu

var _stars := 0

@onready var _body: RichTextLabel = $Margin/Rows/Body
@onready var _star_row: Control = $Margin/Rows/Stars
@onready var _again_button: Button = $Margin/Rows/Buttons/AgainButton
@onready var _close_button: Button = $Margin/Rows/Buttons/CloseButton
@onready var _menu_button: Button = $Margin/Rows/Buttons/MenuButton


func _ready() -> void:
	_again_button.pressed.connect(func(): play_again.emit())
	_close_button.pressed.connect(func(): closed.emit())
	_menu_button.pressed.connect(func(): menu.emit())
	_star_row.draw.connect(_draw_stars)


func show_result(state: GameState, viewer: String) -> void:
	var result := state.result
	var won: bool = result.result == "won" and result.winner == viewer
	var title := "Victory!" if won else "Defeat"
	var humans := state.turn_order.filter(func(f): return state.factions[f].human)
	if humans.size() != 1 and result.winner != "":
		title = "%s wins!" % state.faction_name(result.winner)  # Hotseat or an all-AI game.
	var text := ""
	if Mission.is_mission(state):
		text = state.mission.get("victory_text" if won else "defeat_text", "")
	var lines := PackedStringArray()
	lines.append("[font_size=30][b][color=%s]%s[/color][/b][/font_size]" % ["#8fe08f" if won else "#f08070", title])
	lines.append("")
	if text != "":
		lines.append(text)
		lines.append("")
	lines.append(result.reason)
	if won and Mission.is_mission(state):
		lines.append("Turn %d — par %d, limit %d." % [state.turn, Mission.par(state), Mission.hard_limit(state)])
	_body.text = "\n".join(lines)
	_stars = int(result.get("stars", 0)) if won else 0
	_star_row.visible = _stars > 0
	_star_row.queue_redraw()
	visible = true


func _draw_stars() -> void:
	for i in 3:
		var centre := Vector2(_star_row.size.x / 2.0 + (i - 1) * 56.0, _star_row.size.y / 2.0)
		var points := PackedVector2Array()
		for k in 10:
			var radius := 22.0 if k % 2 == 0 else 9.0
			points.append(centre + Vector2.from_angle(-PI / 2 + k * PI / 5) * radius)
		_star_row.draw_colored_polygon(points, Color("#f2c84b") if i < _stars else Color(0.3, 0.3, 0.3))
