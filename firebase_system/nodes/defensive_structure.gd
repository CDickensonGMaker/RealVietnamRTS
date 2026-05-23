class_name DefensiveStructure
extends Node3D
## DefensiveStructure - Auto-firing emplacement that engages enemies
##
## Serves Pillar 5: "The War Continues" - defenses auto-fire while player
## focuses on operations. Examples: MG Nests, Bunkers with crew, Mortar Pits.
##
## Features:
## - Queries enemies via SpatialHashGrid (O(1) neighbor lookups)
## - Fires at closest enemy within weapon range
## - Respects weapon ROF and reload timing
## - Tracks ammo and requires resupply from firebase
## - Integrates with CombatManager for damage resolution

signal target_acquired(target: Node3D)
signal target_lost()
signal weapon_fired(target: Node3D, weapon_id: String)
signal ammo_depleted()
signal ammo_resupplied(amount: int)
signal structure_destroyed()
signal crew_killed()

# =============================================================================
# CONFIGURATION
# =============================================================================

## Faction that owns this structure
@export var owner_faction: int = 0  # GameEnums.Faction.US_ARMY

## Weapon mounted on this structure (matches VietnamWeaponData keys)
@export var weapon_id: String = "m60"

## Structure type for visual/audio selection
enum StructureType { MG_NEST, BUNKER, MORTAR_PIT, WATCHTOWER, GUARD_TOWER }
@export var structure_type: StructureType = StructureType.MG_NEST

## Override weapon range (0 = use weapon default)
@export var range_override: float = 0.0

## Fire arc in degrees (180 = hemisphere, 360 = full rotation)
@export var fire_arc: float = 360.0

## Direction structure faces (degrees, 0 = +Z)
@export var facing_direction: float = 0.0

## Whether structure can rotate after placement (true for artillery)
var can_rotate_post_placement: bool = false

## BuildingData reference (optional, set by construction system)
var building_data: RefCounted = null

# =============================================================================
# AMMO SYSTEM
# =============================================================================

## Current ammunition count
var current_ammo: int = 100

## Maximum ammunition capacity
var max_ammo: int = 100

## Ammo consumed per shot
var ammo_per_shot: int = 1

## Whether structure can fire (has ammo + crew)
var can_fire: bool = true

# =============================================================================
# CREW SYSTEM
# =============================================================================

## Crew required to operate
var crew_required: int = 2

## Current crew count
var current_crew: int = 2

## Whether structure is manned
var is_manned: bool = true

# =============================================================================
# STATE
# =============================================================================

## Current target being engaged
var _current_target: Node3D = null

## Time until next shot allowed (ROF limiter)
var _fire_cooldown: float = 0.0

## Time in current reload cycle
var _reload_timer: float = 0.0

## Whether currently reloading
var _is_reloading: bool = false

## Weapon stats cache
var _weapon_data: RefCounted = null

## Effective weapon range
var _effective_range: float = 500.0

## Structure health
var health: float = 200.0
var max_health: float = 200.0

## Target scan interval (performance optimization)
var _scan_interval: float = 0.5
var _scan_timer: float = 0.0

## Cached autoload references
var _spatial_hash: Node = null
var _combat_manager: Node = null

# =============================================================================
# VISUAL COMPONENTS
# =============================================================================

var _turret_node: Node3D = null
var _muzzle_point: Node3D = null
var _mesh_instance: MeshInstance3D = null

# =============================================================================
# CONSTANTS
# =============================================================================

const STRUCTURE_HEALTH: Dictionary = {
	StructureType.MG_NEST: 150.0,
	StructureType.BUNKER: 400.0,
	StructureType.MORTAR_PIT: 100.0,
	StructureType.WATCHTOWER: 80.0,
	StructureType.GUARD_TOWER: 100.0,
}

const STRUCTURE_AMMO: Dictionary = {
	StructureType.MG_NEST: 200,      # Belt-fed
	StructureType.BUNKER: 300,       # Larger ammo store
	StructureType.MORTAR_PIT: 24,    # Mortar rounds
	StructureType.WATCHTOWER: 60,    # Rifle ammo
	StructureType.GUARD_TOWER: 80,
}

