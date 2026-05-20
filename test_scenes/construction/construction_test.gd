extends Node3D
## Construction Test Scene
##
## MIGRATED (2026-05-20): Now uses JobSystem + WorkerController pattern.
## Pattern aligned with clearing_test.gd reference implementation.
##
## Tests the full base-building logistics loop without combat pressure:
## - Engineer squads clear vegetation
## - Bulldozers flatten terrain via EngineeringSystem
## - ConstructionManager queues and tracks builds
## - Firebase perimeter is drawn and buildings placed
## - Supply/reinforcement loop runs end-to-end
## - Building placement with footprint preview
##
## Larger map than the infantry test (600m square) so the whole loop fits.
##
## Controls:
## - B: Open build menu popup
## - Left-click: place building (if in build mode) or firebase center
## - 1: Clear terrain mode, 2: Flatten, 3: Road, 4: Gate placement
## - ESC: Cancel current mode
## - Shift+B: Spawn another bulldozer
## - Shift+E: Spawn another engineer squad
## - R: Rotate placement preview

const TestSceneBase = preload("res://test_scenes/common/test_scene_base.gd")
const Squad = preload("res://battle_system/nodes/squad.gd")
const SquadData = preload("res://battle_system/data/squad_data.gd")

# These exist in the user's existing codebase; we reference them via preload
const Firebase = preload("res://firebase_system/firebase.gd")
# Job system classes (migrated from old BuilderAI)
const UnifiedJob = preload("res://firebase_system/job_system/unified_job.gd")
const PaintableCommand = preload("res://battle_system/ui/paintable_command.gd")
const PaintedAreaPreview = preload("res://battle_system/ui/painted_area_preview.gd")
const RoadDecalRenderer = preload("res://firebase_system/road_decal_renderer.gd")
const BuildingPad = preload("res://firebase_system/building_pad.gd")
const BuildMenuPopup = preload("res://battle_system/ui/build_menu_popup.gd")

## Footprint cell size (must match building_composer.gd)
const FOOTPRINT_CELL_SIZE := 2.0

## Available buildings for placement
var BUILDING_SCENES: Dictionary = {
	"gate_entrance": "res://assets/buildings/composed/gate_entrance.tscn"
}

var hud: Label
# NOTE: builder_ai removed - see JobSystem + WorkerController
var engineers: Array[Node3D] = []
var bulldozers: Array[Node3D] = []
var current_firebase: Node3D = null
var camera: Camera3D = null

## Building placement state
var selected_building: String = ""
var placement_preview: Node3D = null
var footprint_mesh: MeshInstance3D = null
var placement_rotation: float = 0.0
var placed_buildings: Array[Node3D] = []
var placed_footprints: Array = []  # Array of [[x,y], ...] nested arrays

## Ghost preview for building placement
var ghost_preview: MeshInstance3D = null
var ghost_material: StandardMaterial3D = null
var current_building_data: Resource = null  # BuildingData for selected building
const BuildingDataClass = preload("res://firebase_system/building_data.gd")

## Command mode enum
enum CommandMode {
	NONE,           # Normal selection/move mode
	CLEAR_TERRAIN,  # Mark area for vegetation clearing
	FLATTEN_AREA,   # Mark area for bulldozer leveling
	BUILD_ROAD,     # Click points to draw road path
	FILL_CRATER,    # Click crater to fill it
	PLACE_BUILDING  # Select building to place
}

var current_command: CommandMode = CommandMode.NONE
var command_start_pos: Vector3 = Vector3.INF  # Start of drag for area commands
var road_points: Array[Vector3] = []  # Points for road building
var area_preview_mesh: MeshInstance3D = null  # Visual feedback for area selection

## Command panel UI - REMOVED: Now using BattleHUD autoload
## The construction-specific commands are integrated via ConstructionManager signals

## Job system integration
var paint_controller: PaintableCommand = null
var area_preview: PaintedAreaPreview = null
var job_list_label: Label = null  # Shows active jobs in HUD

## Road visuals
var road_visuals: Array[RoadDecalRenderer] = []

## Build menu popup
var build_menu: BuildMenuPopup = null

## Current placement mode from build menu
var current_placement_mode: int = 0  # BuildMenuPopup.PlacementMode
var current_building_spacing: float = 0.0  # For PAINTABLE_SPACED


## Helper to convert placement_rotation to 0-3 rotation steps
func _get_rotation_steps() -> int:
	return int(placement_rotation / (PI / 2.0)) % 4


## Stored for deferred camera setup
var _hq_center: Vector3 = Vector3.ZERO


func _ready() -> void:
	# Position camera BEFORE terrain loads so chunks generate in our play area
	# We want a 50x50 area centered around (25, 0, 25)
	var desired_center := Vector3(25.0, 0.0, 25.0)

	var setup: Dictionary = TestSceneBase.setup_environment(self, {
		"seed": 22222,
		"size": 50.0,
		"name": "Construction Test Scene",
		"camera_position": Vector3(25.0, 200.0, 25.0),  # Directly above center, no offset
	})
	camera = setup.get("camera")

	# Set camera bounds immediately so terrain loads in correct area
	if camera:
		camera.map_bounds_min = Vector3(0.0, 100.0, 0.0)
		camera.map_bounds_max = Vector3(50.0, 400.0, 50.0)

	# Place HQ at center of play area
	var map_center := desired_center

	# Get terrain height at the HQ location
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		var ground_height: float = terrain.get_height_at(map_center)
		map_center.y = ground_height
		print("[ConstructionTest] Terrain height at center: %.1f" % ground_height)

	_hq_center = map_center

	# Clear vegetation around HQ before spawning anything
	if terrain and terrain.has_method("prepare_building_site"):
		terrain.prepare_building_site(_hq_center, Vector2(40.0, 40.0))
		print("[ConstructionTest] Cleared 40m area around HQ")

	# Defer camera positioning to after first frame when terrain is fully ready
	call_deferred("_setup_camera_position")

	# Create starter HQ - cleared area with sandbags, wire, towers
	var hq_data: Dictionary = TestSceneBase.spawn_starter_hq(self, _hq_center, 20.0)
	var spawn_points: Array = hq_data.get("spawn_points", [])

	hud = TestSceneBase.make_hud(self)

	# Create footprint preview mesh
	_create_footprint_mesh()

	# Spawn ONE engineer squad in the clearing
	var eng: Node3D = _make_engineer_squad()
	add_child(eng)
	var eng_pos: Vector3 = spawn_points[0] if spawn_points.size() > 0 else _hq_center + Vector3(-5.0, 0.0, 0.0)
	if terrain and terrain.has_method("get_height_at"):
		eng_pos.y = terrain.get_height_at(eng_pos) + 0.1
	eng.global_position = eng_pos
	engineers.append(eng)

	# Spawn ONE bulldozer in the clearing
	var bulldozer: Node3D = _make_bulldozer()
	add_child(bulldozer)
	var dozer_pos: Vector3 = spawn_points[1] if spawn_points.size() > 1 else _hq_center + Vector3(5.0, 0.0, 0.0)
	if terrain and terrain.has_method("get_height_at"):
		dozer_pos.y = terrain.get_height_at(dozer_pos) + 0.1
	bulldozer.global_position = dozer_pos
	bulldozers.append(bulldozer)

	# NOTE: BuilderAI has been replaced by JobSystem + WorkerController
	# Jobs are created via JobSystem autoload, workers find jobs automatically
	print("[ConstructionTest] Workers will auto-find jobs via WorkerController")

	# NOTE: Using BattleHUD autoload for main UI (selection card + command panel)
	# Construction-specific mode indicator is shown in the HUD label above

	# Create area preview mesh for drag operations
	_create_area_preview_mesh()

	# Create paintable command controller
	paint_controller = PaintableCommand.new()
	paint_controller.name = "PaintController"
	add_child(paint_controller)

	# Connect paint controller signals
	paint_controller.area_painted.connect(_on_area_painted)
	paint_controller.polyline_committed.connect(_on_polyline_committed)
	paint_controller.single_placement.connect(_on_single_placement)
	paint_controller.line_painted.connect(_on_line_painted)
	paint_controller.paint_cancelled.connect(_on_paint_cancelled)
	paint_controller.paint_updated.connect(_on_paint_updated)

	# Create painted area preview
	area_preview = PaintedAreaPreview.new()
	area_preview.name = "AreaPreview"
	add_child(area_preview)

	# Create build menu popup
	_create_build_menu()

	# Verify building scenes exist, create fallbacks for missing ones
	_verify_building_scenes()

	# Connect to JobSystem for status updates (aligned with clearing_test.gd pattern)
	var job_system := get_node_or_null("/root/JobSystem")
	if job_system:
		if job_system.has_signal("job_created"):
			job_system.job_created.connect(_on_job_created)
		if job_system.has_signal("job_completed"):
			job_system.job_completed.connect(_on_job_completed)
		print("[ConstructionTest] Connected to JobSystem")

	print("[ConstructionTest] CONSTRUCTION LOOP TEST")
	print("[ConstructionTest] B = Open build menu, 1-4 = Quick commands")
	print("[ConstructionTest] Shift+E = Spawn engineer, Shift+B = Spawn bulldozer")
	print("[ConstructionTest] Jobs auto-chain: Build on jungle creates Clear -> Flatten -> Build")


