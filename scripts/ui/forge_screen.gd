class_name ForgeScreen
extends Control
## The Forge (PRD G), opened with the anvil on a campaign mission's briefing
## and laid out as S&T's: wood and iron over the whole screen. On the left
## are the anvil that buys the selected card, the points to spend (an
## odometer) and the selected card's price. In the middle is the parchment of
## cards (ForgeCard), each row bought from left to right and joined by
## arrows; it scrolls when the rows don't fit. Under it are the tab switch
## (the windmill opens the economy, the target the army), what the selected
## card does, and the check that closes the Forge. Buying asks first: "Do
## you want to buy this upgrade?" with the price.

signal changed

const BASE := Vector2(1280, 720)  # The layout below is for this size.
const CARD := 119.0
const GAP := 47.0  # Between the cards of a row, where the arrow goes.
const ROW := 179.0  # From one row to the next.
const TOP := {"military": 26.0, "economy": 70.0}  # Above the first row.
const GOLD := Color("#e2bd5a")
const INK := Color("#3b2a17")
const ARROW := Color("#8d836c")
const DISC := Color("#2a1b0e")
const KNOB := Color("#d0602a")
const NUMBER := Color("#f1e6cc")
## Where things are, at BASE size.
const PANEL := Rect2(195, 22, 1027, 547)
const BUY := Rect2(34, 107, 116, 116)
const POINTS := Rect2(7, 279, 170, 46)
const PRICE := Rect2(34, 374, 116, 116)
const BOTTOM := 601.0  # The bar above the bottom row.
const TAB_BOX := Rect2(11, 612, 117, 97)
const TEXT_BAR := Rect2(152, 618, 976, 84)
const CHECK_BOX := Rect2(1152, 612, 117, 97)
const V_TRACK := Rect2(1246, 30, 2, 540)
const H_TRACK := Rect2(204, 584, 1036, 2)
# Kept here: a texture loaded inside a draw call would be freed before the
# frame is drawn, and show as a plain square.
const ANVIL := preload("res://assets/icons/ui_anvil.svg")
const SWORDS := preload("res://assets/icons/ui_swords.svg")

var _campaign := ""
var _tab := "military"
var _selected := ["infantry", 0]  # [row, index]
var _cards := {}  # "row/index" -> ForgeCard
var _clip: Control
var _grid: Control
var _content := Vector2.ZERO
var _scroll := 0.0
var _press := Vector2.ZERO
var _pressing := false
var _dragging := false
var _odometer: Odometer
var _price: Label
var _description: Label
var _buy: Button
var _tab_button: Button
var _confirm: WoodPopup
var _italic: Font


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	visible = false
	_italic = load("res://assets/fonts/IMFellEnglish-Italic.ttf")
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.position = PANEL.position
	_clip.size = PANEL.size
	_clip.gui_input.connect(_on_grid_input)
	add_child(_clip)
	_grid = Control.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.draw.connect(_draw_arrows)
	_clip.add_child(_grid)

	_buy = _round_button(BUY, _draw_buy)
	_buy.tooltip_text = "Buy the selected upgrade"
	_buy.pressed.connect(_on_buy)
	_odometer = Odometer.new(POINTS.size.y - 14.0)
	_odometer.digit_color = NUMBER
	_odometer.drum_color = Color("#1b130c")
	_odometer.rim_color = Color(0, 0, 0, 0.6)
	_odometer.position = POINTS.position + Vector2(10, 7)
	_odometer.size = POINTS.size - Vector2(20, 14)
	add_child(_odometer)
	_price = Label.new()
	_price.position = PRICE.position + Vector2(0, PRICE.size.y * 0.3)
	_price.size = Vector2(PRICE.size.x, PRICE.size.y * 0.4)
	_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_price.add_theme_font_override("font", load("res://assets/fonts/Cinzel.ttf"))
	_price.add_theme_font_size_override("font_size", 27)
	_price.add_theme_color_override("font_color", NUMBER)
	_price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_price)

	_tab_button = _round_button(TAB_BOX.grow(-StFrame.BAR), _draw_tab)
	_tab_button.pressed.connect(func(): _show_tab("economy" if _tab == "military" else "military"))
	_description = Label.new()
	_description.position = TEXT_BAR.position
	_description.size = TEXT_BAR.size
	_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_description.add_theme_font_override("font", _italic)
	_description.add_theme_font_size_override("font_size", 26)
	_description.add_theme_color_override("font_color", INK)
	add_child(_description)
	var close := CornerButton.new("check")
	close.tooltip_text = "Back to the briefing"
	close.position = CHECK_BOX.position + Vector2(StFrame.BAR, StFrame.BAR)
	close.size = CHECK_BOX.size - Vector2(StFrame.BAR, StFrame.BAR)
	close.pressed.connect(close_forge)
	add_child(close)
	_confirm = WoodPopup.new()
	add_child(_confirm)


