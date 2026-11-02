class_name TypeIcons
extends RefCounted
## The round gold soldier-type icons used in the slider popups, the green
## army banner and the recruit cards (PRD A): a bow for archers, a crossbow
## for crossbowmen, two crossed spears for spearmen, a shield with a lion
## for heavy infantry, a horse head for cavalry, a pitchfork for militia and
## a wheel for engines. As in S&T, axemen show their axe: a single axe for
## huscarls and the Varangian Guard, crossed axes for berserkers; other
## civilization types use their base type's icon. A small star at the top left
## marks a type upgraded in the Forge. The order windows use S&T's dark
## badge with a gold symbol. Everything is drawn with lines and polygons, so
## there are no image files.

const GOLD := Color("#e2bd5a")
const GOLD_DARK := Color("#9c7a2c")
const INK := Color("#2a1a0c")
const BADGE := Color("#2c1b0e")
const FAMILIES := ["pitchfork", "spears", "shield", "bow", "crossbow", "horse", "siege"]
const FAMILY_NAMES := {
	"pitchfork": "Militia", "spears": "Spearmen", "shield": "Men-at-arms", "bow": "Archers",
	"crossbow": "Crossbowmen", "horse": "Cavalry", "siege": "Engines",
}


## Which icon (and Forge upgrade line) a soldier type belongs to.
static func family(type_id: String) -> String:
	var unit_type := Rules.unit(type_id)
	if unit_type.unit_class == "siege":
		return "siege"
	if unit_type.is_cavalry():
		return "horse"
	if unit_type.is_ranged():
		return "crossbow" if unit_type.counter_id() == "crossbowmen" else "bow"
	if type_id == "militia":
		return "pitchfork"
	if unit_type.counter_id() in ["spearmen", "pikemen"]:
		return "spears"
	return "shield"


## The symbol a soldier type shows: its line's, or its own axe.
static func icon_kind(type_id: String) -> String:
	if type_id in ["huscarl", "varangian_guard"]:
		return "axe"
	if type_id == "berserker":
		return "axes"
	return family(type_id)


## Draws the icon of a soldier type in `rect` on any canvas item; `dark` for
## the order windows' dark badge with a gold symbol.
static func draw(canvas: CanvasItem, type_id: String, rect: Rect2, upgraded := false, alpha := 1.0, dark := false) -> void:
	draw_family(canvas, icon_kind(type_id), rect, upgraded, alpha, dark)


