extends Node
## TreeNodeManager is registered as an autoload singleton
## TreeNodeManager - Manages interactable tree nodes for clearing operations
##
## This implements the hybrid tree system:
## - Distant trees: MultiMesh billboards (handled by VegetationManager)
## - Nearby/targeted trees: Individual TreeNode instances
##
## When a clearing zone is created, this manager:
## 1. Queries the terrain grid for vegetation density in the area
## 2. Spawns TreeNode instances for trees that will be cleared
## 3. Tracks cleared trees and updates terrain data

signal trees_spawned(count: int, region: Rect2)
signal all_trees_cleared(zone: ClearingZoneNode)

## Container for tree nodes
var tree_container: Node3D

## Active clearing zones being tracked
var _active_zones: Array[ClearingZoneNode] = []

## Trees spawned per zone (for cleanup)
var _zone_trees: Dictionary = {}  # ClearingZoneNode -> Array[TreeNode]

## Reference to terrain systems
var _terrain: Node
var _terrain_grid: Node
var _vegetation_manager: Node
var _clearing_system: Node
var _lod_manager: Node


func _ready() -> void:
	# Create container for tree nodes
	tree_container = Node3D.new()
	tree_container.name = "TreeNodes"
	add_child(tree_container)

	# Get terrain references (with fallback to scene-local terrain via group)
	_terrain = get_node_or_null("/root/UnifiedTerrain")
	if not _terrain:
		_terrain = get_node_or_null("/root/TerrainIntegration")
	if not _terrain:
		# Fallback: find any terrain manager in scene tree via group
		for node in get_tree().get_nodes_in_group("terrain_managers"):
			if node.has_method("get_height_at"):
				_terrain = node
				print("[TreeNodeManager] Using scene-local terrain: %s" % node.name)
				break

	# Try to get vegetation manager for billboard removal
	_vegetation_manager = get_node_or_null("/root/TerrainIntegration")
	if _vegetation_manager and _vegetation_manager.has_method("get_vegetation_manager"):
		_vegetation_manager = _vegetation_manager.get_vegetation_manager()

	# Get ClearingSystem for marking terrain as cleared (triggers billboard removal)
	_clearing_system = get_node_or_null("/root/ClearingSystem")

	# Get VegetationLODManager for tree visibility culling
	_lod_manager = get_node_or_null("/root/VegetationLODManager")
	if _lod_manager:
		_lod_manager.register_tree_container(tree_container)

	print("[TreeNodeManager] Initialized (ClearingSystem: %s, LODManager: %s)" % [
		"connected" if _clearing_system else "not found",
		"connected" if _lod_manager else "not found"
	])


## Called when a clearing job is created - creates visual zone for clearing feedback
func prepare_clearing_zone(center: Vector3, radius: float) -> ClearingZoneNode:
	# Create the clearing zone node
	var zone := ClearingZoneNode.create(center, radius)
	tree_container.add_child(zone)
	_active_zones.append(zone)
	_zone_trees[zone] = []

	# Zone completion cleanup (billboard mark + tree cleanup safety net)
	zone.clearing_complete.connect(_on_zone_complete.bind(zone))

	# Spawn individual fell-able TreeNodes so workers can chop them one at a time.
	var tree_count := _spawn_trees_in_area(zone, center, radius)

	print("[TreeNodeManager] Created clearing zone at %v with %d fell-able trees" % [center, tree_count])

	return zone


