class_name Hud
extends Control
## The minimal map HUD: a riveted plaque at the top with the gold, the turn
## and, in a mission, the crown still to be won with its turns left and the
## primary objectives left under crossed swords (PRD H); wooden shield
## buttons in the corners (recruit, treasury, menu, alerts, and the end-turn
## hourglass), a cloth banner on the right listing the turn's orders and
## battles, a parchment strip for the selection, parchment notes at the top
## left for the mission's scripted events, and the faint "Turn: ..." banner
## across the map.

signal recruit_pressed
signal treasury_pressed
signal menu_pressed
signal alerts_pressed
signal end_turn_pressed
signal objectives_pressed

const GOLD := Color("#e2bd5a")
## Crown colours: none, bronze, silver, gold.
const CROWN_COLORS := [Color(0.45, 0.42, 0.38, 0.8), Color("#c0793a"), Color("#d4d8dc"), Color("#f0c64a")]
const NOTE_SECONDS := 8.0
const TURN_BANNER_HEIGHT := 0.8  # The turn banner's middle, as a share of the screen's height.
const TURN_FADE_IN := 0.3
const TURN_HOLD := 1.0
const TURN_FADE_OUT := 0.5

var _gold: Odometer
var _prompt: Label
var _turn_label: Label
var _mission_box: Button
var _crown_icon: TextureRect
var _crown_label: Label
var _swords_label: Label
var _notes: VBoxContainer
var _battle_dim: ColorRect
var _battle_text: Label
var _info: PanelContainer
var _info_text: RichTextLabel
var _info_buttons: HBoxContainer
var _turn_banner: Control
var _turn_text: Label
var _turn_flag: Control
var _turn_color := Color.WHITE
var _turn_civ := ""
var _turn_tween: Tween
var _toast: Label
var _banner: OrdersBanner
var _end_turn: Button
var _alerts_dot: Control
var _shield_buttons: Array[Button] = []
var _army: ArmyBanner
var _skip_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Darker, browner screen edges, behind everything else in the HUD.
	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vignette_material := ShaderMaterial.new()
	vignette_material.shader = load("res://shaders/vignette.gdshader")
	vignette.material = vignette_material
	add_child(vignette)

	# The plaque: gold and turn.
	var plaque := PanelContainer.new()
	plaque.theme_type_variation = "Plaque"
	plaque.custom_minimum_size = Vector2(340, 52)
	plaque.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(plaque)
	plaque.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	plaque.offset_top = 6
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	plaque.add_child(row)
	row.add_child(_icon("res://assets/icons/ui_coins.svg", 30))
	_gold = Odometer.new(28)
	_gold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_gold)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(60, 0)
	row.add_child(gap)
	row.add_child(_icon("res://assets/icons/ui_hourglass.svg", 28))
	_turn_label = _label("1", 24)
	row.add_child(_turn_label)
	# The mission's crown and crossed swords; a click lists the objectives.
	_mission_box = Button.new()
	_mission_box.flat = true
	_mission_box.focus_mode = Control.FOCUS_NONE
	_mission_box.tooltip_text = "Objectives"
	_mission_box.pressed.connect(func(): objectives_pressed.emit())
	row.add_child(_mission_box)
	var mission_row := HBoxContainer.new()
	mission_row.add_theme_constant_override("separation", 8)
	mission_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mission_box.add_child(mission_row)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(30, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mission_row.add_child(spacer)
	_crown_icon = _icon("res://assets/icons/map_crown.svg", 30)
	_crown_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mission_row.add_child(_crown_icon)
	_crown_label = _label("", 24)
	mission_row.add_child(_crown_label)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(14, 0)
	mission_row.add_child(gap2)
	var swords := _icon("res://assets/icons/ui_swords.svg", 26)
	swords.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mission_row.add_child(swords)
	_swords_label = _label("", 24)
	mission_row.add_child(_swords_label)
	mission_row.resized.connect(func(): _mission_box.custom_minimum_size = mission_row.get_combined_minimum_size())
	_mission_box.visible = false

	# Shield buttons in the corners.
	_add_shield("res://assets/icons/knight.svg", true, Vector2(8, 6), Control.PRESET_TOP_LEFT, "Recruit (R)", func(): recruit_pressed.emit())
	_add_shield("res://assets/icons/ui_coins.svg", true, Vector2(8, 120), Control.PRESET_TOP_LEFT, "Treasury", func(): treasury_pressed.emit())
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
	_end_turn.set_meta("sfx", "")  # The hourglass makes its own sound.

	# The orders banner on the right edge.
	_banner = OrdersBanner.new()
	_banner.anchor_left = 1.0
	_banner.anchor_right = 1.0
	_banner.offset_left = -44
	_banner.offset_right = -4
	_banner.offset_top = 128
	_banner.offset_bottom = 460
	add_child(_banner)

	# The green cloth banner listing the selected army's soldiers (PRD A).
	_army = ArmyBanner.new()
	_army.anchor_left = 1.0
	_army.anchor_right = 1.0
	_army.offset_left = -96
	_army.offset_right = -4
	_army.offset_top = 128
	_army.visible = false
	add_child(_army)

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

	# The turn banner, as in S&T: "Turn: Kingdom of …" in light gothic letters
	# low over the map, with the faction's flag after it, and no plate behind.
	# It fades after a moment on your turn and stays through an enemy's.
	_turn_banner = HBoxContainer.new()
	_turn_banner.add_theme_constant_override("separation", 14)
	_turn_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_banner.modulate.a = 0.0
	add_child(_turn_banner)
	_turn_text = _label("", 36)
	_turn_text.add_theme_font_override("font", load("res://assets/fonts/GrenzeGotisch.ttf"))
	_turn_text.add_theme_color_override("font_color", Color("#f2ead8"))
	_turn_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	_turn_text.add_theme_constant_override("shadow_offset_x", 2)
	_turn_text.add_theme_constant_override("shadow_offset_y", 2)
	_turn_text.add_theme_constant_override("shadow_outline_size", 4)
	_turn_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_turn_banner.add_child(_turn_text)
	_turn_flag = Control.new()  # The faction's heraldic shield, after the text.
	_turn_flag.custom_minimum_size = Vector2(40, 48)
	_turn_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_turn_banner.add_child(_turn_flag)
	_turn_flag.draw.connect(func(): Hud.draw_heraldic_shield(_turn_flag, Rect2(Vector2.ZERO, _turn_flag.size), _turn_color, _turn_civ))
	_skip_label = _label("Tap to skip enemy turn", 30)
	_skip_label.add_theme_font_override("font", load("res://assets/fonts/GrenzeGotisch.ttf"))
	_skip_label.add_theme_color_override("font_color", Color("#f2ead8"))
	_skip_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	_skip_label.add_theme_constant_override("shadow_offset_x", 2)
	_skip_label.add_theme_constant_override("shadow_offset_y", 2)
	_skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_label.visible = false
	add_child(_skip_label)

	# "Select a province": the top bar's prompt while reinforcements wait for a place.
	_prompt = _label("", 26)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_prompt.position = Vector2(-300, 100)
	_prompt.custom_minimum_size = Vector2(600, 0)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt)

	# Parchment notes for the mission's scripted events, at the top left under the shields.
	_notes = VBoxContainer.new()
	_notes.position = Vector2(10, 236)
	_notes.custom_minimum_size = Vector2(380, 0)
	_notes.add_theme_constant_override("separation", 6)
	_notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notes)

	# "Battle won" or "Battle lost" as in S&T: big white gothic letters in the
	# middle of the screen while the map dims (PRD L).
	_battle_dim = ColorRect.new()
	_battle_dim.color = Color(0, 0, 0, 0.4)
	_battle_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_battle_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_battle_dim.modulate.a = 0.0
	add_child(_battle_dim)
	_battle_text = _label("", 64)
	_battle_text.add_theme_font_override("font", load("res://assets/fonts/GrenzeGotisch.ttf"))
	_battle_text.add_theme_color_override("font_color", Color("#f6f1e6"))
	_battle_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_battle_text.add_theme_constant_override("shadow_offset_x", 3)
	_battle_text.add_theme_constant_override("shadow_offset_y", 3)
	_battle_text.add_theme_constant_override("shadow_outline_size", 6)
	_battle_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_battle_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_battle_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_battle_text.modulate.a = 0.0
	add_child(_battle_text)

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
	_gold.set_value(roundi(faction.resources.gold) if faction != null else 0)
	_turn_label.text = str(state.turn)
	_mission_box.visible = Mission.is_mission(state) and not Mission.primary(state).is_empty()
	if _mission_box.visible:
		var crown := Mission.crown_now(state)
		_crown_icon.modulate = CROWN_COLORS[crown.crown]
		_crown_label.text = str(crown.turns_left) if crown.crown > 0 else "–"
		_crown_label.add_theme_color_override("font_color", CROWN_COLORS[crown.crown].lightened(0.1))
		_crown_icon.tooltip_text = ("%s crown: finish within %d more turn%s" % [Mission.CROWN_NAMES[crown.crown].capitalize(), crown.turns_left,
			"" if crown.turns_left == 1 else "s"]) if crown.crown > 0 else "No crown left to win"
		_swords_label.text = str(Mission.primary_left(state))
	_alerts_dot.visible = has_alerts
	var entries := []
	for unit: Unit in state.orders:
		if unit.owner == state.viewer():
			for order in state.orders[unit]:
				entries.append(order.steps.back().type)
	_banner.own = entries
	_banner.queue_redraw()


