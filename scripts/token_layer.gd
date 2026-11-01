class_name TokenLayer
extends Node2D
## Draws every visible unit as a heraldic shield badge above its region
## (PRD UT-2, UT-3): the faction's colour with a gold border, the unit's icon,
## the soldier count on a ribbon, rank stars, a general's seal, and a health
## bar in a dark frame that drains smoothly. Badges keep the same size on
## screen at any zoom.
##
## What's drawn is a display model (one TokenVisual per unit) that normally
## follows the game state, so the animations can move, fade and drain tokens
## after the result is already decided.

const SCREEN_SIZE := 46.0  # Badge width on screen, in pixels, at any zoom.
const MIN_WORLD_SIZE := 24.0
const MAX_WORLD_SIZE := 70.0
const GOLD := Color("#d8b25a")
const GOLD_DARK := Color("#8a6420")
const INK := Color("#2b1d10")
const RIBBON := Color("#efe2bf")
const HP_DRAIN_PER_SECOND := 0.9  # Share of max HP the bar drains per second.

## How one unit is drawn right now.
class TokenVisual:
	extends RefCounted
	var unit: Unit
	var region := ""
	var owner := ""
	var hp := 0.0  # Shown HP; drains towards the unit's real HP.
	var alpha := 1.0
	var sink := 0.0  # 0 to 1 as a destroyed unit sinks away.
	var offset := Vector2.ZERO  # Extra offset from the badge's place (advance, recoil, bob).
	## A position on the map that replaces the badge's place while it marches; null when not marching.
	var position_override = null
	## Held by an animation: the shown HP doesn't drain on its own.
	var held := false

	func soldiers() -> int:
		return clampi(ceili(hp / unit.type().soldier_hp() - 0.0001), 0, UnitType.SOLDIERS)


var state: GameState
var selected: Array[Unit] = []
## Regions whose units the viewer can see; null shows everything.
var visible_provinces = null
## The camera's zoom, so badges keep their size on screen.
var view_zoom := 1.0

var visuals := {}  # Unit -> TokenVisual
## Visuals of destroyed units that are still fading out.
var ghosts: Array[TokenVisual] = []

var _rects := {}  # Unit -> Rect2 of its shield, from the last draw, for clicking.
var _icons := {}  # unit type id -> Texture2D
var _time := 0.0
var _count_font: Font
var _seal_font: Font


func _ready() -> void:
	z_index = 5
	var cinzel: FontFile = load("res://assets/fonts/Cinzel.ttf")
	var bold := FontVariation.new()
	bold.base_font = cinzel
	bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	_count_font = bold
	_seal_font = bold
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


## Brings the display model in line with the game state: new units appear,
## units stand in their regions, and units that are gone are dropped.
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


## Badge width in map units for the current zoom.
func token_size() -> float:
	return clampf(SCREEN_SIZE / maxf(view_zoom, 0.01), MIN_WORLD_SIZE, MAX_WORLD_SIZE)


func _shown(visual: TokenVisual) -> bool:
	return visible_provinces == null or visual.owner == state.viewer() or visible_provinces.has(visual.region)


## Where a unit's badge stands in its region's row, as the badge's centre.
func slot_position(unit: Unit) -> Vector2:
	var visual: TokenVisual = visuals.get(unit)
	if visual == null:
		return state.map.provinces[unit.province].centroid
	return _slot(visual)


func _slot(visual: TokenVisual) -> Vector2:
	var row: Array = visuals.values().filter(func(v: TokenVisual): return v.region == visual.region and v.position_override == null and _shown(v))
	var index := row.find(visual)
	if index < 0:
		index = 0
		row = [visual]
	var size := token_size()
	var centre: Vector2 = state.map.provinces[visual.region].centroid
	return centre + Vector2((index - (row.size() - 1) / 2.0) * size * 1.12, -size * 0.95)


## The badge's centre on the map right now, including any animation.
func badge_position(visual: TokenVisual) -> Vector2:
	var base: Vector2 = visual.position_override if visual.position_override != null else _slot(visual)
	return base + visual.offset + Vector2(0, visual.sink * token_size() * 0.6)


## The unit whose badge is under `point` (map coordinates), or null.
func unit_at(point: Vector2) -> Unit:
	for unit in _rects:
		if _rects[unit].grow(2.0).has_point(point):
			return unit
	return null


