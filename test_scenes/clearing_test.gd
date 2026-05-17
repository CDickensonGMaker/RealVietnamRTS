extends Node3D
## Clearing Test Scene - Tests worker auto-assignment to clear jobs
##
## Uses 2D billboard trees from BillboardVegetation system
## RTS camera controls via TestSceneBase
##
## Rise to Ruins style: Paint clear areas, workers auto-go do them
##
## Controls:
## - WASD: Pan camera
## - Mouse wheel: Zoom
## - Middle mouse drag: Rotate
## - Left-click + drag: Paint clear area
## - Right-click: Cancel
## - E: Spawn engineer at cursor
## - B: Spawn bulldozer at cursor
## - Space: Toggle auto-mode

const JobTypes = preload("res://firebase_system/jobs/job_types.gd")
const TerrainTypes = preload("res://terrain/terrain_types.gd")

## Mock heightmap for flat terrain
class MockHeightmap:
	var height: float = 0.0

	func sample_world(_x: float, _z: float) -> float:
		return height

	func get_normal_world(_x: float, _z: float) -> Vector3:
		return Vector3.UP

## State
var camera: Camera3D
var is_painting := false
var paint_start: Vector3 = Vector3.INF
var paint_current: Vector3 = Vector3.INF
var area_preview: MeshInstance3D
var hud: Label
var workers: Array[Node3D] = []

## Note: ground collision is provided by TerrainManager chunks via create_raycast_collision()

## Local terrain for test scene (faster than 3km full terrain)
var local_terrain: TerrainManager  # Local instance with small map
var terrain_intg: Node  # TerrainIntegration autoload (fallback)

## Vegetation systems
var vegetation_manager: VegetationManager
var billboard_vegetation: BillboardVegetation
var mock_heightmap: MockHeightmap
var chunk_size: float = 64.0  # Chunk size for vegetation bundles

## Grid overlay for visualizing clearing bundles
var grid_overlay: MeshInstance3D
var grid_visible := true

## Vegetation chunks (covering center of map)
var VEG_CHUNKS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]

## Map size for camera bounds
var MAP_SIZE := 128.0


func _ready() -> void:
	print("=== Clearing Test (Billboard Trees) ===")
	print("Testing worker auto-assignment to clear jobs")
	print("")

	# Get TerrainIntegration autoload (we may use its systems if already initialized)
	terrain_intg = get_node_or_null("/root/TerrainIntegration")

	# Disable TerrainIntegration's vegetation to prevent duplicate billboard systems
	if terrain_intg and terrain_intg.has_method("get"):
		var ti_billboard = terrain_intg.get("billboard_vegetation")
		if ti_billboard and ti_billboard is Node3D:
			ti_billboard.visible = false
			ti_billboard.set_process(false)
			print("[ClearingTest] Disabled TerrainIntegration billboard vegetation")

	# Calculate center of map for spawning and camera
	var map_center := MAP_SIZE * 0.5

	# Use TestSceneBase for RTS camera and environment
	# Skip global terrain - we use local terrain for fast iteration
	var setup_result: Dictionary = TestSceneBase.setup_environment(self, {
		"name": "Clearing Test",
		"size": MAP_SIZE,
		"seed": 42,
		"add_camera": true,
		"camera_position": Vector3(map_center, 60, map_center + 40),
		"skip_terrain": true,  # We'll create a small local terrain instead
	})
	camera = setup_result.get("camera") as Camera3D

	# Create local TerrainManager for fast terrain (128m instead of 3km)
	# This generates quickly and gives us real heightmap for testing
	_setup_local_terrain()

	_setup_vegetation()
	_setup_area_preview()
	_setup_grid_overlay()

	# Create simple HUD
	hud = TestSceneBase.make_hud(self)

	# Disable SelectionManager to prevent blue box interference
	var sel_mgr = get_node_or_null("/root/SelectionManager")
	if sel_mgr:
		sel_mgr.set_process_input(false)
		print("[ClearingTest] Disabled SelectionManager input")

	# Spawn initial workers at center of map
	_spawn_engineer(Vector3(map_center - 3, 0, map_center))
	_spawn_bulldozer(Vector3(map_center + 3, 0, map_center))

	# Connect to JobManager
	var job_mgr = get_node_or_null("/root/JobManager")
	if job_mgr:
		job_mgr.job_created.connect(_on_job_created)
		job_mgr.job_completed.connect(_on_job_completed)
		print("[ClearingTest] Connected to JobManager")
	else:
		push_error("[ClearingTest] JobManager not found!")

	# Check BuilderAI
	var builder_ai = get_node_or_null("/root/BuilderAI")
	if builder_ai:
		builder_ai.auto_mode_enabled = true
		print("[ClearingTest] BuilderAI auto_mode: %s" % builder_ai.auto_mode_enabled)
	else:
		push_error("[ClearingTest] BuilderAI not found!")

	print("")
	print("Controls:")
	print("  WASD: Pan camera")
	print("  Mouse wheel: Zoom")
	print("  Middle mouse drag: Rotate")
	print("  Left-click + drag: Paint clear area")
	print("  E: Spawn engineer | B: Spawn bulldozer")
	print("  Space: Toggle auto-mode")
	print("  G: Toggle grid overlay")
	print("")


