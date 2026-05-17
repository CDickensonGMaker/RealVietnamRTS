class_name Projectile extends Node3D

## Vietnam-era projectile for bullets, rockets, grenades, shells, and napalm.
## Uses object pooling for performance with high volume of fire.
## Adapted from BP_RTS_Dark_Shadows for modern firearm combat.

signal impact(position: Vector3, target: Node)
signal expired

const VietnamWeaponDataScript = preload("res://battle_system/data/vietnam_weapon_data.gd")
const DamageSystemScript = preload("res://terrain/systems/damage_system.gd")

enum ProjectileType {
	BULLET,         # Fast, direct, tracer trail
	ROCKET,         # Medium speed, smoke trail, AOE
	GRENADE,        # Arcing, tumbling, AOE
	SHELL,          # Artillery/mortar, high arc, AOE
	NAPALM,         # Fire spread, persistent damage
	BOMB,           # Diving, large AOE
}

## Core flight properties
var velocity: Vector3 = Vector3.ZERO
var gravity: float = 9.8
var lifetime: float = 2.0
var elapsed_time: float = 0.0

## Damage properties
var damage: float = 15.0
var damage_type: int = VietnamWeaponDataScript.DamageType.KINETIC
var aoe_radius: float = 0.0
var aoe_falloff: bool = true
var suppression: float = 5.0
var suppression_radius: float = 0.0

## Pierce properties
var max_pierces: int = 0
var pierce_count: int = 0
var pierce_falloff: float = 0.3

## Anti-armor properties
var armor_penetration: float = 0.0
var anti_vehicle_bonus: float = 0.0

## Targeting
var source: Node = null
var source_faction: int = 0
var target_position: Vector3 = Vector3.ZERO
var target_node: Node = null

## Trajectory
var trajectory: int = VietnamWeaponDataScript.Trajectory.FLAT
var arc_height: float = 0.0
var start_position: Vector3 = Vector3.ZERO
var total_distance: float = 0.0

## Visual
var projectile_type: ProjectileType = ProjectileType.BULLET
var is_tracer: bool = false
var trail_enabled: bool = true

## Weapon category for terrain damage mapping
var weapon_category: int = -1

## Pooling
var _is_active: bool = false

## Components
var _mesh: MeshInstance3D = null
var _trail: GPUParticles3D = null
var _area: Area3D = null


func _ready() -> void:
	_setup_visuals()
	_setup_collision()
	set_physics_process(false)


func _setup_visuals() -> void:
	# Create mesh for projectile
	_mesh = MeshInstance3D.new()

	# Default bullet mesh (small elongated sphere)
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.15
	_mesh.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.7, 0.3)  # Brass
	mat.emission_enabled = false
	_mesh.material_override = mat

	add_child(_mesh)

	# Create trail particles
	_trail = GPUParticles3D.new()
	_trail.emitting = false
	_trail.amount = 20
	_trail.lifetime = 0.3
	_trail.explosiveness = 0.0
	_trail.local_coords = false

	var trail_mat := ParticleProcessMaterial.new()
	trail_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	trail_mat.direction = Vector3(0, 0, -1)
	trail_mat.spread = 5.0
	trail_mat.initial_velocity_min = 0.0
	trail_mat.initial_velocity_max = 0.0
	trail_mat.gravity = Vector3.ZERO
	trail_mat.scale_min = 0.02
	trail_mat.scale_max = 0.05
	trail_mat.color = Color(0.8, 0.6, 0.3, 0.8)
	_trail.process_material = trail_mat

	var trail_mesh := SphereMesh.new()
	trail_mesh.radius = 0.02
	trail_mesh.height = 0.04
	_trail.draw_pass_1 = trail_mesh

	add_child(_trail)


func _setup_collision() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2 | 4 | 8  # Units on layers 2, 4, 8
	_area.monitoring = true
	_area.monitorable = false

	var shape := SphereShape3D.new()
	shape.radius = 0.5
	var collision := CollisionShape3D.new()
	collision.shape = shape
	_area.add_child(collision)

	_area.body_entered.connect(_on_body_entered)
	add_child(_area)


