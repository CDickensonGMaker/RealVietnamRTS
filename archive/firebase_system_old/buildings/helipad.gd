extends BuildingBase
class_name Helipad
## Helipad - Landing zone for helicopters

signal helicopter_inbound(helicopter: Node3D)
signal helicopter_landed(helicopter: Node3D)
signal helicopter_departed(helicopter: Node3D)

# Configuration
@export var pad_size: float = 15.0
@export var can_refuel: bool = true
@export var can_rearm: bool = false

# State
var landing_zone = null  # LandingZone
var current_helicopter: Node3D = null
var fuel_reserve: float = 100.0

func _ready() -> void:
	building_type = GameEnums.BuildingType.HELIPAD
	max_health = 50.0
	armor = 0.0
	garrison_capacity = 0
	provides_cover = false
	super._ready()

	# Create associated landing zone
	_create_landing_zone()

func _create_visual() -> void:
	# Circular pad
	var pad := CSGCylinder3D.new()
	pad.radius = pad_size / 2
	pad.height = 0.2
	pad.sides = 16

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.3)
	pad.material = mat

	add_child(pad)

	# H marking (simplified as cross)
	var h_bar1 := CSGBox3D.new()
	h_bar1.size = Vector3(pad_size * 0.6, 0.05, pad_size * 0.1)
	h_bar1.position = Vector3(0, 0.15, 0)

	var h_mat := StandardMaterial3D.new()
	h_mat.albedo_color = Color(0.9, 0.9, 0.9)
	h_bar1.material = h_mat

	add_child(h_bar1)

	visual_mesh = pad

func _create_landing_zone() -> void:
	landing_zone = LandingZone.new()
	landing_zone.lz_name = "Helipad LZ"
	landing_zone.lz_size = pad_size
	landing_zone.max_helicopters = 1
	landing_zone.global_position = global_position

	add_child(landing_zone)

	# Connect signals
	landing_zone.helicopter_landed.connect(_on_helicopter_landed)
	landing_zone.helicopter_departed.connect(_on_helicopter_departed)
	landing_zone.helicopter_approaching.connect(_on_helicopter_approaching)

func _on_helicopter_approaching(helicopter: Node3D) -> void:
	helicopter_inbound.emit(helicopter)

func _on_helicopter_landed(helicopter: Node3D) -> void:
	current_helicopter = helicopter
	helicopter_landed.emit(helicopter)

	# Auto-refuel if enabled
	if can_refuel and helicopter.has_method("refuel"):
		_refuel_helicopter(helicopter)

	# Auto-rearm if enabled
	if can_rearm and helicopter.has_method("rearm"):
		helicopter.rearm()

func _on_helicopter_departed(helicopter: Node3D) -> void:
	if current_helicopter == helicopter:
		current_helicopter = null
	helicopter_departed.emit(helicopter)

func _refuel_helicopter(helicopter: Node3D) -> void:
	if fuel_reserve <= 0:
		return

	var needed: float = 100.0
	if helicopter.has_method("get_fuel_needed"):
		needed = helicopter.get_fuel_needed()

	var given := minf(needed, fuel_reserve)
	fuel_reserve -= given

	if helicopter.has_method("refuel"):
		helicopter.refuel(given)

func resupply_fuel(amount: float) -> void:
	fuel_reserve = minf(100.0, fuel_reserve + amount)

func is_landing_zone() -> bool:
	return true

func get_landing_zone() -> LandingZone:
	return landing_zone

func is_available() -> bool:
	return current_helicopter == null and not is_destroyed

func get_landing_position() -> Vector3:
	return global_position
