extends Node
class_name ImpactEffects
## ImpactEffects - Visual feedback for projectile impacts
##
## Spawns appropriate particles for different impact types:
## - Dirt kick-up for misses
## - Blood splatter for infantry hits
## - Sparks for vehicle/building hits
## - Explosions for AOE weapons

const VietnamWeaponDataScript = preload("res://battle_system/data/vietnam_weapon_data.gd")

## Effect types
enum ImpactType { DIRT, BLOOD, SPARKS, EXPLOSION_SMALL, EXPLOSION_MEDIUM, EXPLOSION_LARGE, NAPALM }

## Pool settings
const PARTICLE_POOL_SIZE: int = 50

## Particle pools by type
var _dirt_pool: Array[GPUParticles3D] = []
var _blood_pool: Array[GPUParticles3D] = []
var _sparks_pool: Array[GPUParticles3D] = []
var _explosion_pool: Array[GPUParticles3D] = []
var _pool_parent: Node3D = null

## Pool indices
var _dirt_index: int = 0
var _blood_index: int = 0
var _sparks_index: int = 0
var _explosion_index: int = 0


func _ready() -> void:
	_pool_parent = Node3D.new()
	_pool_parent.name = "ImpactEffectsPool"
	add_child(_pool_parent)

	_create_dirt_pool()
	_create_blood_pool()
	_create_sparks_pool()
	_create_explosion_pool()

	print("[ImpactEffects] Initialized particle pools")


## Spawn impact effect at position
func spawn_impact(world_pos: Vector3, impact_type: ImpactType, intensity: float = 1.0) -> void:
	var particles: GPUParticles3D = null

	match impact_type:
		ImpactType.DIRT:
			particles = _get_from_pool(_dirt_pool, _dirt_index)
			_dirt_index = (_dirt_index + 1) % _dirt_pool.size()
		ImpactType.BLOOD:
			particles = _get_from_pool(_blood_pool, _blood_index)
			_blood_index = (_blood_index + 1) % _blood_pool.size()
		ImpactType.SPARKS:
			particles = _get_from_pool(_sparks_pool, _sparks_index)
			_sparks_index = (_sparks_index + 1) % _sparks_pool.size()
		ImpactType.EXPLOSION_SMALL, ImpactType.EXPLOSION_MEDIUM, ImpactType.EXPLOSION_LARGE:
			particles = _get_from_pool(_explosion_pool, _explosion_index)
			_explosion_index = (_explosion_index + 1) % _explosion_pool.size()
			_configure_explosion(particles, impact_type)
		ImpactType.NAPALM:
			particles = _get_from_pool(_explosion_pool, _explosion_index)
			_explosion_index = (_explosion_index + 1) % _explosion_pool.size()
			_configure_napalm(particles)

	if particles:
		particles.global_position = world_pos
		particles.emitting = true


## Spawn appropriate impact for projectile hit
func spawn_for_projectile(world_pos: Vector3, hit_target: Node, weapon_category: int, aoe_radius: float) -> void:
	# AOE weapons spawn explosions
	if aoe_radius > 0:
		var explosion_type: ImpactType
		if aoe_radius < 5.0:
			explosion_type = ImpactType.EXPLOSION_SMALL
		elif aoe_radius < 10.0:
			explosion_type = ImpactType.EXPLOSION_MEDIUM
		else:
			explosion_type = ImpactType.EXPLOSION_LARGE
		spawn_impact(world_pos, explosion_type)
		return

	# Check what was hit
	if hit_target:
		# Infantry hit
		if hit_target.is_in_group("infantry") or hit_target.is_in_group("player_units") or hit_target.is_in_group("enemy_units"):
			var is_vehicle: bool = false
			if hit_target.has_method("get") and hit_target.get("data"):
				is_vehicle = hit_target.data.is_vehicle if "is_vehicle" in hit_target.data else false
			if is_vehicle:
				spawn_impact(world_pos, ImpactType.SPARKS)
			else:
				spawn_impact(world_pos, ImpactType.BLOOD)
			return
		# Building hit
		if hit_target.is_in_group("buildings") or hit_target.is_in_group("defensive_structures"):
			spawn_impact(world_pos, ImpactType.SPARKS)
			return

	# Ground hit - dirt
	spawn_impact(world_pos, ImpactType.DIRT)