func _physics_process(delta: float) -> void:
	if not _is_active:
		return

	elapsed_time += delta

	# Check lifetime
	if elapsed_time >= lifetime:
		_expire()
		return

	# Move projectile based on trajectory
	match trajectory:
		VietnamWeaponDataScript.Trajectory.FLAT:
			_process_flat_trajectory(delta)
		VietnamWeaponDataScript.Trajectory.ARCING:
			_process_arcing_trajectory(delta)
		VietnamWeaponDataScript.Trajectory.HIGH_ARC:
			_process_high_arc_trajectory(delta)
		VietnamWeaponDataScript.Trajectory.DIVING:
			_process_diving_trajectory(delta)
		VietnamWeaponDataScript.Trajectory.NAPALM:
			_process_napalm_trajectory(delta)

	# Check ground collision
	if global_position.y <= 0.0:
		global_position.y = 0.0
		_on_ground_impact()


func _process_flat_trajectory(delta: float) -> void:
	# Direct line with slight drop
	velocity.y -= gravity * 0.1 * delta  # Minimal drop for bullets
	global_position += velocity * delta

	# Face velocity direction
	if velocity.length_squared() > 0.01:
		look_at(global_position + velocity, Vector3.UP)


func _process_arcing_trajectory(delta: float) -> void:
	# Parabolic arc for grenades/rockets
	velocity.y -= gravity * delta
	global_position += velocity * delta

	if velocity.length_squared() > 0.01:
		look_at(global_position + velocity, Vector3.UP)


func _process_high_arc_trajectory(_delta: float) -> void:
	# High arc for mortars/artillery
	if total_distance <= 0:
		total_distance = start_position.distance_to(target_position)

	var progress: float = clampf(elapsed_time * velocity.length() / maxf(total_distance, 1.0), 0.0, 1.0)

	# Parabolic height
	var height_offset: float = arc_height * 4.0 * progress * (1.0 - progress)

	# Lerp horizontal position
	var horizontal: Vector3 = start_position.lerp(target_position, progress)
	global_position = Vector3(horizontal.x, start_position.y + height_offset, horizontal.z)

	# Point downward as it descends
	if progress > 0.5:
		var look_target: Vector3 = target_position
		look_target.y = 0.0
		var current_flat: Vector3 = global_position
		current_flat.y = 0.0
		if current_flat.distance_to(look_target) > 0.1:
			var dir: Vector3 = (look_target - current_flat).normalized()
			dir.y = -1.0 * (progress - 0.5) * 2.0
			look_at(global_position + dir, Vector3.UP)


func _process_diving_trajectory(delta: float) -> void:
	# Aircraft bombing run - steep descent
	velocity.y -= gravity * 0.5 * delta
	global_position += velocity * delta

	if velocity.length_squared() > 0.01:
		look_at(global_position + velocity, Vector3.UP)


func _process_napalm_trajectory(delta: float) -> void:
	# Napalm tumbles and spreads
	velocity.y -= gravity * 0.3 * delta
	global_position += velocity * delta

	# Tumble rotation
	rotation.x += delta * 2.0
	rotation.z += delta * 1.5


func _on_body_entered(body: Node3D) -> void:
	if not _is_active:
		return

	# Don't hit source
	if body == source:
		return

	# Check faction - don't hit friendlies
	if body.has_method("get") and body.get("data"):
		var target_faction: int = body.data.faction if body.data else -1
		if target_faction == source_faction:
			return

	# Hit!
	_on_hit(body)


func _on_hit(target: Node) -> void:
	# Calculate damage
	var final_damage: float = damage

	# Pierce falloff
	if pierce_count > 0:
		final_damage *= pow(1.0 - pierce_falloff, float(pierce_count))

	# Anti-vehicle bonus
	if anti_vehicle_bonus > 0.0 and target.has_method("get") and target.get("data"):
		if target.data.is_vehicle:
			final_damage *= (1.0 + anti_vehicle_bonus)

	# Apply damage
	if target.has_method("take_damage"):
		target.take_damage(final_damage, source)

	# Apply suppression
	if suppression > 0.0 and target.has_method("apply_suppression"):
		target.apply_suppression(suppression)

	# Emit impact signal
	impact.emit(global_position, target)

	# AOE damage
	if aoe_radius > 0.0:
		_apply_aoe_damage(global_position)

	# Check pierce
	if pierce_count < max_pierces:
		pierce_count += 1
		return  # Continue flying

	# Deactivate
	_deactivate()


