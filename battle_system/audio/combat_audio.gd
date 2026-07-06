extends Node
class_name CombatAudio
## CombatAudio - Manages weapon firing and impact sounds
##
## Pools AudioStreamPlayer3D nodes to avoid constant instantiation.
## Handles sound attenuation and overlapping weapon sounds.

const VietnamWeaponDataScript = preload("res://battle_system/data/vietnam_weapon_data.gd")

## Audio pool settings
const POOL_SIZE: int = 32
const MAX_DISTANCE: float = 200.0  # Max audible range
const ATTENUATION: float = 1.5  # Distance falloff exponent

## Sound definitions by profile name
## Format: { "profile_name": { "sounds": [paths], "volume_db": float, "pitch_variance": float } }
var SOUND_PROFILES: Dictionary = {
	"rifle": {
		"sounds": [],  # Will use procedural
		"volume_db": -6.0,
		"pitch_variance": 0.1,
		"pitch_base": 1.0,
	},
	"machine_gun": {
		"sounds": [],
		"volume_db": -3.0,
		"pitch_variance": 0.05,
		"pitch_base": 0.9,
	},
	"heavy_mg": {
		"sounds": [],
		"volume_db": 0.0,
		"pitch_variance": 0.05,
		"pitch_base": 0.7,
	},
	"grenade_launcher": {
		"sounds": [],
		"volume_db": -3.0,
		"pitch_variance": 0.1,
		"pitch_base": 0.6,
	},
	"rocket": {
		"sounds": [],
		"volume_db": 0.0,
		"pitch_variance": 0.05,
		"pitch_base": 0.5,
	},
	"mortar": {
		"sounds": [],
		"volume_db": 3.0,
		"pitch_variance": 0.1,
		"pitch_base": 0.4,
	},
	"artillery": {
		"sounds": [],
		"volume_db": 6.0,
		"pitch_variance": 0.05,
		"pitch_base": 0.3,
	},
	"explosion_small": {
		"sounds": [],
		"volume_db": 0.0,
		"pitch_variance": 0.15,
		"pitch_base": 0.8,
	},
	"explosion_large": {
		"sounds": [],
		"volume_db": 6.0,
		"pitch_variance": 0.1,
		"pitch_base": 0.5,
	},
}

## Audio player pool
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_index: int = 0

## Procedural sound generator
var _base_gunshot: AudioStreamWAV = null


func _ready() -> void:
	_create_pool()
	_create_procedural_sounds()
	print("[CombatAudio] Initialized with %d audio players" % POOL_SIZE)


func _create_pool() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		player.max_distance = MAX_DISTANCE
		player.attenuation_filter_cutoff_hz = 5000
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
		add_child(player)
		_pool.append(player)


func _create_procedural_sounds() -> void:
	# Create a basic procedural gunshot waveform
	# This is a placeholder - in production, load real audio files
	_base_gunshot = AudioStreamWAV.new()
	_base_gunshot.format = AudioStreamWAV.FORMAT_16_BITS
	_base_gunshot.mix_rate = 44100
	_base_gunshot.stereo = false

	# Generate a short impulse/crack sound
	var samples := PackedByteArray()
	var duration: float = 0.15
	var sample_count: int = int(44100 * duration)

	for i in sample_count:
		var t: float = float(i) / 44100.0
		var env: float = exp(-t * 30.0)  # Quick decay
		var noise: float = randf_range(-1.0, 1.0)
		var crack: float = sin(t * 2000.0) * exp(-t * 50.0)  # Initial crack
		var value: float = (noise * 0.3 + crack * 0.7) * env
		var sample: int = int(clampf(value, -1.0, 1.0) * 32767)
		# Pack as 16-bit little-endian
		samples.append(sample & 0xFF)
		samples.append((sample >> 8) & 0xFF)

	_base_gunshot.data = samples


## Play weapon fire sound at position
func play_fire(world_pos: Vector3, weapon_id: String) -> void:
	var weapon := VietnamWeaponDataScript.get_weapon(weapon_id)
	if not weapon:
		return

	var profile_name: String = _get_sound_profile(weapon.category)
	_play_at_position(world_pos, profile_name)


## Play impact/explosion sound at position
func play_impact(world_pos: Vector3, is_explosion: bool = false, large: bool = false) -> void:
	var profile_name: String
	if is_explosion:
		profile_name = "explosion_large" if large else "explosion_small"
	else:
		profile_name = "rifle"  # Bullet impact - use short sharp sound
	_play_at_position(world_pos, profile_name)


## Internal: play sound at world position
func _play_at_position(world_pos: Vector3, profile_name: String) -> void:
	var profile: Dictionary = SOUND_PROFILES.get(profile_name, SOUND_PROFILES["rifle"])

	# Get next player from pool
	var player: AudioStreamPlayer3D = _pool[_pool_index]
	_pool_index = (_pool_index + 1) % POOL_SIZE

	# Stop if already playing (pool exhaustion)
	if player.playing:
		player.stop()

	# Position
	player.global_position = world_pos

	# Sound - use loaded sound if available, otherwise procedural
	var sounds: Array = profile.get("sounds", [])
	if sounds.size() > 0:
		var sound_path: String = sounds[randi() % sounds.size()]
		var stream: AudioStream = load(sound_path) if ResourceLoader.exists(sound_path) else null
		if stream:
			player.stream = stream
		else:
			player.stream = _base_gunshot
	else:
		player.stream = _base_gunshot

	# Volume and pitch
	player.volume_db = profile.get("volume_db", 0.0)
	var pitch_base: float = profile.get("pitch_base", 1.0)
	var pitch_var: float = profile.get("pitch_variance", 0.1)
	player.pitch_scale = pitch_base + randf_range(-pitch_var, pitch_var)

	player.play()


## Map weapon category to sound profile
func _get_sound_profile(category: int) -> String:
	match category:
		VietnamWeaponDataScript.WeaponCategory.RIFLE:
			return "rifle"
		VietnamWeaponDataScript.WeaponCategory.MACHINE_GUN:
			return "machine_gun"
		VietnamWeaponDataScript.WeaponCategory.GRENADE_LAUNCHER:
			return "grenade_launcher"
		VietnamWeaponDataScript.WeaponCategory.SIDEARM:
			return "rifle"
		VietnamWeaponDataScript.WeaponCategory.ROCKET_LAUNCHER:
			return "rocket"
		VietnamWeaponDataScript.WeaponCategory.MORTAR:
			return "mortar"
		VietnamWeaponDataScript.WeaponCategory.VEHICLE_MG:
			return "machine_gun"
		VietnamWeaponDataScript.WeaponCategory.ARTILLERY:
			return "artillery"
		VietnamWeaponDataScript.WeaponCategory.TANK_MAIN_GUN:
			return "artillery"
		VietnamWeaponDataScript.WeaponCategory.HELICOPTER_ROCKET:
			return "rocket"
		VietnamWeaponDataScript.WeaponCategory.HELICOPTER_MINIGUN:
			return "heavy_mg"
		VietnamWeaponDataScript.WeaponCategory.AIRCRAFT_GUN:
			return "heavy_mg"
		_:
			return "rifle"


## Load real sound files when available
func load_sounds(profile_name: String, sound_paths: Array) -> void:
	if profile_name in SOUND_PROFILES:
		SOUND_PROFILES[profile_name]["sounds"] = sound_paths