## The battles of the last turn, for the red half of the banner.
func set_battles(kinds: Array) -> void:
	_banner.enemy = kinds
	_banner.queue_redraw()


## Lists the selected army's soldiers on the green banner, or hides it (null).
func show_army(state: GameState, unit: Unit) -> void:
	_army.visible = unit != null
	_banner.visible = unit == null
	if unit != null:
		_army.show_army(state, unit)


## An enemy's turn plays, as in S&T: its "Turn: …" stays at the bottom and
## "Tap to skip enemy turn" shows in the middle of the screen.
func show_enemy_turn(text: String, color: Color, civ: String) -> void:
	_set_turn(text, color, civ)
	_skip_label.reset_size()
	_skip_label.position = ((size - _skip_label.size) / 2.0).round()
	_skip_label.visible = true
	_turn_tween = create_tween()
	_turn_tween.tween_property(_turn_banner, "modulate:a", 1.0, TURN_FADE_IN)


func hide_enemy_turn() -> void:
	_skip_label.visible = false
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()
	_turn_tween = create_tween()
	_turn_tween.tween_property(_turn_banner, "modulate:a", 0.0, TURN_FADE_OUT)


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


## "Turn: Kingdom of …" with the faction's flag fades in and out low over the map.
func show_turn(text: String, color: Color, civ := "") -> void:
	_set_turn(text, color, civ)
	_turn_tween = create_tween()
	_turn_tween.tween_property(_turn_banner, "modulate:a", 1.0, TURN_FADE_IN)
	_turn_tween.tween_interval(TURN_HOLD)
	_turn_tween.tween_property(_turn_banner, "modulate:a", 0.0, TURN_FADE_OUT)