func _round_button(rect: Rect2, painter: Callable) -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.position = rect.position
	button.size = rect.size
	button.draw.connect(painter.bind(button))
	for signal_name in ["mouse_entered", "mouse_exited", "button_down", "button_up"]:
		button.connect(signal_name, button.queue_redraw)
	Hud.react(button)
	add_child(button)
	return button


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _confirm.visible:
			_confirm.close()
		else:
			close_forge()


func show_campaign(campaign_id: String) -> void:
	_campaign = campaign_id
	visible = true
	_odometer.set_value(Progress.forge_points(campaign_id), false)
	_show_tab("military")


func close_forge() -> void:
	_confirm.visible = false
	visible = false


## Lays out a tab's rows of cards, and selects the first row's next card.
func _show_tab(tab: String) -> void:
	_tab = tab
	for card in _cards.values():
		card.queue_free()
	_cards.clear()
	var rows := Forge.rows(tab)
	var longest := 0
	for entry in rows:
		longest = maxi(longest, entry.cards.size())
	var width := longest * CARD + (longest - 1) * GAP
	_content = Vector2(width, TOP[tab] + rows.size() * ROW - (ROW - CARD) + 26.0)
	_grid.size = _content
	_grid.position.x = (PANEL.size.x - width) / 2.0
	for r in rows.size():
		for i in rows[r].cards.size():
			var card := ForgeCard.new(rows[r].cards[i][2], CARD)
			card.position = Vector2(i * (CARD + GAP), TOP[tab] + r * ROW)
			_grid.add_child(card)
			_cards["%s/%d" % [rows[r].id, i]] = card
	_scroll = 0.0
	_apply_scroll()
	_refresh()
	var first: String = rows[0].id
	_select(first, mini(Forge.bought(_owned(), first), rows[0].cards.size() - 1))
	_tab_button.queue_redraw()
	queue_redraw()


func _owned() -> Dictionary:
	return Progress.upgrades(_campaign)


## Each card's look from what is bought.
func _refresh() -> void:
	var owned := _owned()
	for key: String in _cards:
		var parts := key.split("/")
		var done := Forge.bought(owned, parts[0])
		var index := int(parts[1])
		_cards[key].look = ForgeCard.Look.BOUGHT if index < done else (ForgeCard.Look.NEXT if index == done else ForgeCard.Look.LOCKED)
	_grid.queue_redraw()


func _select(row_id: String, index: int) -> void:
	_selected = [row_id, index]
	for key in _cards:
		_cards[key].selected = key == "%s/%d" % [row_id, index]
	_price.text = str(Forge.price(_owned(), row_id, index))
	_description.text = Forge.describe(row_id, index)
	_description.add_theme_color_override("font_color", INK)


func _on_buy() -> void:
	var owned := _owned()
	var row_id: String = _selected[0]
	var index: int = _selected[1]
	var problem := Forge.problem(owned, row_id, index, Progress.forge_points(_campaign))
	if problem != "":
		_description.text = {"already bought": "This upgrade is already bought",
			"the card before it comes first": "Buy the upgrades before it first"}.get(problem,
			"Not enough points: this upgrade costs %d" % Forge.price(owned, row_id, index))
		_description.add_theme_color_override("font_color", Color("#8a2414"))
		return
	_confirm.open("")
	var top := Control.new()
	top.custom_minimum_size.y = 20
	_confirm.body.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	_confirm.body.add_child(row)
	var thumb := ForgeCard.new(_cards["%s/%d" % [row_id, index]].sketch, 84.0)
	thumb.look = ForgeCard.Look.NEXT
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(thumb)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 10)
	text.custom_minimum_size.x = 330
	row.add_child(text)
	for line in ["Do you want to buy this upgrade?", "Price: %d" % Forge.price(owned, row_id, index)]:
		var label := Label.new()
		label.text = line
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", _italic)
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_color", Color("#ecd9a8"))
		text.add_child(label)
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	_confirm.body.add_child(gap)
	_confirm.add_check(func():
		_confirm.close()
		if Progress.buy_upgrade(_campaign, row_id):
			AudioManager.sfx("clash")
			_odometer.set_value(Progress.forge_points(_campaign))
			_refresh()
			_select(row_id, index)
			changed.emit())
	_confirm.add_close()


# --- Scrolling and choosing ---------------------------------------------------------

func _on_grid_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			_scroll += 40.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -40.0
			_apply_scroll()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press = event.position
				_pressing = true
				_dragging = false
			else:
				if _pressing and not _dragging:
					_choose_at(event.position - _grid.position)
				_pressing = false
	elif event is InputEventMouseMotion and _pressing:
		if not _dragging and event.position.distance_to(_press) > 8.0:
			_dragging = true
		if _dragging:
			_scroll -= event.relative.y
			_apply_scroll()