func _exit_tree() -> void:
	# Re-enable TerrainIntegration's vegetation when test scene closes
	if terrain_intg and terrain_intg.has_method("get"):
		var ti_billboard = terrain_intg.get("billboard_vegetation")
		if ti_billboard and ti_billboard is Node3D:
			ti_billboard.visible = true
			ti_billboard.set_process(true)
			print("[ClearingTest] Re-enabled TerrainIntegration billboard vegetation")


## Setup local terrain with small map for fast generation
func _setup_local_terrain() -> void:
	print("[ClearingTest] Creating local terrain (%.0fm map)..." % MAP_SIZE)

	# Create TerrainManager with small map settings
	local_terrain = TerrainManager.new()
	local_terrain.name = "LocalTerrain"
	local_terrain.map_size = MAP_SIZE
	local_terrain.chunk_size = chunk_size  # 64m chunks = 4 chunks for 128m map
	local_terrain.cell_size = 2.0
	local_terrain.height_scale = 40.0  # Lower hills for test area
	local_terrain.rivers_enabled = false  # No rivers for fast generation
	local_terrain.load_distance = 3
	local_terrain.unload_distance = 4
	add_child(local_terrain)

	# Set camera for chunk streaming
	local_terrain.set_camera(camera)

	# Generate terrain synchronously (small map = fast)
	local_terrain.generate_terrain(42)

	print("[ClearingTest] Local terrain ready (%.0fm, %d chunks, height 0-%.0fm)" % [
		MAP_SIZE,
		local_terrain.chunks.size(),
		local_terrain.height_scale
	])


func _setup_vegetation() -> void:
	# Create mock heightmap as fallback (should rarely be used now)
	mock_heightmap = MockHeightmap.new()

	# Get heightmap - should be local_terrain's heightmap
	var heightmap_to_use = _get_heightmap_or_mock()
	var using_real_terrain: bool = heightmap_to_use != mock_heightmap

	# Create VegetationManager for terrain type data
	vegetation_manager = VegetationManager.new()
	vegetation_manager.name = "VegetationManager"
	vegetation_manager.set_chunk_size(chunk_size)
	vegetation_manager.set_camera(camera)
	add_child(vegetation_manager)

	# Create BillboardVegetation for 2D billboard trees
	billboard_vegetation = BillboardVegetation.new()
	billboard_vegetation.name = "BillboardVegetation"
	billboard_vegetation.set_chunk_size(chunk_size)
	billboard_vegetation.set_camera(camera)
	billboard_vegetation.set_vegetation_manager(vegetation_manager)
	add_child(billboard_vegetation)

	# Generate terrain types for all chunks covering the play area
	for chunk_coord in VEG_CHUNKS:
		# Generate terrain types (this creates the terrain data but we won't show 3D trees)
		vegetation_manager.generate_for_chunk(chunk_coord, heightmap_to_use, chunk_size)

		# Set all bundles to HEAVY_JUNGLE for dense forest
		_set_chunk_heavy_jungle(chunk_coord)

		# Hide the 3D trees from VegetationManager (we'll use billboards instead)
		vegetation_manager.clear_chunk_visuals(chunk_coord)

		# Generate billboards using the terrain data and real heightmap
		if vegetation_manager._chunk_terrain.has(chunk_coord):
			var terrain_data: PackedByteArray = vegetation_manager._chunk_terrain[chunk_coord]
			billboard_vegetation.generate_for_chunk(chunk_coord, heightmap_to_use, terrain_data)

	var terrain_source: String = "local TerrainManager" if local_terrain else ("TerrainIntegration" if using_real_terrain else "mock flat")
	print("[ClearingTest] Billboard vegetation generated for %d chunks (terrain: %s)" % [
		VEG_CHUNKS.size(), terrain_source
	])