func _get_from_pool(pool: Array, index: int) -> GPUParticles3D:
	if pool.size() == 0:
		return null
	return pool[index % pool.size()]


# =============================================================================
# POOL CREATION
# =============================================================================

func _create_dirt_pool() -> void:
	for i in 20:
		var particles := _create_dirt_particles()
		_pool_parent.add_child(particles)
		_dirt_pool.append(particles)


func _create_blood_pool() -> void:
	for i in 15:
		var particles := _create_blood_particles()
		_pool_parent.add_child(particles)
		_blood_pool.append(particles)


func _create_sparks_pool() -> void:
	for i in 10:
		var particles := _create_sparks_particles()
		_pool_parent.add_child(particles)
		_sparks_pool.append(particles)


func _create_explosion_pool() -> void:
	for i in 10:
		var particles := _create_explosion_particles()
		_pool_parent.add_child(particles)
		_explosion_pool.append(particles)


# =============================================================================
# PARTICLE SYSTEMS
# =============================================================================

func _create_dirt_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 15
	particles.lifetime = 0.5
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.emitting = false

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.1
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 6.0
	mat.gravity = Vector3(0, -15, 0)
	mat.scale_min = 0.05
	mat.scale_max = 0.15
	mat.color = Color(0.4, 0.35, 0.25, 0.9)  # Brown dirt
	particles.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	particles.draw_pass_1 = mesh

	return particles


func _create_blood_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 12
	particles.lifetime = 0.4
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.emitting = false

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.05
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0, -12, 0)
	mat.scale_min = 0.02
	mat.scale_max = 0.08
	mat.color = Color(0.6, 0.1, 0.1, 0.9)  # Dark red
	particles.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	particles.draw_pass_1 = mesh

	return particles


func _create_sparks_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 20
	particles.lifetime = 0.3
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.emitting = false

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.05
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 80.0
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 10.0
	mat.gravity = Vector3(0, -5, 0)
	mat.scale_min = 0.01
	mat.scale_max = 0.03
	mat.color = Color(1.0, 0.8, 0.3, 1.0)  # Yellow-orange sparks
	particles.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.015
	mesh.height = 0.03
	particles.draw_pass_1 = mesh

	return particles


func _create_explosion_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 30
	particles.lifetime = 0.8
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.emitting = false

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.5
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 15.0
	mat.gravity = Vector3(0, 5, 0)  # Smoke rises
	mat.scale_min = 0.2
	mat.scale_max = 0.8
	mat.color = Color(0.3, 0.25, 0.2, 0.8)  # Gray-brown smoke
	particles.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.2
	mesh.height = 0.4
	particles.draw_pass_1 = mesh

	return particles


func _configure_explosion(particles: GPUParticles3D, size: ImpactType) -> void:
	var mat: ParticleProcessMaterial = particles.process_material as ParticleProcessMaterial
	if not mat:
		return

	match size:
		ImpactType.EXPLOSION_SMALL:
			particles.amount = 20
			mat.emission_sphere_radius = 0.3
			mat.initial_velocity_min = 3.0
			mat.initial_velocity_max = 8.0
			mat.scale_min = 0.1
			mat.scale_max = 0.4
		ImpactType.EXPLOSION_MEDIUM:
			particles.amount = 40
			mat.emission_sphere_radius = 0.8
			mat.initial_velocity_min = 5.0
			mat.initial_velocity_max = 15.0
			mat.scale_min = 0.3
			mat.scale_max = 1.0
		ImpactType.EXPLOSION_LARGE:
			particles.amount = 60
			mat.emission_sphere_radius = 1.5
			mat.initial_velocity_min = 8.0
			mat.initial_velocity_max = 25.0
			mat.scale_min = 0.5
			mat.scale_max = 2.0


func _configure_napalm(particles: GPUParticles3D) -> void:
	var mat: ParticleProcessMaterial = particles.process_material as ParticleProcessMaterial
	if not mat:
		return

	particles.amount = 50
	particles.lifetime = 1.5
	mat.emission_sphere_radius = 2.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 10.0
	mat.scale_min = 0.5
	mat.scale_max = 2.0
	mat.color = Color(1.0, 0.5, 0.1, 0.9)  # Orange fire
