## Model Orientation Audit
##
## Visual inspection tool to determine correct model_rotation_y values.
## Shows each model at rotation.y = 0 with axis markers to identify:
## - Which direction the model's "front" faces
## - Which direction the model's "length" spans (for linear buildings)
##
## Usage:
## 1. Run this scene in Godot
## 2. Look at each model from above (Y-axis view)
## 3. Note which world axis the model's front/length aligns with
## 4. Calculate required model_rotation_y to make front face -Z (Godot forward)
##
## Convention:
## - Godot forward = -Z (negative Z)
## - If model faces +Z at rotation 0, need model_rotation_y = 180
## - If model faces +X at rotation 0, need model_rotation_y = -90 (or 270)
## - If model faces -X at rotation 0, need model_rotation_y = 90
## - If model faces -Z at rotation 0, need model_rotation_y = 0
extends Node3D

# Models to audit
const MODELS_TO_AUDIT := {
	# Linear placement buildings
	"sandbag_light": "res://assets/models/structures/firebase/sandbag_light.glb",
	"sandbag_heavy": "res://assets/models/structures/firebase/sandbag_heavy.glb",
	"barbed_wire": "res://assets/models/structures/converted/barbed_wire.glb",

	# Vehicles
	"bulldozer": "res://assets/models/vehicles/us_bulldozer.glb",
}

# Layout
const MODELS_PER_ROW := 4
const SPACING_X := 8.0
const SPACING_Z := 12.0

func _ready() -> void:
	var sep := "============================================================"
	print(sep)
	print("MODEL ORIENTATION AUDIT")
	print(sep)
	print("")
	print("All models shown at rotation.y = 0 (no rotation)")
	print("Axis colors: RED = +X (East), BLUE = +Z (South), GREEN = +Y (Up)")
	print("Arrow points in model's 'forward' direction (should be -Z for Godot)")
	print("")

	# Create world axis at origin
	_create_world_axis_markers()

	# Spawn each model
	var index := 0
	for model_name in MODELS_TO_AUDIT:
		var model_path: String = MODELS_TO_AUDIT[model_name]
		var row := index / MODELS_PER_ROW
		var col := index % MODELS_PER_ROW
		var position := Vector3(col * SPACING_X, 0, row * SPACING_Z + 5)

		_spawn_model_with_info(model_path, model_name, position)
		index += 1

	print(sep)
	print("INSTRUCTIONS")
	print(sep)
	print("1. Look at each model from above (press 7 on numpad for top view)")
	print("2. Identify which axis the model's FRONT faces at rotation 0")
	print("3. For LINEAR buildings, identify which axis the LENGTH spans")
	print("")
	print("Expected for correct orientation:")
	print("  - Vehicle FRONT should face -Z (toward cyan arrow)")
	print("  - Linear wall LENGTH should span along X axis (red line)")
	print(sep)


func _spawn_model_with_info(model_path: String, model_name: String, position: Vector3) -> void:
	var model_scene: PackedScene = load(model_path)
	if not model_scene:
		push_error("Failed to load model: " + model_path)
		print("  [MISSING] %s: %s" % [model_name, model_path])
		return

	# Spawn model
	var model: Node3D = model_scene.instantiate()
	model.position = position
	model.rotation.y = 0  # No rotation - show native orientation

	# Detect if model needs scaling (Spring 1944 models are in centimeters)
	var aabb := _get_model_aabb(model)
	var max_dim := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))

	# If model is huge (>100 units), assume centimeters and scale down
	if max_dim > 100:
		model.scale = Vector3(0.01, 0.01, 0.01)
		print("  [%s] Scaled 0.01 (was %.0f units, probably centimeters)" % [model_name, max_dim])
	else:
		print("  [%s] No scaling (max dimension: %.2f)" % [model_name, max_dim])

	add_child(model)

	# Get world-space bounds after scaling
	var world_aabb := _get_model_aabb(model)
	var world_size := world_aabb.size * model.scale

	# Determine length axis
	var length_axis := "X" if world_size.x > world_size.z else "Z"
	var width_axis := "Z" if length_axis == "X" else "X"

	print("    World size: (%.2f, %.2f, %.2f) - Length along %s" % [
		world_size.x, world_size.y, world_size.z, length_axis
	])

	# Add label
	var label_3d := Label3D.new()
	label_3d.text = "%s\nrot=0°\nL=%s" % [model_name, length_axis]
	label_3d.position = position + Vector3(0, 2.5, 0)
	label_3d.pixel_size = 0.01
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.font_size = 28
	add_child(label_3d)

	# Add local axis arrows on this model
	_create_model_axis_markers(position)


func _get_model_aabb(model: Node3D) -> AABB:
	var combined_aabb := AABB()
	var first := true

	for child in model.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.mesh:
				var child_aabb := mesh_instance.mesh.get_aabb()
				child_aabb = mesh_instance.transform * child_aabb
				if first:
					combined_aabb = child_aabb
					first = false
				else:
					combined_aabb = combined_aabb.merge(child_aabb)

		# Recurse into children
		for grandchild in child.get_children():
			if grandchild is MeshInstance3D:
				var mesh_instance := grandchild as MeshInstance3D
				if mesh_instance.mesh:
					var gc_aabb := mesh_instance.mesh.get_aabb()
					gc_aabb = grandchild.global_transform * gc_aabb
					if first:
						combined_aabb = gc_aabb
						first = false
					else:
						combined_aabb = combined_aabb.merge(gc_aabb)

	return combined_aabb


func _create_world_axis_markers() -> void:
	var axis_length := 3.0

	# X axis (RED) - East
	_create_axis_line(Vector3.ZERO, Vector3(axis_length, 0, 0), Color.RED, "+X (East)")

	# Z axis (BLUE) - South (Godot +Z)
	_create_axis_line(Vector3.ZERO, Vector3(0, 0, axis_length), Color.BLUE, "+Z (South)")

	# Y axis (GREEN) - Up
	_create_axis_line(Vector3.ZERO, Vector3(0, axis_length, 0), Color.GREEN, "+Y (Up)")

	# Forward indicator (-Z, which is Godot "forward")
	_create_axis_line(Vector3.ZERO, Vector3(0, 0, -axis_length), Color.CYAN, "-Z (Forward)")


func _create_model_axis_markers(center: Vector3) -> void:
	var axis_length := 1.5

	# Small local axis at model position
	_create_axis_line(center, center + Vector3(axis_length, 0, 0), Color.RED, "")
	_create_axis_line(center, center + Vector3(0, 0, axis_length), Color.BLUE, "")
	_create_axis_line(center, center + Vector3(0, 0, -axis_length), Color.CYAN, "")


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

	if label_text != "":
		var label_3d := Label3D.new()
		label_3d.text = label_text
		label_3d.position = end + Vector3(0, 0.3, 0)
		label_3d.pixel_size = 0.008
		label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label_3d.font_size = 24
		label_3d.modulate = color
		add_child(label_3d)
