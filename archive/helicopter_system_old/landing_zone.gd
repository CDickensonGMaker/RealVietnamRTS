extends Node3D
class_name LandingZone
## LandingZone - Helicopter landing area with status tracking

signal lz_status_changed(new_status: int)
signal helicopter_approaching(helicopter: Node3D)
signal helicopter_landed(helicopter: Node3D)
signal helicopter_departed(helicopter: Node3D)

@export var lz_name: String = "LZ Alpha"
@export var lz_size: float = 15.0  # Radius
@export var max_helicopters: int = 2

# Status
var status: int = GameEnums.LZStatus.COLD
var threat_level: float = 0.0  # 0.0 = safe, 1.0 = under heavy fire

# Occupancy
var helicopters_on_ground: Array[Node3D] = []
var helicopters_inbound: Array[Node3D] = []

# Supply tracking
var supplies_delivered: int = 0
var troops_delivered: int = 0
var wounded_evacuated: int = 0

# Smoke/marker
var smoke_active: bool = false
var smoke_color: Color = Color.YELLOW

func _ready() -> void:
	add_to_group("landing_zones")

func _process(delta: float) -> void:
	_update_threat_level(delta)

# =============================================================================
# STATUS
# =============================================================================

func get_status() -> int:
	return status

func get_status_name() -> String:
	match status:
		GameEnums.LZStatus.COLD:
			return "Cold"
		GameEnums.LZStatus.WARM:
			return "Warm"
		GameEnums.LZStatus.HOT:
			return "Hot"
		_:
			return "Unknown"

func set_status(new_status: int) -> void:
	if status != new_status:
		status = new_status
		lz_status_changed.emit(new_status)
		BattleSignals.lz_status_changed.emit(self, new_status)

func get_threat_level() -> float:
	return threat_level

func _update_threat_level(delta: float) -> void:
	# Decay threat level over time
	threat_level = maxf(0.0, threat_level - 0.05 * delta)

	# Check for enemies in area
	var enemies := SpatialHashGrid.get_enemies_in_radius(
		global_position, lz_size * 2, GameEnums.Faction.US_ARMY
	)

	if not enemies.is_empty():
		threat_level = minf(1.0, threat_level + 0.2 * delta * enemies.size())

	# Update status based on threat
	if threat_level > 0.7:
		set_status(GameEnums.LZStatus.HOT)
	elif threat_level > 0.3:
		set_status(GameEnums.LZStatus.WARM)
	else:
		set_status(GameEnums.LZStatus.COLD)

func report_contact() -> void:
	## Report enemy contact at LZ
	threat_level = minf(1.0, threat_level + 0.3)
	_update_threat_level(0)

# =============================================================================
# HELICOPTER MANAGEMENT
# =============================================================================

func is_available() -> bool:
	return helicopters_on_ground.size() < max_helicopters

func get_landing_position() -> Vector3:
	## Get position for helicopter to land
	var offset := Vector3(
		randf_range(-lz_size * 0.3, lz_size * 0.3),
		0,
		randf_range(-lz_size * 0.3, lz_size * 0.3)
	)
	return global_position + offset

func register_inbound(helicopter: Node3D) -> bool:
	if helicopter not in helicopters_inbound:
		helicopters_inbound.append(helicopter)
		helicopter_approaching.emit(helicopter)
		return true
	return false

func register_landed(helicopter: Node3D) -> void:
	helicopters_inbound.erase(helicopter)
	if helicopter not in helicopters_on_ground:
		helicopters_on_ground.append(helicopter)
	helicopter_landed.emit(helicopter)

func register_departure(helicopter: Node3D) -> void:
	helicopters_on_ground.erase(helicopter)
	helicopter_departed.emit(helicopter)

# =============================================================================
# SMOKE MARKERS
# =============================================================================

func pop_smoke(color: Color = Color.YELLOW) -> void:
	## Pop smoke to mark LZ
	smoke_active = true
	smoke_color = color

	# Smoke lasts 60 seconds
	get_tree().create_timer(60.0).timeout.connect(func(): smoke_active = false)

func has_smoke() -> bool:
	return smoke_active

func get_smoke_color() -> Color:
	return smoke_color

# =============================================================================
# STATISTICS
# =============================================================================

func record_supply_delivery(amount: int) -> void:
	supplies_delivered += amount

func record_troop_delivery(count: int) -> void:
	troops_delivered += count

func record_medevac(count: int) -> void:
	wounded_evacuated += count

