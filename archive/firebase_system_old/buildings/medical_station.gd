extends BuildingBase
class_name MedicalStation
## MedicalStation - Field medical facility for treating wounded

signal patient_admitted(unit: Node3D)
signal patient_healed(unit: Node3D)
signal medical_supplies_low()

# Medical configuration
@export var treatment_rate: float = 10.0  # HP per second
@export var treatment_capacity: int = 4  # Simultaneous patients
@export var max_medical_supplies: float = 100.0

# State
var medical_supplies: float = 100.0
var patients: Array[Node3D] = []
var healing_queue: Array[Node3D] = []

func _ready() -> void:
	building_type = GameEnums.BuildingType.MEDICAL_STATION
	max_health = 80.0
	armor = 5.0
	garrison_capacity = 0
	cover_type = 1  # LIGHT
	super._ready()

func _create_visual() -> void:
	# Main tent structure
	var tent := CSGBox3D.new()
	tent.size = Vector3(6, 2.5, 8)
	tent.position.y = 1.25

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.75, 0.7)
	tent.material = mat

	add_child(tent)

	# Red cross
	var cross_h := CSGBox3D.new()
	cross_h.size = Vector3(2, 0.1, 0.5)
	cross_h.position = Vector3(0, 2.6, 0)

	var cross_mat := StandardMaterial3D.new()
	cross_mat.albedo_color = Color(0.9, 0.1, 0.1)
	cross_h.material = cross_mat

	add_child(cross_h)

	var cross_v := CSGBox3D.new()
	cross_v.size = Vector3(0.5, 0.1, 2)
	cross_v.position = Vector3(0, 2.6, 0)
	cross_v.material = cross_mat

	add_child(cross_v)

	visual_mesh = tent

func _process(delta: float) -> void:
	if is_destroyed:
		return

	_process_healing(delta)
	_admit_queued_patients()

func _process_healing(delta: float) -> void:
	if patients.is_empty() or medical_supplies <= 0:
		return

	var healed: Array[Node3D] = []
	var supply_used := 0.0

	for patient in patients:
		if not is_instance_valid(patient):
			healed.append(patient)
			continue

		# Heal the patient
		var heal_amount := treatment_rate * delta

		if patient.has_method("heal"):
			patient.heal(heal_amount)
			supply_used += 0.1 * delta

		# Check if fully healed
		var is_fully_healed := false
		if patient.has_method("get_health_ratio"):
			is_fully_healed = patient.get_health_ratio() >= 1.0
		elif patient.has_method("is_at_full_health"):
			is_fully_healed = patient.is_at_full_health()

		if is_fully_healed:
			healed.append(patient)

	# Consume supplies
	medical_supplies = maxf(0, medical_supplies - supply_used)
	if medical_supplies < 20:
		medical_supplies_low.emit()

	# Remove healed patients
	for patient in healed:
		_discharge_patient(patient)

func _admit_queued_patients() -> void:
	while patients.size() < treatment_capacity and not healing_queue.is_empty():
		var patient: Node3D = healing_queue.pop_front()
		if is_instance_valid(patient):
			patients.append(patient)
			patient_admitted.emit(patient)

func _discharge_patient(patient: Node3D) -> void:
	patients.erase(patient)
	healing_queue.erase(patient)

	if is_instance_valid(patient):
		patient_healed.emit(patient)

func admit_patient(unit: Node3D) -> bool:
	## Add wounded unit to treatment

	if is_destroyed or medical_supplies <= 0:
		return false

	if unit in patients or unit in healing_queue:
		return false

	if patients.size() < treatment_capacity:
		patients.append(unit)
		patient_admitted.emit(unit)
	else:
		healing_queue.append(unit)

	return true

func resupply(amount: float) -> void:
	medical_supplies = minf(max_medical_supplies, medical_supplies + amount)

func get_queue_size() -> int:
	return healing_queue.size()

func get_patient_count() -> int:
	return patients.size()

func get_supply_ratio() -> float:
	return medical_supplies / max_medical_supplies
