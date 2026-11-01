extends Node2D
## The game scene: the painted map, the units and the order arrows, and the
## planning turn (PRD 8.3). Click one of your units, then a region: a blue
## arrow moves there, a red one attacks (choose how many soldiers to send).
## Cavalry can add a second step. Click the unit again, or its arrow, to cancel.
## The hourglass ends your planning; when every faction has planned, the turn
## resolves and plays out on the map.

enum MapMode { POLITICAL, TERRAIN }

const SessionScript := preload("res://scripts/session.gd")
const DRAG_THRESHOLD := 6.0

var state: GameState
var map: MapData
var mode := MapMode.POLITICAL
var selected_unit: Unit
var selected_region := ""
var hovered_id := ""
## What clicking each region would do with the selected unit: "move", "attack" or "blocked".
var reach := {}

var _views := {}  # region id -> ProvinceView
var _decor: MapDecor
var _orders: OrdersLayer
var _tokens: TokenLayer
var _effects: Effects
var _press_button := MOUSE_BUTTON_NONE
var _press_position := Vector2.ZERO
var _dragging := false
var _touch := TouchGestures.new()
var _last_human := ""
var _pass_screen: Control
var _pass_label: Label
var _messages := PackedStringArray()
var _last_battles := []  # [Battle, region] pairs from the last resolution.
var _busy := false  # True while a turn resolves on screen.
var _attack_popup: AttackPopup
var _recruit_window: RecruitWindow
var _popup: WoodPopup

@onready var _map_root: Node2D = $Map
@onready var _camera: MapCamera = $Camera
@onready var _hud: Hud = $UI/Hud
@onready var _dim: Control = $UI/Dim
@onready var _region_popup: ProvincePanel = $UI/ProvincePanel
@onready var _battle_report: BattleReport = $UI/BattleReport
@onready var _end_screen: EndScreen = $UI/EndScreen
@onready var _save_popup: SavePopup = $UI/SavePopup
@onready var _research_panel: ResearchPanel = $UI/ResearchPanel


func _ready() -> void:
	var session := get_node_or_null("/root/Session")
	var setup: Dictionary = session.take_setup() if session != null \
		else {"scenario": SessionScript.load_scenario(SessionScript.DEFAULT_SCENARIO), "seed": 1}
	if setup.has("save"):
		state = SaveGame.from_dict(setup.save)
	else:
		state = GameState.from_scenario(setup.scenario, setup.get("seed", 1))
	map = state.map
	_camera.map_rect = Rect2(Vector2.ZERO, map.size)

	for region in map.province_order:
		var province: Dictionary = map.provinces[region]
		var view := ProvinceView.new()
		view.setup(region, province.polygon, province.centroid, province.name)
		_map_root.add_child(view)
		_views[region] = view
	_decor = MapDecor.new()
	_decor.state = state
	_map_root.add_child(_decor)
	_orders = OrdersLayer.new()
	_orders.state = state
	_map_root.add_child(_orders)
	_tokens = TokenLayer.new()
	_tokens.state = state
	_map_root.add_child(_tokens)
	_orders.tokens = _tokens
	_effects = Effects.new()
	_effects.setup(state, _tokens, _views)
	_map_root.add_child(_effects)

	_attack_popup = AttackPopup.new()
	_recruit_window = RecruitWindow.new()
	_popup = WoodPopup.new()
	for popup in [_attack_popup, _recruit_window, _popup]:
		$UI.add_child(popup)
		popup.closed.connect(_close_popups)
	_attack_popup.confirmed.connect(_on_attack_amounts)
	_recruit_window.recruit_requested.connect(_on_recruit)
	_hud.recruit_pressed.connect(open_recruit)
	_hud.treasury_pressed.connect(open_treasury)
	_hud.menu_pressed.connect(open_menu)
	_hud.alerts_pressed.connect(open_alerts)
	_hud.end_turn_pressed.connect(end_turn)
	_region_popup.build_requested.connect(_on_build_requested)
	_region_popup.recruit_requested.connect(func(region, unit): _on_recruit(region, unit, false))
	$UI/ProvincePanel/Margin/Content/CloseButton.pressed.connect(_close_popups)
	_battle_report.closed.connect(_close_popups)
	_save_popup.save_requested.connect(_on_save_requested)
	_save_popup.load_requested.connect(_on_load_requested)
	_save_popup.closed.connect(_close_popups)
	_end_screen.play_again.connect(_play_again)
	_end_screen.closed.connect(_close_popups)
	_end_screen.menu.connect(_go_to_menu)
	_research_panel.research_requested.connect(_on_research_requested)
	_research_panel.closed.connect(_close_popups)
	_build_pass_screen()
	Hud.react_all($UI)
	Settings.apply(get_tree())

	clear_selection()
	_advance()