func _on_ground_impact() -> void:
	impact.emit(global_position, null)

	# AOE damage on ground impact
	if aoe_radius > 0.0:
		_apply_aoe_damage(global_position)

	# Apply terrain damage for explosive projectiles
	_apply_terrain_damage(global_position)

	# Napalm leaves fire
	if projectile_type == ProjectileType.NAPALM:
		_spawn_fire_hazard()

	_deactivate()


func _apply_aoe_damage(center: Vector3) -> void:
	# Find all units in radius
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = aoe_radius
	query.shape = sphere
	query.transform = Transform3D.IDENTITY.translated(center)
	query.collision_mask = 2 | 4 | 8  # Unit layers

	var results: Array[Dictionary] = space.intersect_shape(query, 32)

	for result in results:
		var body: Node = result.get("collider")
		if not body or body == source:
			continue

		# Check faction
		if body.has_method("get") and body.get("data"):
			var target_faction: int = body.data.faction if body.data else -1
			if target_faction == source_faction:
				continue

		# Calculate distance falloff
		var distance: float = center.distance_to(body.global_position)
		var damage_mult: float = 1.0
		if aoe_falloff and aoe_radius > 0.0:
			damage_mult = 1.0 - (distance / aoe_radius)
			damage_mult = maxf(damage_mult, 0.25)  # Minimum 25%

		# Apply damage
		if body.has_method("take_damage"):
			body.take_damage(damage * damage_mult, source)

		# Apply suppression
		if suppression_radius > 0.0 and distance <= suppression_radius:
			if body.has_method("apply_suppression"):
				body.apply_suppression(suppression * damage_mult)


func _spawn_fire_hazard() -> void:
	# TODO: Spawn persistent fire hazard zone
	# For now, just emit signal
	if BattleSignals:
		BattleSignals.napalm_impact.emit(global_position, aoe_radius)


## Apply terrain damage based on weapon category.
## Only explosive weapons affect terrain (not bullets).
func _apply_terrain_damage(impact_pos: Vector3) -> void:
	var terrain_damage_type: int = _get_terrain_damage_type()
	if terrain_damage_type < 0:
		return  # No terrain damage for this weapon

	# Calculate intensity based on damage (normalized to typical artillery damage)
	var intensity: float = clampf(damage / 500.0, 0.5, 1.5)

	# Apply terrain damage via DamageSystem autoload
	if DamageSystem:
		DamageSystem.apply_damage(impact_pos, terrain_damage_type, intensity)


## Map weapon category to terrain DamageSystem.DamageType.
## Returns -1 for weapons that don't damage terrain (bullets).
func _get_terrain_damage_type() -> int:
	match weapon_category:
		# Small explosions - grenades, mortars, light rockets
		VietnamWeaponDataScript.WeaponCategory.GRENADE_LAUNCHER:
			return DamageSystemScript.DamageType.SMALL_EXPLOSION
		VietnamWeaponDataScript.WeaponCategory.MORTAR:
			return DamageSystemScript.DamageType.SMALL_EXPLOSION
		VietnamWeaponDataScript.WeaponCategory.ROCKET_LAUNCHER:
			return DamageSystemScript.DamageType.SMALL_EXPLOSION
		VietnamWeaponDataScript.WeaponCategory.HELICOPTER_ROCKET:
			return DamageSystemScript.DamageType.SMALL_EXPLOSION

		# Medium explosions - artillery, tank guns
		VietnamWeaponDataScript.WeaponCategory.ARTILLERY:
			return DamageSystemScript.DamageType.MEDIUM_EXPLOSION
		VietnamWeaponDataScript.WeaponCategory.TANK_MAIN_GUN:
			return DamageSystemScript.DamageType.MEDIUM_EXPLOSION

		# Large explosions - bombs
		VietnamWeaponDataScript.WeaponCategory.AIRCRAFT_BOMB:
			return DamageSystemScript.DamageType.LARGE_EXPLOSION

		# Napalm - burns + slight depression
		VietnamWeaponDataScript.WeaponCategory.AIRCRAFT_NAPALM:
			return DamageSystemScript.DamageType.NAPALM

		# Non-terrain-damaging weapons (bullets, miniguns, etc)
		_:
			return -1


