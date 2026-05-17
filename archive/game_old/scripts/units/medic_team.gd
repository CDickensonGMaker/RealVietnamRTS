extends BaseSquad
class_name MedicTeam
## MedicTeam - Combat medics that heal nearby wounded
## Non-combat unit, prioritizes casualty treatment

signal healing_unit(target: Node3D)
signal unit_stabilized(target: Node3D)
signal medevac_requested

# Medic specific
@export var heal_range: float = 10.0
@export var heal_rate: float = 15.0  # Health per second
@export var stabilize_threshold: float = 30.0  # Health % to consider stabilized

# State
var healing_target: Node3D = null
var nearby_wounded: Array[Node3D] = []


func _ready() -> void:
	super._ready()
	squad_name = "Medic Team"
	squad_size = 4
	max_squad_size = 4
	supply_cost = 15

	# Medics are non-combat
	move_speed = 5.5
	sight_range = 25.0
	attack_range = 15.0
	damage_per_second = 3.0  # Minimal self-defense
	accuracy = 0.4


func _physics_process(delta: float) -> void:
	# Override normal combat behavior
	_scan_for_wounded()
	_process_healing(delta)

	# Still need to move
	if current_state == SquadState.MOVING:
		_process_movement(delta)


func _scan_for_wounded() -> void:
	nearby_wounded.clear()

	for squad in GameManager.player_squads:
		if squad == self:
			continue
		if not is_instance_valid(squad):
			continue

		var distance := global_position.distance_to(squad.global_position)
		if distance > heal_range:
			continue

		# Check if wounded
		if squad.has_method("get_health_percent"):
			var health_pct: float = squad.get_health_percent()
			if health_pct < 1.0:
				nearby_wounded.append(squad)


func _process_healing(delta: float) -> void:
	# Clear invalid target
	if healing_target and not is_instance_valid(healing_target):
		healing_target = null

	# Find new target if needed
	if not healing_target and not nearby_wounded.is_empty():
		healing_target = _get_priority_wounded()

	if not healing_target:
		return

	# Check still in range
	var distance := global_position.distance_to(healing_target.global_position)
	if distance > heal_range:
		# Move toward wounded
		move_to(healing_target.global_position)
		return

	# Stop and heal
	if current_state == SquadState.MOVING:
		current_state = SquadState.IDLE
		waypoint_queue.clear()

	# Apply healing
	if healing_target.get("squad_health") != null:
		healing_target.squad_health = min(100, healing_target.squad_health + heal_rate * delta)
		healing_unit.emit(healing_target)

		# Check if stabilized
		if healing_target.squad_health >= stabilize_threshold:
			unit_stabilized.emit(healing_target)

		# Check if fully healed
		if healing_target.squad_health >= 100:
			healing_target = null


func _get_priority_wounded() -> Node3D:
	var most_wounded: Node3D = null
	var lowest_health := 1.0

	for squad in nearby_wounded:
		if not is_instance_valid(squad):
			continue

		var health_pct: float = squad.get_health_percent()
		if health_pct < lowest_health:
			lowest_health = health_pct
			most_wounded = squad

	return most_wounded


func _guard_behavior() -> void:
	# Medics prioritize healing over combat
	if not nearby_wounded.is_empty():
		return

	# Only fight if no wounded and attacked
	if not enemies_in_sight.is_empty() and suppression > 20:
		# Fight back minimally
		super._guard_behavior()


func request_medevac() -> void:
	## Call for helicopter evacuation for critical casualties
	medevac_requested.emit()
	# Would interface with SupplyDirector to dispatch medevac chopper


func get_wounded_count() -> int:
	return nearby_wounded.size()


func is_healing() -> bool:
	return healing_target != null
