class_name AttackPopup
extends WoodPopup
## "Attack": choose how many soldiers to send (PRD 8.3). Ranged units get two
## sliders, one for the soldiers who shoot (bow) and one for those who go into
## melee (crossed swords); the rest stay in their region.

signal confirmed(amounts: Dictionary)

var _shoot: HSlider
var _melee: HSlider
var _total: Label


func show_attack(state: GameState, unit: Unit, target: String, forecast: Dictionary) -> void:
	open("Attack %s" % state.map.region_name(target))
	custom_minimum_size = Vector2(560, 0)
	var total := unit.soldiers()
	var ranged := unit.type().is_ranged()
	_shoot = null
	_melee = null
	if ranged:
		_shoot = _slider_row("res://assets/icons/archers.svg", total, total)
	if not ranged or Orders.melee_allowed(state, unit, target):
		_melee = _slider_row("res://assets/icons/ui_swords.svg", total, 0 if ranged else total)
	_total = Label.new()
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total.add_theme_font_size_override("font_size", 20)
	body.add_child(_total)
	if _shoot != null and _melee != null:
		_shoot.value_changed.connect(func(v): _melee.max_value = total - v; _update(total))
		_melee.value_changed.connect(func(v): _shoot.max_value = total - v; _update(total))
		_melee.max_value = 0
	elif _shoot != null:
		_shoot.value_changed.connect(func(_v): _update(total))
	else:
		_melee.value_changed.connect(func(_v): _update(total))
	if not forecast.is_empty():
		add_text("[i]Forecast for the whole unit: [b]%s[/b] — your strength left %d%%, theirs %d%%.[/i]" % [
			forecast.rating, roundi(forecast.attacker_survival * 100), roundi(forecast.defender_survival * 100)], 16)
	add_text("[i]Those not sent stay home. Soldiers who fail come back; soldiers who win hold the region.[/i]", 15)
	_update(total)
	add_check_and_close(func():
		var amounts := {"soldiers": int(_melee.value) if _melee != null else 0}
		if _shoot != null:
			amounts["shoot"] = int(_shoot.value)
		visible = false
		confirmed.emit(amounts))
	reset_size()


func _slider_row(icon: String, maximum: int, value: int) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	row.add_child(WoodPopup.icon_rect(icon, 44))
	var number := Label.new()
	number.custom_minimum_size = Vector2(36, 0)
	number.add_theme_font_size_override("font_size", 24)
	row.add_child(number)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = maximum
	slider.step = 1
	slider.value = value
	slider.tick_count = 11
	slider.ticks_on_borders = true
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(360, 30)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v): number.text = str(int(v)))
	number.text = str(value)
	row.add_child(slider)
	return slider


func _update(total: int) -> void:
	var sent := int(_shoot.value if _shoot != null else 0) + int(_melee.value if _melee != null else 0)
	_total.text = "%d of %d soldiers sent" % [sent, total]
