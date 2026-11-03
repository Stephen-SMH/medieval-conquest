extends Node2D
## The game scene: the painted map, the armies and the order arrows, and the
## turns (PRD 8.3, A, B, C). Click one of your armies, then a region: a blue
## arrow moves there; an enemy region opens a ring of buttons to attack or,
## when another of your armies already attacks it, to support that attack.
## A slider per soldier type (and a TOTAL slider) chooses who goes. The army
## stays selected, so more arrows can send the rest elsewhere; whoever isn't
## sent stays home. Cavalry detachments can add a second step. Click an arrow
## to cancel that order; right-click the army (or press U) to cancel all.
## The hourglass ends your turn: your orders resolve and play out, then each
## other faction takes its turn on the map (tap to skip it).

enum MapMode { POLITICAL, TERRAIN }

const SessionScript := preload("res://scripts/session.gd")
const DRAG_THRESHOLD := 6.0
const TUTORIAL_ZOOM := 0.8

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
var _marks: SiteMarks
var _tokens: TokenLayer
var _effects: Effects
var _press_button := MOUSE_BUTTON_NONE
var _press_position := Vector2.ZERO
var _dragging := false
## Drag-to-aim (PRD I): the army a left press started on, and whether the drag is aiming it.
var _aim_unit: Unit = null
var _aiming := false
var _touch := TouchGestures.new()
var _last_human := ""
var _pass_screen: Control
var _pass_label: Label
var _messages := PackedStringArray()
## How many of the mission's notes (state.mission_log) the HUD has shown.
var _notes_shown := 0
var _last_battles := []  # [Battle, region] pairs from the last resolution.
var _busy := false  # True while a turn resolves on screen.
var _attack_popup: AttackPopup
var _recruit_window: RecruitWindow
var _popup: WoodPopup
var _pause_menu: PauseMenu
var _tutorial: Tutorial  # The guided tutorial's steps, in the tutorial mission only.
var _tutorial_box: TutorialBox
var _ring: ActionRing
## A reinforcement bundle bought and waiting for its province (PRD E), or {}.
var _placing := {}
## The province the reinforcements window was opened from, or "".
var _recruit_here := ""
## Set by a tap while an enemy's turn plays out: skip the rest of it.
var _skip_enemy := false

@onready var _map_root: Node2D = $Map
@onready var _camera: MapCamera = $Camera
@onready var _hud: Hud = $UI/Hud
@onready var _dim: Control = $UI/Dim
@onready var _region_popup: ProvincePanel = $UI/ProvincePanel
@onready var _battle_report: BattleReport = $UI/BattleReport
@onready var _end_screen: EndScreen = $UI/EndScreen
@onready var _save_popup: SavePopup = $UI/SavePopup


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
	# Open on the player's capital rather than the map's corner (the big real maps are wider than the screen).
	var home: String = state.capitals.get(state.mission.get("player", state.current_faction()), "")
	if home != "":
		_camera.position = map.provinces[home].centroid

	for region in map.province_order:
		var province: Dictionary = map.provinces[region]
		var view := ProvinceView.new()
		view.setup(region, province.polygon, province.centroid, province.name)
		_map_root.add_child(view)
		_views[region] = view
	_decor = MapDecor.new()
	_decor.state = state
	_map_root.add_child(_decor)
	_marks = SiteMarks.new()
	_marks.state = state
	_map_root.add_child(_marks)
	_orders = OrdersLayer.new()
	_orders.state = state
	_map_root.add_child(_orders)
	_tokens = TokenLayer.new()
	_tokens.state = state
	_map_root.add_child(_tokens)
	_orders.tokens = _tokens
	_effects = Effects.new()
	_effects.setup(state, _tokens, _views, _orders)
	_effects.camera = _camera
	_map_root.add_child(_effects)

	_ring = ActionRing.new()
	$UI.add_child(_ring)
	_ring.chosen.connect(_on_ring)
	_attack_popup = AttackPopup.new()
	_recruit_window = RecruitWindow.new()
	_popup = WoodPopup.new()
	for popup in [_attack_popup, _recruit_window, _popup]:
		$UI.add_child(popup)
		popup.closed.connect(_close_popups)
	_attack_popup.confirmed.connect(_on_attack_amounts)
	_recruit_window.bundle_chosen.connect(_on_bundle_chosen)
	_hud.recruit_pressed.connect(open_recruit)
	_hud.treasury_pressed.connect(open_treasury)
	_hud.menu_pressed.connect(open_menu)
	_hud.alerts_pressed.connect(next_idle_army)
	_hud.end_turn_pressed.connect(end_turn)
	_region_popup.build_requested.connect(_on_build_requested)
	$UI/ProvincePanel/Margin/Content/CloseButton.pressed.connect(_close_popups)
	_battle_report.closed.connect(_close_popups)
	_save_popup.save_requested.connect(_on_save_requested)
	_save_popup.load_requested.connect(_on_load_requested)
	_save_popup.closed.connect(_close_popups)
	_end_screen.play_again.connect(_play_again)
	_end_screen.closed.connect(_close_popups)
	_end_screen.menu.connect(_go_to_menu)
	_end_screen.next_mission.connect(_next_mission)
	_hud.objectives_pressed.connect(open_objectives)
	_effects.battle_ended.connect(_hud.battle_result)
	_build_pause_menu()
	_build_pass_screen()
	Hud.react_all($UI)
	Settings.apply(get_tree())
	AudioManager.music("map")
	if state.mission.get("tutorial", false):
		_start_tutorial()

	clear_selection()
	# Notes from earlier turns of a loaded game aren't shown again.
	_notes_shown = state.mission_log.filter(func(n): return int(n.turn) < state.turn).size()
	_show_new_notes()
	_advance()


