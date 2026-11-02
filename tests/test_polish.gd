extends RefCounted
## Sound and music, the volume settings, the tutorial, and the polish fixes:
## arrows kept off region names, the turn banner, the recruit window's gold
## and the varied figures in a unit group.

const Helpers := preload("res://tests/helpers.gd")
const Menu := preload("res://scripts/menu.gd")


func run(t) -> void:
	_test_volume_settings(t)
	_test_audio_manager(t)
	_test_battle_sounds(t)
	_test_recruit_gold(t)
	_test_turn_banner(t)
	_test_arrows_clear_names(t)
	_test_figure_variety(t)
	_test_tutorial_map(t)
	_test_tutorial_steps(t)
	_test_tutorial_offer(t)
	_test_scripts_compile(t)


## Every script compiles, the scene scripts the suites don't otherwise load included.
func _test_scripts_compile(t) -> void:
	var broken := []
	var folders := ["res://scripts"]
	while not folders.is_empty():
		var folder: String = folders.pop_back()
		for sub in DirAccess.get_directories_at(folder):
			folders.append(folder.path_join(sub))
		for file in DirAccess.get_files_at(folder):
			if file.ends_with(".gd"):
				var script = load(folder.path_join(file))
				if not (script is GDScript) or not script.can_instantiate():
					broken.append(file)
	t.check(broken.is_empty(), "every script compiles %s" % [broken])


func _scratch(file: String) -> String:
	return OS.get_user_data_dir().path_join("test_polish_" + file)


func _test_volume_settings(t) -> void:
	var real_path := Settings.config_path
	Settings.config_path = _scratch("settings.cfg")
	DirAccess.remove_absolute(Settings.config_path)
	Settings.load_again()
	t.check(is_equal_approx(Settings.music_volume, 0.7) and is_equal_approx(Settings.sfx_volume, 0.8),
		"music and sound volumes default to 70% and 80%")
	Settings.music_volume = 0.25
	Settings.sfx_volume = 0.0
	Settings.save()
	Settings.music_volume = 1.0
	Settings.sfx_volume = 1.0
	Settings.load_again()
	t.check(is_equal_approx(Settings.music_volume, 0.25) and is_equal_approx(Settings.sfx_volume, 0.0),
		"the volumes are saved with the other settings and read back")
	var config := ConfigFile.new()
	config.load(Settings.config_path)
	config.set_value("audio", "music_volume", 7.0)
	config.save(Settings.config_path)
	Settings.load_again()
	t.check(is_equal_approx(Settings.music_volume, 1.0), "a volume out of range in the file is clamped to 0..1")
	DirAccess.remove_absolute(Settings.config_path)
	Settings.config_path = real_path
	Settings.load_again()


func _test_audio_manager(t) -> void:
	t.check(AudioManager.volume_db(0.0) <= AudioManager.SILENT_DB and is_equal_approx(AudioManager.volume_db(1.0), 0.0)
		and absf(AudioManager.volume_db(0.5) + 6.02) < 0.1, "volume 0 is silent, 100% is 0 dB and 50% about -6 dB")
	t.check(AudioManager.track_for("map", 0) != AudioManager.track_for("map", 1) and AudioManager.track_for("map", 0) == AudioManager.track_for("map", 2),
		"the map music alternates between its calm tracks")
	t.check(AudioManager.track_for("nonsense") == "", "an unknown mood has no track")
	var missing := []
	for mood in AudioManager.TRACKS:
		for track in AudioManager.TRACKS[mood]:
			if not ResourceLoader.exists(AudioManager.MUSIC_DIR + track + ".ogg"):
				missing.append(track)
	for sound in AudioManager.SOUNDS:
		if not ResourceLoader.exists(AudioManager.SFX_DIR + AudioManager.SOUNDS[sound][0] + ".ogg"):
			missing.append(sound)
	t.check(missing.is_empty(), "every music track and sound effect has its .ogg file (missing: %s)" % [missing])
	for name in ["menu", "victory", "defeat"]:
		t.check(AudioManager.TRACKS.has(name), "there is music for '%s'" % name)
	for name in ["click", "select", "order", "hourglass", "march", "hooves", "clash", "volley", "catapult", "impact", "capture", "coins", "destroyed"]:
		if not AudioManager.SOUNDS.has(name):
			missing.append(name)
	t.check(missing.is_empty(), "every sound the game asks for is listed")

	# Running for real, but on the dummy driver in the headless tests: nothing may break.
	var audio := AudioManager.new()
	(t as SceneTree).root.add_child(audio)
	if audio.mood == "" and audio._voices.is_empty():
		audio.setup()  # The test runner's tree isn't running yet, so _ready hasn't fired.
	t.check(AudioServer.get_bus_index(AudioManager.MUSIC_BUS) >= 0 and AudioServer.get_bus_index(AudioManager.SFX_BUS) >= 0,
		"the Music and SFX buses exist")
	audio.play_sfx("clash")
	audio.play_sfx("no such sound")
	audio.play_music("menu")
	audio.play_music("map")
	audio.play_music("no such mood")
	t.check(audio.mood == "map", "music switches moods and ignores unknown ones")
	audio._stream("res://assets/audio/sfx/does_not_exist.ogg", false)
	t.check(audio._stream("res://assets/audio/sfx/does_not_exist.ogg", false) == null, "a missing file is silence, not an error")
	AudioManager.sfx("click")  # The static helpers work whether the autoload runs or not.
	AudioManager.music("menu")
	Settings.music_volume = 0.0
	AudioManager.apply_volumes()
	t.check(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioManager.MUSIC_BUS)), "a volume of 0 mutes its bus")
	Settings.load_again()
	AudioManager.apply_volumes()
	audio.free()


