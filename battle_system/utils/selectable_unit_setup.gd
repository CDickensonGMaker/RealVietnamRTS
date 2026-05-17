class_name SelectableUnitSetup
extends RefCounted
## Utility for setting up player-controlled units with synced collision and visuals
## Use this to ensure selection hitboxes match visual positions
##
## Usage:
##   var setup := SelectableUnitSetup.new()
##   setup.setup_selectable(unit_node, collision_shape, faction, is_vehicle)
##
## Or for automatic bounds-based collision:
##   setup.create_collision_from_model(unit_node, model_instance, faction)

# Standard height offsets for unit types (matches Squad.gd)
const INFANTRY_CENTER_Y := 0.9
const VEHICLE_CENTER_Y := 0.75
const HELICOPTER_CENTER_Y := 2.0

# Collision layers per project.godot
const LAYER_TERRAIN := 1
const LAYER_US_UNITS := 2      # bit 1
const LAYER_VC_UNITS := 4      # bit 2
const LAYER_NVA_UNITS := 8     # bit 3
const LAYER_VEHICLES := 16     # bit 4
const LAYER_HELICOPTERS := 32  # bit 5
const LAYER_BUILDINGS := 64    # bit 6


## Setup a unit to be properly selectable
## - Sets collision layer based on faction
## - Ensures collision shape is positioned at visual center
## - Adds to appropriate groups
static func setup_selectable(
	unit: CharacterBody3D,
	collision_shape: CollisionShape3D,
	faction: int,
	is_vehicle: bool = false,
	is_helicopter: bool = false
) -> void:
	# Position collision at visual center
	var center_y: float = INFANTRY_CENTER_Y
	if is_helicopter:
		center_y = HELICOPTER_CENTER_Y
	elif is_vehicle:
		center_y = VEHICLE_CENTER_Y

	collision_shape.position.y = center_y

	# Set collision layer based on faction
	match faction:
		GameEnums.Faction.US_ARMY, GameEnums.Faction.ARVN:
			unit.collision_layer = LAYER_US_UNITS
		GameEnums.Faction.VC:
			unit.collision_layer = LAYER_VC_UNITS
		GameEnums.Faction.NVA:
			unit.collision_layer = LAYER_NVA_UNITS
		_:
			unit.collision_layer = LAYER_US_UNITS  # Default

	# Additional layer for vehicles/helicopters
	if is_vehicle:
		unit.collision_layer |= LAYER_VEHICLES
	if is_helicopter:
		unit.collision_layer |= LAYER_HELICOPTERS

	# Set mask to collide with terrain only (for ground movement)
	unit.collision_mask = LAYER_TERRAIN

	# Add to groups for selection system
	unit.add_to_group("all_units")

	# Player/enemy group based on faction
	var is_player: bool = (faction == GameEnums.Faction.US_ARMY or faction == GameEnums.Faction.ARVN)
	if is_player:
		unit.add_to_group("player_units")
	else:
		unit.add_to_group("enemy_units")


## Create a collision shape that matches the visual bounds of a model
## Returns the CollisionShape3D with properly sized shape
static func create_collision_from_model(
	model: Node3D,
	is_vehicle: bool = false
) -> CollisionShape3D:
	var collision_shape := CollisionShape3D.new()

	# Calculate model bounds
	var aabb: AABB = _calculate_model_bounds(model)

	if is_vehicle:
		# Use box for vehicles
		var box := BoxShape3D.new()
		box.size = aabb.size
		collision_shape.shape = box
		collision_shape.position.y = aabb.size.y / 2.0
	else:
		# Use capsule for infantry (more forgiving click detection)
		var capsule := CapsuleShape3D.new()
		capsule.radius = maxf(aabb.size.x, aabb.size.z) / 2.0
		capsule.height = aabb.size.y
		collision_shape.shape = capsule
		collision_shape.position.y = aabb.size.y / 2.0

	return collision_shape


## Auto-setup a unit with collision based on loaded model
## This is the simplest way to ensure visual/collision sync
static func auto_setup_from_model(
	unit: CharacterBody3D,
	model: Node3D,
	faction: int,
	is_vehicle: bool = false,
	is_helicopter: bool = false
) -> CollisionShape3D:
	# Create collision from model bounds
	var collision := create_collision_from_model(model, is_vehicle)
	unit.add_child(collision)

	# Setup selectable properties
	setup_selectable(unit, collision, faction, is_vehicle, is_helicopter)

	return collision


## Create a standard infantry collision shape
## Use when model bounds calculation isn't needed
static func create_infantry_collision() -> CollisionShape3D:
	var collision_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 1.8
	collision_shape.shape = capsule
	collision_shape.position.y = INFANTRY_CENTER_Y
	return collision_shape


## Create a standard vehicle collision shape
static func create_vehicle_collision(size: Vector3 = Vector3(2.0, 1.5, 4.0)) -> CollisionShape3D:
	var collision_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision_shape.shape = box
	collision_shape.position.y = VEHICLE_CENTER_Y
	return collision_shape


## Sync visual position with collision
## Call this if model has a custom offset
static func sync_visual_to_collision(
	model: Node3D,
	collision_shape: CollisionShape3D
) -> void:
	# Match model center to collision center
	model.position.y = collision_shape.position.y - _get_model_center_y(model)


## Get the visual center Y offset for a unit type
static func get_center_offset(is_vehicle: bool = false, is_helicopter: bool = false) -> float:
	if is_helicopter:
		return HELICOPTER_CENTER_Y
	elif is_vehicle:
		return VEHICLE_CENTER_Y
	else:
		return INFANTRY_CENTER_Y


## Calculate the AABB bounds of a model including all children
static func _calculate_model_bounds(model: Node3D) -> AABB:
	var aabb := AABB()
	var first := true

	for child in _get_all_mesh_instances(model):
		var mesh_instance: MeshInstance3D = child
		if mesh_instance.mesh:
			var child_aabb: AABB = mesh_instance.mesh.get_aabb()
			# Transform to model space
			child_aabb = mesh_instance.global_transform * child_aabb
			child_aabb.position -= model.global_position

			if first:
				aabb = child_aabb
				first = false
			else:
				aabb = aabb.merge(child_aabb)

	# Fallback if no meshes found
	if first:
		aabb = AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1.8, 1))

	return aabb


## Recursively find all MeshInstance3D nodes
static func _get_all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []

	if node is MeshInstance3D:
		result.append(node)

	for child in node.get_children():
		result.append_array(_get_all_mesh_instances(child))

	return result


## Get the center Y position of a model based on its mesh bounds
static func _get_model_center_y(model: Node3D) -> float:
	var aabb := _calculate_model_bounds(model)
	return aabb.position.y + aabb.size.y / 2.0


## Debug helper - visualize the collision shape
static func visualize_collision(collision_shape: CollisionShape3D, color: Color = Color(0, 1, 0, 0.3)) -> MeshInstance3D:
	var debug_mesh := MeshInstance3D.new()

	if collision_shape.shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = collision_shape.shape
		var mesh := CapsuleMesh.new()
		mesh.radius = capsule.radius
		mesh.height = capsule.height
		debug_mesh.mesh = mesh
	elif collision_shape.shape is BoxShape3D:
		var box: BoxShape3D = collision_shape.shape
		var mesh := BoxMesh.new()
		mesh.size = box.size
		debug_mesh.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_mesh.material_override = mat

	debug_mesh.position = collision_shape.position

	return debug_mesh
