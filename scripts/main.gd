extends Node2D
## Campaign map: builds the provinces from data/map.json and handles selection,
## hover, camera controls and map modes.

enum MapMode { POLITICAL, TERRAIN, RESOURCES }

const DRAG_THRESHOLD := 6.0  # Screen pixels the mouse must move before a click becomes a drag.
const LOW_FOOD_COLOR := Color("#7a3f2a")
const HIGH_FOOD_COLOR := Color("#7fc24f")

var map: MapData
var mode := MapMode.POLITICAL
var selected_id := ""
var hovered_id := ""

var _views := {}  # province id -> ProvinceView
var _food_range := Vector2i.ZERO  # Lowest and highest food output, for the resources map.
var _press_button := MOUSE_BUTTON_NONE
var _press_position := Vector2.ZERO
var _dragging := false

@onready var _map_root: Node2D = $Map
@onready var _camera: MapCamera = $Camera
@onready var _panel: ProvincePanel = $UI/ProvincePanel
@onready var _top_bar: Control = $UI/TopBar
@onready var _mode_buttons := {
	MapMode.POLITICAL: $UI/TopBar/Rows/Modes/PoliticalButton,
	MapMode.TERRAIN: $UI/TopBar/Rows/Modes/TerrainButton,
	MapMode.RESOURCES: $UI/TopBar/Rows/Modes/ResourcesButton,
}


func _ready() -> void:
	map = MapData.load_default()
	_camera.map_rect = Rect2(Vector2.ZERO, map.size)

	_food_range = Vector2i(1 << 30, 0)
	for id in map.province_order:
		var province: Dictionary = map.provinces[id]
		var view := ProvinceView.new()
		view.setup(id, province.polygon, province.centroid, province.name)
		_map_root.add_child(view)
		_views[id] = view
		var food := ProvincePanel.food_output(map, id)
		_food_range = Vector2i(mini(_food_range.x, food), maxi(_food_range.y, food))

	var border_layer := BorderLayer.new()
	border_layer.map = map
	for id in map.province_order:
		border_layer.capital_colors[id] = map.factions[map.provinces[id].owner].color
	_map_root.add_child(border_layer)

	var group := ButtonGroup.new()
	for map_mode in _mode_buttons:
		var button: Button = _mode_buttons[map_mode]
		button.button_group = group
		button.pressed.connect(set_mode.bind(map_mode))

	set_mode(MapMode.POLITICAL)
	select("")


func _process(_delta: float) -> void:
	_update_hover()


func _unhandled_input(event: InputEvent) -> void:
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
	elif event.is_action_pressed("deselect"):
		select("")
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func select(id: String) -> void:
	selected_id = id
	var neighbours: Array = map.neighbours(id) if id != "" else []
	for view_id in _views:
		var view: ProvinceView = _views[view_id]
		view.selected = view_id == id
		view.neighbour = view_id in neighbours
	_panel.show_province(map, id)


func set_mode(new_mode: MapMode) -> void:
	mode = new_mode
	for id in _views:
		_views[id].set_base_color(_color_for(id))
	for map_mode in _mode_buttons:
		_mode_buttons[map_mode].set_pressed_no_signal(map_mode == mode)
	_show_legend()


func _color_for(id: String) -> Color:
	match mode:
		MapMode.TERRAIN:
			return map.terrain(id).color
		MapMode.RESOURCES:
			var food := ProvincePanel.food_output(map, id)
			return LOW_FOOD_COLOR.lerp(HIGH_FOOD_COLOR, inverse_lerp(_food_range.x, _food_range.y, food))
		_:
			return map.factions[map.provinces[id].owner].color


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


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if not (event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]):
		return
	if event.pressed:
		if _press_button == MOUSE_BUTTON_NONE:
			_press_button = event.button_index
			_press_position = event.position
			_dragging = event.button_index != MOUSE_BUTTON_LEFT  # Right and middle always drag.
	elif event.button_index == _press_button:
		if not _dragging:
			select(map.province_at(get_global_mouse_position()))
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
	var over_ui := _panel.get_global_rect().has_point(mouse) or _top_bar.get_global_rect().has_point(mouse)
	if not over_ui and not _dragging:
		id = map.province_at(get_global_mouse_position())
	if id == hovered_id:
		return
	if hovered_id != "":
		_views[hovered_id].hovered = false
	hovered_id = id
	if id != "":
		_views[id].hovered = true


## Wheel zoom goes towards the mouse; keyboard zoom towards the screen centre.
func _zoom_anchor(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return event.position
	return get_viewport_rect().size / 2.0