func _setup_camera_position() -> void:
	if not camera:
		return

	# Camera above HQ center, looking down - no Z offset
	var cam_pos := Vector3(25.0, _hq_center.y + 60.0, 25.0)

	# Set position instantly (no lerping)
	camera.global_position = cam_pos
	camera.target_position = cam_pos
	camera.current_zoom = cam_pos.y
	camera.rotation_degrees = Vector3(-60.0, 0.0, 0.0)  # More top-down view

	# Update camera bounds based on actual terrain height
	camera.map_bounds_min = Vector3(0.0, _hq_center.y + 20.0, 0.0)
	camera.map_bounds_max = Vector3(50.0, _hq_center.y + 200.0, 50.0)

	print("[ConstructionTest] Camera at %s, HQ at %s" % [cam_pos, _hq_center])


func _make_engineer_squad() -> Node3D:
	var squad: Squad = Squad.new()
	var data := SquadData.new()
	data.display_name = "US Engineer Squad"
	data.faction = 0
	data.squad_size = 6
	data.health_per_soldier = 100.0
	data.attack_range = 20.0
	data.move_speed = 4.5
	data.training_level = 1
	data.max_slope = 0.60
	data.slope_speed_penalty = 0.7
	data.can_build = true
	squad.data = data
	squad.is_player_controlled = true
	squad.primary_weapon = "m16"

	# Add to groups for selection system
	squad.add_to_group("all_units")
	squad.add_to_group("player_units")
	squad.add_to_group("selectable_units")

	return squad


func _make_bulldozer() -> Node3D:
	# A bulldozer is a vehicle that can clear/flatten. Using SquadData with
	# can_build=true and is_vehicle=true. The actual bulldozer model would
	# replace the visual.
	var squad: Squad = Squad.new()
	var data := SquadData.new()
	data.display_name = "M9 ACE Bulldozer"
	data.faction = 0
	data.squad_size = 1
	data.health_per_soldier = 400.0
	data.armor = 15.0
	data.attack_range = 0.0
	data.move_speed = 3.0
	data.max_slope = 0.30  # Bulldozer can't climb steep terrain
	data.slope_speed_penalty = 0.7
	data.can_build = true
	data.is_vehicle = true
	squad.data = data
	squad.is_player_controlled = true

	# Add to groups for selection system
	squad.add_to_group("all_units")
	squad.add_to_group("player_units")
	squad.add_to_group("selectable_units")

	return squad


func _create_footprint_mesh() -> void:
	footprint_mesh = MeshInstance3D.new()
	footprint_mesh.name = "FootprintPreview"
	footprint_mesh.visible = false
	add_child(footprint_mesh)


func _on_command_button_pressed(mode: CommandMode, building_key: String) -> void:
	# Cancel any current operation first
	_cancel_command()

	current_command = mode
	var status_text: String = ""

	# Activate paint controller for appropriate modes
	if paint_controller:
		var job_type := _command_to_job_type(mode)

		match mode:
			CommandMode.CLEAR_TERRAIN:
				paint_controller.activate(PaintableCommand.InputMode.RECT, job_type)
				status_text = "Click + drag area to clear"
			CommandMode.FLATTEN_AREA:
				paint_controller.activate(PaintableCommand.InputMode.RECT, job_type)
				status_text = "Click + drag area to flatten"
			CommandMode.FILL_CRATER:
				paint_controller.activate(PaintableCommand.InputMode.SINGLE, job_type)
				status_text = "Click crater to fill"
			CommandMode.BUILD_ROAD:
				paint_controller.activate(PaintableCommand.InputMode.POLYLINE, job_type)
				road_points.clear()
				status_text = "Click points, ENTER to finish"
			CommandMode.PLACE_BUILDING:
				paint_controller.activate(PaintableCommand.InputMode.SINGLE, job_type)
				if building_key != "":
					_select_building(building_key)
				status_text = "Click to place, R rotate"

	print("[ConstructionTest] %s" % status_text)


func _on_auto_build_toggled(_enabled: bool) -> void:
	# NOTE: Auto-build toggling now handled via WorkerController
	pass


func _cancel_command() -> void:
	var was_active: bool = current_command != CommandMode.NONE

	current_command = CommandMode.NONE
	command_start_pos = Vector3.INF
	road_points.clear()

	# Deactivate paint controller
	if paint_controller:
		paint_controller.deactivate()

	# Hide area preview
	if area_preview:
		area_preview.hide_preview()

	if area_preview_mesh:
		area_preview_mesh.visible = false

	if placement_preview:
		placement_preview.queue_free()
		placement_preview = null

	# Clear ghost preview
	_clear_ghost_preview()

	selected_building = ""
	if footprint_mesh:
		footprint_mesh.visible = false

	print("[ConstructionTest] Ready - Select a command (1-4)")

	if was_active:
		print("[ConstructionTest] Command cancelled")


func _create_area_preview_mesh() -> void:
	area_preview_mesh = MeshInstance3D.new()
	area_preview_mesh.name = "AreaPreview"
	area_preview_mesh.visible = false

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.2, 0.8, 0.2, 0.3)
	area_preview_mesh.material_override = mat

	add_child(area_preview_mesh)


func _create_build_menu() -> void:
	## Create and setup the build menu popup
	build_menu = BuildMenuPopup.new()
	build_menu.name = "BuildMenuPopup"

	# Add to CanvasLayer so it's always on top
	var canvas := CanvasLayer.new()
	canvas.name = "BuildMenuCanvas"
	canvas.layer = 10
	add_child(canvas)
	canvas.add_child(build_menu)

	# Connect signals
	build_menu.building_selected.connect(_on_build_menu_building_selected)
	build_menu.menu_closed.connect(_on_build_menu_closed)