func _set_chunk_heavy_jungle(chunk_coord: Vector2i) -> void:
	if vegetation_manager._chunk_terrain.has(chunk_coord):
		var terrain: PackedByteArray = vegetation_manager._chunk_terrain[chunk_coord]
		for i in range(terrain.size()):
			terrain[i] = VegetationManager.TerrainType.HEAVY_JUNGLE
		vegetation_manager._chunk_terrain[chunk_coord] = terrain
		print("[ClearingTest] Set all bundles to HEAVY_JUNGLE")


func _setup_area_preview() -> void:
	area_preview = MeshInstance3D.new()
	area_preview.name = "AreaPreview"
	var box := BoxMesh.new()
	box.size = Vector3(1, 0.1, 1)
	area_preview.mesh = box

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.8, 0.2, 0.4)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	area_preview.material_override = mat
	area_preview.visible = false
	add_child(area_preview)


func _setup_grid_overlay() -> void:
	grid_overlay = MeshInstance3D.new()
	grid_overlay.name = "GridOverlay"
	add_child(grid_overlay)
	_rebuild_grid_overlay()
	print("[ClearingTest] Grid overlay created (G to toggle)")


## Rebuild the grid overlay mesh based on current vegetation terrain types
## Grid conforms to actual terrain height from TerrainManager
func _rebuild_grid_overlay() -> void:
	if not grid_overlay or not vegetation_manager:
		return

	var bundle_size: float = vegetation_manager.bundle_meters
	var bundles_per_side: int = int(chunk_size / bundle_size)

	# Build immediate geometry mesh with grid lines and cell fills
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	# Draw grid lines - sample terrain height at each vertex
	var line_color := Color(0.8, 0.8, 0.8, 0.6)  # Light gray
	var height_offset := 0.15  # Slightly above terrain surface

	# Draw grid for all chunks
	for chunk_coord in VEG_CHUNKS:
		if not vegetation_manager._chunk_terrain.has(chunk_coord):
			continue

		var chunk_offset_x: float = chunk_coord.x * chunk_size
		var chunk_offset_z: float = chunk_coord.y * chunk_size

		# Vertical lines (along Z) - sample height at each segment
		for x in range(bundles_per_side + 1):
			var world_x: float = chunk_offset_x + x * bundle_size
			for z in range(bundles_per_side):
				var z0: float = chunk_offset_z + z * bundle_size
				var z1: float = chunk_offset_z + (z + 1) * bundle_size
				var y0: float = _get_terrain_height(world_x, z0) + height_offset
				var y1: float = _get_terrain_height(world_x, z1) + height_offset
				im.surface_set_color(line_color)
				im.surface_add_vertex(Vector3(world_x, y0, z0))
				im.surface_add_vertex(Vector3(world_x, y1, z1))

		# Horizontal lines (along X) - sample height at each segment
		for z in range(bundles_per_side + 1):
			var world_z: float = chunk_offset_z + z * bundle_size
			for x in range(bundles_per_side):
				var x0: float = chunk_offset_x + x * bundle_size
				var x1: float = chunk_offset_x + (x + 1) * bundle_size
				var y0: float = _get_terrain_height(x0, world_z) + height_offset
				var y1: float = _get_terrain_height(x1, world_z) + height_offset
				im.surface_set_color(line_color)
				im.surface_add_vertex(Vector3(x0, y0, world_z))
				im.surface_add_vertex(Vector3(x1, y1, world_z))

	im.surface_end()

	# Create material for lines
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.vertex_color_use_as_albedo = true
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.no_depth_test = false
	im.surface_set_material(0, line_mat)

	# Build cell fill quads for terrain type visualization
	# Each quad conforms to terrain height at its 4 corners
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var fill_offset := 0.12  # Slightly below grid lines

	for chunk_coord in VEG_CHUNKS:
		if not vegetation_manager._chunk_terrain.has(chunk_coord):
			continue

		var terrain: PackedByteArray = vegetation_manager._chunk_terrain[chunk_coord]
		var chunk_offset_x: float = chunk_coord.x * chunk_size
		var chunk_offset_z: float = chunk_coord.y * chunk_size

		for bz in bundles_per_side:
			for bx in bundles_per_side:
				var idx: int = bz * bundles_per_side + bx
				if idx >= terrain.size():
					continue

				var terrain_type: int = terrain[idx]
				var cell_color: Color

				# Color based on terrain type
				match terrain_type:
					VegetationManager.TerrainType.CLEAR:
						cell_color = Color(0.6, 0.5, 0.3, 0.25)  # Light brown (cleared)
					VegetationManager.TerrainType.RICE_PADDY:
						cell_color = Color(0.4, 0.6, 0.3, 0.25)  # Yellow-green (paddies)
					VegetationManager.TerrainType.GRASSLAND:
						cell_color = Color(0.5, 0.7, 0.3, 0.25)  # Light green (grass)
					VegetationManager.TerrainType.LIGHT_JUNGLE:
						cell_color = Color(0.2, 0.5, 0.2, 0.25)  # Medium green
					VegetationManager.TerrainType.MEDIUM_JUNGLE:
						cell_color = Color(0.1, 0.4, 0.15, 0.3)  # Darker green
					VegetationManager.TerrainType.HEAVY_JUNGLE:
						cell_color = Color(0.05, 0.3, 0.1, 0.35)  # Dark green
					_:
						cell_color = Color(0.5, 0.5, 0.5, 0.2)  # Gray (unknown)

				# Quad corners with terrain-conforming heights
				var x0: float = chunk_offset_x + bx * bundle_size
				var x1: float = chunk_offset_x + (bx + 1) * bundle_size
				var z0: float = chunk_offset_z + bz * bundle_size
				var z1: float = chunk_offset_z + (bz + 1) * bundle_size

				var y00: float = _get_terrain_height(x0, z0) + fill_offset
				var y10: float = _get_terrain_height(x1, z0) + fill_offset
				var y01: float = _get_terrain_height(x0, z1) + fill_offset
				var y11: float = _get_terrain_height(x1, z1) + fill_offset

				# Two triangles for quad (terrain-conforming)
				im.surface_set_color(cell_color)
				im.surface_add_vertex(Vector3(x0, y00, z0))
				im.surface_add_vertex(Vector3(x1, y10, z0))
				im.surface_add_vertex(Vector3(x1, y11, z1))

				im.surface_add_vertex(Vector3(x0, y00, z0))
				im.surface_add_vertex(Vector3(x1, y11, z1))
				im.surface_add_vertex(Vector3(x0, y01, z1))

	im.surface_end()

	# Create material for fill
	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.vertex_color_use_as_albedo = true
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	im.surface_set_material(1, fill_mat)

	grid_overlay.mesh = im
	grid_overlay.visible = grid_visible


