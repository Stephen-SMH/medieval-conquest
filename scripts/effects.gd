class_name Effects
extends Node2D
## Plays a resolved turn on the map (PRD BR-4) as S&T does, in the order it
## was resolved. The turn's arrows stay on the map (OrdersLayer.playing) and
## each goes once its order is carried out. Units that split into
## detachments step apart into separate figure groups; volleys fly (arrows
## arc, catapults throw stones); in a battle the arrows aimed at the region
## burn while gold crossed swords hang over it, dust and sparks fly there,
## the numbers drain and a cracked gold shield pops over each side that
## takes losses (PRD L); a beaten army fades and sinks, the winners march in
## and the region fills with its new colour from the attacker's side as a
## banner drops in. Marches slide with a bob; detachments that come home
## march back into their army. When the viewer fought, battle_ended() lets
## the HUD say "Battle won" or "Battle lost". As in S&T, the camera glides
## to a battle, or another side's march, that happens off screen. The
## results are already decided: this only shows them. A click skips.

## A battle the viewer fought is over: `won` from the viewer's side.
signal battle_ended(won: bool)

const MARCH := 0.7
const VOLLEY := 0.85
const CLASH := 0.9
const BURN := 0.9  # How long the arrows burn before the losses show.
const SWEEP := 0.8
const AI_FAST := 1.8  # Moves by computer factions play this much faster.
const CRACK_SECONDS := 0.9
const GOLD := Color("#e2bd5a")

var state: GameState
var tokens: TokenLayer
var camera: Camera2D  # Moved to off-screen action, if set.
var orders: OrdersLayer
var views := {}

var _tracks := []  # Running animations; see _track().
var _projectiles := []  # {from, to, t, stone}
var _banners := []  # {at, color, t}
var _fights := []  # {at, t}: crossed swords over a region being fought over.
var _cracks := []  # {at, t}: a cracked shield over a unit that was hit.
var _swords: Texture2D
var _speed := 1.0
var _skip := false
var _clock := 0.0


func setup(game: GameState, token_layer: TokenLayer, region_views: Dictionary, orders_layer: OrdersLayer) -> void:
	state = game
	tokens = token_layer
	views = region_views
	orders = orders_layer
	z_index = 8
	_swords = load("res://assets/icons/ui_swords.svg")


func skip() -> void:
	_skip = true


## Plays the events. `before` holds each unit's region and HP before the turn.
func play(events: Array, before: Dictionary, speed: float) -> void:
	if speed <= 0.0 or not is_inside_tree():
		return
	_speed = speed
	_skip = false
	_rewind(before)
	var i := 0
	while i < events.size():
		var event: Dictionary = events[i]
		match event.type:
			"split":
				var splits := []
				while i < events.size() and events[i].type == "split":
					splits.append(events[i])
					i += 1
				await _splits(splits)
				continue
			"rejoined":
				var joins := []
				while i < events.size() and events[i].type == "rejoined":
					joins.append(events[i])
					i += 1
				await _rejoins(joins)
				continue
			"volley":
				var volleys := []
				while i < events.size() and events[i].type in ["volley", "volley_missed", "destroyed", "rejoined"]:
					volleys.append(events[i])
					i += 1
				await _volleys(volleys)
				continue
			"moved", "swapped", "merged":
				var marches := []
				while i < events.size() and events[i].type in ["moved", "swapped", "merged"]:
					marches.append(events[i])
					i += 1
				await _marches(marches)
				continue
			"battle":
				await _battle(event)
			"repulsed":
				await _march_back(event.unit)
			"retreated":
				await _march(event.unit, event.province, MARCH)
			"destroyed":
				await _fade(event.unit)
			"captured":
				await _capture(event)
		i += 1
	await _wait(0.2)
	for visual: TokenLayer.TokenVisual in tokens.visuals.values():
		visual.held = false
	tokens.ghosts.clear()
	_tracks.clear()
	_projectiles.clear()
	_banners.clear()
	_fights.clear()
	_cracks.clear()
	orders.stop_playing()
	queue_redraw()


