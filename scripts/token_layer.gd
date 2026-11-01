class_name TokenLayer
extends Node2D
## Draws each unit as a small group of painted figures on its region
## (PRD UT-2): three to five soldiers (two or three riders, one or two
## engines) depending on its soldiers, in the faction's colours, the faction's
## banner on a pole behind them (with a light-blue pennant for a general), gold
## chevrons for rank, a thin health bar with a white tip, the soldier number in
## italic, a red X once every soldier has an order (and no detachment can take
## another step), and while only some of them have orders, a small shield with
## how many are left at home.
##
## What's drawn is a display model (one TokenVisual per unit) that normally
## follows the game state, so the animations can march, fade and drain units
## after the turn's result is already decided.

const SCREEN_HEIGHT := 64.0  # Token height on screen, in pixels, at any zoom.
const MIN_WORLD := 42.0
const MAX_WORLD := 90.0
const GOLD := Color("#e2bd5a")
const INK := Color("#1d130a")
const HP_DRAIN_PER_SECOND := 0.9
## The painted figures (tools/render_figures.gd): a sprite per unit type, plus a
## grey layer of the parts that take the faction colour. In a sprite the ground
## is FIGURE_FEET down and a standing man is FIGURE_MAN of its height.
const FIGURE_FEET := 0.80
const FIGURE_MAN := 0.6
## Where the figures of a group stand, by count, as offsets from the group's
## foot point in token sizes; drawn back to front.
const INFANTRY_SPOTS := {
	3: [Vector2(-0.3, -0.08), Vector2(0.24, -0.08), Vector2(-0.03, 0.05)],
	4: [Vector2(-0.34, -0.09), Vector2(0.08, -0.11), Vector2(-0.16, 0.05), Vector2(0.27, 0.04)],
	5: [Vector2(-0.42, -0.1), Vector2(-0.03, -0.12), Vector2(0.36, -0.1), Vector2(-0.23, 0.05), Vector2(0.18, 0.05)],
}
const MOUNTED_SPOTS := {
	2: [Vector2(-0.26, -0.08), Vector2(0.2, 0.05)],
	3: [Vector2(-0.4, -0.1), Vector2(0.3, -0.09), Vector2(-0.05, 0.06)],
}
const SIEGE_SPOTS := {
	1: [Vector2(0.0, 0.0)],
	2: [Vector2(-0.24, -0.07), Vector2(0.2, 0.04)],
}

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
	## Held by an animation: the shown HP doesn't drain on its own and the
	## shown rank stays the one from before the turn.
	var held := false
	var rank := 0

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
var _team_layers := {}
var _time := 0.0
var _number_font: Font


func _ready() -> void:
	z_index = 6
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_number_font = load("res://assets/fonts/IMFellEnglish-Italic.ttf")
	sync()


func _process(delta: float) -> void:
	_time += delta
	var changed := not selected.is_empty()
	for visual: TokenVisual in visuals.values():
		if visual.held or not state.units.has(visual.unit):
			continue
		if visual.rank != visual.unit.rank():
			visual.rank = visual.unit.rank()
			changed = true
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
		visual.rank = unit.rank()
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
	return TokenLayer.layout(state.map.provinces[region].centroid, token_size()).centre


