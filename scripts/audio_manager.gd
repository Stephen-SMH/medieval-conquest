class_name AudioManager
extends Node
## Autoload "Audio": music and sound effects on their own buses ("Music" and
## "SFX", both into Master), with the volumes from Settings. The music
## crossfades between the menu track and the calm map tracks, and plays a
## short sting on victory or defeat. Every button press clicks.
##
## Everything is optional: a missing file, a dummy audio driver or no autoload
## at all (the headless tests) just means silence. Call the static helpers
## (AudioManager.sfx("coins"), AudioManager.music("map")) from anywhere.

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"
const CROSSFADE := 1.6
const VOICES := 10  # Sound effects that can play at once.
const SILENT_DB := -60.0

## Which files a music "mood" can play; the map alternates its tracks.
const TRACKS := {
	"menu": ["menu_minstrel_dance"],
	"map": ["map_bards_tale", "map_old_tower_inn"],
	"victory": ["victory"],
	"defeat": ["defeat"],
}
## Stings play once; the other moods loop.
const STINGS := ["victory", "defeat"]
## Every sound effect, by name: its file and its loudness in dB.
const SOUNDS := {
	"click": ["ui_click", -4.0],
	"select": ["unit_select", 0.0],
	"order": ["order_thunk", -2.0],
	"hourglass": ["hourglass", -1.0],
	"march": ["march", -5.0],
	"hooves": ["hooves", -3.0],
	"clash": ["sword_clash", -3.0],
	"volley": ["arrow_volley", -2.0],
	"catapult": ["catapult_throw", -1.0],
	"impact": ["catapult_impact", -5.0],
	"capture": ["capture_horn", -3.0],
	"coins": ["coins", -2.0],
	"destroyed": ["unit_destroyed", -3.0],
}

var mood := ""
var _music: Array[AudioStreamPlayer] = []
var _active := 0  # Which of the two music players is the current one.
var _voices: Array[AudioStreamPlayer] = []
var _streams := {}
var _fade: Tween
var _map_turn := 0  # Which map track plays next.


func _ready() -> void:
	setup()


## Makes the buses and players and hooks every button's click. Runs once.
func setup() -> void:
	if not _music.is_empty():
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_buses()
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = MUSIC_BUS
		player.volume_db = SILENT_DB
		player.finished.connect(_on_music_finished.bind(player))
		add_child(player)
		_music.append(player)
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = SFX_BUS
		add_child(voice)
		_voices.append(voice)
	apply_volumes()
	var tree := get_tree() if is_inside_tree() else Engine.get_main_loop() as SceneTree
	if tree != null and not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)


## Adds the Music and SFX buses if the project has no bus layout for them.
static func ensure_buses() -> void:
	for bus in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, "Master")


## The bus gain for a volume from 0 to 1: silent at 0, 0 dB at 1.
static func volume_db(linear: float) -> float:
	return SILENT_DB if linear <= 0.001 else maxf(linear_to_db(clampf(linear, 0.0, 1.0)), SILENT_DB)


## Sets the Music and SFX buses from Settings.
static func apply_volumes() -> void:
	Settings.ensure_loaded()
	ensure_buses()
	for entry in [[MUSIC_BUS, Settings.music_volume], [SFX_BUS, Settings.sfx_volume]]:
		var index := AudioServer.get_bus_index(entry[0])
		AudioServer.set_bus_volume_db(index, volume_db(entry[1]))
		AudioServer.set_bus_mute(index, entry[1] <= 0.001)


## The autoload, or null when it isn't running (tests, tools).
static func instance() -> AudioManager:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Audio") as AudioManager


## Plays a sound effect by name (see SOUNDS), if audio is running.
static func sfx(sound: String, pitch_jitter := 0.06) -> void:
	var audio := instance()
	if audio != null:
		audio.play_sfx(sound, pitch_jitter)


## Switches the music to a mood (see TRACKS), if audio is running.
static func music(new_mood: String) -> void:
	var audio := instance()
	if audio != null:
		audio.play_music(new_mood)


## The file a mood plays, given how many times the map music has turned over.
static func track_for(new_mood: String, turn := 0) -> String:
	var tracks: Array = TRACKS.get(new_mood, [])
	return "" if tracks.is_empty() else tracks[posmod(turn, tracks.size())]


func play_sfx(sound: String, pitch_jitter := 0.06) -> void:
	if not SOUNDS.has(sound) or _voices.is_empty() or not is_inside_tree():
		return
	var stream := _stream(SFX_DIR + SOUNDS[sound][0] + ".ogg", false)
	if stream == null:
		return
	var voice := _free_voice()
	voice.stream = stream
	voice.volume_db = SOUNDS[sound][1]
	voice.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	voice.play()


## Crossfades to a mood's music. Asking for the mood already playing does nothing.
func play_music(new_mood: String) -> void:
	if new_mood == mood or not TRACKS.has(new_mood):
		return
	mood = new_mood
	var track := track_for(new_mood, _map_turn)
	if new_mood == "map":
		_map_turn += 1
	# The menu track loops; map tracks end so the next one can start; stings play once.
	_crossfade(_stream(MUSIC_DIR + track + ".ogg", new_mood == "menu"))


func _crossfade(stream: AudioStream) -> void:
	if _music.size() < 2 or not is_inside_tree():
		return
	var old := _music[_active]
	_active = 1 - _active
	var new := _music[_active]
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween().set_parallel()
	_fade.tween_property(old, "volume_db", SILENT_DB, CROSSFADE)
	_fade.chain().tween_callback(old.stop)
	if stream == null:
		return
	new.stream = stream
	new.volume_db = SILENT_DB
	new.play()
	_fade.parallel().tween_property(new, "volume_db", 0.0, CROSSFADE * 0.75).set_trans(Tween.TRANS_SINE)


## When a map track ends, the next one starts (the tracks themselves don't loop).
func _on_music_finished(player: AudioStreamPlayer) -> void:
	if player != _music[_active] or STINGS.has(mood) or mood == "":
		return
	var again := mood
	mood = ""
	play_music(again)


func _free_voice() -> AudioStreamPlayer:
	for voice in _voices:
		if not voice.playing:
			return voice
	# All busy: cut the one that has played longest.
	var oldest := _voices[0]
	for voice in _voices:
		if voice.get_playback_position() > oldest.get_playback_position():
			oldest = voice
	return oldest


func _stream(path: String, looped: bool) -> AudioStream:
	var key := path + (":loop" if looped else "")
	if not _streams.has(key):
		var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
		if stream is AudioStreamOggVorbis:
			stream = stream.duplicate()
			stream.loop = looped
		_streams[key] = stream
	return _streams[key]


## Every button in the game clicks when pressed, unless it plays its own
## sound (meta "sfx" set to another sound name, or "" for none).
func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta("click_hooked"):
		node.set_meta("click_hooked", true)
		node.pressed.connect(func():
			var sound: String = node.get_meta("sfx", "click")
			if sound != "":
				AudioManager.sfx(sound, 0.03))
