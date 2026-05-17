extends Node
## AirSupportManager - Manages air strikes, napalm, CAS, and B-52 strikes
## Accessed globally via AirSupportManager autoload (no class_name needed)

signal sortie_available(strike_type: int)
signal sortie_launched(strike_type: int, target: Vector3)
signal sortie_on_station(aircraft: Node3D, strike_type: int)
signal sortie_complete(strike_type: int)

# Available sorties (replenish over time)
var available_sorties := {
	GameEnums.AirStrikeType.NAPALM_RUN: 3,
	GameEnums.AirStrikeType.CLOSE_AIR_SUPPORT: 5,
	GameEnums.AirStrikeType.ROLLING_THUNDER: 1,
	GameEnums.AirStrikeType.SPOOKY: 2,
	GameEnums.AirStrikeType.ARC_LIGHT: 1,
}

# Sortie cooldowns
var sortie_cooldowns := {
	GameEnums.AirStrikeType.NAPALM_RUN: 120.0,
	GameEnums.AirStrikeType.CLOSE_AIR_SUPPORT: 90.0,
	GameEnums.AirStrikeType.ROLLING_THUNDER: 300.0,
	GameEnums.AirStrikeType.SPOOKY: 180.0,
	GameEnums.AirStrikeType.ARC_LIGHT: 600.0,
}

# Strike parameters
var strike_params := {
	GameEnums.AirStrikeType.NAPALM_RUN: {
		"damage": 150.0, "radius": 25.0, "eta": 30.0,
		"aircraft": "F-4 Phantom", "burns": true, "clears_jungle": true
	},
	GameEnums.AirStrikeType.CLOSE_AIR_SUPPORT: {
		"damage": 100.0, "radius": 15.0, "eta": 20.0,
		"aircraft": "A-1 Skyraider", "burns": false, "clears_jungle": false
	},
	GameEnums.AirStrikeType.ROLLING_THUNDER: {
		"damage": 300.0, "radius": 40.0, "eta": 60.0,
		"aircraft": "B-52 Stratofortress", "burns": false, "clears_jungle": true
	},
	GameEnums.AirStrikeType.SPOOKY: {
		"damage": 30.0, "radius": 50.0, "eta": 45.0,
		"aircraft": "AC-47 Spooky", "burns": false, "clears_jungle": false,
		"loiter_time": 180.0
	},
	GameEnums.AirStrikeType.ARC_LIGHT: {
		"damage": 500.0, "radius": 100.0, "eta": 120.0,
		"aircraft": "B-52 Stratofortress", "burns": false, "clears_jungle": true,
		"terror": true
	},
}

# Active missions
var active_strikes: Array[Dictionary] = []
var cooldown_timers: Dictionary = {}

func _ready() -> void:
	# Initialize cooldown timers
	for strike_type in sortie_cooldowns:
		cooldown_timers[strike_type] = 0.0

func _process(delta: float) -> void:
	# Update cooldowns
	for strike_type in cooldown_timers:
		if cooldown_timers[strike_type] > 0:
			cooldown_timers[strike_type] -= delta
			if cooldown_timers[strike_type] <= 0:
				_replenish_sortie(strike_type)

	# Process active strikes
	_process_active_strikes(delta)

# =============================================================================
# STRIKE REQUESTS
# =============================================================================

func can_call_strike(strike_type: int) -> bool:
	## Check if a strike type is available
	if not WeatherSystem.can_call_air_support():
		return false

	return available_sorties.get(strike_type, 0) > 0

func get_available_strikes() -> Dictionary:
	return available_sorties.duplicate()

func request_airstrike(strike_type: int, target: Vector3,
					   direction: Vector3 = Vector3.FORWARD) -> Dictionary:
	## Request an airstrike at target position
	var result := {
		"success": false,
		"eta": 0.0,
		"reason": "",
	}

	# Check weather
	if not WeatherSystem.can_call_air_support():
		result.reason = "Weather prevents air operations"
		return result

	# Check availability
	if available_sorties.get(strike_type, 0) <= 0:
		result.reason = "No sorties available"
		return result

	# Consume sortie
	available_sorties[strike_type] -= 1

	# Get strike parameters
	var params: Dictionary = strike_params.get(strike_type, {})
	var eta: float = params.get("eta", 30.0)

	# Create strike mission
	var strike := {
		"type": strike_type,
		"target": target,
		"direction": direction,
		"eta": eta,
		"timer": 0.0,
		"phase": "inbound",
		"params": params,
	}

	active_strikes.append(strike)

	# Start cooldown
	cooldown_timers[strike_type] = sortie_cooldowns.get(strike_type, 120.0)

	# Emit signals
	BattleSignals.airstrike_requested.emit(strike_type, target)
	BattleSignals.airstrike_inbound.emit(strike_type, target, eta)
	sortie_launched.emit(strike_type, target)

	result.success = true
	result.eta = eta

	return result