func _process(_delta: float) -> void:
	_update_hover()
	if not is_equal_approx(_tokens.view_zoom, _camera.zoom.x):
		_tokens.view_zoom = _camera.zoom.x
		_tokens.queue_redraw()
		_orders.queue_redraw()  # Arrows run between the units' feet, which move with the token size.


func _is_my_turn() -> bool:
	return state.factions[state.current_faction()].human and not state.is_over() and not _busy


# --- Input ---------------------------------------------------------------------------

## Touch: two fingers pinch to zoom and drag to pan; a trackpad pinch zooms too.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		var gesture := _touch.handle(event)
		if not gesture.is_empty():
			_camera.zoom_at(gesture.center, gesture.zoom)
			_camera.pan_by_screen(gesture.pan)
		if _touch.is_multi_touch():
			_press_button = MOUSE_BUTTON_NONE
	elif event is InputEventMagnifyGesture:
		_camera.zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		_camera.pan_by_screen(-event.delta * 8.0)
	elif _busy and event is InputEventMouseButton and event.pressed:
		_effects.skip()  # Click to skip the turn's animation.


func _unhandled_input(event: InputEvent) -> void:
	if _pass_screen.visible or _busy:
		return
	if _dim.visible:
		if event.is_action_pressed("deselect"):
			_close_popups()
		return
	if event.is_action_pressed("zoom_in"):
		_camera.zoom_at(_zoom_anchor(event), MapCamera.ZOOM_STEP)
	elif event.is_action_pressed("zoom_out"):
		_camera.zoom_at(_zoom_anchor(event), 1.0 / MapCamera.ZOOM_STEP)
	elif event.is_action_pressed("end_turn"):
		end_turn()
	elif event.is_action_pressed("undo"):
		if selected_unit != null and _is_my_turn():
			_cancel_order(selected_unit)
	elif event.is_action_pressed("map_mode_political"):
		set_mode(MapMode.POLITICAL)
	elif event.is_action_pressed("map_mode_terrain"):
		set_mode(MapMode.TERRAIN)
	elif event.is_action_pressed("deselect"):
		if selected_unit != null or selected_region != "":
			clear_selection()
		else:
			open_menu()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
		open_recruit()
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


# --- Selection and orders (OR-1..OR-7) ---------------------------------------------------

func select_unit(unit: Unit) -> void:
	selected_unit = unit
	selected_region = ""
	_show_unit_info(unit)
	_refresh_world()


func select_region(region: String) -> void:
	selected_unit = null
	selected_region = region
	if region == "":
		_hud.hide_info()
	else:
		_show_region_info(region)
	_refresh_world()


func clear_selection() -> void:
	select_region("")


## A click on the map: an arrow cancels its order; with a unit selected a lit
## region is an order; a unit of yours selects it (again: cancels its orders).
func _click(point: Vector2) -> void:
	var arrow := _orders.unit_at(point)
	if arrow != null and _is_my_turn() and arrow.owner == state.current_faction():
		_cancel_order(arrow)
		return
	var unit := _tokens.unit_at(point)
	var region := map.province_at(point)
	if unit != null:
		region = unit.province
	if selected_unit != null and reach.has(region) and region != selected_unit.province:
		order(region)
		return
	if unit != null and unit.owner == state.current_faction() and _is_my_turn():
		if unit == selected_unit and state.orders.has(unit):
			_cancel_order(unit)
		else:
			select_unit(unit)
		return
	select_region(region)