## Puts every unit back where it stood before the turn.
func _rewind(before: Dictionary) -> void:
	for unit: Unit in tokens.visuals:
		var visual: TokenLayer.TokenVisual = tokens.visuals[unit]
		if before.has(unit):
			visual.region = before[unit].province
			visual.show(before[unit])
		visual.held = true
		visual.offset = Vector2.ZERO
		visual.position_override = null
		visual.alpha = 1.0
		visual.sink = 0.0
	tokens.queue_redraw()


func _visual(unit) -> TokenLayer.TokenVisual:
	return tokens.visual_for(unit) if unit != null else null


func _pace(unit) -> float:
	var faster: bool = unit != null and state.factions.has(unit.owner) and not state.factions[unit.owner].human
	return _speed * (AI_FAST if faster else 1.0)


# --- Pieces ------------------------------------------------------------------------------

## Each split unit's detachments appear as their own small figure groups,
## stepping out beside the soldiers who stay home.
func _splits(splits: Array) -> void:
	var size := tokens.token_size()
	for event in splits:
		var home := _visual(event.unit)
		if home != null:
			home.show(event.hp[event.unit])
		var parts: Array = event.parts
		for k in parts.size():
			var part: Unit = parts[k]
			var visual := TokenLayer.TokenVisual.new()
			visual.unit = part
			visual.region = event.province
			visual.owner = part.owner
			visual.show(event.hp[part])
			visual.held = true
			tokens.visuals[part] = visual
			# Fan out: alternately right and left, a little further each time.
			var side := 1.0 if k % 2 == 0 else -1.0
			var spread := Vector2(side * size * (0.85 + 0.7 * floorf(k / 2.0)), size * 0.12)
			_track(visual, "offset", Vector2.ZERO, spread, 0.35 / _speed)
	tokens.queue_redraw()
	await _wait(0.5 / _speed)


## Detachments march back into their unit, which fills up again.
func _rejoins(joins: Array) -> void:
	var longest := 0.0
	var marching := []
	for event in joins:
		var part := _visual(event.part)
		var pace := _pace(event.unit)
		if part != null and part.alpha > 0.0:
			_march_now(event.part, event.province, MARCH * 0.6 / pace, true)
			marching.append(event.part)
			longest = maxf(longest, MARCH * 0.6 / pace)
	for sound in march_sounds(marching):
		_sound(sound)
	await _wait(longest)
	for event in joins:
		if event.has("hp"):
			_drain({event.unit: event.hp}, 0.3 / _speed)

func _volleys(volleys: Array) -> void:
	var drains := []
	for event in volleys:
		match event.type:
			"volley":
				var from := tokens.region_anchor(event.origin)
				var to := tokens.region_anchor(event.province)
				var stone: bool = event.unit.troops.any(func(t): return t.type().unit_class == "siege") and not event.unit.troops.any(func(t): return t.type().unit_class == "ranged")
				for k in (2 if stone else 7):
					_projectiles.append({"from": from + Vector2(randf_range(-14, 14), randf_range(-8, 8)),
						"to": to + Vector2(randf_range(-22, 22), randf_range(-12, 12)), "t": -k * 0.06, "stone": stone})
				drains.append(event)
			"destroyed":
				drains.append(event)
	var sounds := volley_sounds(volleys)
	for sound in sounds:
		_sound(sound)
	await _wait(VOLLEY / _speed)
	if sounds.has("catapult"):
		_sound("impact")
	_projectiles.clear()
	for event in drains:
		if event.type == "volley":
			_drain(event.hp)
	await _wait(0.4 / _speed)
	for event in drains:
		if event.type == "destroyed":
			_fade_now(event.unit)
		elif event.type == "volley":
			orders.drop(event.province)
	await _wait(0.4 / _speed)