static func draw_family(canvas: CanvasItem, kind: String, rect: Rect2, upgraded := false, alpha := 1.0, dark := false) -> void:
	var r := minf(rect.size.x, rect.size.y) / 2.0
	var c := rect.get_center()
	var ink := Color(INK, alpha)
	var accent := Color(GOLD, alpha)  # Details drawn over the symbol.
	if dark:
		canvas.draw_circle(c + Vector2(0, r * 0.08), r, Color(0, 0, 0, 0.3 * alpha))
		canvas.draw_circle(c, r, Color(BADGE.darkened(0.25), alpha))
		canvas.draw_circle(c, r * 0.92, Color(BADGE, alpha))
		canvas.draw_circle(c - Vector2(r * 0.15, r * 0.2), r * 0.55, Color(1, 0.85, 0.6, 0.05 * alpha))
		ink = Color(GOLD, alpha)
		accent = Color(BADGE, alpha)
	else:
		canvas.draw_circle(c + Vector2(0, r * 0.06), r, Color(0, 0, 0, 0.35 * alpha))
		canvas.draw_circle(c, r, Color(GOLD_DARK, alpha))
		canvas.draw_circle(c, r * 0.86, Color(GOLD, alpha))
		canvas.draw_circle(c - Vector2(r * 0.2, r * 0.25), r * 0.45, Color(1, 0.95, 0.75, 0.25 * alpha))
		canvas.draw_arc(c, r * 0.86, 0.0, TAU, 32, Color(INK, 0.5 * alpha), maxf(r * 0.05, 1.0), true)
	var w := maxf(r * 0.12, 1.2)
	match kind:
		"axe":
			_axe(canvas, c + Vector2(-r * 0.42, r * 0.55), c + Vector2(r * 0.3, -r * 0.5), r, ink, w)
		"axes":
			_axe(canvas, c + Vector2(-r * 0.45, r * 0.52), c + Vector2(r * 0.35, -r * 0.45), r * 0.85, ink, w * 0.85)
			_axe(canvas, c + Vector2(r * 0.45, r * 0.52), c + Vector2(-r * 0.35, -r * 0.45), r * 0.85, ink, w * 0.85)
		"bow":
			canvas.draw_arc(c + Vector2(-r * 0.25, 0), r * 0.6, -1.15, 1.15, 16, ink, w, true)
			var top := c + Vector2(-r * 0.25, 0) + Vector2.from_angle(-1.15) * r * 0.6
			var bottom := c + Vector2(-r * 0.25, 0) + Vector2.from_angle(1.15) * r * 0.6
			canvas.draw_line(top, bottom, ink, w * 0.45, true)
			canvas.draw_line(c + Vector2(-r * 0.05, 0), c + Vector2(r * 0.6, 0), ink, w * 0.7, true)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.68, 0), c + Vector2(r * 0.45, -r * 0.13), c + Vector2(r * 0.45, r * 0.13)]), ink)
		"crossbow":
			canvas.draw_line(c + Vector2(0, -r * 0.5), c + Vector2(0, r * 0.6), ink, w, true)
			canvas.draw_arc(c + Vector2(0, r * 0.25), r * 0.55, PI + 0.5, TAU - 0.5, 16, ink, w, true)
			canvas.draw_line(c + Vector2(-r * 0.48, -r * 0.02), c + Vector2(r * 0.48, -r * 0.02), ink, w * 0.45, true)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.68), c + Vector2(-r * 0.12, -r * 0.46), c + Vector2(r * 0.12, -r * 0.46)]), ink)
		"spears":
			for side in [-1.0, 1.0]:
				var from := c + Vector2(side * r * 0.5, r * 0.55)
				var to := c + Vector2(-side * r * 0.45, -r * 0.5)
				canvas.draw_line(from, to, ink, w * 0.8, true)
				var dir := (to - from).normalized()
				var normal := dir.orthogonal()
				canvas.draw_colored_polygon(PackedVector2Array([to + dir * r * 0.22, to + normal * r * 0.1, to - normal * r * 0.1]), ink)
		"shield":
			var s := PackedVector2Array([c + Vector2(-r * 0.45, -r * 0.5), c + Vector2(r * 0.45, -r * 0.5), c + Vector2(r * 0.42, r * 0.05),
				c + Vector2(0, r * 0.6), c + Vector2(-r * 0.42, r * 0.05)])
			canvas.draw_colored_polygon(s, ink)
			# A rampant lion, simplified: head, body and raised paws in gold.
			var g := accent
			canvas.draw_circle(c + Vector2(r * 0.06, -r * 0.22), r * 0.11, g)
			canvas.draw_line(c + Vector2(r * 0.02, -r * 0.12), c + Vector2(-r * 0.06, r * 0.25), g, w * 0.9, true)
			canvas.draw_line(c + Vector2(0, -r * 0.05), c + Vector2(r * 0.2, -r * 0.3), g, w * 0.5, true)
			canvas.draw_line(c + Vector2(-r * 0.06, r * 0.25), c + Vector2(r * 0.12, r * 0.38), g, w * 0.5, true)
			canvas.draw_line(c + Vector2(-r * 0.06, r * 0.22), c + Vector2(-r * 0.22, r * 0.36), g, w * 0.5, true)
		"horse":
			var head := PackedVector2Array([c + Vector2(-r * 0.15, -r * 0.55), c + Vector2(r * 0.1, -r * 0.35), c + Vector2(r * 0.55, r * 0.1),
				c + Vector2(r * 0.45, r * 0.28), c + Vector2(r * 0.12, r * 0.12), c + Vector2(-r * 0.05, r * 0.55), c + Vector2(-r * 0.45, r * 0.55),
				c + Vector2(-r * 0.35, -r * 0.2), c + Vector2(-r * 0.25, -r * 0.62)])
			canvas.draw_colored_polygon(head, ink)
			canvas.draw_circle(c + Vector2(r * 0.12, -r * 0.18), r * 0.06, accent)
		"pitchfork":
			canvas.draw_line(c + Vector2(r * 0.35, r * 0.6), c + Vector2(-r * 0.1, -r * 0.1), ink, w * 0.9, true)
			var base := c + Vector2(-r * 0.1, -r * 0.1)
			canvas.draw_line(base + Vector2(-r * 0.2, r * 0.12), base + Vector2(r * 0.12, -r * 0.18), ink, w * 0.7, true)
			for k in 3:
				var root := base + Vector2(-r * 0.2, r * 0.12).lerp(Vector2(r * 0.12, -r * 0.18), k / 2.0)
				canvas.draw_line(root, root + Vector2(-r * 0.32, -r * 0.3), ink, w * 0.55, true)
		"siege":
			canvas.draw_arc(c, r * 0.48, 0.0, TAU, 24, ink, w, true)
			for k in 4:
				canvas.draw_line(c, c + Vector2.from_angle(k * PI / 4.0) * r * 0.48, ink, w * 0.5, true)
				canvas.draw_line(c, c - Vector2.from_angle(k * PI / 4.0) * r * 0.48, ink, w * 0.5, true)
	if upgraded:
		draw_star(canvas, rect.position + Vector2(r * 0.28, r * 0.28), r * 0.34, alpha)