func order(region: String) -> void:
	if selected_unit == null or not _is_my_turn():
		return
	var unit := selected_unit
	match reach.get(region, ""):
		"move":
			var problem := Orders.give(state, unit, "move", region)
			if problem != "":
				_hud.toast(problem.capitalize())
		"attack":
			_attack_popup.show_attack(state, unit, region, state.forecast_attack([unit], region))
			_attack_popup.set_meta("target", region)
			_attack_popup.set_meta("unit", unit)
			_dim.visible = true
			return
		"blocked":
			var index := maxi(Orders.next_step_index(state, unit), 0)
			_hud.toast("Can't go to %s: %s." % [map.region_name(region), Orders.problem(state, unit, "move", region, index)])
			return
	_after_order(unit)


func _on_attack_amounts(amounts: Dictionary) -> void:
	var unit: Unit = _attack_popup.get_meta("unit")
	var region: String = _attack_popup.get_meta("target")
	_close_popups()
	var problem := Orders.give(state, unit, "attack", region, amounts)
	if problem != "":
		_hud.toast(problem.capitalize())
	_after_order(unit)


## Cavalry with a step left stays selected for its second step.
func _after_order(unit: Unit) -> void:
	if Orders.next_step_index(state, unit) > 0:
		select_unit(unit)
	else:
		clear_selection()


func _cancel_order(unit: Unit) -> void:
	Orders.cancel(state, unit)
	_hud.toast("Order cancelled.")
	select_unit(unit)


func _show_unit_info(unit: Unit) -> void:
	var unit_type := unit.type()
	var lines := PackedStringArray()
	lines.append("[b]%s[/b] — %d of %d soldiers, %s%s" % [unit_type.display_name, unit.soldiers(), UnitType.SOLDIERS, unit.rank_name(),
		", general %s (Command %d)" % [unit.general.name, unit.general.command] if unit.general != null else ""])
	lines.append("[i]%s Attack %d, defense %d, %s%s.[/i]" % [unit_type.description, unit_type.attack, unit_type.defense,
		"range %d" % unit_type.attack_range if unit_type.is_ranged() else "melee", ", two steps a turn" if unit_type.is_cavalry() else ""])
	var buttons := []
	if unit.owner == state.current_faction() and _is_my_turn():
		var order_of := Orders.order_of(state, unit)
		if order_of.is_empty():
			lines.append("Click a [color=#2a4fa0]region to move[/color] or an [color=#9b2d20]enemy to attack[/color].")
		else:
			var steps := PackedStringArray()
			for step in order_of.steps:
				steps.append("%s %s" % [step.type, map.region_name(step.target)])
			lines.append("Orders: %s.%s" % [", then ".join(steps), " Click a region for its second step." if Orders.next_step_index(state, unit) > 0 else ""])
			buttons.append(["Cancel order (U)", func(): _cancel_order(unit)])
		for target in map.neighbours(unit.province):
			if Orders.problem(state, unit, "besiege", target) == "":
				buttons.append(["Besiege %s" % map.region_name(target), func(): Orders.give(state, unit, "besiege", target); clear_selection()])
		if unit.general == null:
			buttons.append(["Hire general (%dg)" % Economy.GENERAL_COST.gold, func():
				if state.hire_general(unit):
					_hud.toast("General %s takes command." % unit.general.name)
				select_unit(unit), "" if state.factions[unit.owner].can_afford(Economy.GENERAL_COST) else "not enough gold"])
		if state.owners[unit.province] == unit.owner:
			buttons.append(["Recruit here", func(): open_recruit(unit.province)])
			buttons.append(["Build here", func(): _open_region(unit.province)])
	_hud.show_info("\n".join(lines), buttons)


func _show_region_info(region: String) -> void:
	var owner: String = state.owners[region]
	var lines := PackedStringArray()
	var extras := PackedStringArray()
	if state.is_capital(region):
		extras.append("capital")
	if Sieges.walls(state, region) > 0:
		extras.append(Sieges.WALL_NAMES[Sieges.walls(state, region)].to_lower())
	if Economy.site(state, region) != "":
		extras.append(Economy.site(state, region) + ": mercenaries")
	lines.append("[b]%s[/b] — %s%s. %s, %d gold a turn." % [map.region_name(region), state.faction_name(owner),
		" (%s)" % ", ".join(extras) if not extras.is_empty() else "", map.terrain(region).display_name, roundi(Economy.region_income(state, region))])
	var occupant := state.unit_in(region)
	if occupant != null and (occupant.owner == state.viewer() or state.visible_provinces(state.viewer()).has(region)):
		lines.append("Held by %s %s (%d soldiers)." % [state.faction_name(occupant.owner), occupant.type().display_name.to_lower(), occupant.soldiers()])
	var buttons := []
	if owner == state.current_faction() and _is_my_turn():
		buttons.append(["Recruit here", func(): open_recruit(region)])
		buttons.append(["Build", func(): _open_region(region)])
	_hud.show_info("\n".join(lines), buttons)


