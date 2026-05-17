extends BaseStructure
class_name CommandPost
## CommandPost - The heart of the firebase
## Spawns units, if destroyed = game over

signal unit_spawned(unit: Node3D)
signal spawn_queue_changed(queue: Array)

# Spawn configuration
const SPAWN_COSTS := {
	"rifle_squad": 20,
	"engineer_squad": 25,
	"recon_team": 15,
	"weapons_squad": 35,
	"medic_team": 15
}

const SPAWN_TIMES := {
	"rifle_squad": 10.0,
	"engineer_squad": 12.0,
	"recon_team": 8.0,
	"weapons_squad": 15.0,
	"medic_team": 10.0
}

# State
var spawn_queue: Array[String] = []
var current_spawn: String = ""
var spawn_progress: float = 0.0
var spawn_time_required: float = 0.0

# Scene references
var rifle_squad_scene: PackedScene
var engineer_squad_scene: PackedScene
var recon_team_scene: PackedScene
var weapons_squad_scene: PackedScene
var medic_team_scene: PackedScene

# Spawn point
@onready var spawn_point: Marker3D = $SpawnPoint if has_node("SpawnPoint") else null


func _ready() -> void:
	super._ready()
	structure_name = "Command Post"
	max_health = 200.0
	armor = 10.0
	current_health = max_health

	_load_unit_scenes()


func _load_unit_scenes() -> void:
	if ResourceLoader.exists("res://scenes/units/rifle_squad.tscn"):
		rifle_squad_scene = load("res://scenes/units/rifle_squad.tscn")
	if ResourceLoader.exists("res://scenes/units/engineer_squad.tscn"):
		engineer_squad_scene = load("res://scenes/units/engineer_squad.tscn")
	if ResourceLoader.exists("res://scenes/units/recon_team.tscn"):
		recon_team_scene = load("res://scenes/units/recon_team.tscn")
	if ResourceLoader.exists("res://scenes/units/weapons_squad.tscn"):
		weapons_squad_scene = load("res://scenes/units/weapons_squad.tscn")
	if ResourceLoader.exists("res://scenes/units/medic_team.tscn"):
		medic_team_scene = load("res://scenes/units/medic_team.tscn")


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	_process_spawn_queue(delta)


func _process_spawn_queue(delta: float) -> void:
	# Start next spawn if queue not empty and not currently spawning
	if current_spawn.is_empty() and not spawn_queue.is_empty():
		current_spawn = spawn_queue[0]
		spawn_time_required = SPAWN_TIMES.get(current_spawn, 10.0)
		spawn_progress = 0.0

	# Process current spawn
	if not current_spawn.is_empty():
		spawn_progress += delta

		if spawn_progress >= spawn_time_required:
			_complete_spawn()


func _complete_spawn() -> void:
	var unit := _create_unit(current_spawn)

	if unit:
		var spawn_pos := global_position + Vector3(0, 0, 5)
		if spawn_point:
			spawn_pos = spawn_point.global_position

		unit.global_position = spawn_pos

		var squads_parent: Node = get_tree().current_scene.get_node_or_null("GameWorld/Units/PlayerSquads")
		if squads_parent:
			squads_parent.add_child(unit)
		else:
			get_parent().add_child(unit)

		unit_spawned.emit(unit)

	# Clear current spawn and remove from queue
	spawn_queue.pop_front()
	current_spawn = ""
	spawn_progress = 0.0
	spawn_queue_changed.emit(spawn_queue)


func _create_unit(unit_type: String) -> Node3D:
	match unit_type:
		"rifle_squad":
			if rifle_squad_scene:
				return rifle_squad_scene.instantiate()
		"engineer_squad":
			if engineer_squad_scene:
				return engineer_squad_scene.instantiate()
		"recon_team":
			if recon_team_scene:
				return recon_team_scene.instantiate()
		"weapons_squad":
			if weapons_squad_scene:
				return weapons_squad_scene.instantiate()
		"medic_team":
			if medic_team_scene:
				return medic_team_scene.instantiate()

	# Fallback placeholder
	return _create_placeholder_unit(unit_type)


func _create_placeholder_unit(unit_type: String) -> CharacterBody3D:
	var unit := CharacterBody3D.new()
	unit.name = unit_type.capitalize().replace("_", "")
	unit.set_script(load("res://scripts/units/base_squad.gd"))

	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.8
	shape.height = 2.0
	collision.shape = shape
	collision.position.y = 1.0
	unit.add_child(collision)

	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.7
	cylinder.height = 1.4
	mesh.mesh = cylinder
	mesh.position.y = 0.7
	unit.add_child(mesh)

	unit.collision_layer = 2
	unit.collision_mask = 7

	return unit


# Public interface

func queue_spawn(unit_type: String) -> bool:
	if unit_type not in SPAWN_COSTS:
		push_warning("CommandPost: Unknown unit type: " + unit_type)
		return false

	var cost: int = SPAWN_COSTS[unit_type]
	if not GameManager.spend_supplies(cost):
		push_warning("CommandPost: Insufficient supplies for " + unit_type)
		return false

	spawn_queue.append(unit_type)
	spawn_queue_changed.emit(spawn_queue)
	return true


func cancel_spawn(index: int) -> void:
	if index < 0 or index >= spawn_queue.size():
		return

	# Refund if canceling item after current
	if index > 0:
		var unit_type: String = spawn_queue[index]
		var refund: int = SPAWN_COSTS.get(unit_type, 0)
		GameManager.add_supplies(refund)

	spawn_queue.remove_at(index)
	spawn_queue_changed.emit(spawn_queue)


func get_spawn_progress() -> float:
	if spawn_time_required > 0:
		return spawn_progress / spawn_time_required
	return 0.0


func get_current_spawn() -> String:
	return current_spawn


func get_spawn_queue() -> Array[String]:
	return spawn_queue


func can_spawn(unit_type: String) -> bool:
	if unit_type not in SPAWN_COSTS:
		return false
	return GameManager.supplies >= SPAWN_COSTS[unit_type]


# Override destruction - game over
func _destroy() -> void:
	GameManager.end_game(false)
	super._destroy()