## A long-hafted axe from `low` to `high`, its bearded blade on the side the
## haft leans away from.
static func _axe(canvas: CanvasItem, low: Vector2, high: Vector2, r: float, ink: Color, w: float) -> void:
	canvas.draw_line(low, high, ink, w * 0.75, true)
	var along := (high - low).normalized()
	var out := along.orthogonal()
	if out.x * (high.x - low.x) < 0.0:
		out = -out
	var neck := high - along * r * 0.22
	var blade := PackedVector2Array([neck + along * r * 0.12, neck - along * r * 0.12])
	for k in 9:
		var t := lerpf(-1.25, 1.1, k / 8.0)
		blade.append(neck + out * r * 0.12 + (out * cos(t) + along * sin(t)) * r * 0.38)
	canvas.draw_colored_polygon(blade, ink)


## The small upgrade star: gold with a dark edge.
static func draw_star(canvas: CanvasItem, at: Vector2, size: float, alpha := 1.0) -> void:
	var points := PackedVector2Array()
	for k in 10:
		var radius := size if k % 2 == 0 else size * 0.45
		points.append(at + Vector2.from_angle(-PI / 2.0 + k * PI / 5.0) * radius)
	var edge := points.duplicate()
	edge.append(points[0])
	canvas.draw_colored_polygon(points, Color("#fff2a8", alpha))
	canvas.draw_polyline(edge, Color(INK, alpha), maxf(size * 0.18, 1.0), true)


## A Control that shows one type's icon at its size, with a tooltip.
static func control(type_id: String, size: float, upgraded := false, dark := false) -> Control:
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(size, size)
	icon.tooltip_text = Rules.unit(type_id).display_name
	icon.draw.connect(func(): TypeIcons.draw(icon, type_id, Rect2(Vector2.ZERO, icon.size), upgraded, 1.0, dark))
	return icon


## A Control that shows a line's icon (a family, as in the Forge).
static func family_control(kind: String, size: float, upgraded := false) -> Control:
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(size, size)
	icon.tooltip_text = FAMILY_NAMES[kind]
	icon.draw.connect(func(): TypeIcons.draw_family(icon, kind, Rect2(Vector2.ZERO, icon.size), upgraded))
	return icon
