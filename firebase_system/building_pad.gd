class_name BuildingPad
extends StaticBody3D
## BuildingPad - Self-stamped flat collision pad for buildings
##
## When a building completes construction, this pad is created beneath it
## at the highest terrain corner. Buildings rest on this pad instead of
## directly on terrain, preventing clipping into slopes.
##
## The pad includes:
## - A flat CollisionShape3D for physics
## - A BuildingPadDecal child for visual blending to terrain

## Pad collision layer (terrain)
const PAD_COLLISION_LAYER := 1

## Padding around footprint for collision
const FOOTPRINT_PADDING := 0.5

## Visual components
var collision_shape: CollisionShape3D
var decal: BuildingPadDecal = null

## Pad data
var pad_size: Vector2 = Vector2.ZERO
var pad_height: float = 0.0


func _init() -> void:
	collision_layer = PAD_COLLISION_LAYER
	collision_mask = 0  # Pad doesn't need to detect collisions


## Create a building pad at the specified position
## Returns the pad, which should be added as a child of the building or scene
static func create_for_building(
	footprint_size: Vector2,
	world_position: Vector3,
	building_rotation: float = 0.0
) -> BuildingPad:
	var pad := BuildingPad.new()
	pad.name = "BuildingPad"

	# Calculate pad size with padding
	var padded_size := footprint_size + Vector2(FOOTPRINT_PADDING * 2, FOOTPRINT_PADDING * 2)
	pad.pad_size = padded_size

	# Sample terrain heights at footprint corners to find highest point
	var terrain := Engine.get_singleton("TerrainIntegration") if Engine.has_singleton("TerrainIntegration") else null
	if not terrain:
		terrain = pad.get_node_or_null("/root/TerrainIntegration")

	var half_x := footprint_size.x * 0.5
	var half_z := footprint_size.y * 0.5

	# Calculate corner positions considering rotation
	var corners: Array[Vector3] = []
	var sin_r := sin(building_rotation)
	var cos_r := cos(building_rotation)

	var local_corners: Array[Vector2] = [
		Vector2(-half_x, -half_z),
		Vector2(half_x, -half_z),
		Vector2(half_x, half_z),
		Vector2(-half_x, half_z),
	]

	for lc in local_corners:
		var rotated_x := lc.x * cos_r - lc.y * sin_r
		var rotated_z := lc.x * sin_r + lc.y * cos_r
		corners.append(Vector3(
			world_position.x + rotated_x,
			0,
			world_position.z + rotated_z
		))

	# Find highest corner
	var max_height: float = -INF
	if terrain and terrain.has_method("get_height_at"):
		for corner in corners:
			var h: float = terrain.get_height_at(corner)
			max_height = maxf(max_height, h)
	else:
		max_height = world_position.y

	pad.pad_height = max_height

	# Position pad at the highest corner height
	pad.global_position = Vector3(world_position.x, max_height, world_position.z)
	pad.rotation.y = building_rotation

	# Create collision shape
	pad._create_collision_shape(padded_size)

	# Create decal for visual blending
	pad._create_decal(footprint_size, corners, max_height, terrain)

	return pad


## Create the collision shape
func _create_collision_shape(size: Vector2) -> void:
	collision_shape = CollisionShape3D.new()
	collision_shape.name = "PadCollision"

	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 0.2, size.y)  # Thin box

	collision_shape.shape = box
	collision_shape.position = Vector3(0, -0.1, 0)  # Slightly below surface

	add_child(collision_shape)


## Create the blending decal
func _create_decal(footprint_size: Vector2, corners: Array[Vector3], max_height: float, terrain: Node) -> void:
	decal = BuildingPadDecal.new()
	decal.name = "PadDecal"

	# Position decal slightly above pad surface
	decal.position = Vector3(0, 0.5, 0)

	# Pass data to decal for setup
	decal.setup(footprint_size, corners, max_height, terrain, rotation.y)

	add_child(decal)


## Get the height buildings should use
func get_building_height() -> float:
	return pad_height


## Update decal if needed (e.g., after terrain modification)
func refresh_decal() -> void:
	if decal:
		decal.rebuild_mesh()


## Get the pad's AABB for culling/queries
func get_pad_aabb() -> AABB:
	var half := Vector3(pad_size.x * 0.5, 0.5, pad_size.y * 0.5)
	return AABB(global_position - half, half * 2)