const STRUCTURE_CREW: Dictionary = {
	StructureType.MG_NEST: 2,
	StructureType.BUNKER: 4,
	StructureType.MORTAR_PIT: 3,
	StructureType.WATCHTOWER: 1,
	StructureType.GUARD_TOWER: 2,
}

const DEFAULT_WEAPONS: Dictionary = {
	StructureType.MG_NEST: "m60",
	StructureType.BUNKER: "m2_browning",
	StructureType.MORTAR_PIT: "mortar_81mm",
	StructureType.WATCHTOWER: "m14",
	StructureType.GUARD_TOWER: "m60",
}


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Cache autoload references
	_spatial_hash = get_node_or_null("/root/SpatialHashGrid")
	_combat_manager = get_node_or_null("/root/CombatManager")

	# Initialize from structure type
	_initialize_from_type()

	# Load weapon data
	_load_weapon_data()

	# Add to groups
	add_to_group("defensive_structures")
	add_to_group("all_units")
	add_to_group("buildings")

	# Create visual representation
	_setup_visuals()

	# Register with spatial hash
	_register_with_spatial_hash()

	print("[DefensiveStructure] %s initialized with %s, range %.0fm, ammo %d" % [
		StructureType.keys()[structure_type],
		weapon_id,
		_effective_range,
		current_ammo
	])


func _process(delta: float) -> void:
	if not is_manned or not can_fire:
		return

	# Update timers
	_update_cooldowns(delta)

	# Scan for targets periodically
	_scan_timer += delta
	if _scan_timer >= _scan_interval:
		_scan_timer = 0.0
		_scan_for_targets()

	# Engage current target if valid
	if _current_target and is_instance_valid(_current_target):
		_engage_target(delta)
	elif _current_target:
		_lose_target()


# =============================================================================
# INITIALIZATION
# =============================================================================

func _initialize_from_type() -> void:
	"""Initialize stats based on structure type."""
	max_health = STRUCTURE_HEALTH.get(structure_type, 150.0)
	health = max_health

	max_ammo = STRUCTURE_AMMO.get(structure_type, 100)
	current_ammo = max_ammo

	crew_required = STRUCTURE_CREW.get(structure_type, 2)
	current_crew = crew_required

	# Use default weapon if none specified
	if weapon_id.is_empty():
		weapon_id = DEFAULT_WEAPONS.get(structure_type, "m60")


func initialize_from_building_data(data: RefCounted) -> void:
	"""Initialize structure from BuildingData resource (called by construction system).

	This allows fire arcs and facing direction to be set during placement.
	"""
	building_data = data

	# Read fire arc properties from BuildingData
	if data.get("fire_arc") != null:
		fire_arc = data.fire_arc

	if data.get("weapon_range") != null and data.weapon_range > 0.0:
		range_override = data.weapon_range

	if data.get("initial_facing") != null:
		facing_direction = data.initial_facing

	if data.get("rotatable_post_placement") != null:
		can_rotate_post_placement = data.rotatable_post_placement

	print("[DefensiveStructure] Initialized from BuildingData: arc=%.0f°, facing=%.0f°, rotatable=%s" % [
		fire_arc, facing_direction, can_rotate_post_placement
	])


func rotate_to_face(world_position: Vector3) -> void:
	"""Rotate structure to face a world position (only works for rotatable structures)."""
	if not can_rotate_post_placement:
		return

	var to_target: Vector3 = world_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return

	# Calculate angle to target (0 = +Z, clockwise positive)
	facing_direction = rad_to_deg(atan2(to_target.x, to_target.z))
	print("[DefensiveStructure] Rotated to face %.0f°" % facing_direction)


func rotate_by(degrees: float) -> void:
	"""Rotate structure by a relative angle (only works for rotatable structures)."""
	if not can_rotate_post_placement:
		return

	facing_direction = wrapf(facing_direction + degrees, -180.0, 180.0)