func _on_build_menu_building_selected(building_key: String, placement_mode: int) -> void:
	## Handle building selection from build menu
	print("[ConstructionTest] Build menu selected: %s (mode %d)" % [building_key, placement_mode])

	selected_building = building_key
	current_placement_mode = placement_mode
	current_building_spacing = build_menu.get_building_spacing(building_key)
	placement_rotation = 0.0  # Reset rotation when selecting new building

	# Create ghost preview for all placement modes
	_create_ghost_preview(building_key)

	# Set command mode based on placement mode
	match placement_mode:
		BuildMenuPopup.PlacementMode.SINGLE:
			_on_command_button_pressed(CommandMode.PLACE_BUILDING, building_key)

		BuildMenuPopup.PlacementMode.PAINTABLE:
			# Use LINE mode for paintable buildings (sandbags, trenches)
			current_command = CommandMode.PLACE_BUILDING
			if paint_controller:
				paint_controller.activate(PaintableCommand.InputMode.LINE,
					UnifiedJob.Type.BUILD_STRUCTURE)
			print("[ConstructionTest] Line mode: drag to draw %s wall" % building_key)

		BuildMenuPopup.PlacementMode.PAINTABLE_SPACED:
			# Use RECT mode with spacing for tank traps, wire
			current_command = CommandMode.PLACE_BUILDING
			if paint_controller:
				paint_controller.activate(PaintableCommand.InputMode.RECT,
					UnifiedJob.Type.BUILD_STRUCTURE)
			print("[ConstructionTest] Spaced mode (%.1f units): drag to place %s" % [
				current_building_spacing, building_key])

		BuildMenuPopup.PlacementMode.PAINTABLE_LINE_JITTERED:
			# Use LINE mode with jittered placement (foxholes, defensive positions)
			current_command = CommandMode.PLACE_BUILDING
			if paint_controller:
				paint_controller.activate(PaintableCommand.InputMode.LINE,
					UnifiedJob.Type.BUILD_STRUCTURE)
			print("[ConstructionTest] Jittered line mode: drag to place %s (%.1fm spacing)" % [
				building_key, current_building_spacing])


func _on_build_menu_closed() -> void:
	## Handle build menu being closed without selection
	print("[ConstructionTest] Build menu closed")


## Execute clear terrain command - remove vegetation in area
## Uses unified box selection: both engineers AND bulldozers can clear
func _execute_clear_terrain(center: Vector3, size: Vector2) -> void:
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("prepare_building_site"):
		terrain.prepare_building_site(center, size)
		print("[ConstructionTest] Cleared %.0fx%.0f area at %s" % [size.x, size.y, center])

	# Get selected units from SelectionManager
	var selection_mgr := get_node_or_null("/root/SelectionManager")
	var selected: Array = []
	if selection_mgr and selection_mgr.has_method("get_selected_units"):
		selected = selection_mgr.get_selected_units()

	# Order ALL selected units that can clear (engineers AND bulldozers)
	var assigned_count: int = 0
	for unit in selected:
		if not is_instance_valid(unit):
			continue

		# Check if unit can build/clear
		var can_clear: bool = false
		if unit.has_method("get"):
			var data: Resource = unit.get("data")
			if data and "can_build" in data and data.can_build:
				can_clear = true

		if can_clear:
			# Move unit to clear area - WorkerController will handle job assignment
			if unit.has_method("move_to"):
				unit.move_to(center)
				assigned_count += 1

	if assigned_count > 0:
		print("[ConstructionTest] Assigned %d unit(s) to clear area" % assigned_count)
		# Calculate estimated time based on area and worker count
		var tree_count: float = size.x * size.y * 0.5  # ~0.5 trees per sqm
		var work_rate: float = assigned_count * 0.286  # Engineer rate
		var est_time: float = tree_count / work_rate if work_rate > 0 else 0
		print("[ConstructionTest] Estimated time: %.1f seconds (%d trees)" % [est_time, int(tree_count)])
	else:
		print("[ConstructionTest] No units selected - clearing area marked for later")


## Execute flatten area command - level terrain
func _execute_flatten_area(center: Vector3, size: Vector2) -> void:
	# Get average height in area for target level
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		var target_height: float = terrain.get_height_at(center)
		print("[ConstructionTest] Flatten %.0fx%.0f area at %s (target height: %.1f)" % [
			size.x, size.y, center, target_height])
		print("Flattening %.0fx%.0fm" % [size.x, size.y])

	# Order bulldozers to this area
	_order_units_to_area(center, size, "flatten")


## Execute fill crater command
func _execute_fill_crater(pos: Vector3) -> void:
	print("[ConstructionTest] Fill crater at %s" % pos)
	print("Filling crater...")

	# Order nearest bulldozer to fill
	var nearest_dozer: Node3D = null
	var nearest_dist: float = INF
	for dozer in bulldozers:
		if is_instance_valid(dozer):
			var dist: float = dozer.global_position.distance_to(pos)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_dozer = dozer

	if nearest_dozer and nearest_dozer.has_method("move_to"):
		nearest_dozer.move_to(pos)


## Finish road building command
func _finish_road_command() -> void:
	if road_points.size() < 2:
		print("[ConstructionTest] Need at least 2 points for road")
		return

	print("[ConstructionTest] Build road with %d points" % road_points.size())
	print("Building road (%d segments)" % (road_points.size() - 1))

	# TODO: Actually create road segments
	# For now, just visualize
	_create_road_visual()

	_cancel_command()


## Create visual road segments
func _create_road_visual() -> void:
	for i in range(road_points.size() - 1):
		var p1: Vector3 = road_points[i]
		var p2: Vector3 = road_points[i + 1]

		# Create simple road mesh between points
		var road_seg := MeshInstance3D.new()
		road_seg.name = "RoadSegment_%d" % i

		var length: float = p1.distance_to(p2)
		var box := BoxMesh.new()
		box.size = Vector3(4.0, 0.1, length)
		road_seg.mesh = box

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.32, 0.28)
		road_seg.material_override = mat

		# Position and rotate
		road_seg.global_position = (p1 + p2) * 0.5
		road_seg.global_position.y = _hq_center.y + 0.05
		road_seg.look_at(p2)

		add_child(road_seg)


## Update road preview while building
func _update_road_preview() -> void:
	if road_points.size() < 1:
		return

	# Create/update road preview mesh
	# For simplicity, just print point count
	print("Road: %d points (ENTER to finish)" % road_points.size())


## Order selected units to area for construction work
func _order_units_to_area(center: Vector3, size: Vector2, task: String) -> void:
	# Get selection manager to find selected units
	var selection_mgr := get_node_or_null("/root/SelectionManager")
	if selection_mgr and selection_mgr.has_method("get_selected_units"):
		var selected: Array = selection_mgr.get_selected_units()
		for unit in selected:
			if is_instance_valid(unit):
				# Check if unit can do this task
				var can_do: bool = false
				if unit.has_method("get"):
					var data: Resource = unit.get("data")
					if data and "can_build" in data and data.can_build:
						can_do = true

				if can_do and unit.has_method("move_to"):
					unit.move_to(center)