func _spawn_engineer(pos: Vector3) -> void:
	var data: Resource = load("res://battle_system/data/units/us_engineers.tres")
	if not data:
		data = SquadData.new()
		data.display_name = "Combat Engineer"
		data.squad_size = 4
		data.faction = GameEnums.Faction.US_ARMY
		data.can_build = true
		data.is_vehicle = false

	var engineer := Squad.new()
	engineer.name = "Engineer_%d" % workers.size()
	engineer.data = data
	# Set Y position from terrain height
	var terrain_y: float = _get_terrain_height(pos.x, pos.z)
	engineer.position = Vector3(pos.x, terrain_y, pos.z)

	add_child(engineer)
	workers.append(engineer)

	var builder_ai = get_node_or_null("/root/BuilderAI")
	if builder_ai and builder_ai.has_method("register_engineer"):
		builder_ai.register_engineer(engineer)
		print("[ClearingTest] Engineer spawned at Y=%.1f and registered" % terrain_y)


func _spawn_bulldozer(pos: Vector3) -> void:
	var data: Resource = load("res://battle_system/data/units/us_bulldozer.tres")
	if not data:
		data = SquadData.new()
		data.display_name = "D7 Bulldozer"
		data.squad_size = 1
		data.faction = GameEnums.Faction.US_ARMY
		data.can_build = true
		data.is_vehicle = true
		data.move_speed = 3.0

	var bulldozer := Squad.new()
	bulldozer.name = "Bulldozer_%d" % workers.size()
	bulldozer.data = data
	# Set Y position from terrain height
	var terrain_y: float = _get_terrain_height(pos.x, pos.z)
	bulldozer.position = Vector3(pos.x, terrain_y, pos.z)

	add_child(bulldozer)
	workers.append(bulldozer)

	var builder_ai = get_node_or_null("/root/BuilderAI")
	if builder_ai and builder_ai.has_method("register_bulldozer"):
		builder_ai.register_bulldozer(bulldozer)
		print("[ClearingTest] Bulldozer spawned at Y=%.1f and registered" % terrain_y)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_handle_mouse_button(mb)

	elif event is InputEventMouseMotion:
		if is_painting:
			paint_current = _raycast_ground(event.position)
			_update_area_preview()

	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed:
			_handle_key(key)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			paint_start = _raycast_ground(event.position)
			paint_current = paint_start
			is_painting = true
			area_preview.visible = true
		else:
			if is_painting and paint_start != Vector3.INF:
				_create_clear_job(paint_start, paint_current)
			is_painting = false
			area_preview.visible = false

	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		is_painting = false
		area_preview.visible = false


