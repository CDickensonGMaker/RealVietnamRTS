extends Node3D
class_name Village

## Village - Vietnamese village with population and allegiance
## Provides resources to whoever controls it (US hearts-and-minds or VC taxation)

signal allegiance_changed(village: Village, new_allegiance: int)
signal population_changed(village: Village, new_pop: int)
signal vc_tax_collected(village: Village, amount: float)
signal us_aid_delivered(village: Village, amount: float)
signal village_attacked(village: Village, attacker: Node3D)
signal civilian_killed(village: Village, killer: Node3D)

enum Allegiance { NEUTRAL, PRO_US, PRO_VC, CONTESTED }

## Configuration
@export var village_name: String = "Village"
@export var initial_population: int = 100
@export var initial_allegiance: Allegiance = Allegiance.NEUTRAL

## State
var population: int = 100
var allegiance: Allegiance = Allegiance.NEUTRAL
var vc_presence: float = 0.3  # 0-1, VC influence level
var us_influence: float = 0.0  # 0-1, US influence level
var fear_level: float = 0.0  # 0-1, fear from violence

## Resources
var rice_production: float = 10.0  # Per minute
var recruit_pool: int = 0  # Available recruits for VC
var supply_stockpile: float = 0.0

## Civilians
var civilians: Array[Node3D] = []
var vc_sympathizers: int = 0  # Hidden VC fighters among civilians

## Timers
var _tax_timer: float = 0.0
var _production_timer: float = 0.0
const TAX_INTERVAL := 60.0
const PRODUCTION_INTERVAL := 10.0


func _ready() -> void:
	population = initial_population
	allegiance = initial_allegiance
	vc_sympathizers = int(population * vc_presence * 0.1)
	recruit_pool = int(population * 0.05)

	add_to_group("villages")
	_create_visual()
	_spawn_civilians()

	print("[Village] %s initialized - Pop: %d, Allegiance: %s" % [
		village_name, population, _get_allegiance_name()
	])


func _create_visual() -> void:
	"""Create village visual representation"""
	# Central hut
	var main_hut := _create_hut(Vector3.ZERO, 3.0)
	add_child(main_hut)

	# Surrounding huts
	for i in range(3, 6):
		var angle: float = (TAU / 5.0) * float(i)
		var dist: float = randf_range(8.0, 15.0)
		var pos := Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		var hut := _create_hut(pos, randf_range(2.0, 3.5))
		add_child(hut)


func _create_hut(pos: Vector3, size: float) -> Node3D:
	"""Create a simple hut mesh"""
	var hut := Node3D.new()
	hut.position = pos

	# Base
	var base := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size, size * 0.6, size)
	base.mesh = box
	base.position.y = size * 0.3

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.4, 0.25)  # Bamboo/thatch color
	base.material_override = mat

	hut.add_child(base)

	# Roof (cone)
	var roof := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.1
	cone.bottom_radius = size * 0.8
	cone.height = size * 0.5
	roof.mesh = cone
	roof.position.y = size * 0.85

	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.35, 0.3, 0.15)  # Thatch
	roof.material_override = roof_mat

	hut.add_child(roof)

	return hut


func _spawn_civilians() -> void:
	"""Spawn civilian NPCs"""
	var civilian_count: int = mini(10, population / 10)

	for i in civilian_count:
		var civilian := _create_civilian()
		var angle: float = randf() * TAU
		var dist: float = randf_range(5.0, 20.0)
		civilian.position = Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		add_child(civilian)
		civilians.append(civilian)


func _create_civilian() -> Node3D:
	"""Create a civilian NPC"""
	var civilian := CharacterBody3D.new()
	civilian.name = "Civilian"
	civilian.add_to_group("civilians")

	# Simple mesh
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	mesh.mesh = capsule
	mesh.position.y = 0.8

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.5, 0.4)  # Civilian clothing
	mesh.material_override = mat

	civilian.add_child(mesh)

	# Collision
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.6
	collision.shape = shape
	collision.position.y = 0.8
	civilian.add_child(collision)

	return civilian


func _process(delta: float) -> void:
	_production_timer += delta
	_tax_timer += delta

	# Production
	if _production_timer >= PRODUCTION_INTERVAL:
		_production_timer = 0.0
		_produce_resources()

	# VC taxation (if VC controlled)
	if _tax_timer >= TAX_INTERVAL and (allegiance == Allegiance.PRO_VC or vc_presence > 0.5):
		_tax_timer = 0.0
		_vc_tax_collection()

	# Update allegiance based on influence
	_update_allegiance()

	# Decay fear over time
	fear_level = maxf(fear_level - delta * 0.01, 0.0)


func _produce_resources() -> void:
	"""Village produces resources"""
	var production: float = rice_production * (float(population) / 100.0)
	supply_stockpile += production

	# Generate recruits
	if randf() < 0.1 and recruit_pool < population * 0.1:
		recruit_pool += 1


