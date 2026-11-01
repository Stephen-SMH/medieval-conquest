class_name SavePopup
extends PanelContainer
## Save and load slots: an autosave at the start of each of your turns and three manual slots.

signal save_requested(slot: String)
signal load_requested(slot: String)
signal closed

@onready var _rows: VBoxContainer = $Margin/Rows


func open(can_save: bool) -> void:
	for child in _rows.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "Save or load"
	title.add_theme_font_size_override("font_size", 22)
	_rows.add_child(title)
	for slot in SaveGame.SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		var description := SaveGame.describe(slot)
		label.text = "%s: %s" % ["Autosave" if slot == "auto" else "Slot " + slot, description if description != "" else "empty"]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size = Vector2(340, 0)
		row.add_child(label)
		if slot != "auto":
			var save := Button.new()
			save.text = "Save"
			save.disabled = not can_save
			save.focus_mode = Control.FOCUS_NONE
			save.pressed.connect(func(): save_requested.emit(slot))
			row.add_child(save)
		var load := Button.new()
		load.text = "Load"
		load.disabled = description == ""
		load.focus_mode = Control.FOCUS_NONE
		load.pressed.connect(func(): load_requested.emit(slot))
		row.add_child(load)
		_rows.add_child(row)
	var close := Button.new()
	close.text = "Close [Esc]"
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func(): closed.emit())
	_rows.add_child(close)
	visible = true
