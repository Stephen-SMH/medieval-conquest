class_name AttackPopup
extends WoodPopup
## "How many go?" (PRD OR-3): the window that opens when a unit is given an
## arrow. For a march or a melee attack, one slider sets how many soldiers
## the detachment takes; ranged units attacking get two sliders, one for the
## soldiers who shoot (bow) and one for those who go into melee (crossed
## swords). By default every soldier not yet given an order goes. Soldiers
## not sent stay home, where another arrow can still send them elsewhere.
## Re-opened on an existing order, it changes that order's count and can
## remove it.

signal confirmed(amounts: Dictionary)
signal remove_requested

var _shoot: HSlider
var _melee: HSlider
var _total: Label


## Opens the window for an arrow from `unit` to `target`. `type` is "move" or
## "attack"; `available` the most soldiers it may take; `current` the
## order being changed ({} for a new one); `whole` locks the slider to everyone.
func show_order(state: GameState, unit: Unit, type: String, target: String, forecast: Dictionary, available: int,
		current := {}, whole := false, from := "") -> void:
	var editing := not current.is_empty()
	var attack := type == "attack"
	open(("Attack %s" if attack else "March to %s") % state.map.region_name(target))
	custom_minimum_size = Vector2(560, 0)
	var total := maxi(available, 1)
	var ranged := attack and unit.type().is_ranged()
	_shoot = null
	_melee = null
	if ranged:
		_shoot = _slider_row("res://assets/icons/archers.svg", total, int(current.get("shoot", total)))
		if Orders.melee_allowed(state, unit, target, from):
			_melee = _slider_row("res://assets/icons/ui_swords.svg", total, int(current.get("soldiers", 0)))
	else:
		_melee = _slider_row("res://assets/icons/ui_swords.svg" if attack else unit_icon(unit), total, int(current.get("size", total)))
		_melee.min_value = total if whole else 1
	_total = Label.new()
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total.add_theme_font_size_override("font_size", 20)
	body.add_child(_total)
	if _shoot != null and _melee != null:
		_shoot.value_changed.connect(func(v): _melee.max_value = total - v; _update(total))
		_melee.value_changed.connect(func(v): _shoot.max_value = total - v; _update(total))
		_shoot.max_value = total - _melee.value
		_melee.max_value = total - _shoot.value
	elif _shoot != null:
		_shoot.value_changed.connect(func(_v): _update(total))
	else:
		_melee.value_changed.connect(func(_v): _update(total))
	if attack and not forecast.is_empty():
		add_text("[i]Forecast for the whole unit: [b]%s[/b] — your strength left %d%%, theirs %d%%.[/i]" % [
			forecast.rating, roundi(forecast.attacker_survival * 100), roundi(forecast.defender_survival * 100)], 16)
	if whole:
		add_text("[i]Your other unit is there: only the whole unit can go, and only if that unit leaves or swaps places.[/i]", 15)
	elif attack:
		add_text("[i]Soldiers not sent stay home or can be sent elsewhere. Those who fail come back; those who win hold the region.[/i]", 15)
	else:
		add_text("[i]Soldiers not sent stay home or can be sent elsewhere. Those who march hold %s as a unit of their own.[/i]" % state.map.region_name(target), 15)
	_update(total)
	if editing:
		add_button("Remove this order", func():
			visible = false
			remove_requested.emit(), body)
	add_check_and_close(func():
		var amounts := {"soldiers": int(_melee.value) if _melee != null else 0}
		if _shoot != null:
			amounts["shoot"] = int(_shoot.value)
		visible = false
		confirmed.emit(amounts))
	reset_size()


## The old entry point: an attack sending up to every free soldier.
func show_attack(state: GameState, unit: Unit, target: String, forecast: Dictionary) -> void:
	show_order(state, unit, "attack", target, forecast, Orders.available(state, unit, target))


static func unit_icon(unit: Unit) -> String:
	var unit_type := unit.type()
	if unit_type.unit_class == "siege":
		return "res://assets/icons/catapult.svg"
	if unit_type.is_cavalry():
		return "res://assets/icons/light_cavalry.svg"
	if unit_type.is_ranged():
		return "res://assets/icons/archers.svg"
	return "res://assets/icons/spearmen.svg"


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
	slider.value = clampi(value, 0, maximum)
	slider.tick_count = mini(maximum + 1, 11)
	slider.ticks_on_borders = true
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(360, 30)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v): number.text = str(int(v)))
	number.text = str(int(slider.value))
	row.add_child(slider)
	return slider


func _update(total: int) -> void:
	var sent := int(_shoot.value if _shoot != null else 0) + int(_melee.value if _melee != null else 0)
	var free := total - sent
	_total.text = "%d of %d soldiers go%s" % [sent, total, ", %d left to send elsewhere or keep home" % free if free > 0 else ""]
