class_name Airport extends Node3D
## Airport - Fixed-wing aircraft home base.
## Provides parking, refuel/rearm services, and runway alignment.

signal airplane_landed(plane: Node3D)
signal airplane_departed(plane: Node3D)

@export var airport_name: String = "Bien Hoa"
@export var runway_length: float = 80.0
@export var runway_width: float = 8.0
@export var runway_heading_degrees: float = 0.0  # Direction along runway
@export var parking_capacity: int = 4

var parked_aircraft: Array[Node3D] = []
var _parking_spots: Array[Vector3] = []


func _ready() -> void:
	add_to_group("airports")
	_build_visual()
	_compute_parking_spots()


func _build_visual() -> void:
	# Runway strip
	var runway := MeshInstance3D.new()
	runway.name = "Runway"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(runway_width, runway_length)
	runway.mesh = mesh
	runway.position.y = 0.05
	runway.rotation_degrees.y = runway_heading_degrees

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.25, 0.27)  # Tarmac
	runway.material_override = mat
	add_child(runway)

	# Centerline markings
	for i in 6:
		var stripe := MeshInstance3D.new()
		var sm := PlaneMesh.new()
		sm.size = Vector2(0.4, 4.0)
		stripe.mesh = sm
		stripe.position = Vector3(0, 0.06, lerp(-runway_length * 0.4, runway_length * 0.4, float(i) / 5.0))
		stripe.rotation_degrees.y = runway_heading_degrees
		var stripe_mat := StandardMaterial3D.new()
		stripe_mat.albedo_color = Color(0.9, 0.9, 0.7)
		stripe.material_override = stripe_mat
		add_child(stripe)


func _compute_parking_spots() -> void:
	# Parking spots run alongside the runway (perpendicular to heading)
	var perp_rad: float = deg_to_rad(runway_heading_degrees + 90.0)
	var perp: Vector3 = Vector3(sin(perp_rad), 0, cos(perp_rad))
	var offset: float = runway_width * 0.5 + 4.0
	for i in parking_capacity:
		var spot: Vector3 = global_position + perp * offset
		spot += Vector3(sin(deg_to_rad(runway_heading_degrees)), 0, cos(deg_to_rad(runway_heading_degrees))) * float(i - parking_capacity / 2) * 8.0
		_parking_spots.append(spot)


## Get the next available parking spot.
func get_parking_spot() -> Vector3:
	if parked_aircraft.size() >= _parking_spots.size():
		return _parking_spots[0]  # Overflow - stack
	return _parking_spots[parked_aircraft.size()]


func get_runway_heading_rad() -> float:
	return deg_to_rad(runway_heading_degrees)


## Get takeoff start position (one end of runway).
func get_takeoff_start() -> Vector3:
	var dir: Vector3 = Vector3(sin(deg_to_rad(runway_heading_degrees)), 0, cos(deg_to_rad(runway_heading_degrees)))
	return global_position - dir * (runway_length * 0.4)


## Register an aircraft as parked.
func park_aircraft(plane: Node3D) -> void:
	if not plane in parked_aircraft:
		parked_aircraft.append(plane)
		airplane_landed.emit(plane)


## Remove aircraft from parked list (taking off).
func release_aircraft(plane: Node3D) -> void:
	parked_aircraft.erase(plane)
	airplane_departed.emit(plane)
