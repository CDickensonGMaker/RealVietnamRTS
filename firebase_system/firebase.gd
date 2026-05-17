extends Node3D
class_name Firebase

## Firebase - Main base structure
## Contains construction zones and manages firebase operations

signal firebase_level_changed(firebase: Firebase, new_level: int)
signal building_constructed(firebase: Firebase, building: Node3D)
signal firebase_attacked(firebase: Firebase, attacker: Node3D)
signal firebase_destroyed(firebase: Firebase)

enum FirebaseLevel { PATROL_BASE, FIRE_SUPPORT_BASE, MAJOR_FIREBASE }

const ConstructionZone = preload("res://firebase_system/construction_zone.gd")
const BuildingData = preload("res://firebase_system/building_data.gd")

## Configuration
@export var firebase_name: String = "Firebase Alpha"
@export var initial_level: FirebaseLevel = FirebaseLevel.PATROL_BASE
@export var default_radius: float = 60.0  # Default perimeter radius (Pillar 2)

## State
var level: FirebaseLevel = FirebaseLevel.PATROL_BASE
var construction_zones: Array[ConstructionZone] = []
var buildings: Array[Node3D] = []
var garrison: Array[Node3D] = []

## Perimeter (Pillar 2: Player-drawn perimeter, not preset grid)
var perimeter_polygon: PackedVector2Array = []  # Player-drawn outline (XZ coords)
var perimeter_center: Vector3 = Vector3.ZERO

## Resources
var supply_level: float = 100.0
var max_supply: float = 500.0

## Stats
var total_health: float = 500.0
var current_health: float = 500.0


func _ready() -> void:
	level = initial_level
	perimeter_center = global_position

	# Initialize with default circular perimeter (Pillar 2)
	# Player can override by calling set_perimeter_polygon()
	_init_default_perimeter()

	# Prepare terrain for firebase (connect to TerrainIntegration)
	_prepare_terrain()

	_create_firebase_visual()

	add_to_group("firebases")
	add_to_group("all_units")

	if BattleSignals:
		BattleSignals.firebase_established.emit(self)

	print("[Firebase] %s established (Level %d, radius %.0fm)" % [firebase_name, level, default_radius])


func _init_default_perimeter() -> void:
	"""Initialize default circular perimeter (Pillar 2: Player can modify later)"""
	if perimeter_polygon.is_empty():
		# Create default circular perimeter
		var segments: int = 32
		for i in segments:
			var angle: float = TAU * float(i) / float(segments)
			var point := Vector2(
				cos(angle) * default_radius,
				sin(angle) * default_radius
			)
			perimeter_polygon.append(point)


func _prepare_terrain() -> void:
	"""Prepare terrain at firebase location via TerrainIntegration"""
	var terrain_integration: Node = get_node_or_null("/root/TerrainIntegration")
	if terrain_integration and terrain_integration.has_method("prepare_building_site"):
		# Clear terrain for firebase footprint
		var size := Vector2(default_radius * 2, default_radius * 2)
		terrain_integration.prepare_building_site(global_position, size)


## Add a construction zone at a specific world position (Pillar 2)
func add_construction_zone_at(world_pos: Vector3, building_type: int = -1) -> ConstructionZone:
	"""Create a construction zone at a specific world position (player-placed)"""
	# Check if within perimeter
	if not is_position_in_perimeter(world_pos):
		push_warning("[Firebase] Position outside perimeter")
		return null

	# Check zone limit
	if construction_zones.size() >= get_max_zones():
		push_warning("[Firebase] Maximum construction zones reached")
		return null

	var zone := ConstructionZone.new()
	zone.name = "Zone_%d" % construction_zones.size()
	zone.position = world_pos - global_position  # Local position

	add_child(zone)
	construction_zones.append(zone)
	zone.construction_complete.connect(_on_construction_complete)

	# Start construction if building type specified
	if building_type >= 0:
		var data: BuildingData = BuildingData.get_building_data(building_type)
		if data and supply_level >= data.supply_cost:
			supply_level -= data.supply_cost
			zone.start_construction(data)

	return zone


func is_position_in_perimeter(world_pos: Vector3) -> bool:
	"""Check if a world position is inside the firebase perimeter"""
	if perimeter_polygon.is_empty():
		# Fallback to radius check
		return global_position.distance_to(world_pos) <= default_radius

	# Convert to local 2D coordinates
	var local_pos := world_pos - global_position
	var point := Vector2(local_pos.x, local_pos.z)

	# Point-in-polygon test
	return Geometry2D.is_point_in_polygon(point, perimeter_polygon)


func set_perimeter_polygon(polygon: PackedVector2Array) -> void:
	"""Set custom perimeter polygon (player-drawn)"""
	perimeter_polygon = polygon
	_update_perimeter()


func _create_firebase_visual() -> void:
	"""Create visual representation of firebase perimeter"""
	var perimeter := MeshInstance3D.new()
	perimeter.name = "Perimeter"

	var radius: float = get_firebase_radius()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.5
	torus.outer_radius = radius
	torus.rings = 32
	torus.ring_segments = 8
	perimeter.mesh = torus
	perimeter.position.y = 0.1
	perimeter.rotation_degrees.x = 90

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.35, 0.2, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	perimeter.material_override = mat

	add_child(perimeter)