# --- Turns -------------------------------------------------------------------------------

## The hourglass: this faction is done planning.
func end_turn() -> void:
	if not _is_my_turn():
		return
	_last_human = state.current_faction()
	clear_selection()
	var before := _snapshot()
	var events := state.end_faction_turn()
	if not events.is_empty():
		await _show_resolution(events, before)
	_advance()


## Lets the computer factions plan, resolves the turn when everyone has, and
## stops when a human has to plan.
func _advance() -> void:
	while not state.is_over():
		var faction := state.current_faction()
		if state.factions[faction].human:
			_start_human_planning()
			return
		AI.play_turn(state)
		var before := _snapshot()
		var events := state.end_faction_turn()
		if not events.is_empty():
			await _show_resolution(events, before)
	_refresh_world()
	_check_end()


func _start_human_planning() -> void:
	var faction := state.current_faction()
	_refresh_world()
	var humans := state.turn_order.filter(func(f): return state.factions[f].human)
	if humans.size() > 1 and faction != _last_human and _last_human != "":
		_pass_label.text = "Pass the device to\n%s" % state.faction_name(faction)
		_pass_label.add_theme_color_override("font_color", state.faction_color(faction).lightened(0.4))
		_pass_screen.visible = true
	if faction == humans[0]:
		SaveGame.save(state, "auto")
	_hud.show_turn("Turn: %s" % state.faction_name(faction), state.faction_color(faction), state.factions[faction].civ if state.factions.has(faction) else "")


## Where every unit stood, and with how much HP, before the turn resolved.
func _snapshot() -> Dictionary:
	var before := {}
	for unit in state.units:
		before[unit] = {"province": unit.province, "hp": unit.hp, "rank": unit.rank()}
	return before


## Plays the turn's resolution on the map, then catches the screen up.
func _show_resolution(events: Array, before: Dictionary) -> void:
	_busy = true
	_hud.set_end_turn_enabled(false)
	_last_battles.clear()
	var kinds := []
	for event in events:
		if event.type in ["battle", "volley"]:
			_last_battles.append([event.battle, event.province])
			kinds.append(event.get("kind", "volley"))
	_hud.set_battles(kinds)
	await _effects.play(events, before, _animation_speed())
	_busy = false
	_hud.set_end_turn_enabled(true)
	_report_events(events)
	_refresh_world()
	_check_end()


func _animation_speed() -> float:
	Settings.ensure_loaded()
	return Settings.animation_speed()


## Collects the turn's news for the alerts shield and shows the main line.
func _report_events(events: Array) -> void:
	var viewer := state.viewer()
	var notes := PackedStringArray()
	for event in events:
		match event.type:
			"economy":
				if event.faction == viewer:
					notes.append(event.text)
			"captured":
				if event.faction == viewer or event.previous_owner == viewer:
					notes.append("%s took %s." % [state.faction_name(event.faction), map.region_name(event.province)])
			"battle":
				var battle: Battle = event.battle
				notes.append("Battle of %s: the %s won." % [map.region_name(event.province), "attackers" if battle.attacker_won() else "defenders"])
			"general_lost":
				notes.append("General %s was %s." % [event.general.name, event.fate])
			"siege_breached":
				notes.append("The walls of %s are breached." % map.region_name(event.province))
	_messages = notes
	if not notes.is_empty():
		_hud.toast(notes[0] + ("  (+%d more: see the ! shield)" % (notes.size() - 1) if notes.size() > 1 else ""))


func _check_end() -> bool:
	if not state.is_over():
		return false
	_refresh_world()
	if state.result.result == "won" and state.mission.has("campaign") and state.result.winner == state.viewer():
		Progress.record(state.mission.campaign, int(state.mission.mission_index), int(state.result.stars))
	_end_screen.show_result(state, state.viewer())
	_dim.visible = true
	return true


# --- Popups --------------------------------------------------------------------------------

