extends Area3D
class_name BoobyTrap

## Booby Trap - VC trap that damages/kills player units
## Various types: punji pit, tripwire, grenade trap

signal trap_triggered(trap: BoobyTrap, victim: Node3D)
signal trap_disarmed(trap: BoobyTrap)
signal trap_discovered(trap: BoobyTrap)

enum TrapType {
	PUNJI_PIT,        # Spiked pit, instant damage
	TRIPWIRE_GRENADE, # Triggers grenade explosion
	CLAYMORE_TRAP,    # Directional mine
	WHIP_TRAP,        # Swinging spike trap
	CARTRIDGE_TRAP,   # Hidden bullet shoots up
	TIGER_TRAP,       # Large spiked pit
}

enum TrapState { HIDDEN, DISCOVERED, TRIGGERED, DISARMED }

## Configuration
@export var trap_type: TrapType = TrapType.PUNJI_PIT
@export var damage: float = 50.0
@export var detection_radius: float = 1.5
@export var camouflage_rating: float = 0.7

## State
var state: TrapState = TrapState.HIDDEN
var discovery_progress: float = 0.0


func _ready() -> void:
	add_to_group("booby_traps")
	_configure_trap()
	_create_visual()
	_setup_collision()

	body_entered.connect(_on_body_entered)


func _configure_trap() -> void:
	"""Configure trap stats based on type"""
	match trap_type:
		TrapType.PUNJI_PIT:
			damage = 40.0
			detection_radius = 1.0
			camouflage_rating = 0.8
		TrapType.TRIPWIRE_GRENADE:
			damage = 80.0
			detection_radius = 3.0
			camouflage_rating = 0.6
		TrapType.CLAYMORE_TRAP:
			damage = 150.0
			detection_radius = 5.0
			camouflage_rating = 0.7
		TrapType.WHIP_TRAP:
			damage = 60.0
			detection_radius = 2.0
			camouflage_rating = 0.75
		TrapType.CARTRIDGE_TRAP:
			damage = 30.0
			detection_radius = 0.5
			camouflage_rating = 0.9
		TrapType.TIGER_TRAP:
			damage = 200.0  # Usually fatal
			detection_radius = 2.0
			camouflage_rating = 0.7


func _create_visual() -> void:
	"""Create trap visual (hidden by default)"""
	var mesh := MeshInstance3D.new()
	mesh.name = "TrapMesh"

	match trap_type:
		TrapType.PUNJI_PIT, TrapType.TIGER_TRAP:
			var box := BoxMesh.new()
			box.size = Vector3(detection_radius * 2, 0.1, detection_radius * 2)
			mesh.mesh = box
			mesh.position.y = -0.05
		TrapType.TRIPWIRE_GRENADE:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.05
			cylinder.bottom_radius = 0.05
			cylinder.height = detection_radius * 2
			mesh.mesh = cylinder
			mesh.rotation.z = PI / 2
			mesh.position.y = 0.1
		_:
			var box := BoxMesh.new()
			box.size = Vector3(0.3, 0.1, 0.3)
			mesh.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.35, 0.2, 0.0)  # Invisible when hidden
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat

	add_child(mesh)


func _setup_collision() -> void:
	"""Setup collision detection"""
	var collision := CollisionShape3D.new()

	match trap_type:
		TrapType.PUNJI_PIT, TrapType.TIGER_TRAP:
			var box := BoxShape3D.new()
			box.size = Vector3(detection_radius * 2, 1.0, detection_radius * 2)
			collision.shape = box
		TrapType.TRIPWIRE_GRENADE:
			var box := BoxShape3D.new()
			box.size = Vector3(detection_radius * 2, 0.5, 0.3)
			collision.shape = box
		_:
			var sphere := SphereShape3D.new()
			sphere.radius = detection_radius
			collision.shape = sphere

	add_child(collision)


func _on_body_entered(body: Node3D) -> void:
	"""Handle something entering trap area"""
	if state != TrapState.HIDDEN and state != TrapState.DISCOVERED:
		return

	# Only trigger on player units
	if not body.is_in_group("player_units"):
		return

	# Check for detection
	if state == TrapState.HIDDEN:
		_check_detection(body)

	# Trigger if stepped on
	var distance: float = global_position.distance_to(body.global_position)
	if distance <= detection_radius * 0.5:
		trigger(body)