func _marches(marches: Array) -> void:
	var theirs := marches.filter(func(e): return e.unit != null and e.unit.owner != state.viewer())
	if not theirs.is_empty():
		await _look_at(theirs[0].province)
	var longest := 0.0
	for sound in march_sounds(marches.map(func(e): return e.get("unit"))):
		_sound(sound)
	for event in marches:
		var pace := _pace(event.unit)
		match event.type:
			"moved":
				_march_now(event.unit if _visual(event.unit) != null else event.get("main"), event.province, MARCH / pace)
				orders.drop(event.province, event.from)
			"swapped":
				_march_now(event.unit, event.province, MARCH / pace)
				_march_now(event.other, event.from, MARCH / pace)
				orders.drop(event.province, event.from)
				orders.drop(event.from, event.province)
			"merged":
				_march_now(event.unit, event.province, MARCH / pace, true)
				orders.drop(event.province, event.from)
		longest = maxf(longest, MARCH / pace)
	await _wait(longest)


func _battle(event: Dictionary) -> void:
	await _look_at(event.province)
	var attacker := _visual(event.unit)
	var defender := _visual(event.get("other"))
	var pace := _pace(event.unit)
	var from := tokens.region_anchor(event.origin)
	var to := tokens.region_anchor(event.province)
	var fight := {"at": to + Vector2(0, -tokens.token_size() * 1.25), "t": 0.0}
	_fights.append(fight)
	orders.burn(event.province)
	_sound("charge")
	_sound("clash")
	await _wait(BURN / pace)
	_clash_effects(to)
	for side in [[attacker, from], [defender, to]]:
		var visual: TokenLayer.TokenVisual = side[0]
		var after: Dictionary = event.hp.get(visual.unit, {}) if visual != null else {}
		if not after.is_empty() and float(after.hp) / maxf(float(after.full), 0.001) < visual.hp / visual.full - 0.005:
			_cracks.append({"at": side[1] + Vector2(0, -tokens.token_size() * 0.75), "t": 0.0})
	_drain(event.hp, CLASH / pace)
	await _wait(CLASH / pace)
	_fights.erase(fight)
	orders.burn(event.province, false)
	orders.drop(event.province)
	queue_redraw()
	var viewer := state.viewer()
	var defending: String = event.other.owner if event.get("other") != null else ""
	if viewer in [event.unit.owner, defending]:
		var battle: Battle = event.battle
		var won: bool = battle.attacker_won() == (event.unit.owner == viewer)
		_sound("won" if won else "lost")  # Your men cheer, or the drums toll.
		battle_ended.emit(won)
		await _wait(1.1 / pace)


func _march_back(unit) -> void:
	var visual := _visual(unit)
	if visual == null:
		return
	for sound in march_sounds([unit]):
		_sound(sound)
	_track(visual, "offset", visual.offset, Vector2.ZERO, MARCH / _pace(unit), true)
	await _wait(MARCH / _pace(unit))


func _march(unit, region: String, seconds: float) -> void:
	for sound in march_sounds([unit]):
		_sound(sound)
	_march_now(unit, region, seconds / _pace(unit))
	await _wait(seconds / _pace(unit))


## Marches a unit along a short path to another region, bobbing as it goes.
func _march_now(unit, region: String, seconds: float, fade_at_end := false) -> void:
	var visual := _visual(unit)
	if visual == null:
		return
	var start := tokens.badge_position(visual)
	var end := tokens.region_anchor(region)
	visual.offset = Vector2.ZERO
	visual.position_override = start
	_tracks.append({"visual": visual, "kind": "march", "from": start, "to": end, "t": 0.0, "duration": maxf(seconds, 0.01),
		"region": region, "fade": fade_at_end})


func _fade(unit) -> void:
	_fade_now(unit)
	await _wait(0.6 / _speed)


