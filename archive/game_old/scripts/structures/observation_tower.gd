extends BaseStructure
class_name ObservationTower
## Observation Tower - Extended sight range, spots for mortars

@export var sight_range: float = 60.0  # Much larger than normal structures
@export var detection_bonus: float = 1.5  # Detects enemies faster
@export var can_spot_for_mortar: bool = true

var spotted_enemies: Array[Node3D] = []
var scan_timer: float = 0.0
const SCAN_INTERVAL: float = 0.5


func _ready() -> void:
	super._ready()
	structure_name = "Observation Tower"
	max_health = 35.0
	armor = 1.0
	current_health = max_health

	# Add to observation group
	add_to_group("observation")


func _process(delta: float) -> void:
	super._process(delta)

	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	scan_timer += delta
	if scan_timer >= SCAN_INTERVAL:
		scan_timer = 0.0
		_scan_for_enemies()


func _scan_for_enemies() -> void:
	spotted_enemies.clear()

	# Check all enemy units in sight range
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(node):
			continue

		var enemy := node as Node3D
		if not enemy:
			continue

		var dist := global_position.distance_to(enemy.global_position)
		if dist > sight_range:
			continue

		# Enemy is in sight range
		spotted_enemies.append(enemy)

		# Report to Intel Director
		IntelDirector.report_enemy_contact(enemy.global_position, "observation_tower", 1.0)

	# Update fog of war with extended range
	if spotted_enemies.size() > 0:
		IntelDirector.reveal_area(global_position, sight_range)


func get_spotted_enemies() -> Array[Node3D]:
	return spotted_enemies


func get_nearest_enemy() -> Node3D:
	if spotted_enemies.is_empty():
		return null

	var nearest: Node3D = null
	var nearest_dist := INF

	for enemy in spotted_enemies:
		if not is_instance_valid(enemy):
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy

	return nearest


func request_mortar_strike(target_pos: Vector3) -> bool:
	## Request mortar fire on a spotted position
	if not can_spot_for_mortar:
		return false

	# Find friendly mortar pits
	for structure in GameManager.structures:
		if not is_instance_valid(structure):
			continue
		if structure is MortarPit:
			var mortar: MortarPit = structure
			if mortar.can_fire() and mortar.is_in_range(target_pos):
				mortar.fire_at_position(target_pos)
				return true

	return false
