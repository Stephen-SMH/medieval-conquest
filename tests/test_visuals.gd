extends RefCounted
## The map's drawing rules: the rank shown during a turn's playback, token
## layout around region names, icons inside shield buttons, painted figures
## and spear arrows.

const Helpers := preload("res://tests/helpers.gd")


func run(t) -> void:
	_test_rank_during_playback(t)
	_test_token_layout(t)
	_test_shield_icons(t)
	_test_figures(t)
	_test_spears(t)


func _test_rank_during_playback(t) -> void:
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red"}, [["blue", "greywater", "swordsmen"]])
	var unit: Unit = state.units[0]
	var tokens := TokenLayer.new()
	tokens.state = state
	tokens.sync()
	var before := {unit: {"province": unit.province, "hp": unit.hp, "rank": unit.rank()}}
	unit.xp = 5  # The battle made it Elite; the result is decided before it's shown.
	var effects := Effects.new()
	effects.setup(state, tokens, {})
	effects._rewind(before)
	var visual := tokens.visual_for(unit)
	t.check(visual.rank == 0, "during playback the token shows the rank from before the battle")
	tokens._process(0.016)
	t.check(visual.rank == 0, "a held token keeps the old rank while the turn plays out")
	visual.held = false  # Playback is over: the result is applied.
	tokens._process(0.016)
	t.check(visual.rank == 2, "once the result is applied the token shows the new rank")
	tokens.sync()
	t.check(visual.rank == unit.rank(), "syncing shows the unit's real rank")
	effects.free()
	tokens.free()


func _test_token_layout(t) -> void:
	var centroid := Vector2(400, 300)
	var clear := true
	var size := TokenLayer.MIN_WORLD
	while size <= TokenLayer.MAX_WORLD:
		var layout := TokenLayer.layout(centroid, size)
		var label := MapDecor.label_rect(centroid)
		if layout.number_rect.intersects(label) or layout.bar.end.y > layout.number_rect.position.y + 1.0:
			clear = false
		size += 2.0
	t.check(clear, "the soldier number never overlaps the region name, at any zoom")
	var layout := TokenLayer.layout(centroid, 58.0)
	t.check(layout.centre.y < centroid.y and layout.foot.y < MapDecor.label_rect(centroid).position.y,
		"the figures stand above the region's name")


func _test_shield_icons(t) -> void:
	var fits := true
	for button_size in [Vector2(92, 106), Vector2(184, 212), Vector2(60, 70)]:
		var inner: Rect2 = Hud.shield_inner_rect(button_size)
		for texture_size in [Vector2(512, 512), Vector2(32, 32), Vector2(800, 200), Vector2(100, 600)]:
			var rect: Rect2 = Hud.shield_icon_rect(button_size, texture_size)
			if not inner.grow(0.01).encloses(rect) or not is_equal_approx(rect.size.x / rect.size.y, texture_size.x / texture_size.y):
				fits = false
	t.check(fits, "shield-button icons always fit inside the shield and keep their shape")


func _test_figures(t) -> void:
	Rules.ensure_loaded()
	var missing := []
	for id in Rules.units:
		if not ResourceLoader.exists("res://assets/figures/%s.png" % id) or not ResourceLoader.exists("res://assets/figures/%s_team.png" % id):
			missing.append(id)
	t.check(missing.is_empty(), "every unit type has a painted figure and a faction-colour layer %s" % [missing])
	var spearmen := Rules.unit("spearmen")
	t.check(TokenLayer.figure_spots(spearmen, 3).size() == 3 and TokenLayer.figure_spots(spearmen, 10).size() == 4
		and TokenLayer.figure_spots(spearmen, 20).size() == 5, "infantry show 3 to 5 figures as their soldiers grow")
	t.check(TokenLayer.figure_spots(Rules.unit("knight"), 20).size() == 3 and TokenLayer.figure_spots(Rules.unit("catapult"), 5).size() == 1,
		"cavalry show up to 3 riders and siege 1 or 2 engines")


func _test_spears(t) -> void:
	var shape: PackedVector2Array = OrdersLayer.spear_geometry(Vector2(0, 0), Vector2(300, 0)).shape
	t.check(Geometry2D.is_point_in_polygon(Vector2(150, 0), shape) and Geometry2D.is_point_in_polygon(Vector2(270, 0), shape),
		"a spear arrow can be clicked along its shaft and on its head")
	t.check(OrdersLayer.spear_geometry(Vector2(0, 0), Vector2(40, 0)).is_empty(), "no arrow between regions too close to draw")
