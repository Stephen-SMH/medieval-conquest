class_name WoodPopup
extends PanelContainer
## A wood window as in S&T: planks inside a riveted iron frame cut at the
## corners (StFrame), a gothic title, a body, and a footer row. The check
## and the X sit in framed boxes in the bottom corners. Popups build their
## own content in `body`, and anything else for the footer in `footer`.

signal closed

const GOLD := Color("#e2bd5a")
const INK := Color("#2f2012")
const TITLE := Color("#cdb88c")
const SIDE := 24.0  # Space between the frame and the title, body and footer.
const BOX := Vector2(98, 72)  # A corner box, inside the frame.

var body: VBoxContainer
var footer: HBoxContainer
## The title's height, or 0 to fit the text.
var title_height := 0.0:
	set(value):
		title_height = value
		if _title != null:
			_title.custom_minimum_size.y = value
var _title: Label
var _left: MarginContainer
var _right: MarginContainer
var _boxes := {}  # MarginContainer -> true while it holds a corner button


func _init() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	visible = false
	var frame := StyleBoxEmpty.new()
	frame.set_content_margin_all(StFrame.BAR)
	add_theme_stylebox_override("panel", frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", load("res://assets/fonts/GrenzeGotisch.ttf"))
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", TITLE)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	_title.add_theme_constant_override("shadow_offset_y", 2)
	column.add_child(_margins(_title, SIDE, 10.0, 0.0))
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	column.add_child(_margins(body, SIDE, 0.0, 0.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	column.add_child(row)
	_left = _margins(null, 0.0, 0.0, 0.0)
	row.add_child(_left)
	footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_margins(footer, 0.0, 0.0, 12.0))
	_right = _margins(null, 0.0, 0.0, 0.0)
	row.add_child(_right)
	_left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_right.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.get_child(1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.sort_children.connect(queue_redraw)
	resized.connect(func(): if visible: recenter())


static func _margins(child: Control, side: float, top: float, bottom: float) -> MarginContainer:
	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", int(side))
	margins.add_theme_constant_override("margin_right", int(side))
	margins.add_theme_constant_override("margin_top", int(top))
	margins.add_theme_constant_override("margin_bottom", int(bottom))
	if child != null:
		margins.add_child(child)
	return margins


func _draw() -> void:
	var panel := Rect2(Vector2.ZERO, size)
	StFrame.draw_panel(self, panel)
	for slot: MarginContainer in [_left, _right]:
		if _boxes.has(slot):
			var to_here := get_global_transform().affine_inverse() * slot.get_global_transform()
			StFrame.draw_corner_box(self, panel, Rect2(to_here.origin, slot.size), slot == _left)


## Opens the window empty, with `title` at the top (none if "").
func open(title: String) -> void:
	_title.text = title
	_title.get_parent().visible = title != ""
	for child in body.get_children() + footer.get_children() + _left.get_children() + _right.get_children():
		child.queue_free()
	_boxes.clear()
	for slot: MarginContainer in [_left, _right]:
		slot.custom_minimum_size = Vector2(SIDE - 10.0, 0)
		for side in ["margin_top", "margin_left", "margin_right"]:
			slot.add_theme_constant_override(side, 0)
	visible = true
	reset_size()
	recenter.call_deferred()
	_refit()
	Hud.pop_in(self)


## Shrinks the window to its content once the wrapped text has its real
## height (a RichTextLabel measures itself narrow first), so no empty strip
## is left at the bottom.
func _refit() -> void:
	for i in 2:
		await get_tree().process_frame
	if visible:
		reset_size()
		recenter()
		queue_redraw()


## Keeps the window in the middle of the screen once its content is built.
func recenter() -> void:
	var screen := get_viewport_rect().size
	position = ((screen - size) / 2.0).max(Vector2(8, 8))


func close() -> void:
	visible = false
	closed.emit()


func add_text(bbcode: String, size := 18, color := Color("#f1e3bd")) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.text = bbcode
	label.add_theme_font_size_override("normal_font_size", size)
	label.add_theme_color_override("default_color", color)
	body.add_child(label)
	return label


func add_button(text: String, on_pressed: Callable, parent: Control = null) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	Hud.react(button)
	(parent if parent != null else footer).add_child(button)
	return button


## The check (confirm) and the X (close) in the bottom corner boxes.
func add_check_and_close(on_confirm: Callable) -> void:
	add_check(on_confirm)
	add_close()


func add_check(on_confirm: Callable) -> Button:
	return _corner(_left, "check", on_confirm)


func add_close() -> Button:
	return _corner(_right, "cross", close)


func _corner(slot: MarginContainer, mark: String, on_pressed: Callable) -> Button:
	for child in slot.get_children():
		child.queue_free()
	slot.custom_minimum_size = BOX
	slot.add_theme_constant_override("margin_top", int(StFrame.BAR))
	if slot == _left:
		slot.add_theme_constant_override("margin_right", int(StFrame.BAR))
	else:
		slot.add_theme_constant_override("margin_left", int(StFrame.BAR))
	var button := CornerButton.new(mark)
	button.pressed.connect(on_pressed)
	slot.add_child(button)
	_boxes[slot] = true
	queue_redraw()
	return button


static func icon_rect(path: String, size: float, tint := Color("#e2bd5a")) -> TextureRect:
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(path)
	icon.custom_minimum_size = Vector2(size, size)
	icon.size = Vector2(size, size)
	icon.modulate = tint
	return icon