## Update area preview during drag
func _update_area_preview(current_pos: Vector3) -> void:
	if command_start_pos == Vector3.INF or not area_preview_mesh:
		return

	var min_pos := Vector3(
		minf(command_start_pos.x, current_pos.x),
		_hq_center.y + 0.1,
		minf(command_start_pos.z, current_pos.z)
	)
	var max_pos := Vector3(
		maxf(command_start_pos.x, current_pos.x),
		_hq_center.y + 0.1,
		maxf(command_start_pos.z, current_pos.z)
	)
	var size := max_pos - min_pos
	var center := (min_pos + max_pos) * 0.5

	# Update mesh
	var box := BoxMesh.new()
	box.size = Vector3(size.x, 0.05, size.z)
	area_preview_mesh.mesh = box
	area_preview_mesh.global_position = center

	# Color based on mode
	var mat: StandardMaterial3D = area_preview_mesh.material_override
	if mat:
		match current_command:
			CommandMode.CLEAR_TERRAIN:
				mat.albedo_color = Color(0.3, 0.7, 0.2, 0.35)  # Green
			CommandMode.FLATTEN_AREA:
				mat.albedo_color = Color(0.7, 0.5, 0.2, 0.35)  # Orange


func _select_building(building_key: String) -> void:
	if building_key not in BUILDING_SCENES:
		print("[ConstructionTest] Unknown building: %s" % building_key)
		return

	# Clear previous preview
	if placement_preview:
		placement_preview.queue_free()
		placement_preview = null

	selected_building = building_key
	placement_rotation = 0.0

	# Load building scene for preview
	var scene_path: String = BUILDING_SCENES[building_key]
	var scene: PackedScene = load(scene_path) as PackedScene
	if scene:
		placement_preview = scene.instantiate()
		placement_preview.name = "PlacementPreview"
		# Make it semi-transparent
		_set_preview_transparency(placement_preview, 0.5)
		add_child(placement_preview)
		footprint_mesh.visible = true
		print("[ConstructionTest] Selected: %s. Click to place, R to rotate." % building_key)
	else:
		print("[ConstructionTest] Failed to load: %s" % scene_path)


func _set_preview_transparency(node: Node3D, alpha: float) -> void:
	# Set transparency on all mesh instances
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_inst: MeshInstance3D = child as MeshInstance3D
			if mesh_inst.mesh:
				var material := StandardMaterial3D.new()
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.albedo_color = Color(1, 1, 1, alpha)
				mesh_inst.material_override = material
		if child is Node3D:
			_set_preview_transparency(child as Node3D, alpha)


## Create a ghost preview box for building placement
## Shows a transparent box matching the building's footprint and height
func _create_ghost_preview(building_key: String) -> void:
	# Clear any existing ghost
	_clear_ghost_preview()

	# Get building data from menu entry
	if not build_menu:
		return
	var entry = build_menu.get_building(building_key)
	if not entry:
		print("[ConstructionTest] No entry for: %s" % building_key)
		return

	# Get footprint from BuildingData if we have a valid type
	var footprint_size := Vector2(4.0, 4.0)  # Default
	var building_height := 2.0  # Default

	if entry.building_type >= 0:
		current_building_data = BuildingDataClass.get_building_data(entry.building_type)
		if current_building_data:
			footprint_size = current_building_data.footprint_size
			building_height = current_building_data.height

	# Create ghost mesh
	ghost_preview = MeshInstance3D.new()
	ghost_preview.name = "GhostPreview"

	# Create box mesh for the building outline
	var box := BoxMesh.new()
	box.size = Vector3(footprint_size.x, building_height, footprint_size.y)
	ghost_preview.mesh = box

	# Create transparent material (green = valid placement)
	ghost_material = StandardMaterial3D.new()
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.albedo_color = Color(0.2, 0.8, 0.2, 0.4)  # Green, semi-transparent
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # See both sides
	ghost_preview.material_override = ghost_material

	# Store y offset as metadata (NOT in position.y which gets overwritten by global_position)
	ghost_preview.set_meta("y_offset", building_height * 0.5)

	add_child(ghost_preview)
	print("[ConstructionTest] Ghost preview created for: %s (%.1fx%.1f, h=%.1f)" % [
		building_key, footprint_size.x, footprint_size.y, building_height])


## Clear the ghost preview
func _clear_ghost_preview() -> void:
	if ghost_preview:
		ghost_preview.queue_free()
		ghost_preview = null
	ghost_material = null
	current_building_data = null


## Update ghost preview color based on placement validity
func _update_ghost_color(is_valid: bool) -> void:
	if not ghost_material:
		return
	if is_valid:
		ghost_material.albedo_color = Color(0.2, 0.8, 0.2, 0.4)  # Green
	else:
		ghost_material.albedo_color = Color(0.8, 0.2, 0.2, 0.4)  # Red


func _get_building_footprint_cells(building: Node3D) -> Array:
	"""Get footprint cells from building metadata"""
	if building.has_meta("footprint_cells"):
		return building.get_meta("footprint_cells")
	return []


func _rotate_cell(cell: Array, rotation_steps: int) -> Vector2i:
	"""Rotate a cell by 90-degree increments (0-3)"""
	var x: int = cell[0]
	var z: int = cell[1]
	match rotation_steps % 4:
		1:  # 90 degrees
			return Vector2i(-z, x)
		2:  # 180 degrees
			return Vector2i(-x, -z)
		3:  # 270 degrees
			return Vector2i(z, -x)
		_:  # 0 degrees
			return Vector2i(x, z)


func _get_world_cells(origin: Vector3, cells: Array, rotation_steps: int) -> Array[Vector2i]:
	"""Convert local footprint cells to world grid cells"""
	var world_cells: Array[Vector2i] = []
	var origin_cell := Vector2i(
		int(floorf(origin.x / FOOTPRINT_CELL_SIZE)),
		int(floorf(origin.z / FOOTPRINT_CELL_SIZE))
	)

	for cell in cells:
		var rotated: Vector2i = _rotate_cell(cell, rotation_steps)
		world_cells.append(origin_cell + rotated)

	return world_cells


func _check_footprint_overlap(world_cells: Array[Vector2i]) -> bool:
	"""Check if any cells overlap with existing buildings"""
	for existing_footprint in placed_footprints:
		for existing_cell in existing_footprint:
			var existing_v2i := Vector2i(existing_cell[0], existing_cell[1])
			for new_cell in world_cells:
				if new_cell == existing_v2i:
					return true
	return false


func _update_footprint_preview(position: Vector3, is_valid: bool) -> void:
	"""Update the footprint mesh to show current placement"""
	if not placement_preview:
		footprint_mesh.visible = false
		return

	var cells: Array = _get_building_footprint_cells(placement_preview)
	if cells.is_empty():
		footprint_mesh.visible = false
		return

	var rotation_steps: int = _get_rotation_steps()
	var world_cells: Array[Vector2i] = _get_world_cells(position, cells, rotation_steps)

	# Build mesh from cells
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var color := Color(0, 1, 0, 0.4) if is_valid else Color(1, 0, 0, 0.4)

	for cell in world_cells:
		var x0: float = cell.x * FOOTPRINT_CELL_SIZE
		var z0: float = cell.y * FOOTPRINT_CELL_SIZE
		var x1: float = x0 + FOOTPRINT_CELL_SIZE
		var z1: float = z0 + FOOTPRINT_CELL_SIZE
		var y: float = 0.1  # Slightly above ground

		st.set_color(color)
		# First triangle
		st.add_vertex(Vector3(x0, y, z0))
		st.add_vertex(Vector3(x1, y, z0))
		st.add_vertex(Vector3(x1, y, z1))
		# Second triangle
		st.add_vertex(Vector3(x0, y, z0))
		st.add_vertex(Vector3(x1, y, z1))
		st.add_vertex(Vector3(x0, y, z1))

	footprint_mesh.mesh = st.commit()

	# Create material
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	footprint_mesh.material_override = mat
	footprint_mesh.visible = true


