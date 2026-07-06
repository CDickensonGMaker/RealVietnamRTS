class_name ThreatHeatmap
extends RefCounted

## Grid-based threat assessment system (spring1944-inspired).
## Tracks firepower concentration across the battlefield for AI decisions.
## Enables smarter retreat, flanking, and positioning behavior.
##
## Ported from BP RTS DARK SHADOWS and adapted for Vietnam RTS squad-based combat.

# Grid parameters
var cell_size: float = 20.0  # Each cell is 20x20 world units (meters)
var cells: Dictionary = {}    # Vector2i -> {us: float, vc: float, nva: float}

# Faction keys match GameEnums.Faction
const FACTION_US := 0      # US_ARMY and ARVN
const FACTION_VC := 1      # Viet Cong
const FACTION_NVA := 2     # North Vietnamese Army

# Decay rate for threat values (per second)
const THREAT_DECAY_RATE: float = 0.15  # Threats decay 15% per second (faster than medieval)


func clear() -> void:
	## Clear all threat data.
	cells.clear()


func update_threat(position: Vector3, faction: int, firepower: float) -> void:
	## Add threat at a position. Called when units occupy/shoot from a location.
	var cell := _world_to_cell(position)
	if cell not in cells:
		cells[cell] = {"us": 0.0, "vc": 0.0, "nva": 0.0}

	var key := _faction_to_key(faction)
	cells[cell][key] += firepower


func set_unit_threat(position: Vector3, faction: int, firepower: float) -> void:
	## Set threat for a unit position (replaces rather than adds).
	var cell := _world_to_cell(position)
	if cell not in cells:
		cells[cell] = {"us": 0.0, "vc": 0.0, "nva": 0.0}

	var key := _faction_to_key(faction)
	cells[cell][key] = maxf(cells[cell][key], firepower)  # Keep highest threat in cell


func get_threat_at(position: Vector3, my_faction: int) -> float:
	## Get enemy threat level at a position (from perspective of my_faction).
	## Returns combined threat from all enemy factions.
	var cell := _world_to_cell(position)
	if cell not in cells:
		return 0.0

	var threat: float = 0.0
	if _is_us_faction(my_faction):
		# US sees VC + NVA as threats
		threat = cells[cell]["vc"] + cells[cell]["nva"]
	else:
		# VC/NVA see US as threat
		threat = cells[cell]["us"]

	return threat


func get_my_strength_at(position: Vector3, my_faction: int) -> float:
	## Get friendly strength at a position.
	var cell := _world_to_cell(position)
	if cell not in cells:
		return 0.0

	if _is_us_faction(my_faction):
		return cells[cell]["us"]
	elif my_faction == GameEnums.Faction.VC:
		return cells[cell]["vc"]
	else:
		return cells[cell]["nva"]


func get_threat_gradient(position: Vector3, my_faction: int) -> Vector3:
	## Get direction pointing AWAY from highest threat (for retreat).
	var cell := _world_to_cell(position)
	var gradient := Vector3.ZERO

	# Sample 8 neighboring cells (Moore neighborhood)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue

			var neighbor := cell + Vector2i(dx, dz)
			var threat := _get_cell_threat(neighbor, my_faction)
			# Point AWAY from threat (negative contribution)
			gradient -= Vector3(float(dx), 0, float(dz)) * threat

	return gradient.normalized() if gradient.length() > 0.1 else Vector3.ZERO


func get_flanking_direction(position: Vector3, target_position: Vector3, my_faction: int) -> Vector3:
	## Get a direction for flanking (perpendicular to direct approach, toward lower threat).
	var direct := (target_position - position)
	direct.y = 0
	direct = direct.normalized()

	# Two perpendicular options
	var flank_left := Vector3(-direct.z, 0, direct.x)
	var flank_right := Vector3(direct.z, 0, -direct.x)

	# Check threat in each direction
	var pos_left := position + flank_left * cell_size
	var pos_right := position + flank_right * cell_size

	var threat_left := get_threat_at(pos_left, my_faction)
	var threat_right := get_threat_at(pos_right, my_faction)

	# Go toward lower threat
	if threat_left < threat_right:
		return flank_left
	elif threat_right < threat_left:
		return flank_right
	else:
		# Equal - pick deterministically based on position
		return flank_left if fmod(position.x + position.z, 2.0) < 1.0 else flank_right


func should_retreat(position: Vector3, my_faction: int, my_firepower: float, hp_ratio: float) -> bool:
	## Check if a unit should retreat based on threat assessment.
	## Returns true if enemy threat > 2x our firepower AND HP < 50%.
	## Vietnam-specific: VC retreat earlier (guerrilla tactics).
	var threat := get_threat_at(position, my_faction)

	# VC retreat more readily (hit-and-run doctrine)
	var retreat_threshold: float = 0.5
	var threat_multiplier: float = 2.0
	if my_faction == GameEnums.Faction.VC:
		retreat_threshold = 0.6  # Retreat at 60% health
		threat_multiplier = 1.5  # Retreat when outnumbered 1.5x

	return threat > my_firepower * threat_multiplier and hp_ratio < retreat_threshold


