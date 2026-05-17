extends BaseStructure
class_name AidStation
## Aid Station - Heals wounded soldiers in radius, reduces medevac need

@export var heal_rate: float = 5.0  # HP healed per second
@export var heal_radius: float = 15.0
@export var max_patients: int = 3  # Max squads being healed at once

var patients: Array[Node3D] = []
var heal_timer: float = 0.0
const HEAL_TICK: float = 0.5


func _ready() -> void:
	super._ready()
	structure_name = "Aid Station"
	max_health = 60.0
	armor = 3.0
	current_health = max_health

	# Add to medical structures group
	add_to_group("medical")


func _process(delta: float) -> void:
	super._process(delta)

	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	heal_timer += delta
	if heal_timer >= HEAL_TICK:
		heal_timer = 0.0
		_heal_nearby_units()


func _heal_nearby_units() -> void:
	# Find wounded friendly units in radius
	patients.clear()

	for squad in GameManager.player_squads:
		if not is_instance_valid(squad):
			continue

		var dist := global_position.distance_to(squad.global_position)
		if dist > heal_radius:
			continue

		# Check if wounded
		if squad.has_method("get_health_percent"):
			var health_pct: float = squad.get_health_percent()
			if health_pct < 1.0:
				patients.append(squad)

	# Sort by health (heal most wounded first)
	patients.sort_custom(func(a, b):
		var a_health: float = a.get_health_percent() if a.has_method("get_health_percent") else 1.0
		var b_health: float = b.get_health_percent() if b.has_method("get_health_percent") else 1.0
		return a_health < b_health
	)

	# Heal up to max_patients
	var healed_count := 0
	for patient in patients:
		if healed_count >= max_patients:
			break

		if patient.has_method("heal"):
			patient.heal(heal_rate * HEAL_TICK)
			healed_count += 1


func get_patient_count() -> int:
	return patients.size()


func is_at_capacity() -> bool:
	return patients.size() >= max_patients
