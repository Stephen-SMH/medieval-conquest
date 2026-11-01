extends Node2D
## The game scene: draws the map and unit tokens, and turns clicks into orders
## (PRD 8.3): click a unit (or your region, for the whole stack), then a green
## region to move, a red one to attack. Also runs the other factions' turns.

enum MapMode { POLITICAL, TERRAIN, RESOURCES }

const SessionScript := preload("res://scripts/session.gd")
const DRAG_THRESHOLD := 6.0  # Screen pixels the mouse must move before a click becomes a drag.
const LOW_FOOD_COLOR := Color("#7a3f2a")
const HIGH_FOOD_COLOR := Color("#7fc24f")

var state: GameState
var map: MapData
var mode := MapMode.POLITICAL
var selection: Array[Unit] = []
var selected_region := ""
var hovered_id := ""
## What clicking each region would do with the selection: "move", "attack" or "blocked".
var reach := {}

var _views := {}  # region id -> ProvinceView
var _food_range := Vector2i.ZERO
var _press_button := MOUSE_BUTTON_NONE
var _press_position := Vector2.ZERO
var _dragging := false
var _border_layer: BorderLayer
var _token_layer: TokenLayer
var _pending_attack := {}  # {"units": Array[Unit], "region": String} waiting for the forecast's OK.
var _last_battle := []  # [Battle, region] for the Report button.

@onready var _map_root: Node2D = $Map
@onready var _camera: MapCamera = $Camera
@onready var _panel: ProvincePanel = $UI/ProvincePanel
@onready var _unit_panel: UnitPanel = $UI/UnitPanel
@onready var _top_bar: Control = $UI/TopBar
@onready var _turn_bar: Control = $UI/TurnBar
@onready var _date_label: Label = $UI/TurnBar/Rows/Turn/Date
@onready var _message_label: Label = $UI/TurnBar/Rows/Message
@onready var _end_turn_button: Button = $UI/TurnBar/Rows/Turn/EndTurnButton
@onready var _undo_button: Button = $UI/TurnBar/Rows/Turn/UndoButton
@onready var _report_button: Button = $UI/TurnBar/Rows/Turn/ReportButton
@onready var _dim: Control = $UI/Dim
@onready var _forecast_popup: ForecastPopup = $UI/ForecastPopup
@onready var _battle_report: BattleReport = $UI/BattleReport
@onready var _resource_bar: ResourceBar = $UI/TopBar/Rows/Resources
@onready var _objectives_label: RichTextLabel = $UI/TopBar/Rows/Objectives
@onready var _save_button: Button = $UI/TopBar/Rows/Modes/SaveButton
@onready var _end_screen: EndScreen = $UI/EndScreen
@onready var _save_popup: SavePopup = $UI/SavePopup
@onready var _mode_buttons := {
	MapMode.POLITICAL: $UI/TopBar/Rows/Modes/PoliticalButton,
	MapMode.TERRAIN: $UI/TopBar/Rows/Modes/TerrainButton,
	MapMode.RESOURCES: $UI/TopBar/Rows/Modes/ResourcesButton,
}


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
	_border_layer = BorderLayer.new()
	_border_layer.state = state
	_map_root.add_child(_border_layer)
	_token_layer = TokenLayer.new()
	_token_layer.state = state
	_map_root.add_child(_token_layer)

	var group := ButtonGroup.new()
	for map_mode in _mode_buttons:
		var button: Button = _mode_buttons[map_mode]
		button.button_group = group
		button.pressed.connect(set_mode.bind(map_mode))
	_end_turn_button.pressed.connect(end_turn)
	_undo_button.pressed.connect(undo)
	_report_button.pressed.connect(_show_last_report)
	_unit_panel.select_only.connect(func(unit): select_units([unit]))
	_unit_panel.merge_requested.connect(_on_merge_requested)
	_unit_panel.hire_requested.connect(_on_hire_requested)
	_unit_panel.region_requested.connect(select_region)
	_unit_panel.besiege_requested.connect(_on_besiege_requested)
	_save_button.pressed.connect(_open_saves)
	_save_popup.save_requested.connect(_on_save_requested)
	_save_popup.load_requested.connect(_on_load_requested)
	_save_popup.closed.connect(_close_popups)
	_end_screen.play_again.connect(_play_again)
	_end_screen.closed.connect(_close_popups)
	_end_screen.menu.connect(_go_to_menu)
	_forecast_popup.confirmed.connect(_on_attack_confirmed)
	_forecast_popup.cancelled.connect(_close_popups)
	_battle_report.closed.connect(_close_popups)
	_panel.build_requested.connect(_on_build_requested)
	_panel.recruit_requested.connect(_on_recruit_requested)
	_resource_bar.tax_changed.connect(_on_tax_changed)

	set_mode(MapMode.POLITICAL)
	clear_selection()
	_show_message("You are %s. Click one of your units, then a green region to move or a red one to attack." % state.faction_name(state.viewer()))
	_run_other_factions()


