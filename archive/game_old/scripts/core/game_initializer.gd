extends Node
## GameInitializer - Sets up the game world and spawns initial units
## Attach to Main scene root

@export var spawn_test_units: bool = true
@export var starting_supplies: int = 150

# Scene references
var rifle_squad_scene: PackedScene
var engineer_squad_scene: PackedScene
var recon_team_scene: PackedScene
var command_post_scene: PackedScene

# Node references
@onready var player_squads: Node3D = $GameWorld/Units/PlayerSquads
@onready var enemy_squads: Node3D = $GameWorld/Units/EnemySquads
@onready var structures: Node3D = $GameWorld/Structures
@onready var terrain: Node3D = $GameWorld/Terrain
@onready var camera: Camera3D = $RTSCamera
@onready var directors: Node = $Directors

# UI references
@onready var ui: CanvasLayer = $UI
@onready var supply_panel: Control = $UI/SupplyPanel
@onready var squad_panel: Control = $UI/SquadPanel
@onready var build_menu: Control = $UI/BuildMenu


func _ready() -> void:
	print("[GameInitializer] Starting initialization...")

	_load_scenes()
	print("[GameInitializer] Scenes loaded - rifle: %s, engineer: %s, command_post: %s" % [
		rifle_squad_scene != null, engineer_squad_scene != null, command_post_scene != null
	])

	_setup_directors()
	_setup_ui()

	print("[GameInitializer] spawn_test_units = %s" % spawn_test_units)
	print("[GameInitializer] player_squads node = %s" % player_squads)
	print("[GameInitializer] structures node = %s" % structures)

	if spawn_test_units:
		_spawn_initial_units()
		print("[GameInitializer] Initial units spawned")

	# Set initial supplies
	GameManager.supplies = starting_supplies
	GameManager.max_supply_storage = 200

	# Start the game
	await get_tree().create_timer(0.5).timeout
	GameManager.start_game()
	print("[GameInitializer] Game started")


func _load_scenes() -> void:
	# Load unit scenes
	if ResourceLoader.exists("res://scenes/units/rifle_squad.tscn"):
		rifle_squad_scene = load("res://scenes/units/rifle_squad.tscn")
	if ResourceLoader.exists("res://scenes/units/engineer_squad.tscn"):
		engineer_squad_scene = load("res://scenes/units/engineer_squad.tscn")
	if ResourceLoader.exists("res://scenes/units/recon_team.tscn"):
		recon_team_scene = load("res://scenes/units/recon_team.tscn")
	if ResourceLoader.exists("res://scenes/structures/command_post.tscn"):
		command_post_scene = load("res://scenes/structures/command_post.tscn")


func _setup_directors() -> void:
	# Add AI Director if not present
	if not directors.has_node("AIDirector"):
		var ai_dir := Node.new()
		ai_dir.name = "AIDirector"
		ai_dir.set_script(load("res://scripts/directors/ai_director.gd"))
		directors.add_child(ai_dir)

	# Set firebase position for AI Director
	var ai_director: Node = directors.get_node_or_null("AIDirector")
	if ai_director:
		ai_director.set_firebase_position(Vector3(100, 0, 100))


func _setup_ui() -> void:
	# UI controller sets itself up in its own _ready()
	# No need to call setup() here - it causes duplicate UI elements
	pass


func _spawn_initial_units() -> void:
	# Spawn command post at center
	var command_post_pos := Vector3(100, 0, 100)
	_spawn_command_post(command_post_pos)

	# Spawn starting squads
	_spawn_rifle_squad(command_post_pos + Vector3(5, 0, 5))
	_spawn_rifle_squad(command_post_pos + Vector3(-5, 0, 5))
	_spawn_engineer_squad(command_post_pos + Vector3(0, 0, -5))

	# Focus camera on firebase
	if camera and camera.has_method("focus_on"):
		camera.focus_on(command_post_pos)


func _spawn_command_post(pos: Vector3) -> Node3D:
	var cp: Node3D
	if command_post_scene:
		cp = command_post_scene.instantiate()
		print("[GameInitializer] Command post instantiated from scene")
	else:
		# Create placeholder
		cp = _create_placeholder_structure("CommandPost", Vector3(6, 4, 6), Color(0.3, 0.35, 0.3))
		print("[GameInitializer] Command post created as placeholder")

	cp.global_position = pos
	structures.add_child(cp)
	GameManager.command_post = cp
	GameManager.register_structure(cp)
	return cp


