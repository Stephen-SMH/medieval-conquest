class_name Hud
extends Control
## The minimal map HUD: a riveted plaque at the top with the gold and the turn,
## wooden shield buttons in the corners (recruit, treasury, menu, alerts, and
## the end-turn hourglass), a cloth banner on the right listing the turn's
## orders and battles, a parchment strip for the selection, and the faint
## "Turn: ..." banner across the map.

signal recruit_pressed
signal treasury_pressed
signal menu_pressed
signal alerts_pressed
signal end_turn_pressed

const GOLD := Color("#e2bd5a")

var _gold_label: Label
var _turn_label: Label
var _info: PanelContainer
var _info_text: RichTextLabel
var _info_buttons: HBoxContainer
var _turn_banner: Control
var _turn_text: Label
var _turn_flag: ColorRect
var _toast: Label
var _banner: OrdersBanner
var _end_turn: Button
var _alerts_dot: Control
var _shield_buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# The plaque: gold and turn.
	var plaque := PanelContainer.new()
	plaque.theme_type_variation = "Plaque"
	plaque.set_anchors_preset(Control.PRESET_CENTER_TOP)
	plaque.position = Vector2(-170, 6)
	plaque.custom_minimum_size = Vector2(340, 52)
	add_child(plaque)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	plaque.add_child(row)
	row.add_child(_icon("res://assets/icons/ui_coins.svg", 30))
	_gold_label = _label("0", 24)
	row.add_child(_gold_label)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(60, 0)
	row.add_child(gap)
	row.add_child(_icon("res://assets/icons/ui_hourglass.svg", 28))
	_turn_label = _label("1", 24)
	row.add_child(_turn_label)

	# Shield buttons in the corners.
	_add_shield("res://assets/icons/knight.svg", true, Vector2(8, 6), Control.PRESET_TOP_LEFT, "Recruit (R)", func(): recruit_pressed.emit())
	_add_shield("res://assets/icons/ui_coins.svg", true, Vector2(8, 120), Control.PRESET_TOP_LEFT, "Treasury and research", func(): treasury_pressed.emit())
	_add_shield("res://assets/icons/ui_pause.svg", false, Vector2(-100, 6), Control.PRESET_TOP_RIGHT, "Menu (Esc)", func(): menu_pressed.emit())
	var alerts := _add_shield("", false, Vector2(-100, -228), Control.PRESET_BOTTOM_RIGHT, "Messages", func(): alerts_pressed.emit())
	var bang := _label("!", 48)
	bang.add_theme_font_override("font", load("res://assets/fonts/Cinzel.ttf"))
	bang.set_anchors_preset(Control.PRESET_FULL_RECT)
	bang.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bang.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bang.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alerts.add_child(bang)
	_alerts_dot = ColorRect.new()
	(_alerts_dot as ColorRect).color = Color("#d03a28")
	_alerts_dot.size = Vector2(12, 12)
	_alerts_dot.position = Vector2(70, 12)
	_alerts_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alerts.add_child(_alerts_dot)
	_end_turn = _add_shield("res://assets/icons/ui_hourglass.svg", false, Vector2(-100, -114), Control.PRESET_BOTTOM_RIGHT, "End turn (Enter)", func(): end_turn_pressed.emit())

	# The orders banner on the right edge.
	_banner = OrdersBanner.new()
	_banner.anchor_left = 1.0
	_banner.anchor_right = 1.0
	_banner.offset_left = -44
	_banner.offset_right = -4
	_banner.offset_top = 128
	_banner.offset_bottom = 460
	add_child(_banner)

	# The parchment strip for the selection.
	_info = PanelContainer.new()
	_info.theme_type_variation = "Parchment"
	_info.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_info.position = Vector2(-330, -132)
	_info.custom_minimum_size = Vector2(660, 0)
	_info.visible = false
	add_child(_info)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_info.add_child(column)
	_info_text = RichTextLabel.new()
	_info_text.bbcode_enabled = true
	_info_text.fit_content = true
	_info_text.add_theme_color_override("default_color", Color("#2f2012"))
	column.add_child(_info_text)
	_info_buttons = HBoxContainer.new()
	_info_buttons.add_theme_constant_override("separation", 8)
	column.add_child(_info_buttons)

	# The turn banner: faint calligraphy across the middle of the map.
	_turn_banner = HBoxContainer.new()
	_turn_banner.set_anchors_preset(Control.PRESET_CENTER)
	_turn_banner.position = Vector2(-330, 120)
	_turn_banner.custom_minimum_size = Vector2(660, 70)
	_turn_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	_turn_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_banner.modulate.a = 0.0
	add_child(_turn_banner)
	_turn_text = _label("", 44)
	_turn_text.add_theme_font_override("font", load("res://assets/fonts/IMFellEnglish-Italic.ttf"))
	_turn_text.add_theme_color_override("font_color", Color(1, 0.97, 0.9, 0.85))
	_turn_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_turn_banner.add_child(_turn_text)
	_turn_flag = ColorRect.new()  # Kept for the faction colour: drawn as a pennant beside the text.
	_turn_flag.custom_minimum_size = Vector2(46, 40)
	_turn_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_turn_flag.material = null
	_turn_banner.add_child(_turn_flag)
	_turn_flag.draw.connect(func():
		_turn_flag.draw_rect(Rect2(Vector2.ZERO, _turn_flag.size), Color(0, 0, 0, 0), true)
	)

	_toast = _label("", 18)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-330, 66)
	_toast.custom_minimum_size = Vector2(660, 0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_toast.add_theme_constant_override("shadow_offset_x", 1)
	_toast.add_theme_constant_override("shadow_offset_y", 1)
	_toast.add_theme_constant_override("shadow_outline_size", 6)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)


