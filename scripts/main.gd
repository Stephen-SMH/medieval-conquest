extends Node2D
## Campaign map: builds the provinces from data/map.json and handles selection,
## hover, camera controls, map modes, armies, movement and turns.

enum MapMode { POLITICAL, TERRAIN, RESOURCES }

const DRAG_THRESHOLD := 6.0  # Screen pixels the mouse must move before a click becomes a drag.
const LOW_FOOD_COLOR := Color("#7a3f2a")
const HIGH_FOOD_COLOR := Color("#7fc24f")
const GAME_SEED := 20261101

var state: GameState
var map: MapData
var mode := MapMode.POLITICAL
var selected_id := ""
var selected_army: Army
var hovered_id := ""
## A province clicked once as the selected army's destination; a second click confirms.
var pending_destination := ""

var _views := {}  # province id -> ProvinceView
var _food_range := Vector2i.ZERO  # Lowest and highest food output, for the resources map.
var _press_button := MOUSE_BUTTON_NONE
var _press_position := Vector2.ZERO
var _dragging := false
var _border_layer: BorderLayer
var _army_layer: ArmyLayer
var _path_layer: PathLayer
var _pending_attack := ""  # Destination waiting for the player to confirm the forecast.
var _report_queue := []    # [Battle, province] pairs still to show.

@onready var _map_root: Node2D = $Map
@onready var _camera: MapCamera = $Camera
@onready var _panel: ProvincePanel = $UI/ProvincePanel
@onready var _army_panel: ArmyPanel = $UI/ArmyPanel
@onready var _top_bar: Control = $UI/TopBar
@onready var _turn_bar: Control = $UI/TurnBar
@onready var _date_label: Label = $UI/TurnBar/Rows/Turn/Date
@onready var _message_label: Label = $UI/TurnBar/Rows/Message
@onready var _end_turn_button: Button = $UI/TurnBar/Rows/Turn/EndTurnButton
@onready var _dim: Control = $UI/Dim
@onready var _forecast_popup: ForecastPopup = $UI/ForecastPopup
@onready var _battle_report: BattleReport = $UI/BattleReport
@onready var _resource_bar: ResourceBar = $UI/TopBar/Rows/Resources
@onready var _mode_buttons := {
	MapMode.POLITICAL: $UI/TopBar/Rows/Modes/PoliticalButton,
	MapMode.TERRAIN: $UI/TopBar/Rows/Modes/TerrainButton,
	MapMode.RESOURCES: $UI/TopBar/Rows/Modes/ResourcesButton,
}


func _ready() -> void:
	map = MapData.load_default()
	state = GameState.new_game(map, GAME_SEED)
	_camera.map_rect = Rect2(Vector2.ZERO, map.size)

	for id in map.province_order:
		var province: Dictionary = map.provinces[id]
		var view := ProvinceView.new()
		view.setup(id, province.polygon, province.centroid, province.name)
		_map_root.add_child(view)
		_views[id] = view

	_border_layer = BorderLayer.new()
	_border_layer.map = map
	_map_root.add_child(_border_layer)
	_path_layer = PathLayer.new()
	_path_layer.state = state
	_map_root.add_child(_path_layer)
	_army_layer = ArmyLayer.new()
	_army_layer.state = state
	_map_root.add_child(_army_layer)

	var group := ButtonGroup.new()
	for map_mode in _mode_buttons:
		var button: Button = _mode_buttons[map_mode]
		button.button_group = group
		button.pressed.connect(set_mode.bind(map_mode))
	_end_turn_button.pressed.connect(end_turn)
	_army_panel.split_requested.connect(_on_split_requested)
	_army_panel.merge_requested.connect(_on_merge_requested)
	_army_panel.appoint_requested.connect(_on_appoint_requested)
	_forecast_popup.confirmed.connect(_on_attack_confirmed)
	_forecast_popup.cancelled.connect(_close_forecast)
	_battle_report.closed.connect(_show_next_report)
	_panel.build_requested.connect(_on_build_requested)
	_panel.recruit_requested.connect(_on_recruit_requested)
	_resource_bar.tax_changed.connect(_on_tax_changed)

	set_mode(MapMode.POLITICAL)
	select("")
	_refresh_world()
	_show_message("Your realm: the Kingdom of Aldmere (blue). Click your banner in Greywater.")


func _process(_delta: float) -> void:
	_update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if _dim.visible:
		# A popup is open: Esc closes it, everything else waits.
		if event.is_action_pressed("deselect"):
			if _forecast_popup.visible:
				_close_forecast()
			elif _battle_report.visible:
				_show_next_report()
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
	elif event.is_action_pressed("deselect"):
		if pending_destination != "":
			pending_destination = ""
			_update_path_preview()
		else:
			select("")
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