func open_recruit(region := "") -> void:
	if not _is_my_turn():
		return
	var faction := state.current_faction()
	if region == "":
		region = selected_region if selected_region != "" else (selected_unit.province if selected_unit != null else state.capitals.get(faction, ""))
	if region == "" or state.owners.get(region) != faction:
		_hud.toast("Select one of your regions to recruit there.")
		return
	_recruit_window.show_region(state, region)
	_dim.visible = true


func _on_recruit(region: String, unit: String, mercenary: bool) -> void:
	var done := Economy.hire(state, region, unit) if mercenary else Economy.recruit(state, region, unit)
	if done:
		_hud.toast("%s will be ready in %s at the end of the turn." % [Rules.unit(unit).display_name, map.region_name(region)])
	_close_popups()
	_refresh_world()


func open_treasury() -> void:
	var faction := state.viewer()
	_popup.open("Treasury")
	var lines := PackedStringArray()
	var total := 0.0
	for line in Economy.breakdown(state, faction).gold:
		lines.append("%s: %+d" % [line[0], roundi(line[1])])
		total += line[1]
	_popup.add_text("[b]Gold: %d[/b]  (%+d a turn)\n%s" % [roundi(state.factions[faction].resources.gold), roundi(total), "\n".join(lines)])
	_popup.add_text("[i]Every region pays 10 gold a turn, towns and capitals more, markets more again. Gold pays for units, mercenaries, healing, buildings and research; if it runs out, soldiers desert.[/i]", 16)
	_popup.add_button("Research", func(): _close_popups(); open_research(), _popup.body)
	_popup.add_close()
	_dim.visible = true


func open_research() -> void:
	if not state.factions.has(state.viewer()):
		return
	_research_panel.open(state, state.viewer())
	_dim.visible = true


func open_menu() -> void:
	_popup.open("Menu")
	_popup.add_button("Resume", _close_popups, _popup.body)
	_popup.add_button("Save or load", func(): _close_popups(); _open_saves(), _popup.body)
	_popup.add_button("Research", func(): _close_popups(); open_research(), _popup.body)
	_popup.add_button("Last battle report", func(): _close_popups(); _show_last_report(), _popup.body).disabled = _last_battles.is_empty()
	_popup.add_button("Map: %s" % ("terrain" if mode == MapMode.POLITICAL else "political"), func():
		set_mode(MapMode.TERRAIN if mode == MapMode.POLITICAL else MapMode.POLITICAL)
		_close_popups(), _popup.body)
	_popup.add_button("Main menu", _go_to_menu, _popup.body)
	_dim.visible = true


func open_alerts() -> void:
	_popup.open("Messages")
	_popup.add_text("\n".join(_messages) if not _messages.is_empty() else "[i]Nothing new.[/i]")
	_popup.add_close()
	_dim.visible = true


func _open_region(region: String) -> void:
	_region_popup.show_province(state, region)
	_region_popup.visible = true
	Hud.pop_in(_region_popup)
	_dim.visible = true


func _show_last_report() -> void:
	if _last_battles.is_empty():
		return
	var last: Array = _last_battles.back()
	_battle_report.show_battle(state, last[0], last[1], state.viewer())
	_dim.visible = true


func _close_popups() -> void:
	for popup: Control in [_attack_popup, _recruit_window, _popup, _region_popup, _battle_report, _end_screen, _save_popup, _research_panel]:
		popup.visible = false
	_dim.visible = false
	_refresh_world()


func _open_saves() -> void:
	_save_popup.open(_is_my_turn())
	_dim.visible = true


func _on_save_requested(slot: String) -> void:
	var error := SaveGame.save(state, slot)
	_hud.toast("Saved to slot %s." % slot if error == OK else "Couldn't save: %s." % error_string(error))
	_save_popup.open(_is_my_turn())


func _on_load_requested(slot: String) -> void:
	var data := SaveGame.load_slot(slot)
	var session := get_node_or_null("/root/Session")
	if data.is_empty() or session == null:
		return
	session.setup = {"save": data}
	get_tree().reload_current_scene()


func _play_again() -> void:
	var session := get_node_or_null("/root/Session")
	if session != null:
		session.setup = session.last_setup.duplicate(true)
	get_tree().reload_current_scene()


