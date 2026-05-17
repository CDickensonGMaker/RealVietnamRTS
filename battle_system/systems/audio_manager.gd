extends Node
class_name AudioManager

## Manages all game audio - voices, weapons, explosions, ambient
## Connects to BattleSignals to play contextual sounds

## Audio pools
var _voice_pool: Array[AudioStreamPlayer] = []
var _sfx_pool: Array[AudioStreamPlayer3D] = []
const VOICE_POOL_SIZE := 4
const SFX_POOL_SIZE := 16

## Sound libraries
var voice_select: Array[AudioStream] = []
var voice_order: Array[AudioStream] = []
var voice_attack: Array[AudioStream] = []
var explosions: Array[AudioStream] = []
var weapon_sounds: Dictionary = {}  # weapon_type -> AudioStream

## Settings
@export var master_volume: float = 1.0
@export var voice_volume: float = 0.8
@export var sfx_volume: float = 1.0

## Cooldowns to prevent sound spam
var _last_voice_time: float = 0.0
const VOICE_COOLDOWN := 0.3


func _ready() -> void:
	_init_audio_pools()
	_load_sounds()
	_connect_signals()
	print("[AudioManager] Initialized with %d voices, %d explosions" % [voice_select.size(), explosions.size()])


func _init_audio_pools() -> void:
	"""Create audio player pools"""
	# Voice pool (2D, for UI responses)
	for i in VOICE_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_voice_pool.append(player)

	# SFX pool (3D, for positional audio)
	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.bus = "Master"
		player.max_distance = 100.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_sfx_pool.append(player)


func _load_sounds() -> void:
	"""Load all sound resources"""
	# Voice - Selection
	_load_sound_array("res://assets/audio/voice/us/US_GEN_Select", 5, voice_select)

	# Voice - Order acknowledged
	_load_sound_array("res://assets/audio/voice/us/US_GEN_OK", 4, voice_order)

	# Explosions
	_load_sound_array("res://assets/audio/weapons/GEN_Explo_", 11, explosions)

	# Weapon sounds (map to weapon types)
	_load_weapon_sounds()


func _load_sound_array(base_path: String, count: int, target: Array[AudioStream]) -> void:
	"""Load numbered sound files into array"""
	for i in range(1, count + 1):
		var path: String = "%s%d.wav" % [base_path, i]
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path)
			if stream:
				target.append(stream)


func _load_weapon_sounds() -> void:
	"""Load weapon-specific sounds"""
	# Map weapon types to sound files
	# These will be loaded if they exist
	var weapon_map: Dictionary = {
		"rifle": "res://assets/audio/weapons/rifle.wav",
		"machinegun": "res://assets/audio/weapons/machinegun.wav",
		"explosion": "res://assets/audio/weapons/GEN_Explo_1.wav",
		"grenade": "res://assets/audio/weapons/GEN_Explo_Grenade.wav",
	}

	for weapon_type in weapon_map:
		var path: String = weapon_map[weapon_type]
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path)
			if stream:
				weapon_sounds[weapon_type] = stream


func _connect_signals() -> void:
	"""Connect to game signals"""
	if not BattleSignals:
		return

	BattleSignals.unit_selected.connect(_on_unit_selected)
	BattleSignals.unit_died.connect(_on_unit_died)
	BattleSignals.unit_damaged.connect(_on_unit_damaged)
	BattleSignals.projectile_impact.connect(_on_projectile_impact)

	# Connect to selection manager if available
	var sel_mgr: Node = get_node_or_null("/root/SelectionManager")
	if sel_mgr and sel_mgr.has_signal("selection_changed"):
		sel_mgr.selection_changed.connect(_on_selection_changed)


func _on_unit_selected(unit: Node3D) -> void:
	"""Play selection voice when unit selected"""
	if not _can_play_voice():
		return

	# Only play for player units
	if unit.has_method("get") and unit.get("is_player_controlled") != null:
		if not unit.is_player_controlled:
			return

	play_voice_random(voice_select)


