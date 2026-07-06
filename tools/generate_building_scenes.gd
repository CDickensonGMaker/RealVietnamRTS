@tool
extends EditorScript

## Editor tool to generate .tscn scene files for all buildings with models
## Run via: Script Editor > File > Run (Ctrl+Shift+X)
##
## This creates placeable building scenes in game/scenes/buildings/
## Each building can then be dragged into levels in the Godot editor

const BuildingData = preload("res://firebase_system/building_data.gd")
const ConstructionZone = preload("res://firebase_system/construction_zone.gd")

const OUTPUT_DIR := "res://game/scenes/buildings/"
const PLACED_BUILDING_SCRIPT := "res://firebase_system/placed_building.gd"


func _run() -> void:
	print("=== Generating Building Scene Files ===")

	# Ensure output directory exists
	var dir := DirAccess.open("res://")
	if not dir:
		push_error("Failed to open res:// directory")
		return

	if not dir.dir_exists(OUTPUT_DIR):
		var err := dir.make_dir_recursive(OUTPUT_DIR)
		if err != OK:
			push_error("Failed to create output directory: %s" % OUTPUT_DIR)
			return

	var generated_count: int = 0
	var skipped_count: int = 0
	var missing_model_count: int = 0

	# Iterate all building types
	for type_name: String in BuildingData.BuildingType.keys():
		var building_type: int = BuildingData.BuildingType[type_name]

		# Skip if no model mapped
		if not ConstructionZone.BUILDING_MODELS.has(building_type):
			skipped_count += 1
			continue

		var model_path: String = ConstructionZone.BUILDING_MODELS[building_type]

		# Check if model file exists
		if not FileAccess.file_exists(model_path):
			print("  MISSING MODEL: %s -> %s" % [type_name, model_path])
			missing_model_count += 1
			continue

		# Get building data for this type
		var data: BuildingData = BuildingData.get_building_data(building_type)
		if not data:
			print("  NO DATA: %s" % type_name)
			skipped_count += 1
			continue

		# Generate scene file
		var scene_name: String = _type_to_filename(type_name)
		var scene_path: String = OUTPUT_DIR + scene_name + ".tscn"

		# Skip if already exists (don't overwrite manual edits)
		if FileAccess.file_exists(scene_path):
			#print("  EXISTS: %s" % scene_path)
			skipped_count += 1
			continue

		var success := _generate_scene_file(scene_path, type_name, building_type, data, model_path)
		if success:
			generated_count += 1
			print("  CREATED: %s" % scene_path)
		else:
			print("  FAILED: %s" % scene_path)

	print("")
	print("=== Generation Complete ===")
	print("  Generated: %d scenes" % generated_count)
	print("  Skipped (existing): %d" % skipped_count)
	print("  Missing models: %d" % missing_model_count)
	print("")
	print("NOTE: Reimport project (Project > Reload Current Project) to see new scenes")


func _type_to_filename(type_name: String) -> String:
	"""Convert ENUM_NAME to file_name"""
	return type_name.to_lower()


func _generate_scene_file(path: String, type_name: String, building_type: int, data: BuildingData, model_path: String) -> bool:
	"""Generate a .tscn scene file for a building"""

	# Calculate collision box size from footprint
	var footprint: Vector2 = data.footprint_size
	var height: float = 3.0  # Default height

	# Adjust height based on building category
	if type_name.contains("TOWER") or type_name.contains("OBSERVATION"):
		height = 8.0
	elif type_name.contains("BRIDGE"):
		height = 2.0
	elif type_name.contains("WIRE") or type_name.contains("CLAYMORE") or type_name.contains("PUNJI"):
		height = 1.0
	elif type_name.contains("SANDBAG") and not type_name.contains("BUNKER"):
		height = 1.5

	var collision_y: float = height / 2.0

	# Determine if this is an HQ building
	var auto_create_firebase: String = "true" if data.is_hq_building else "false"
	var influence_radius: float = data.influence_radius if data.is_hq_building else 0.0

	# Build scene content
	var scene_content := """[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="%s" id="1"]
[ext_resource type="PackedScene" path="%s" id="2"]

[sub_resource type="BoxShape3D" id="BoxShape3D_1"]
size = Vector3(%.1f, %.1f, %.1f)

[node name="%s" type="StaticBody3D"]
collision_layer = 64
collision_mask = 1
script = ExtResource("1")
building_type = %d
auto_create_firebase = %s
""" % [
		PLACED_BUILDING_SCRIPT,
		model_path,
		footprint.x, height, footprint.y,
		_type_to_scene_name(type_name),
		building_type,
		auto_create_firebase
	]

	# Add influence radius for HQ buildings
	if data.is_hq_building:
		scene_content += "firebase_influence_radius = %.1f\n" % influence_radius

	# Add model and collision nodes
	scene_content += """
[node name="Model" parent="." instance=ExtResource("2")]

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %.1f, 0)
shape = SubResource("BoxShape3D_1")
""" % collision_y

	# Write file
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Failed to open file for writing: %s" % path)
		return false

	file.store_string(scene_content)
	file.close()
	return true


func _type_to_scene_name(type_name: String) -> String:
	"""Convert ENUM_NAME to SceneName"""
	var parts := type_name.split("_")
	var result := ""
	for part: String in parts:
		result += part.capitalize()
	return result