func _test_battle_sounds(t) -> void:
	var state := Helpers.game({"greywater": "blue", "kingsvale": "red"},
		[["blue", "greywater", "archers"], ["blue", "northmarch", "catapult"], ["red", "kingsvale", "light_cavalry"], ["blue", "ashford", "spearmen"]])
	var archers: Unit = Helpers.units_of_type(state, "archers")[0]
	var catapult: Unit = Helpers.units_of_type(state, "catapult")[0]
	var horse: Unit = Helpers.units_of_type(state, "light_cavalry")[0]
	var spears: Unit = Helpers.units_of_type(state, "spearmen")[0]
	t.check(Effects.volley_sounds([{"type": "volley", "unit": archers}, {"type": "volley", "unit": archers}]) == ["volley"],
		"a volley of arrows whistles once, however many archers shoot")
	t.check(Effects.volley_sounds([{"type": "volley", "unit": catapult}, {"type": "destroyed", "unit": archers}]) == ["catapult"],
		"a catapult's volley throws a stone")
	t.check(Effects.march_sounds([spears]) == ["march"] and Effects.march_sounds([horse]) == ["hooves"],
		"infantry march with footsteps, cavalry with hooves")
	t.check(Effects.march_sounds([spears, horse, null]).size() == 2, "mixed marches play both, and skip missing units")


func _test_recruit_gold(t) -> void:
	t.check(RecruitWindow.gold_text(300) == "300", "the recruit window shows 300 gold as \"300\", not \"000300\"")
	t.check(RecruitWindow.gold_text(0) == "0" and RecruitWindow.gold_text(1250) == "1,250", "0 stays 0 and thousands get a comma")


func _test_turn_banner(t) -> void:
	var screen := Vector2(1280, 720)
	var banner := Vector2(520, 62)
	var at := Hud.turn_banner_position(screen, banner)
	t.check(is_equal_approx(at.x + banner.x / 2.0, screen.x / 2.0) and at.y >= 64.0, "the turn banner is centred under the plaque")
	t.check(Hud.turn_banner_seconds() <= 2.0, "the turn banner is gone within 2 seconds (it was 2.7)")