# --- Selection --------------------------------------------------------------

func select(id: String) -> void:
	selected_army = null
	pending_destination = ""
	selected_id = id
	var neighbours: Array = map.neighbours(id) if id != "" else []
	for view_id in _views:
		var view: ProvinceView = _views[view_id]
		view.selected = view_id == id
		view.neighbour = view_id in neighbours
	_panel.show_province(state, id)
	_panel.visible = true
	_army_panel.visible = false
	_refresh_world()


func select_army(army: Army) -> void:
	select("")
	selected_army = army
	_panel.visible = false
	_army_panel.visible = true
	_army_panel.show_army(state, army)
	_refresh_world()


## Click on the map: a banner selects its army; with one of your armies
## selected, a province is a destination (click twice to march); otherwise
## the province is selected.
func _click(point: Vector2) -> void:
	var army := _army_layer.army_at(point)
	if army != null:
		select_army(army)
		return
	var id := map.province_at(point)
	if _can_order(selected_army) and id != "" and id != selected_army.province:
		if pending_destination == id:
			order_move(id)
		else:
			pending_destination = id
			_update_path_preview()
		return
	select(id)


func _can_order(army: Army) -> bool:
	return army != null and army.owner == state.player and army.can_move()


# --- Orders and turns --------------------------------------------------------

## Marches the selected army. If the path runs into an enemy army the player
## can see, the battle forecast is shown first and the march waits for "Attack!".
func order_move(destination: String) -> void:
	if not _can_order(selected_army):
		return
	var army := selected_army
	var path := state.find_path(army.province, destination)
	for i in path.size():
		if _army_layer.visible_provinces.has(path[i]) and not state.enemy_armies_in(path[i], army.owner).is_empty():
			var from := army.province if i == 0 else path[i - 1]
			_pending_attack = destination
			_forecast_popup.show_forecast(state, army, path[i], state.forecast_battle(army, path[i], from))
			_dim.visible = true
			return
	_march(army, destination)


func _march(army: Army, destination: String) -> void:
	var events := state.order_move(army, destination)
	pending_destination = ""
	_report(events)
	if state.armies.has(army):
		select_army(army)
	else:
		select(destination)


func _on_attack_confirmed() -> void:
	var destination := _pending_attack
	_close_forecast()
	_march(selected_army, destination)


func _close_forecast() -> void:
	_pending_attack = ""
	_forecast_popup.visible = false
	_dim.visible = false


func _show_next_report() -> void:
	if _report_queue.is_empty():
		_battle_report.visible = false
		_dim.visible = false
		return
	var next: Array = _report_queue.pop_front()
	_battle_report.show_battle(state, next[0], next[1])
	_dim.visible = true


func end_turn() -> void:
	var events := state.end_turn()
	_report(events)
	_refresh_world()
	if selected_army != null and state.armies.has(selected_army):
		select_army(selected_army)
	else:
		select(selected_id)


func _on_build_requested(province: String, building: String) -> void:
	if Economy.start_building(state, province, building):
		_show_message("Construction started in %s: %s." % [map.provinces[province].name, Rules.building(building).display_name])
	select(province)


func _on_recruit_requested(province: String, unit: String) -> void:
	if Economy.recruit(state, province, unit):
		_show_message("%s will join the garrison in %s next turn." % [Rules.unit(unit).display_name, map.provinces[province].name])
	select(province)


func _on_tax_changed(level: String) -> void:
	state.factions[state.player].tax = level
	_show_message("Taxes set to %s." % level)
	_refresh_world()
	if selected_id != "":
		_panel.show_province(state, selected_id)


## Shows the most important movement event in the message line, and queues
## a report for every battle.
func _report(events: Array) -> void:
	var message := ""
	var economy_notes := PackedStringArray()
	for event in events:
		if event.type == "economy":
			if event.faction == state.player:
				economy_notes.append(event.text)
			continue
		var army: Army = event.army
		var where: String = map.provinces[event.province].name
		match event.type:
			"moved":
				if army.owner == state.player:
					message = "%s marched to %s." % [army.display_name(), where]
			"zone_of_control":
				message = "%s stopped in %s: enemy army nearby." % [army.display_name(), where]
			"occupied":
				message = "%s captured %s from %s." % [army.display_name(), where, map.factions[event.previous_owner].name]
			"battle":
				var battle: Battle = event.battle
				message = "Battle of %s: the %s won." % [where, "attackers" if battle.attacker_won() else "defenders"]
				_report_queue.append([battle, event.province])
	if not economy_notes.is_empty():
		message = " ".join(economy_notes) + (" " + message if message != "" else "")
	if message != "":
		_show_message(message)
	_refresh_world()
	if not _battle_report.visible and not _report_queue.is_empty():
		_show_next_report()


