extends Node
## EnemySpawner - Spawns enemy units based on AI Director commands
## Manages enemy positions and assault waves

signal enemy_spawned(enemy: Node3D)
signal wave_spawned(wave_number: int, enemy_count: int)

# Scene references
var vc_infantry_scene: PackedScene
var nva_regular_scene: PackedScene
var sapper_scene: PackedScene

# References
var enemy_squads_parent: Node3D
var ai_director: Node

# Spawn points (edges of map for assaults)
var assault_spawn_points: Array[Vector3] = []
var map_size: Vector2 = Vector2(200, 200)


func _ready() -> void:
	_setup_spawn_points()
	_load_scenes()

	# Find references
	await get_tree().process_frame
	var squads_node: Node = get_tree().current_scene.get_node_or_null("GameWorld/Units/EnemySquads")
	enemy_squads_parent = squads_node as Node3D
	ai_director = get_tree().current_scene.get_node_or_null("Directors/AIDirector")

	if ai_director:
		ai_director.assault_wave_starting.connect(_on_assault_wave)


func _setup_spawn_points() -> void:
	# Create spawn points around map edges
	var edge_distance := 10.0
	var center := Vector3(map_size.x / 2, 0, map_size.y / 2)

	# North edge
	for i in range(5):
		var x := edge_distance + (map_size.x - edge_distance * 2) * (i / 4.0)
		assault_spawn_points.append(Vector3(x, 0, edge_distance))

	# South edge
	for i in range(5):
		var x := edge_distance + (map_size.x - edge_distance * 2) * (i / 4.0)
		assault_spawn_points.append(Vector3(x, 0, map_size.y - edge_distance))

	# East edge
	for i in range(5):
		var z := edge_distance + (map_size.y - edge_distance * 2) * (i / 4.0)
		assault_spawn_points.append(Vector3(map_size.x - edge_distance, 0, z))

	# West edge
	for i in range(5):
		var z := edge_distance + (map_size.y - edge_distance * 2) * (i / 4.0)
		assault_spawn_points.append(Vector3(edge_distance, 0, z))


func _load_scenes() -> void:
	if ResourceLoader.exists("res://scenes/units/vc_infantry.tscn"):
		vc_infantry_scene = load("res://scenes/units/vc_infantry.tscn")
	if ResourceLoader.exists("res://scenes/units/nva_regular.tscn"):
		nva_regular_scene = load("res://scenes/units/nva_regular.tscn")


func _on_assault_wave(wave_number: int, direction: Vector3) -> void:
	# Get wave composition from AI Director
	var infantry_count := 10 + wave_number * 3

	# Find spawn points in the attack direction
	var firebase_pos := Vector3(map_size.x / 2, 0, map_size.y / 2)
	var spawn_center := firebase_pos - direction * 80.0

	# Clamp to map bounds
	spawn_center.x = clamp(spawn_center.x, 10, map_size.x - 10)
	spawn_center.z = clamp(spawn_center.z, 10, map_size.y - 10)

	# Spawn infantry squads
	var squads_spawned := 0
	var squad_size := 8

	while infantry_count > 0:
		var this_squad_size := mini(squad_size, infantry_count)
		var spawn_offset := Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		var spawn_pos := spawn_center + spawn_offset

		var enemy := spawn_vc_infantry(spawn_pos)
		if enemy:
			# Set assault behavior
			enemy.advance_to(GameManager.command_post)
			squads_spawned += 1

		infantry_count -= this_squad_size

	wave_spawned.emit(wave_number, squads_spawned)


func spawn_vc_infantry(position: Vector3) -> Node3D:
	var enemy: Node3D

	if vc_infantry_scene:
		enemy = vc_infantry_scene.instantiate()
	else:
		enemy = _create_placeholder_enemy("VCInfantry")

	enemy.global_position = position

	if enemy_squads_parent:
		enemy_squads_parent.add_child(enemy)
	else:
		get_tree().current_scene.add_child(enemy)

	enemy_spawned.emit(enemy)
	return enemy


func spawn_test_enemies(count: int, near_position: Vector3, radius: float = 30.0) -> Array[Node3D]:
	## Spawn test enemies in a radius around a position
	var spawned: Array[Node3D] = []

	for i in count:
		var angle := randf() * TAU
		var dist := randf_range(radius * 0.5, radius)
		var offset := Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		var spawn_pos := near_position + offset

		var enemy := spawn_vc_infantry(spawn_pos)
		if enemy:
			spawned.append(enemy)

	return spawned


func _create_placeholder_enemy(enemy_name: String) -> CharacterBody3D:
	var enemy := CharacterBody3D.new()
	enemy.name = enemy_name

	# Add collision
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.7
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	enemy.add_child(collision)

	# Add mesh - red tinted to distinguish from player
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.4
	mesh.bottom_radius = 0.6
	mesh.height = 1.2
	mesh_instance.mesh = mesh
	mesh_instance.position.y = 0.6

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.3, 0.25)  # Brownish-red
	mesh_instance.material_override = material
	mesh_instance.name = "Mesh"
	enemy.add_child(mesh_instance)

	# Add script
	enemy.set_script(load("res://scripts/units/enemy_squad.gd"))

	# Set collision layers
	enemy.collision_layer = 2
	enemy.collision_mask = 7

	return enemy