func _place_building(position: Vector3) -> void:
	"""Place the selected building at position"""
	if not placement_preview:
		return

	var cells: Array = _get_building_footprint_cells(placement_preview)
	var rotation_steps: int = _get_rotation_steps()
	var world_cells: Array[Vector2i] = _get_world_cells(position, cells, rotation_steps)

	# Check overlap
	if _check_footprint_overlap(world_cells):
		print("[ConstructionTest] Cannot place - footprint overlaps existing building!")
		return

	# Place the building
	var scene_path: String = BUILDING_SCENES[selected_building]
	var scene: PackedScene = load(scene_path) as PackedScene
	if scene:
		var building: Node3D = scene.instantiate()
		building.global_position = position
		building.rotation.y = placement_rotation
		add_child(building)
		placed_buildings.append(building)

		# Store footprint for collision checking
		var footprint_data: Array = []
		for cell in world_cells:
			footprint_data.append([cell.x, cell.y])
		placed_footprints.append(footprint_data)

		print("[ConstructionTest] Placed %s at %s (rotation: %.0f°)" % [
			selected_building, position, rad_to_deg(placement_rotation)
		])

	# Clear selection after placing
	_cancel_command()


func _input(event: InputEvent) -> void:
	# Handle mouse button events
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_handle_left_click_down(mb.position)
			else:
				_handle_left_click_up(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# Right-click cancels command mode
			if current_command != CommandMode.NONE:
				_cancel_command()

	# Handle key events
	if event is InputEventKey and event.pressed:
		var key_event := event as InputEventKey
		var shift_held: bool = key_event.shift_pressed

		match key_event.keycode:
			KEY_ESCAPE:
				if build_menu and build_menu.visible:
					build_menu.close_menu()
				else:
					_cancel_command()
			KEY_R:
				# Rotate building preview (works for both old placement_preview and new ghost_preview)
				if placement_preview or ghost_preview:
					placement_rotation += PI / 2.0
					if placement_rotation >= TAU:
						placement_rotation = 0.0
					print("[ConstructionTest] Rotation: %.0f°" % rad_to_deg(placement_rotation))
			KEY_B:
				if shift_held:
					_spawn_bulldozer()
				else:
					# Open build menu
					if build_menu:
						if build_menu.visible:
							build_menu.close_menu()
						else:
							var supply_amount: int = 1000
							var sm = get_node_or_null("/root/SupplyManager")
							if sm and sm.has_method("get_global_supply"):
								supply_amount = int(sm.get_global_supply())
							build_menu.open_menu(supply_amount)
			KEY_E:
				if shift_held:
					_spawn_engineer()
			KEY_ENTER, KEY_KP_ENTER:
				# Finish road building
				if current_command == CommandMode.BUILD_ROAD and road_points.size() >= 2:
					_finish_road_command()
			# Quick command keys: 1=Clear, 2=Flatten, 3=Road, 4=Quick build
			KEY_1:
				_on_command_button_pressed(CommandMode.CLEAR_TERRAIN, "")
			KEY_2:
				_on_command_button_pressed(CommandMode.FLATTEN_AREA, "")
			KEY_3:
				_on_command_button_pressed(CommandMode.BUILD_ROAD, "")
			KEY_4:
				_on_command_button_pressed(CommandMode.PLACE_BUILDING, "gate_entrance")
			# Legacy hotkeys for compatibility
			KEY_C:
				if current_command == CommandMode.NONE:
					_on_command_button_pressed(CommandMode.CLEAR_TERRAIN, "")
			KEY_F:
				if current_command == CommandMode.NONE:
					_on_command_button_pressed(CommandMode.FLATTEN_AREA, "")
			KEY_V:
				if current_command == CommandMode.NONE:
					_on_command_button_pressed(CommandMode.FILL_CRATER, "")
			KEY_G:
				if current_command == CommandMode.NONE:
					_on_command_button_pressed(CommandMode.PLACE_BUILDING, "gate_entrance")
			KEY_TAB:
				# Toggle auto-build (now via WorkerController)
				print("[ConstructionTest] Auto-build toggle not implemented yet")


func _handle_left_click_down(screen_pos: Vector2) -> void:
	if not camera:
		return
	var target: Vector3 = _raycast_ground(screen_pos)
	if target == Vector3.INF:
		return

	# Handle based on current command mode
	match current_command:
		CommandMode.CLEAR_TERRAIN, CommandMode.FLATTEN_AREA:
			# Start area selection
			command_start_pos = target
			if area_preview_mesh:
				area_preview_mesh.visible = true

		CommandMode.FILL_CRATER:
			# Immediate action - fill crater at click
			_execute_fill_crater(target)

		CommandMode.BUILD_ROAD:
			# Add point to road path
			road_points.append(target)
			_update_road_preview()

		CommandMode.PLACE_BUILDING:
			# Try to place building
			if placement_preview:
				var cells: Array = _get_building_footprint_cells(placement_preview)
				var rotation_steps: int = _get_rotation_steps()
				var world_cells: Array[Vector2i] = _get_world_cells(target, cells, rotation_steps)
				var is_valid: bool = not _check_footprint_overlap(world_cells)
				if is_valid:
					_place_building(target)
				else:
					print("[ConstructionTest] Invalid placement - overlapping!")

		CommandMode.NONE:
			# Default: place firebase if none exists
			if not current_firebase:
				_place_firebase(target)


func _handle_left_click_up(screen_pos: Vector2) -> void:
	if not camera:
		return

	# Only handle for area selection commands
	if current_command != CommandMode.CLEAR_TERRAIN and current_command != CommandMode.FLATTEN_AREA:
		return

	if command_start_pos == Vector3.INF:
		return

	var target: Vector3 = _raycast_ground(screen_pos)
	if target == Vector3.INF:
		target = command_start_pos

	# Calculate area bounds
	var min_pos := Vector3(
		minf(command_start_pos.x, target.x),
		0,
		minf(command_start_pos.z, target.z)
	)
	var max_pos := Vector3(
		maxf(command_start_pos.x, target.x),
		0,
		maxf(command_start_pos.z, target.z)
	)
	var size := max_pos - min_pos
	var center := (min_pos + max_pos) * 0.5

	# Minimum area size
	if size.x < 5.0 or size.z < 5.0:
		size = Vector3(10.0, 0, 10.0)

	# Execute command
	match current_command:
		CommandMode.CLEAR_TERRAIN:
			_execute_clear_terrain(center, Vector2(size.x, size.z))
		CommandMode.FLATTEN_AREA:
			_execute_flatten_area(center, Vector2(size.x, size.z))

	# Reset
	command_start_pos = Vector3.INF
	if area_preview_mesh:
		area_preview_mesh.visible = false
	_cancel_command()


func _place_firebase(pos: Vector3) -> void:
	current_firebase = Firebase.new()
	current_firebase.name = "Firebase Test"
	add_child(current_firebase)
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		pos.y = terrain.get_height_at(pos)
	current_firebase.global_position = pos
	print("[ConstructionTest] Firebase placed at %s. Engineers will begin clearing." % pos)

	# Auto-issue clearing orders to engineers
	for eng in engineers:
		if is_instance_valid(eng) and eng.has_method("start_clearing"):
			eng.start_clearing(pos, 30.0)


func _spawn_bulldozer() -> void:
	var b: Node3D = _make_bulldozer()
	add_child(b)
	# Spawn near HQ
	var spawn_pos := _hq_center + Vector3(randf_range(-20.0, 20.0), 0.0, randf_range(-20.0, 20.0))
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		spawn_pos.y = terrain.get_height_at(spawn_pos) + 0.1
	b.global_position = spawn_pos
	bulldozers.append(b)
	# Workers auto-register with JobSystem via WorkerController
	print("[ConstructionTest] Spawned bulldozer at %s" % spawn_pos)


func _spawn_engineer() -> void:
	var e: Node3D = _make_engineer_squad()
	add_child(e)
	# Spawn near HQ
	var spawn_pos := _hq_center + Vector3(randf_range(-20.0, 20.0), 0.0, randf_range(-20.0, 20.0))
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		spawn_pos.y = terrain.get_height_at(spawn_pos) + 0.1
	e.global_position = spawn_pos
	engineers.append(e)
	# Workers auto-register with JobSystem via WorkerController
	print("[ConstructionTest] Spawned engineer squad at %s" % spawn_pos)


func _raycast_ground(screen_pos: Vector2) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 2000.0)
	query.collision_mask = 1
	var result: Dictionary = space.intersect_ray(query)
	if not result.is_empty() and result.has("position"):
		return result["position"] as Vector3
	# Fallback: intersect with Y=0 plane if no physics collision
	if ray_dir.y != 0:
		var t: float = -ray_origin.y / ray_dir.y
		if t > 0:
			return ray_origin + ray_dir * t
	return Vector3.INF


