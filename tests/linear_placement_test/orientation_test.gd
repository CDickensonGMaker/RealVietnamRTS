## Empirical Test: Linear Placement Model Orientation
##
## This test scene spawns sandbag_light.glb at different Y rotations to verify
## which rotation makes the model's 2m length dimension span the world X-axis.
##
## Expected behavior (if models are correctly authored):
## - At rotation.y = 0: Model's length (2m) should span local X = world X
## - At rotation.y = 90° (PI/2): Model's length should span world -Z
## - At rotation.y = 180° (PI): Model's length should span world -X
## - At rotation.y = 270° (3*PI/2): Model's length should span world +Z
##
## Reference: War Room synthesis at:
## production/war_room/linear_placement_orientation/synthesis.md
extends Node3D

const SANDBAG_PATH := "res://assets/models/structures/firebase/sandbag_light.glb"
const BARBED_WIRE_PATH := "res://assets/models/structures/converted/barbed_wire.glb"

# Test rotations in degrees
const TEST_ROTATIONS := [0.0, 90.0, 180.0, 270.0]

# Spacing between test models
const MODEL_SPACING := 5.0

var _test_results: Dictionary = {}

func _ready() -> void:
	var sep := "============================================================"
	print(sep)
	print("LINEAR PLACEMENT ORIENTATION TEST")
	print(sep)
	print("")

	# Create axis visualization
	_create_world_axis_markers()

	# Test sandbag model
	print("--- SANDBAG_LIGHT TEST ---")
	_spawn_test_row(SANDBAG_PATH, "Sandbag", Vector3(0, 0, 0))

	# Test barbed wire model
	print("")
	print("--- BARBED_WIRE TEST ---")
	_spawn_test_row(BARBED_WIRE_PATH, "BarbedWire", Vector3(0, 0, 10))

	# Print analysis
	print("")
	print(sep)
	print("VISUAL INSPECTION GUIDE")
	print(sep)
	print("- RED LINE = World +X axis (East)")
	print("- BLUE LINE = World +Z axis (South in Godot)")
	print("- GREEN LINE = World +Y axis (Up)")
	print("")
	print("For CoH-style behavior, painting EAST should produce:")
	print("  -> Model's LENGTH axis spanning EAST-WEST (along red line)")
	print("")
	print("Look at each rotation and note which one aligns the LONG")
	print("dimension (2m for sandbag, 6m for wire) with the RED line.")
	print(sep)


func _spawn_test_row(model_path: String, label: String, base_position: Vector3) -> void:
	var model_scene: PackedScene = load(model_path)
	if not model_scene:
		push_error("Failed to load model: " + model_path)
		return

	for i in range(TEST_ROTATIONS.size()):
		var rotation_deg: float = TEST_ROTATIONS[i]
		var position := base_position + Vector3(i * MODEL_SPACING, 0, 0)

		# Spawn model
		var model: Node3D = model_scene.instantiate()
		model.position = position
		model.rotation.y = deg_to_rad(rotation_deg)
		model.scale = Vector3(0.01, 0.01, 0.01)  # Match game scale
		add_child(model)

		# Add label
		_add_rotation_label(position, rotation_deg, label)

		# Calculate and print model bounds
		var aabb := _get_model_aabb(model)
		var world_size := aabb.size * model.scale

		print("  %s @ %d°: World size = (%.2f, %.2f, %.2f)" % [
			label,
			int(rotation_deg),
			world_size.x,
			world_size.y,
			world_size.z
		])

		# Determine which axis is "length" (largest horizontal dimension)
		var length_axis := "X" if world_size.x > world_size.z else "Z"
		print("    -> Length axis in WORLD space: %s (%.2fm)" % [
			length_axis,
			maxf(world_size.x, world_size.z)
		])


func _get_model_aabb(model: Node3D) -> AABB:
	var combined_aabb := AABB()
	var first := true

	for child in model.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.mesh:
				var child_aabb := mesh_instance.mesh.get_aabb()
				# Transform by child's local transform
				child_aabb = mesh_instance.transform * child_aabb
				if first:
					combined_aabb = child_aabb
					first = false
				else:
					combined_aabb = combined_aabb.merge(child_aabb)

	return combined_aabb


func _add_rotation_label(position: Vector3, rotation_deg: float, label: String) -> void:
	var label_3d := Label3D.new()
	label_3d.text = "%s\n%d°" % [label, int(rotation_deg)]
	label_3d.position = position + Vector3(0, 1.5, 0)
	label_3d.pixel_size = 0.01
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.font_size = 32
	add_child(label_3d)


func _create_world_axis_markers() -> void:
	# Create visual axis indicators at origin
	var axis_length := 3.0

	# X axis (RED) - East
	_create_axis_line(Vector3.ZERO, Vector3(axis_length, 0, 0), Color.RED, "X (East)")

	# Z axis (BLUE) - South (Godot +Z)
	_create_axis_line(Vector3.ZERO, Vector3(0, 0, axis_length), Color.BLUE, "Z (South)")

	# Y axis (GREEN) - Up
	_create_axis_line(Vector3.ZERO, Vector3(0, axis_length, 0), Color.GREEN, "Y (Up)")

	# Forward indicator (-Z, which is Godot "forward")
	_create_axis_line(Vector3.ZERO, Vector3(0, 0, -axis_length), Color.CYAN, "-Z (Forward)")


func _create_axis_line(start: Vector3, end: Vector3, color: Color, label_text: String) -> void:
	var mesh_instance := MeshInstance3D.new()
	var immediate_mesh := ImmediateMesh.new()

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_set_color(color)
	immediate_mesh.surface_add_vertex(start)
	immediate_mesh.surface_add_vertex(end)
	immediate_mesh.surface_end()

	mesh_instance.mesh = immediate_mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh_instance.material_override = material

	add_child(mesh_instance)

	# Add label at end of axis
	var label_3d := Label3D.new()
	label_3d.text = label_text
	label_3d.position = end + Vector3(0, 0.3, 0)
	label_3d.pixel_size = 0.008
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.font_size = 24
	label_3d.modulate = color
	add_child(label_3d)
