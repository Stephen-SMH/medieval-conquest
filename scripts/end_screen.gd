class_name EndScreen
extends PanelContainer
## Victory and defeat (PRD H, CP-7), laid out as S&T's scroll: wood all
## round, a parchment scroll with rolled sides and the red crown banner,
## "Victory" at the top. On the left: the objectives with ✓ or ✗ and their
## points, the development points they add up to (the score, which the
## Forge spends), the awards (the bronze, silver and gold crowns and the
## points each gives, the one won lit) and the turns taken. On the right:
## your losses and the enemy's by soldier type, the total score, and your
## rank with a bar to the next. Under the scroll, S&T's round buttons: the
## castle (back to the menu), replay and, after a won campaign mission, the
## arrow to the next mission's briefing. Skirmish and hotseat show the
## result, the losses and the buttons.

signal play_again
signal closed
signal menu
signal next_mission

const SCROLL := Rect2(122, 54, 1036, 528)  # The sheet, between its rolled sides.
const ROLL := 72.0
const BANNER := Rect2(150, 54, 92, 126)
const OBJECTIVES := Rect2(166, 186, 474, 218)
const AWARDS := Rect2(166, 420, 318, 112)
const TURNS := Rect2(500, 420, 140, 112)
const LOSSES := Rect2(660, 186, 456, 256)
const RANK := Rect2(660, 458, 456, 74)
const BUTTON_Y := 648.0

var _canvas: Control
var _boxes: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	for child in get_children():
		child.queue_free()
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)


func _draw() -> void:
	StScroll.draw_screen(self, size)
	StScroll.draw_sheet(self, SCROLL)
	for x in [SCROLL.position.x - ROLL + 8, SCROLL.end.x - 8]:
		StScroll.draw_roll(self, Rect2(x, SCROLL.position.y - 14, ROLL, SCROLL.size.y + 28), true)
	StScroll.draw_banner(self, BANNER)
	for rect in _boxes:
		StScroll.draw_box(self, rect)


func show_result(state: GameState, viewer: String) -> void:
	for child in _canvas.get_children():
		child.queue_free()
	var result := state.result
	var won: bool = result.result == "won" and result.winner == viewer
	var mission := Mission.is_mission(state)
	var title := "Victory" if won else "Defeat"
	var humans := state.turn_order.filter(func(f): return state.factions[f].human)
	if humans.size() != 1 and result.winner != "":
		title = "%s wins!" % state.faction_name(result.winner)  # Hotseat or an all-AI game.
	_label(title, Rect2(SCROLL.position.x, 92, SCROLL.size.x, 54), 44, StScroll.TITLE, HORIZONTAL_ALIGNMENT_CENTER)
	var story: String = state.mission.get("victory_text" if won else "defeat_text", "") if mission else ""
	_label(story if story != "" else result.reason, Rect2(SCROLL.position.x + 140, 146, SCROLL.size.x - 280, 30), 17,
		StScroll.INK.lightened(0.25), HORIZONTAL_ALIGNMENT_CENTER)

	_boxes = [OBJECTIVES, LOSSES]
	if mission and result.has("objectives"):
		_objectives(result, won)
		if Mission.crowns(state).size() == 3:
			_boxes += [AWARDS, TURNS]
			_awards(int(result.stars) if won else 0, int(result.get("turns", state.turn)))
	else:
		_label(result.reason, OBJECTIVES.grow(-18), 22, StScroll.INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	_losses(state, viewer)
	if mission and (state.mission.has("campaign") or state.mission.has("scenario")):
		_boxes.append(RANK)
		_rank()
	queue_redraw()

	var buttons := [["castle", "Back to the menu", func(): menu.emit()], ["replay", "Play again", func(): play_again.emit()]]
	if won and state.mission.has("campaign"):
		var campaign := Campaigns.get_campaign(state.mission.campaign)
		if int(state.mission.mission_index) + 1 < campaign.get("missions", []).size():
			buttons.append(["arrow", "Next mission", func(): next_mission.emit()])
	for i in buttons.size():
		var button := RoundButton.new(buttons[i][0], 108)
		button.disc = true
		button.tooltip_text = buttons[i][1]
		button.pressed.connect(buttons[i][2])
		button.position = Vector2(640.0 + (i - (buttons.size() - 1) / 2.0) * 272.0 - 54, BUTTON_Y - 54)
		_canvas.add_child(button)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scale = Vector2.ONE
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)


