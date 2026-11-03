class_name LoadingScreen
extends Control
## The loading screen before a game, as in S&T: wood in an iron frame, the
## logo, a red bar with the percentage and a tip under it. It loads the game
## scene in the background, shows for at least MIN_SECONDS, then changes to
## it. The logo is S&T's own if the player's copy has it in the git-ignored
## assets/st/menu/, else the game's name in gold.

const MIN_SECONDS := 1.4
const BAR := Rect2(26, 446, 1228, 22)  # At 1280x720, as S&T's mobile screen.
const RED := Color("#b0342a")
const TIPS := [
	"A region holds at most 20 soldiers. Order some out before others can come in.",
	"Finish a mission fast: its score pays for the upgrades in the Forge.",
	"Reinforcements arrive the turn after you buy them.",
	"Spears beat horse, horse beats bows, bows beat spears.",
	"Cavalry can move twice in one turn.",
	"Support an attack from next door: your soldiers fight, then stay at home.",
	"Archers shoot into a neighbouring region without leaving their own.",
	"Losing your capital can lose the mission. Keep an army in it.",
	"Walls make a region much harder to take. Siege engines break them.",
]
const ST_LOGO := "res://assets/st/menu/logo.png"

var _scene := ""
var _shown := 0.0
var _elapsed := 0.0
var _tip := ""
var _logo: Texture2D


## Shows the loading screen over everything and goes to `scene_path`.
static func open(tree: SceneTree, scene_path: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.add_child(LoadingScreen.new(scene_path))
	tree.root.add_child(layer)


func _init(scene_path: String) -> void:
	_scene = scene_path
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_tip = TIPS[randi() % TIPS.size()]
	if ResourceLoader.exists(ST_LOGO):
		_logo = load(ST_LOGO)


func _ready() -> void:
	ResourceLoader.load_threaded_request(_scene)


func _process(delta: float) -> void:
	_elapsed += delta
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(_scene, progress)
	var loaded: float = 1.0 if status == ResourceLoader.THREAD_LOAD_LOADED else (progress[0] if not progress.is_empty() else 0.0)
	# The bar never runs ahead of the clock, so it is seen to fill.
	_shown = move_toward(_shown, minf(loaded, _elapsed / MIN_SECONDS), delta * 1.5)
	queue_redraw()
	if status == ResourceLoader.THREAD_LOAD_LOADED and _shown >= 1.0:
		_finish(func(): get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(_scene)))
	elif status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
		_finish(func(): get_tree().change_scene_to_file(_scene))


## Changes scene, and takes the screen away once the new scene is up.
func _finish(change: Callable) -> void:
	set_process(false)
	change.call()
	await get_tree().process_frame
	await get_tree().process_frame
	get_parent().queue_free()


func _draw() -> void:
	var screen := Rect2(Vector2.ZERO, size)
	StFrame.draw_wood(self, screen)
	draw_rect(screen, Color(0, 0, 0, 0.12))
	var bar := StFrame.BAR
	for rect in [Rect2(0, 0, size.x, bar), Rect2(0, size.y - bar, size.x, bar), Rect2(0, 0, bar, size.y), Rect2(size.x - bar, 0, bar, size.y)]:
		StFrame.draw_bar(self, rect)
	var scale := size / Vector2(1280, 720)
	if _logo != null:
		var height := 330.0 * scale.y
		var width := height * _logo.get_width() / _logo.get_height()
		draw_texture_rect(_logo, Rect2(Vector2((size.x - width) / 2.0, 40.0 * scale.y), Vector2(width, height)), false)
	else:
		var font: Font = load("res://assets/fonts/Cinzel.ttf")
		for line in [["MEDIEVAL", 150.0, 108], ["CONQUEST", 290.0, 108]]:
			var at := Vector2(0, line[1] * scale.y)
			draw_string(font, at + Vector2(3, 5), line[0], HORIZONTAL_ALIGNMENT_CENTER, size.x, int(line[2] * scale.y), Color(0, 0, 0, 0.6))
			draw_string(font, at, line[0], HORIZONTAL_ALIGNMENT_CENTER, size.x, int(line[2] * scale.y), Color("#e2b95a"))
	var groove := Rect2(BAR.position * scale, BAR.size * scale)
	_capsule(groove, Color("#1d120a"))
	_capsule(Rect2(groove.position + Vector2(0, 2), Vector2(groove.size.x, groove.size.y - 4)), Color(1, 0.9, 0.7, 0.05))
	if _shown > 0.0:
		var fill := Rect2(groove.position + Vector2(3, 3), Vector2(maxf((groove.size.x - 6) * _shown, groove.size.y - 6), groove.size.y - 6))
		_capsule(fill, RED)
		_capsule(Rect2(fill.position, Vector2(fill.size.x, fill.size.y * 0.45)), Color(1, 0.75, 0.7, 0.25))
	var italic: Font = load("res://assets/fonts/IMFellEnglish-Italic.ttf")
	draw_string(italic, groove.position + Vector2(0, groove.size.y * 0.78), "%d%%" % int(round(_shown * 100)), HORIZONTAL_ALIGNMENT_CENTER,
		groove.size.x, int(16 * scale.y), Color(0.95, 0.9, 0.82, 0.9))
	var regular: Font = load("res://assets/fonts/IMFellEnglish-Regular.ttf")
	draw_string(regular, Vector2(0, 560 * scale.y), _tip, HORIZONTAL_ALIGNMENT_CENTER, size.x, int(24 * scale.y), Color("#f1e6cc"))


func _capsule(rect: Rect2, color: Color) -> void:
	var r := rect.size.y / 2.0
	draw_circle(rect.position + Vector2(r, r), r, color)
	draw_circle(rect.position + Vector2(rect.size.x - r, r), r, color)
	draw_rect(Rect2(rect.position + Vector2(r, 0), Vector2(maxf(rect.size.x - 2 * r, 0), rect.size.y)), color)