func _check_detection(unit: Node3D) -> void:
	"""Check if unit detects the trap"""
	var detect_chance: float = 1.0 - camouflage_rating

	# Engineers are better at detecting traps
	if unit.has_method("get") and unit.get("unit_type") != null:
		if unit.unit_type == GameEnums.UnitType.ENGINEERS:
			detect_chance += 0.4

	# Slow movement helps detection
	if unit.has_method("get") and unit.get("velocity") != null:
		if unit.velocity.length() < 2.0:
			detect_chance += 0.2

	discovery_progress += detect_chance * 0.1

	if randf() < detect_chance * 0.1 or discovery_progress >= 1.0:
		discover()


func discover() -> void:
	"""Reveal the trap without triggering"""
	if state != TrapState.HIDDEN:
		return

	state = TrapState.DISCOVERED
	_update_visual()
	trap_discovered.emit(self)
	print("[BoobyTrap] Trap discovered at %s" % global_position)


func _update_visual() -> void:
	"""Update visual for current state"""
	var mesh: MeshInstance3D = get_node_or_null("TrapMesh")
	if not mesh or not mesh.material_override:
		return

	var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D

	match state:
		TrapState.HIDDEN:
			mat.albedo_color.a = 0.0
		TrapState.DISCOVERED:
			mat.albedo_color = Color(0.8, 0.2, 0.2, 0.7)  # Visible red warning
		TrapState.TRIGGERED:
			mat.albedo_color = Color(0.3, 0.3, 0.3, 1.0)  # Spent
		TrapState.DISARMED:
			mat.albedo_color = Color(0.2, 0.5, 0.2, 0.5)  # Safe green


func trigger(victim: Node3D = null) -> void:
	"""Trigger the trap"""
	if state == TrapState.TRIGGERED or state == TrapState.DISARMED:
		return

	state = TrapState.TRIGGERED
	_update_visual()
	trap_triggered.emit(self, victim)

	# Apply damage
	if is_instance_valid(victim):
		_apply_damage(victim)

	# Area effect for explosive traps
	if trap_type in [TrapType.TRIPWIRE_GRENADE, TrapType.CLAYMORE_TRAP]:
		_apply_area_damage()

	# Play sound/effect
	if BattleSignals:
		BattleSignals.projectile_impact.emit(global_position, GameEnums.DamageType.EXPLOSIVE)

	print("[BoobyTrap] Trap triggered at %s" % global_position)


func _apply_damage(target: Node3D) -> void:
	"""Apply damage to single target"""
	if target.has_method("take_damage"):
		target.take_damage(damage, null)

	# Punji traps also slow/immobilize
	if trap_type in [TrapType.PUNJI_PIT, TrapType.TIGER_TRAP]:
		if target.has_method("apply_status"):
			target.apply_status("immobilized", 3.0)


func _apply_area_damage() -> void:
	"""Apply damage in area (for explosive traps)"""
	var radius: float = 5.0
	if trap_type == TrapType.CLAYMORE_TRAP:
		radius = 10.0

	# Find units in radius
	var units: Array[Node] = get_tree().get_nodes_in_group("player_units")
	for unit in units:
		if not is_instance_valid(unit):
			continue

		var dist: float = global_position.distance_to(unit.global_position)
		if dist <= radius:
			var falloff: float = 1.0 - (dist / radius)
			var area_damage: float = damage * falloff

			if unit.has_method("take_damage"):
				unit.take_damage(area_damage, null)


func disarm() -> bool:
	"""Attempt to disarm the trap"""
	if state != TrapState.DISCOVERED:
		return false

	# Engineers can safely disarm
	state = TrapState.DISARMED
	_update_visual()
	trap_disarmed.emit(self)

	print("[BoobyTrap] Trap disarmed at %s" % global_position)
	return true


func is_active() -> bool:
	return state == TrapState.HIDDEN or state == TrapState.DISCOVERED