# =============================================================================
# STRIKE PROCESSING
# =============================================================================

func _process_active_strikes(delta: float) -> void:
	var completed: Array[int] = []

	for i in range(active_strikes.size()):
		var strike: Dictionary = active_strikes[i]
		strike.timer += delta

		match strike.phase:
			"inbound":
				if strike.timer >= strike.eta:
					_execute_strike(strike)
					strike.phase = "on_station"
					strike.timer = 0.0

			"on_station":
				var loiter: float = strike.params.get("loiter_time", 0.0)
				if loiter > 0:
					# Loitering aircraft (Spooky)
					_process_loiter(strike, delta)
					if strike.timer >= loiter:
						strike.phase = "rtb"
				else:
					strike.phase = "rtb"

			"rtb":
				completed.append(i)
				_complete_strike(strike)

	# Remove completed strikes
	for i in range(completed.size() - 1, -1, -1):
		active_strikes.remove_at(completed[i])

func _execute_strike(strike: Dictionary) -> void:
	## Execute the air strike
	var target: Vector3 = strike.target
	var params: Dictionary = strike.params
	var damage: float = params.get("damage", 100.0)
	var radius: float = params.get("radius", 20.0)

	# Apply damage
	CombatManager.apply_area_damage(target, radius, damage, 80.0)

	# Napalm effects
	if params.get("burns", false):
		BattleSignals.napalm_impact.emit(target, radius)
		CombatManager.apply_napalm_damage(target, radius)

	# Jungle clearing
	if params.get("clears_jungle", false):
		BattleSignals.jungle_burned.emit(target, radius)
		# TerrainClearingSystem would handle this

	# Terror effect (Arc Light)
	if params.get("terror", false):
		var affected := SpatialHashGrid.get_units_in_radius(target, radius * 2)
		for unit in affected:
			CombatManager.apply_terror(unit, "arc_light")

	BattleSignals.airstrike_delivered.emit(strike.type, target)

func _process_loiter(strike: Dictionary, delta: float) -> void:
	## Process loitering aircraft (Spooky gunship)
	var target: Vector3 = strike.target
	var radius: float = strike.params.get("radius", 50.0)

	# Find enemies in area
	var enemies := SpatialHashGrid.get_enemies_in_radius(
		target, radius, GameEnums.Faction.US_ARMY
	)

	# Apply continuous fire
	for enemy in enemies:
		if is_instance_valid(enemy):
			var damage: float = strike.params.get("damage", 30.0) * delta
			if enemy.has_method("take_damage"):
				enemy.take_damage(damage)
			if enemy.has_method("apply_suppression"):
				enemy.apply_suppression(50.0 * delta)

func _complete_strike(strike: Dictionary) -> void:
	BattleSignals.airstrike_complete.emit(strike.type)
	sortie_complete.emit(strike.type)

func _replenish_sortie(strike_type: int) -> void:
	## Replenish a sortie after cooldown
	var max_sorties := {
		GameEnums.AirStrikeType.NAPALM_RUN: 3,
		GameEnums.AirStrikeType.CLOSE_AIR_SUPPORT: 5,
		GameEnums.AirStrikeType.ROLLING_THUNDER: 2,
		GameEnums.AirStrikeType.SPOOKY: 2,
		GameEnums.AirStrikeType.ARC_LIGHT: 1,
	}

	var max_count: int = max_sorties.get(strike_type, 3)
	if available_sorties.get(strike_type, 0) < max_count:
		available_sorties[strike_type] = available_sorties.get(strike_type, 0) + 1
		sortie_available.emit(strike_type)

# =============================================================================
# UTILITY
# =============================================================================

func get_strike_name(strike_type: int) -> String:
	match strike_type:
		GameEnums.AirStrikeType.NAPALM_RUN:
			return "Napalm Run"
		GameEnums.AirStrikeType.CLOSE_AIR_SUPPORT:
			return "Close Air Support"
		GameEnums.AirStrikeType.ROLLING_THUNDER:
			return "Rolling Thunder"
		GameEnums.AirStrikeType.SPOOKY:
			return "Spooky Gunship"
		GameEnums.AirStrikeType.ARC_LIGHT:
			return "Arc Light"
		_:
			return "Unknown"

func get_eta_for_strike(strike_type: int) -> float:
	var params: Dictionary = strike_params.get(strike_type, {})
	return params.get("eta", 30.0)

func cancel_strike(target: Vector3) -> bool:
	## Cancel a strike if still inbound
	for i in range(active_strikes.size()):
		var strike: Dictionary = active_strikes[i]
		if strike.phase == "inbound" and strike.target.distance_to(target) < 10.0:
			active_strikes.remove_at(i)
			return true
	return false