func _set_turn(text: String, color: Color, civ: String) -> void:
	_turn_text.text = text
	_turn_color = color
	_turn_civ = civ
	_turn_flag.queue_redraw()
	_turn_banner.reset_size()
	_turn_banner.position = turn_banner_position(size, _turn_banner.size)
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()


## Where the turn banner goes: centred, low over the map, as in S&T.
static func turn_banner_position(screen: Vector2, banner: Vector2) -> Vector2:
	return Vector2(roundf((screen.x - banner.x) / 2.0), roundf(screen.y * TURN_BANNER_HEIGHT - banner.y / 2.0))


## How long the turn banner shows on your turn, in seconds, from fading in to gone.
static func turn_banner_seconds() -> float:
	return TURN_FADE_IN + TURN_HOLD + TURN_FADE_OUT


## "Battle won" or "Battle lost" in the middle of the dimmed screen for a moment.
func battle_result(won: bool) -> void:
	_battle_text.text = "Battle won" if won else "Battle lost"
	var tween := create_tween()
	tween.set_parallel()
	tween.tween_property(_battle_dim, "modulate:a", 1.0, 0.2)
	tween.tween_property(_battle_text, "modulate:a", 1.0, 0.2)
	tween.chain().tween_interval(0.9)
	tween.chain().tween_property(_battle_dim, "modulate:a", 0.0, 0.3)
	tween.parallel().tween_property(_battle_text, "modulate:a", 0.0, 0.3)