func _apply_scroll() -> void:
	_scroll = clampf(_scroll, 0.0, maxf(_content.y - PANEL.size.y, 0.0))
	_grid.position.y = -_scroll
	queue_redraw()


func _choose_at(point: Vector2) -> void:
	for key: String in _cards:
		var card: ForgeCard = _cards[key]
		if Rect2(card.position, card.size).grow(ForgeCard.BRACKET_GAP).has_point(point):
			var parts := key.split("/")
			_select(parts[0], int(parts[1]))
			AudioManager.sfx("click")
			return


# --- Drawing ------------------------------------------------------------------------

func _draw() -> void:
	var screen := Rect2(Vector2.ZERO, BASE)
	StFrame.draw_wood(self, screen)
	var bar := StFrame.BAR
	# Iron round the screen, above the bottom row and between its boxes.
	for rect in [Rect2(0, 0, BASE.x, bar), Rect2(0, BASE.y - bar, BASE.x, bar), Rect2(0, 0, bar, BASE.y), Rect2(BASE.x - bar, 0, bar, BASE.y),
			Rect2(0, BOTTOM, BASE.x, bar), Rect2(TAB_BOX.end.x, BOTTOM, bar, BASE.y - BOTTOM), Rect2(CHECK_BOX.position.x - bar, BOTTOM, bar, BASE.y - BOTTOM)]:
		StFrame.draw_bar(self, rect)
	_paper(PANEL)
	_paper(TEXT_BAR)
	for rect in [BUY, PRICE]:
		_disc(rect)
	_plate(POINTS)
	_draw_price_marks()
	_draw_scrollbars()


## Parchment in a thin dark frame, darker towards its edges.
func _paper(rect: Rect2) -> void:
	draw_rect(rect.grow(5), Color("#2b2117"))
	draw_rect(rect.grow(3), Color("#8b7b5c"))
	draw_rect(rect, ForgeCard.PAPER)
	for k in 6:
		draw_rect(rect.grow(-k * 2.0), Color(0.45, 0.33, 0.15, 0.06 - k * 0.008), false, 2.0)


## A dark round disc with a soft edge, as under S&T's anvil and price.
func _disc(rect: Rect2) -> void:
	var c := rect.get_center()
	var r := rect.size.x / 2.0
	for k in 6:
		draw_circle(c, r + 6.0 - k, Color(0, 0, 0, 0.07))
	draw_circle(c, r, DISC)
	draw_circle(c - Vector2(0, r * 0.15), r * 0.82, Color(1, 0.85, 0.6, 0.03))


## The odometer's iron plate.
func _plate(rect: Rect2) -> void:
	var points := StFrame.cut_rect(rect, 10.0)
	var shadow := PackedVector2Array()
	for point in points:
		shadow.append(point + Vector2(0, 3))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	var uvs := PackedVector2Array()
	for point in points:
		uvs.append(point / StFrame.iron().get_size())
	draw_colored_polygon(points, Color.WHITE, uvs, StFrame.iron())
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, StFrame.EDGE, 1.5, true)
	for x in [rect.position.x + 6.0, rect.end.x - 6.0]:
		draw_circle(Vector2(x, rect.get_center().y), 2.0, Color("#2e2c28"))


## The little gold arrow over the price and the anvil under it.
func _draw_price_marks() -> void:
	var c := PRICE.get_center()
	var top := c + Vector2(0, -PRICE.size.y * 0.3)
	draw_colored_polygon(PackedVector2Array([top + Vector2(0, -8), top + Vector2(7, 6), top + Vector2(0, 2), top + Vector2(-7, 6)]), GOLD)
	var low := c + Vector2(0, PRICE.size.y * 0.3)
	draw_texture_rect(ANVIL, Rect2(low - Vector2(13, 12), Vector2(26, 26)), false, GOLD)
	draw_set_transform(low + Vector2(5, -10), -0.6)
	draw_texture_rect(ForgeCard.icon("claw_hammer"), Rect2(-7, -7, 14, 14), false, GOLD)
	draw_set_transform(Vector2.ZERO)