## The token stacked above a region's name: the figures, then the health bar,
## then the soldier number, whose bottom stays clear of the name (MapDecor).
## Everything is relative to the region's centroid, for a token `size` high.
static func layout(centroid: Vector2, size: float) -> Dictionary:
	var number_size := int(maxf(size * 0.3, 11.0))
	var label_top := MapDecor.label_rect(centroid).position.y
	var baseline := label_top - 3.0 - number_size * 0.2
	var bar_height := maxf(size * 0.055, 2.5)
	var bar_top := baseline - number_size * 0.95 - bar_height
	var foot := Vector2(centroid.x, bar_top - size * 0.12)
	return {
		"centre": foot - Vector2(0, size * 0.45),
		"foot": foot,
		"bar": Rect2(Vector2(centroid.x - size * 0.4, bar_top), Vector2(size * 0.8, bar_height)),
		"number_size": number_size,
		"baseline": baseline,
		"number_rect": Rect2(Vector2(centroid.x - size * 0.4, baseline - number_size * 0.8), Vector2(size * 0.8, number_size * 0.8 + number_size * 0.2)),
	}


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
	var alpha := visual.alpha
	var faction_color := state.faction_color(visual.owner)
	var foot := centre + Vector2(0, size * 0.45)

	# Selection: a pulsing gold ring on the ground.
	if selected.has(unit):
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		_draw_ellipse(foot, Vector2(size * (0.8 + 0.06 * pulse), size * 0.26), Color(GOLD, (0.25 + 0.25 * pulse) * alpha))
		_draw_ellipse_outline(foot, Vector2(size * (0.8 + 0.06 * pulse), size * 0.26), Color(GOLD.lightened(0.3), 0.9 * alpha), maxf(size * 0.05, 1.5))
	_draw_ellipse(foot, Vector2(size * 0.6, size * 0.15), Color(0, 0, 0, 0.26 * alpha))

	# The faction's banner on a pole behind the figures.
	var civ: String = state.factions[visual.owner].civ if state.factions.has(visual.owner) else ""
	var pole_foot := foot + Vector2(size * 0.4, -size * 0.1)
	draw_banner(self, pole_foot, size * 1.3, faction_color, civ, alpha)
	if unit.general != null:
		var pennant_top := foot + Vector2(-size * 0.5, -size * 1.25)
		draw_line(pennant_top + Vector2(0, size * 1.15), pennant_top, Color("#3a2410", alpha), maxf(size * 0.035, 1.0))
		draw_colored_polygon(PackedVector2Array([pennant_top, pennant_top + Vector2(-size * 0.36, size * 0.07), pennant_top + Vector2(0, size * 0.16)]),
			Color("#9cc8ec", alpha))

	# The painted figures: three to five soldiers, two or three riders, one or two engines.
	# Each figure gets its own pose variant, a slightly different size, place
	# and shade, so a group doesn't look like a row of copies.
	var spots: Array = figure_spots(unit.type(), visual.soldiers())
	var variants := variant_count(unit.type_id)
	var sprite := size * 0.68 / FIGURE_MAN  # A standing man is 0.68 token sizes tall.
	var team_color := faction_color.lightened(0.12)
	var o := maxf(size * 0.012, 0.6)
	for i in spots.size():
		var look := figure_look(unit.get_instance_id(), i, variants)
		var textures := _figure(unit.type_id, look.variant)
		var feet: Vector2 = foot + (spots[i] + look.offset) * size
		var shown: float = sprite * look.scale
		var rect := Rect2(feet - Vector2(shown * 0.5, shown * FIGURE_FEET), Vector2(shown, shown))
		for shift in [Vector2(o, 0), Vector2(-o, 0), Vector2(0, o), Vector2(0, -o)]:
			draw_texture_rect(textures[0], Rect2(rect.position + shift, rect.size), false, Color(INK, 0.3 * alpha))
		var shade: float = look.shade
		draw_texture_rect(textures[0], rect, false, Color(shade, shade, shade * 0.98, alpha))
		if textures[1] != null:
			draw_texture_rect(textures[1], rect, false, Color(team_color.r * shade, team_color.g * shade, team_color.b * shade, alpha))

	# Rank chevrons beside the figures (the rank from before the turn while it plays out).
	for i in visual.rank:
		var c := foot + Vector2(-size * 0.62, -size * 0.62 + i * size * 0.14)
		var w := size * 0.12
		draw_polyline(PackedVector2Array([c + Vector2(-w, w * 0.7), c, c + Vector2(w, w * 0.7)]), Color(INK, alpha), maxf(size * 0.07, 2.2), true)
		draw_polyline(PackedVector2Array([c + Vector2(-w, w * 0.7), c, c + Vector2(w, w * 0.7)]), Color(GOLD, alpha), maxf(size * 0.045, 1.4), true)

	# A thin health bar with a white tip, the soldiers under it, and a red X when spent.
	var bar := Rect2(foot + Vector2(-size * 0.4, size * 0.12), Vector2(size * 0.8, maxf(size * 0.055, 2.5)))
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
	elif _planning(unit) and state.orders.has(unit) and Orders.unassigned(state, unit) > 0:
		_draw_home_badge(bar.position + Vector2(-size * 0.2, bar.size.y / 2.0), Orders.unassigned(state, unit), size, alpha)


