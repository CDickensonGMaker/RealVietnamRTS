class_name AudioPool3D extends Node3D
## Pool of AudioStreamPlayer3D for efficient spatial sound playback
##
## Eliminates node creation/destruction overhead during combat.
## All sounds are properly positioned in 3D space.
##
## Usage:
##   AudioPool3D.play_at(sound_stream, position)
##   AudioPool3D.play_at(sound_stream, position, -5.0)  # quieter

const POOL_SIZE := 32

var _players: Array[AudioStreamPlayer3D] = []
var _next_index: int = 0

## Singleton instance
static var instance: AudioPool3D = null


func _ready() -> void:
	AudioPool3D.instance = self
	_initialize_pool()


func _initialize_pool() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.bus = "SFX"
		player.max_distance = 100.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.unit_size = 10.0
		add_child(player)
		_players.append(player)


## Play a sound at a 3D position
static func play_at(stream: AudioStream, position: Vector3, volume_db: float = 0.0) -> void:
	if not instance or not stream:
		return

	var player := instance._players[instance._next_index]
	instance._next_index = (instance._next_index + 1) % POOL_SIZE

	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db
	player.play()


## Play a sound at a position with pitch variation
static func play_at_with_pitch(stream: AudioStream, position: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if not instance or not stream:
		return

	var player := instance._players[instance._next_index]
	instance._next_index = (instance._next_index + 1) % POOL_SIZE

	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()


## Play a weapon fire sound with slight randomization
static func play_weapon_fire(stream: AudioStream, position: Vector3, volume_db: float = 0.0) -> void:
	# Add slight pitch variation for realism
	var pitch := randf_range(0.95, 1.05)
	play_at_with_pitch(stream, position, volume_db, pitch)


## Play an explosion sound
static func play_explosion(stream: AudioStream, position: Vector3, volume_db: float = 3.0) -> void:
	# Explosions are louder with slight variation
	var pitch := randf_range(0.9, 1.1)
	play_at_with_pitch(stream, position, volume_db, pitch)


## Play an impact sound (bullet, shell)
static func play_impact(stream: AudioStream, position: Vector3, volume_db: float = -3.0) -> void:
	var pitch := randf_range(0.85, 1.15)
	play_at_with_pitch(stream, position, volume_db, pitch)
