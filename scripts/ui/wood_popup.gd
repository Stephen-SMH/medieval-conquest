class_name WoodPopup
extends PanelContainer
## A riveted wood window with a gold title, a body and a footer row with the
## check and close buttons. Popups build their own content in `body`.

signal closed

const GOLD := Color("#e2bd5a")
const INK := Color("#2f2012")

var body: VBoxContainer
var footer: HBoxContainer
var _title: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	_title = Label.new()
	_title.theme_type_variation = "HeadingLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	column.add_child(body)
	footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	resized.connect(func(): if visible: recenter())


func open(title: String) -> void:
	_title.text = title
	for child in body.get_children():
		child.queue_free()
	for child in footer.get_children():
		child.queue_free()
	visible = true
	reset_size()
	recenter.call_deferred()
	Hud.pop_in(self)


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


## The gold check (confirm) and X (close) buttons in the footer.
func add_check_and_close(on_confirm: Callable) -> void:
	var check := add_button("", on_confirm)
	check.icon = load("res://assets/icons/ui_check.svg")
	check.expand_icon = true
	check.custom_minimum_size = Vector2(70, 56)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	add_close()


func add_close() -> void:
	var cross := add_button("X", close)
	cross.add_theme_font_size_override("font_size", 26)
	cross.custom_minimum_size = Vector2(70, 56)


static func icon_rect(path: String, size: float, tint := Color("#e2bd5a")) -> TextureRect:
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(path)
	icon.custom_minimum_size = Vector2(size, size)
	icon.size = Vector2(size, size)
	icon.modulate = tint
	return icon
