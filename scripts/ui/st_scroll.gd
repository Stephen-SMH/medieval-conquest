class_name StScroll
extends RefCounted
## S&T's full-screen scrolls, drawn: wood in an iron frame behind; a sheet
## of parchment with torn edges and rolled ends; the red banner with a gold
## crown; lighter boxes on the parchment; and the map sheets of the briefing.
## The briefing (BriefingScreen) and the victory scroll (EndScreen) use them.

const PAPER := Color("#e6d6a6")
const PAPER_DARK := Color("#cdb886")
const BOX := Color("#efe2b8")
const INK := Color("#2c1c10")
const TITLE := Color("#6e1a12")
const RED := Color("#a8261c")


## Wood over the whole screen, with iron bars round its edges.
static func draw_screen(canvas: CanvasItem, size: Vector2) -> void:
	var screen := Rect2(Vector2.ZERO, size)
	StFrame.draw_wood(canvas, screen)
	canvas.draw_rect(screen, Color(0, 0, 0, 0.18))
	var bar := StFrame.BAR
	for rect in [Rect2(0, 0, size.x, bar), Rect2(0, size.y - bar, size.x, bar), Rect2(0, 0, bar, size.y), Rect2(size.x - bar, 0, bar, size.y)]:
		StFrame.draw_bar(canvas, rect)


## A sheet of parchment with a few torn notches along its top and bottom.
static func draw_sheet(canvas: CanvasItem, rect: Rect2, notches := true) -> void:
	canvas.draw_rect(Rect2(rect.position + Vector2(4, 6), rect.size), Color(0, 0, 0, 0.3))
	canvas.draw_rect(rect, PAPER)
	# Darker towards the edges, as old paper.
	for k in 8:
		canvas.draw_rect(rect.grow(-k * 3.0), Color(PAPER_DARK, 0.1 - k * 0.012), false, 3.0)
	if notches:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(rect.size.x * 7 + rect.size.y)
		for edge in [rect.position.y, rect.end.y]:
			var x := rect.position.x + 120.0
			while x < rect.end.x - 120.0:
				x += rng.randf_range(120.0, 320.0)
				var depth := rng.randf_range(8.0, 15.0) * (1.0 if edge == rect.position.y else -1.0)
				canvas.draw_colored_polygon(PackedVector2Array([Vector2(x - 7, edge), Vector2(x + 7, edge), Vector2(x + 1, edge + depth)]),
					Color("#2a190c"))


## A rolled end of the scroll: a cylinder of parchment, `upright` for the
## sides of the victory scroll, else lying along the top of the briefing.
static func draw_roll(canvas: CanvasItem, rect: Rect2, upright: bool) -> void:
	canvas.draw_rect(Rect2(rect.position + Vector2(4, 6), rect.size), Color(0, 0, 0, 0.3))
	var steps := 14
	for k in steps:
		var t := float(k) / (steps - 1)
		var shade := 1.0 - pow(absf(t - 0.4) * 1.6, 2.0) * 0.35
		var color := Color(PAPER.r * shade, PAPER.g * shade, PAPER.b * shade)
		if upright:
			canvas.draw_rect(Rect2(rect.position + Vector2(rect.size.x * k / steps, 0), Vector2(rect.size.x / steps + 1, rect.size.y)), color)
		else:
			canvas.draw_rect(Rect2(rect.position + Vector2(0, rect.size.y * k / steps), Vector2(rect.size.x, rect.size.y / steps + 1)), color)
	canvas.draw_rect(rect, Color(0.3, 0.2, 0.1, 0.5), false, 1.5)


## A lighter box on the parchment, for a group of lines.
static func draw_box(canvas: CanvasItem, rect: Rect2) -> void:
	canvas.draw_rect(rect, BOX)
	canvas.draw_rect(rect, Color(0.45, 0.33, 0.15, 0.12), false, 2.0)


## The red banner with the gold crown hanging from its pole.
static func draw_banner(canvas: CanvasItem, rect: Rect2) -> void:
	var a := rect.position
	var b := rect.end
	var points := PackedVector2Array([a, Vector2(b.x, a.y), Vector2(b.x, b.y - rect.size.x * 0.22), Vector2(a.x + rect.size.x / 2.0, b.y),
		Vector2(a.x, b.y - rect.size.x * 0.22)])
	var shadow := PackedVector2Array()
	for point in points:
		shadow.append(point + Vector2(4, 6))
	canvas.draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	canvas.draw_colored_polygon(points, RED)
	canvas.draw_rect(Rect2(a, Vector2(rect.size.x, 6)), RED.darkened(0.35))
	for k in 5:
		canvas.draw_line(Vector2(a.x + rect.size.x * (0.15 + k * 0.18), a.y + 6), Vector2(a.x + rect.size.x * (0.15 + k * 0.18), b.y - 30),
			Color(0, 0, 0, 0.06), 6.0)
	draw_crown(canvas, Vector2(a.x + rect.size.x / 2.0, a.y + rect.size.y * 0.42), rect.size.x * 0.62, Color("#e8b54a"))


## A gold crown, `width` wide, its middle at `c`.
static func draw_crown(canvas: CanvasItem, c: Vector2, width: float, color: Color) -> void:
	var w := width
	var base := c + Vector2(-w / 2.0, w * 0.22)
	canvas.draw_colored_polygon(PackedVector2Array([base, base + Vector2(0, -w * 0.4), base + Vector2(w * 0.2, -w * 0.18), base + Vector2(w * 0.35, -w * 0.48),
		base + Vector2(w * 0.5, -w * 0.2), base + Vector2(w * 0.65, -w * 0.48), base + Vector2(w * 0.8, -w * 0.18), base + Vector2(w, -w * 0.4),
		base + Vector2(w, 0)]), color)
	canvas.draw_rect(Rect2(base + Vector2(0, -w * 0.02), Vector2(w, w * 0.1)), color.darkened(0.2))
	for x in [0.0, 0.35, 0.65, 1.0]:
		canvas.draw_circle(base + Vector2(w * x, -w * (0.44 if x in [0.0, 1.0] else 0.52)), w * 0.05, color)


## The briefing's loose map sheets, fanned in the bottom left.
static func draw_maps(canvas: CanvasItem, corner: Vector2, size: Vector2) -> void:
	for k in 3:
		var angle := deg_to_rad(-24.0 + k * 11.0)
		canvas.draw_set_transform(corner + Vector2(k * 26.0, -k * 8.0), angle)
		var sheet := Rect2(Vector2(0, -size.y), size)
		canvas.draw_rect(Rect2(sheet.position + Vector2(5, 6), sheet.size), Color(0, 0, 0, 0.3))
		canvas.draw_rect(sheet, PAPER.darkened(0.04 * k))
		# A faded coast and a few borders.
		var rng := RandomNumberGenerator.new()
		rng.seed = 11 + k
		var coast := PackedVector2Array()
		for i in 9:
			coast.append(Vector2(size.x * (0.15 + 0.7 * i / 8.0) + rng.randf_range(-12, 12), -size.y * (0.25 + rng.randf_range(0.0, 0.5))))
		canvas.draw_polyline(coast, Color(0.36, 0.48, 0.55, 0.45), 3.0, true)
		for i in 3:
			canvas.draw_line(coast[2 + i * 2], coast[2 + i * 2] + Vector2(rng.randf_range(-30, 30), size.y * 0.3), Color(0.4, 0.3, 0.2, 0.3), 1.5)
		canvas.draw_rect(sheet, Color(0.3, 0.2, 0.1, 0.4), false, 1.5)
	canvas.draw_set_transform(Vector2.ZERO)
