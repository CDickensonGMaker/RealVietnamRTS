class_name JungleZone
extends Area3D
## JungleZone - Provides gameplay effects that diminish as area is cleared
##
## Use Area3D nodes in your scenes to define jungle zones with gameplay effects:
## - Cover bonus (harder to hit units in zone)
## - Movement penalty (slower movement in dense jungle)
## - Visibility range (limited sight distance)
##
## Effects diminish proportionally as the zone is cleared by workers.

signal zone_cleared_changed(zone: JungleZone, cleared_pct: float)
signal zone_fully_cleared(zone: JungleZone)

enum DensityLevel { LIGHT, MEDIUM, HEAVY }

## Jungle density level - affects base values
@export var density: DensityLevel = DensityLevel.MEDIUM

## Base cover bonus (0.0-1.0) - how much harder to hit units in this zone
## At full jungle, units receive this bonus to their hit avoidance
@export_range(0.0, 0.5) var base_cover_bonus: float = 0.2

## Base movement penalty (0.0-1.0) - how much slower units move
## 0.3 = 30% slower, 0.5 = 50% slower, etc.
@export_range(0.0, 0.7) var base_movement_penalty: float = 0.3

## Base visibility range (meters) - max sight distance in full jungle
## Units cannot see targets beyond this distance while in the zone
@export_range(5.0, 50.0) var base_visibility_range: float = 15.0

## Visual debug - show zone bounds with semi-transparent mesh
@export var show_debug_mesh: bool = false

## Original zone area for calculating cleared percentage
var _original_area: float = 0.0

## Total area that has been cleared within this zone
var _cleared_area: float = 0.0

## Debug mesh for visualization
var _debug_mesh: MeshInstance3D = null


func _ready() -> void:
	# Calculate original area from collision shape
	_calculate_original_area()

	# Add to group for easy queries
	add_to_group("jungle_zones")

	# Set collision layer for zone detection (layer 10 = bit 512)
	collision_layer = 512
	collision_mask = 0  # We don't need to detect anything

	# Apply density-based defaults if not customized
	_apply_density_defaults()

	# Create debug visualization if enabled
	if show_debug_mesh:
		_create_debug_mesh()

	print("[JungleZone] Created %s density zone at %v (area: %.1f m^2)" % [
		DensityLevel.keys()[density], global_position, _original_area
	])


func _apply_density_defaults() -> void:
	"""Apply default values based on density level"""
	match density:
		DensityLevel.LIGHT:
			if base_cover_bonus == 0.2:  # Only if not customized
				base_cover_bonus = 0.1
			if base_movement_penalty == 0.3:
				base_movement_penalty = 0.15
			if base_visibility_range == 15.0:
				base_visibility_range = 30.0
		DensityLevel.MEDIUM:
			# Defaults are already for medium
			pass
		DensityLevel.HEAVY:
			if base_cover_bonus == 0.2:
				base_cover_bonus = 0.35
			if base_movement_penalty == 0.3:
				base_movement_penalty = 0.5
			if base_visibility_range == 15.0:
				base_visibility_range = 10.0


func _calculate_original_area() -> void:
	"""Calculate the original area from collision shapes"""
	for child in get_children():
		if child is CollisionShape3D:
			var shape: Shape3D = child.shape
			if shape is BoxShape3D:
				var box := shape as BoxShape3D
				_original_area += box.size.x * box.size.z
			elif shape is CylinderShape3D:
				var cyl := shape as CylinderShape3D
				_original_area += PI * cyl.radius * cyl.radius
			elif shape is SphereShape3D:
				var sphere := shape as SphereShape3D
				_original_area += PI * sphere.radius * sphere.radius

	# If no collision shapes, estimate from scale
	if _original_area <= 0:
		_original_area = scale.x * scale.z * 100.0  # Rough estimate


func _create_debug_mesh() -> void:
	"""Create a semi-transparent mesh to visualize zone bounds"""
	_debug_mesh = MeshInstance3D.new()
	_debug_mesh.name = "DebugMesh"

	# Try to match collision shape
	for child in get_children():
		if child is CollisionShape3D:
			var shape: Shape3D = child.shape
			if shape is BoxShape3D:
				var box := shape as BoxShape3D
				var mesh := BoxMesh.new()
				mesh.size = box.size
				_debug_mesh.mesh = mesh
				_debug_mesh.position = child.position
				break
			elif shape is CylinderShape3D:
				var cyl := shape as CylinderShape3D
				var mesh := CylinderMesh.new()
				mesh.top_radius = cyl.radius
				mesh.bottom_radius = cyl.radius
				mesh.height = cyl.height
				_debug_mesh.mesh = mesh
				_debug_mesh.position = child.position
				break

	if not _debug_mesh.mesh:
		# Fallback to a simple box
		var mesh := BoxMesh.new()
		mesh.size = Vector3(10, 3, 10)
		_debug_mesh.mesh = mesh

	# Create semi-transparent material
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = _get_density_color()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_debug_mesh.material_override = mat

	add_child(_debug_mesh)


func _get_density_color() -> Color:
	"""Get debug color based on density and cleared percentage"""
	var cleared := get_cleared_percentage()
	var base_color: Color

	match density:
		DensityLevel.LIGHT:
			base_color = Color(0.2, 0.6, 0.2, 0.3)  # Light green
		DensityLevel.MEDIUM:
			base_color = Color(0.1, 0.4, 0.1, 0.4)  # Medium green
		DensityLevel.HEAVY:
			base_color = Color(0.05, 0.25, 0.05, 0.5)  # Dark green
		_:
			base_color = Color(0.1, 0.4, 0.1, 0.4)

	# Fade to transparent as zone is cleared
	base_color.a *= (1.0 - cleared)
	return base_color


