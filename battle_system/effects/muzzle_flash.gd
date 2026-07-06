class_name MuzzleFlash extends Node3D
## MuzzleFlash - Quick burst of light and particles when weapons fire
##
## Spawned by CombatManager when weapons fire. Auto-frees after flash duration.
## Different sizes for different weapon types.

enum FlashSize { SMALL, MEDIUM, LARGE, HUGE }

## Flash settings
var flash_size: FlashSize = FlashSize.MEDIUM
var flash_duration: float = 0.08
var _elapsed: float = 0.0

## Components
var _light: OmniLight3D = null
var _sprite: Sprite3D = null
var _particles: GPUParticles3D = null


func _ready() -> void:
	_setup_light()
	_setup_sprite()
	_setup_particles()

	# Start flash
	_light.visible = true
	_sprite.visible = true
	if _particles:
		_particles.emitting = true


func _process(delta: float) -> void:
	_elapsed += delta

	# Fade out light intensity
	var progress: float = _elapsed / flash_duration
	if progress >= 1.0:
		queue_free()
		return

	# Quick fade
	var fade: float = 1.0 - progress
	_light.light_energy = _get_light_energy() * fade
	_sprite.modulate.a = fade


func _setup_light() -> void:
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.8, 0.4)  # Warm muzzle flash
	_light.light_energy = _get_light_energy()
	_light.omni_range = _get_light_range()
	_light.omni_attenuation = 2.0
	_light.shadow_enabled = false  # Performance
	add_child(_light)


func _setup_sprite() -> void:
	_sprite = Sprite3D.new()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.no_depth_test = true
	_sprite.pixel_size = 0.01

	# Create procedural flash texture
	var size: int = 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var center := Vector2(size / 2.0, size / 2.0)
	var radius: float = size / 2.0

	for y in size:
		for x in size:
			var dist: float = Vector2(x, y).distance_to(center)
			if dist < radius:
				var alpha: float = 1.0 - (dist / radius)
				alpha = pow(alpha, 0.5)  # Bright center falloff
				img.set_pixel(x, y, Color(1.0, 0.9, 0.6, alpha))

	var tex := ImageTexture.create_from_image(img)
	_sprite.texture = tex
	_sprite.scale = Vector3.ONE * _get_sprite_scale()
	add_child(_sprite)


func _setup_particles() -> void:
	# Optional smoke puff for larger weapons
	if flash_size < FlashSize.LARGE:
		return

	_particles = GPUParticles3D.new()
	_particles.amount = 8
	_particles.lifetime = 0.3
	_particles.one_shot = true
	_particles.explosiveness = 0.9

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.1
	mat.direction = Vector3(0, 0, -1)  # Forward from muzzle
	mat.spread = 30.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0, 1, 0)  # Smoke rises
	mat.scale_min = 0.1
	mat.scale_max = 0.3
	mat.color = Color(0.6, 0.55, 0.5, 0.6)  # Gray smoke
	_particles.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	_particles.draw_pass_1 = mesh

	add_child(_particles)


func _get_light_energy() -> float:
	match flash_size:
		FlashSize.SMALL: return 2.0
		FlashSize.MEDIUM: return 4.0
		FlashSize.LARGE: return 8.0
		FlashSize.HUGE: return 15.0
	return 4.0


func _get_light_range() -> float:
	match flash_size:
		FlashSize.SMALL: return 3.0
		FlashSize.MEDIUM: return 5.0
		FlashSize.LARGE: return 10.0
		FlashSize.HUGE: return 20.0
	return 5.0


func _get_sprite_scale() -> float:
	match flash_size:
		FlashSize.SMALL: return 0.3
		FlashSize.MEDIUM: return 0.5
		FlashSize.LARGE: return 1.0
		FlashSize.HUGE: return 2.0
	return 0.5


## Factory: Create muzzle flash at position
static func spawn(parent: Node, world_pos: Vector3, size: FlashSize = FlashSize.MEDIUM) -> MuzzleFlash:
	var flash := MuzzleFlash.new()
	flash.flash_size = size
	parent.add_child(flash)
	flash.global_position = world_pos
	return flash


## Factory: Create muzzle flash sized for weapon category
static func spawn_for_weapon(parent: Node, world_pos: Vector3, weapon_category: int) -> MuzzleFlash:
	var size: FlashSize = FlashSize.MEDIUM

	# Map weapon category to flash size
	match weapon_category:
		0, 3:  # RIFLE, SIDEARM
			size = FlashSize.SMALL
		1, 6, 11:  # MACHINE_GUN, VEHICLE_MG, HELICOPTER_MINIGUN
			size = FlashSize.MEDIUM
		2:  # GRENADE_LAUNCHER
			size = FlashSize.MEDIUM
		4, 5:  # ROCKET_LAUNCHER, MORTAR
			size = FlashSize.LARGE
		7, 8:  # ARTILLERY, TANK_MAIN_GUN
			size = FlashSize.HUGE
		9, 10:  # HELICOPTER_ROCKET, AIRCRAFT_GUN
			size = FlashSize.LARGE
		_:
			size = FlashSize.MEDIUM

	return spawn(parent, world_pos, size)