## Spawn tree nodes based on terrain vegetation density
func _spawn_trees_in_area(zone: ClearingZoneNode, center: Vector3, radius: float) -> int:
	# De-dup: if fell-able trees already exist here (e.g. a scene pre-spawned its own
	# dense trees), don't pile more on top. The worker felling path targets whatever
	# trees are in the area, so existing ones are handled either way.
	var existing := 0
	for t in get_tree().get_nodes_in_group("trees"):
		if t is Node3D and is_instance_valid(t):
			var d := Vector2(t.global_position.x - center.x, t.global_position.z - center.z).length()
			if d <= radius:
				existing += 1
	if existing > 0:
		print("[TreeNodeManager] %d trees already present - skipping spawn" % existing)
		return existing

	var trees_spawned_count := 0

	# Get vegetation density from terrain grid
	var density := _get_vegetation_density(center, radius)

	# Calculate tree count based on density and area
	var area := PI * radius * radius
	var trees_per_sq_meter := 0.1 * density  # Adjust based on density (0-1)
	var target_tree_count := int(area * trees_per_sq_meter)
	target_tree_count = clampi(target_tree_count, 1, 50)  # Reasonable limits

	# Spawn trees in a scattered pattern
	for i in range(target_tree_count):
		# Random position within radius (uniform distribution)
		var angle := randf() * TAU
		var dist := sqrt(randf()) * radius  # sqrt for uniform area distribution
		var pos := Vector3(
			center.x + cos(angle) * dist,
			0,
			center.z + sin(angle) * dist
		)

		# Get terrain height
		if _terrain and _terrain.has_method("get_height_at"):
			pos.y = _terrain.get_height_at(pos)

		# Determine tree type from terrain density
		var terrain_type: int = 5  # Default: HEAVY_JUNGLE
		if _terrain and _terrain.has_method("get_terrain_type"):
			terrain_type = _terrain.get_terrain_type(pos)

		# Random height based on density
		var height := randf_range(6.0, 12.0)
		match terrain_type:
			3:  # LIGHT_JUNGLE
				height = randf_range(4.0, 7.0)
			4:  # MEDIUM_JUNGLE
				height = randf_range(6.0, 10.0)
			5:  # HEAVY_JUNGLE
				height = randf_range(8.0, 14.0)

		# Create tree using density-specific model
		var tree := TreeNode.create_from_terrain_type(terrain_type, pos, height)
		tree_container.add_child(tree)
		_zone_trees[zone].append(tree)

		# Register with LOD manager for distance culling
		if _lod_manager:
			_lod_manager.register_tree(tree)

		# Connect tree cleared signal
		tree.tree_cleared.connect(_on_single_tree_cleared.bind(zone))

		trees_spawned_count += 1

	return trees_spawned_count


## Get vegetation density at a position (0-1)
func _get_vegetation_density(center: Vector3, radius: float) -> float:
	# Try to get from terrain grid
	if _terrain and _terrain.has_method("get_clearing_stage"):
		var stage: int = _terrain.get_clearing_stage(center)
		# JUNGLE = high density, CLEARED = no density
		match stage:
			0:  # HEAVY_JUNGLE
				return 1.0
			1:  # LIGHT_JUNGLE
				return 0.6
			2:  # PARTIALLY_CLEARED
				return 0.3
			_:  # CLEARED, FORTIFIED
				return 0.0

	# Fallback: assume jungle
	return 0.8


func _on_single_tree_cleared(tree: TreeNode, zone: ClearingZoneNode) -> void:
	# Unregister from LOD manager
	if _lod_manager:
		_lod_manager.unregister_tree(tree)

	# Remove from tracking
	if zone in _zone_trees:
		_zone_trees[zone].erase(tree)


func _on_zone_complete(zone: ClearingZoneNode) -> void:
	all_trees_cleared.emit(zone)

	# NOTE: Progressive clearing in ClearingZoneNode._update_visuals() handles
	# billboard removal as the zone expands. This final call ensures any edge
	# cases are cleaned up (shouldn't be needed but acts as a safety net).
	if _clearing_system and _clearing_system.has_method("mark_area_cleared"):
		_clearing_system.mark_area_cleared(zone.global_position, zone.target_radius)

	# Clean up remaining trees (shouldn't be any, but just in case)
	if zone in _zone_trees:
		for tree in _zone_trees[zone]:
			if is_instance_valid(tree):
				tree.queue_free()
		_zone_trees.erase(zone)

	_active_zones.erase(zone)


## Add work to a specific clearing zone (called by workers)
func add_work_to_zone(zone: ClearingZoneNode, amount: float) -> bool:
	if is_instance_valid(zone):
		return zone.add_work(amount)
	return false


## Get the clearing zone at a position (if any)
func get_zone_at(world_pos: Vector3) -> ClearingZoneNode:
	for zone in _active_zones:
		if not is_instance_valid(zone):
			continue
		var dist := Vector2(world_pos.x - zone.global_position.x, world_pos.z - zone.global_position.z).length()
		if dist <= zone.target_radius:
			return zone
	return null


## Clean up all zones
func clear_all_zones() -> void:
	for zone in _active_zones:
		if is_instance_valid(zone):
			zone.queue_free()
	_active_zones.clear()
	_zone_trees.clear()

	# Clear any orphaned trees
	for child in tree_container.get_children():
		child.queue_free()
