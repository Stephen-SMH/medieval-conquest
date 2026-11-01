class_name TokenLayer
extends Node2D
## Draws each unit as a small group of standing figures on its region
## (PRD UT-2): one to three figures depending on its soldiers, the faction's
## banner on a pole behind them (with a light-blue pennant for a general), gold
## chevrons for rank, a thin health bar with a white tip, the soldier number in
## italic, and a red X once the unit has no moves left this turn.
##
## What's drawn is a display model (one TokenVisual per unit) that normally
## follows the game state, so the animations can march, fade and drain units
## after the turn's result is already decided.

const SCREEN_HEIGHT := 58.0  # Figure height on screen, in pixels, at any zoom.
const MIN_WORLD := 30.0
const MAX_WORLD := 84.0
const GOLD := Color("#e2bd5a")
const INK := Color("#1d130a")
const HP_DRAIN_PER_SECOND := 0.9
const FIGURES := {
	"militia": "farmer", "spearmen": "pikeman", "swordsmen": "swordman", "archers": "bowman",
	"crossbowmen": "archer", "light_cavalry": "cavalry", "heavy_cavalry": "mounted-knight", "catapult": "catapult",
	"berserker": "barbarian", "huscarl": "barbarian", "longbowman": "bowman", "yeoman": "pikeman",
	"knight": "mounted-knight", "sergeant": "pikeman", "cataphract": "mounted-knight", "varangian_guard": "guards",
	"mamluk": "horse-archer", "ghazi": "swordman",
}
## Painted tones for the figures by kind of unit; the faction's colour tints them.
const TONES := {"infantry": Color("#e6e1d4"), "ranged": Color("#e8d6a8"), "cavalry": Color("#e0d2bb"), "siege": Color("#c9a77a")}

## How one unit is drawn right now.
class TokenVisual:
	extends RefCounted
	var unit: Unit
	var region := ""
	var owner := ""
	var hp := 0.0  # Shown HP; drains towards the unit's real HP.
	var alpha := 1.0
	var sink := 0.0  # 0 to 1 as a destroyed unit sinks away.
	var offset := Vector2.ZERO  # Extra offset (advance, recoil, bob).
	## A map position that replaces the unit's place while it marches; null when not marching.
	var position_override = null
	## Held by an animation: the shown HP doesn't drain on its own.
	var held := false

	func soldiers() -> int:
		return clampi(ceili(hp / unit.type().soldier_hp() - 0.0001), 0, UnitType.SOLDIERS)


var state: GameState
var selected: Array[Unit] = []
## Regions whose units the viewer can see; null shows everything.
var visible_provinces = null
var view_zoom := 1.0

var visuals := {}  # Unit -> TokenVisual
## Visuals of destroyed units that are still fading out.
var ghosts: Array[TokenVisual] = []

var _rects := {}
var _figures := {}
var _time := 0.0
var _number_font: Font


func _ready() -> void:
	z_index = 6
	_number_font = load("res://assets/fonts/IMFellEnglish-Italic.ttf")
	sync()


func _process(delta: float) -> void:
	_time += delta
	var changed := not selected.is_empty()
	for visual: TokenVisual in visuals.values():
		if visual.held or not state.units.has(visual.unit):
			continue
		if not is_equal_approx(visual.hp, visual.unit.hp):
			visual.hp = move_toward(visual.hp, visual.unit.hp, visual.unit.max_hp() * HP_DRAIN_PER_SECOND * delta)
			changed = true
	if changed or not ghosts.is_empty():
		queue_redraw()


## Brings the display model in line with the game state.
func sync(snap_hp := false) -> void:
	for unit in state.units:
		var visual: TokenVisual = visuals.get(unit)
		if visual == null:
			visual = TokenVisual.new()
			visual.unit = unit
			visual.hp = unit.hp
			visuals[unit] = visual
		visual.region = unit.province
		visual.owner = unit.owner
		visual.offset = Vector2.ZERO
		visual.position_override = null
		visual.alpha = 1.0
		visual.sink = 0.0
		visual.held = false
		if snap_hp:
			visual.hp = unit.hp
	for unit in visuals.keys():
		if not state.units.has(unit):
			visuals.erase(unit)
	queue_redraw()


func visual_for(unit: Unit) -> TokenVisual:
	return visuals.get(unit)


## Figure height in map units for the current zoom.
func token_size() -> float:
	return clampf(SCREEN_HEIGHT / maxf(view_zoom, 0.01), MIN_WORLD, MAX_WORLD)


func _shown(visual: TokenVisual) -> bool:
	return visible_provinces == null or visual.owner == state.viewer() or visible_provinces.has(visual.region)


## Where a unit stands in a region: just above the region's name.
func region_anchor(region: String) -> Vector2:
	return state.map.provinces[region].centroid + Vector2(0, -token_size() * 0.88)


