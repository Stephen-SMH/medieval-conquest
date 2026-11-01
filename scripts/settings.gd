class_name Settings
extends RefCounted
## Player settings kept in user://settings.cfg.

const PATH := "user://settings.cfg"
const UI_SCALES := [0.9, 1.0, 1.25, 1.5]

static var show_forecast := true
## "normal", "fast" or "off".
static var animation := "normal"
static var fullscreen := false
static var ui_scale := 1.0
## Music and sound-effect volumes, 0 (off) to 1.
static var music_volume := 0.7
static var sfx_volume := 0.8
## The one-time "First time here?" tutorial prompt has been shown.
static var tutorial_offered := false
## Where the settings live; tests point this at a scratch file.
static var config_path := PATH
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return
	show_forecast = config.get_value("game", "show_forecast", true)
	fullscreen = config.get_value("display", "fullscreen", false)
	ui_scale = config.get_value("display", "ui_scale", 1.0)
	animation = config.get_value("game", "animation", "normal")
	music_volume = clampf(float(config.get_value("audio", "music_volume", 0.7)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", 0.8)), 0.0, 1.0)
	tutorial_offered = config.get_value("game", "tutorial_offered", false)


## Forgets what was loaded, so the next ensure_loaded() reads the file again.
static func load_again() -> void:
	_loaded = false
	ensure_loaded()


static func save() -> void:
	var config := ConfigFile.new()
	config.set_value("game", "show_forecast", show_forecast)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "ui_scale", ui_scale)
	config.set_value("game", "animation", animation)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("game", "tutorial_offered", tutorial_offered)
	config.save(config_path)


## How fast the turn plays out: 1 normal, 2.2 fast, 0 off.
static func animation_speed() -> float:
	return {"normal": 1.0, "fast": 2.2, "off": 0.0}.get(animation, 1.0)


## Applies the display settings to the running game.
static func apply(tree: SceneTree) -> void:
	ensure_loaded()
	tree.root.content_scale_factor = ui_scale
	if not OS.has_feature("web") and not OS.has_feature("mobile") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		if not fullscreen and not _window_fitted:
			_window_fitted = true
			_fit_window_to_screen()


static var _window_fitted := false


## The project's 1280x720 window is tiny on a HiDPI screen, so on first launch the window is sized to most of the
## usable screen at 16:9 and centred. The stretch mode scales the whole interface up with it.
static func _fit_window_to_screen() -> void:
	if Engine.is_embedded_in_editor():
		return
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var fit := Vector2(usable.size) * 0.85
	var window_size := Vector2i(fit) if fit.x / fit.y <= 16.0 / 9.0 else Vector2i(roundi(fit.y * 16.0 / 9.0), roundi(fit.y))
	window_size.y = roundi(window_size.x * 9.0 / 16.0)
	if window_size.x <= 1280:
		return
	DisplayServer.window_set_size(window_size)
	DisplayServer.window_set_position(usable.position + (usable.size - window_size) / 2)