func _vc_tax_collection() -> void:
	"""VC collects taxes/supplies from village"""
	var tax_amount: float = supply_stockpile * 0.3 * vc_presence

	if tax_amount > 0:
		supply_stockpile -= tax_amount
		vc_tax_collected.emit(self, tax_amount)

		# Increase VC influence through presence
		vc_presence = minf(vc_presence + 0.02, 1.0)


func _update_allegiance() -> void:
	"""Update village allegiance based on influence levels"""
	var old_allegiance: Allegiance = allegiance

	var net_influence: float = us_influence - vc_presence

	# Fear of violence pushes toward whoever caused it
	if fear_level > 0.3:
		net_influence *= 0.5  # Villagers just want to survive

	if net_influence > 0.3:
		allegiance = Allegiance.PRO_US
	elif net_influence < -0.3:
		allegiance = Allegiance.PRO_VC
	elif abs(net_influence) < 0.1:
		allegiance = Allegiance.NEUTRAL
	else:
		allegiance = Allegiance.CONTESTED

	if allegiance != old_allegiance:
		allegiance_changed.emit(self, allegiance)


func _get_allegiance_name() -> String:
	match allegiance:
		Allegiance.NEUTRAL:
			return "Neutral"
		Allegiance.PRO_US:
			return "Pro-US"
		Allegiance.PRO_VC:
			return "Pro-VC"
		Allegiance.CONTESTED:
			return "Contested"
	return "Unknown"


## Public API

func deliver_aid(amount: float) -> void:
	"""US delivers aid to village (hearts and minds)"""
	us_influence = minf(us_influence + amount * 0.01, 1.0)
	supply_stockpile += amount * 0.5  # Some aid goes to villagers

	us_aid_delivered.emit(self, amount)


func apply_civic_action(duration: float = 1.0) -> void:
	"""US performs civic action (medical aid, construction, etc.)"""
	us_influence = minf(us_influence + duration * 0.05, 1.0)
	vc_presence = maxf(vc_presence - duration * 0.02, 0.0)


func vc_infiltrate(strength: float = 0.1) -> void:
	"""VC increases presence in village"""
	vc_presence = minf(vc_presence + strength, 1.0)

	# Some villagers become sympathizers
	var new_sympathizers: int = int(population * strength * 0.05)
	vc_sympathizers = mini(vc_sympathizers + new_sympathizers, population / 5)


func recruit_for_vc() -> int:
	"""VC recruits fighters from village"""
	var recruits: int = mini(recruit_pool, 3)
	recruit_pool -= recruits
	population -= recruits

	if population < initial_population * 0.5:
		population_changed.emit(self, population)

	return recruits


func get_vc_sympathizers() -> int:
	"""Get hidden VC fighters in village"""
	return vc_sympathizers


func reveal_sympathizers() -> Array[Node3D]:
	"""Reveal hidden VC sympathizers as enemy combatants"""
	var revealed: Array[Node3D] = []

	var to_reveal: int = mini(vc_sympathizers, civilians.size())
	for i in to_reveal:
		if i < civilians.size():
			var civilian: Node3D = civilians[i]
			# Convert to VC fighter
			civilian.add_to_group("enemy_units")
			civilian.remove_from_group("civilians")

			# Change color to indicate enemy
			var mesh: MeshInstance3D = civilian.get_node_or_null("MeshInstance3D")
			if mesh and mesh.material_override:
				(mesh.material_override as StandardMaterial3D).albedo_color = Color(0.4, 0.35, 0.2)

			revealed.append(civilian)

	vc_sympathizers -= revealed.size()
	for r in revealed:
		civilians.erase(r)

	return revealed


func attack_by(attacker: Node3D) -> void:
	"""Village is attacked"""
	village_attacked.emit(self, attacker)

	# Increase fear
	fear_level = minf(fear_level + 0.2, 1.0)

	# If attacked by US, VC gains influence
	if attacker.is_in_group("player_units"):
		vc_presence = minf(vc_presence + 0.1, 1.0)
		us_influence = maxf(us_influence - 0.15, 0.0)


func civilian_casualty(killer: Node3D) -> void:
	"""A civilian was killed"""
	population -= 1
	civilian_killed.emit(self, killer)

	# Major influence penalty for killing civilians
	if killer.is_in_group("player_units"):
		us_influence = maxf(us_influence - 0.2, 0.0)
		vc_presence = minf(vc_presence + 0.1, 1.0)
		fear_level = minf(fear_level + 0.3, 1.0)

	population_changed.emit(self, population)


func get_supply_for_vc() -> float:
	"""Get available supplies for VC"""
	if allegiance == Allegiance.PRO_VC or vc_presence > 0.6:
		var amount: float = supply_stockpile * 0.5
		supply_stockpile -= amount
		return amount
	return 0.0


func get_intelligence_value() -> float:
	"""Get intelligence value (how much info villagers provide)"""
	if allegiance == Allegiance.PRO_US:
		return us_influence
	elif allegiance == Allegiance.PRO_VC:
		return -vc_presence  # Negative = provides intel to VC
	return 0.0