func get_stats() -> Dictionary:
	return {
		"supplies_delivered": supplies_delivered,
		"troops_delivered": troops_delivered,
		"wounded_evacuated": wounded_evacuated,
	}

# =============================================================================
# LZ TYPE DETECTION
# =============================================================================

func is_landing_zone() -> bool:
	return true

# =============================================================================
# APPROACH VECTORS
# =============================================================================

func get_best_approach_vector() -> Vector3:
	## Calculate safest approach direction avoiding enemy positions

	# Default approach from east (typical)
	var best_direction := Vector3(1, 0, 0)
	var best_threat := INF

	# Check 8 approach directions
	for i in range(8):
		var angle := (TAU / 8) * i
		var direction := Vector3(cos(angle), 0, sin(angle))
		var check_pos := global_position + direction * lz_size * 3

		# Count enemies along this approach
		var enemies := SpatialHashGrid.get_enemies_in_radius(
			check_pos, lz_size * 2, GameEnums.Faction.US_ARMY
		)
		var threat := enemies.size()

		if threat < best_threat:
			best_threat = threat
			best_direction = direction

	return best_direction

func get_approach_waypoints(from_direction: Vector3) -> Array[Vector3]:
	## Get waypoints for helicopter approach

	var waypoints: Array[Vector3] = []

	# Initial approach point (far out)
	var approach_start := global_position + from_direction * 200
	approach_start.y = 100  # High altitude
	waypoints.append(approach_start)

	# Mid approach (descending)
	var mid_approach := global_position + from_direction * 100
	mid_approach.y = 50
	waypoints.append(mid_approach)

	# Final approach (low)
	var final_approach := global_position + from_direction * 30
	final_approach.y = 15
	waypoints.append(final_approach)

	# Landing position
	waypoints.append(get_landing_position())

	return waypoints

func get_departure_waypoints(to_direction: Vector3) -> Array[Vector3]:
	## Get waypoints for helicopter departure

	var waypoints: Array[Vector3] = []

	# Takeoff position
	var takeoff := global_position
	takeoff.y = 5
	waypoints.append(takeoff)

	# Quick climb
	var climb_point := global_position + to_direction * 30
	climb_point.y = 30
	waypoints.append(climb_point)

	# Departure point
	var departure := global_position + to_direction * 150
	departure.y = 80
	waypoints.append(departure)

	return waypoints

# =============================================================================
# SECURITY PERIMETER
# =============================================================================

func get_security_radius() -> float:
	## Required secure radius around LZ
	return lz_size * 3

func is_perimeter_secure() -> bool:
	## Check if security perimeter is clear of enemies
	var enemies := SpatialHashGrid.get_enemies_in_radius(
		global_position, get_security_radius(), GameEnums.Faction.US_ARMY
	)
	return enemies.is_empty()

func get_security_status() -> Dictionary:
	## Detailed security assessment
	var radius := get_security_radius()
	var enemies := SpatialHashGrid.get_enemies_in_radius(
		global_position, radius, GameEnums.Faction.US_ARMY
	)

	var friendlies := SpatialHashGrid.get_friendlies_in_radius(
		global_position, radius, GameEnums.Faction.US_ARMY
	)

	return {
		"secure": enemies.is_empty(),
		"enemy_count": enemies.size(),
		"friendly_count": friendlies.size(),
		"threat_level": threat_level,
		"status": get_status_name(),
		"available": is_available(),
	}

# =============================================================================
# PREP FIRE
# =============================================================================

func request_prep_fire(duration: float = 30.0) -> void:
	## Request artillery prep fire before insertion
	BattleSignals.airstrike_requested.emit(
		GameEnums.AirStrikeType.CLOSE_AIR_SUPPORT,
		global_position
	)

func request_gunship_suppression() -> void:
	## Request gunship suppression of LZ perimeter
	# This would be handled by the helicopter system
	pass

# =============================================================================
# LZ ZONES
# =============================================================================

func get_tree_line_distance() -> float:
	## Estimate distance to tree line / cover

	# Would query terrain system in real implementation
	return lz_size * 2  # Default estimate

func get_ground_slope() -> float:
	## Get ground slope at LZ (affects landing difficulty)
	# Would query terrain in real implementation
	return 0.0  # Flat

func can_support_chinook() -> bool:
	## Check if LZ is large enough for CH-47
	return lz_size >= 25.0

func can_support_multiple_landing() -> bool:
	## Check if LZ supports multiple simultaneous landings
	return max_helicopters >= 2 and lz_size >= 20.0
