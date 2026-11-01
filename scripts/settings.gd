class_name Settings
extends RefCounted
## Player settings kept in user://settings.cfg.

const PATH := "user://settings.cfg"
const UI_SCALES := [0.9, 1.0, 1.25, 1.5]

static var show_forecast := true
static var fullscreen := false
static var ui_scale := 1.0
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	show_forecast = config.get_value("game", "show_forecast", true)
	fullscreen = config.get_value("display", "fullscreen", false)
	ui_scale = config.get_value("display", "ui_scale", 1.0)


static func save() -> void:
	var config := ConfigFile.new()
	config.set_value("game", "show_forecast", show_forecast)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "ui_scale", ui_scale)
	config.save(PATH)


## Applies the display settings to the running game.
static func apply(tree: SceneTree) -> void:
	ensure_loaded()
	tree.root.content_scale_factor = ui_scale
	if not OS.has_feature("web") and not OS.has_feature("mobile") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
