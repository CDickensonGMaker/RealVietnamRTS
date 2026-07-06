class_name ParticlePool extends Node
## Pool of reusable particle effects for efficient spawning
##
## Usage:
##   ParticlePool.spawn_muzzle_flash(position)
##   ParticlePool.spawn_mortar_impact(position)
##   ParticlePool.spawn_dust_cloud(position)

const POOL_SIZE := 16

## Particle scenes
const MuzzleFlashScene := preload("res://effects/particles/muzzle_flash.tscn")
const MortarImpactScene := preload("res://effects/particles/mortar_impact.tscn")
const DustCloudScene := preload("res://effects/particles/dust_cloud.tscn")

## Instance pools
var _muzzle_pool: Array[Node] = []
var _muzzle_index: int = 0

var _impact_pool: Array[Node] = []
var _impact_index: int = 0

var _dust_pool: Array[Node] = []
var _dust_index: int = 0

## Singleton instance
static var instance: ParticlePool = null


func _ready() -> void:
	ParticlePool.instance = self
	_initialize_pools()


func _initialize_pools() -> void:
	# Pre-spawn particle instances
	for i in POOL_SIZE:
		var muzzle := MuzzleFlashScene.instantiate()
		muzzle.emitting = false
		add_child(muzzle)
		_muzzle_pool.append(muzzle)

		var impact := MortarImpactScene.instantiate()
		impact.visible = false
		add_child(impact)
		_impact_pool.append(impact)

		var dust := DustCloudScene.instantiate()
		dust.emitting = false
		add_child(dust)
		_dust_pool.append(dust)


## Spawn muzzle flash at position
static func spawn_muzzle_flash(pos: Vector3) -> void:
	if not instance:
		return

	var particles := instance._muzzle_pool[instance._muzzle_index] as GPUParticles3D
	instance._muzzle_index = (instance._muzzle_index + 1) % POOL_SIZE

	particles.global_position = pos
	particles.emitting = true


## Spawn mortar/explosion impact at position
static func spawn_mortar_impact(pos: Vector3) -> void:
	if not instance:
		return

	var impact := instance._impact_pool[instance._impact_index] as Node3D
	instance._impact_index = (instance._impact_index + 1) % POOL_SIZE

	impact.global_position = pos
	impact.visible = true

	# Start all particle emitters
	for child in impact.get_children():
		if child is GPUParticles3D:
			child.emitting = true

	# Fade out light
	var light := impact.get_node_or_null("Light") as OmniLight3D
	if light:
		light.light_energy = 3.0
		var tween := instance.create_tween()
		tween.tween_property(light, "light_energy", 0.0, 0.3)
		tween.tween_callback(func(): impact.visible = false)


## Spawn dust cloud at position
static func spawn_dust_cloud(pos: Vector3) -> void:
	if not instance:
		return

	var particles := instance._dust_pool[instance._dust_index] as GPUParticles3D
	instance._dust_index = (instance._dust_index + 1) % POOL_SIZE

	particles.global_position = pos
	particles.emitting = true