## Soldiers of a partly ordered unit still at home: a small parchment shield with the number.
func _draw_home_badge(at: Vector2, count: int, size: float, alpha: float) -> void:
	var r := size * 0.17
	var shield := PackedVector2Array([at + Vector2(-r, -r), at + Vector2(r, -r), at + Vector2(r, r * 0.25), at + Vector2(0, r * 1.15),
		at + Vector2(-r, r * 0.25)])
	var ring := shield.duplicate()
	ring.append(shield[0])
	draw_colored_polygon(shield, Color("#f1e3bd", alpha))
	draw_polyline(ring, Color(INK, 0.9 * alpha), maxf(size * 0.035, 1.4), true)
	var font_size := int(maxf(size * 0.24, 10.0))
	draw_string(_number_font, at + Vector2(-r, font_size * 0.3), str(count), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, font_size, Color(INK, alpha))


## Where the figures of a unit stand: more figures as it has more soldiers.
static func figure_spots(unit_type: UnitType, soldiers: int) -> Array:
	if unit_type.unit_class == "siege":
		return SIEGE_SPOTS[1 if soldiers <= 10 else 2]
	if unit_type.is_cavalry():
		return MOUNTED_SPOTS[2 if soldiers <= 10 else 3]
	return INFANTRY_SPOTS[3 if soldiers <= 7 else (4 if soldiers <= 14 else 5)]


## A faction banner on a pole: a hanging cloth with a swallowtail, a gold
## finial and the civilization's charge.
static func draw_banner(canvas: CanvasItem, pole_foot: Vector2, height: float, color: Color, civ: String, alpha := 1.0) -> void:
	var size := height / 1.3
	var pole_top := pole_foot + Vector2(0, -height)
	canvas.draw_line(pole_foot, pole_top, Color("#3a2410", alpha), maxf(size * 0.04, 1.2))
	canvas.draw_line(pole_top + Vector2(-size * 0.04, size * 0.05), pole_top + Vector2(size * 0.34, size * 0.05), Color("#3a2410", alpha), maxf(size * 0.03, 1.0))
	canvas.draw_circle(pole_top, size * 0.04, Color(GOLD, alpha))
	var top := pole_top + Vector2(0, size * 0.06)
	var flag := PackedVector2Array([top, top + Vector2(size * 0.3, 0), top + Vector2(size * 0.3, size * 0.5),
		top + Vector2(size * 0.15, size * 0.4), top + Vector2(0, size * 0.5)])
	var shades := PackedColorArray([color.lightened(0.15), color, color.darkened(0.25), color.darkened(0.1), color.darkened(0.2)])
	for i in shades.size():
		shades[i].a = alpha
	canvas.draw_polygon(flag, shades)
	var flag_line := flag.duplicate()
	flag_line.append(flag[0])
	canvas.draw_polyline(flag_line, Color(INK, 0.7 * alpha), maxf(size * 0.025, 1.0), true)
	draw_emblem(canvas, civ, top + Vector2(size * 0.15, size * 0.2), size * 0.085, Color(1, 0.95, 0.8, 0.92 * alpha))


## The viewer's unit, while its owner plans.
func _planning(unit: Unit) -> bool:
	return state.units.has(unit) and unit.owner == state.viewer() and unit.owner == state.current_faction()


