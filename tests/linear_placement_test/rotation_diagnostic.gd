## Rotation Diagnostic Test
##
## Visual test to verify linear placement rotation at ALL angles.
## Shows a ring of models around a center point, each representing
## a different drag direction. The model's length should point
## ALONG each drag direction (like spokes of a wheel).
##
## PASS: All models point outward like wheel spokes
## FAIL: Models are perpendicular or at wrong angles
##
## Press keys to test different buildings:
##   1 = Sandbag Light
##   2 = Sandbag Heavy
##   3 = Wire Obstacle
##   4 = Triple Concertina
##
## Press R to rebuild with current settings
## Press Space to toggle rotation animation
extends Node3D

const BuildingData := preload("res://firebase_system/building_data.gd")

# Test configuration
var current_building_type: int = 0  # SANDBAG_LIGHT
var num_directions: int = 24  # Test every 15 degrees (more odd angles visible)
var ring_radius: float = 10.0  # Larger ring to fit more models
var animate_rotation: bool = false
var animation_speed: float = 0.5

# Building type enum values (from BuildingData.BuildingType)
const SANDBAG_LIGHT := 0
const SANDBAG_HEAVY := 1
const WIRE_OBSTACLE := 7
const TRIPLE_CONCERTINA := 8

# Model paths (matching ConstructionZone.BUILDING_MODELS)
const MODEL_PATHS := {
	0: "res://assets/models/structures/firebase/sandbag_light.glb",   # SANDBAG_LIGHT
	1: "res://assets/models/structures/firebase/sandbag_heavy.glb",   # SANDBAG_HEAVY
	7: "res://assets/models/structures/converted/barbed_wire.glb",    # WIRE_OBSTACLE
	8: "res://assets/models/structures/converted/barbed_wire.glb",    # TRIPLE_CONCERTINA
}

# Runtime
var _spawned_models: Array[Node3D] = []
var _direction_arrows: Array[Node3D] = []
var _footprint_markers: Array[Node3D] = []
var _current_rotation_offset: float = 0.0

@onready var _info_label: Label3D = $InfoLabel


func _ready() -> void:
	_print_instructions()
	_rebuild_test()


func _process(delta: float) -> void:
	if animate_rotation:
		_current_rotation_offset += delta * animation_speed
		_update_model_rotations()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				current_building_type = SANDBAG_LIGHT
				_rebuild_test()
			KEY_2:
				current_building_type = SANDBAG_HEAVY
				_rebuild_test()
			KEY_3:
				current_building_type = WIRE_OBSTACLE
				_rebuild_test()
			KEY_4:
				current_building_type = TRIPLE_CONCERTINA
				_rebuild_test()
			KEY_R:
				_rebuild_test()
			KEY_SPACE:
				animate_rotation = not animate_rotation
				print("Animation: %s" % ("ON" if animate_rotation else "OFF"))


func _print_instructions() -> void:
	print("=" .repeat(60))
	print("ROTATION DIAGNOSTIC TEST")
	print("=" .repeat(60))
	print("")
	print("This test spawns models around a ring, each at a different")
	print("'drag direction'. If rotation is correct, all model lengths")
	print("should point OUTWARD like spokes of a wheel.")
	print("")
	print("GREEN ARROW = Drag direction (where you'd drag TO)")
	print("RED LINE = Model's actual length axis")
	print("BLUE RECTANGLE = Expected footprint")
	print("")
	print("Controls:")
	print("  1 = Sandbag Light")
	print("  2 = Sandbag Heavy")
	print("  3 = Wire Obstacle")
	print("  4 = Triple Concertina")
	print("  R = Rebuild")
	print("  Space = Toggle rotation animation")
	print("=" .repeat(60))