func update(state: GameState, has_alerts: bool) -> void:
	var faction: FactionState = state.factions.get(state.viewer())
	_gold_label.text = str(roundi(faction.resources.gold)) if faction != null else "—"
	_turn_label.text = str(state.turn)
	_alerts_dot.visible = has_alerts
	var entries := []
	for unit: Unit in state.orders:
		if unit.owner == state.viewer():
			entries.append(state.orders[unit].steps.back().type)
	_banner.own = entries
	_banner.queue_redraw()


## The battles of the last turn, for the red half of the banner.
func set_battles(kinds: Array) -> void:
	_banner.enemy = kinds
	_banner.queue_redraw()


func show_info(bbcode: String, buttons: Array) -> void:
	_info_text.text = bbcode
	for child in _info_buttons.get_children():
		child.queue_free()
	for entry in buttons:
		var button := Button.new()
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = entry.size() > 2 and entry[2] != ""
		if button.disabled:
			button.tooltip_text = entry[2]
		button.pressed.connect(entry[1])
		Hud.react(button)
		_info_buttons.add_child(button)
	if not _info.visible:
		_info.visible = true
		Hud.pop_in(_info)


func hide_info() -> void:
	_info.visible = false


func is_over_ui(point: Vector2) -> bool:
	for control: Control in _shield_buttons + [_info] as Array[Control]:
		if control.visible and control.get_global_rect().has_point(point):
			return true
	return false


## "Turn: Kingdom of …" fades in and out across the map, with the faction's flag.
func show_turn(text: String, color: Color) -> void:
	_turn_text.text = text
	_turn_flag.color = Color(color, 0.8)
	var tween := create_tween()
	tween.tween_property(_turn_banner, "modulate:a", 0.85, 0.5)
	tween.tween_interval(1.4)
	tween.tween_property(_turn_banner, "modulate:a", 0.0, 0.8)


func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(_toast, "modulate:a", 0.0, 1.2)


func set_end_turn_enabled(enabled: bool) -> void:
	_end_turn.disabled = not enabled