func _show_message(text: String) -> void:
	_message_label.text = text


func _on_split_requested(indices: Array) -> void:
	var new_army := state.split(selected_army, indices)
	if new_army == null:
		_show_message("Tick at least one regiment and leave one behind. The new general costs %d gold." % Economy.GENERAL_COST.gold)
		return
	_show_message("%s now leads %d regiments." % [new_army.display_name(), new_army.regiments.size()])
	select_army(new_army)


func _on_merge_requested(other: Army) -> void:
	var army := selected_army
	if state.merge(army, other):
		_show_message("Armies merged: %d regiments." % army.regiments.size())
	select_army(army)


func _on_appoint_requested() -> void:
	if state.appoint_general(selected_army):
		_show_message("%s takes command." % selected_army.general.name)
	else:
		_show_message("Appointing a general costs %d gold." % Economy.GENERAL_COST.gold)
	select_army(selected_army)


# --- Drawing -----------------------------------------------------------------

func set_mode(new_mode: MapMode) -> void:
	mode = new_mode
	_recolor()
	for map_mode in _mode_buttons:
		_mode_buttons[map_mode].set_pressed_no_signal(map_mode == mode)
	_show_legend()


func _refresh_world() -> void:
	_date_label.text = state.date_text()
	_resource_bar.show_faction(state, state.player)
	_recolor()
	_show_legend()
	for id in map.province_order:
		_border_layer.capital_colors[id] = map.factions[state.owners[id]].color
	_border_layer.queue_redraw()
	_army_layer.selected_army = selected_army
	_army_layer.visible_provinces = state.visible_provinces(state.player)
	_army_layer.queue_redraw()
	_update_path_preview()


func _recolor() -> void:
	_food_range = Vector2i(1 << 30, 0)
	for id in map.province_order:
		var food := roundi(Economy.province_food(state, id))
		_food_range = Vector2i(mini(_food_range.x, food), maxi(_food_range.y, food))
	for id in _views:
		_views[id].set_base_color(_color_for(id))


## Shows the selected army's path: to the pending destination if there is one,
## else to the hovered province, else the path it is already marching.
func _update_path_preview() -> void:
	if not _can_order(selected_army):
		_path_layer.clear()
		return
	var target := pending_destination if pending_destination != "" else hovered_id
	if target == "" or target == selected_army.province:
		if selected_army.path.is_empty():
			_path_layer.clear()
		else:
			_path_layer.show_path(selected_army, selected_army.path, _army_layer.visible_provinces)
		return
	_path_layer.show_path(selected_army, state.find_path(selected_army.province, target), _army_layer.visible_provinces)


func _color_for(id: String) -> Color:
	match mode:
		MapMode.TERRAIN:
			return map.terrain(id).color
		MapMode.RESOURCES:
			var food := Economy.province_food(state, id)
			return LOW_FOOD_COLOR.lerp(HIGH_FOOD_COLOR, inverse_lerp(_food_range.x, _food_range.y, food))
		_:
			return map.factions[state.owners[id]].color


func _show_legend() -> void:
	var entries := []
	match mode:
		MapMode.POLITICAL:
			for id in map.factions:
				entries.append([map.factions[id].color, map.factions[id].name])
			_panel.show_legend("Factions", entries)
		MapMode.TERRAIN:
			for id in Rules.terrains:
				var terrain: TerrainType = Rules.terrains[id]
				entries.append([terrain.color, "%s (move %d)" % [terrain.display_name, terrain.move_cost]])
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
				var id := map.province_at(point)
				if _can_order(selected_army) and id != "" and id != selected_army.province:
					order_move(id)
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
	var id := ""
	var mouse := get_viewport().get_mouse_position()
	var over_ui := false
	for control: Control in [_panel, _army_panel, _top_bar, _turn_bar, _dim]:
		over_ui = over_ui or (control.visible and control.get_global_rect().has_point(mouse))
	if not over_ui and not _dragging:
		id = map.province_at(get_global_mouse_position())
	if id == hovered_id:
		return
	if hovered_id != "":
		_views[hovered_id].hovered = false
	hovered_id = id
	if id != "":
		_views[id].hovered = true
	if pending_destination == "":
		_update_path_preview()


## Wheel zoom goes towards the mouse; keyboard zoom towards the screen centre.
func _zoom_anchor(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return event.position
	return get_viewport_rect().size / 2.0