func _process(_delta: float) -> void:
	if not camera:
		return

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var target: Vector3 = _raycast_ground(mouse_pos)

	# Update placement preview position
	if placement_preview:
		if target != Vector3.INF:
			placement_preview.global_position = target
			placement_preview.rotation.y = placement_rotation

			# Check validity and update footprint
			var cells: Array = _get_building_footprint_cells(placement_preview)
			var rotation_steps: int = _get_rotation_steps()
			var world_cells: Array[Vector2i] = _get_world_cells(target, cells, rotation_steps)
			var is_valid: bool = not _check_footprint_overlap(world_cells)
			_update_footprint_preview(target, is_valid)

	# Update ghost preview position, rotation, and validity color
	if ghost_preview and target != Vector3.INF:
		# Position ghost at cursor with stored y offset
		var y_offset: float = ghost_preview.get_meta("y_offset", 0.0)
		ghost_preview.global_position = Vector3(target.x, target.y + y_offset, target.z)
		ghost_preview.rotation.y = placement_rotation

		# Check placement validity for ghost color
		var is_valid := true
		if current_building_data:
			var fp_size: Vector2 = current_building_data.footprint_size
			var half_size := Vector3(fp_size.x * 0.5, 0, fp_size.y * 0.5)
			var test_bounds := AABB(target - half_size, half_size * 2.0)

			# Check for overlapping buildings
			for placed in placed_buildings:
				if not is_instance_valid(placed):
					continue
				var placed_pos: Vector3 = placed.global_position
				var dist: float = target.distance_to(placed_pos)
				if dist < (fp_size.x + fp_size.y) * 0.5:  # Rough overlap check
					is_valid = false
					break

			# Check supply affordability
			if is_valid:
				var sm = get_node_or_null("/root/SupplyManager")
				if sm and sm.has_method("can_afford"):
					if not sm.can_afford(current_building_data.supply_cost):
						is_valid = false

		_update_ghost_color(is_valid)

	# Update area preview during drag
	if command_start_pos != Vector3.INF and target != Vector3.INF:
		if current_command == CommandMode.CLEAR_TERRAIN or current_command == CommandMode.FLATTEN_AREA:
			_update_area_preview(target)

	# Update HUD with job info
	_update_hud()


func _update_hud() -> void:
	## Update HUD including job list (aligned with clearing_test.gd pattern)
	if not hud:
		return

	var mode_text: String = ""
	match current_command:
		CommandMode.NONE:
			mode_text = "Ready"
		CommandMode.CLEAR_TERRAIN:
			mode_text = "CLEAR TERRAIN"
		CommandMode.FLATTEN_AREA:
			mode_text = "FLATTEN AREA"
		CommandMode.FILL_CRATER:
			mode_text = "FILL CRATER"
		CommandMode.BUILD_ROAD:
			mode_text = "BUILD ROAD (%d pts)" % road_points.size()
		CommandMode.PLACE_BUILDING:
			mode_text = "PLACE: %s" % selected_building

	# Get active jobs from JobSystem
	var job_system := get_node_or_null("/root/JobSystem")
	var job_count: int = 0
	var pending_count: int = 0

	var lines: PackedStringArray = [
		"=== CONSTRUCTION LOOP TEST ===",
		"Engineers: %d   Bulldozers: %d" % [engineers.size(), bulldozers.size()],
		"Firebase: %s" % ("placed" if current_firebase else "click to place"),
		"Buildings: %d" % placed_buildings.size(),
	]

	# Show job counts and queue details (aligned with clearing_test.gd)
	if job_system:
		var counts: Dictionary = job_system.get_job_counts()
		job_count = counts.ready + counts.in_progress
		pending_count = counts.pending
		lines.append("")
		lines.append("Jobs: %d pending, %d ready, %d in-progress" % [
			counts.pending, counts.ready, counts.in_progress
		])

		# Show job queue details (up to 5 jobs)
		var all_jobs: Array = []
		if job_system.has_method("get") and job_system.get("_ready_jobs"):
			all_jobs.append_array(job_system._ready_jobs)
		if job_system.has_method("get") and job_system.get("_in_progress_jobs"):
			all_jobs.append_array(job_system._in_progress_jobs)

		if all_jobs.size() > 0:
			lines.append("Active Jobs:")
			var shown: int = 0
			for job in all_jobs:
				if not is_instance_valid(job):
					continue
				if shown >= 5:
					lines.append("  ... +%d more" % (all_jobs.size() - 5))
					break
				var type_name: String = UnifiedJob.get_type_name(job.job_type)
				var progress: float = job.work_done / job.work_required if job.work_required > 0 else 0.0
				var workers_count: int = job.assigned_workers.size()
				var state: String = "RDY" if job.state == UnifiedJob.State.READY else "WRK"
				lines.append("  [%s] %s: %.0f%% (%d workers)" % [
					state, type_name, progress * 100, workers_count
				])
				shown += 1

		# Show pending jobs count
		if pending_count > 0:
			lines.append("Pending: %d (waiting for prerequisites)" % pending_count)

	lines.append("")
	lines.append("Mode: %s" % mode_text)
	lines.append("")

	# Worker status section (aligned with clearing_test.gd)
	lines.append("Worker Status:")
	for eng in engineers:
		if is_instance_valid(eng):
			var status: String = _get_worker_status(eng)
			lines.append("  %s: %s" % [eng.data.display_name if eng.data else eng.name, status])
	for dozer in bulldozers:
		if is_instance_valid(dozer):
			var status: String = _get_worker_status(dozer)
			lines.append("  %s: %s" % [dozer.data.display_name if dozer.data else dozer.name, status])

	lines.append("")
	lines.append("CONTROLS:")
	lines.append("  B = Build menu | 1-4 = Quick commands")
	lines.append("  Shift+E/B = Spawn units | R = Rotate")
	lines.append("  Right-click = Cancel mode")

	hud.text = "\n".join(lines)