func _expire() -> void:
	expired.emit()
	_deactivate()


func _deactivate() -> void:
	_is_active = false
	set_physics_process(false)
	_trail.emitting = false
	visible = false


## Initialize and fire the projectile.
func fire(config: Dictionary) -> void:
	# Reset state
	_is_active = true
	elapsed_time = 0.0
	pierce_count = 0
	visible = true

	# Position
	global_position = config.get("start_position", Vector3.ZERO)
	start_position = global_position
	target_position = config.get("target_position", Vector3.ZERO)

	# Source
	source = config.get("source", null)
	source_faction = config.get("source_faction", 0)
	target_node = config.get("target_node", null)

	# Flight properties
	var speed: float = config.get("speed", 300.0)
	lifetime = config.get("lifetime", 2.0)
	trajectory = config.get("trajectory", VietnamWeaponDataScript.Trajectory.FLAT)
	arc_height = config.get("arc_height", 0.0)

	# Calculate initial velocity
	var direction: Vector3 = (target_position - start_position).normalized()
	velocity = direction * speed

	# Add scatter
	var scatter: float = config.get("scatter_angle", 0.0)
	if scatter > 0.0:
		var scatter_rad: float = deg_to_rad(scatter)
		velocity = velocity.rotated(Vector3.UP, randf_range(-scatter_rad, scatter_rad))
		velocity = velocity.rotated(Vector3.RIGHT, randf_range(-scatter_rad * 0.5, scatter_rad * 0.5))

	# For arcing trajectories, calculate initial upward velocity
	if trajectory == VietnamWeaponDataScript.Trajectory.ARCING:
		total_distance = start_position.distance_to(target_position)
		var flight_time: float = total_distance / speed
		velocity.y = (arc_height * 4.0 / flight_time) + (gravity * flight_time * 0.5)
	elif trajectory == VietnamWeaponDataScript.Trajectory.HIGH_ARC:
		total_distance = start_position.distance_to(target_position)

	# Damage properties
	damage = config.get("damage", 15.0)
	damage_type = config.get("damage_type", VietnamWeaponDataScript.DamageType.KINETIC)
	aoe_radius = config.get("aoe_radius", 0.0)
	aoe_falloff = config.get("aoe_falloff", true)
	suppression = config.get("suppression", 5.0)
	suppression_radius = config.get("suppression_radius", 0.0)

	# Pierce properties
	max_pierces = config.get("max_pierces", 0)
	pierce_falloff = config.get("pierce_falloff", 0.3)

	# Anti-armor
	armor_penetration = config.get("armor_penetration", 0.0)
	anti_vehicle_bonus = config.get("anti_vehicle_bonus", 0.0)

	# Weapon category for terrain damage and visuals
	weapon_category = config.get("weapon_category", -1)

	# Visual type
	is_tracer = config.get("is_tracer", false)
	_update_visuals()

	# Point toward target
	if direction.length_squared() > 0.01:
		look_at(global_position + direction, Vector3.UP)

	# Start processing
	set_physics_process(true)

	# Start trail
	if trail_enabled:
		_trail.emitting = true


