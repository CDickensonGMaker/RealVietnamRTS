extends Node3D
class_name BuildingBase
## BuildingBase - Base class for all firebase buildings

signal building_damaged(amount: float, source: Node3D)
signal building_destroyed()
signal building_repaired(amount: float)
signal garrison_changed(count: int)

# =============================================================================
# CONFIGURATION
# =============================================================================
@export var building_type: int = GameEnums.BuildingType.BUNKER
@export var max_health: float = 100.0
@export var armor: float = 0.0  # Damage reduction
@export var garrison_capacity: int = 0
@export var provides_cover: bool = true
@export var cover_type: int = 2  # CoverSystem.CoverType.MEDIUM

# =============================================================================
# STATE
# =============================================================================
var health: float = 100.0
var is_destroyed: bool = false
var garrison: Array[Node3D] = []
var owner_firebase: Node3D = null

# Visual
var visual_mesh: Node3D = null

func _ready() -> void:
	add_to_group("buildings")
	add_to_group("us_structures")
	health = max_health
	_create_visual()
	_setup_collision()

func _create_visual() -> void:
	## Override in subclasses for specific visuals
	visual_mesh = CSGBox3D.new()
	visual_mesh.size = Vector3(4, 2, 4)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.45, 0.35)
	(visual_mesh as CSGBox3D).material = mat

	add_child(visual_mesh)

func _setup_collision() -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 2, 4)
	collision.shape = shape

	var body := StaticBody3D.new()
	body.add_child(collision)
	body.set_collision_layer_value(7, true)  # Buildings layer
	add_child(body)

# =============================================================================
# BUILDING TYPE
# =============================================================================

func get_building_type() -> int:
	return building_type

func get_building_name() -> String:
	match building_type:
		GameEnums.BuildingType.SANDBAG_WALL: return "Sandbag Wall"
		GameEnums.BuildingType.BUNKER: return "Bunker"
		GameEnums.BuildingType.MACHINE_GUN_NEST: return "MG Nest"
		GameEnums.BuildingType.MORTAR_PIT: return "Mortar Pit"
		GameEnums.BuildingType.WIRE_OBSTACLE: return "Wire Obstacle"
		GameEnums.BuildingType.WATCHTOWER: return "Watchtower"
		GameEnums.BuildingType.HELIPAD: return "Helipad"
		GameEnums.BuildingType.AMMO_BUNKER: return "Ammo Bunker"
		GameEnums.BuildingType.MEDICAL_STATION: return "Medical Station"
		GameEnums.BuildingType.TOC: return "TOC"
		GameEnums.BuildingType.COMMO_BUNKER: return "Commo Bunker"
		GameEnums.BuildingType.ARTILLERY_PIT: return "Artillery Pit"
		_: return "Unknown Building"

# =============================================================================
# DAMAGE
# =============================================================================

func take_damage(amount: float, source: Node3D = null) -> void:
	if is_destroyed:
		return

	var actual_damage := maxf(0, amount - armor)
	health -= actual_damage

	building_damaged.emit(actual_damage, source)

	if health <= 0:
		_destroy()

func repair(amount: float) -> void:
	if is_destroyed:
		return

	health = minf(max_health, health + amount)
	building_repaired.emit(amount)

func _destroy() -> void:
	is_destroyed = true

	# Evacuate garrison
	for unit in garrison:
		if is_instance_valid(unit):
			_eject_unit(unit)

	building_destroyed.emit()
	BattleSignals.cover_destroyed.emit(self)

	# Spawn destruction effects
	_spawn_destruction_effects()

func _spawn_destruction_effects() -> void:
	BattleSignals.explosion.emit(global_position, 5.0, 0.0)
	# Would spawn debris, smoke, etc.

func get_health_ratio() -> float:
	return health / max_health

# =============================================================================
# GARRISON
# =============================================================================

func can_garrison(unit: Node3D) -> bool:
	return garrison_capacity > 0 and garrison.size() < garrison_capacity and not is_destroyed

func add_to_garrison(unit: Node3D) -> bool:
	if not can_garrison(unit):
		return false

	if unit not in garrison:
		garrison.append(unit)
		unit.visible = false  # Hide unit inside building
		garrison_changed.emit(garrison.size())
		return true

	return false

func remove_from_garrison(unit: Node3D) -> void:
	if unit in garrison:
		garrison.erase(unit)
		unit.visible = true
		garrison_changed.emit(garrison.size())

func _eject_unit(unit: Node3D) -> void:
	remove_from_garrison(unit)
	if is_instance_valid(unit):
		# Place unit next to building
		var offset := Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		unit.global_position = global_position + offset

func get_garrison_size() -> int:
	return garrison.size()

# =============================================================================
# COVER
# =============================================================================

func get_cover_type() -> int:
	return cover_type

func is_cover() -> bool:
	return provides_cover and not is_destroyed

# =============================================================================
# SPECIAL ABILITIES (override in subclasses)
# =============================================================================

func is_landing_zone() -> bool:
	return false

func is_defensive_weapon() -> bool:
	return false

func engage_target(_target: Node3D) -> void:
	pass

func cease_fire() -> void:
	pass
