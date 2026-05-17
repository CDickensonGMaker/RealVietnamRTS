## cell_streamer.gd - Loads/unloads terrain cells around the camera
## Daggerfall-style cell streaming for seamless Vietnam terrain
class_name VietnamCellStreamer
extends Node3D


## =============================================================================
## SIGNALS
## =============================================================================
signal cell_loaded(coords: Vector2i, cell: VietnamCell)
signal cell_unloaded(coords: Vector2i)
signal active_cell_changed(old_coords: Vector2i, new_coords: Vector2i)
signal streaming_started()
signal streaming_stopped()


## =============================================================================
## CONFIGURATION
## =============================================================================
@export var load_radius: int = 2          ## Cells to load around camera
@export var unload_radius: int = 3        ## Cells beyond this are unloaded
@export var load_delay: float = 0.1       ## Delay between cell loads (performance)
@export var campaign_id: String = "ia_drang"


## =============================================================================
## STATE
## =============================================================================
var _loaded_cells: Dictionary = {}  # Vector2i -> VietnamCell
var _active_cell: Vector2i = Vector2i.ZERO
var _camera: Camera3D = null
var _streaming_enabled: bool = false
var _pending_loads: Array[Vector2i] = []
var _load_timer: float = 0.0


## =============================================================================
## LIFECYCLE
## =============================================================================

func _ready() -> void:
	# Find camera
	_camera = get_viewport().get_camera_3d()


func _process(delta: float) -> void:
	if not _streaming_enabled:
		return

	# Get camera position
	var camera_pos: Vector3 = _get_camera_world_position()
	var camera_cell: Vector2i = VietnamWorldGrid.world_to_cell(camera_pos)

	# Check if active cell changed
	if camera_cell != _active_cell:
		var old_cell: Vector2i = _active_cell
		_active_cell = camera_cell
		active_cell_changed.emit(old_cell, camera_cell)
		_update_cell_loading()

	# Process pending loads
	if _pending_loads.size() > 0:
		_load_timer += delta
		if _load_timer >= load_delay:
			_load_timer = 0.0
			_load_next_cell()


func _get_camera_world_position() -> Vector3:
	if _camera:
		return _camera.global_position
	return Vector3.ZERO


## =============================================================================
## PUBLIC API
## =============================================================================

## Start streaming from a specific cell
func start_streaming(start_coords: Vector2i) -> void:
	_streaming_enabled = true
	_active_cell = start_coords

	# Initialize world grid and systems
	VietnamWorldGrid.initialize(campaign_id)
	TrailNetwork.initialize(campaign_id)
	RiverGenerator.initialize(campaign_id)
	VillagePlacer.initialize(campaign_id)

	_update_cell_loading()
	streaming_started.emit()


## Stop streaming and unload all cells
func stop_streaming() -> void:
	_streaming_enabled = false
	_pending_loads.clear()

	# Unload all cells
	for coords in _loaded_cells.keys():
		_unload_cell(coords)

	streaming_stopped.emit()


## Pause streaming (keep cells loaded)
func pause_streaming() -> void:
	_streaming_enabled = false


## Resume streaming
func resume_streaming() -> void:
	_streaming_enabled = true
	_update_cell_loading()


## Get the currently active cell
func get_active_cell() -> Vector2i:
	return _active_cell


## Check if a cell is loaded
func is_cell_loaded(coords: Vector2i) -> bool:
	return _loaded_cells.has(coords)


## Get a loaded cell
func get_cell(coords: Vector2i) -> VietnamCell:
	return _loaded_cells.get(coords, null)


## Teleport to a specific cell
func teleport_to_cell(coords: Vector2i) -> void:
	_active_cell = coords
	_update_cell_loading()


## Set camera reference
func set_camera(camera: Camera3D) -> void:
	_camera = camera


## Change campaign
func set_campaign(new_campaign_id: String) -> void:
	stop_streaming()
	campaign_id = new_campaign_id
	start_streaming(_active_cell)


## =============================================================================
## CELL LOADING/UNLOADING
## =============================================================================