func _process(_delta: float) -> void:
	_update_hover()
	if _tutorial != null and _tutorial.update(state, selected_unit):
		_show_tutorial_step()
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
			_stop_aiming()
	elif event is InputEventMagnifyGesture:
		_camera.zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		_camera.pan_by_screen(-event.delta * 8.0)
	elif _busy and (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		_effects.skip()  # Click to skip the turn's animation...
		_skip_enemy = true  # ...and the rest of an enemy's turn.


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
	elif event.is_action_pressed("deselect") and not _placing.is_empty():
		_cancel_placing()
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
	_ring.visible = false
	_show_unit_info(unit)
	_hud.show_army(state, unit)
	_refresh_world()


func select_region(region: String) -> void:
	selected_unit = null
	selected_region = region
	_ring.visible = false
	_hud.show_army(state, null)
	if region == "":
		_hud.hide_info()
	else:
		_show_region_info(region)
	_refresh_world()


func clear_selection() -> void:
	select_region("")


## A click on the map: an arrow cancels that order; with a unit selected a lit
## region is an order; a unit of yours selects it and shows its orders.
func _click(point: Vector2) -> void:
	if not _placing.is_empty():
		var target := map.province_at(point)
		if target != "" and Economy.bundle_problem(state, target, _placing, state.current_faction()) == "":
			_place_bundle(target)
		else:
			_hud.toast("Select one of the lit provinces, or right-click to cancel.")
		return
	var arrow := _orders.order_at(point)
	if not arrow.is_empty() and _is_my_turn() and arrow[0].owner == state.current_faction():
		AudioManager.sfx("click")
		_cancel_one(arrow[0], arrow[1])
		return
	var unit := _tokens.unit_at(point)
	var region := map.province_at(point)
	if unit != null:
		region = unit.province
	if selected_unit != null and reach.has(region) and region != selected_unit.province:
		order(region)
		return
	if unit != null and unit.owner == state.current_faction() and _is_my_turn():
		AudioManager.sfx("select")
		select_unit(unit)
		return
	select_region(region)


## Gives the selected army an order to `region`. A march, or a change to an
## existing order, opens the slider window; a new attack first opens the
## ring of buttons (attack, support, cancel); a cavalry detachment's second
## march just carries on.
func order(region: String) -> void:
	if selected_unit == null or not _is_my_turn():
		return
	var unit := selected_unit
	if reach.get(region, "") == "blocked" or not reach.has(region):
		_hud.toast("Can't go to %s: %s." % [map.region_name(region), Orders.problem(state, unit, "move", region)])
		return
	var plan := Orders.intent(state, unit, region)
	if plan.is_empty():
		return
	if plan.type == "move" and plan.step > 0:
		_give(unit, "move", region, {})
		return
	if plan.type == "attack" and plan.order < 0:
		var actions := ["cancel", "attack"]
		if Orders.can_support(state, unit, region):
			actions.append("support")
		_ring.set_meta("target", region)
		_ring.set_meta("unit", unit)
		_ring.open_at(_tokens.get_global_transform_with_canvas() * _tokens.region_anchor(region), actions)
		return
	_open_slider(unit, plan.type, region, false)


## The ring's choice: attack or support opens the slider window.
func _on_ring(action: String) -> void:
	var unit: Unit = _ring.get_meta("unit")
	var region: String = _ring.get_meta("target")
	if action == "cancel" or not state.units.has(unit):
		return
	_open_slider(unit, "attack", region, action == "support")


func _open_slider(unit: Unit, type: String, region: String, support: bool) -> void:
	var plan := Orders.intent(state, unit, region)
	var current: Dictionary = Orders.orders_of(state, unit)[plan.order] if not plan.is_empty() and plan.order >= 0 and plan.step == 0 else {}
	if not current.is_empty():
		support = current.get("support", false)
	_attack_popup.show_order(state, unit, type, region, Orders.available(state, unit, region, type), current, support,
		Orders.room_for(state, unit, region, type, support))
	_attack_popup.set_meta("target", region)
	_attack_popup.set_meta("unit", unit)
	_attack_popup.set_meta("type", type)
	_dim.visible = true


func _on_attack_amounts(amounts: Dictionary) -> void:
	var unit: Unit = _attack_popup.get_meta("unit")
	var region: String = _attack_popup.get_meta("target")
	_close_popups()
	_give(unit, _attack_popup.get_meta("type", "attack"), region, amounts)


func _give(unit: Unit, type: String, region: String, amounts: Dictionary) -> void:
	var problem := Orders.give(state, unit, type, region, amounts)
	if problem != "":
		_hud.toast(problem.capitalize())
	else:
		AudioManager.sfx("order")
	_after_order(unit)


## The unit stays selected for more arrows until every soldier has one.
func _after_order(unit: Unit) -> void:
	if Orders.is_spent(state, unit):
		clear_selection()
	else:
		select_unit(unit)


## Cancels all the unit's orders.
func _cancel_order(unit: Unit) -> void:
	if not state.orders.has(unit):
		return
	Orders.cancel(state, unit)
	_tutorial_record("cancel")
	_hud.toast("All orders cancelled.")
	select_unit(unit)


## Cancels one order (its arrow was clicked); its soldiers are free again.
func _cancel_one(unit: Unit, index: int) -> void:
	Orders.cancel_order(state, unit, index)
	_tutorial_record("cancel")
	_hud.toast("Order cancelled.")
	select_unit(unit)


func _show_unit_info(unit: Unit) -> void:
	var lines := PackedStringArray()
	lines.append("[b]%s army[/b] — %d soldiers: %s" % [state.faction_name(unit.owner), unit.soldiers(), unit.describe()])
	var health := roundi(unit.health() * 100)
	if health < 100:
		lines.append("[i]Health %d%%. Resting in your own region heals it.[/i]" % health)
	var buttons := []
	if unit.owner == state.current_faction() and _is_my_turn():
		if not state.orders.has(unit):
			lines.append("Click a [color=#2a4fa0]region to move[/color] or an [color=#9b2d20]enemy to attack[/color], or drag the army onto it; sliders set who goes.")
		else:
			var hints := PackedStringArray()
			if Orders.chain_index(state, unit) >= 0:
				hints.append("Click a region for the riders' second step.")
			if Orders.unassigned(state, unit) > 0:
				hints.append("More arrows send the rest elsewhere.")
			hints.append("Click an arrow to cancel it.")
			lines.append("Orders: %s. %s" % [Orders.describe(state, unit), " ".join(hints)])
			buttons.append(["Cancel all orders (U)", func(): _cancel_order(unit)])
		for target in map.neighbours(unit.province):
			if Orders.problem(state, unit, "besiege", target) == "":
				buttons.append(["Besiege %s" % map.region_name(target), func(): Orders.give(state, unit, "besiege", target); clear_selection()])
		if state.owners[unit.province] == unit.owner:
			if Economy.recruit_point(state, unit.province, unit.owner):
				buttons.append(["Reinforce here", func(): open_recruit(unit.province)])
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
		extras.append(Economy.site(state, region) + ": reinforcements")
	var ports := map.sea_links(region)
	if not ports.is_empty():
		extras.append("sails to " + ", ".join(ports.map(func(r): return map.region_name(r))))
	lines.append("[b]%s[/b] — %s%s. %s, %d gold a turn." % [map.region_name(region), state.faction_name(owner),
		" (%s)" % ", ".join(extras) if not extras.is_empty() else "", map.terrain(region).display_name, roundi(Economy.region_income(state, region))])
	var occupant := state.unit_in(region)
	if occupant != null and (occupant.owner == state.viewer() or state.visible_provinces(state.viewer()).has(region)):
		lines.append("Held by an army of %s: %d soldiers (%s)." % [state.faction_name(occupant.owner), occupant.soldiers(), occupant.describe()])
	var buttons := []
	if owner == state.current_faction() and _is_my_turn():
		if Economy.recruit_point(state, region, owner):
			buttons.append(["Reinforce here", func(): open_recruit(region)])
		buttons.append(["Build", func(): _open_region(region)])
	_hud.show_info("\n".join(lines), buttons)


# --- Turns -------------------------------------------------------------------------------

## The hourglass: your orders resolve and play out, then the other factions
## take their turns (PRD C).
func end_turn() -> void:
	if not _is_my_turn():
		return
	if _tutorial != null and not _tutorial.may_end_turn():
		_hud.toast("Finish this step of the tutorial first, or skip it.")
		return
	AudioManager.sfx("hourglass", 0.0)
	_last_human = state.current_faction()
	clear_selection()
	var before := _snapshot()
	_orders.snapshot()
	var events := state.end_faction_turn()
	await _show_resolution(events, before)
	_advance()


## Plays the computer factions' turns one after another, and stops when a
## human has to plan.
func _advance() -> void:
	while not state.is_over():
		var faction := state.current_faction()
		if state.factions[faction].human:
			_start_human_planning()
			return
		await _enemy_turn(faction)
	_refresh_world()
	_check_end()


## A computer faction's turn on the map, as in S&T: "Turn: …" with its flag
## at the bottom, its arrows, and its orders playing out. A tap skips the rest.
func _enemy_turn(faction: String) -> void:
	_busy = true
	_skip_enemy = false
	_hud.set_end_turn_enabled(false)
	var fast := _animation_speed() <= 0.0
	_hud.show_enemy_turn("Turn: %s" % state.faction_name(faction), state.faction_color(faction), state.factions[faction].civ)
	AI.play_turn(state)
	_refresh_world()
	if not fast and not _skip_enemy:
		await _pause(0.9)
	var before := _snapshot()
	_orders.snapshot()
	var events := state.end_faction_turn()
	await _show_resolution(events, before)
	_hud.hide_enemy_turn()


## Waits, unless the player taps to skip the enemy's turn.
func _pause(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds and not _skip_enemy:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _start_human_planning() -> void:
	var faction := state.current_faction()
	_busy = false
	_hud.set_end_turn_enabled(true)
	_refresh_world()
	var humans := state.turn_order.filter(func(f): return state.factions[f].human)
	if humans.size() > 1 and faction != _last_human and _last_human != "":
		_pass_label.text = "Pass the device to\n%s" % state.faction_name(faction)
		_pass_label.add_theme_color_override("font_color", state.faction_color(faction).lightened(0.4))
		_pass_screen.visible = true
	if faction == humans[0] and _tutorial == null:  # The tutorial doesn't overwrite the autosave.
		SaveGame.save(state, "auto")
	_hud.show_turn("Turn: %s" % state.faction_name(faction), state.faction_color(faction), state.factions[faction].civ if state.factions.has(faction) else "")


## Where every unit stood, and with how much HP, before the turn resolved.
func _snapshot() -> Dictionary:
	var before := {}
	for unit in state.units:
		before[unit] = Resolver.look(unit)
		before[unit]["province"] = unit.province
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
	await _effects.play(events, before, 0.0 if _skip_enemy else _animation_speed())
	_orders.stop_playing()
	_tokens.sync()
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
			"economy", "arrived":
				if event.faction == viewer:
					notes.append(event.text)
			"captured":
				if event.faction == viewer or event.previous_owner == viewer:
					notes.append("%s took %s." % [state.faction_name(event.faction), map.region_name(event.province)])
			"siege_breached":
				notes.append("The walls of %s are breached." % map.region_name(event.province))
	_messages = notes
	_show_new_notes()


func _check_end() -> bool:
	if not state.is_over():
		return false
	_refresh_world()
	if state.result.result == "won" and state.mission.has("campaign") and state.result.winner == state.viewer():
		Progress.record(state.mission.campaign, int(state.mission.mission_index), int(state.result.stars),
			int(state.result.get("points", 0)))
	elif state.result.result == "won" and state.mission.has("scenario") and state.result.winner == state.viewer():
		Progress.record_scenario(state.mission.scenario, int(state.result.stars), int(state.result.get("points", 0)))
	AudioManager.music("victory" if state.result.get("winner", "") == state.viewer() else "defeat")
	_end_screen.show_result(state, state.viewer())
	_dim.visible = true
	return true


# --- Popups --------------------------------------------------------------------------------

## The reinforcements window (PRD E): pick a bundle, confirm, then a
## province. Opened from a province that can take them ("Reinforce here"),
## the bundle goes straight there.
func open_recruit(region := "") -> void:
	if not _is_my_turn():
		return
	_recruit_here = region
	_recruit_window.show_faction(state, state.current_faction())
	_dim.visible = true


## A bundle was bought in the window: now pick its province on the map; only
## valid ones are lit, everything else is dimmed.
func _on_bundle_chosen(bundle: Dictionary) -> void:
	_close_popups()
	var targets := Economy.bundle_targets(state, bundle, state.current_faction())
	if targets.is_empty():
		_hud.toast("No province can take these reinforcements now.")
		return
	if _recruit_here in targets:
		_placing = bundle
		_place_bundle(_recruit_here)
		return
	clear_selection()
	_placing = bundle
	_hud.prompt("Select a province")
	_refresh_world()


func _place_bundle(region: String) -> void:
	var bundle := _placing
	_placing = {}
	_hud.prompt("")
	if Economy.buy(state, region, bundle):
		AudioManager.sfx("coins")
		_tutorial_record("recruit")
		_hud.toast("%d %s will arrive in %s next turn." % [int(bundle.soldiers), Rules.unit(bundle.type).plural_name().to_lower(), map.region_name(region)])
	else:
		_hud.toast("Can't send them to %s: %s." % [map.region_name(region), Economy.bundle_problem(state, region, bundle, state.current_faction())])
	_refresh_world()


func _cancel_placing() -> void:
	_placing = {}
	_hud.prompt("")
	_hud.toast("Reinforcements not ordered.")
	_refresh_world()


func open_treasury() -> void:
	var faction := state.viewer()
	_tutorial_record("treasury")
	_popup.open("Treasury")
	var lines := PackedStringArray()
	var total := 0.0
	for line in Economy.breakdown(state, faction).gold:
		lines.append("%s: %+d" % [line[0], roundi(line[1])])
		total += line[1]
	_popup.add_text("[b]Gold: %d[/b]  (%+d a turn)\n%s" % [roundi(state.factions[faction].resources.gold), roundi(total), "\n".join(lines)])
	_popup.add_text("[i]Every region pays gold each turn, towns and capitals more, markets more again. Gold pays for reinforcements, buildings and upkeep; if it runs out, soldiers desert.[/i]", 16)
	_popup.add_close()
	_dim.visible = true


## The pause screen (PRD K).
func open_menu() -> void:
	_close_popups()
	_pause_menu.open(not _restart_setup().is_empty(), not _last_battles.is_empty(), Mission.is_mission(state) and not Mission.primary(state).is_empty(),
		"Map: %s" % ("terrain" if mode == MapMode.POLITICAL else "political"))
	_dim.visible = true


func _build_pause_menu() -> void:
	_pause_menu = PauseMenu.new()
	$UI.add_child(_pause_menu)
	_pause_menu.resume.connect(_close_popups)
	_pause_menu.saves.connect(func(): _close_popups(); _open_saves())
	_pause_menu.report.connect(func(): _close_popups(); _show_last_report())
	_pause_menu.map_mode.connect(func():
		set_mode(MapMode.TERRAIN if mode == MapMode.POLITICAL else MapMode.POLITICAL)
		_close_popups())
	_pause_menu.objectives.connect(func(): _close_popups(); open_objectives())
	_pause_menu.info.connect(func(): _close_popups(); open_info())
	_pause_menu.restart.connect(func(): _confirm("Restart", "Start this game again from the beginning?", _restart))
	_pause_menu.exit.connect(func(): _confirm("Exit", "Leave for the main menu? Anything since the start of this turn is lost.", _go_to_menu))
	_pause_menu.surrender.connect(func():
		if not _is_my_turn():
			_hud.toast("You can surrender on your own turn.")
			return
		_confirm("Surrender", "Lay down your arms? %s" % ("The mission is lost." if Mission.is_mission(state) else "Your realm leaves the war."), _surrender))


## A yes-or-no question in a wooden window; `on_yes` runs on the check mark.
func _confirm(title: String, question: String, on_yes: Callable) -> void:
	_close_popups()
	_popup.open(title)
	_popup.add_text("[center]%s[/center]" % question, 20)
	_popup.add_check_and_close(func(): _close_popups(); on_yes.call())
	_dim.visible = true


## The setup to start this game again: the last new game if it's this one,
## else a campaign mission rebuilt from its campaign; {} if neither.
func _restart_setup() -> Dictionary:
	var session := get_node_or_null("/root/Session")
	if session != null and not session.last_setup.is_empty() and session.last_setup.scenario.get("id", "") == state.scenario_id:
		return session.last_setup
	if state.mission.has("campaign"):
		var campaign: String = state.mission.campaign
		return {"scenario": Forge.equip(Campaigns.mission(campaign, int(state.mission.mission_index)), Progress.upgrades(campaign)), "seed": randi()}
	return {}


func _restart() -> void:
	var session := get_node_or_null("/root/Session")
	if session != null:
		session.setup = _restart_setup().duplicate(true)
	LoadingScreen.open(get_tree(), scene_file_path)


## The player gives up (PRD K): the game is lost, or in hotseat their realm
## leaves it and the next player goes on.
func _surrender() -> void:
	Mission.surrender(state, state.current_faction())
	clear_selection()
	if state.is_over():
		_check_end()
		return
	_last_human = state.current_faction()
	var before := _snapshot()
	_orders.snapshot()
	var events := state.end_faction_turn()
	await _show_resolution(events, before)
	_advance()


## Where the game stands (PRD K's info): the map and turn, then each realm's
## regions and soldiers, and your treasury.
func open_info() -> void:
	_popup.open("Info")
	var lines := PackedStringArray()
	var title := state.scenario_id.capitalize()
	if state.mission.has("campaign"):
		var index := int(state.mission.mission_index)
		title = "%s — %s" % [Campaigns.get_campaign(state.mission.campaign).name, Campaigns.mission(state.mission.campaign, index).name]
	lines.append("[b]%s[/b]\n%s, %d regions. %s." % [title, map.display_name, map.province_order.size(), state.date_text()])
	lines.append("")
	for faction in state.turn_order:
		var regions := map.province_order.filter(func(r): return state.owners[r] == faction).size()
		var soldiers := 0
		for unit in state.units_of(faction):
			soldiers += unit.soldiers()
		var civ := Rules.civilization(state.factions[faction].civ)
		lines.append("[color=#%s]■[/color] [b]%s[/b]%s: %s" % [state.faction_color(faction).to_html(false), state.faction_name(faction),
			" (%s)" % civ.display_name if civ != null else "",
			"%d regions, %d soldiers" % [regions, soldiers] if state.factions[faction].alive else "[i]fallen[/i]"])
	var viewer: FactionState = state.factions.get(state.viewer())
	if viewer != null:
		lines.append("\n[b]Your treasury:[/b] %d gold, %+d a turn." % [roundi(viewer.resources.gold), roundi(Economy.deltas(state, state.viewer()).gold)])
	_popup.add_text("\n".join(lines), 17).custom_minimum_size = Vector2(560, 0)
	_popup.add_close()
	_dim.visible = true


## The mission's scripted notes not yet shown, as parchment notes at the top left (PRD H).
func _show_new_notes() -> void:
	for i in range(_notes_shown, state.mission_log.size()):
		_hud.note(state.mission_log[i].text)
	_notes_shown = state.mission_log.size()


## The mission's objectives, defeat conditions, crowns and notes so far (PRD H).
func open_objectives() -> void:
	if not Mission.is_mission(state):
		return
	_popup.open("Objectives")
	var mark := func(o): return "[color=#8fe08f]✓[/color]" if o.done else "[color=#c8b48a]•[/color]"
	var lines := PackedStringArray()
	lines.append("[b]Primary objective[/b]")
	for objective in Mission.primary(state):
		lines.append("%s %s" % [mark.call(objective), objective.text])
	var extra := Mission.additional(state)
	if not extra.is_empty():
		lines.append("\n[b]Additional objectives[/b]")
		for objective in extra:
			lines.append("%s %s  [i](%d points)[/i]" % [mark.call(objective), objective.text, objective.points])
	var defeats := Mission.defeats(state)
	if not defeats.is_empty():
		lines.append("\n[b]Defeat[/b]")
		for line in defeats:
			lines.append("[color=#f08070]✗[/color] %s" % line)
	var limits := Mission.crowns(state)
	if limits.size() == 3:
		lines.append("\n[b]Crowns[/b]  gold by turn %d, silver by %d, bronze by %d" % limits)
	if not state.mission_log.is_empty():
		lines.append("\n[b]Chronicle[/b]")
		for entry in state.mission_log:
			lines.append("[i]Turn %d:[/i] %s" % [int(entry.turn), entry.text])
	_popup.add_text("\n".join(lines), 17).custom_minimum_size = Vector2(620, 0)
	_popup.add_close()
	_dim.visible = true


## The "!" shield, as in S&T: selects the next of your armies with no
## orders yet and brings the camera to it; with none left, the turn's news.
func next_idle_army() -> void:
	if not _is_my_turn():
		open_alerts()
		return
	var idle: Array = state.units_of(state.viewer()).filter(func(u): return state.orders.get(u, []).is_empty())
	if idle.is_empty():
		open_alerts()
		return
	idle.sort_custom(func(a, b): return map.province_order.find(a.province) < map.province_order.find(b.province))
	var at := idle.find(selected_unit)
	var unit: Unit = idle[(at + 1) % idle.size()]
	select_unit(unit)
	create_tween().tween_property(_camera, "position", map.provinces[unit.province].centroid, 0.35) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


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
	for popup: Control in [_attack_popup, _recruit_window, _popup, _region_popup, _battle_report, _end_screen, _save_popup, _pause_menu]:
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
	LoadingScreen.open(get_tree(), scene_file_path)


func _play_again() -> void:
	_restart()


func _go_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


## The victory screen's "next": the next mission's briefing, where the Forge is.
func _next_mission() -> void:
	var session := get_node_or_null("/root/Session")
	if session != null and state.mission.has("campaign"):
		session.menu_target = {"briefing": [state.mission.campaign, int(state.mission.mission_index) + 1]}
	_go_to_menu()


func _on_build_requested(region: String, building: String) -> void:
	if Economy.start_building(state, region, building):
		_hud.toast("Construction started in %s: %s." % [map.region_name(region), Rules.building(building).display_name])
	_region_popup.show_province(state, region)
	_refresh_world()


# --- Tutorial ----------------------------------------------------------------------------------

func _start_tutorial() -> void:
	_tutorial = Tutorial.new(state.turn)
	_tutorial_box = TutorialBox.new()
	$UI.add_child(_tutorial_box)
	_tutorial_box.skip_pressed.connect(func():
		_tutorial.skip()
		_show_tutorial_step())
	_tutorial_box.leave_pressed.connect(_go_to_menu)
	# Look at the regions in play, shifted right so the hint box in the
	# lower-left corner doesn't hide them.
	var in_play := map.province_order.filter(func(r): return state.owners[r] != "neutral")
	var centre := Vector2.ZERO
	for region in in_play:
		centre += map.provinces[region].centroid
	_camera.zoom = Vector2.ONE * TUTORIAL_ZOOM
	_camera.position = centre / maxf(in_play.size(), 1) - Vector2((TutorialBox.WIDTH + 2.0 * TutorialBox.MARGIN) / 2.0 / TUTORIAL_ZOOM, 0)
	_show_tutorial_step()


func _show_tutorial_step() -> void:
	if _tutorial.finished():
		_tutorial_box.visible = false
		return
	_tutorial_box.show_step(_tutorial.current(), _tutorial.step, Tutorial.STEPS.size())


func _tutorial_record(kind: String) -> void:
	if _tutorial != null:
		_tutorial.record(kind)


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
		if not _placing.is_empty():
			view.reach = "move" if Economy.bundle_problem(state, region, _placing, state.current_faction()) == "" else "blocked"
	_decor.queue_redraw()
	_marks.queue_redraw()
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
			# A left press on one of your armies may become a drag that aims it.
			var unit := _tokens.unit_at(get_global_mouse_position())
			if event.button_index == MOUSE_BUTTON_LEFT and _placing.is_empty() and _is_my_turn() \
					and unit != null and unit.owner == state.current_faction():
				_aim_unit = unit
	elif event.button_index == _press_button:
		if _aiming:
			_release_aim(get_global_mouse_position())
		elif not _dragging:
			var point := get_global_mouse_position()
			if event.button_index == MOUSE_BUTTON_LEFT:
				_click(point)
			elif event.button_index == MOUSE_BUTTON_RIGHT and not _placing.is_empty():
				_cancel_placing()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				var region := map.province_at(point)
				var unit := _tokens.unit_at(point)
				if unit != null and unit.owner == state.current_faction() and _is_my_turn() and state.orders.has(unit):
					AudioManager.sfx("click")
					_cancel_order(unit)  # Right-click your unit: cancel all its orders.
				elif reach.has(region) and reach[region] != "blocked":
					order(region)
				else:
					clear_selection()
		_press_button = MOUSE_BUTTON_NONE
		_dragging = false
		_stop_aiming()


## Dragging from one of your armies aims it (PRD I); dragging anywhere else pans the map.
func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _press_button == MOUSE_BUTTON_NONE:
		return
	if not _dragging and not _aiming and event.position.distance_to(_press_position) > DRAG_THRESHOLD:
		if _aim_unit != null and _is_my_turn():
			_aiming = true
			if selected_unit != _aim_unit:
				AudioManager.sfx("select")
				select_unit(_aim_unit)
		else:
			_dragging = true
	if _aiming:
		_aim_at(get_global_mouse_position())
	elif _dragging:
		_camera.pan_by_screen(event.relative)


## The aiming arrow: onto a lit region it shows the order it would give,
## elsewhere it follows the pointer.
func _aim_at(point: Vector2) -> void:
	var region := map.province_at(point)
	var plan := Orders.intent(state, _aim_unit, region) if reach.get(region, "") in ["move", "attack"] else {}
	if not plan.is_empty():
		_orders.preview = {"from": plan.from, "to": region, "kind": plan.type}
	else:
		_orders.preview = {"from": _orders.anchor(_aim_unit.province), "to": point, "kind": "move"}
	_orders.queue_redraw()


## Letting go over a lit region gives the order, just as clicking it would.
func _release_aim(point: Vector2) -> void:
	var region := map.province_at(point)
	_stop_aiming()
	if selected_unit != null and region != "" and region != selected_unit.province and reach.has(region):
		order(region)


func _stop_aiming() -> void:
	if _aiming:
		_orders.preview = {}
		_orders.queue_redraw()
	_aim_unit = null
	_aiming = false


func _update_hover() -> void:
	var region := ""
	var mouse := get_viewport().get_mouse_position()
	var over_hint := _tutorial_box != null and _tutorial_box.visible and _tutorial_box.get_global_rect().has_point(mouse)
	if not _dragging and not _dim.visible and not _pass_screen.visible and not _hud.is_over_ui(mouse) and not over_hint:
		region = map.province_at(get_global_mouse_position())
	if region == hovered_id:
		return
	if hovered_id != "":
		_views[hovered_id].hovered = false
	hovered_id = region
	if region != "":
		_views[region].hovered = true
	if _aiming:
		return  # The aiming arrow is drawn by _aim_at().
	# Preview the arrow the selected unit would get.
	_orders.preview = {}
	if selected_unit != null and reach.get(region, "") in ["move", "attack"]:
		var plan := Orders.intent(state, selected_unit, region)
		if not plan.is_empty():
			_orders.preview = {"from": plan.from, "to": region, "kind": plan.type}
	_orders.queue_redraw()


func _zoom_anchor(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return event.position
	return get_viewport_rect().size / 2.0
