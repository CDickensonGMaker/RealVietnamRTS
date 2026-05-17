extends Node
## CoverSystem - Manages cover positions, damage reduction, and cover detection
## Accessed globally via CoverSystem autoload (no class_name needed)

signal cover_position_registered(position: Vector3, cover_type: String)
signal cover_destroyed(position: Vector3)
signal unit_entered_cover(unit: Node3D, cover_type: String)
signal unit_left_cover(unit: Node3D)

# =============================================================================
# COVER TYPES
# =============================================================================

enum CoverType {
	NONE,
	LIGHT,      # Elephant grass, light vegetation, debris
	MEDIUM,     # Foxhole, sandbags, low wall, crater
	HEAVY,      # Bunker, building, tank hull
	FORTIFIED,  # Hardened bunker, reinforced position
}

const COVER_STATS: Dictionary = {
	CoverType.NONE: {
		"damage_reduction": 0.0,
		"accuracy_penalty": 0.0,
		"suppression_reduction": 0.0,
		"concealment": 0.0,
	},
	CoverType.LIGHT: {
		"damage_reduction": 0.25,
		"accuracy_penalty": 0.1,     # Firing from cover is slightly harder
		"suppression_reduction": 0.2,
		"concealment": 0.3,
	},
	CoverType.MEDIUM: {
		"damage_reduction": 0.50,
		"accuracy_penalty": 0.15,
		"suppression_reduction": 0.4,
		"concealment": 0.5,
	},
	CoverType.HEAVY: {
		"damage_reduction": 0.75,
		"accuracy_penalty": 0.2,
		"suppression_reduction": 0.7,
		"concealment": 0.6,
	},
	CoverType.FORTIFIED: {
		"damage_reduction": 0.90,
		"accuracy_penalty": 0.25,
		"suppression_reduction": 0.9,
		"concealment": 0.7,
	},
}

# Cover direction matters - can be flanked
const COVER_ARC_DEGREES := 120.0  # Cover protects 120 degree arc

# =============================================================================
# STATE
# =============================================================================

# Registered cover positions in the world
var cover_positions: Dictionary = {}  # position_key -> CoverData

# Units currently in cover
var units_in_cover: Dictionary = {}  # unit -> CoverData

# =============================================================================
# PUBLIC API
# =============================================================================

func register_cover(position: Vector3, cover_type: CoverType,
					facing: Vector3 = Vector3.ZERO,
					capacity: int = 4) -> void:
	## Register a cover position in the world
	var key := _position_to_key(position)
	cover_positions[key] = {
		"position": position,
		"type": cover_type,
		"facing": facing.normalized() if facing != Vector3.ZERO else Vector3.FORWARD,
		"capacity": capacity,
		"occupants": [],
		"health": 100.0,
	}
	cover_position_registered.emit(position, CoverType.keys()[cover_type])


func unregister_cover(position: Vector3) -> void:
	## Remove a cover position (destroyed)
	var key := _position_to_key(position)
	if cover_positions.has(key):
		var data: Dictionary = cover_positions[key]
		# Kick out any occupants
		for unit in data.occupants:
			if is_instance_valid(unit):
				_remove_unit_from_cover(unit)
		cover_positions.erase(key)
		cover_destroyed.emit(position)


func get_cover_at_position(position: Vector3, search_radius: float = 5.0) -> Dictionary:
	## Find best cover near a position
	var best_cover: Dictionary = {}
	var best_score := -INF

	for key in cover_positions:
		var data: Dictionary = cover_positions[key]
		var dist := position.distance_to(data.position)
		if dist <= search_radius:
			var score := _calculate_cover_score(data, dist)
			if score > best_score:
				best_score = score
				best_cover = data

	return best_cover


func enter_cover(unit: Node3D, cover_position: Vector3) -> bool:
	## Try to enter cover at position
	var key := _position_to_key(cover_position)
	if not cover_positions.has(key):
		return false

	var data: Dictionary = cover_positions[key]

	# Check capacity
	if data.occupants.size() >= data.capacity:
		return false

	# Remove from any current cover
	if units_in_cover.has(unit):
		leave_cover(unit)

	# Enter new cover
	data.occupants.append(unit)
	units_in_cover[unit] = data

	unit_entered_cover.emit(unit, CoverType.keys()[data.type])
	return true