func _draw() -> void:
	_rects.clear()
	var size := token_size()
	var castle := _icon("castle")
	for region in state.map.province_order:
		var walls := Sieges.walls(state, region)
		if walls > 0 and castle != null:
			# A castle behind the badges; bigger for stronger walls.
			var castle_size := size * (1.5 + 0.35 * walls)
			var at: Vector2 = state.map.provinces[region].centroid + Vector2(0, -size * 0.95)
			draw_texture_rect(castle, Rect2(at - Vector2(castle_size, castle_size) / 2.0, Vector2(castle_size, castle_size)),
				false, Color(INK, 0.45))
	var drawn: Array[TokenVisual] = []
	for visual: TokenVisual in visuals.values():
		if _shown(visual):
			drawn.append(visual)
	drawn.append_array(ghosts)
	drawn.sort_custom(func(a: TokenVisual, b: TokenVisual): return badge_position(a).y < badge_position(b).y)
	for visual in drawn:
		var centre := badge_position(visual)
		_draw_badge(visual, centre, size)
		if visual.alpha > 0.5 and state.units.has(visual.unit):
			_rects[visual.unit] = Rect2(centre - Vector2(size, size * 1.2) / 2.0, Vector2(size, size * 1.2))


## A heater shield, its top edge `size` wide, centred on `centre`.
func _shield_points(centre: Vector2, size: float) -> PackedVector2Array:
	var w := size / 2.0
	var h := size * 1.15
	var top := centre.y - h / 2.0
	var points := PackedVector2Array()
	points.append(Vector2(centre.x - w, top))
	points.append(Vector2(centre.x + w, top))
	var shoulder := top + h * 0.42
	var tip := Vector2(centre.x, top + h)
	for i in range(0, 13):
		var t := i / 12.0
		# Right side: straight down, then a curve to the tip.
		var a := Vector2(centre.x + w, shoulder)
		var c := Vector2(centre.x + w, shoulder + h * 0.38)
		points.append(a.lerp(c, t).lerp(c.lerp(tip, t), t))
	for i in range(1, 13):
		var t := i / 12.0
		var a := tip
		var c := Vector2(centre.x - w, shoulder + h * 0.38)
		var b := Vector2(centre.x - w, shoulder)
		points.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return points