func _on_construction_complete(_zone: ConstructionZone, building: Node3D) -> void:
	"""Handle building completion"""
	buildings.append(building)
	building_constructed.emit(self, building)

	# Check for level upgrade
	_check_level_upgrade()


func _check_level_upgrade() -> void:
	"""Check if firebase should upgrade"""
	var building_count: int = buildings.size()

	if level == FirebaseLevel.PATROL_BASE and building_count >= 3:
		_upgrade_level(FirebaseLevel.FIRE_SUPPORT_BASE)
	elif level == FirebaseLevel.FIRE_SUPPORT_BASE and building_count >= 6:
		_upgrade_level(FirebaseLevel.MAJOR_FIREBASE)


func _upgrade_level(new_level: FirebaseLevel) -> void:
	"""Upgrade firebase to new level"""
	var old_level: FirebaseLevel = level
	level = new_level

	# Add new construction zones
	var old_count: int = get_max_zones_for_level(old_level)
	var new_count: int = get_max_zones()

	for i in range(old_count, new_count):
		var zone := ConstructionZone.new()
		zone.name = "Zone_%d" % i

		# Position new zones on outer ring
		var angle: float = TAU * float(i - old_count) / float(new_count - old_count)
		var radius: float = get_firebase_radius() * 0.7
		zone.position = Vector3(cos(angle) * radius, 0, sin(angle) * radius)

		add_child(zone)
		construction_zones.append(zone)
		zone.construction_complete.connect(_on_construction_complete)

	# Update perimeter visual
	_update_perimeter()

	firebase_level_changed.emit(self, level)
	print("[Firebase] %s upgraded to level %d" % [firebase_name, level])


func _update_perimeter() -> void:
	"""Update perimeter visual for new size"""
	var perimeter: MeshInstance3D = get_node_or_null("Perimeter")
	if perimeter and perimeter.mesh is TorusMesh:
		var radius: float = get_firebase_radius()
		(perimeter.mesh as TorusMesh).inner_radius = radius - 0.5
		(perimeter.mesh as TorusMesh).outer_radius = radius


## Public API

func get_max_zones() -> int:
	"""Get max construction zones for current level"""
	return get_max_zones_for_level(level)


static func get_max_zones_for_level(lv: FirebaseLevel) -> int:
	"""Get max construction zones for a level"""
	match lv:
		FirebaseLevel.PATROL_BASE:
			return 4
		FirebaseLevel.FIRE_SUPPORT_BASE:
			return 8
		FirebaseLevel.MAJOR_FIREBASE:
			return 12
	return 4


func get_firebase_radius() -> float:
	"""Get firebase perimeter radius"""
	match level:
		FirebaseLevel.PATROL_BASE:
			return 20.0
		FirebaseLevel.FIRE_SUPPORT_BASE:
			return 35.0
		FirebaseLevel.MAJOR_FIREBASE:
			return 50.0
	return 20.0


func get_empty_zone() -> ConstructionZone:
	"""Find an empty construction zone"""
	for zone in construction_zones:
		if zone.is_empty():
			return zone
	return null


func start_building(building_type: int, zone: ConstructionZone = null) -> bool:
	"""Start constructing a building"""
	if zone == null:
		zone = get_empty_zone()

	if zone == null or not zone.is_empty():
		return false

	var data: BuildingData = BuildingData.get_building_data(building_type)

	# Check level requirement
	if data.requires_firebase_level > level:
		return false

	# Check supply cost
	if supply_level < data.supply_cost:
		return false

	# Deduct supply
	supply_level -= data.supply_cost

	return zone.start_construction(data)


func add_supply(amount: float) -> void:
	"""Add supply to firebase"""
	supply_level = minf(supply_level + amount, max_supply)


func take_damage(amount: float, source: Node3D = null) -> void:
	"""Apply damage to firebase"""
	current_health -= amount

	if BattleSignals:
		BattleSignals.firebase_under_attack.emit(self, source)

	firebase_attacked.emit(self, source)

	if current_health <= 0:
		_destroy()


func _destroy() -> void:
	"""Firebase destroyed"""
	firebase_destroyed.emit(self)
	# Don't queue_free - let campaign handle cleanup


func garrison_unit(unit: Node3D) -> void:
	"""Add unit to firebase garrison"""
	if unit not in garrison:
		garrison.append(unit)


func remove_from_garrison(unit: Node3D) -> void:
	"""Remove unit from garrison"""
	garrison.erase(unit)


func get_building_count() -> int:
	return buildings.size()


func has_building_type(building_type: int) -> bool:
	"""Check if firebase has a specific building type"""
	for zone in construction_zones:
		if zone.is_complete() and zone.building_data:
			if zone.building_data.building_type == building_type:
				return true
	return false


func get_level_name() -> String:
	match level:
		FirebaseLevel.PATROL_BASE:
			return "Patrol Base"
		FirebaseLevel.FIRE_SUPPORT_BASE:
			return "Fire Support Base"
		FirebaseLevel.MAJOR_FIREBASE:
			return "Major Firebase"
	return "Unknown"
