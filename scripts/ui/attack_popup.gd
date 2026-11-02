class_name AttackPopup
extends WoodPopup
## "Who goes?" (PRD A, B, OR-3), laid out exactly as S&T's window that opens
## when an army is given an arrow: the title (Move, Attack or Support), one
## row per soldier type in two columns (the type's dark round badge, how many
## go, a slider), and, with more than one type, a total slider between the
## check and the X in the bottom corners. Nothing else: no route, forecast or
## notes. By default every soldier not yet given an order goes (those not sent
## stay home, where another arrow can still send them elsewhere). Re-opened on
## an existing order, it changes that order; clicking the arrow on the map
## cancels it. A region holds at most Unit.CAP soldiers, so the sliders stop
## at the room left there (archers who only shoot, and supporters, need none).

signal confirmed(amounts: Dictionary)

const WIDTH := 648.0  # S&T's window is half the screen wide.
const NUMBER := Color("#f6f1e6")

var _sliders := {}  # type id -> DotSlider
var _available := {}
var _total: DotSlider
var _total_label: Label
var _support := false
var _syncing := false
var _room := -1  # Places left in the target, or -1 for no limit.
var _type := "move"


func _init() -> void:
	super()
	title_height = 86.0


## Opens the window for an arrow from `unit` to `target`. `type` is "move" or
## "attack"; `available` the soldiers of each type it may take; `current` the
## order being changed ({} for a new one); `room` is Orders.room_for.
func show_order(state: GameState, unit: Unit, type: String, _target: String, available: Dictionary, current := {},
		support := false, room := -1) -> void:
	var editing := not current.is_empty()
	var attack := type == "attack"
	_support = support
	_room = room
	_type = type
	open("Support" if support else ("Attack" if attack else "Move"))
	custom_minimum_size = Vector2(WIDTH, 0)
	_available = available.duplicate()
	_sliders.clear()
	var grid := GridContainer.new()
	grid.columns = 2 if available.size() > 1 else 1
	grid.add_theme_constant_override("h_separation", 44)
	grid.add_theme_constant_override("v_separation", 22)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(grid)
	var chosen: Dictionary = current.get("troops", Orders.fit(available, room, type))
	for type_id in available:
		var most := int(available[type_id])
		if room >= 0 and not (attack and Rules.unit(type_id).is_ranged()):
			most = mini(most, room)
		var count := _number()
		var slider := DotSlider.new()
		slider.max_value = most
		slider.value = clampi(int(chosen.get(type_id, 0 if editing else available[type_id])), 0, most)
		slider.value_changed.connect(func(v):
			var fitted := _fit(int(v))
			if fitted != int(v):
				slider.set_value_no_signal(fitted)
			count.text = str(fitted)
			_on_type_changed())
		count.text = str(int(slider.value))
		grid.add_child(_row(TypeIcons.control(type_id, 40, state.is_upgraded(unit.owner, type_id), true), count, slider))
		_sliders[type_id] = slider
	# With several types, a total slider scales them all together.
	_total = null
	_total_label = null
	if available.size() > 1:
		var gap := Control.new()
		gap.custom_minimum_size.y = 14
		body.add_child(gap)
		_total_label = _number()
		_total = DotSlider.new()
		_total.max_value = Orders.total(Orders.fit(available, room, type))
		_total.min_value = 1
		_total.value_changed.connect(_on_total_changed)
		footer.add_child(_row(null, _total_label, _total))
	add_check(_confirm)
	add_close()
	_on_type_changed()
	reset_size()


## A badge (or nothing), the count and the slider, as one row.
func _row(badge: Control, count: Label, slider: DotSlider) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if badge != null:
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
	row.add_child(count)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	return row


func _number() -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(32, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", NUMBER)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


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
		troops = Orders.pick(_pool(), 1)
	visible = false
	confirmed.emit({"troops": troops, "support": _support})


## The total slider scales every type together.
func _on_total_changed(value: float) -> void:
	if _syncing:
		return
	_syncing = true
	var share := Orders.pick(_pool(), int(value))
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


func _refresh_total() -> void:
	if _total_label != null:
		_total_label.text = str(Orders.total(chosen()))


## A type slider's value, lowered so the soldiers chosen fit the room. An
## attack of archers only needs none.
func _fit(value: int) -> int:
	var troops := chosen()
	if _room < 0 or Orders.total(troops) <= _room or (_type == "attack" and Orders.all_ranged(troops)):
		return value
	return maxi(value - (Orders.total(troops) - _room), 0)


## The soldiers the total slider shares out: with no room, an attack's archers only.
func _pool() -> Dictionary:
	return Orders.fit(_available, _room, _type) if _room == 0 else _available