## A parchment note at the top left (a scripted event, PRD H). It fades
## after a few seconds; a click puts it away at once.
func note(text: String) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = "Parchment"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.custom_minimum_size = Vector2(360, 0)
	label.add_theme_color_override("default_color", Color("#2f2012"))
	label.add_theme_font_size_override("normal_font_size", 17)
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(label)
	_notes.add_child(card)
	pop_in(card)
	var fade := func():
		if is_instance_valid(card):
			var tween := card.create_tween()
			tween.tween_property(card, "modulate:a", 0.0, 0.6)
			tween.tween_callback(card.queue_free)
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			fade.call())
	get_tree().create_timer(NOTE_SECONDS).timeout.connect(fade)


## A standing prompt under the top bar ("" hides it).
func prompt(text: String) -> void:
	_prompt.text = text


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
	# The icon is drawn fitted inside the shield, whatever size the button ends up.
	var texture: Texture2D = load(icon_path) if icon_path != "" else null
	button.draw.connect(func():
		if texture != null:
			button.draw_texture_rect(texture, Hud.shield_icon_rect(button.size, texture.get_size()), false, GOLD)
		if plus:
			var inner: Rect2 = Hud.shield_inner_rect(button.size)
			var plus_at := inner.end - Vector2(7, 9)
			for d in [Vector2(6, 0), Vector2(0, 6)]:
				button.draw_line(plus_at - d, plus_at + d, Color(0, 0, 0, 0.6), 4.5)
				button.draw_line(plus_at - d, plus_at + d, GOLD.lightened(0.15), 2.5))
	button.pressed.connect(on_pressed)
	react(button)
	add_child(button)
	_shield_buttons.append(button)
	return button


## The face of a shield button, inside its rim and above its point.
static func shield_inner_rect(button_size: Vector2) -> Rect2:
	return Rect2(button_size * Vector2(0.22, 0.18), button_size * Vector2(0.56, 0.48))


## Where a shield button's icon goes: as big as fits inside the face, keeping its shape.
static func shield_icon_rect(button_size: Vector2, texture_size: Vector2) -> Rect2:
	var inner := shield_inner_rect(button_size)
	var scale := minf(inner.size.x / maxf(texture_size.x, 1.0), inner.size.y / maxf(texture_size.y, 1.0))
	var shown := texture_size * scale
	return Rect2(inner.position + (inner.size - shown) / 2.0, shown)


