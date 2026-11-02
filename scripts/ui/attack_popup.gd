class_name AttackPopup
extends WoodPopup
## "Who goes?" (PRD A, B, OR-3): the window that opens when an army is given
## an arrow, titled "Attack", "Move" or "Support". One row per soldier type,
## in two columns: the type's round icon (a star if upgraded), how many go,
## and a slider. At the bottom, between the check and the X, a TOTAL slider
## scales every type together. By default every soldier not yet given an
## order goes; those not sent stay home, where another arrow can still send
## them elsewhere. Re-opened on an existing order, it changes that order and
## can remove it. An attack shows the forecast for the soldiers chosen.

signal confirmed(amounts: Dictionary)
signal remove_requested

var _sliders := {}  # type id -> HSlider
var _available := {}
var _total: HSlider
var _total_label: Label
var _forecast: RichTextLabel
var _forecaster := Callable()
var _support := false
var _syncing := false
var _forecast_due := 0.0


## Opens the window for an arrow from `unit` to `target`. `type` is "move" or
## "attack"; `available` the soldiers of each type it may take; `current` the
## order being changed ({} for a new one). `forecaster`, for an attack, takes
## {type: soldiers} and returns a forecast.
func show_order(state: GameState, unit: Unit, type: String, target: String, available: Dictionary, current := {},
		support := false, forecaster := Callable()) -> void:
	var editing := not current.is_empty()
	var attack := type == "attack"
	_support = support
	_forecaster = forecaster
	open("Support" if support else ("Attack" if attack else "Move"))
	custom_minimum_size = Vector2(620, 0)
	_available = available.duplicate()
	_sliders.clear()
	var where := Label.new()
	where.text = ("%s → %s" % [state.map.region_name(unit.province), state.map.region_name(target)])
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	where.add_theme_font_size_override("font_size", 17)
	body.add_child(where)
	var grid := GridContainer.new()
	grid.columns = 2 if available.size() > 1 else 1
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	var chosen: Dictionary = current.get("troops", available)
	for type_id in available:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		grid.add_child(row)
		row.add_child(TypeIcons.control(type_id, 40, state.is_upgraded(unit.owner, type_id)))
		var number := Label.new()
		number.custom_minimum_size = Vector2(30, 0)
		number.add_theme_font_size_override("font_size", 22)
		row.add_child(number)
		var slider := _slider(int(available[type_id]), int(chosen.get(type_id, 0 if editing else available[type_id])),
			240 if grid.columns == 2 else 420)
		slider.value_changed.connect(func(v):
			number.text = str(int(v))
			_on_type_changed())
		number.text = str(int(slider.value))
		row.add_child(slider)
		_sliders[type_id] = slider
	_forecast = add_text("", 16)
	var note := "Soldiers not sent stay home or can be sent elsewhere."
	if support:
		note += " They join the attack already ordered there and fight it as one battle."
	elif attack:
		note += " Archers shoot from home and only wear the enemy down; the rest go in. Those who win hold the region."
	else:
		note += " Those who march hold %s, or join your army there." % state.map.region_name(target)
	add_text("[i]%s[/i]" % note, 15)
	if editing:
		add_button("Remove this order", func():
			visible = false
			remove_requested.emit(), body)
	# The footer: check, the TOTAL slider, X.
	var check := add_button("", _confirm)
	check.icon = load("res://assets/icons/ui_check.svg")
	check.expand_icon = true
	check.custom_minimum_size = Vector2(64, 52)
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(middle)
	_total_label = Label.new()
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total_label.add_theme_font_size_override("font_size", 17)
	middle.add_child(_total_label)
	_total = _slider(Orders.total(available), 0, 300)
	_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_total.min_value = 1
	_total.value_changed.connect(_on_total_changed)
	middle.add_child(_total)
	add_close()
	_on_type_changed()
	_update_forecast()
	reset_size()


func _process(delta: float) -> void:
	if _forecast_due > 0.0:
		_forecast_due -= delta
		if _forecast_due <= 0.0:
			_update_forecast()


## The soldiers chosen, per type.
func chosen() -> Dictionary:
	var troops := {}
	for type_id in _sliders:
		var count := int(_sliders[type_id].value)
		if count > 0:
			troops[type_id] = count
	return troops


func _confirm() -> void:
	var troops := chosen()
	if troops.is_empty():
		troops = Orders.pick(_available, 1)
	visible = false
	confirmed.emit({"troops": troops, "support": _support})


## The TOTAL slider scales every type together.
func _on_total_changed(value: float) -> void:
	if _syncing:
		return
	_syncing = true
	var share := Orders.pick(_available, int(value))
	for type_id in _sliders:
		_sliders[type_id].value = int(share.get(type_id, 0))
	_syncing = false
	_refresh_total()


func _on_type_changed() -> void:
	if not _syncing and _total != null:
		_syncing = true
		_total.value = maxi(Orders.total(chosen()), 1)
		_syncing = false
	_refresh_total()
	_forecast_due = 0.25


func _refresh_total() -> void:
	if _total_label == null:
		return
	var sent := Orders.total(chosen())
	_total_label.text = "TOTAL  %d of %d" % [sent, Orders.total(_available)]


func _update_forecast() -> void:
	if _forecast == null:
		return
	if not _forecaster.is_valid() or chosen().is_empty():
		_forecast.text = ""
		return
	var forecast: Dictionary = _forecaster.call(chosen())
	if forecast.is_empty():
		_forecast.text = ""
		return
	_forecast.text = "[i]Forecast: [b]%s[/b] — your strength left %d%%, theirs %d%%.[/i]" % [
		forecast.rating, roundi(forecast.attacker_survival * 100), roundi(forecast.defender_survival * 100)]


func _slider(maximum: int, value: int, width: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = maximum
	slider.step = 1
	slider.value = clampi(value, 0, maximum)
	slider.tick_count = mini(maximum + 1, 11)
	slider.ticks_on_borders = true
	slider.custom_minimum_size = Vector2(width, 30)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	return slider