## Get the percentage of this zone that has been cleared (0.0-1.0)
func get_cleared_percentage() -> float:
	if _original_area <= 0:
		return 0.0
	return clampf(_cleared_area / _original_area, 0.0, 1.0)


## Get effective cover bonus (decreases as zone is cleared)
func get_effective_cover() -> float:
	return base_cover_bonus * (1.0 - get_cleared_percentage())


## Get effective movement penalty (decreases as zone is cleared)
func get_effective_movement_penalty() -> float:
	return base_movement_penalty * (1.0 - get_cleared_percentage())


## Get effective visibility range (increases as zone is cleared)
func get_effective_visibility() -> float:
	var cleared := get_cleared_percentage()
	# Visibility INCREASES as jungle is cleared (less obstruction)
	# At 0% cleared: base_visibility_range (e.g., 15m in heavy jungle)
	# At 100% cleared: 100m (normal visibility)
	return lerpf(base_visibility_range, 100.0, cleared)


## Check if a unit should receive cover bonus from this zone
func provides_cover_at(world_pos: Vector3) -> bool:
	if get_cleared_percentage() >= 1.0:
		return false

	# Check if position overlaps with zone
	for child in get_children():
		if child is CollisionShape3D:
			var local_pos := to_local(world_pos)
			var shape: Shape3D = child.shape
			if shape is BoxShape3D:
				var box := shape as BoxShape3D
				var half := box.size * 0.5
				if absf(local_pos.x) <= half.x and absf(local_pos.z) <= half.z:
					return true
			elif shape is CylinderShape3D or shape is SphereShape3D:
				var radius: float = 0.0
				if shape is CylinderShape3D:
					radius = (shape as CylinderShape3D).radius
				else:
					radius = (shape as SphereShape3D).radius
				if Vector2(local_pos.x, local_pos.z).length() <= radius:
					return true
	return false


## Called when clearing completes in this zone's area
## area_size: the size of the area that was cleared (in square meters)
func mark_area_cleared(area_size: float) -> void:
	_cleared_area += area_size
	var pct := get_cleared_percentage()

	# Update debug mesh color
	if _debug_mesh and _debug_mesh.material_override:
		var mat := _debug_mesh.material_override as StandardMaterial3D
		mat.albedo_color = _get_density_color()

	zone_cleared_changed.emit(self, pct)

	print("[JungleZone] Cleared %.1f m^2 (now %.0f%% cleared)" % [area_size, pct * 100])

	if pct >= 1.0:
		zone_fully_cleared.emit(self)
		# Optionally disable zone when fully cleared
		monitoring = false
		monitorable = false


## Check if a circle overlaps with this zone (for clearing integration)
func overlaps_circle(center: Vector3, radius: float) -> bool:
	for child in get_children():
		if child is CollisionShape3D:
			var shape_center := global_position + child.position
			var shape: Shape3D = child.shape

			if shape is BoxShape3D:
				var box := shape as BoxShape3D
				# Simple box-circle overlap check
				var closest := Vector3(
					clampf(center.x, shape_center.x - box.size.x/2, shape_center.x + box.size.x/2),
					center.y,
					clampf(center.z, shape_center.z - box.size.z/2, shape_center.z + box.size.z/2)
				)
				if center.distance_to(closest) <= radius:
					return true
			elif shape is CylinderShape3D or shape is SphereShape3D:
				var shape_radius: float = 0.0
				if shape is CylinderShape3D:
					shape_radius = (shape as CylinderShape3D).radius
				else:
					shape_radius = (shape as SphereShape3D).radius
				var dist := Vector2(center.x - shape_center.x, center.z - shape_center.z).length()
				if dist <= radius + shape_radius:
					return true
	return false


## Static helper: Get all jungle zones at a world position
static func get_zones_at(world_pos: Vector3) -> Array[JungleZone]:
	var result: Array[JungleZone] = []
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return result

	for zone in tree.get_nodes_in_group("jungle_zones"):
		if zone is JungleZone and zone.provides_cover_at(world_pos):
			result.append(zone)

	return result


## Static helper: Get combined cover bonus at a position (from all overlapping zones)
static func get_cover_at(world_pos: Vector3) -> float:
	var zones := get_zones_at(world_pos)
	var max_cover: float = 0.0
	for zone in zones:
		max_cover = maxf(max_cover, zone.get_effective_cover())
	return max_cover


## Static helper: Get combined movement penalty at a position
static func get_movement_penalty_at(world_pos: Vector3) -> float:
	var zones := get_zones_at(world_pos)
	var max_penalty: float = 0.0
	for zone in zones:
		max_penalty = maxf(max_penalty, zone.get_effective_movement_penalty())
	return max_penalty


## Static helper: Get minimum visibility range at a position
static func get_visibility_at(world_pos: Vector3) -> float:
	var zones := get_zones_at(world_pos)
	if zones.is_empty():
		return 100.0  # Default full visibility

	var min_vis: float = 100.0
	for zone in zones:
		min_vis = minf(min_vis, zone.get_effective_visibility())
	return min_vis