## Every arrow's ends and turns stay off the names of the regions they're in.
func _test_arrows_clear_names(t) -> void:
	var map := MapData.load_map("heartlands")
	var size := 58.0
	var anchor := func(r): return TokenLayer.layout(map.provinces[r].centroid, size).foot
	# The reported case: cavalry through Highcrag.
	var regions := ["kingsvale", "highcrag", "eastwold"]
	var points := OrdersLayer.route_points(regions.map(anchor), regions.map(func(r): return OrdersLayer.name_rect(map, r)), size)
	var label := OrdersLayer.name_rect(map, "highcrag")
	t.check(not OrdersLayer.spear_crosses(points[0], points[1], label) and not OrdersLayer.spear_crosses(points[1], points[2], label),
		"a two-step cavalry arrow through Highcrag leaves its name readable")
	# Every move between neighbours, and every two-step route, on every map.
	var singles := []
	var doubles := []
	var double_count := 0
	var before_fix := 0
	for map_id in MapData.list_maps():
		var m := MapData.load_map(map_id)
		var foot := func(r): return TokenLayer.layout(m.provinces[r].centroid, size).foot
		for a in m.province_order:
			for b in m.neighbours(a):
				for c in m.neighbours(b) + [""]:
					if c == a:
						continue
					var path: Array = [a, b] if c == "" else [a, b, c]
					var labels: Array = path.map(func(r): return OrdersLayer.name_rect(m, r))
					var feet: Array = path.map(foot)
					var route := OrdersLayer.route_points(feet, labels, size)
					if c != "":
						double_count += 1
					for i in path.size() - 1:
						if OrdersLayer.spear_crosses(feet[i], feet[i + 1], labels[i]) or OrdersLayer.spear_crosses(feet[i], feet[i + 1], labels[i + 1]):
							before_fix += 1
						if OrdersLayer.spear_crosses(route[i], route[i + 1], labels[i]) or OrdersLayer.spear_crosses(route[i], route[i + 1], labels[i + 1]):
							(singles if c == "" else doubles).append("%s: %s" % [map_id, "-".join(path)])
							break
	t.check(singles.is_empty(), "no one-step arrow on any map covers the name of the region it leaves or enters %s" % [singles])
	# A sharp V around a waypoint's name (in from below on one side, out below on
	# the other) can't miss it with straight arrows; those are rare and cover it least.
	t.check(doubles.size() * 20 <= double_count, "at most 5%% of two-step routes touch a name (%d of %d; %d arrows did before)" % [doubles.size(), double_count, before_fix])
	t.check(OrdersLayer.joint(null, Vector2(500, 300), null, Rect2(480, 310, 40, 30), size) == Vector2(500, 300),
		"a point nothing runs through stays at the unit's feet")


func _test_figure_variety(t) -> void:
	t.check(TokenLayer.variant_count("spearmen") == 3, "spearmen were rendered in 3 poses")
	t.check(TokenLayer.figure_textures("spearmen", 1)[0] != TokenLayer.figure_textures("spearmen", 0)[0], "a pose variant is its own picture")
	t.check(TokenLayer.figure_textures("no_such_unit", 2)[0] != null, "an unknown unit or variant falls back to a figure")
	var all_differ := true
	var in_range := true
	for seed in [1, 77, 12345, 999999]:
		var looks := []
		for i in 5:
			looks.append(TokenLayer.figure_look(seed, i, 3))
		if looks[0].variant == looks[1].variant or looks[1].variant == looks[2].variant or looks[0].variant == looks[2].variant:
			all_differ = false
		for look in looks:
			if look.scale < 0.92 or look.scale > 1.08 or absf(look.offset.x) > 0.04 or look.shade < 0.9 or look.shade > 1.04:
				in_range = false
	t.check(all_differ, "the first three figures of a group are three different poses")
	t.check(in_range, "figures vary in size by at most 8% and shift only a little")
	t.check(TokenLayer.figure_look(42, 3, 3) == TokenLayer.figure_look(42, 3, 3), "the same unit always looks the same")
	t.check(TokenLayer.figure_look(42, 1, 1).variant == 0, "a unit with one picture uses it for every figure")


func _test_tutorial_map(t) -> void:
	var scenario := Tutorial.scenario()
	t.check(not scenario.is_empty() and scenario.mission.get("tutorial", false), "the tutorial scenario loads")
	var map := MapData.load_map(scenario.map)
	t.check(map.province_order.size() >= 6 and map.province_order.size() <= 8, "the tutorial map has 6 to 8 regions (%d)" % map.province_order.size())
	var symmetric := true
	for a in map.province_order:
		for b in map.neighbours(a):
			if not map.are_neighbours(b, a) or map.shared_edges(a, b).is_empty():
				symmetric = false
	t.check(symmetric, "tutorial neighbours are mutual and share a border")
	t.check(not MapData.list_maps().has(scenario.map), "the tutorial map isn't offered for skirmish or hotseat")
	var sites := map.province_order.map(func(r): return map.provinces[r].get("site", ""))
	t.check(sites.has("town") and sites.has("camp"), "the tutorial map has a town and a camp for reinforcements")


