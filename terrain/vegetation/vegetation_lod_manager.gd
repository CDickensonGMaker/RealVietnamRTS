extends Node
## VegetationLODManager - Autoload singleton
## Note: No class_name needed - autoloads are accessed by their registered name.
## Adding class_name would conflict with the autoload singleton in Godot 4.6+.
## Coordinates LOD transitions between 3D trees (near) and billboards (far).
## Uses hysteresis to prevent flickering at distance thresholds.

# LOD distance thresholds with hysteresis buffer
# Increased distances for better visibility - 3D trees visible much further
const TREE_SHOW_DISTANCE := 200.0   # 3D trees become visible below this
const TREE_HIDE_DISTANCE := 250.0   # 3D trees hide above this (50m buffer)
# Billboards remain visible at ALL distances - no hiding
# This creates dense jungle illusion with 3D trees emerging close to camera

# Update frequency (matches billboard system)
const UPDATE_INTERVAL := 0.1  # 10Hz

# Tracked state
var _camera: Camera3D
var _tracked_trees: Array[Node3D] = []
var _tree_visibility: Dictionary = {}  # Node3D -> bool
var _tree_containers: Array[Node3D] = []  # Containers holding multiple trees
var _update_timer: float = 0.0
var _enabled: bool = true


func _ready() -> void:
	set_process(true)
	print("[VegetationLODManager] Initialized - Tree LOD: show<%dm, hide>%dm" % [
		int(TREE_SHOW_DISTANCE), int(TREE_HIDE_DISTANCE)
	])


func _process(delta: float) -> void:
	if not _enabled:
		return

	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_update_lod()


## Set the camera to track for distance calculations
func set_camera(camera: Camera3D) -> void:
	_camera = camera
	if camera:
		print("[VegetationLODManager] Camera set: %s" % camera.name)


## Auto-detect camera from viewport
func auto_detect_camera() -> void:
	var viewport := get_viewport()
	if viewport:
		_camera = viewport.get_camera_3d()
		if _camera:
			print("[VegetationLODManager] Auto-detected camera: %s" % _camera.name)


## Register a single tree for LOD management
func register_tree(tree: Node3D) -> void:
	if tree and tree not in _tracked_trees:
		_tracked_trees.append(tree)
		_tree_visibility[tree] = true  # Assume visible initially


## Unregister a tree (call before freeing)
func unregister_tree(tree: Node3D) -> void:
	_tracked_trees.erase(tree)
	_tree_visibility.erase(tree)


## Register a container node - all direct children will be tracked
func register_tree_container(container: Node3D) -> void:
	if container and container not in _tree_containers:
		_tree_containers.append(container)
		# Register all current children
		for child in container.get_children():
			if child is Node3D:
				register_tree(child)
		print("[VegetationLODManager] Registered container '%s' with %d trees" % [
			container.name, container.get_child_count()
		])


## Unregister a container and all its trees
func unregister_tree_container(container: Node3D) -> void:
	if container in _tree_containers:
		_tree_containers.erase(container)
		# Unregister all children
		for child in container.get_children():
			if child is Node3D:
				unregister_tree(child)


## Bulk register trees from an array
func register_trees(trees: Array) -> void:
	for tree in trees:
		if tree is Node3D:
			register_tree(tree)
	print("[VegetationLODManager] Bulk registered %d trees" % trees.size())


## Clear all tracked trees
func clear_all() -> void:
	_tracked_trees.clear()
	_tree_visibility.clear()
	_tree_containers.clear()


## Enable/disable LOD updates
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		# Show all trees when disabled
		for tree in _tracked_trees:
			if is_instance_valid(tree):
				tree.visible = true


## Get current tree count
func get_tracked_tree_count() -> int:
	return _tracked_trees.size()


## Core LOD update - called at 10Hz
func _update_lod() -> void:
	if not _camera:
		auto_detect_camera()
		if not _camera:
			return

	var cam_pos := _camera.global_position
	var trees_shown := 0
	var trees_hidden := 0

	# Clean up invalid references and update visibility
	var valid_trees: Array[Node3D] = []

	for tree in _tracked_trees:
		if not is_instance_valid(tree):
			_tree_visibility.erase(tree)
			continue

		valid_trees.append(tree)

		var dist := cam_pos.distance_to(tree.global_position)
		var currently_visible: bool = _tree_visibility.get(tree, true)
		var should_show: bool

		# Hysteresis logic prevents flicker at threshold
		if currently_visible:
			# Currently visible - stay visible until we exceed hide distance
			should_show = dist < TREE_HIDE_DISTANCE
		else:
			# Currently hidden - become visible when below show distance
			should_show = dist < TREE_SHOW_DISTANCE

		# Only update if state changed
		if should_show != currently_visible:
			tree.visible = should_show
			_tree_visibility[tree] = should_show

		if should_show:
			trees_shown += 1
		else:
			trees_hidden += 1

	# Update tracked array with only valid trees
	_tracked_trees = valid_trees


## Force all trees visible (for debugging/manual override)
func force_all_visible() -> void:
	for tree in _tracked_trees:
		if is_instance_valid(tree):
			tree.visible = true
			_tree_visibility[tree] = true


## Force all trees hidden
func force_all_hidden() -> void:
	for tree in _tracked_trees:
		if is_instance_valid(tree):
			tree.visible = false
			_tree_visibility[tree] = false


## Get visibility stats for debugging
func get_stats() -> Dictionary:
	var visible_count := 0
	var hidden_count := 0
	var invalid_count := 0

	for tree in _tracked_trees:
		if not is_instance_valid(tree):
			invalid_count += 1
		elif _tree_visibility.get(tree, true):
			visible_count += 1
		else:
			hidden_count += 1

	return {
		"total": _tracked_trees.size(),
		"visible": visible_count,
		"hidden": hidden_count,
		"invalid": invalid_count,
		"containers": _tree_containers.size()
	}
