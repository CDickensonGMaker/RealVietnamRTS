class_name HitEffects extends Node
## Hit Effects - Visual and audio feedback for combat impacts.
## Creates muzzle flashes, tracer rounds, impact effects, and blood splatter.
## Manages effect pooling for performance.
##
## Serves Pillar 5 (The War Continues) by providing clear feedback even when
## not watching a specific engagement, so the player knows combat is happening.

signal effect_spawned(effect_type: int, position: Vector3)
signal large_explosion(position: Vector3, radius: float)

enum EffectType {
	MUZZLE_FLASH_SMALL,   # Pistol, rifle
	MUZZLE_FLASH_MEDIUM,  # MG
	MUZZLE_FLASH_LARGE,   # Tank cannon
	TRACER_RED,           # VC/NVA tracer
	TRACER_GREEN,         # US tracer
	IMPACT_DIRT,          # Ground hit
	IMPACT_METAL,         # Vehicle hit
	IMPACT_WOOD,          # Structure hit
	IMPACT_FLESH,         # Infantry hit
	BLOOD_SPLATTER,       # Lethal hit
	EXPLOSION_SMALL,      # Grenade
	EXPLOSION_MEDIUM,     # Mortar, RPG
	EXPLOSION_LARGE,      # Artillery
	EXPLOSION_NAPALM,     # Napalm
	SMOKE_PUFF,           # Dust/smoke
	FIRE_SMALL,           # Burning debris
	FIRE_LARGE,           # Burning vehicle
	SUPPRESSION_MARKER,   # UI indicator
}

## Effect pools
var _muzzle_flash_pool: Array[Node3D] = []
var _impact_pool: Array[Node3D] = []
var _explosion_pool: Array[Node3D] = []
var _tracer_pool: Array[Node3D] = []

const POOL_SIZE_MUZZLE := 50
const POOL_SIZE_IMPACT := 100
const POOL_SIZE_EXPLOSION := 30
const POOL_SIZE_TRACER := 200

## Configuration
@export var effects_enabled: bool = true
@export var tracer_frequency: float = 0.2  # 1 in 5 rounds shows tracer
@export var blood_effects_enabled: bool = true


func _ready() -> void:
	_initialize_pools()


func _initialize_pools() -> void:
	# Create pooled effect objects
	for i in POOL_SIZE_MUZZLE:
		var flash := _create_muzzle_flash()
		flash.visible = false
		add_child(flash)
		_muzzle_flash_pool.append(flash)

	for i in POOL_SIZE_IMPACT:
		var impact := _create_impact_effect()
		impact.visible = false
		add_child(impact)
		_impact_pool.append(impact)

	for i in POOL_SIZE_EXPLOSION:
		var explosion := _create_explosion_effect()
		explosion.visible = false
		add_child(explosion)
		_explosion_pool.append(explosion)

	for i in POOL_SIZE_TRACER:
		var tracer := _create_tracer()
		tracer.visible = false
		add_child(tracer)
		_tracer_pool.append(tracer)


func _create_muzzle_flash() -> Node3D:
	var flash := Node3D.new()
	flash.name = "MuzzleFlash"

	# Light
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.4)
	light.light_energy = 2.0
	light.omni_range = 5.0
	flash.add_child(light)

	# Flash mesh (small sphere)
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	mesh.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.3)
	mat.emission_energy_multiplier = 3.0
	mesh.material_override = mat

	flash.add_child(mesh)

	return flash


func _create_impact_effect() -> Node3D:
	var impact := Node3D.new()
	impact.name = "Impact"

	# Particles would go here - using mesh for now
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	mesh.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.4, 0.3, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat

	impact.add_child(mesh)

	return impact


func _create_explosion_effect() -> Node3D:
	var explosion := Node3D.new()
	explosion.name = "Explosion"

	# Light
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 5.0
	light.omni_range = 15.0
	explosion.add_child(light)

	# Fireball mesh
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 2.0
	mesh.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.1)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat

	explosion.add_child(mesh)

	return explosion


func _create_tracer() -> Node3D:
	var tracer := Node3D.new()
	tracer.name = "Tracer"

	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.02
	capsule.height = 2.0
	mesh.mesh = capsule
	mesh.rotation_degrees = Vector3(90, 0, 0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.1)
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat

	tracer.add_child(mesh)

	return tracer


# =============================================================================
# PUBLIC API
# =============================================================================

func spawn_muzzle_flash(position: Vector3, direction: Vector3, size: int = 0) -> void:
	if not effects_enabled:
		return

	var flash: Node3D = _get_pooled(_muzzle_flash_pool)
	if not flash:
		return

	flash.global_position = position
	if direction.length() > 0.1:
		flash.look_at(position + direction)

	# Scale based on size
	var scale: float = 1.0
	match size:
		EffectType.MUZZLE_FLASH_SMALL:
			scale = 0.5
		EffectType.MUZZLE_FLASH_MEDIUM:
			scale = 1.0
		EffectType.MUZZLE_FLASH_LARGE:
			scale = 2.0

	flash.scale = Vector3.ONE * scale
	flash.visible = true

	effect_spawned.emit(EffectType.MUZZLE_FLASH_SMALL + size, position)

	# Hide after brief flash
	_delayed_hide(flash, 0.05)