func _rebuild_test() -> void:
	# Clear existing
	for model in _spawned_models:
		if is_instance_valid(model):
			model.queue_free()
	_spawned_models.clear()

	for arrow in _direction_arrows:
		if is_instance_valid(arrow):
			arrow.queue_free()
	_direction_arrows.clear()

	for marker in _footprint_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_footprint_markers.clear()

	# Get building data
	var data: BuildingData = BuildingData.get_building_data(current_building_type)
	if not data:
		push_error("No building data for type %d" % current_building_type)
		return

	var model_path: String = MODEL_PATHS.get(current_building_type, "")
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		push_error("No model for type %d at %s" % [current_building_type, model_path])
		return

	print("")
	print("Testing: %s" % data.display_name)
	print("  model_rotation_y = %.1f°" % data.model_rotation_y)
	print("  footprint = %v" % data.footprint_size)
	print("  model_scale = %.3f" % data.model_scale)
	print("")

	# Update info label
	if _info_label:
		_info_label.text = "%s\nmodel_rotation_y = %.0f°" % [data.display_name, data.model_rotation_y]

	# Spawn models at each direction
	var model_scene: PackedScene = load(model_path)
	if not model_scene:
		push_error("Failed to load model scene: %s" % model_path)
		return

	for i in range(num_directions):
		var angle_deg: float = (360.0 / num_directions) * i
		var angle_rad: float = deg_to_rad(angle_deg)

		# Direction vector (simulating drag direction)
		var direction := Vector3(sin(angle_rad), 0, cos(angle_rad))

		# Position on ring
		var pos := direction * ring_radius

		# Calculate rotation using the SAME formula as placement_controller
		# Model length aligns WITH drag direction (wall style)
		var direction_angle := atan2(-direction.x, -direction.z)
		var model_offset := deg_to_rad(data.model_rotation_y)
		var final_rotation := direction_angle + model_offset  # This is what construction_manager does

		# Spawn model
		var model: Node3D = model_scene.instantiate()
		if not model:
			push_error("Failed to instantiate model")
			continue
		model.position = pos
		model.rotation.y = final_rotation
		if data.model_scale != 1.0:
			model.scale = Vector3.ONE * data.model_scale
		add_child(model)
		_spawned_models.append(model)

		# Create direction arrow (green)
		var arrow := _create_direction_arrow(pos, direction, 2.0)
		add_child(arrow)
		_direction_arrows.append(arrow)

		# Create footprint marker (blue)
		var footprint := _create_footprint_marker(pos, final_rotation, data.footprint_size)
		add_child(footprint)
		_footprint_markers.append(footprint)

		# Print debug for cardinal directions
		if i % (num_directions / 4) == 0:
			var dir_name := _get_direction_name(angle_deg)
			print("  %s (%.0f°): dir_angle=%.1f° + offset=%.1f° = final=%.1f°" % [
				dir_name, angle_deg, rad_to_deg(direction_angle), data.model_rotation_y, rad_to_deg(final_rotation)
			])


func _update_model_rotations() -> void:
	var data: BuildingData = BuildingData.get_building_data(current_building_type)
	if not data:
		return

	for i in range(_spawned_models.size()):
		var model := _spawned_models[i]
		if not is_instance_valid(model):
			continue

		var angle_deg: float = (360.0 / num_directions) * i + rad_to_deg(_current_rotation_offset)
		var angle_rad: float = deg_to_rad(angle_deg)
		var direction := Vector3(sin(angle_rad), 0, cos(angle_rad))

		# Same formula as _rebuild_test - model length aligns with drag direction
		var direction_angle := atan2(-direction.x, -direction.z)
		var model_offset := deg_to_rad(data.model_rotation_y)
		var final_rotation := direction_angle + model_offset

		model.position = direction * ring_radius
		model.rotation.y = final_rotation

		# Update footprint position/rotation (don't recreate)
		if i < _footprint_markers.size() and is_instance_valid(_footprint_markers[i]):
			_footprint_markers[i].position = model.position
			_footprint_markers[i].rotation.y = final_rotation


func _create_direction_arrow(origin: Vector3, direction: Vector3, length: float) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var immediate_mesh := ImmediateMesh.new()

	var tip := origin + direction * length
	var y_offset := Vector3(0, 0.5, 0)

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_set_color(Color.GREEN)
	immediate_mesh.surface_add_vertex(origin + y_offset)
	immediate_mesh.surface_add_vertex(tip + y_offset)
	immediate_mesh.surface_end()

	mesh_instance.mesh = immediate_mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color.GREEN
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh_instance.material_override = material

	return mesh_instance


func _create_footprint_marker(pos: Vector3, rotation_y: float, size: Vector2) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()

	var hw := size.x * 0.5
	var hd := size.y * 0.5
	var y := 0.3

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINE_STRIP)

	# Rectangle outline
	var corners := [
		Vector3(-hw, y, -hd),
		Vector3(hw, y, -hd),
		Vector3(hw, y, hd),
		Vector3(-hw, y, hd),
		Vector3(-hw, y, -hd),  # Close the loop
	]

	for corner in corners:
		st.add_vertex(corner)

	mesh_instance.mesh = st.commit()
	mesh_instance.position = pos
	mesh_instance.rotation.y = rotation_y

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.5, 1.0, 0.8)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = material

	return mesh_instance


func _get_direction_name(angle_deg: float) -> String:
	# Normalize to 0-360
	angle_deg = fmod(angle_deg + 360.0, 360.0)

	if angle_deg < 22.5 or angle_deg >= 337.5:
		return "South"
	elif angle_deg < 67.5:
		return "SW"
	elif angle_deg < 112.5:
		return "West"
	elif angle_deg < 157.5:
		return "NW"
	elif angle_deg < 202.5:
		return "North"
	elif angle_deg < 247.5:
		return "NE"
	elif angle_deg < 292.5:
		return "East"
	else:
		return "SE"