func _spawn_rifle_squad(pos: Vector3) -> Node3D:
	var squad: Node3D
	if rifle_squad_scene:
		squad = rifle_squad_scene.instantiate()
		print("[GameInitializer] Rifle squad instantiated from scene")
	else:
		# Create placeholder with script
		squad = _create_placeholder_squad("RifleSquad", Color(0.2, 0.5, 0.2))
		print("[GameInitializer] Rifle squad created as placeholder")

	squad.global_position = pos
	player_squads.add_child(squad)
	print("[GameInitializer] Rifle squad added at position: %s, child count: %d" % [pos, player_squads.get_child_count()])
	return squad


func _spawn_engineer_squad(pos: Vector3) -> Node3D:
	var squad: Node3D
	if engineer_squad_scene:
		squad = engineer_squad_scene.instantiate()
		print("[GameInitializer] Engineer squad instantiated from scene")
	else:
		squad = _create_placeholder_squad("EngineerSquad", Color(0.5, 0.4, 0.2))
		print("[GameInitializer] Engineer squad created as placeholder")

	squad.global_position = pos
	player_squads.add_child(squad)
	print("[GameInitializer] Engineer squad added at position: %s, child count: %d" % [pos, player_squads.get_child_count()])
	return squad


func _create_placeholder_squad(squad_name: String, color: Color) -> CharacterBody3D:
	var squad := CharacterBody3D.new()
	squad.name = squad_name

	# Add collision shape
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.8
	shape.height = 2.0
	collision.shape = shape
	collision.position.y = 1.0
	squad.add_child(collision)

	# Add visual mesh (group of soldiers represented as cluster)
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.6
	mesh.bottom_radius = 0.8
	mesh.height = 1.5
	mesh_instance.mesh = mesh
	mesh_instance.position.y = 0.75

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material
	mesh_instance.name = "Mesh"
	squad.add_child(mesh_instance)

	# Add selection indicator
	var selection_ind := MeshInstance3D.new()
	var selection_mesh := TorusMesh.new()
	selection_mesh.inner_radius = 0.9
	selection_mesh.outer_radius = 1.1
	selection_ind.mesh = selection_mesh
	selection_ind.position.y = 0.1
	selection_ind.rotation.x = PI / 2

	var sel_material := StandardMaterial3D.new()
	sel_material.albedo_color = Color(0.2, 1.0, 0.2)
	sel_material.emission_enabled = true
	sel_material.emission = Color(0.2, 1.0, 0.2)
	sel_material.emission_energy_multiplier = 0.5
	selection_ind.material_override = sel_material
	selection_ind.name = "SelectionIndicator"
	selection_ind.visible = false
	squad.add_child(selection_ind)

	# Add script
	squad.set_script(load("res://scripts/units/base_squad.gd"))

	# Set collision layers
	squad.collision_layer = 2  # Units layer
	squad.collision_mask = 1 | 2 | 4  # Terrain, units, structures

	return squad


func _create_placeholder_structure(struct_name: String, size: Vector3, color: Color) -> StaticBody3D:
	var structure := StaticBody3D.new()
	structure.name = struct_name

	# Add collision
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position.y = size.y / 2
	structure.add_child(collision)

	# Add mesh
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position.y = size.y / 2

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material
	mesh_instance.name = "Mesh"
	structure.add_child(mesh_instance)

	# Add selection indicator
	var selection_ind := MeshInstance3D.new()
	var selection_mesh := BoxMesh.new()
	selection_mesh.size = Vector3(size.x + 0.2, 0.1, size.z + 0.2)
	selection_ind.mesh = selection_mesh
	selection_ind.position.y = 0.05

	var sel_material := StandardMaterial3D.new()
	sel_material.albedo_color = Color(0.2, 1.0, 0.2, 0.5)
	sel_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	selection_ind.material_override = sel_material
	selection_ind.name = "SelectionIndicator"
	selection_ind.visible = false
	structure.add_child(selection_ind)

	# Set collision layers
	structure.collision_layer = 4  # Structures layer
	structure.collision_mask = 0

	return structure


# Public spawn functions for runtime use

func spawn_squad(squad_type: String, position: Vector3) -> Node3D:
	match squad_type:
		"rifle":
			return _spawn_rifle_squad(position)
		"engineer":
			return _spawn_engineer_squad(position)
		_:
			push_warning("Unknown squad type: " + squad_type)
			return null