func _process(_delta: float) -> void:
	_update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if _dim.visible:
		if event.is_action_pressed("deselect"):
			_close_popups()
		return
	if event.is_action_pressed("map_mode_political"):
		set_mode(MapMode.POLITICAL)
	elif event.is_action_pressed("map_mode_terrain"):
		set_mode(MapMode.TERRAIN)
	elif event.is_action_pressed("map_mode_resources"):
		set_mode(MapMode.RESOURCES)
	elif event.is_action_pressed("zoom_in"):
		_camera.zoom_at(_zoom_anchor(event), MapCamera.ZOOM_STEP)
	elif event.is_action_pressed("zoom_out"):
		_camera.zoom_at(_zoom_anchor(event), 1.0 / MapCamera.ZOOM_STEP)
	elif event.is_action_pressed("end_turn"):
		end_turn()
	elif event.is_action_pressed("undo"):
		undo()
	elif event.is_action_pressed("deselect"):
		clear_selection()
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _is_my_turn() -> bool:
	return state.factions[state.current_faction()].human and not state.is_over()


# --- Selection (OR-1, OR-2) ----------------------------------------------------------

func select_units(units: Array) -> void:
	selection.assign(units)
	selected_region = ""
	_panel.visible = false
	_unit_panel.visible = true
	_unit_panel.show_units(state, selection)
	_refresh_world()


func select_region(region: String) -> void:
	selection.clear()
	selected_region = region
	_panel.visible = true
	_unit_panel.visible = false
	_panel.show_province(state, region)
	_refresh_world()


func clear_selection() -> void:
	select_region("")


## A click on the map: a token selects that unit; with units selected, a lit
## region is an order; your own region selects its whole stack.
func _click(point: Vector2) -> void:
	var unit := _token_layer.unit_at(point)
	var region := map.province_at(point)
	if unit != null:
		region = unit.province
		if unit.owner == state.current_faction() and _is_my_turn():
			select_units([unit])
			return
	if region == "":
		clear_selection()
		return
	if not selection.is_empty() and reach.has(region):
		order(region)
		return
	var mine := state.units_in(region).filter(func(u: Unit): return u.owner == state.current_faction())
	if not mine.is_empty() and _is_my_turn() and (unit == null or unit.owner == state.current_faction()):
		select_units(mine)
		return
	select_region(region)


# --- Orders (OR-3..OR-7) ----------------------------------------------------------------

## Carries out what the selection can do in `region`.
func order(region: String) -> void:
	if selection.is_empty() or not _is_my_turn():
		return
	match reach.get(region, ""):
		"move":
			var events := state.move_stack(selection, region)
			_report_events(events)
			select_units(selection)
			_check_end()
		"attack":
			var attackers := state.attackers_for(selection, region)
			_pending_attack = {"units": attackers, "region": region}
			_forecast_popup.show_forecast(state, attackers, region, state.forecast_attack(attackers, region))
			_dim.visible = true
		"blocked":
			var reasons := PackedStringArray()
			for unit in selection:
				var problem := state.move_problem(unit, region)
				if problem != "" and not (problem in reasons):
					reasons.append(problem)
			_show_message("Can't go to %s: %s." % [map.region_name(region), ", ".join(reasons)])


