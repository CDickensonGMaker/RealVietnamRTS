extends BaseStructure
class_name WirePerimeter
## Wire Perimeter - Slows enemy movement and channels attacks

@export var slow_factor: float = 0.3  # Enemies move at 30% speed through wire
@export var damage_per_second: float = 2.0  # Light damage to units in wire

var units_in_wire: Array[Node3D] = []


func _ready() -> void:
	super._ready()
	structure_name = "Wire Perimeter"
	max_health = 20.0
	armor = 0.0
	current_health = max_health

	# Create area for detecting units
	_setup_wire_area()


func _setup_wire_area() -> void:
	var area := Area3D.new()
	area.name = "WireArea"

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 1, 1)  # Match wire footprint
	collision.shape = shape
	collision.position.y = 0.5

	area.add_child(collision)
	area.collision_layer = 0
	area.collision_mask = 2  # Units layer

	area.body_entered.connect(_on_unit_entered)
	area.body_exited.connect(_on_unit_exited)

	add_child(area)


func _process(delta: float) -> void:
	super._process(delta)

	# Damage units in wire
	for unit in units_in_wire:
		if is_instance_valid(unit) and unit.has_method("take_damage"):
			unit.take_damage(damage_per_second * delta, self)


func _on_unit_entered(body: Node3D) -> void:
	# Only affect enemy units
	if body.is_in_group("enemy"):
		units_in_wire.append(body)

		# Apply slow effect
		if body.has_method("apply_slow"):
			body.apply_slow(slow_factor)


func _on_unit_exited(body: Node3D) -> void:
	units_in_wire.erase(body)

	# Remove slow effect
	if body.has_method("remove_slow"):
		body.remove_slow()
