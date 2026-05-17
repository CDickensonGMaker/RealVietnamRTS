extends Node
## AudioManager - Handles all game audio
## Manages music, ambient sounds, and sound effects

signal music_changed(track_name: String)

# Audio buses
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_AMBIENT := "Ambient"
const BUS_UI := "UI"

# Audio pools for sound effects
var sfx_pool: Array[AudioStreamPlayer3D] = []
var sfx_pool_2d: Array[AudioStreamPlayer] = []
const POOL_SIZE := 16

# Music player
var music_player: AudioStreamPlayer
var ambient_player: AudioStreamPlayer

# Volume settings (0.0 - 1.0)
var master_volume: float = 1.0
var music_volume: float = 0.7
var sfx_volume: float = 1.0
var ambient_volume: float = 0.5

# Sound effect definitions
const SFX := {
	# UI
	"ui_click": "res://assets/audio/sfx/ui_click.wav",
	"ui_select": "res://assets/audio/sfx/ui_select.wav",
	"ui_build": "res://assets/audio/sfx/ui_build.wav",
	"ui_alert": "res://assets/audio/sfx/ui_alert.wav",

	# Combat
	"rifle_fire": "res://assets/audio/sfx/rifle_fire.wav",
	"mg_fire": "res://assets/audio/sfx/mg_fire.wav",
	"mortar_fire": "res://assets/audio/sfx/mortar_fire.wav",
	"mortar_impact": "res://assets/audio/sfx/mortar_impact.wav",
	"explosion": "res://assets/audio/sfx/explosion.wav",

	# Units
	"squad_move": "res://assets/audio/sfx/squad_move.wav",
	"squad_acknowledge": "res://assets/audio/sfx/squad_acknowledge.wav",
	"squad_death": "res://assets/audio/sfx/squad_death.wav",

	# Vehicles
	"helicopter_rotor": "res://assets/audio/sfx/helicopter_rotor.wav",
	"helicopter_land": "res://assets/audio/sfx/helicopter_land.wav",
	"convoy_engine": "res://assets/audio/sfx/convoy_engine.wav",

	# Environment
	"jungle_ambient": "res://assets/audio/sfx/jungle_ambient.wav",
}

# Music tracks
const MUSIC := {
	"menu": "res://assets/audio/music/menu_theme.ogg",
	"gameplay_calm": "res://assets/audio/music/gameplay_calm.ogg",
	"gameplay_tense": "res://assets/audio/music/gameplay_tense.ogg",
	"combat": "res://assets/audio/music/combat.ogg",
	"victory": "res://assets/audio/music/victory.ogg",
	"defeat": "res://assets/audio/music/defeat.ogg",
}


func _ready() -> void:
	_setup_audio_buses()
	_create_audio_pools()
	_create_music_players()


func _setup_audio_buses() -> void:
	# Audio buses should be set up in project settings
	# This is a fallback/verification
	pass


func _create_audio_pools() -> void:
	# Create 3D sound effect pool
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer3D.new()
		player.name = "SFX3D_%d" % i
		player.bus = BUS_SFX
		player.max_distance = 100.0
		player.unit_size = 5.0
		add_child(player)
		sfx_pool.append(player)

	# Create 2D sound effect pool (UI, etc)
	for i in range(POOL_SIZE / 2):
		var player := AudioStreamPlayer.new()
		player.name = "SFX2D_%d" % i
		player.bus = BUS_UI
		add_child(player)
		sfx_pool_2d.append(player)


func _create_music_players() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.bus = BUS_MUSIC
	music_player.volume_db = linear_to_db(music_volume)
	add_child(music_player)

	ambient_player = AudioStreamPlayer.new()
	ambient_player.name = "AmbientPlayer"
	ambient_player.bus = BUS_AMBIENT
	ambient_player.volume_db = linear_to_db(ambient_volume)
	add_child(ambient_player)


func play_sfx_3d(sfx_name: String, position: Vector3, volume_db: float = 0.0) -> void:
	## Play a 3D positioned sound effect
	if sfx_name not in SFX:
		return

	var player := _get_available_3d_player()
	if not player:
		return

	var sfx_path: String = SFX[sfx_name]
	var stream: AudioStream = _load_audio(sfx_path)
	if stream:
		player.stream = stream
		player.global_position = position
		player.volume_db = volume_db
		player.play()


func play_sfx_2d(sfx_name: String, volume_db: float = 0.0) -> void:
	## Play a 2D sound effect (UI, notifications)
	if sfx_name not in SFX:
		return

	var player := _get_available_2d_player()
	if not player:
		return

	var sfx_path: String = SFX[sfx_name]
	var stream: AudioStream = _load_audio(sfx_path)
	if stream:
		player.stream = stream
		player.volume_db = volume_db
		player.play()


func play_music(track_name: String, fade_time: float = 1.0) -> void:
	## Play a music track with optional crossfade
	if track_name not in MUSIC:
		push_warning("AudioManager: Unknown music track: " + track_name)
		return

	var music_path: String = MUSIC[track_name]
	var stream: AudioStream = _load_audio(music_path)
	if not stream:
		return

	if fade_time > 0 and music_player.playing:
		# Crossfade
		var tween := create_tween()
		tween.tween_property(music_player, "volume_db", -40.0, fade_time)
		tween.tween_callback(func():
			music_player.stream = stream
			music_player.play()
			music_player.volume_db = linear_to_db(music_volume)
		)
	else:
		music_player.stream = stream
		music_player.play()

	music_changed.emit(track_name)


func stop_music(fade_time: float = 1.0) -> void:
	if fade_time > 0:
		var tween := create_tween()
		tween.tween_property(music_player, "volume_db", -40.0, fade_time)
		tween.tween_callback(music_player.stop)
	else:
		music_player.stop()


func play_ambient(ambient_name: String) -> void:
	## Play looping ambient sound
	if ambient_name not in SFX:
		return

	var ambient_path: String = SFX[ambient_name]
	var stream: AudioStream = _load_audio(ambient_path)
	if stream:
		ambient_player.stream = stream
		ambient_player.play()


func stop_ambient() -> void:
	ambient_player.stop()


func _get_available_3d_player() -> AudioStreamPlayer3D:
	for player in sfx_pool:
		if not player.playing:
			return player
	# All busy, return first (will cut off oldest sound)
	return sfx_pool[0]


func _get_available_2d_player() -> AudioStreamPlayer:
	for player in sfx_pool_2d:
		if not player.playing:
			return player
	return sfx_pool_2d[0]


func _load_audio(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path)
	# Return null if file doesn't exist (placeholder)
	return null


func set_master_volume(volume: float) -> void:
	master_volume = clamp(volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_MASTER), linear_to_db(master_volume))


func set_music_volume(volume: float) -> void:
	music_volume = clamp(volume, 0.0, 1.0)
	music_player.volume_db = linear_to_db(music_volume)


func set_sfx_volume(volume: float) -> void:
	sfx_volume = clamp(volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_SFX), linear_to_db(sfx_volume))


func set_ambient_volume(volume: float) -> void:
	ambient_volume = clamp(volume, 0.0, 1.0)
	ambient_player.volume_db = linear_to_db(ambient_volume)