func leave_cover(unit: Node3D) -> void:
	## Leave current cover
	_remove_unit_from_cover(unit)


func get_unit_cover(unit: Node3D) -> Dictionary:
	## Get cover data for a unit
	return units_in_cover.get(unit, {})


func get_unit_cover_type(unit: Node3D) -> CoverType:
	## Get cover type enum for unit
	var data: Dictionary = units_in_cover.get(unit, {})
	return data.get("type", CoverType.NONE)


func is_unit_in_cover(unit: Node3D) -> bool:
	return units_in_cover.has(unit)


# =============================================================================
# DAMAGE CALCULATION HELPERS
# =============================================================================

func calculate_cover_effectiveness(unit: Node3D, attacker_position: Vector3) -> float:
	## Calculate how effective cover is against an attack from a direction
	## Returns 0.0 to 1.0 (1.0 = full cover protection)

	if not units_in_cover.has(unit):
		return 0.0

	var cover_data: Dictionary = units_in_cover[unit]
	var cover_type: CoverType = cover_data.type
	var cover_facing: Vector3 = cover_data.facing
	var cover_pos: Vector3 = cover_data.position

	# Direction from attacker to unit
	var attack_dir := (unit.global_position - attacker_position).normalized()

	# Check if attack is within cover arc
	var angle := rad_to_deg(acos(clampf(attack_dir.dot(-cover_facing), -1.0, 1.0)))

	if angle > COVER_ARC_DEGREES / 2.0:
		# Flanked! Cover provides no protection
		return 0.0

	# Full protection within arc
	var base_reduction: float = COVER_STATS[cover_type].damage_reduction

	# Reduce effectiveness at arc edges
	var arc_falloff := 1.0 - (angle / (COVER_ARC_DEGREES / 2.0)) * 0.3

	return base_reduction * arc_falloff


func get_damage_reduction(unit: Node3D, attacker_position: Vector3) -> float:
	## Get damage reduction multiplier (0.0 to 1.0, higher = more damage blocked)
	return calculate_cover_effectiveness(unit, attacker_position)


func get_suppression_reduction(unit: Node3D) -> float:
	## Get suppression reduction based on cover
	var cover_type := get_unit_cover_type(unit)
	return COVER_STATS.get(cover_type, COVER_STATS[CoverType.NONE]).suppression_reduction


func get_accuracy_penalty(unit: Node3D) -> float:
	## Get accuracy penalty for firing from cover
	var cover_type := get_unit_cover_type(unit)
	return COVER_STATS.get(cover_type, COVER_STATS[CoverType.NONE]).accuracy_penalty


func get_concealment_bonus(unit: Node3D) -> float:
	## Get concealment bonus from cover
	var cover_type := get_unit_cover_type(unit)
	return COVER_STATS.get(cover_type, COVER_STATS[CoverType.NONE]).concealment


# =============================================================================
# COVER QUERIES
# =============================================================================

func find_cover_toward(position: Vector3, threat_direction: Vector3,
					   search_radius: float = 30.0) -> Vector3:
	## Find cover that protects against threat from direction
	var best_pos := Vector3.ZERO
	var best_score := -INF

	for key in cover_positions:
		var data: Dictionary = cover_positions[key]
		var dist := position.distance_to(data.position)

		if dist > search_radius:
			continue

		if data.occupants.size() >= data.capacity:
			continue

		# Score based on cover type and how well it faces the threat
		var cover_facing: Vector3 = data.facing
		var alignment := cover_facing.dot(-threat_direction.normalized())

		if alignment < 0.3:  # Cover doesn't face threat well
			continue

		var type_score: float = data.type * 20.0  # Higher cover type = better
		var distance_score := 30.0 - dist  # Closer is better
		var alignment_score := alignment * 20.0  # Better alignment = better

		var total_score := type_score + distance_score + alignment_score

		if total_score > best_score:
			best_score = total_score
			best_pos = data.position

	return best_pos