## Fades a panel open, growing slightly from its centre.
static func pop_in(control: Control) -> void:
	control.modulate.a = 0.0
	control.scale = Vector2(0.96, 0.96)
	control.pivot_offset = control.size / 2.0
	var tween := control.create_tween().set_parallel()
	tween.tween_property(control, "modulate:a", 1.0, 0.22)
	tween.tween_property(control, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Buttons swell a little under the mouse.
static func react(button: Control) -> void:
	button.mouse_entered.connect(func():
		button.pivot_offset = button.size / 2.0
		button.create_tween().tween_property(button, "scale", Vector2(1.05, 1.05), 0.1))
	button.mouse_exited.connect(func(): button.create_tween().tween_property(button, "scale", Vector2.ONE, 0.12))


## Applies `react` to every button under `root`.
static func react_all(root: Node) -> void:
	for child in root.get_children():
		if child is BaseButton and not child.has_meta("reacts"):
			child.set_meta("reacts", true)
			react(child)
		react_all(child)


func _add_shield(icon_path: String, plus: bool, at: Vector2, anchors: Control.LayoutPreset, tip: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.theme_type_variation = "ShieldButton"
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = tip
	button.set_anchors_preset(anchors)
	button.position = at if anchors == Control.PRESET_TOP_LEFT else at
	button.size = Vector2(92, 106)
	button.custom_minimum_size = Vector2(92, 106)
	if anchors in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT]:
		button.offset_left = at.x
		button.offset_right = at.x + 92
	if anchors == Control.PRESET_BOTTOM_RIGHT:
		button.offset_top = at.y
		button.offset_bottom = at.y + 106
	if icon_path != "":
		var icon := _icon(icon_path, 48)
		icon.position = Vector2(22, 22)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
	if plus:
		var mark := _label("+", 26)
		mark.position = Vector2(58, 52)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(mark)
	button.pressed.connect(on_pressed)
	react(button)
	add_child(button)
	_shield_buttons.append(button)
	return button


func _icon(path: String, size: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(path)
	icon.custom_minimum_size = Vector2(size, size)
	icon.size = Vector2(size, size)
	icon.modulate = GOLD
	return icon


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", GOLD.lightened(0.15))
	label.add_theme_font_override("font", load("res://assets/fonts/Cinzel.ttf"))
	return label


## A tall cloth banner listing this turn's orders (green, yours) and last turn's battles (red).
class OrdersBanner:
	extends Control
	var own := []
	var enemy := []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var green_height := maxf(60.0, 22.0 + own.size() * 26.0)
		var red_height := maxf(0.0, 22.0 + enemy.size() * 26.0) if not enemy.is_empty() else 0.0
		_cloth(Rect2(0, 0, w, green_height), Color("#2f5a2a"))
		for i in own.size():
			_glyph(own[i], Vector2(w / 2.0, 22 + i * 26))
		if red_height > 0:
			_cloth(Rect2(0, green_height + 4, w, red_height), Color("#7a2018"))
			for i in enemy.size():
				_glyph(enemy[i], Vector2(w / 2.0, green_height + 26 + i * 26))

	func _cloth(rect: Rect2, color: Color) -> void:
		var points := PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.end,
			rect.end + Vector2(-rect.size.x / 2.0, -10), Vector2(rect.position.x, rect.end.y)])
		draw_colored_polygon(points, color)
		var line := points.duplicate()
		line.append(points[0])
		draw_polyline(line, Color("#e2bd5a", 0.8), 1.5, true)

	func _glyph(kind: String, at: Vector2) -> void:
		var gold := Color("#e2bd5a")
		match kind:
			"move":
				draw_line(at + Vector2(-8, 0), at + Vector2(7, 0), gold, 2.0)
				draw_colored_polygon(PackedVector2Array([at + Vector2(10, 0), at + Vector2(4, -5), at + Vector2(4, 5)]), gold)
			"attack", "battle", "assault", "head_on", "contest":
				draw_line(at + Vector2(-7, -7), at + Vector2(7, 7), gold, 2.0)
				draw_line(at + Vector2(7, -7), at + Vector2(-7, 7), gold, 2.0)
			"volley":
				draw_arc(at + Vector2(-3, 0), 8.0, -1.2, 1.2, 10, gold, 2.0)
				draw_line(at + Vector2(-7, 0), at + Vector2(8, 0), gold, 1.5)
			_:
				draw_rect(Rect2(at - Vector2(6, 6), Vector2(12, 12)), gold, false, 2.0)