func _handle_key(event: InputEventKey) -> void:
	var cursor_pos := _raycast_ground(get_viewport().get_mouse_position())

	match event.keycode:
		KEY_E:
			if cursor_pos != Vector3.INF:
				_spawn_engineer(cursor_pos)

		KEY_B:
			if cursor_pos != Vector3.INF:
				_spawn_bulldozer(cursor_pos)

		KEY_SPACE:
			var builder_ai = get_node_or_null("/root/BuilderAI")
			if builder_ai:
				builder_ai.auto_mode_enabled = not builder_ai.auto_mode_enabled
				print("[ClearingTest] Auto-mode: %s" % builder_ai.auto_mode_enabled)

		KEY_G:
			grid_visible = not grid_visible
			if grid_overlay:
				grid_overlay.visible = grid_visible
			print("[ClearingTest] Grid overlay: %s" % ("ON" if grid_visible else "OFF"))


func _raycast_ground(screen_pos: Vector2) -> Vector3:
	if not camera:
		return Vector3.INF

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)

	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin, ray_origin + ray_dir * 500.0
	)
	query.collision_mask = 1

	var result: Dictionary = space.intersect_ray(query)
	if not result.is_empty() and result.has("position"):
		return result["position"] as Vector3

	if ray_dir.y != 0:
		var t: float = -ray_origin.y / ray_dir.y
		if t > 0:
			return ray_origin + ray_dir * t

	return Vector3.INF


func _update_area_preview() -> void:
	if paint_start == Vector3.INF or paint_current == Vector3.INF:
		return

	var min_x: float = minf(paint_start.x, paint_current.x)
	var max_x: float = maxf(paint_start.x, paint_current.x)
	var min_z: float = minf(paint_start.z, paint_current.z)
	var max_z: float = maxf(paint_start.z, paint_current.z)

	var size_x: float = maxf(max_x - min_x, 0.5)
	var size_z: float = maxf(max_z - min_z, 0.5)

	area_preview.position = Vector3((min_x + max_x) * 0.5, 0.5, (min_z + max_z) * 0.5)
	area_preview.scale = Vector3(size_x, 1.0, size_z)