## A heater shield in the faction's colour with a gold rim and its civilization's charge.
static func draw_heraldic_shield(canvas: CanvasItem, rect: Rect2, color: Color, civ: String) -> void:
	var w := rect.size.x
	var h := rect.size.y
	var p := rect.position
	var outline := PackedVector2Array()
	outline.append(p)
	outline.append(p + Vector2(w, 0))
	for i in range(1, 11):
		var t := i / 10.0
		outline.append(p + Vector2(w - w * 0.5 * (1.0 - cos(t * PI / 2.0)), h * 0.42 + h * 0.58 * sin(t * PI / 2.0)))
	for i in range(9, 0, -1):
		var t := i / 10.0
		outline.append(p + Vector2(w * 0.5 * (1.0 - cos(t * PI / 2.0)), h * 0.42 + h * 0.58 * sin(t * PI / 2.0)))
	var colors := PackedColorArray()
	for point in outline:
		var k := (point - p).x / w * 0.5 + (point - p).y / h * 0.5
		colors.append(color.lightened(0.18).lerp(color.darkened(0.3), k))
	canvas.draw_polygon(outline, colors)
	var ring := outline.duplicate()
	ring.append(outline[0])
	canvas.draw_polyline(ring, Color(0, 0, 0, 0.5), 5.0, true)
	canvas.draw_polyline(ring, GOLD, 2.5, true)
	# A gold chief line and the charge.
	canvas.draw_line(p + Vector2(4, h * 0.14), p + Vector2(w - 4, h * 0.14), Color(GOLD, 0.7), 1.5)
	TokenLayer.draw_emblem(canvas, civ, p + Vector2(w * 0.5, h * 0.48), w * 0.22, Color(1, 0.95, 0.8, 0.95))


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


## The green cloth banner on the right edge listing the selected army's
## soldiers, one small type icon per soldier (PRD A). Hovering or tapping an
## icon shows a parchment tooltip with the type's name.
class ArmyBanner:
	extends Control
	const ICON := 22.0
	const COLUMNS := 3
	var _grid: GridContainer
	var _tip: PanelContainer
	var _tip_label: Label

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid = GridContainer.new()
		_grid.columns = COLUMNS
		_grid.position = Vector2(10, 14)
		_grid.add_theme_constant_override("h_separation", 4)
		_grid.add_theme_constant_override("v_separation", 4)
		add_child(_grid)
		_tip = PanelContainer.new()
		_tip.theme_type_variation = "Parchment"
		_tip.visible = false
		_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tip_label = Label.new()
		_tip_label.theme_type_variation = "InkLabel"
		_tip_label.add_theme_font_size_override("font_size", 15)
		_tip.add_child(_tip_label)
		add_child(_tip)

	func show_army(state: GameState, unit: Unit) -> void:
		for child in _grid.get_children():
			child.queue_free()
		for troop in unit.troops:
			for k in troop.soldiers:
				var icon := TypeIcons.control(troop.type_id, ICON, state.is_upgraded(unit.owner, troop.type_id))
				icon.tooltip_text = ""
				icon.mouse_filter = Control.MOUSE_FILTER_STOP
				var name := "%s (%d)" % [troop.type().display_name, troop.soldiers]
				icon.mouse_entered.connect(func(): _show_tip(icon, name))
				icon.mouse_exited.connect(func(): _tip.visible = false)
				icon.gui_input.connect(func(event):
					if event is InputEventScreenTouch or (event is InputEventMouseButton and event.pressed):
						_show_tip(icon, name))
				_grid.add_child(icon)
		var rows := ceili(unit.soldiers() / float(COLUMNS))
		custom_minimum_size = Vector2(COLUMNS * (ICON + 4) + 16, rows * (ICON + 4) + 40)
		size = custom_minimum_size
		offset_left = -size.x - 4
		offset_bottom = offset_top + size.y
		queue_redraw()

	func _show_tip(icon: Control, text: String) -> void:
		_tip_label.text = text
		_tip.reset_size()
		_tip.position = Vector2(-_tip.size.x - 6, icon.position.y + _grid.position.y - 4)
		_tip.visible = true

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var cloth := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(w / 2.0, h - 16), Vector2(0, h)])
		draw_colored_polygon(cloth, Color("#2f5a2a"))
		for k in 5:
			draw_line(Vector2(w * (k + 0.5) / 5.0, 2), Vector2(w * (k + 0.5) / 5.0, h - 20), Color(0, 0, 0, 0.06), 3.0)
		var edge := cloth.duplicate()
		edge.append(cloth[0])
		draw_polyline(edge, Color("#e2bd5a", 0.85), 2.0, true)
		draw_rect(Rect2(-4, -6, w + 8, 8), Color("#5a3a1c"))
		draw_rect(Rect2(-4, -6, w + 8, 8), Color("#e2bd5a", 0.6), false, 1.0)