func _load_weapon_data() -> void:
	"""Load weapon stats from VietnamWeaponData."""
	var WeaponData: GDScript = load("res://battle_system/data/vietnam_weapon_data.gd")
	if WeaponData:
		_weapon_data = WeaponData.get_weapon(weapon_id)

	if _weapon_data:
		_effective_range = range_override if range_override > 0.0 else _weapon_data.max_range
		ammo_per_shot = 1 if _weapon_data.fire_pattern == 0 else _weapon_data.burst_count  # SINGLE = 0
	else:
		push_warning("[DefensiveStructure] Unknown weapon: %s, using defaults" % weapon_id)
		_effective_range = range_override if range_override > 0.0 else 500.0


func _register_with_spatial_hash() -> void:
	"""Register this structure with spatial hash for enemy targeting."""
	if _spatial_hash and _spatial_hash.has_method("register_unit"):
		_spatial_hash.register_unit(self, owner_faction)


# =============================================================================
# TARGETING
# =============================================================================

func _scan_for_targets() -> void:
	"""Find the closest enemy within range and fire arc."""
	if not _spatial_hash:
		return

	# Query enemies in range
	var enemies: Array[Node3D] = _spatial_hash.get_enemies_in_radius(
		global_position,
		_effective_range,
		owner_faction
	)

	if enemies.is_empty():
		if _current_target:
			_lose_target()
		return

	# Find closest valid target
	var best_target: Node3D = null
	var best_dist_sq: float = INF

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Check if target is alive
		if not _is_target_valid(enemy):
			continue

		# Check fire arc
		if not _is_in_fire_arc(enemy.global_position):
			continue

		# Check line of sight (skip for mortars - indirect fire)
		if structure_type != StructureType.MORTAR_PIT:
			if not _has_line_of_sight(enemy):
				continue

		var dist_sq: float = global_position.distance_squared_to(enemy.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_target = enemy

	# Update target
	if best_target and best_target != _current_target:
		_acquire_target(best_target)


func _is_target_valid(target: Node3D) -> bool:
	"""Check if target is a valid combat target."""
	# Check if dead
	if target.has_method("get") and target.get("state"):
		if target.state == 5:  # State.DEAD
			return false

	# Check health
	if "current_health" in target:
		if target.current_health <= 0:
			return false
	elif "health" in target:
		if target.health <= 0:
			return false

	return true


func _is_in_fire_arc(target_pos: Vector3) -> bool:
	"""Check if target is within structure's fire arc."""
	if fire_arc >= 360.0:
		return true

	var to_target: Vector3 = target_pos - global_position
	to_target.y = 0
	var angle_to_target: float = rad_to_deg(atan2(to_target.x, to_target.z))

	var angle_diff: float = absf(wrapf(angle_to_target - facing_direction, -180.0, 180.0))
	return angle_diff <= fire_arc * 0.5


func _has_line_of_sight(target: Node3D) -> bool:
	"""Check if we have clear line of sight to target."""
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if not space_state:
		return true  # Assume LOS if no physics

	var muzzle_pos: Vector3
	if is_instance_valid(_muzzle_point):
		muzzle_pos = _muzzle_point.global_position
	else:
		muzzle_pos = global_position + Vector3.UP
	var target_pos: Vector3 = target.global_position + Vector3(0, 1, 0)  # Aim at center mass

	var query := PhysicsRayQueryParameters3D.create(muzzle_pos, target_pos)
	query.collision_mask = 1 | 64  # Terrain + buildings
	query.exclude = [self]

	var result: Dictionary = space_state.intersect_ray(query)

	# No hit = clear LOS, or hit is the target
	if result.is_empty():
		return true

	var hit_collider: Object = result.get("collider")
	return hit_collider == target


func _acquire_target(target: Node3D) -> void:
	"""Lock onto a new target."""
	_current_target = target
	target_acquired.emit(target)

	# Connect to target death signal if available
	if target.has_signal("tree_exiting"):
		if not target.tree_exiting.is_connected(_on_target_destroyed):
			target.tree_exiting.connect(_on_target_destroyed.bind(target))


func _lose_target() -> void:
	"""Lost current target."""
	_current_target = null
	target_lost.emit()


func _on_target_destroyed(target: Node3D) -> void:
	"""Handle target being destroyed."""
	if target == _current_target:
		_lose_target()


# =============================================================================
# COMBAT
# =============================================================================

func _engage_target(delta: float) -> void:
	"""Fire at current target if able."""
	# Can't fire while reloading
	if _is_reloading:
		return

	# Cooldown check
	if _fire_cooldown > 0.0:
		return

	# Ammo check
	if current_ammo <= 0:
		_on_ammo_depleted()
		return

	# Range check (target may have moved)
	var distance: float = global_position.distance_to(_current_target.global_position)
	if distance > _effective_range:
		_lose_target()
		return

	# Rotate turret toward target
	_aim_at_target()

	# Fire!
	_fire_weapon()


func _aim_at_target() -> void:
	"""Rotate turret to face target."""
	if not _turret_node or not _current_target:
		return

	var to_target: Vector3 = _current_target.global_position - global_position
	to_target.y = 0

	if to_target.length_squared() > 0.01:
		var target_angle: float = atan2(to_target.x, to_target.z)
		_turret_node.rotation.y = target_angle


func _fire_weapon() -> void:
	"""Fire the weapon at current target."""
	if not _current_target:
		return

	# Consume ammo
	current_ammo -= ammo_per_shot

	# Set cooldown based on ROF
	if _weapon_data:
		var rof: float = _weapon_data.rate_of_fire
		_fire_cooldown = 60.0 / maxf(rof, 1.0)  # Convert RPM to seconds between shots
	else:
		_fire_cooldown = 0.5  # Default half second

	# Use CombatManager for damage resolution
	if _combat_manager and _combat_manager.has_method("fire_weapon"):
		_combat_manager.fire_weapon(self, _current_target, weapon_id)

	# Emit signal
	weapon_fired.emit(_current_target, weapon_id)

	# Check if out of magazine - need reload
	if _weapon_data and current_ammo > 0:
		var mag_remaining: int = current_ammo % _weapon_data.magazine_size
		if mag_remaining == 0:
			_start_reload()


func _start_reload() -> void:
	"""Begin reload sequence."""
	if not _weapon_data:
		return

	_is_reloading = true
	_reload_timer = _weapon_data.reload_time


func _update_cooldowns(delta: float) -> void:
	"""Update fire and reload cooldowns."""
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta

	if _is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_is_reloading = false
			_reload_timer = 0.0


func _on_ammo_depleted() -> void:
	"""Handle running out of ammo."""
	can_fire = false
	ammo_depleted.emit()

	if BattleSignals:
		BattleSignals.unit_ammo_depleted.emit(self)


# =============================================================================
# RESUPPLY
# =============================================================================

func resupply(amount: int) -> int:
	"""Add ammunition. Returns amount actually added."""
	var space: int = max_ammo - current_ammo
	var actual: int = mini(amount, space)

	if actual > 0:
		current_ammo += actual
		can_fire = is_manned
		ammo_resupplied.emit(actual)

	return actual


func get_ammo_percent() -> float:
	"""Get ammo as percentage (0.0 to 1.0)."""
	if max_ammo <= 0:
		return 0.0
	return float(current_ammo) / float(max_ammo)


func needs_resupply() -> bool:
	"""Check if structure needs resupply."""
	return current_ammo < max_ammo * 0.5


# =============================================================================
# CREW
# =============================================================================

func kill_crew(count: int = 1) -> void:
	"""Kill crew members."""
	current_crew = maxi(current_crew - count, 0)

	if current_crew < crew_required:
		is_manned = false
		can_fire = false
		crew_killed.emit()


func add_crew(count: int = 1) -> void:
	"""Add crew members."""
	current_crew = mini(current_crew + count, crew_required + 2)  # Allow slight overstaffing

	if current_crew >= crew_required:
		is_manned = true
		can_fire = current_ammo > 0


# =============================================================================
# DAMAGE
# =============================================================================

func take_damage(amount: float, source: Node3D = null) -> void:
	"""Apply damage to structure."""
	health -= amount

	if BattleSignals:
		BattleSignals.unit_damaged.emit(self, amount, source)

	# Chance to kill crew on damage
	if randf() < amount / max_health:
		kill_crew(1)

	if health <= 0:
		_destroy()


func _destroy() -> void:
	"""Structure destroyed."""
	structure_destroyed.emit()

	if BattleSignals:
		BattleSignals.unit_died.emit(self, null)

	# Unregister from spatial hash
	if _spatial_hash and _spatial_hash.has_method("unregister_unit"):
		_spatial_hash.unregister_unit(self)

	print("[DefensiveStructure] Destroyed at %s" % global_position)
	queue_free()


# =============================================================================
# VISUALS
# =============================================================================

func _setup_visuals() -> void:
	"""Create visual representation based on structure type."""
	# Create base mesh
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "BaseMesh"
	add_child(_mesh_instance)

	# Create turret node for rotation
	_turret_node = Node3D.new()
	_turret_node.name = "Turret"
	_turret_node.position.y = 0.5
	add_child(_turret_node)

	# Create muzzle point
	_muzzle_point = Node3D.new()
	_muzzle_point.name = "MuzzlePoint"
	_muzzle_point.position.z = 1.0
	_turret_node.add_child(_muzzle_point)

	# Build mesh based on type
	match structure_type:
		StructureType.MG_NEST:
			_create_mg_nest_mesh()
		StructureType.BUNKER:
			_create_bunker_mesh()
		StructureType.MORTAR_PIT:
			_create_mortar_pit_mesh()
		StructureType.WATCHTOWER:
			_create_watchtower_mesh()
		StructureType.GUARD_TOWER:
			_create_guard_tower_mesh()


func _create_mg_nest_mesh() -> void:
	"""Create MG nest visual."""
	# Sandbag ring
	var sandbag_mat := StandardMaterial3D.new()
	sandbag_mat.albedo_color = Color(0.45, 0.4, 0.3)
	sandbag_mat.roughness = 0.9

	var base := CylinderMesh.new()
	base.top_radius = 1.5
	base.bottom_radius = 1.8
	base.height = 0.8
	_mesh_instance.mesh = base
	_mesh_instance.material_override = sandbag_mat

	# Gun mount
	var gun := MeshInstance3D.new()
	var gun_mesh := BoxMesh.new()
	gun_mesh.size = Vector3(0.2, 0.2, 1.2)
	gun.mesh = gun_mesh
	gun.position.z = 0.5

	var gun_mat := StandardMaterial3D.new()
	gun_mat.albedo_color = Color(0.2, 0.2, 0.2)
	gun_mat.metallic = 0.8
	gun.material_override = gun_mat
	_turret_node.add_child(gun)


func _create_bunker_mesh() -> void:
	"""Create bunker visual."""
	var concrete_mat := StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.5, 0.48, 0.45)
	concrete_mat.roughness = 0.85

	var bunker := BoxMesh.new()
	bunker.size = Vector3(4, 1.5, 3)
	_mesh_instance.mesh = bunker
	_mesh_instance.material_override = concrete_mat
	_mesh_instance.position.y = 0.75

	# Firing slit
	var slit := MeshInstance3D.new()
	var slit_mesh := BoxMesh.new()
	slit_mesh.size = Vector3(0.8, 0.2, 0.1)
	slit.mesh = slit_mesh
	slit.position = Vector3(0, 0.5, 1.5)

	var slit_mat := StandardMaterial3D.new()
	slit_mat.albedo_color = Color(0.1, 0.1, 0.1)
	slit.material_override = slit_mat
	_mesh_instance.add_child(slit)