func _on_selection_changed(_selected: Array) -> void:
	"""Play order voice when selection changes"""
	# Handled by unit_selected
	pass


func _on_unit_died(unit: Node3D, _killer: Node3D) -> void:
	"""Play death sound"""
	if is_instance_valid(unit):
		play_sfx_at(unit.global_position, _get_random(explosions))


func _on_unit_damaged(target: Node3D, damage: float, _source: Node3D) -> void:
	"""Play impact sound when unit takes damage"""
	if is_instance_valid(target):
		# Play explosion for big hits
		if damage > 50 and randf() < 0.3:
			play_sfx_at(target.global_position, _get_random(explosions), 0.5)


func _on_projectile_impact(position: Vector3, damage_type: int) -> void:
	"""Play impact sound at projectile hit location"""
	# damage_type from GameEnums.DamageType
	if damage_type == GameEnums.DamageType.EXPLOSIVE:
		play_explosion_at(position, 1.0)
	elif damage_type == GameEnums.DamageType.ARTILLERY:
		play_explosion_at(position, 1.5)


## Public API

func play_order_voice() -> void:
	"""Play order acknowledged voice"""
	if _can_play_voice():
		play_voice_random(voice_order)


func play_attack_voice() -> void:
	"""Play attack voice"""
	if _can_play_voice() and not voice_attack.is_empty():
		play_voice_random(voice_attack)
	else:
		play_order_voice()


func play_voice_random(sounds: Array[AudioStream]) -> void:
	"""Play a random voice sound"""
	if sounds.is_empty():
		return

	var stream: AudioStream = _get_random(sounds)
	_play_voice(stream)


func play_sfx_at(position: Vector3, stream: AudioStream, volume_scale: float = 1.0) -> void:
	"""Play a 3D positioned sound effect"""
	if not stream:
		return

	var player: AudioStreamPlayer3D = _get_free_sfx_player()
	if player:
		player.stream = stream
		player.global_position = position
		player.volume_db = linear_to_db(sfx_volume * volume_scale * master_volume)
		player.play()


func play_explosion_at(position: Vector3, intensity: float = 1.0) -> void:
	"""Play explosion sound at position"""
	if explosions.is_empty():
		return

	var stream: AudioStream = _get_random(explosions)
	play_sfx_at(position, stream, intensity)


func play_weapon_fire(weapon_type: String, position: Vector3) -> void:
	"""Play weapon firing sound"""
	var stream: AudioStream = null

	# Try specific weapon sound
	if weapon_type in weapon_sounds:
		stream = weapon_sounds[weapon_type]
	# Fallback to generic
	elif "rifle" in weapon_sounds:
		stream = weapon_sounds["rifle"]

	if stream:
		play_sfx_at(position, stream, 0.6)


## Internal helpers

func _play_voice(stream: AudioStream) -> void:
	"""Play voice using 2D player"""
	var player: AudioStreamPlayer = _get_free_voice_player()
	if player:
		player.stream = stream
		player.volume_db = linear_to_db(voice_volume * master_volume)
		player.play()
		_last_voice_time = Time.get_ticks_msec() / 1000.0


func _get_free_voice_player() -> AudioStreamPlayer:
	"""Get an available voice player from pool"""
	for player in _voice_pool:
		if not player.playing:
			return player
	return _voice_pool[0]  # Fallback to first


func _get_free_sfx_player() -> AudioStreamPlayer3D:
	"""Get an available SFX player from pool"""
	for player in _sfx_pool:
		if not player.playing:
			return player
	return _sfx_pool[0]  # Fallback to first


func _can_play_voice() -> bool:
	"""Check if we can play a voice (cooldown)"""
	var current: float = Time.get_ticks_msec() / 1000.0
	return current - _last_voice_time >= VOICE_COOLDOWN


func _get_random(sounds: Array[AudioStream]) -> AudioStream:
	"""Get random sound from array"""
	if sounds.is_empty():
		return null
	return sounds[randi() % sounds.size()]
