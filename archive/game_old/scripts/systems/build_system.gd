extends Node
## BuildSystem - Handles structure placement and construction
## Validates placement, shows ghost preview, and manages construction queue

signal build_started(structure_type: String, position: Vector3)
signal build_completed(structure: Node3D)
signal build_cancelled

# Structure definitions
const STRUCTURES := {
	"sandbag": {
		"name": "Sandbag Wall",
		"cost": 0,
		"build_time": 5.0,
		"requires_engineer": false,
		"scene": "res://scenes/structures/sandbag.tscn",
		"footprint": Vector2(2, 1)
	},
	"foxhole": {
		"name": "Foxhole",
		"cost": 0,
		"build_time": 10.0,
		"requires_engineer": false,
		"scene": "res://scenes/structures/foxhole.tscn",
		"footprint": Vector2(3, 3)
	},
	"bunker": {
		"name": "Bunker",
		"cost": 30,
		"build_time": 30.0,
		"requires_engineer": true,
		"scene": "res://scenes/structures/bunker.tscn",
		"footprint": Vector2(4, 4)
	},
	"mg_nest": {
		"name": "MG Nest",
		"cost": 25,
		"build_time": 20.0,
		"requires_engineer": true,
		"scene": "res://scenes/structures/mg_nest.tscn",
		"footprint": Vector2(3, 3)
	},
	"mortar_pit": {
		"name": "Mortar Pit",
		"cost": 40,
		"build_time": 25.0,
		"requires_engineer": true,
		"scene": "res://scenes/structures/mortar_pit.tscn",
		"footprint": Vector2(4, 4)
	},
	"wire": {
		"name": "Wire Perimeter",
		"cost": 8,
		"build_time": 8.0,
		"requires_engineer": false,
		"scene": "res://scenes/structures/wire.tscn",
		"footprint": Vector2(4, 1)
	},
	"minefield": {
		"name": "Minefield",
		"cost": 20,
		"build_time": 15.0,
		"requires_engineer": true,
		"scene": "res://scenes/structures/minefield.tscn",
		"footprint": Vector2(5, 5)
	},
	"lz": {
		"name": "Landing Zone",
		"cost": 15,
		"build_time": 45.0,
		"requires_engineer": true,
		"scene": "res://scenes/structures/landing_zone.tscn",
		"footprint": Vector2(10, 10)
	},
	"supply_depot": {
		"name": "Supply Depot",
		"cost": 25,
		"build_time": 20.0,
		"requires_engineer": true,
		"scene": "res://scenes/structures/supply_depot.tscn",
		"footprint": Vector2(4, 4)
	},
	"aid_station": {
		"name": "Aid Station",
		"cost": 20,
		"build_time": 20.0,
		"requires_engineer": true,
		"scene": "res://scenes/structures/aid_station.tscn",
		"footprint": Vector2(4, 3)
	},
	"ammo_dump": {
		"name": "Ammo Dump",
		"cost": 15,
		"build_time": 15.0,
		"requires_engineer": true,
		"scene": "res://scenes/structures/ammo_dump.tscn",
		"footprint": Vector2(3, 3)
	},
	"observation_tower": {
		"name": "Observation Tower",
		"cost": 20,
		"build_time": 25.0,
		"requires_engineer": true,
		"scene": "res://scenes/structures/observation_tower.tscn",
		"footprint": Vector2(2, 2)
	}
}

# Placement state
var is_placing: bool = false
var current_structure_type: String = ""
var ghost_preview: Node3D = null
var placement_valid: bool = false
var placement_rotation: float = 0.0

# References
var camera: Camera3D
var structures_parent: Node3D

# Materials for ghost preview
var valid_material: StandardMaterial3D
var invalid_material: StandardMaterial3D


func _ready() -> void:
	# Create preview materials
	valid_material = StandardMaterial3D.new()
	valid_material.albedo_color = Color(0.2, 0.8, 0.2, 0.5)
	valid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	invalid_material = StandardMaterial3D.new()
	invalid_material.albedo_color = Color(0.8, 0.2, 0.2, 0.5)
	invalid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _process(delta: float) -> void:
	if is_placing and ghost_preview:
		_update_ghost_position()


func _unhandled_input(event: InputEvent) -> void:
	if not is_placing:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if placement_valid:
				_confirm_placement()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_placement()

	# Rotate with R key
	if event is InputEventKey:
		if event.keycode == KEY_R and event.pressed:
			placement_rotation += PI / 2
			if ghost_preview:
				ghost_preview.rotation.y = placement_rotation


func start_placement(structure_type: String) -> bool:
	## Begin placement mode for a structure type
	if structure_type not in STRUCTURES:
		push_warning("BuildSystem: Unknown structure type: " + structure_type)
		return false

	var struct_def: Dictionary = STRUCTURES[structure_type]

	# Check cost
	if struct_def.cost > 0 and GameManager.supplies < struct_def.cost:
		push_warning("BuildSystem: Insufficient supplies for " + structure_type)
		return false

	# Check engineer requirement
	if struct_def.requires_engineer and not _has_engineer_selected():
		push_warning("BuildSystem: Engineers required for " + structure_type)
		return false

	is_placing = true
	current_structure_type = structure_type
	placement_rotation = 0.0

	_create_ghost_preview(structure_type)

	return true