func spawn_impact(position: Vector3, impact_type: int = EffectType.IMPACT_DIRT) -> void:
	if not effects_enabled:
		return

	var impact: Node3D = _get_pooled(_impact_pool)
	if not impact:
		return

	impact.global_position = position
	impact.visible = true

	# Color based on type
	var mesh: MeshInstance3D = impact.get_child(0) as MeshInstance3D
	if mesh and mesh.material_override:
		var mat: StandardMaterial3D = mesh.material_override
		match impact_type:
			EffectType.IMPACT_DIRT:
				mat.albedo_color = Color(0.5, 0.4, 0.3, 0.8)
			EffectType.IMPACT_METAL:
				mat.albedo_color = Color(1.0, 0.8, 0.3, 0.9)
			EffectType.IMPACT_WOOD:
				mat.albedo_color = Color(0.6, 0.4, 0.2, 0.8)
			EffectType.IMPACT_FLESH:
				if blood_effects_enabled:
					mat.albedo_color = Color(0.6, 0.1, 0.1, 0.9)
				else:
					mat.albedo_color = Color(0.4, 0.3, 0.3, 0.8)

	effect_spawned.emit(impact_type, position)

	_delayed_hide(impact, 0.3)


func spawn_blood_splatter(position: Vector3) -> void:
	if not effects_enabled or not blood_effects_enabled:
		return

	spawn_impact(position, EffectType.IMPACT_FLESH)


func spawn_explosion(position: Vector3, size: int = EffectType.EXPLOSION_MEDIUM) -> void:
	if not effects_enabled:
		return

	var explosion: Node3D = _get_pooled(_explosion_pool)
	if not explosion:
		return

	explosion.global_position = position
	explosion.visible = true

	# Scale based on size
	var scale: float = 1.0
	var duration: float = 0.5
	var radius: float = 5.0

	match size:
		EffectType.EXPLOSION_SMALL:
			scale = 0.5
			duration = 0.3
			radius = 3.0
		EffectType.EXPLOSION_MEDIUM:
			scale = 1.0
			duration = 0.5
			radius = 5.0
		EffectType.EXPLOSION_LARGE:
			scale = 2.0
			duration = 0.8
			radius = 10.0
		EffectType.EXPLOSION_NAPALM:
			scale = 3.0
			duration = 2.0
			radius = 15.0

			# Napalm has different color
			var mesh: MeshInstance3D = explosion.get_child(1) as MeshInstance3D
			if mesh and mesh.material_override:
				var mat: StandardMaterial3D = mesh.material_override
				mat.albedo_color = Color(1.0, 0.3, 0.0, 0.9)
				mat.emission = Color(1.0, 0.2, 0.0)

	explosion.scale = Vector3.ONE * scale

	effect_spawned.emit(size, position)
	large_explosion.emit(position, radius)

	# Animate scale down
	var tween := get_tree().create_tween()
	tween.tween_property(explosion, "scale", Vector3.ONE * scale * 1.5, duration * 0.2)
	tween.tween_property(explosion, "scale", Vector3.ONE * scale * 0.1, duration * 0.8)
	tween.tween_callback(func(): explosion.visible = false)


func spawn_tracer(start: Vector3, end: Vector3, is_enemy: bool = false, projectile_speed: float = 0.0) -> void:
	if not effects_enabled:
		return

	# Only show some tracers for performance
	if randf() > tracer_frequency:
		return

	var tracer: Node3D = _get_pooled(_tracer_pool)
	if not tracer:
		return

	tracer.global_position = start
	tracer.visible = true

	# Point toward target
	var direction: Vector3 = end - start
	if direction.length() > 0.1:
		tracer.look_at(end)
		tracer.rotation.x += PI / 2.0  # Adjust for capsule orientation

	# Color based on faction
	var mesh: MeshInstance3D = tracer.get_child(0) as MeshInstance3D
	if mesh and mesh.material_override:
		var mat: StandardMaterial3D = mesh.material_override
		if is_enemy:
			mat.albedo_color = Color(0.2, 1.0, 0.2)  # Green for VC
			mat.emission = Color(0.2, 1.0, 0.2)
		else:
			mat.albedo_color = Color(1.0, 0.3, 0.1)  # Red for US
			mat.emission = Color(1.0, 0.3, 0.1)

	effect_spawned.emit(EffectType.TRACER_RED if not is_enemy else EffectType.TRACER_GREEN, start)

	# Animate tracer moving - use actual projectile speed if provided, else default
	# Weapons range from 30 m/s (grenades) to 1030 m/s (tank rounds)
	var actual_speed: float = projectile_speed if projectile_speed > 0.0 else 500.0
	var flight_time: float = direction.length() / actual_speed
	var tween := get_tree().create_tween()
	tween.tween_property(tracer, "global_position", end, flight_time)
	tween.tween_callback(func(): tracer.visible = false)


