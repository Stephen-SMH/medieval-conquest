class_name Effects
extends Node2D
## Plays a resolved turn on the map (PRD BR-4), in the order it was resolved:
## all volleys together (arrows arc, catapults throw stones), then marches,
## clashes and captures. Units march with a bob; an attacker advances to the
## border, dust and sparks fly, the defender recoils and the numbers drain; a
## failed attacker marches back; a destroyed unit fades and sinks; a captured
## region fills with its new colour from the attacker's side as a banner drops
## in. The results are already decided: this only shows them. A click skips.

const MARCH := 0.7
const VOLLEY := 0.85
const CLASH := 0.9
const SWEEP := 0.8
const AI_FAST := 1.8  # Moves by computer factions play this much faster.

var state: GameState
var tokens: TokenLayer
var views := {}

var _tracks := []  # Running animations; see _track().
var _projectiles := []  # {from, to, t, stone}
var _banners := []  # {at, color, t}
var _speed := 1.0
var _skip := false
var _clock := 0.0


func setup(game: GameState, token_layer: TokenLayer, region_views: Dictionary) -> void:
	state = game
	tokens = token_layer
	views = region_views
	z_index = 8


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
			"volley":
				var volleys := []
				while i < events.size() and events[i].type in ["volley", "volley_missed", "destroyed", "general_lost", "rejoined"]:
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
	queue_redraw()


## Puts every unit back where it stood before the turn.
func _rewind(before: Dictionary) -> void:
	for unit: Unit in tokens.visuals:
		var visual: TokenLayer.TokenVisual = tokens.visuals[unit]
		if before.has(unit):
			visual.region = before[unit].province
			visual.hp = before[unit].hp
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

func _volleys(volleys: Array) -> void:
	var drains := []
	for event in volleys:
		match event.type:
			"volley":
				var from := tokens.region_anchor(event.origin)
				var to := tokens.region_anchor(event.province)
				var stone: bool = event.unit.type().unit_class == "siege"
				for k in (2 if stone else 7):
					_projectiles.append({"from": from + Vector2(randf_range(-14, 14), randf_range(-8, 8)),
						"to": to + Vector2(randf_range(-22, 22), randf_range(-12, 12)), "t": -k * 0.06, "stone": stone})
				drains.append(event)
			"destroyed":
				drains.append(event)
	await _wait(VOLLEY / _speed)
	_projectiles.clear()
	for event in drains:
		if event.type == "volley":
			_drain(event.hp)
	await _wait(0.4 / _speed)
	for event in drains:
		if event.type == "destroyed":
			_fade_now(event.unit)
	await _wait(0.4 / _speed)


func _marches(marches: Array) -> void:
	var longest := 0.0
	for event in marches:
		var pace := _pace(event.unit)
		match event.type:
			"moved":
				_march_now(event.unit if _visual(event.unit) != null else event.get("main"), event.province, MARCH / pace)
			"swapped":
				_march_now(event.unit, event.province, MARCH / pace)
				_march_now(event.other, event.from, MARCH / pace)
			"merged":
				_march_now(event.unit, event.province, MARCH / pace, true)
		longest = maxf(longest, MARCH / pace)
	await _wait(longest)


func _battle(event: Dictionary) -> void:
	var attacker := _visual(event.unit)
	var defender := _visual(event.get("other"))
	var pace := _pace(event.unit)
	var from := tokens.region_anchor(event.origin)
	var to := tokens.region_anchor(event.province)
	var border := from.lerp(to, 0.5)
	if attacker != null:
		_track(attacker, "offset", attacker.offset, border - from, 0.4 / pace)
	await _wait(0.4 / pace)
	_clash_effects(border)
	if defender != null:
		var away := (to - from).normalized() * tokens.token_size() * 0.35
		_track(defender, "offset", Vector2.ZERO, away, 0.15 / pace)
		await _wait(0.15 / pace)
		_track(defender, "offset", away, Vector2.ZERO, 0.3 / pace)
	_drain(event.hp, CLASH / pace)
	await _wait(CLASH / pace)


func _march_back(unit) -> void:
	var visual := _visual(unit)
	if visual == null:
		return
	_track(visual, "offset", visual.offset, Vector2.ZERO, MARCH / _pace(unit), true)
	await _wait(MARCH / _pace(unit))


func _march(unit, region: String, seconds: float) -> void:
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
	tokens.visuals.erase(unit)
	tokens.ghosts.append(visual)
	_tracks.append({"visual": visual, "kind": "fade", "t": 0.0, "duration": 0.6 / _speed})


func _capture(event: Dictionary) -> void:
	var region: String = event.province
	var view: ProvinceView = views.get(region)
	if view == null:
		return
	var origin: Vector2 = state.map.provinces[event.from].centroid if event.get("from", "") != "" else state.map.provinces[region].centroid
	view.sweep_to(ProvinceView.paint(state.faction_color(event.faction)), origin.lerp(state.map.provinces[region].centroid, 0.25), SWEEP / _speed)
	_banners.append({"at": tokens.region_anchor(region) + Vector2(-tokens.token_size() * 0.9, -tokens.token_size() * 0.2),
		"color": state.faction_color(event.faction), "t": 0.0})
	await _wait(SWEEP / _speed)


func _drain(hp: Dictionary, seconds := 0.5) -> void:
	for unit in hp:
		var visual := _visual(unit)
		if visual != null:
			_track(visual, "hp", visual.hp, hp[unit], seconds)


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
	if _tracks.is_empty() and _projectiles.is_empty() and _banners.is_empty():
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


## Waits, unless the player clicked to skip.
func _wait(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds and not _skip:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