func _create_ghost_preview(structure_type: String) -> void:
	# Create a simple box as placeholder ghost
	var struct_def: Dictionary = STRUCTURES[structure_type]
	var footprint: Vector2 = struct_def.footprint

	ghost_preview = CSGBox3D.new()
	(ghost_preview as CSGBox3D).size = Vector3(footprint.x, 2.0, footprint.y)
	ghost_preview.material = valid_material

	if structures_parent:
		structures_parent.add_child(ghost_preview)
	else:
		get_tree().current_scene.add_child(ghost_preview)


func _update_ghost_position() -> void:
	if not camera:
		camera = get_viewport().get_camera_3d()

	if not camera:
		return

	# Raycast to ground
	var mouse_pos := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse_pos)
	var to := from + camera.project_ray_normal(mouse_pos) * 500.0

	var plane := Plane(Vector3.UP, 0)
	var intersection_result: Variant = plane.intersects_ray(from, to - from)

	if intersection_result:
		var intersection: Vector3 = intersection_result as Vector3
		# Snap to grid (optional)
		var grid_size := 1.0
		intersection.x = round(intersection.x / grid_size) * grid_size
		intersection.z = round(intersection.z / grid_size) * grid_size

		ghost_preview.global_position = intersection
		ghost_preview.global_position.y = 1.0  # Half height above ground

		# Check validity
		placement_valid = _check_placement_valid(intersection)
		ghost_preview.material = valid_material if placement_valid else invalid_material


func _check_placement_valid(position: Vector3) -> bool:
	var struct_def: Dictionary = STRUCTURES[current_structure_type]
	var footprint: Vector2 = struct_def.footprint

	# Check terrain bounds
	if position.x < footprint.x / 2 or position.x > 200 - footprint.x / 2:
		return false
	if position.z < footprint.y / 2 or position.z > 200 - footprint.y / 2:
		return false

	# Check collision with existing structures
	var space_state := ghost_preview.get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = Vector3(footprint.x - 0.5, 2.0, footprint.y - 0.5)

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D.IDENTITY.translated(position)
	query.collision_mask = 4  # Structure layer

	var results := space_state.intersect_shape(query, 1)
	if not results.is_empty():
		return false

	return true


func _confirm_placement() -> void:
	if not placement_valid:
		return

	var struct_def: Dictionary = STRUCTURES[current_structure_type]
	var position := ghost_preview.global_position
	position.y = 0

	# Spend supplies
	if struct_def.cost > 0:
		if not GameManager.spend_supplies(struct_def.cost):
			return

	# Create construction site
	_start_construction(current_structure_type, position, placement_rotation)

	build_started.emit(current_structure_type, position)

	# Clean up
	_cleanup_ghost()
	is_placing = false
	current_structure_type = ""


func cancel_placement() -> void:
	_cleanup_ghost()
	is_placing = false
	current_structure_type = ""
	build_cancelled.emit()


func _cleanup_ghost() -> void:
	if ghost_preview:
		ghost_preview.queue_free()
		ghost_preview = null


func _start_construction(structure_type: String, position: Vector3, rot: float) -> void:
	var struct_def: Dictionary = STRUCTURES[structure_type]

	# For now, instantly place structure (construction queue to be added)
	# In full implementation, this would create a construction site
	# that engineers work on over time

	# Try to load the structure scene
	if ResourceLoader.exists(struct_def.scene):
		var scene := load(struct_def.scene) as PackedScene
		if scene:
			var instance := scene.instantiate()
			instance.global_position = position
			instance.rotation.y = rot

			if structures_parent:
				structures_parent.add_child(instance)
			else:
				get_tree().current_scene.get_node("GameWorld/Structures").add_child(instance)

			GameManager.register_structure(instance)
			build_completed.emit(instance)
			return

	# Fallback: create placeholder
	var placeholder := CSGBox3D.new()
	var footprint: Vector2 = struct_def.footprint
	placeholder.size = Vector3(footprint.x, 2.0, footprint.y)
	placeholder.global_position = position + Vector3(0, 1, 0)
	placeholder.rotation.y = rot

	if structures_parent:
		structures_parent.add_child(placeholder)
	else:
		get_tree().current_scene.get_node("GameWorld/Structures").add_child(placeholder)

	GameManager.register_structure(placeholder)
	build_completed.emit(placeholder)


func _has_engineer_selected() -> bool:
	# Check if any selected units are engineers
	# For now, return true (selection system integration needed)
	return true


func get_structure_info(structure_type: String) -> Dictionary:
	return STRUCTURES.get(structure_type, {})


func get_all_structure_types() -> Array:
	return STRUCTURES.keys()


func can_build(structure_type: String) -> bool:
	if structure_type not in STRUCTURES:
		return false

	var struct_def: Dictionary = STRUCTURES[structure_type]

	# Check supplies
	if struct_def.cost > GameManager.supplies:
		return false

	# Check engineer requirement
	if struct_def.requires_engineer and not _has_engineer_selected():
		return false

	return true