func _test_tutorial_steps(t) -> void:
	var state := GameState.from_scenario(Tutorial.scenario(), 1)
	var tutorial := Tutorial.new(state.turn)
	var unit_of := func(type_id): return state.units.filter(func(u): return u.type_id == type_id and u.owner == Tutorial.PLAYER)[0]
	var spears: Unit = unit_of.call("spearmen")
	var swords: Unit = unit_of.call("swordsmen")
	var horse: Unit = unit_of.call("light_cavalry")
	Helpers.plan_as(state, Tutorial.PLAYER)
	t.check(tutorial.current().id == "select" and not tutorial.update(state, null), "the tutorial starts by waiting for a unit to be selected")
	t.check(not tutorial.may_end_turn(), "the hourglass waits until the orders have been taught")
	tutorial.update(state, spears)
	t.check(tutorial.current().id == "move", "selecting a unit moves on to marching")
	t.check(Orders.give(state, spears, "move", "fernridge") == "", "the spearmen can march to Fernridge")
	tutorial.update(state, spears)
	t.check(tutorial.current().id == "cancel", "a march order moves on to cancelling")
	Orders.cancel(state, spears)
	tutorial.record("cancel")
	tutorial.update(state, spears)
	t.check(tutorial.current().id == "cancel", "after cancelling it waits for the order to be given again")
	Orders.give(state, spears, "move", "fernridge")
	tutorial.update(state, spears)
	t.check(tutorial.current().id == "attack", "then it teaches the attack")
	t.check(Orders.give(state, swords, "attack", "ravensford", {"melee": 12}) == "", "the swordsmen can attack Ravensford with part of the unit")
	tutorial.update(state, swords)
	t.check(tutorial.current().id == "cavalry", "then cavalry's two steps")
	Orders.give(state, horse, "move", "saltfen")
	tutorial.update(state, horse)
	t.check(tutorial.current().id == "cavalry", "one cavalry step isn't enough")
	t.check(Orders.give(state, horse, "move", "highmoor") == "" or Orders.give(state, horse, "attack", "ravensford") == "", "the cavalry takes a second step")
	tutorial.update(state, horse)
	t.check(tutorial.current().id == "hourglass" and tutorial.may_end_turn(), "then the hourglass, which may now be turned")
	Helpers.plan_as(state, "raiders")
	AI.play_turn(state)
	t.check(state.orders.keys().all(func(u): return u.owner != "raiders") and state.provinces["ravensford"].recruits.is_empty(),
		"the tutorial's raiders are passive: no orders, no recruits")
	Helpers.resolve(state)
	tutorial.update(state, null)
	t.check(tutorial.current().id == "treasury", "after the turn it teaches gold")
	tutorial.record("treasury")
	tutorial.update(state, null)
	t.check(tutorial.current().id == "reinforce", "then reinforcements")
	Helpers.plan_as(state, Tutorial.PLAYER)
	var bundle := Economy.bundle_of(state, Tutorial.PLAYER, "spearmen")
	t.check(Economy.bundle_targets(state, bundle, Tutorial.PLAYER).has("oakhollow") and Economy.buy(state, "millbrook", bundle),
		"a bundle can go to the capital or Millbrook's town (%s)" % Economy.bundle_problem(state, "millbrook", bundle, Tutorial.PLAYER))
	tutorial.record("recruit")
	tutorial.update(state, null)
	t.check(tutorial.current().id == "finish" and not tutorial.finished(), "the last step waits for the player to finish")
	tutorial.skip()
	t.check(tutorial.finished(), "skipping the last step ends the tutorial")
	var skipper := Tutorial.new()
	for i in 4:
		skipper.skip()
	t.check(skipper.current().id == "cavalry", "any step can be skipped")
	t.check(not state.is_over(), "the tutorial has no objectives to end it early")


func _test_tutorial_offer(t) -> void:
	var real_settings := Settings.config_path
	var real_progress := Progress.path
	Settings.config_path = _scratch("offer.cfg")
	Progress.path = _scratch("offer.json")
	DirAccess.remove_absolute(Settings.config_path)
	DirAccess.remove_absolute(Progress.path)
	Settings.load_again()
	t.check(Menu.should_offer_tutorial(), "a new player is offered the tutorial")
	Settings.tutorial_offered = true
	t.check(not Menu.should_offer_tutorial(), "the offer is made only once")
	Settings.tutorial_offered = false
	Progress.record("norse", 0, 2)
	t.check(Progress.any_progress() and not Menu.should_offer_tutorial(), "a player with campaign progress isn't offered it")
	DirAccess.remove_absolute(Settings.config_path)
	DirAccess.remove_absolute(Progress.path)
	Settings.config_path = real_settings
	Progress.path = real_progress
	Settings.load_again()
