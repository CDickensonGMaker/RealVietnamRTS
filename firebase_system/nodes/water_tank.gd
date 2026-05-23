class_name WaterTank extends Node3D
## Water Tank - Self-filling water supply for firebase
##
## Water tanks auto-fill over time (simulating rain collection, well, etc.)
## Units in firebase range need water to fight - broken tank = can't reload.
## Tanks can be damaged and need repair.

signal water_depleted
signal water_low  ## Emitted at 20%
signal tank_broken
signal tank_repaired

## Configuration
@export var max_water: float = 100.0
@export var fill_rate: float = 5.0         ## Units per minute (self-filling)
@export var consume_rate: float = 2.0      ## Per unit per minute in firebase
@export var max_health: float = 100.0

## State
var water_level: float = 100.0
var is_broken: bool = false
var current_health: float = 100.0
var faction: int = 0  # GameEnums.Faction
var is_player_controlled: bool = true

## Visual
var _tank_mesh: MeshInstance3D = null


func _ready() -> void:
	add_to_group("water_tanks")
	add_to_group("fortifications")
	add_to_group("all_units")

	if is_player_controlled:
		add_to_group("player_structures")
	else:
		add_to_group("enemy_structures")

	water_level = max_water
	current_health = max_health

	_create_visual()


func _process(delta: float) -> void:
	if is_broken:
		# Broken tanks drain faster, no refill
		var firebase := _get_parent_firebase()
		if firebase:
			var pop := _get_firebase_population(firebase)
			water_level -= consume_rate * pop * delta / 60.0 * 2.0  # 2x drain when broken
		return

	# Self-fill (rain collection, well, etc.)
	water_level += fill_rate * delta / 60.0

	# Consumption based on firebase population
	var firebase := _get_parent_firebase()
	if firebase:
		var pop := _get_firebase_population(firebase)
		water_level -= consume_rate * pop * delta / 60.0

	# Clamp
	var old_level := water_level
	water_level = clampf(water_level, 0.0, max_water)

	# Emit signals on thresholds
	if water_level <= 0 and old_level > 0:
		water_depleted.emit()
	elif water_level < max_water * 0.2 and old_level >= max_water * 0.2:
		water_low.emit()


func _create_visual() -> void:
	# Simple cylindrical tank visual
	_tank_mesh = MeshInstance3D.new()
	_tank_mesh.name = "Tank"

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.5
	cylinder.bottom_radius = 1.5
	cylinder.height = 2.5
	_tank_mesh.mesh = cylinder
	_tank_mesh.position.y = 1.25

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.3, 0.35)  # Metal gray
	_tank_mesh.material_override = mat

	add_child(_tank_mesh)

	# Support structure (simple legs)
	var legs := MeshInstance3D.new()
	var leg_box := BoxMesh.new()
	leg_box.size = Vector3(2.5, 0.5, 2.5)
	legs.mesh = leg_box
	legs.position.y = 0.25

	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = Color(0.2, 0.2, 0.2)
	legs.material_override = leg_mat
	add_child(legs)

	# Collision
	var body := StaticBody3D.new()
	body.name = "Body"
	var coll := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.5
	shape.height = 2.5
	coll.shape = shape
	coll.position.y = 1.25
	body.add_child(coll)
	body.collision_layer = 64  # Buildings layer
	add_child(body)


func _get_parent_firebase() -> Node3D:
	# Check if we're a child of a firebase
	var parent := get_parent()
	while parent:
		if parent.is_in_group("firebases"):
			return parent as Node3D
		parent = parent.get_parent()

	# Fall back to finding nearest firebase
	var firebases := get_tree().get_nodes_in_group("firebases")
	var nearest: Node3D = null
	var nearest_dist := 999999.0

	for fb in firebases:
		if not is_instance_valid(fb) or not fb is Node3D:
			continue
		var dist: float = global_position.distance_to(fb.global_position)
		if dist < nearest_dist:
			nearest = fb as Node3D
			nearest_dist = dist

	return nearest


func _get_firebase_population(firebase: Node3D) -> int:
	# Count units within firebase radius
	if not firebase:
		return 0

	# Check for garrison property
	if "garrison" in firebase:
		var garrison_array: Array = firebase.garrison
		return garrison_array.size()

	# Count units in "all_units" within firebase radius
	var radius: float = 50.0
	if firebase.has_method("get_firebase_radius"):
		radius = firebase.get_firebase_radius()

	var count := 0
	for unit in get_tree().get_nodes_in_group("all_units"):
		if not is_instance_valid(unit) or not unit is Node3D:
			continue
		if unit.global_position.distance_to(firebase.global_position) <= radius:
			count += 1

	return count


# =============================================================================
# WATER ACCESS
# =============================================================================

## Check if water tank is providing water
func is_working() -> bool:
	return not is_broken and water_level > 0


## Check if this is a water tank (for Firebase.has_water() duck typing)
func is_water_tank() -> bool:
	return true


func get_water_percent() -> float:
	return water_level / max_water


# =============================================================================
# DAMAGE & REPAIR
# =============================================================================

func take_damage(amount: float, _source: Node = null) -> void:
	current_health -= amount

	if current_health <= 0 and not is_broken:
		break_down()


func break_down() -> void:
	is_broken = true
	tank_broken.emit()
	print("[WaterTank] Broken! Needs repair.")

	# Visual: tilt the tank
	if _tank_mesh:
		_tank_mesh.rotation.z = deg_to_rad(15)

		var mat := _tank_mesh.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.3, 0.25, 0.2)  # Rusty


func repair() -> void:
	is_broken = false
	current_health = max_health
	tank_repaired.emit()
	print("[WaterTank] Repaired!")

	# Reset visual
	if _tank_mesh:
		_tank_mesh.rotation.z = 0

		var mat := _tank_mesh.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.25, 0.3, 0.35)  # Normal metal


## Check if tank can be repaired
func needs_repair() -> bool:
	return is_broken


## Start repair by engineer (called by job system)
func start_repair() -> void:
	# Would be called by WorkerController when repairing
	repair()


# =============================================================================
# STATIC FACTORY
# =============================================================================

static func create(world_position: Vector3) -> WaterTank:
	var tank := WaterTank.new()
	tank.position = world_position
	tank.name = "WaterTank"
	return tank