func _create_clear_job(start: Vector3, end: Vector3) -> void:
	var min_corner := Vector3(minf(start.x, end.x), 0, minf(start.z, end.z))
	var max_corner := Vector3(maxf(start.x, end.x), 0, maxf(start.z, end.z))

	var size: Vector3 = max_corner - min_corner
	if size.x < 2.0 or size.z < 2.0:
		print("[ClearingTest] Area too small (min 2x2)")
		return

	print("[ClearingTest] Creating CLEAR job: %.1f x %.1f at %s" % [size.x, size.z, min_corner])

	var job_mgr = get_node_or_null("/root/JobManager")
	if job_mgr:
		var job = job_mgr.create_area_job(
			JobTypes.JobType.CLEAR_TERRAIN,
			min_corner,
			max_corner,
			false
		)
		if job:
			var center := (min_corner + max_corner) * 0.5
			var radius := maxf(size.x, size.z) * 0.5
			job.set_meta("clear_center", center)
			job.set_meta("clear_radius", radius)
			job.set_meta("clear_min", min_corner)
			job.set_meta("clear_max", max_corner)
			print("[ClearingTest] Job #%d created" % job.job_id)


func _on_job_created(job) -> void:
	print("[ClearingTest] JOB CREATED: #%d %s" % [job.job_id, JobTypes.get_job_name(job.job_type)])


func _on_job_completed(job) -> void:
	print("[ClearingTest] JOB COMPLETED: #%d %s" % [job.job_id, JobTypes.get_job_name(job.job_type)])

	# Clear vegetation in the job area
	if job.has_meta("clear_min") and job.has_meta("clear_max"):
		var min_corner: Vector3 = job.get_meta("clear_min")
		var max_corner: Vector3 = job.get_meta("clear_max")
		_clear_vegetation_in_rect(min_corner, max_corner)


func _clear_vegetation_in_rect(min_corner: Vector3, max_corner: Vector3) -> void:
	if not vegetation_manager or not billboard_vegetation:
		return

	var bundle_size: float = vegetation_manager.bundle_meters
	var bundles_per_side: int = int(chunk_size / bundle_size)
	var heightmap_to_use = _get_heightmap_or_mock()

	var total_cleared := 0

	# Check each chunk for affected bundles
	for chunk_coord in VEG_CHUNKS:
		if not vegetation_manager._chunk_terrain.has(chunk_coord):
			continue

		var terrain: PackedByteArray = vegetation_manager._chunk_terrain[chunk_coord]
		var chunk_offset_x: float = chunk_coord.x * chunk_size
		var chunk_offset_z: float = chunk_coord.y * chunk_size
		var cleared := 0

		# Clear bundles in the rectangle
		for bz in bundles_per_side:
			for bx in bundles_per_side:
				var bundle_center_x: float = chunk_offset_x + (bx + 0.5) * bundle_size
				var bundle_center_z: float = chunk_offset_z + (bz + 0.5) * bundle_size

				if bundle_center_x >= min_corner.x and bundle_center_x <= max_corner.x:
					if bundle_center_z >= min_corner.z and bundle_center_z <= max_corner.z:
						var idx: int = bz * bundles_per_side + bx
						if idx < terrain.size() and terrain[idx] != VegetationManager.TerrainType.CLEAR:
							terrain[idx] = VegetationManager.TerrainType.CLEAR
							cleared += 1

		if cleared > 0:
			vegetation_manager._chunk_terrain[chunk_coord] = terrain
			billboard_vegetation.generate_for_chunk(chunk_coord, heightmap_to_use, terrain)
			total_cleared += cleared

	if total_cleared > 0:
		# Force visibility
		_force_billboard_visibility()

		# Rebuild grid overlay to show cleared areas
		_rebuild_grid_overlay()

		print("[ClearingTest] Cleared %d vegetation bundles" % total_cleared)


func _force_billboard_visibility() -> void:
	# Force billboards visible regardless of LOD distance
	if not billboard_vegetation:
		return
	for chunk_coord in VEG_CHUNKS:
		if billboard_vegetation._chunk_billboards.has(chunk_coord):
			var container: Node3D = billboard_vegetation._chunk_billboards[chunk_coord]
			if is_instance_valid(container):
				container.visible = true


func _process(_delta: float) -> void:
	# Force billboards visible (override LOD)
	_force_billboard_visibility()

	_update_hud()


