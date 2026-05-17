extends BaseStructure
class_name LandingZone
## LandingZone - Helicopter landing pad
## Required for air supply and medevac operations

signal helicopter_landing
signal helicopter_departed
signal under_fire

# LZ State
var is_clear: bool = true
var helicopter_present: bool = false
var threat_level: float = 0.0

# Landing point
@onready var landing_point: Marker3D = $LandingPoint if has_node("LandingPoint") else null


func _ready() -> void:
	super._ready()
	structure_name = "Landing Zone"
	max_health = 50.0
	armor = 0.0
	current_health = max_health

	# Register with supply director
	SupplyDirector.register_landing_zone(self)


func _exit_tree() -> void:
	SupplyDirector.unregister_landing_zone(self)
	super._exit_tree()


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	# Decay threat level
	threat_level = max(0, threat_level - delta * 5)

	# Check if clear
	is_clear = threat_level < 10


func take_damage(amount: float) -> void:
	super.take_damage(amount)

	# Increase threat level when taking fire
	threat_level += amount
	under_fire.emit()


func get_landing_position() -> Vector3:
	if landing_point:
		return landing_point.global_position
	return global_position + Vector3(0, 0.5, 0)


func is_safe_to_land() -> bool:
	return is_clear and not helicopter_present


func set_helicopter_present(present: bool) -> void:
	helicopter_present = present
	if present:
		helicopter_landing.emit()
	else:
		helicopter_departed.emit()


func get_threat_level() -> float:
	return threat_level