## A destroyed unit fades and sinks into the ground.
func _fade_now(unit) -> void:
	var visual := _visual(unit)
	if visual == null:
		return
	_sound("destroyed")
	tokens.visuals.erase(unit)
	tokens.ghosts.append(visual)
	_tracks.append({"visual": visual, "kind": "fade", "t": 0.0, "duration": 0.6 / _speed})


func _capture(event: Dictionary) -> void:
	var region: String = event.province
	var view: ProvinceView = views.get(region)
	if view == null:
		return
	_sound("capture")
	var origin: Vector2 = state.map.provinces[event.from].centroid if event.get("from", "") != "" else state.map.provinces[region].centroid
	view.sweep_to(ProvinceView.paint(state.faction_color(event.faction)), origin.lerp(state.map.provinces[region].centroid, 0.25), SWEEP / _speed)
	_banners.append({"at": tokens.region_anchor(region) + Vector2(-tokens.token_size() * 0.9, -tokens.token_size() * 0.2),
		"color": state.faction_color(event.faction), "t": 0.0})
	await _wait(SWEEP / _speed)


## Drains (or fills) armies' bars to a snapshot {soldiers, hp, full, troops}.
func _drain(looks: Dictionary, seconds := 0.5) -> void:
	for unit in looks:
		var visual := _visual(unit)
		if visual != null:
			var look: Dictionary = looks[unit]
			var from := visual.hp / visual.full * float(look.full)  # Keep the bar where it is while the numbers change.
			visual.count = int(look.soldiers)
			visual.full = maxf(float(look.full), 0.001)
			if look.has("troops"):
				visual.troops = look.troops.duplicate()
			visual.hp = from
			_track(visual, "hp", from, float(look.hp), seconds)


## Dust and sparks where two units clash.
func _clash_effects(at: Vector2) -> void:
	var size := tokens.token_size()
	for kind in ["dust", "sparks"]:
		var particles := CPUParticles2D.new()
		particles.position = at
		particles.one_shot = true
		particles.explosiveness = 0.85
		particles.z_index = 9
		if kind == "dust":
			particles.amount = 26
			particles.lifetime = 0.9 / _speed
			particles.direction = Vector2(0, -1)
			particles.spread = 180.0
			particles.initial_velocity_min = size * 0.6
			particles.initial_velocity_max = size * 1.4
			particles.gravity = Vector2(0, -size * 0.4)
			particles.scale_amount_min = size * 0.06
			particles.scale_amount_max = size * 0.14
			particles.color = Color("#8a7458", 0.55)
		else:
			particles.amount = 18
			particles.lifetime = 0.35 / _speed
			particles.spread = 180.0
			particles.initial_velocity_min = size * 2.0
			particles.initial_velocity_max = size * 4.0
			particles.gravity = Vector2(0, size * 3.0)
			particles.scale_amount_min = size * 0.03
			particles.scale_amount_max = size * 0.05
			particles.color = Color("#ffd970")
		add_child(particles)
		particles.emitting = true
		get_tree().create_timer(2.0).timeout.connect(particles.queue_free)


# --- Tracks and timing -----------------------------------------------------------------------

func _track(visual: TokenLayer.TokenVisual, kind: String, from, to, seconds: float, bob := false) -> void:
	_tracks.append({"visual": visual, "kind": kind, "from": from, "to": to, "t": 0.0, "duration": maxf(seconds, 0.01), "bob": bob})