func _update_cell_loading() -> void:
	# Find cells that should be loaded
	var cells_to_load: Array[Vector2i] = _get_cells_in_radius(_active_cell, load_radius)

	# Find cells that should be unloaded
	var cells_to_unload: Array[Vector2i] = []
	for coords in _loaded_cells.keys():
		var distance: int = _cell_distance(coords, _active_cell)
		if distance > unload_radius:
			cells_to_unload.append(coords)

	# Unload distant cells immediately
	for coords in cells_to_unload:
		_unload_cell(coords)

	# Queue cells for loading (prioritize by distance)
	_pending_loads.clear()
	for coords in cells_to_load:
		if not _loaded_cells.has(coords):
			_pending_loads.append(coords)

	# Sort by distance (closest first)
	_pending_loads.sort_custom(_compare_by_distance)


func _compare_by_distance(a: Vector2i, b: Vector2i) -> bool:
	return _cell_distance(a, _active_cell) < _cell_distance(b, _active_cell)


func _get_cells_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []

	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			var coords := Vector2i(x, y)
			if _cell_distance(coords, center) <= radius:
				if VietnamWorldGrid.is_in_bounds(coords, campaign_id):
					cells.append(coords)

	return cells


func _cell_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _load_next_cell() -> void:
	if _pending_loads.is_empty():
		return

	var coords: Vector2i = _pending_loads.pop_front()

	# Double check it's not already loaded
	if _loaded_cells.has(coords):
		return

	_load_cell(coords)


func _load_cell(coords: Vector2i) -> void:
	var cell := VietnamCell.new()
	cell.name = "Cell_%d_%d" % [coords.x, coords.y]

	# Position cell in world
	var world_pos: Vector3 = VietnamWorldGrid.cell_to_world(coords)
	cell.position = world_pos

	add_child(cell)

	# Generate terrain
	cell.generate(coords, campaign_id)

	_loaded_cells[coords] = cell
	cell_loaded.emit(coords, cell)


func _unload_cell(coords: Vector2i) -> void:
	if not _loaded_cells.has(coords):
		return

	var cell: VietnamCell = _loaded_cells[coords]
	cell.unload()

	_loaded_cells.erase(coords)
	cell_unloaded.emit(coords)


## =============================================================================
## QUERY HELPERS
## =============================================================================

## Get height at world position
func get_height_at(world_pos: Vector3) -> float:
	var coords: Vector2i = VietnamWorldGrid.world_to_cell(world_pos)
	var cell: VietnamCell = get_cell(coords)

	if cell:
		return cell.get_height_at_world(world_pos)

	return 0.0


## Get terrain type at world position
func get_terrain_at(world_pos: Vector3) -> VietnamTerrain.TerrainType:
	var coords: Vector2i = VietnamWorldGrid.world_to_cell(world_pos)
	var cell: VietnamCell = get_cell(coords)

	if cell:
		return cell.get_terrain_type()

	return VietnamTerrain.TerrainType.SINGLE_CANOPY


## Get speed modifier at world position
func get_speed_modifier_at(world_pos: Vector3) -> float:
	var coords: Vector2i = VietnamWorldGrid.world_to_cell(world_pos)
	var cell: VietnamCell = get_cell(coords)

	if cell:
		return cell.get_speed_modifier()

	return 1.0


## Get concealment at world position
func get_concealment_at(world_pos: Vector3) -> float:
	var coords: Vector2i = VietnamWorldGrid.world_to_cell(world_pos)
	var cell: VietnamCell = get_cell(coords)

	if cell:
		return cell.get_concealment()

	return 0.0


## Get all loaded cells
func get_loaded_cells() -> Array[VietnamCell]:
	var cells: Array[VietnamCell] = []
	for cell in _loaded_cells.values():
		cells.append(cell)
	return cells


## Get cell at world position
func get_cell_at(world_pos: Vector3) -> VietnamCell:
	var coords: Vector2i = VietnamWorldGrid.world_to_cell(world_pos)
	return get_cell(coords)