func _go_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _on_build_requested(region: String, building: String) -> void:
	if Economy.start_building(state, region, building):
		_hud.toast("Construction started in %s: %s." % [map.region_name(region), Rules.building(building).display_name])
	_region_popup.show_province(state, region)
	_refresh_world()


func _on_research_requested(tech: String) -> void:
	if _is_my_turn() and Research.start(state, state.viewer(), tech):
		_hud.toast("Research started: %s." % Rules.tech_name(tech))
	_research_panel.open(state, state.viewer())
	_refresh_world()


func _build_pass_screen() -> void:
	_pass_screen = TextureRect.new()
	(_pass_screen as TextureRect).texture = load("res://assets/ui/wood.png")
	(_pass_screen as TextureRect).stretch_mode = TextureRect.STRETCH_TILE
	_pass_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pass_screen.visible = false
	$UI.add_child(_pass_screen)
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pass_screen.add_child(card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 24)
	card.add_child(rows)
	_pass_label = Label.new()
	_pass_label.theme_type_variation = "HeadingLabel"
	_pass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pass_label.add_theme_font_size_override("font_size", 34)
	rows.add_child(_pass_label)
	var ready := Button.new()
	ready.text = "I'm ready — show my map"
	ready.custom_minimum_size = Vector2(340, 56)
	ready.pressed.connect(func():
		_pass_screen.visible = false
		clear_selection())
	rows.add_child(ready)


# --- Drawing -----------------------------------------------------------------------------------

func set_mode(new_mode: MapMode) -> void:
	mode = new_mode
	_refresh_world()


func _refresh_world() -> void:
	_hud.update(state, not _messages.is_empty())
	reach = Orders.reachable(state, selected_unit) if _is_my_turn() and selected_unit != null and state.units.has(selected_unit) else {}
	for region in _views:
		var view: ProvinceView = _views[region]
		view.set_base_color(ProvinceView.paint(state.faction_color(state.owners[region])) if mode == MapMode.POLITICAL else map.terrain(region).color)
		view.selected = region == selected_region or (selected_unit != null and selected_unit.province == region)
		view.reach = reach.get(region, "")
	_decor.queue_redraw()
	_tokens.selected.clear()
	if selected_unit != null:
		_tokens.selected.append(selected_unit)
	_tokens.visible_provinces = state.visible_provinces(state.viewer())
	if not _busy:
		_tokens.sync()
	_orders.preview = {}
	_orders.queue_redraw()


# --- Mouse ---------------------------------------------------------------------------------------

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if not (event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]):
		return
	if event.pressed:
		if _press_button == MOUSE_BUTTON_NONE:
			_press_button = event.button_index
			_press_position = event.position
			_dragging = event.button_index == MOUSE_BUTTON_MIDDLE
	elif event.button_index == _press_button:
		if not _dragging:
			var point := get_global_mouse_position()
			if event.button_index == MOUSE_BUTTON_LEFT:
				_click(point)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				var region := map.province_at(point)
				if reach.has(region):
					order(region)
				else:
					clear_selection()
		_press_button = MOUSE_BUTTON_NONE
		_dragging = false


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _press_button == MOUSE_BUTTON_NONE:
		return
	if not _dragging and event.position.distance_to(_press_position) > DRAG_THRESHOLD:
		_dragging = true
	if _dragging:
		_camera.pan_by_screen(event.relative)


func _update_hover() -> void:
	var region := ""
	var mouse := get_viewport().get_mouse_position()
	if not _dragging and not _dim.visible and not _pass_screen.visible and not _hud.is_over_ui(mouse):
		region = map.province_at(get_global_mouse_position())
	if region == hovered_id:
		return
	if hovered_id != "":
		_views[hovered_id].hovered = false
	hovered_id = region
	if region != "":
		_views[region].hovered = true
	# Preview the arrow the selected unit would get.
	_orders.preview = {}
	if selected_unit != null and reach.get(region, "") in ["move", "attack"]:
		var index := maxi(Orders.next_step_index(state, selected_unit), 0)
		var from := Orders.step_origin(state, selected_unit, index)
		_orders.preview = {"from": _orders.anchor(from), "to": _orders.anchor(region), "kind": reach[region]}
	_orders.queue_redraw()


func _zoom_anchor(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return event.position
	return get_viewport_rect().size / 2.0