func _process(delta: float) -> void:
	_clock += delta
	if _tracks.is_empty() and _projectiles.is_empty() and _banners.is_empty() and _fights.is_empty() and _cracks.is_empty():
		return
	var step := 1000.0 if _skip else delta
	for track in _tracks:
		track.t = minf(track.t + step, track.duration)
		var k: float = track.t / track.duration
		var visual: TokenLayer.TokenVisual = track.visual
		match track.kind:
			"march":
				var eased := k * k * (3.0 - 2.0 * k)
				var bob := -absf(sin(k * PI * 5.0)) * tokens.token_size() * 0.07
				visual.position_override = track.from.lerp(track.to, eased) + Vector2(0, bob)
				if k >= 1.0:
					visual.position_override = null
					visual.region = track.region
					if track.fade:
						visual.alpha = 0.0
			"offset":
				var bob := -absf(sin(k * PI * 4.0)) * tokens.token_size() * 0.05 if track.get("bob", false) else 0.0
				visual.offset = track.from.lerp(track.to, k * k * (3.0 - 2.0 * k)) + Vector2(0, bob)
			"hp":
				visual.hp = lerpf(track.from, track.to, k)
			"fade":
				visual.alpha = 1.0 - k
				visual.sink = k
	_tracks = _tracks.filter(func(t): return t.t < t.duration)
	for projectile in _projectiles:
		projectile.t += step / VOLLEY * _speed
	for banner in _banners:
		banner.t += step * _speed
	_banners = _banners.filter(func(b): return b.t < 2.5)
	for entry in _fights + _cracks:
		entry.t += step * _speed
	_cracks = _cracks.filter(func(c): return c.t < CRACK_SECONDS)
	tokens.queue_redraw()
	queue_redraw()


func _draw() -> void:
	var size := tokens.token_size() if tokens != null else 40.0
	for projectile in _projectiles:
		var t := clampf(projectile.t, 0.0, 1.0)
		if projectile.t < 0.0 or projectile.t > 1.0:
			continue
		var from: Vector2 = projectile.from
		var to: Vector2 = projectile.to
		var height := from.distance_to(to) * 0.35
		var at := from.lerp(to, t) + Vector2(0, -sin(t * PI) * height)
		var ahead := from.lerp(to, minf(t + 0.03, 1.0)) + Vector2(0, -sin(minf(t + 0.03, 1.0) * PI) * height)
		if projectile.stone:
			draw_circle(at, size * 0.09, Color("#4a4038"))
			draw_circle(at + Vector2(-1, -1), size * 0.05, Color("#8a8070"))
		else:
			var direction := (ahead - at).normalized()
			draw_line(at - direction * size * 0.25, at, Color("#2a1a0e"), maxf(size * 0.03, 1.2))
			draw_colored_polygon(PackedVector2Array([at + direction * size * 0.06, at - direction.orthogonal() * size * 0.03,
				at + direction.orthogonal() * size * 0.03]), Color("#2a1a0e"))
	# Gold crossed swords over each region being fought over, swelling as it goes on.
	for fight in _fights:
		var grow := minf(fight.t / 0.25, 1.0)
		var pulse := 1.0 + 0.06 * sin(fight.t * 9.0)
		var s := size * 0.95 * grow * pulse
		var box := Rect2(fight.at - Vector2(s, s) / 2.0, Vector2(s, s))
		draw_circle(fight.at, s * 0.62, Color(0.1, 0.06, 0.02, 0.55 * grow))
		draw_texture_rect(_swords, box.grow(s * 0.06), false, Color(0, 0, 0, 0.5 * grow))
		draw_texture_rect(_swords, box, false, Color(GOLD, grow))
	# A cracked gold shield pops over each side that was hit, then fades.
	for crack in _cracks:
		var k: float = crack.t / CRACK_SECONDS
		draw_cracked_shield(self, crack.at + Vector2(0, -k * size * 0.3), size * (0.32 + 0.1 * minf(k * 4.0, 1.0)), 1.0 - k * k)
	# Banners dropping into captured regions.
	for banner in _banners:
		var k := clampf(banner.t / 0.5, 0.0, 1.0)
		var drop := (1.0 - k) * (1.0 - k) * size * 1.6
		var bounce := sin(clampf((banner.t - 0.5) * 8.0, 0.0, PI)) * size * 0.08
		var alpha := clampf((2.5 - banner.t) / 0.6, 0.0, 1.0)
		var foot: Vector2 = banner.at + Vector2(0, -drop + bounce)
		var top := foot + Vector2(0, -size * 1.3)
		draw_line(foot, top, Color("#3a2410", alpha), maxf(size * 0.05, 1.5))
		draw_colored_polygon(PackedVector2Array([top, top + Vector2(size * 0.45, 0), top + Vector2(size * 0.45, size * 0.6),
			top + Vector2(size * 0.22, size * 0.48), top + Vector2(0, size * 0.6)]), Color(banner.color, alpha))
		draw_circle(top, size * 0.05, Color("#e2bd5a", alpha))