func _on_attack_confirmed() -> void:
	var attackers: Array = _pending_attack.units
	var region: String = _pending_attack.region
	_close_popups()
	var before := {}
	for unit in attackers + state.enemy_units_in(region, attackers[0].owner):
		before[unit] = unit.soldiers()
	var result := state.attack(attackers, region)
	if result.is_empty():
		return
	_play_battle(result, before)
	var survivors := attackers.filter(func(u): return state.units.has(u))
	if survivors.is_empty():
		clear_selection()
	else:
		select_units(survivors)
	_check_end()


## The short battle effect on the map (BR-4): both regions shake, each unit's
## losses float up, and a captured region says so.
func _play_battle(result: Dictionary, before: Dictionary) -> void:
	var battle: Battle = result.battle
	var region: String = result.events[0].province
	var origin: String = result.events[0].origin
	_token_layer.shake(region)
	_token_layer.shake(origin)
	_refresh_world()
	for unit: Unit in before:
		var lost: int = before[unit] - (unit.soldiers() if state.units.has(unit) and not unit.is_destroyed() else 0)
		if lost <= 0:
			continue
		var at: Vector2 = _token_layer.token_rect(unit).get_center() if state.units.has(unit) \
			else map.provinces[unit.province].centroid
		_token_layer.float_text(at, "−%d" % lost if state.units.has(unit) else "destroyed", Color("#ff8070"))
	for event in result.events:
		if event.type == "captured":
			_token_layer.float_text(map.provinces[region].centroid + Vector2(0, -60), "Captured!", Color("#ffe080"))
	_last_battle = [battle, region]
	_report_button.visible = true
	_report_events(result.events)


func undo() -> void:
	if _is_my_turn() and state.undo_last_move():
		_show_message("Move undone.")
		if selection.is_empty():
			_refresh_world()
		else:
			select_units(selection)


func end_turn() -> void:
	if not _is_my_turn():
		return
	_report_events(state.end_faction_turn())
	_run_other_factions()
	clear_selection()


## Plays every AI faction's turn until a human is up, then autosaves.
func _run_other_factions() -> void:
	var guard := state.turn_order.size() * 2
	while not state.factions[state.current_faction()].human and not state.is_over() and guard > 0:
		guard -= 1
		var events := AI.play_turn(state)
		events.append_array(state.end_faction_turn())
		_report_events(events, true)
	_refresh_world()
	if not _check_end():
		SaveGame.save(state, "auto")


## Shows the end screen once the game is decided, and records campaign stars.
func _check_end() -> bool:
	if not state.is_over():
		return false
	_refresh_world()
	if state.result.result == "won" and state.mission.has("campaign") and state.result.winner == state.viewer():
		Progress.record(state.mission.campaign, int(state.mission.mission_index), int(state.result.stars))
	_end_screen.show_result(state, state.viewer())
	_dim.visible = true
	return true


func _play_again() -> void:
	var session := get_node_or_null("/root/Session")
	if session != null:
		session.setup = session.last_setup.duplicate(true)
	get_tree().reload_current_scene()


func _go_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _open_saves() -> void:
	_save_popup.open(_is_my_turn())
	_dim.visible = true


func _on_save_requested(slot: String) -> void:
	var error := SaveGame.save(state, slot)
	_show_message("Saved to slot %s." % slot if error == OK else "Couldn't save: %s." % error_string(error))
	_save_popup.open(_is_my_turn())