func _create_mortar_pit_mesh() -> void:
	"""Create mortar pit visual."""
	# Circular sandbag wall
	var sandbag_mat := StandardMaterial3D.new()
	sandbag_mat.albedo_color = Color(0.45, 0.4, 0.3)
	sandbag_mat.roughness = 0.9

	var pit := TorusMesh.new()
	pit.inner_radius = 1.0
	pit.outer_radius = 1.5
	pit.rings = 16
	pit.ring_segments = 8
	_mesh_instance.mesh = pit
	_mesh_instance.material_override = sandbag_mat
	_mesh_instance.position.y = 0.25
	_mesh_instance.rotation_degrees.x = 90

	# Mortar tube
	var tube := MeshInstance3D.new()
	var tube_mesh := CylinderMesh.new()
	tube_mesh.top_radius = 0.08
	tube_mesh.bottom_radius = 0.1
	tube_mesh.height = 0.8
	tube.mesh = tube_mesh
	tube.position.y = 0.4
	tube.rotation_degrees.x = -60

	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.25, 0.25, 0.2)
	metal_mat.metallic = 0.7
	tube.material_override = metal_mat
	_turret_node.add_child(tube)


func _create_watchtower_mesh() -> void:
	"""Create watchtower visual."""
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.45, 0.35, 0.25)
	wood_mat.roughness = 0.85

	# Legs
	for i in range(4):
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.15, 4.0, 0.15)
		leg.mesh = leg_mesh
		leg.material_override = wood_mat

		var angle: float = TAU * float(i) / 4.0 + PI / 4.0
		leg.position = Vector3(cos(angle) * 1.2, 2.0, sin(angle) * 1.2)
		add_child(leg)

	# Platform
	var platform := BoxMesh.new()
	platform.size = Vector3(3.0, 0.15, 3.0)
	_mesh_instance.mesh = platform
	_mesh_instance.material_override = wood_mat
	_mesh_instance.position.y = 4.0

	# Move turret to platform height
	_turret_node.position.y = 4.5