func get_all_cover_in_radius(center: Vector3, radius: float) -> Array[Dictionary]:
	## Get all cover positions within radius
	var result: Array[Dictionary] = []

	for key in cover_positions:
		var data: Dictionary = cover_positions[key]
		if center.distance_to(data.position) <= radius:
			result.append(data)

	return result


# =============================================================================
# DYNAMIC COVER
# =============================================================================

func register_structure_cover(structure: Node3D) -> void:
	## Auto-register cover around a structure
	if not is_instance_valid(structure):
		return

	var cover_type := CoverType.MEDIUM
	var capacity := 4

	# Determine cover type based on structure
	if structure.has_method("get_building_type"):
		var building_type: int = structure.get_building_type()
		match building_type:
			GameEnums.BuildingType.SANDBAG_WALL:
				cover_type = CoverType.MEDIUM
				capacity = 6
			GameEnums.BuildingType.BUNKER:
				cover_type = CoverType.HEAVY
				capacity = 8
			GameEnums.BuildingType.MACHINE_GUN_NEST:
				cover_type = CoverType.HEAVY
				capacity = 2
			GameEnums.BuildingType.MORTAR_PIT:
				cover_type = CoverType.MEDIUM
				capacity = 4

	# Register cover on each side of structure
	var pos := structure.global_position
	var directions: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]

	for dir in directions:
		var cover_pos: Vector3 = pos + dir * 2.0
		register_cover(cover_pos, cover_type, -dir, capacity / 4)


func register_crater_cover(position: Vector3, radius: float) -> void:
	## Register a crater as cover (from explosions)
	var cover_type := CoverType.MEDIUM if radius >= 3.0 else CoverType.LIGHT
	var capacity := int(radius * 2)

	# Craters provide 360 degree cover (all directions)
	register_cover(position, cover_type, Vector3.ZERO, capacity)


func damage_cover(position: Vector3, damage: float) -> void:
	## Apply damage to cover at position
	var key := _position_to_key(position)
	if not cover_positions.has(key):
		return

	var data: Dictionary = cover_positions[key]
	data.health -= damage

	if data.health <= 0:
		unregister_cover(position)
		BattleSignals.cover_destroyed.emit(position)


# =============================================================================
# INTERNAL HELPERS
# =============================================================================

func _position_to_key(position: Vector3) -> String:
	## Convert position to dictionary key
	return "%d_%d_%d" % [int(position.x), int(position.y), int(position.z)]


func _calculate_cover_score(data: Dictionary, distance: float) -> float:
	var type_score: float = data.type * 25.0
	var dist_score: float = maxf(0.0, 10.0 - distance)
	var capacity_score: float = (data.capacity - data.occupants.size()) * 5.0
	return type_score + dist_score + capacity_score


func _remove_unit_from_cover(unit: Node3D) -> void:
	if not units_in_cover.has(unit):
		return

	var data: Dictionary = units_in_cover[unit]
	data.occupants.erase(unit)
	units_in_cover.erase(unit)

	unit_left_cover.emit(unit)


# =============================================================================
# TERRAIN-BASED COVER
# =============================================================================

func get_terrain_cover(position: Vector3) -> CoverType:
	## Get natural cover from terrain at position
	var terrain_type := GameEnums.TerrainType.SINGLE_CANOPY

	# Interface with terrain system if available
	if TerrainClearingSystem and TerrainClearingSystem.has_method("get_terrain_type_at"):
		terrain_type = TerrainClearingSystem.get_terrain_type_at(position)

	match terrain_type:
		GameEnums.TerrainType.TRIPLE_CANOPY_JUNGLE:
			return CoverType.MEDIUM
		GameEnums.TerrainType.SINGLE_CANOPY:
			return CoverType.LIGHT
		GameEnums.TerrainType.BAMBOO:
			return CoverType.LIGHT
		GameEnums.TerrainType.ELEPHANT_GRASS:
			return CoverType.LIGHT
		GameEnums.TerrainType.RICE_PADDY:
			return CoverType.NONE
		GameEnums.TerrainType.CLEARED_FIREBASE:
			return CoverType.NONE
		_:
			return CoverType.NONE
