extends Node
## WeatherSystem - Manages weather conditions and their gameplay effects
## Accessed globally via WeatherSystem autoload (no class_name needed)

signal weather_changing(new_weather: int, transition_time: float)
signal time_advancing(new_hour: float)

# Current state
var current_weather: int = GameEnums.WeatherCondition.CLEAR
var time_of_day: float = 8.0  # 0.0 to 24.0 (starts at 0800)
var visibility_modifier: float = 1.0

# Weather duration
var weather_timer: float = 0.0
var weather_duration: float = 300.0  # 5 minutes base

# Time progression
var time_scale: float = 60.0  # 1 real second = 1 game minute
var is_time_paused: bool = false

# Weather probabilities by season
var monsoon_season: bool = false  # May-October

func _ready() -> void:
	_update_visibility()

func _process(delta: float) -> void:
	if is_time_paused:
		return

	# Progress time
	time_of_day += (delta * time_scale) / 3600.0
	if time_of_day >= 24.0:
		time_of_day -= 24.0

	BattleSignals.time_of_day_changed.emit(time_of_day)

	# Weather duration
	weather_timer -= delta
	if weather_timer <= 0:
		_roll_weather_change()

# =============================================================================
# WEATHER EFFECTS
# =============================================================================

func get_weather_effects() -> Dictionary:
	## Get current weather effects on gameplay
	var effects := {
		"visibility": 1.0,
		"air_support_available": true,
		"air_support_accuracy": 1.0,
		"artillery_accuracy": 1.0,
		"movement_speed": 1.0,
		"vc_morale_bonus": 0.0,
		"detection_range": 1.0,
		"flares_needed": false,
	}

	# Apply weather effects
	match current_weather:
		GameEnums.WeatherCondition.CLEAR:
			pass  # No modifications

		GameEnums.WeatherCondition.OVERCAST:
			effects.air_support_accuracy = 0.8
			effects.visibility = 0.9

		GameEnums.WeatherCondition.MONSOON:
			effects.visibility = 0.5
			effects.air_support_available = false
			effects.artillery_accuracy = 0.6
			effects.movement_speed = 0.7
			effects.vc_morale_bonus = 20.0
			effects.detection_range = 0.5

		GameEnums.WeatherCondition.FOG:
			effects.visibility = 0.3
			effects.air_support_available = false
			effects.air_support_accuracy = 0.0
			effects.artillery_accuracy = 0.5
			effects.detection_range = 0.3

		GameEnums.WeatherCondition.NIGHT:
			effects.visibility = 0.2
			effects.air_support_accuracy = 0.5
			effects.vc_morale_bonus = 30.0
			effects.detection_range = 0.2
			effects.flares_needed = true

	# Night modifier
	if is_night():
		effects.visibility *= 0.3
		effects.detection_range *= 0.4
		effects.flares_needed = true
		effects.vc_morale_bonus += 20.0

	return effects

func is_night() -> bool:
	return time_of_day < 6.0 or time_of_day > 19.0

func can_call_air_support() -> bool:
	var effects := get_weather_effects()
	return effects.air_support_available

func get_visibility() -> float:
	return visibility_modifier

func get_time_string() -> String:
	var hours := int(time_of_day)
	var minutes := int((time_of_day - hours) * 60)
	return "%02d:%02d" % [hours, minutes]

func get_weather_name() -> String:
	match current_weather:
		GameEnums.WeatherCondition.CLEAR:
			return "Clear"
		GameEnums.WeatherCondition.OVERCAST:
			return "Overcast"
		GameEnums.WeatherCondition.MONSOON:
			return "Monsoon"
		GameEnums.WeatherCondition.FOG:
			return "Fog"
		GameEnums.WeatherCondition.NIGHT:
			return "Night"
		_:
			return "Unknown"

# =============================================================================
# WEATHER CHANGES
# =============================================================================

func set_weather(new_weather: int, transition_time: float = 30.0) -> void:
	var old_weather := current_weather
	current_weather = new_weather

	weather_changing.emit(new_weather, transition_time)
	BattleSignals.weather_changed.emit(old_weather, new_weather)

	_update_visibility()
	_set_weather_duration()

func _roll_weather_change() -> void:
	## Randomly change weather based on probabilities
	var roll := randf()

	if monsoon_season:
		# Higher chance of rain during monsoon
		if roll < 0.3:
			set_weather(GameEnums.WeatherCondition.MONSOON)
		elif roll < 0.5:
			set_weather(GameEnums.WeatherCondition.OVERCAST)
		elif roll < 0.6:
			set_weather(GameEnums.WeatherCondition.FOG)
		else:
			set_weather(GameEnums.WeatherCondition.CLEAR)
	else:
		# Dry season
		if roll < 0.1:
			set_weather(GameEnums.WeatherCondition.MONSOON)
		elif roll < 0.25:
			set_weather(GameEnums.WeatherCondition.OVERCAST)
		elif roll < 0.35:
			set_weather(GameEnums.WeatherCondition.FOG)
		else:
			set_weather(GameEnums.WeatherCondition.CLEAR)

func _set_weather_duration() -> void:
	match current_weather:
		GameEnums.WeatherCondition.CLEAR:
			weather_duration = randf_range(300.0, 600.0)
		GameEnums.WeatherCondition.OVERCAST:
			weather_duration = randf_range(180.0, 300.0)
		GameEnums.WeatherCondition.MONSOON:
			weather_duration = randf_range(120.0, 240.0)
		GameEnums.WeatherCondition.FOG:
			weather_duration = randf_range(60.0, 120.0)
		_:
			weather_duration = 300.0

	weather_timer = weather_duration

func _update_visibility() -> void:
	var effects := get_weather_effects()
	visibility_modifier = effects.visibility
	BattleSignals.visibility_changed.emit(visibility_modifier)

# =============================================================================
# TIME CONTROL
# =============================================================================

func set_time(hour: float) -> void:
	time_of_day = clampf(hour, 0.0, 24.0)
	time_advancing.emit(time_of_day)

func pause_time() -> void:
	is_time_paused = true

func resume_time() -> void:
	is_time_paused = false

func set_time_scale(scale: float) -> void:
	time_scale = maxf(0.0, scale)

# =============================================================================
# ILLUMINATION
# =============================================================================

func fire_flare(position: Vector3, duration: float = 60.0) -> void:
	## Fire illumination flare at position
	# This would create a temporary light source
	# and improve visibility in the area
	pass

func call_illumination_mission(position: Vector3) -> void:
	## Request aircraft illumination
	if not can_call_air_support():
		return

	# Continuous illumination from aircraft
	fire_flare(position, 300.0)