## Thin tracks with an orange knob, a fleur-de-lis at their start.
func _draw_scrollbars() -> void:
	var track := Color(0.08, 0.05, 0.02, 0.8)
	draw_rect(V_TRACK, track)
	draw_rect(H_TRACK, track)
	var shown := clampf(PANEL.size.y / maxf(_content.y, 1.0), 0.0, 1.0)
	var length := V_TRACK.size.y * shown
	var at := V_TRACK.position.y + (V_TRACK.size.y - length) * (_scroll / maxf(_content.y - PANEL.size.y, 1.0))
	draw_rect(Rect2(V_TRACK.position.x - 1.5, at, 5, length), KNOB)
	draw_rect(Rect2(H_TRACK.position.x + 18, H_TRACK.position.y - 1.5, 46, 5), KNOB)
	_fleur(Vector2(V_TRACK.get_center().x, V_TRACK.position.y - 4.0), 0.0)
	_fleur(Vector2(H_TRACK.position.x - 4.0, H_TRACK.get_center().y), -PI / 2.0)


## A small gold fleur-de-lis pointing up (turned by `angle`), its foot at `at`.
func _fleur(at: Vector2, angle: float) -> void:
	draw_set_transform(at, angle)
	var middle := PackedVector2Array([Vector2(0, -14), Vector2(3, -9), Vector2(2.5, -3), Vector2(0, 0), Vector2(-2.5, -3), Vector2(-3, -9)])
	draw_colored_polygon(middle, GOLD)
	for side in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([Vector2(side * 1.5, -3), Vector2(side * 6, -9), Vector2(side * 9, -8), Vector2(side * 7.5, -5),
			Vector2(side * 5, -6), Vector2(side * 2, -1)]), GOLD)
	draw_rect(Rect2(-5, -3, 10, 2), GOLD)
	draw_set_transform(Vector2.ZERO)


## The arrows from each card to the next in its row.
func _draw_arrows() -> void:
	var rows := Forge.rows(_tab)
	for r in rows.size():
		for i in rows[r].cards.size() - 1:
			var y: float = TOP[_tab] + r * ROW + CARD / 2.0
			var from := Vector2(i * (CARD + GAP) + CARD + 5.0, y)
			var to := Vector2((i + 1) * (CARD + GAP) - 6.0, y)
			_grid.draw_line(from, to, ARROW, 2.0, true)
			_grid.draw_colored_polygon(PackedVector2Array([to + Vector2(2, 0), to + Vector2(-9, -5.5), to + Vector2(-6.5, 0), to + Vector2(-9, 5.5)]), ARROW)


## The anvil that buys: gold anvil, a hammer over it and a plus beside.
func _draw_buy(button: Button) -> void:
	var c := button.size / 2.0
	var color := GOLD.lightened(0.25) if button.is_hovered() else GOLD
	var lift := Vector2(0, 2) if button.is_pressed() else Vector2.ZERO
	button.draw_texture_rect(ANVIL, Rect2(c + lift + Vector2(-30, -22), Vector2(62, 62)), false, color)
	button.draw_set_transform(c + lift + Vector2(10, -24), -0.5)
	button.draw_texture_rect(ForgeCard.icon("claw_hammer"), Rect2(-17, -17, 34, 34), false, color)
	button.draw_set_transform(Vector2.ZERO)
	var plus := c + lift + Vector2(-26, 26)
	button.draw_rect(Rect2(plus - Vector2(9, 2.5), Vector2(18, 5)), color)
	button.draw_rect(Rect2(plus - Vector2(2.5, 9), Vector2(5, 18)), color)


## The tab switch: the windmill (economy) on the army's tab, the target with
## crossed swords (army) on the economy's, each in a laurel wreath.
func _draw_tab(button: Button) -> void:
	var c := button.size / 2.0 + (Vector2(0, 2) if button.is_pressed() else Vector2.ZERO)
	var color := GOLD.lightened(0.25) if button.is_hovered() else GOLD
	if _tab == "military":
		button.draw_texture_rect(ForgeCard.icon("windmill"), Rect2(c - Vector2(25, 28), Vector2(50, 50)), false, color)
	else:
		button.draw_texture_rect(SWORDS, Rect2(c - Vector2(27, 29), Vector2(54, 54)), false, color)
		button.draw_circle(c - Vector2(0, 2), 18.0, Color("#3a2614"))
		button.draw_texture_rect(ForgeCard.icon("archery_target"), Rect2(c - Vector2(17, 19), Vector2(34, 34)), false, color)
	# Leaves up each side, from the bottom of a circle round the icon.
	for side in [-1.0, 1.0]:
		var leaf := func(angle: float) -> Vector2:
			return c + Vector2(side * absf(cos(deg_to_rad(angle))), sin(deg_to_rad(angle))) * 34.0
		for k in 6:
			var at: Vector2 = leaf.call(100.0 + k * 22.0)
			var along: Vector2 = (leaf.call(110.0 + k * 22.0) - at).normalized()
			var normal := along.orthogonal()
			button.draw_colored_polygon(PackedVector2Array([at - along * 6.0, at + normal * 2.8, at + along * 6.0, at - normal * 2.8]), color)