func get_safest_retreat_position(position: Vector3, my_faction: int, search_radius: float = 60.0) -> Vector3:
	## Find safest nearby position to retreat to.
	## VC retreats toward tunnels/jungle, US retreats toward firebase.
	var retreat_pos: Vector3

	var gradient := get_threat_gradient(position, my_faction)
	if gradient.length() > 0.1:
		retreat_pos = position + gradient * search_radius
	else:
		# No threat gradient - use faction-specific retreat direction
		var retreat_dir: Vector3
		if _is_us_faction(my_faction):
			# US retreats south (toward firebase/base camp)
			retreat_dir = Vector3(0, 0, 1)  # +Z is south
		else:
			# VC/NVA retreats north (toward jungle/Cambodia)
			retreat_dir = Vector3(0, 0, -1)  # -Z is north
		retreat_pos = position + retreat_dir * search_radius

	return retreat_pos


func decay_threats(delta: float) -> void:
	## Decay all threat values over time. Call once per AI tick (not per frame).
	var decay_factor := 1.0 - (THREAT_DECAY_RATE * delta)
	var cells_to_remove: Array[Vector2i] = []

	for cell in cells:
		cells[cell]["us"] *= decay_factor
		cells[cell]["vc"] *= decay_factor
		cells[cell]["nva"] *= decay_factor

		# Remove empty cells to prevent unbounded growth
		var total: float = cells[cell]["us"] + cells[cell]["vc"] + cells[cell]["nva"]
		if total < 0.1:
			cells_to_remove.append(cell)

	for cell in cells_to_remove:
		cells.erase(cell)


func update_from_squads(squads: Array) -> void:
	## Update heatmap from all active squads.
	## Call this periodically (e.g., every 0.5s) from AI tick manager.
	for squad in squads:
		if not is_instance_valid(squad):
			continue
		if squad.is_dead():
			continue

		# Calculate firepower based on squad strength and weapons
		var firepower := _calculate_squad_firepower(squad)
		var faction: int = squad.data.faction if squad.data else GameEnums.Faction.VC

		set_unit_threat(squad.global_position, faction, firepower)


func _calculate_squad_firepower(squad) -> float:
	## Calculate effective firepower of a squad.
	## Based on unit count, weapon damage, and current health.
	var base_power: float = 0.0

	# Get weapon data if available
	if squad.has_method("get_weapon_data"):
		var weapon = squad.get_weapon_data()
		if weapon:
			base_power = weapon.damage * weapon.rate_of_fire / 60.0  # DPS
	else:
		# Fallback: estimate from squad type
		base_power = 50.0  # Default firepower

	# Scale by squad size ratio
	var size_ratio: float = 1.0
	if squad.has_method("get_size_ratio"):
		size_ratio = squad.get_size_ratio()
	elif "current_soldiers" in squad and "max_soldiers" in squad:
		if squad.max_soldiers > 0:
			size_ratio = float(squad.current_soldiers) / float(squad.max_soldiers)

	base_power *= size_ratio

	# Suppressed units have reduced effective firepower
	if squad.has_method("get_suppression_level"):
		var suppression: float = squad.get_suppression_level()
		base_power *= (1.0 - suppression * 0.5)  # Up to 50% reduction when fully suppressed

	return base_power


func _world_to_cell(position: Vector3) -> Vector2i:
	## Convert world position to cell coordinates.
	return Vector2i(int(position.x / cell_size), int(position.z / cell_size))


func _cell_to_world(cell: Vector2i) -> Vector3:
	## Convert cell to world position (center of cell).
	return Vector3(float(cell.x) * cell_size + cell_size * 0.5, 0, float(cell.y) * cell_size + cell_size * 0.5)


func _get_cell_threat(cell: Vector2i, my_faction: int) -> float:
	## Get threat in a specific cell.
	if cell not in cells:
		return 0.0

	if _is_us_faction(my_faction):
		return cells[cell]["vc"] + cells[cell]["nva"]
	else:
		return cells[cell]["us"]


func _faction_to_key(faction: int) -> String:
	## Convert faction enum to cell dictionary key.
	if _is_us_faction(faction):
		return "us"
	elif faction == GameEnums.Faction.VC:
		return "vc"
	else:
		return "nva"


func _is_us_faction(faction: int) -> bool:
	## Check if faction is US/ARVN (player-controlled).
	return faction == GameEnums.Faction.US_ARMY or faction == GameEnums.Faction.ARVN


# --- DEBUG ---

func get_debug_info() -> Dictionary:
	## Get debug info about current heatmap state.
	var total_us_threat := 0.0
	var total_vc_threat := 0.0
	var total_nva_threat := 0.0
	var cell_count := cells.size()

	for cell in cells:
		total_us_threat += cells[cell]["us"]
		total_vc_threat += cells[cell]["vc"]
		total_nva_threat += cells[cell]["nva"]

	return {
		"cell_count": cell_count,
		"total_us_threat": total_us_threat,
		"total_vc_threat": total_vc_threat,
		"total_nva_threat": total_nva_threat,
		"cell_size": cell_size
	}


func get_threat_visualization() -> Array[Dictionary]:
	## Get array of threat data for debug visualization.
	## Each entry: {position: Vector3, us: float, vc: float, nva: float}
	var result: Array[Dictionary] = []
	for cell in cells:
		result.append({
			"position": _cell_to_world(cell),
			"us": cells[cell]["us"],
			"vc": cells[cell]["vc"],
			"nva": cells[cell]["nva"]
		})
	return result