## A gold heater shield with a dark crack down it, `r` its half width.
static func draw_cracked_shield(canvas: CanvasItem, at: Vector2, r: float, alpha := 1.0) -> void:
	var shape := shield_points(at, r)
	canvas.draw_colored_polygon(shape, Color(0, 0, 0, 0.4 * alpha))
	canvas.draw_colored_polygon(shield_points(at, r * 0.86), Color(GOLD, alpha))
	canvas.draw_colored_polygon(shield_points(at + Vector2(-r * 0.1, -r * 0.1), r * 0.45), Color(1, 0.95, 0.75, 0.25 * alpha))
	var crack := PackedVector2Array([at + Vector2(-r * 0.05, -r * 0.95), at + Vector2(r * 0.15, -r * 0.45), at + Vector2(-r * 0.12, -r * 0.05),
		at + Vector2(r * 0.18, r * 0.35), at + Vector2(-r * 0.02, r * 0.85)])
	canvas.draw_polyline(crack, Color("#2a1a0c", alpha), maxf(r * 0.12, 1.5), true)
	canvas.draw_line(at + Vector2(-r * 0.12, -r * 0.05), at + Vector2(-r * 0.5, r * 0.15), Color("#2a1a0c", alpha), maxf(r * 0.07, 1.0), true)


## The outline of a heater shield around `at`, `r` its half width: a flat
## top, sides that run straight down a little, then curve in to the point.
static func shield_points(at: Vector2, r: float) -> PackedVector2Array:
	var points := PackedVector2Array([at + Vector2(-r, -r), at + Vector2(r, -r)])
	var side := []
	for i in range(1, 12):
		var a := float(i) / 11.0
		side.append(Vector2(r * sqrt(maxf(1.0 - a * a, 0.0)), -r * 0.6 + a * r * 1.75))
	for p in side:
		points.append(at + p)
	for i in range(side.size() - 2, -1, -1):
		points.append(at + Vector2(-side[i].x, side[i].y))
	return points


## The sounds a group of volleys makes: taiko drums for archers, a throw for catapults.
static func volley_sounds(volleys: Array) -> Array:
	var sounds := []
	for event in volleys:
		if event.type != "volley" or event.get("unit") == null:
			continue
		var engines: bool = event.unit.troops.any(func(t): return t.type().unit_class == "siege")
		var sound := "catapult" if engines else "volley"
		if not sounds.has(sound):
			sounds.append(sound)
	return sounds


## The sounds of units marching together: footsteps, and hooves for cavalry.
static func march_sounds(units: Array) -> Array:
	var sounds := []
	for unit in units:
		if unit == null:
			continue
		var sound := "hooves" if unit.all_cavalry() else "march"
		if not sounds.has(sound):
			sounds.append(sound)
	return sounds


## Plays a sound effect, unless the player is skipping the animation.
func _sound(sound: String) -> void:
	if not _skip:
		AudioManager.sfx(sound)


## Waits, unless the player clicked to skip.
func _wait(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds and not _skip:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


## Glides the camera to a region if it isn't comfortably on screen.
func _look_at(region: String) -> void:
	if camera == null or _skip or not state.map.provinces.has(region):
		return
	var at: Vector2 = state.map.provinces[region].centroid
	var view := camera.get_viewport_rect().size / camera.zoom
	if Rect2(camera.position - view / 2.0, view).grow(-minf(view.x, view.y) * 0.15).has_point(at):
		return
	var tween := create_tween()
	tween.tween_property(camera, "position", at, 0.45 / _speed).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