## Get worker status string (aligned with clearing_test.gd pattern)
func _get_worker_status(worker: Node3D) -> String:
	if not is_instance_valid(worker):
		return "INVALID"

	# Check WorkerController for status
	if worker.has_method("get_worker_controller"):
		var wc: Node = worker.get_worker_controller()
		if wc and wc.has_method("get_status_string"):
			return wc.get_status_string()

	# Fallback: check for common state properties
	if "current_job" in worker and worker.current_job:
		return "WORKING"
	if "is_moving" in worker and worker.is_moving:
		return "MOVING"
	return "IDLE"


## =============================================================================
## JOB SYSTEM INTEGRATION
## =============================================================================

## Handle job creation notification (aligned with clearing_test.gd)
func _on_job_created(job) -> void:
	print("[ConstructionTest] JOB CREATED: #%d %s at %v" % [
		job.job_id, UnifiedJob.get_type_name(job.job_type), job.center
	])


## Handle job completion notification (aligned with clearing_test.gd)
func _on_job_completed(job) -> void:
	print("[ConstructionTest] JOB COMPLETED: #%d %s" % [
		job.job_id, UnifiedJob.get_type_name(job.job_type)
	])
	# Building jobs trigger actual building placement via _on_build_job_completed
	if job.job_type == UnifiedJob.Type.BUILD_STRUCTURE:
		_on_build_job_completed(job)


func _verify_building_scenes() -> void:
	## Check building scenes exist, create fallbacks for missing
	for key in BUILDING_SCENES:
		var path: String = BUILDING_SCENES[key]
		if not ResourceLoader.exists(path):
			print("[ConstructionTest] Building scene not found: %s - will use placeholder" % path)
			# Create a placeholder cube scene path
			BUILDING_SCENES[key] = ""  # Mark as using placeholder


func _on_area_painted(min_corner: Vector3, max_corner: Vector3) -> void:
	"""Handle area paint completion - create job"""
	var job_system := get_node_or_null("/root/JobSystem")
	if not job_system:
		push_error("[ConstructionTest] JobSystem not found")
		return

	var center: Vector3 = (min_corner + max_corner) * 0.5
	var size: Vector2 = Vector2(absf(max_corner.x - min_corner.x), absf(max_corner.z - min_corner.z))
	var job: UnifiedJob = null

	match current_command:
		CommandMode.CLEAR_TERRAIN:
			job = job_system.create_job(UnifiedJob.Type.CLEAR_TERRAIN, center, size)
		CommandMode.FLATTEN_AREA:
			job = job_system.create_job(UnifiedJob.Type.FLATTEN_AREA, center, size)

	if job:
		print("[ConstructionTest] Created %s job #%d" % [
			UnifiedJob.get_type_name(job.job_type), job.job_id
		])

	# Stay in same mode for quick successive operations
	print("Job created - drag again or ESC to exit")


func _on_polyline_committed(points: PackedVector3Array) -> void:
	"""Handle road polyline completion - create job"""
	if points.size() < 2:
		return

	var job_system := get_node_or_null("/root/JobSystem")
	if not job_system:
		return

	# Calculate road center and approximate size
	var center: Vector3 = Vector3.ZERO
	for p in points:
		center += p
	center /= points.size()
	var size := Vector2(10.0, 10.0)  # Approximate road area

	var job: UnifiedJob = job_system.create_job(UnifiedJob.Type.BUILD_ROAD, center, size)

	if job:
		job.metadata["path_points"] = points

		# Create road visual connected to job
		var road_visual := RoadDecalRenderer.create_for_job(job)
		add_child(road_visual)
		road_visuals.append(road_visual)

		print("[ConstructionTest] Created road job #%d with %d points" % [
			job.job_id, points.size()
		])

	road_points.clear()
	_cancel_command()


func _on_single_placement(position: Vector3) -> void:
	"""Handle single-click placement"""
	match current_command:
		CommandMode.FILL_CRATER:
			_create_fill_job(position)

		CommandMode.PLACE_BUILDING:
			_create_build_job(position)


func _on_line_painted(start_pos: Vector3, end_pos: Vector3) -> void:
	"""Handle line paint completion - place building segments along line"""
	if current_command != CommandMode.PLACE_BUILDING:
		return

	if selected_building.is_empty():
		return

	# Calculate line direction and length
	var line_vec: Vector3 = end_pos - start_pos
	line_vec.y = 0  # Keep horizontal
	var length: float = line_vec.length()
	if length < 0.5:
		return

	var direction: Vector3 = line_vec.normalized()

	# Get segment size based on building type
	var segment_size: float = 2.0  # Default sandbag segment size
	if current_placement_mode == BuildMenuPopup.PlacementMode.PAINTABLE_SPACED:
		segment_size = current_building_spacing
	elif current_placement_mode == BuildMenuPopup.PlacementMode.PAINTABLE_LINE_JITTERED:
		segment_size = current_building_spacing if current_building_spacing > 0 else 4.0
	else:
		# For seamless walls, use building footprint size
		segment_size = 2.0  # Sandbag wall segment

	# Calculate number of segments
	var num_segments: int = maxi(1, int(length / segment_size))

	# Place segments along the line
	var segments_placed: int = 0
	for i in range(num_segments):
		var t: float = (float(i) + 0.5) / float(num_segments)
		var pos: Vector3 = start_pos.lerp(end_pos, t)

		# Get terrain height at position
		var terrain := get_node_or_null("/root/TerrainIntegration")
		if terrain and terrain.has_method("get_height_at"):
			pos.y = terrain.get_height_at(pos)

		# Calculate rotation to face along the line
		var rot: float = atan2(direction.x, direction.z)

		# Apply jitter for PAINTABLE_LINE_JITTERED mode (foxholes, defensive positions)
		if current_placement_mode == BuildMenuPopup.PlacementMode.PAINTABLE_LINE_JITTERED:
			# Jitter perpendicular to line direction
			var perp := Vector3(-direction.z, 0, direction.x)
			var lateral_jitter := randf_range(-1.5, 1.5)  # +/- 1.5m off the line
			var along_jitter := randf_range(-0.4, 0.4)    # +/- 0.4m along line
			pos += perp * lateral_jitter + direction * along_jitter
			# Randomize rotation slightly - foxholes don't all face the same way
			rot += randf_range(-0.4, 0.4)
			# Re-sample terrain height at jittered position
			if terrain and terrain.has_method("get_height_at"):
				pos.y = terrain.get_height_at(pos)

		# Create build job for this segment
		_create_wall_segment_job(pos, rot, selected_building)
		segments_placed += 1

	print("[ConstructionTest] Placed %d %s segments along %.1fm line" % [
		segments_placed, selected_building, length])

	# Stay in LINE mode for continued wall building
	print("Wall placed - drag again or ESC to exit")