## The centre of a unit's figures on the map right now, including any animation.
func badge_position(visual: TokenVisual) -> Vector2:
	var base: Vector2 = visual.position_override if visual.position_override != null else region_anchor(visual.region)
	return base + visual.offset + Vector2(0, visual.sink * token_size() * 0.5)


func slot_position(unit: Unit) -> Vector2:
	var visual: TokenVisual = visuals.get(unit)
	return badge_position(visual) if visual != null else region_anchor(unit.province)


## The unit whose figures are under `point` (map coordinates), or null.
func unit_at(point: Vector2) -> Unit:
	for unit in _rects:
		if _rects[unit].has_point(point):
			return unit
	return null


func _draw() -> void:
	_rects.clear()
	var size := token_size()
	var drawn: Array[TokenVisual] = []
	for visual: TokenVisual in visuals.values():
		if _shown(visual):
			drawn.append(visual)
	drawn.append_array(ghosts)
	drawn.sort_custom(func(a: TokenVisual, b: TokenVisual): return badge_position(a).y < badge_position(b).y)
	for visual in drawn:
		var centre := badge_position(visual)
		_draw_unit(visual, centre, size)
		if visual.alpha > 0.5 and state.units.has(visual.unit):
			_rects[visual.unit] = Rect2(centre - Vector2(size * 0.75, size * 0.85), Vector2(size * 1.5, size * 1.5))


func _draw_unit(visual: TokenVisual, centre: Vector2, size: float) -> void:
	var unit := visual.unit
	var unit_type := unit.type()
	var alpha := visual.alpha
	var faction_color := state.faction_color(visual.owner)
	var foot := centre + Vector2(0, size * 0.45)

	# Selection: a pulsing gold ring on the ground.
	if selected.has(unit):
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		_draw_ellipse(foot, Vector2(size * (0.8 + 0.06 * pulse), size * 0.26), Color(GOLD, (0.25 + 0.25 * pulse) * alpha))
		_draw_ellipse_outline(foot, Vector2(size * (0.8 + 0.06 * pulse), size * 0.26), Color(GOLD.lightened(0.3), 0.9 * alpha), maxf(size * 0.05, 1.5))
	_draw_ellipse(foot, Vector2(size * 0.62, size * 0.17), Color(0, 0, 0, 0.32 * alpha))

	# The faction's banner on a pole behind the figures.
	var pole_foot := centre + Vector2(size * 0.42, size * 0.35)
	var pole_top := pole_foot + Vector2(0, -size * 1.25)
	draw_line(pole_foot, pole_top, Color("#3a2410", alpha), maxf(size * 0.04, 1.2))
	draw_circle(pole_top, size * 0.035, Color(GOLD, alpha))
	var flag := PackedVector2Array([pole_top + Vector2(0, size * 0.05), pole_top + Vector2(size * 0.3, size * 0.05),
		pole_top + Vector2(size * 0.3, size * 0.48), pole_top + Vector2(size * 0.15, size * 0.38), pole_top + Vector2(0, size * 0.48)])
	draw_colored_polygon(flag, Color(faction_color, alpha))
	var flag_line := flag.duplicate()
	flag_line.append(flag[0])
	draw_polyline(flag_line, Color(INK, 0.7 * alpha), maxf(size * 0.025, 1.0), true)
	_draw_emblem(state.factions[visual.owner].civ if state.factions.has(visual.owner) else "", pole_top + Vector2(size * 0.15, size * 0.22), size * 0.08, Color(1, 1, 1, 0.9 * alpha))
	if unit.general != null:
		var pennant_top := centre + Vector2(-size * 0.45, -size * 0.85)
		draw_line(pennant_top + Vector2(0, size * 1.2), pennant_top, Color("#3a2410", alpha), maxf(size * 0.035, 1.0))
		draw_colored_polygon(PackedVector2Array([pennant_top, pennant_top + Vector2(-size * 0.36, size * 0.07), pennant_top + Vector2(0, size * 0.16)]),
			Color("#9cc8ec", alpha))

	# The figures: one to three, depending on the soldiers left.
	var count := 1 if visual.soldiers() <= 6 else (2 if visual.soldiers() <= 13 else 3)
	var spots: Array = [[Vector2(0, 0)], [Vector2(-0.24, -0.04), Vector2(0.2, 0.04)],
		[Vector2(-0.34, -0.06), Vector2(0.32, -0.06), Vector2(-0.02, 0.06)]][count - 1]
	var texture := _figure(unit.type_id)
	var tone: Color = TONES.get(unit_type.unit_class, Color.WHITE).lerp(faction_color, 0.28)
	var figure_size := size * (0.85 if unit_type.is_cavalry() or unit_type.unit_class == "siege" else 0.78)
	for spot: Vector2 in spots:
		var rect := Rect2(centre + spot * size - Vector2(figure_size, figure_size) / 2.0, Vector2(figure_size, figure_size))
		var o := maxf(size * 0.025, 1.0)
		for shift in [Vector2(o, 0), Vector2(-o, 0), Vector2(0, o), Vector2(0, -o)]:
			draw_texture_rect(texture, Rect2(rect.position + shift, rect.size), false, Color(INK, 0.9 * alpha))
		draw_texture_rect(texture, rect, false, Color(tone, alpha))

	# Rank chevrons beside the figures.
	for i in unit.rank():
		var c := centre + Vector2(size * 0.62, -size * 0.25 + i * size * 0.14)
		var w := size * 0.12
		draw_polyline(PackedVector2Array([c + Vector2(-w, w * 0.7), c, c + Vector2(w, w * 0.7)]), Color(INK, alpha), maxf(size * 0.07, 2.2), true)
		draw_polyline(PackedVector2Array([c + Vector2(-w, w * 0.7), c, c + Vector2(w, w * 0.7)]), Color(GOLD, alpha), maxf(size * 0.045, 1.4), true)

	# A thin health bar with a white tip, the soldiers under it, and a red X when spent.
	var bar := Rect2(foot + Vector2(-size * 0.4, size * 0.14), Vector2(size * 0.8, maxf(size * 0.055, 2.5)))
	draw_rect(bar.grow(1.0), Color(INK, 0.85 * alpha))
	var health := clampf(visual.hp / unit.max_hp(), 0.0, 1.0)
	var fill := Color("#c8402c").lerp(Color("#e0c040"), clampf(health * 2.0, 0.0, 1.0)) if health < 0.5 \
		else Color("#e0c040").lerp(Color("#6ac74a"), (health - 0.5) * 2.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * health, bar.size.y)), Color(fill, alpha))
	if health > 0.02:
		draw_rect(Rect2(bar.position + Vector2(bar.size.x * health - 2.0, 0), Vector2(2.0, bar.size.y)), Color(1, 1, 1, alpha))
	var number_size := int(maxf(size * 0.3, 11.0))
	var number_at := Vector2(bar.position.x, bar.end.y + number_size * 0.95)
	draw_string_outline(_number_font, number_at, str(visual.soldiers()), HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, number_size, 4, Color(INK, 0.9 * alpha))
	draw_string(_number_font, number_at, str(visual.soldiers()), HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, number_size, Color(1, 1, 1, alpha))
	if _spent(unit):
		var x_centre := bar.position + Vector2(-size * 0.14, bar.size.y / 2.0)
		var r := size * 0.09
		for d in [Vector2(r, r), Vector2(r, -r)]:
			draw_line(x_centre - d, x_centre + d, Color(INK, alpha), maxf(size * 0.075, 2.5))
			draw_line(x_centre - d, x_centre + d, Color("#e0301e", alpha), maxf(size * 0.05, 1.8))