func _update_visuals() -> void:
	# Determine projectile type from weapon category (uses class member)
	match weapon_category:
		VietnamWeaponDataScript.WeaponCategory.RIFLE, \
		VietnamWeaponDataScript.WeaponCategory.MACHINE_GUN, \
		VietnamWeaponDataScript.WeaponCategory.SIDEARM, \
		VietnamWeaponDataScript.WeaponCategory.VEHICLE_MG, \
		VietnamWeaponDataScript.WeaponCategory.HELICOPTER_MINIGUN, \
		VietnamWeaponDataScript.WeaponCategory.AIRCRAFT_GUN:
			projectile_type = ProjectileType.BULLET
			_setup_bullet_visual()
		VietnamWeaponDataScript.WeaponCategory.ROCKET_LAUNCHER, \
		VietnamWeaponDataScript.WeaponCategory.HELICOPTER_ROCKET:
			projectile_type = ProjectileType.ROCKET
			_setup_rocket_visual()
		VietnamWeaponDataScript.WeaponCategory.GRENADE_LAUNCHER:
			projectile_type = ProjectileType.GRENADE
			_setup_grenade_visual()
		VietnamWeaponDataScript.WeaponCategory.MORTAR, \
		VietnamWeaponDataScript.WeaponCategory.ARTILLERY, \
		VietnamWeaponDataScript.WeaponCategory.TANK_MAIN_GUN:
			projectile_type = ProjectileType.SHELL
			_setup_shell_visual()
		VietnamWeaponDataScript.WeaponCategory.AIRCRAFT_NAPALM:
			projectile_type = ProjectileType.NAPALM
			_setup_napalm_visual()
		VietnamWeaponDataScript.WeaponCategory.AIRCRAFT_BOMB:
			projectile_type = ProjectileType.BOMB
			_setup_bomb_visual()
		_:
			projectile_type = ProjectileType.BULLET
			_setup_bullet_visual()


func _setup_bullet_visual() -> void:
	# Small, fast bullet
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.1
	_mesh.mesh = mesh

	var mat := StandardMaterial3D.new()
	if is_tracer:
		mat.albedo_color = Color(1.0, 0.8, 0.3)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.6, 0.2)
		mat.emission_energy_multiplier = 2.0
		trail_enabled = true
	else:
		mat.albedo_color = Color(0.6, 0.5, 0.3)
		trail_enabled = false
	_mesh.material_override = mat

	_mesh.scale = Vector3(1, 1, 2)  # Elongate


func _setup_rocket_visual() -> void:
	# Rocket with smoke trail
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.05
	mesh.bottom_radius = 0.08
	mesh.height = 0.4
	_mesh.mesh = mesh
	_mesh.rotation.x = deg_to_rad(90)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.4, 0.3)  # Olive drab
	_mesh.material_override = mat

	trail_enabled = true
	_update_trail_for_rocket()


func _setup_grenade_visual() -> void:
	# 40mm grenade
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.04
	mesh.height = 0.15
	_mesh.mesh = mesh
	_mesh.rotation.x = deg_to_rad(90)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.4, 0.2)
	_mesh.material_override = mat

	trail_enabled = false


func _setup_shell_visual() -> void:
	# Artillery shell
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.1
	mesh.bottom_radius = 0.15
	mesh.height = 0.5
	_mesh.mesh = mesh
	_mesh.rotation.x = deg_to_rad(90)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.35, 0.25)
	_mesh.material_override = mat

	trail_enabled = true
	_update_trail_for_shell()


func _setup_napalm_visual() -> void:
	# Napalm canister
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.3
	mesh.bottom_radius = 0.3
	mesh.height = 1.5
	_mesh.mesh = mesh
	_mesh.rotation.x = deg_to_rad(90)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.6, 0.6)
	_mesh.material_override = mat

	trail_enabled = false


func _setup_bomb_visual() -> void:
	# Bomb (Mk 82)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.2
	mesh.bottom_radius = 0.25
	mesh.height = 1.2
	_mesh.mesh = mesh
	_mesh.rotation.x = deg_to_rad(90)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.3)  # Olive
	_mesh.material_override = mat

	trail_enabled = false


func _update_trail_for_rocket() -> void:
	if not _trail.process_material:
		return
	var mat: ParticleProcessMaterial = _trail.process_material as ParticleProcessMaterial
	mat.color = Color(0.8, 0.6, 0.4, 0.9)  # Smoke color
	mat.scale_min = 0.1
	mat.scale_max = 0.2
	_trail.amount = 30
	_trail.lifetime = 0.5


func _update_trail_for_shell() -> void:
	if not _trail.process_material:
		return
	var mat: ParticleProcessMaterial = _trail.process_material as ParticleProcessMaterial
	mat.color = Color(0.5, 0.5, 0.5, 0.7)
	mat.scale_min = 0.05
	mat.scale_max = 0.1
	_trail.amount = 20
	_trail.lifetime = 0.4


## Check if projectile is currently active.
func is_active() -> bool:
	return _is_active