func _create_wall_segment_job(position: Vector3, rotation: float, building_key: String) -> void:
	"""Create a build job for a single wall segment"""
	# Check and consume supply before creating job
	if current_building_data:
		var sm = get_node_or_null("/root/SupplyManager")
		if sm and sm.has_method("consume_global_supply"):
			if not sm.consume_global_supply(current_building_data.supply_cost):
				print("[ConstructionTest] Cannot afford %s segment" % building_key)
				return

	var job_system := get_node_or_null("/root/JobSystem")
	if not job_system:
		return

	# Create build job at position
	var job: UnifiedJob = job_system.create_job(
		UnifiedJob.Type.BUILD_STRUCTURE,
		position,
		Vector2(2.0, 2.0)  # Wall segment size
	)

	if job:
		# Store building info in job metadata
		job.metadata["rotation"] = rotation
		job.metadata["building_key"] = building_key


func _on_paint_cancelled() -> void:
	"""Handle paint cancellation"""
	if area_preview:
		area_preview.hide_preview()
	_cancel_command()


func _on_paint_updated(current_pos: Vector3) -> void:
	"""Handle paint preview update"""
	if not area_preview:
		return

	var job_type: UnifiedJob.Type = _command_to_job_type(current_command)

	match current_command:
		CommandMode.CLEAR_TERRAIN, CommandMode.FLATTEN_AREA:
			if paint_controller.is_painting and paint_controller.drag_start != Vector3.INF:
				var rect: Rect2 = paint_controller.get_drag_rect()
				area_preview.show_area(rect, job_type, true)
			else:
				area_preview.show_single(current_pos, job_type, true)

		CommandMode.BUILD_ROAD:
			var preview_points := paint_controller.get_polyline_preview()
			if preview_points.size() > 0:
				area_preview.show_polyline(preview_points, job_type, true)
			else:
				area_preview.show_single(current_pos, job_type, true)

		CommandMode.FILL_CRATER:
			area_preview.show_single(current_pos, job_type, true)

		CommandMode.PLACE_BUILDING:
			# Check if we're in LINE mode (for paintable walls)
			if paint_controller.input_mode == PaintableCommand.InputMode.LINE:
				var line_pts := paint_controller.get_line_preview()
				if line_pts.size() >= 2:
					# Show line preview with wall segments
					area_preview.show_wall_line(line_pts[0], line_pts[1], job_type,
						current_building_spacing if current_building_spacing > 0 else 2.0, true)
				else:
					area_preview.show_single(current_pos, job_type, true)
			else:
				area_preview.show_single(current_pos, job_type, true)


func _command_to_job_type(cmd: CommandMode) -> UnifiedJob.Type:
	"""Convert command mode to job type"""
	match cmd:
		CommandMode.CLEAR_TERRAIN:
			return UnifiedJob.Type.CLEAR_TERRAIN
		CommandMode.FLATTEN_AREA:
			return UnifiedJob.Type.FLATTEN_AREA
		CommandMode.BUILD_ROAD:
			return UnifiedJob.Type.BUILD_ROAD
		CommandMode.FILL_CRATER:
			return UnifiedJob.Type.FILL_CRATER
		CommandMode.PLACE_BUILDING:
			return UnifiedJob.Type.BUILD_STRUCTURE
		_:
			return UnifiedJob.Type.CLEAR_TERRAIN


func _create_fill_job(position: Vector3) -> void:
	"""Create a fill crater job"""
	var job_system := get_node_or_null("/root/JobSystem")
	if not job_system:
		return

	var job: UnifiedJob = job_system.create_job(
		UnifiedJob.Type.FILL_CRATER,
		position,
		Vector2(5.0, 5.0)  # Crater fill area
	)

	if job:
		print("[ConstructionTest] Created fill job #%d at %s" % [job.job_id, position])

	print("[ConstructionTest] Created fill crater job at %s" % position)
	_cancel_command()


func _create_build_job(position: Vector3) -> void:
	"""Create a building job with auto-prerequisite chain"""
	if selected_building.is_empty():
		return

	# Check and consume supply before creating job
	if current_building_data:
		var sm = get_node_or_null("/root/SupplyManager")
		if sm and sm.has_method("consume_global_supply"):
			if not sm.consume_global_supply(current_building_data.supply_cost):
				print("[ConstructionTest] Cannot afford %s (cost: %d)" % [
					selected_building, current_building_data.supply_cost])
				return

	var job_system := get_node_or_null("/root/JobSystem")
	if not job_system:
		return

	# Get footprint size from building data or use default
	var footprint_size := Vector2(4.0, 4.0)
	if current_building_data and current_building_data.footprint_size:
		footprint_size = current_building_data.footprint_size
	elif placement_preview and placement_preview.has_meta("footprint_size"):
		footprint_size = placement_preview.get_meta("footprint_size")

	# Create build job
	var job: UnifiedJob = job_system.create_job(
		UnifiedJob.Type.BUILD_STRUCTURE,
		position,
		footprint_size
	)

	if job:
		# Store building info in job metadata
		job.metadata["building_key"] = selected_building
		job.metadata["rotation"] = placement_rotation
		job.metadata["footprint_size"] = footprint_size

		print("[ConstructionTest] Created build job #%d" % job.job_id)

	_cancel_command()


func _on_build_job_completed(job: UnifiedJob) -> void:
	"""Handle build job completion - actually place the building"""
	var building_key: String = job.metadata.get("building_key", "")
	var rotation: float = job.metadata.get("rotation", 0.0)
	var position: Vector3 = job.center

	# Get terrain height
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		position.y = terrain.get_height_at(position)

	# Create building pad
	var footprint_size := Vector2(4.0, 4.0)
	if job.metadata.has("footprint_size"):
		footprint_size = job.metadata["footprint_size"]

	var pad: BuildingPad = BuildingPad.create_for_building(footprint_size, position, rotation)
	add_child(pad)

	# Place building on pad
	var building: Node3D = _create_building(building_key, position, rotation)
	if building:
		building.global_position.y = pad.get_building_height()
		placed_buildings.append(building)

	print("[ConstructionTest] Building placed: %s at %s" % [building_key, position])


func _create_building(building_key: String, position: Vector3, rotation: float) -> Node3D:
	"""Create a building instance (with placeholder fallback)"""
	var building: Node3D = null
	var scene_path: String = BUILDING_SCENES.get(building_key, "")

	if scene_path != "" and ResourceLoader.exists(scene_path):
		var scene: PackedScene = load(scene_path)
		if scene:
			building = scene.instantiate()
	else:
		# Create placeholder cube
		building = _create_placeholder_building(building_key)

	if building:
		building.global_position = position
		building.rotation.y = rotation
		add_child(building)

	return building


func _create_placeholder_building(building_key: String) -> Node3D:
	"""Create a placeholder cube for missing building assets"""
	var placeholder := Node3D.new()
	placeholder.name = "Placeholder_" + building_key

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "PlaceholderMesh"

	var box := BoxMesh.new()
	box.size = Vector3(4.0, 2.5, 4.0)
	mesh_instance.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.55, 0.45)  # Tan placeholder color
	mesh_instance.material_override = mat
	mesh_instance.position.y = 1.25

	placeholder.add_child(mesh_instance)

	# Add label
	var label := Label3D.new()
	label.text = building_key.to_upper()
	label.font_size = 24
	label.position.y = 3.0
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	placeholder.add_child(label)

	# Store footprint metadata
	placeholder.set_meta("footprint_cells", [[0, 0], [1, 0], [0, 1], [1, 1]])
	placeholder.set_meta("footprint_size", Vector2(4.0, 4.0))

	return placeholder