## The viewer's unit has used every soldier and step it can this turn.
func _spent(unit: Unit) -> bool:
	return _planning(unit) and Orders.is_spent(state, unit)


## The painted figure of a unit type (one of its pose variants) and its faction-colour layer.
func _figure(type_id: String, variant := 0) -> Array:
	var key := "%s/%d" % [type_id, variant]
	if not _figures.has(key):
		_figures[key] = figure_textures(type_id, variant)
	return _figures[key]


const MAX_VARIANTS := 3
static var _variant_counts := {}


## How many pose variants a unit type has been rendered in (1 if only the base figure).
static func variant_count(type_id: String) -> int:
	if not _variant_counts.has(type_id):
		var count := 1
		while count < MAX_VARIANTS and ResourceLoader.exists("res://assets/figures/%s_v%d.png" % [type_id, count]):
			count += 1
		_variant_counts[type_id] = count
	return _variant_counts[type_id]


## How the `index`th figure of a unit looks: its pose variant (neighbours in a
## group never share one while there are enough), a size within 8% either
## way, a small nudge from its spot (in token sizes) and a shade. The same
## unit always looks the same.
static func figure_look(unit_seed: int, index: int, variants: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([unit_seed, index])
	var first := posmod(hash(unit_seed), maxi(variants, 1))
	return {
		"variant": posmod(first + index, maxi(variants, 1)),
		"scale": rng.randf_range(0.92, 1.08),
		"offset": Vector2(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.02, 0.02)),
		"shade": rng.randf_range(0.9, 1.04),
	}


static var _bounds := {}


## The part of a figure's sprite that isn't transparent, in pixels.
static func figure_bounds(type_id: String) -> Rect2:
	if not _bounds.has(type_id):
		var image: Image = figure_textures(type_id)[0].get_image()
		_bounds[type_id] = Rect2(image.get_used_rect()) if image != null else Rect2(0, 0, 1, 1)
	return _bounds[type_id]


static func figure_textures(type_id: String, variant := 0) -> Array:
	var path := "res://assets/figures/%s.png" % type_id
	if variant > 0 and ResourceLoader.exists("res://assets/figures/%s_v%d.png" % [type_id, variant]):
		path = "res://assets/figures/%s_v%d.png" % [type_id, variant]
	if not ResourceLoader.exists(path):
		path = "res://assets/figures/spearmen.png"
	var team_path := path.replace(".png", "_team.png")
	return [load(path), load(team_path) if ResourceLoader.exists(team_path) else null]


## A simple heraldic charge per civilization on the banner.
static func draw_emblem(canvas: CanvasItem, civ: String, at: Vector2, r: float, color: Color) -> void:
	match civ:
		"norse":
			canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r * 0.9, r), at + Vector2(-r * 0.9, r)]), color)
		"anglish":
			canvas.draw_line(at + Vector2(-r, 0), at + Vector2(r, 0), color, r * 0.45)
			canvas.draw_line(at + Vector2(0, -r), at + Vector2(0, r), color, r * 0.45)
		"frankish":
			for i in 3:
				canvas.draw_circle(at + Vector2.from_angle(-PI / 2 + i * TAU / 3) * r * 0.6, r * 0.35, color)
		"crusader":
			canvas.draw_line(at + Vector2(0, -r * 1.05), at + Vector2(0, r * 1.05), color, r * 0.5)
			canvas.draw_line(at + Vector2(-r * 0.75, -r * 0.3), at + Vector2(r * 0.75, -r * 0.3), color, r * 0.5)
		"byzantine":
			canvas.draw_arc(at, r * 0.8, 0.0, TAU, 16, color, r * 0.35)
		"saracen":
			canvas.draw_arc(at + Vector2(-r * 0.2, 0), r * 0.85, PI * 0.35, PI * 1.65, 16, color, r * 0.4)
		_:
			canvas.draw_circle(at, r * 0.6, color)


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