func _on_load_requested(slot: String) -> void:
	var data := SaveGame.load_slot(slot)
	var session := get_node_or_null("/root/Session")
	if data.is_empty() or session == null:
		return
	session.setup = {"save": data}
	get_tree().reload_current_scene()


func _on_besiege_requested(region: String) -> void:
	if Sieges.besiege(state, selection, region):
		_show_message("The siege of %s begins: %d turns until the walls are breached, if you stay next to them." % [
			map.region_name(region), Sieges.duration(state, region, state.current_faction())])
	select_units(selection)


## Writes the most important events to the message line.
func _report_events(events: Array, quiet := false) -> void:
	var notes := PackedStringArray()
	var viewer := state.viewer()
	for event in events:
		match event.type:
			"economy":
				if event.faction == viewer:
					notes.append(event.text)
			"captured":
				if event.faction == viewer or event.previous_owner == viewer:
					notes.append("%s captured %s." % [state.faction_name(event.faction), map.region_name(event.province)])
			"battle":
				var battle: Battle = event.battle
				if battle.ending == "ranged":
					notes.append("Volleys at %s." % map.region_name(event.province))
				else:
					notes.append("Battle of %s: the %s won." % [map.region_name(event.province),
						"attackers" if battle.attacker_won() else "defenders"])
			"repulsed":
				if not quiet:
					notes.append("The attack failed; the survivors fell back to %s." % map.region_name(event.province))
			"general_lost":
				notes.append("General %s was %s." % [event.general.name, event.fate])
			"siege_breached":
				if event.faction == viewer or state.owners[event.province] == viewer:
					notes.append("The walls of %s are breached." % map.region_name(event.province))
	if not notes.is_empty():
		_show_message(" ".join(notes))
	_refresh_world()


func _show_message(text: String) -> void:
	_message_label.text = text


func _show_last_report() -> void:
	if _last_battle.is_empty():
		return
	_battle_report.show_battle(state, _last_battle[0], _last_battle[1], state.viewer())
	_dim.visible = true


func _close_popups() -> void:
	_pending_attack = {}
	_forecast_popup.visible = false
	_battle_report.visible = false
	_end_screen.visible = false
	_save_popup.visible = false
	_dim.visible = false


func _on_merge_requested(target: Unit, source: Unit) -> void:
	if state.merge(target, source):
		_show_message("Merged: %d soldiers, %s." % [target.soldiers(), target.rank_name()])
	select_units([target])


func _on_hire_requested(unit: Unit) -> void:
	if state.hire_general(unit):
		_show_message("General %s takes command." % unit.general.name)
	else:
		_show_message("A general costs %d gold." % Economy.GENERAL_COST.gold)
	select_units([unit])


func _on_build_requested(region: String, building: String) -> void:
	if Economy.start_building(state, region, building):
		_show_message("Construction started in %s: %s." % [map.region_name(region), Rules.building(building).display_name])
	select_region(region)


func _on_recruit_requested(region: String, unit: String) -> void:
	if Economy.recruit(state, region, unit):
		_show_message("%s will be ready in %s at the end of the turn." % [Rules.unit(unit).display_name, map.region_name(region)])
	select_region(region)


func _on_tax_changed(level: String) -> void:
	state.factions[state.viewer()].tax = level
	_show_message("Taxes set to %s." % level)
	_refresh_world()


# --- Drawing -----------------------------------------------------------------

func set_mode(new_mode: MapMode) -> void:
	mode = new_mode
	for map_mode in _mode_buttons:
		_mode_buttons[map_mode].set_pressed_no_signal(map_mode == mode)
	_refresh_world()