func _update_hud() -> void:
	if not hud:
		return

	var job_mgr = get_node_or_null("/root/JobManager")
	var builder_ai = get_node_or_null("/root/BuilderAI")

	var text := "=== Clearing Test (Billboard Trees) ===\n"
	text += "Workers: %d\n" % workers.size()

	var engineers := 0
	var bulldozers := 0
	for w in workers:
		if w.data and w.data.is_vehicle:
			bulldozers += 1
		else:
			engineers += 1
	text += "  Engineers: %d, Bulldozers: %d\n" % [engineers, bulldozers]

	if builder_ai:
		text += "Auto-mode: %s\n" % ("ON" if builder_ai.auto_mode_enabled else "OFF")
		text += "Registered: %d eng, %d bull\n" % [builder_ai.engineers.size(), builder_ai.bulldozers.size()]

	if job_mgr:
		text += "Active jobs: %d\n" % job_mgr.get_active_job_count()

	# Vegetation stats
	var cleared := _count_clear_bundles()
	var total := _count_total_bundles()
	text += "\nVegetation: %d/%d bundles cleared\n" % [cleared, total]
	text += "Grid overlay: %s (G to toggle)\n" % ("ON" if grid_visible else "OFF")

	# Worker states - match BuilderAI.TaskType enum:
	# IDLE=0, CLEARING=1, BUILDING=2, MOVING=3, WORKING_JOB=4
	if builder_ai:
		text += "\nWorker Tasks:\n"
		for worker in workers:
			if builder_ai.unit_tasks.has(worker):
				var task: Dictionary = builder_ai.unit_tasks[worker]
				var task_type: String = "IDLE"
				if task.has("type"):
					match task["type"]:
						0: task_type = "IDLE"
						1: task_type = "CLEARING"
						2: task_type = "BUILDING"
						3: task_type = "MOVING"
						4: task_type = "WORKING_JOB"
						_: task_type = "UNKNOWN(%d)" % task["type"]
				# Add job info if working on a job
				if task.has("job") and is_instance_valid(task["job"]):
					var job = task["job"]
					task_type += " (Job #%d, %.0f%%)" % [job.job_id, job.get_progress_percent()]
				text += "  %s: %s\n" % [worker.name, task_type]

	if is_painting:
		var size_x: float = absf(paint_current.x - paint_start.x)
		var size_z: float = absf(paint_current.z - paint_start.z)
		text += "\nPainting: %.1f x %.1f m" % [size_x, size_z]

	hud.text = text


func _count_clear_bundles() -> int:
	if not vegetation_manager:
		return 0
	var count := 0
	for chunk_coord in VEG_CHUNKS:
		if vegetation_manager._chunk_terrain.has(chunk_coord):
			var terrain: PackedByteArray = vegetation_manager._chunk_terrain[chunk_coord]
			for t in terrain:
				if t == VegetationManager.TerrainType.CLEAR:
					count += 1
	return count


func _count_total_bundles() -> int:
	if not vegetation_manager:
		return 0
	var count := 0
	for chunk_coord in VEG_CHUNKS:
		if vegetation_manager._chunk_terrain.has(chunk_coord):
			count += vegetation_manager._chunk_terrain[chunk_coord].size()
	return count


## Get terrain height at world position using local terrain (primary) or TerrainIntegration (fallback)
func _get_terrain_height(world_x: float, world_z: float) -> float:
	# Primary: use local terrain (fast, small map)
	if local_terrain and local_terrain.heightmap:
		return local_terrain.heightmap.sample_world(world_x, world_z)
	# Fallback: TerrainIntegration (if loaded from main scene)
	if terrain_intg and terrain_intg.terrain_manager and terrain_intg.terrain_manager.heightmap:
		return terrain_intg.terrain_manager.heightmap.sample_world(world_x, world_z)
	return 0.0


## Get heightmap from local terrain or TerrainIntegration, fallback to mock
func _get_heightmap_or_mock():
	# Primary: local terrain heightmap
	if local_terrain and local_terrain.heightmap:
		return local_terrain.heightmap
	# Fallback: TerrainIntegration
	if terrain_intg and terrain_intg.terrain_manager and terrain_intg.terrain_manager.heightmap:
		return terrain_intg.terrain_manager.heightmap
	return mock_heightmap
