extends BaseSquad
class_name EngineerSquad
## EngineerSquad - Construction specialists
## Can build all structures, builds faster, repairs damaged buildings

signal construction_started(structure_type: String)
signal construction_completed(structure: Node3D)
signal repair_started(structure: Node3D)
signal repair_completed(structure: Node3D)

# Engineer-specific stats
@export var build_speed_multiplier: float = 2.0
@export var repair_rate: float = 10.0  # Health per second

# State
enum EngineerTask { NONE, BUILDING, REPAIRING }
var current_task: EngineerTask = EngineerTask.NONE
var build_target_type: String = ""
var build_target_position: Vector3 = Vector3.ZERO
var repair_target: Node3D = null

# Construction progress
var construction_progress: float = 0.0
var construction_time_required: float = 0.0


func _ready() -> void:
	super._ready()
	squad_name = "Engineer Squad"
	damage_per_second = 6.0  # Lower combat effectiveness
	accuracy = 0.5


func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	match current_task:
		EngineerTask.BUILDING:
			_process_building(delta)
		EngineerTask.REPAIRING:
			_process_repairing(delta)


func _process_building(delta: float) -> void:
	# Check if at build site
	var distance := global_position.distance_to(build_target_position)

	if distance > 3.0:
		# Move to build site
		if current_state != SquadState.MOVING:
			move_to(build_target_position)
		return

	# Stop and build
	if current_state == SquadState.MOVING:
		current_state = SquadState.BUILDING
		waypoint_queue.clear()

	# Progress construction
	construction_progress += delta * build_speed_multiplier
	if construction_progress >= construction_time_required:
		_complete_construction()


func _process_repairing(delta: float) -> void:
	if not is_instance_valid(repair_target):
		current_task = EngineerTask.NONE
		return

	var distance := global_position.distance_to(repair_target.global_position)

	if distance > 4.0:
		if current_state != SquadState.MOVING:
			move_to(repair_target.global_position)
		return

	# Stop and repair
	if current_state == SquadState.MOVING:
		current_state = SquadState.BUILDING  # Reuse building state
		waypoint_queue.clear()

	# Apply repairs
	if repair_target.has_method("repair"):
		repair_target.repair(repair_rate * delta)

		# Check if fully repaired
		if repair_target.has_method("needs_repair") and not repair_target.needs_repair():
			repair_completed.emit(repair_target)
			current_task = EngineerTask.NONE
			current_state = SquadState.IDLE


func _complete_construction() -> void:
	# Actual structure spawning is handled by build system
	# This just signals completion
	construction_completed.emit(null)
	current_task = EngineerTask.NONE
	current_state = SquadState.IDLE
	construction_progress = 0.0


# Public interface

func start_building(structure_type: String, position: Vector3, build_time: float) -> void:
	build_target_type = structure_type
	build_target_position = position
	construction_time_required = build_time / build_speed_multiplier
	construction_progress = 0.0
	current_task = EngineerTask.BUILDING

	construction_started.emit(structure_type)
	move_to(position)


func start_repair(structure: Node3D) -> void:
	if not structure.has_method("repair"):
		push_warning("EngineerSquad: Target cannot be repaired")
		return

	repair_target = structure
	current_task = EngineerTask.REPAIRING

	repair_started.emit(structure)
	move_to(structure.global_position)


func cancel_task() -> void:
	current_task = EngineerTask.NONE
	construction_progress = 0.0
	repair_target = null
	current_state = SquadState.IDLE


func get_construction_progress() -> float:
	if construction_time_required > 0:
		return construction_progress / construction_time_required
	return 0.0


func is_building() -> bool:
	return current_task == EngineerTask.BUILDING


func is_repairing() -> bool:
	return current_task == EngineerTask.REPAIRING