func _refresh_world() -> void:
	var faction := state.current_faction()
	_date_label.text = "%s — %s to move" % [state.date_text(), state.faction_name(faction)]
	_undo_button.disabled = state.undo_stack.is_empty() or not _is_my_turn()
	_resource_bar.show_faction(state, state.viewer())
	_show_objectives()
	reach = state.reachable(selection) if _is_my_turn() and not selection.is_empty() else {}
	_food_range = Vector2i(1 << 30, 0)
	for region in map.province_order:
		var food := roundi(Economy.province_food(state, region))
		_food_range = Vector2i(mini(_food_range.x, food), maxi(_food_range.y, food))
	var selected_here := {}
	for unit in selection:
		selected_here[unit.province] = true
	for region in _views:
		var view: ProvinceView = _views[region]
		view.set_base_color(_color_for(region))
		view.selected = region == selected_region or selected_here.has(region)
		view.neighbour = false
		view.reach = reach.get(region, "")
	_show_legend()
	_border_layer.queue_redraw()
	_token_layer.selected = selection
	_token_layer.visible_provinces = state.visible_provinces(state.viewer())
	_token_layer.queue_redraw()


func _show_objectives() -> void:
	if not Mission.is_mission(state):
		_objectives_label.text = "[b]Conquest:[/b] defeat every rival. %d factions remain." % state.living_factions().size()
		return
	var parts := PackedStringArray()
	for objective in Mission.objectives(state):
		parts.append("[color=%s]%s %s[/color]" % ["#8fe08f" if objective.done else "#e8e4dc",
			"[x]" if objective.done else "[  ]", objective.text])
	_objectives_label.text = "%s   [b]Turn %d[/b] — par %d, limit %d" % ["   ".join(parts), state.turn,
		Mission.par(state), Mission.hard_limit(state)]


func _color_for(region: String) -> Color:
	match mode:
		MapMode.TERRAIN:
			return map.terrain(region).color
		MapMode.RESOURCES:
			var food := Economy.province_food(state, region)
			return LOW_FOOD_COLOR.lerp(HIGH_FOOD_COLOR, inverse_lerp(_food_range.x, _food_range.y, food))
		_:
			return state.faction_color(state.owners[region])


func _show_legend() -> void:
	var entries := []
	match mode:
		MapMode.POLITICAL:
			for id in state.turn_order:
				entries.append([state.faction_color(id), state.faction_name(id) + ("" if state.factions[id].alive else " (fallen)")])
			entries.append([state.faction_color("neutral"), state.faction_name("neutral")])
			_panel.show_legend("Factions", entries)
		MapMode.TERRAIN:
			for id in Rules.terrains:
				var terrain: TerrainType = Rules.terrains[id]
				entries.append([terrain.color, terrain.display_name])
			_panel.show_legend("Terrain", entries)
		MapMode.RESOURCES:
			var middle := roundi((_food_range.x + _food_range.y) / 2.0)
			entries.append([LOW_FOOD_COLOR, "%d food per turn" % _food_range.x])
			entries.append([LOW_FOOD_COLOR.lerp(HIGH_FOOD_COLOR, 0.5), "%d food per turn" % middle])
			entries.append([HIGH_FOOD_COLOR, "%d food per turn" % _food_range.y])
			_panel.show_legend("Food output", entries)


# --- Mouse -------------------------------------------------------------------

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if not (event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]):
		return
	if event.pressed:
		if _press_button == MOUSE_BUTTON_NONE:
			_press_button = event.button_index
			_press_position = event.position
			_dragging = event.button_index == MOUSE_BUTTON_MIDDLE  # Middle always drags.
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
	var over_ui := false
	for control: Control in [_panel, _unit_panel, _top_bar, _turn_bar, _dim]:
		over_ui = over_ui or (control.visible and control.get_global_rect().has_point(mouse))
	if not over_ui and not _dragging:
		region = map.province_at(get_global_mouse_position())
	if region == hovered_id:
		return
	if hovered_id != "":
		_views[hovered_id].hovered = false
	hovered_id = region
	if region != "":
		_views[region].hovered = true


## Wheel zoom goes towards the mouse; keyboard zoom towards the screen centre.
func _zoom_anchor(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return event.position
	return get_viewport_rect().size / 2.0