func spawn_suppression_marker(position: Vector3, intensity: float = 1.0) -> void:
	# Visual indicator that units are being suppressed
	# Could be a bouncing icon or particle effect
	if not effects_enabled:
		return

	# For now, just spawn smoke puff
	var impact: Node3D = _get_pooled(_impact_pool)
	if not impact:
		return

	impact.global_position = position + Vector3(0, 1.5, 0)
	impact.scale = Vector3.ONE * intensity
	impact.visible = true

	var mesh: MeshInstance3D = impact.get_child(0) as MeshInstance3D
	if mesh and mesh.material_override:
		var mat: StandardMaterial3D = mesh.material_override
		mat.albedo_color = Color(0.8, 0.8, 0.0, 0.5)  # Yellow warning

	_delayed_hide(impact, 1.0)


func spawn_smoke(position: Vector3, duration: float = 5.0) -> void:
	if not effects_enabled:
		return

	var smoke: Node3D = _get_pooled(_impact_pool)
	if not smoke:
		return

	smoke.global_position = position
	smoke.scale = Vector3.ONE * 3.0
	smoke.visible = true

	var mesh: MeshInstance3D = smoke.get_child(0) as MeshInstance3D
	if mesh and mesh.material_override:
		var mat: StandardMaterial3D = mesh.material_override
		mat.albedo_color = Color(0.5, 0.5, 0.5, 0.7)

	# Animate rising and fading
	var tween := get_tree().create_tween()
	tween.tween_property(smoke, "global_position:y", position.y + 10.0, duration)
	tween.parallel().tween_property(smoke, "scale", Vector3.ONE * 6.0, duration)
	tween.tween_callback(func(): smoke.visible = false)


# =============================================================================
# HELPERS
# =============================================================================

func _get_pooled(pool: Array[Node3D]) -> Node3D:
	for effect in pool:
		if not effect.visible:
			return effect

	# Pool exhausted, return first (will interrupt previous effect)
	if not pool.is_empty():
		var effect: Node3D = pool[0]
		effect.visible = false
		return effect

	return null


func _delayed_hide(node: Node3D, delay: float) -> void:
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func():
		if is_instance_valid(node):
			node.visible = false
	)


# =============================================================================
# INTEGRATION WITH COMBAT SYSTEM
# =============================================================================

func on_weapon_fired(attacker: Node3D, target_pos: Vector3, weapon_id: String) -> void:
	if not is_instance_valid(attacker):
		return

	var muzzle_pos: Vector3 = attacker.global_position + Vector3(0, 1.0, 0)
	var direction: Vector3 = (target_pos - muzzle_pos).normalized()

	# Determine muzzle flash size based on weapon
	var flash_size: int = EffectType.MUZZLE_FLASH_SMALL
	if weapon_id.contains("m60") or weapon_id.contains("m2") or weapon_id.contains("minigun"):
		flash_size = EffectType.MUZZLE_FLASH_MEDIUM
	elif weapon_id.contains("cannon") or weapon_id.contains("howitzer") or weapon_id.contains("main_gun"):
		flash_size = EffectType.MUZZLE_FLASH_LARGE

	spawn_muzzle_flash(muzzle_pos, direction, flash_size)

	# Spawn tracer
	var is_enemy: bool = attacker.is_in_group("enemy_units")
	spawn_tracer(muzzle_pos, target_pos, is_enemy)


func on_projectile_impact(position: Vector3, weapon_id: String, hit_target: Node3D = null) -> void:
	# Determine effect type
	if weapon_id.contains("napalm"):
		spawn_explosion(position, EffectType.EXPLOSION_NAPALM)
	elif weapon_id.contains("howitzer") or weapon_id.contains("artillery"):
		spawn_explosion(position, EffectType.EXPLOSION_LARGE)
	elif weapon_id.contains("mortar") or weapon_id.contains("rpg") or weapon_id.contains("rocket"):
		spawn_explosion(position, EffectType.EXPLOSION_MEDIUM)
	elif weapon_id.contains("grenade") or weapon_id.contains("m79"):
		spawn_explosion(position, EffectType.EXPLOSION_SMALL)
	else:
		# Small arms impact
		var impact_type: int = EffectType.IMPACT_DIRT
		if hit_target:
			if hit_target.is_in_group("vehicles"):
				impact_type = EffectType.IMPACT_METAL
			elif hit_target.is_in_group("buildings"):
				impact_type = EffectType.IMPACT_WOOD
			elif hit_target.is_in_group("infantry") or hit_target.is_in_group("civilians"):
				impact_type = EffectType.IMPACT_FLESH

		spawn_impact(position, impact_type)


func on_unit_killed(unit: Node3D) -> void:
	if not is_instance_valid(unit):
		return

	if blood_effects_enabled:
		spawn_blood_splatter(unit.global_position)


func on_vehicle_destroyed(vehicle: Node3D) -> void:
	if not is_instance_valid(vehicle):
		return

	spawn_explosion(vehicle.global_position, EffectType.EXPLOSION_MEDIUM)
