class_name AudioManager
extends Node
## Autoload "Audio": music and sound effects on their own buses ("Music" and
## "SFX", both into Master), with the volumes from Settings. The music
## crossfades between the menu theme and the map tracks (a playlist; the
## Norse have their own first), and plays a sting on victory or defeat. When
## a battle is fought on screen the battle music swells over the map music
## and holds until no battle has been fought for BATTLE_HOLD seconds; then the
## map track carries on where it paused. Every button press clicks.
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
## Seconds the battle music holds after the last battle on screen.
const BATTLE_HOLD := 25.0
const BATTLE_FADE := 1.2

## Which files a music "mood" can play; the map moods play theirs in turn.
## Sources and licences are in CREDITS.md.
const TRACKS := {
	"menu": ["menu_rise_of_kingdoms"],
	"map": ["map_medieval_chateau", "map_towards_the_horizon", "map_gates_of_glory", "map_tavern_tales"],
	"map_norse": ["map_the_vikings", "map_gates_of_glory", "map_towards_the_horizon", "map_medieval_chateau"],
	"battle": ["battle_loop", "battle_the_great_battle"],
	"victory": ["victory_superepic"],
	"defeat": ["defeat_for_the_fallen"],
}
## Stings play once; the menu and battle music loop; map tracks follow one another.
const STINGS := ["victory", "defeat"]
const LOOPED := ["menu", "battle"]
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
	"charge": ["battle_charge", -1.0],  # An attack: the armies close, roars and steel.
	"won": ["battle_won", 0.0],  # Your men cheer a battle won.
	"lost": ["battle_lost", 0.0],  # Slow drums for a battle lost.
}

var mood := ""
var _music: Array[AudioStreamPlayer] = []
var _active := 0  # Which of the two music players is the current one.
var _voices: Array[AudioStreamPlayer] = []
var _streams := {}
var _fade: Tween
var _map_turn := 0  # Which map track plays next.
var _battle: AudioStreamPlayer
var _battle_fade: Tween
var _battle_left := 0.0  # Seconds the battle music still holds.
var _battle_turn := 0  # Which battle track plays next.


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
	_battle = AudioStreamPlayer.new()
	_battle.bus = MUSIC_BUS
	_battle.volume_db = SILENT_DB
	add_child(_battle)
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = SFX_BUS
		add_child(voice)
		_voices.append(voice)
	apply_volumes()
	var tree := get_tree() if is_inside_tree() else Engine.get_main_loop() as SceneTree
	if tree != null and not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)


## Adds the Music and SFX buses if the bus layout (default_bus_layout.tres)
## has none. The layout is what normally makes them: in the web build a bus
## added with add_bus()'s default position lands at the wrong index on the
## browser's side and feeds back into itself, and the browser mutes it all.
static func ensure_buses() -> void:
	for bus in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus(AudioServer.bus_count)
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


## The map mood for a civilization: its own playlist if it has one.
static func map_mood(civ: String) -> String:
	return "map_" + civ if TRACKS.has("map_" + civ) else "map"


## A battle is fought on screen: the battle music swells (see BATTLE_HOLD).
static func battle() -> void:
	var audio := instance()
	if audio != null:
		audio.start_battle()


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
	if new_mood == mood or not TRACKS.has(new_mood) or new_mood == "battle":
		return
	_stop_battle(BATTLE_FADE)
	mood = new_mood
	var track := track_for(new_mood, _map_turn)
	if new_mood.begins_with("map"):
		_map_turn += 1
	_crossfade(_stream(MUSIC_DIR + track + ".ogg", LOOPED.has(new_mood)))


## On the map, the battle music fades in over the map track, which pauses;
## another battle while it plays keeps it going longer.
func start_battle() -> void:
	if not mood.begins_with("map"):
		return
	var already := _battle_left > 0.0
	_battle_left = BATTLE_HOLD
	if already or _music.size() < 2 or not is_inside_tree():
		return
	var stream := _stream(MUSIC_DIR + track_for("battle", _battle_turn) + ".ogg", true)
	if stream == null:
		return
	_battle_turn += 1
	var map_player := _music[_active]
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(map_player, "volume_db", SILENT_DB, BATTLE_FADE)
	_fade.tween_callback(func(): map_player.stream_paused = true)
	if _battle_fade != null and _battle_fade.is_valid():
		_battle_fade.kill()
	_battle.stream = stream
	_battle.volume_db = SILENT_DB
	_battle.play()
	_battle_fade = create_tween()
	_battle_fade.tween_property(_battle, "volume_db", 0.0, BATTLE_FADE).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	if _battle_left > 0.0:
		_battle_left -= delta
		if _battle_left <= 0.0:
			_end_battle()


## The battle music fades out and the map track carries on where it paused.
func _end_battle() -> void:
	_stop_battle(BATTLE_FADE * 2.0)
	if not mood.begins_with("map"):
		return
	var map_player := _music[_active]
	map_player.stream_paused = false
	if not map_player.playing and map_player.stream != null:
		map_player.play()
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(map_player, "volume_db", 0.0, BATTLE_FADE * 2.0).set_trans(Tween.TRANS_SINE)


func _stop_battle(seconds: float) -> void:
	_battle_left = 0.0
	if _battle == null or not _battle.playing:
		return
	if _battle_fade != null and _battle_fade.is_valid():
		_battle_fade.kill()
	_battle_fade = create_tween()
	_battle_fade.tween_property(_battle, "volume_db", SILENT_DB, seconds)
	_battle_fade.tween_callback(_battle.stop)


## Whether the battle music is on (for the tests).
func battle_playing() -> bool:
	return _battle_left > 0.0


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
	_fade.chain().tween_callback(func():
		old.stop()
		old.stream_paused = false)
	if stream == null:
		return
	new.stream = stream
	new.volume_db = SILENT_DB
	new.play()
	_fade.parallel().tween_property(new, "volume_db", 0.0, CROSSFADE * 0.75).set_trans(Tween.TRANS_SINE)


## When a map track ends, the next one starts (the tracks themselves don't loop).
func _on_music_finished(player: AudioStreamPlayer) -> void:
	if player != _music[_active] or STINGS.has(mood) or LOOPED.has(mood) or mood == "":
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