func _create_guard_tower_mesh() -> void:
	"""Create guard tower visual (like prison tower)."""
	_create_watchtower_mesh()  # Base is same

	# Add roof
	var roof := MeshInstance3D.new()
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(3.5, 0.1, 3.5)
	roof.mesh = roof_mesh
	roof.position.y = 6.0

	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.3, 0.35, 0.3)
	metal_mat.metallic = 0.6
	roof.material_override = metal_mat
	add_child(roof)


# =============================================================================
# PUBLIC API
# =============================================================================

func get_faction() -> int:
	"""Return owner faction for targeting systems."""
	return owner_faction


func get_weapon_range() -> float:
	"""Return effective weapon range."""
	return _effective_range


func get_current_target() -> Node3D:
	"""Return current engagement target."""
	return _current_target


func is_operational() -> bool:
	"""Check if structure can engage enemies."""
	return is_manned and can_fire and current_ammo > 0 and health > 0


func get_status() -> Dictionary:
	"""Get structure status for UI."""
	return {
		"type": StructureType.keys()[structure_type],
		"weapon": weapon_id,
		"health": health,
		"max_health": max_health,
		"ammo": current_ammo,
		"max_ammo": max_ammo,
		"crew": current_crew,
		"crew_required": crew_required,
		"is_manned": is_manned,
		"can_fire": can_fire,
		"is_reloading": _is_reloading,
		"has_target": _current_target != null,
		"range": _effective_range,
	}


# =============================================================================
# FACTORY
# =============================================================================

static func create(
	world_position: Vector3,
	type: StructureType,
	faction: int = 0,
	weapon: String = ""
) -> DefensiveStructure:
	"""Factory method to create a defensive structure."""
	var structure := DefensiveStructure.new()
	structure.position = world_position
	structure.structure_type = type
	structure.owner_faction = faction
	if not weapon.is_empty():
		structure.weapon_id = weapon
	return structure