func _label(text: String, rect: Rect2, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	label.clip_text = not wrap
	label.add_theme_font_override("font", load("res://assets/fonts/IMFellEnglish-Italic.ttf"))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_canvas.add_child(label)
	return label


func _line(at: Vector2, width: float) -> void:
	var line := ColorRect.new()
	line.color = Color(0.35, 0.25, 0.12, 0.28)
	line.position = at
	line.size = Vector2(width, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(line)


## The objectives, each with a red ✓ or ✗ and the points it earned, then the
## development points they add up to.
func _objectives(result: Dictionary, won: bool) -> void:
	var box := OBJECTIVES
	_label("Objectives", Rect2(box.position + Vector2(16, 6), Vector2(300, 30)), 22, StScroll.INK)
	var rows: Array = result.objectives
	var step := minf(38.0, 128.0 / maxf(rows.size(), 1))
	for i in rows.size():
		var objective: Dictionary = rows[i]
		var y := box.position.y + 42 + i * step
		_label("✓" if objective.done else "✗", Rect2(box.position.x + 14, y, 24, step), 20, StScroll.RED)
		_label(Mission.plain(objective.text), Rect2(box.position.x + 40, y, box.size.x - 130, step), 19, StScroll.INK)
		_label(str(int(objective.points)) if objective.done else "0", Rect2(box.end.x - 96, y, 80, step), 19, StScroll.INK,
			HORIZONTAL_ALIGNMENT_RIGHT)
		_line(Vector2(box.position.x + 14, y + step - 2), box.size.x - 28)
	_label("Development points", Rect2(box.position.x + 16, box.end.y - 40, 300, 34), 21, StScroll.INK)
	_label(str(int(result.get("points", 0))) if won else "0", Rect2(box.end.x - 116, box.end.y - 40, 100, 34), 21, StScroll.INK,
		HORIZONTAL_ALIGNMENT_RIGHT)


## The bronze, silver and gold crowns with the points each gives (the one won
## lit), and the turns taken.
func _awards(crown: int, turns: int) -> void:
	_label("Awards", Rect2(AWARDS.position + Vector2(16, 6), Vector2(200, 30)), 22, StScroll.INK)
	for level in [1, 2, 3]:
		var x: float = AWARDS.position.x + 20 + (level - 1) * 100
		var icon := Control.new()
		icon.position = Vector2(x, AWARDS.position.y + 56)
		icon.size = Vector2(34, 34)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lit: bool = crown == level
		icon.draw.connect(func(): StScroll.draw_crown(icon, Vector2(17, 16), 30, Hud.CROWN_COLORS[level] if lit else Color(0.55, 0.47, 0.32, 0.55)))
		_canvas.add_child(icon)
		_label(str(Mission.CROWN_POINTS[level]), Rect2(x + 34, AWARDS.position.y + 52, 60, 40), 21,
			StScroll.INK if lit else StScroll.INK.lightened(0.45))
	_label("Turns", Rect2(TURNS.position + Vector2(0, 6), Vector2(TURNS.size.x, 30)), 22, StScroll.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_label(str(turns), Rect2(TURNS.position + Vector2(0, 46), Vector2(TURNS.size.x, 50)), 34, StScroll.INK, HORIZONTAL_ALIGNMENT_CENTER)


## Your losses and the enemy's: each type's icon and how many fell, two to a row.
func _losses(state: GameState, viewer: String) -> void:
	var enemy := {}
	for faction in state.losses:
		if faction != viewer:
			for type_id in state.losses[faction]:
				enemy[type_id] = int(enemy.get(type_id, 0)) + int(state.losses[faction][type_id])
	var half := LOSSES.size.x / 2.0
	for side in 2:
		var by_type: Dictionary = state.losses.get(viewer, {}) if side == 0 else enemy
		var left := LOSSES.position.x + side * half
		_label("Your losses" if side == 0 else "Enemy losses", Rect2(left, LOSSES.position.y + 6, half, 30), 22, StScroll.INK,
			HORIZONTAL_ALIGNMENT_CENTER)
		var shown := 0
		for type_id in by_type:
			if int(by_type[type_id]) <= 0 or not Rules.units.has(type_id):
				continue
			var at := Vector2(left + 20 + (shown % 2) * (half / 2.0 - 6), LOSSES.position.y + 48 + (shown / 2) * 38)
			var icon := TypeIcons.control(type_id, 30, side == 0 and state.is_upgraded(viewer, type_id), true)
			icon.position = at
			_canvas.add_child(icon)
			_label(str(int(by_type[type_id])), Rect2(at + Vector2(34, -2), Vector2(half / 2.0 - 64, 34)), 20, StScroll.INK,
				HORIZONTAL_ALIGNMENT_RIGHT)
			shown += 1
		if shown == 0:
			_label("none", Rect2(left, LOSSES.position.y + 48, half, 34), 19, StScroll.INK.lightened(0.45), HORIZONTAL_ALIGNMENT_CENTER)
	_line(Vector2(LOSSES.position.x + 16, LOSSES.end.y - 46), LOSSES.size.x - 32)
	_label("Total", Rect2(LOSSES.position.x + 16, LOSSES.end.y - 42, 200, 36), 22, StScroll.INK)
	_label(str(Progress.total_score()), Rect2(LOSSES.end.x - 136, LOSSES.end.y - 42, 120, 36), 22, StScroll.INK, HORIZONTAL_ALIGNMENT_RIGHT)


## "Your rank: Serf" and S&T's bar from this rank's number to the next one's.
func _rank() -> void:
	var score := Progress.total_score()
	var rank := Progress.rank(score)
	_label("Your rank: %s" % rank.name, Rect2(RANK.position + Vector2(0, 2), Vector2(RANK.size.x, 30)), 21, StScroll.INK,
		HORIZONTAL_ALIGNMENT_CENTER)
	_label(str(int(rank.index) + 1), Rect2(RANK.position.x + 12, RANK.position.y + 34, 30, 30), 19, StScroll.INK, HORIZONTAL_ALIGNMENT_CENTER)
	if rank.next != "":
		_label(str(int(rank.index) + 2), Rect2(RANK.end.x - 42, RANK.position.y + 34, 30, 30), 19, StScroll.INK, HORIZONTAL_ALIGNMENT_CENTER)
	var bar := Control.new()
	bar.position = Vector2(RANK.position.x + 54, RANK.position.y + 44)
	bar.size = Vector2(RANK.size.x - 108, 10)
	bar.tooltip_text = "%d points in all%s" % [score, ", next: %s" % rank.next if rank.next != "" else ""]
	bar.draw.connect(func():
		bar.draw_line(Vector2(0, 5), Vector2(bar.size.x, 5), Color(0.35, 0.25, 0.12, 0.5), 2.0)
		bar.draw_line(Vector2(0, 5), Vector2(bar.size.x * float(rank.progress), 5), Color("#b8452c"), 5.0))
	_canvas.add_child(bar)