## The viewer's unit has used every move it can this turn.
func _spent(unit: Unit) -> bool:
	return state.units.has(unit) and unit.owner == state.viewer() and unit.owner == state.current_faction() \
		and Orders.next_step_index(state, unit) < 0


func _figure(type_id: String) -> Texture2D:
	if not _figures.has(type_id):
		_figures[type_id] = load("res://assets/figures/%s.svg" % FIGURES.get(type_id, "pikeman"))
	return _figures[type_id]


## A simple heraldic charge per civilization on the banner.
func _draw_emblem(civ: String, at: Vector2, r: float, color: Color) -> void:
	match civ:
		"norse":
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r * 0.9, r), at + Vector2(-r * 0.9, r)]), color)
		"anglish":
			draw_line(at + Vector2(-r, 0), at + Vector2(r, 0), color, r * 0.45)
			draw_line(at + Vector2(0, -r), at + Vector2(0, r), color, r * 0.45)
		"frankish":
			for i in 3:
				draw_circle(at + Vector2.from_angle(-PI / 2 + i * TAU / 3) * r * 0.6, r * 0.35, color)
		"byzantine":
			draw_arc(at, r * 0.8, 0.0, TAU, 16, color, r * 0.35)
		"saracen":
			draw_arc(at + Vector2(-r * 0.2, 0), r * 0.85, PI * 0.35, PI * 1.65, 16, color, r * 0.4)
		_:
			draw_circle(at, r * 0.6, color)


func _draw_ellipse(centre: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 24:
		points.append(centre + Vector2(cos(i * TAU / 24) * radii.x, sin(i * TAU / 24) * radii.y))
	draw_colored_polygon(points, color)


func _draw_ellipse_outline(centre: Vector2, radii: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in 25:
		points.append(centre + Vector2(cos(i * TAU / 24) * radii.x, sin(i * TAU / 24) * radii.y))
	draw_polyline(points, color, width, true)
