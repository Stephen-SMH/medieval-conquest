class_name SiteMarks
extends Node2D
## Marks drawn over the map's own icons (PRD E): a red no-sign over the town
## or camp icon of a province of yours that already has reinforcements
## coming this turn, so it can't take another order.

var state: GameState


func _ready() -> void:
	z_index = 3


func _draw() -> void:
	var faction := state.current_faction()
	if not state.factions.has(faction) or not state.factions[faction].human:
		return
	for region in state.map.province_order:
		if Economy.recruit_closed(state, region, faction):
			draw_no_sign(self, icon_centre(state, region), 14.0)


## Where MapDecor draws a region's town or camp icon (or the capital's crown
## when it has neither): the icons sit left of the name, crown, tower, then site.
static func icon_centre(game: GameState, region: String) -> Vector2:
	var centre: Vector2 = game.map.provinces[region].centroid
	var index := 0
	if Economy.site(game, region) != "":
		index = (1 if game.is_capital(region) else 0) + (1 if Sieges.walls(game, region) > 0 else 0)
	return centre + Vector2(-62 - index * 24, 18) + Vector2(11, 11)


static func draw_no_sign(canvas: CanvasItem, at: Vector2, radius: float) -> void:
	var red := Color("#d0261c")
	canvas.draw_arc(at, radius, 0.0, TAU, 28, Color(0, 0, 0, 0.5), radius * 0.36, true)
	canvas.draw_arc(at, radius, 0.0, TAU, 28, red, radius * 0.24, true)
	var d := Vector2(radius, -radius).normalized() * radius * 0.92
	canvas.draw_line(at - d, at + d, red, radius * 0.24, true)