func _draw_badge(visual: TokenVisual, centre: Vector2, size: float) -> void:
	var unit := visual.unit
	var unit_type := unit.type()
	var alpha := visual.alpha
	var spent := state.units.has(unit) and unit.owner == state.current_faction() and (unit.attacked or unit.move_points_left == 0) \
		and not (unit.coastal_moves > 0)
	var base := state.faction_color(visual.owner)
	if spent:
		base = base.lerp(Color(0.45, 0.42, 0.38), 0.55)
	var shield := _shield_points(centre, size)

	# Selection: a pulsing gold ring behind the badge.
	if selected.has(unit):
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		var ring := size * (0.66 + 0.05 * pulse)
		draw_circle(centre + Vector2(0, size * 0.05), ring, Color(GOLD, (0.12 + 0.18 * pulse) * alpha))
		draw_arc(centre + Vector2(0, size * 0.05), ring, 0.0, TAU, 40, Color(GOLD.lightened(0.3), (0.6 + 0.4 * pulse) * alpha), maxf(size * 0.05, 1.5), true)

	# Drop shadow, field with a light-to-dark wash, gold border.
	var shadow := PackedVector2Array()
	for p in shield:
		shadow.append(p + Vector2(size * 0.05, size * 0.07))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.35 * alpha))
	var colors := PackedColorArray()
	var top := shield[0].y
	for p in shield:
		var t := (p.y - top) / (size * 1.15)
		colors.append(Color(base.lightened(0.18).lerp(base.darkened(0.3), t), alpha))
	draw_polygon(shield, colors)
	var closed := shield.duplicate()
	closed.append(shield[0])
	draw_polyline(closed, Color(INK, alpha), size * 0.11, true)
	draw_polyline(closed, Color(GOLD, alpha), size * 0.065, true)

	# The unit's icon.
	var icon := _icon(unit.type_id)
	if icon != null:
		var icon_size := size * 0.62
		var icon_rect := Rect2(centre - Vector2(icon_size, icon_size * 1.05) / 2.0, Vector2(icon_size, icon_size))
		draw_texture_rect(icon, Rect2(icon_rect.position + Vector2(1, 1.5) * size * 0.03, icon_rect.size), false, Color(0, 0, 0, 0.45 * alpha))
		draw_texture_rect(icon, icon_rect, false, Color(1, 1, 1, alpha) if not spent else Color(0.85, 0.82, 0.76, alpha))

	# A civilization's special unit: a small gold lozenge in the corner.
	if unit_type.civilization != "":
		var corner := shield[1] + Vector2(-size * 0.17, size * 0.17)
		var r := size * 0.08
		draw_colored_polygon(PackedVector2Array([corner + Vector2(0, -r), corner + Vector2(r, 0), corner + Vector2(0, r), corner + Vector2(-r, 0)]), Color(GOLD, alpha))

	# The soldier count on a ribbon across the foot of the shield.
	var ribbon_centre := centre + Vector2(0, size * 0.42)
	var rw := size * 0.46
	var rh := size * 0.17
	var notch := size * 0.08
	var ribbon := PackedVector2Array([
		ribbon_centre + Vector2(-rw - notch * 1.6, -rh), ribbon_centre + Vector2(rw + notch * 1.6, -rh),
		ribbon_centre + Vector2(rw + notch * 0.6, 0), ribbon_centre + Vector2(rw + notch * 1.6, rh),
		ribbon_centre + Vector2(-rw - notch * 1.6, rh), ribbon_centre + Vector2(-rw - notch * 0.6, 0)])
	draw_colored_polygon(ribbon, Color(RIBBON, alpha))
	var ribbon_line := ribbon.duplicate()
	ribbon_line.append(ribbon[0])
	draw_polyline(ribbon_line, Color(INK, alpha), maxf(size * 0.03, 1.0), true)
	var font_size := int(size * 0.3)
	var count := str(visual.soldiers())
	draw_string(_count_font, ribbon_centre + Vector2(-size, font_size * 0.36), count, HORIZONTAL_ALIGNMENT_CENTER, size * 2.0, font_size, Color(INK, alpha))

	# Rank stars centred along the top, a general's wax seal on the top-left corner.
	for i in unit.rank():
		_draw_star(Vector2(centre.x + (i - (unit.rank() - 1) / 2.0) * size * 0.22, shield[0].y - size * 0.02), size * 0.1, Color(GOLD.lightened(0.2), alpha))
	if unit.general != null:
		var seal := shield[0] + Vector2(size * 0.04, size * 0.02)
		draw_circle(seal, size * 0.17, Color(INK, alpha))
		draw_circle(seal, size * 0.14, Color("#9b2d20", alpha))
		draw_string(_seal_font, seal + Vector2(-size * 0.2, size * 0.07), "G", HORIZONTAL_ALIGNMENT_CENTER, size * 0.4, int(size * 0.2), Color(GOLD.lightened(0.3), alpha))

	# Health bar in a dark frame under the badge.
	var bar := Rect2(centre + Vector2(-size * 0.5, size * 0.66), Vector2(size, size * 0.13))
	draw_rect(bar.grow(size * 0.025), Color(INK, alpha))
	draw_rect(bar, Color(0.18, 0.12, 0.08, alpha))
	var health := clampf(visual.hp / unit.max_hp(), 0.0, 1.0)
	var fill := Color("#b8382a").lerp(Color("#d8b030"), clampf(health * 2.0, 0.0, 1.0)) if health < 0.5 \
		else Color("#d8b030").lerp(Color("#4f9a3a"), (health - 0.5) * 2.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * health, bar.size.y)), Color(fill, alpha))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * health, bar.size.y * 0.35)), Color(1, 1, 1, 0.2 * alpha))


func _icon(type_id: String) -> Texture2D:
	if not _icons.has(type_id):
		var path := "res://assets/icons/%s.svg" % type_id
		_icons[type_id] = load(path) if ResourceLoader.exists(path) else null
	return _icons[type_id]


func _draw_star(at: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var r := radius if i % 2 == 0 else radius * 0.45
		points.append(at + Vector2.from_angle(-PI / 2 + i * PI / 5) * r)
	draw_colored_polygon(points, Color(INK, color.a))
	var inner := PackedVector2Array()
	for p in points:
		inner.append(at + (p - at) * 0.75)
	draw_colored_polygon(inner, color)
