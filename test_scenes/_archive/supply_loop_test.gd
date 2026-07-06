extends Node3D

## Supply Loop Test Scene - GAME READY VERSION
## Demonstrates Pillar 3: Physical Supply Chains
##
## This test scene proves:
## 1. Truck supply convoy loops between rear depot and firebase
## 2. CH-47 Chinook helicopter supply runs with actual flight
## 3. Infantry squads consume supply, triggering resupply
## 4. Road network with visual waypoints and damage system
## 5. Supply depot levels track correctly
## 6. Multiple trucks in convoy formation
##
## Controls:
## - B: Start bulldozer road construction (required before trucks can move)
## - T: Dispatch truck convoy manually
## - H: Request CH-47 Chinook supply run
## - D: Damage random road segment (slows trucks)
## - R: Repair all roads
## - V: Toggle spline debug visualizer
## - C: Add truck to convoy
## - 1-4: Set supply consumption rate
## - Tab: Cycle camera focus
## - F/G: Cycle through squads (select)
## - Right Click: Move selected squad to position
## - Left Click on road: Damage that road segment
## - Esc: Reset test state

const TestSceneBase = preload("res://test_scenes/common/test_scene_base.gd")
const SupplyDepotScene = preload("res://game/scenes/buildings/supply_depot.tscn")
const FirebaseClass = preload("res://firebase_system/firebase.gd")
const TreeNodeScript = preload("res://terrain/vegetation/tree_node.gd")
# TerrainSpline, TerrainSplineVisualizer, and RoadDecalRenderer have class_name declarations
# so they are globally available - no preload needed

# Model paths
const M35_TRUCK_MODEL := "res://assets/models/vehicles/m35_deuce_truck.glb"
const CH47_CHINOOK_MODEL := "res://assets/models/helicopters/ch47_chinook.glb"
const UH1_HUEY_MODEL := "res://assets/models/vehicles/uh1_huey.glb"

# Map setup - matching clearing_test.gd pattern
const MAP_SIZE := 400.0
var map_center: float = MAP_SIZE * 0.5  # 200.0

# Positions are calculated relative to map_center
# Rear depot on west side, firebase on east side, within map bounds
var REAR_DEPOT_POS: Vector3
var FIREBASE_POS: Vector3
var CHINOOK_WAITING_POS: Vector3  # Chinook hover position when idle

# Supply parameters
const REAR_DEPOT_CAPACITY := 999999.0
const FIREBASE_DEPOT_CAPACITY := 2000.0
const INITIAL_FIREBASE_SUPPLY := 400.0  # Start low to trigger resupply
const TRUCK_SUPPLY_AMOUNT := 500.0
const HELI_SUPPLY_AMOUNT := 800.0  # Chinook carries more than Huey

# Consumption
const CONSUMPTION_RATES := [1.0, 5.0, 10.0, 20.0]
var _consumption_rate_index: int = 1
var _consumption_timer: float = 0.0

# Camera
var camera: Camera3D
var _camera_targets: Array[Node3D] = []
var _camera_target_index: int = 0

# Systems
var _supply_trucks: Array[Node3D] = []  # Convoy of trucks
var _rear_depot: Node3D
var _firebase_depot: Node3D
var _firebase: Node3D
var _firebase_node: Node3D = null  # Firebase class with influence circle
var _rear_helipad: Node3D
var _firebase_helipad: Node3D
var _chinook: Node3D  # CH-47 Chinook helicopter

# Road
var _road_waypoints: Array[Vector3] = []
var _waypoint_markers: Array[Node3D] = []
var _road_spline: RefCounted = null  # TerrainSpline for smooth road curves
var _return_spline: RefCounted = null  # Reverse spline for return trip
var _spline_visualizer: Node3D = null
var _road_decal: Node3D = null
var _damaged_segments: Dictionary = {}  # segment_idx -> damage_level (0.0-1.0)

# Units
var _test_squads: Array[Node3D] = []

# HUD
var _hud_label: Label
var _depot_labels: Dictionary = {}

# State
var _convoy_state: String = "IDLE"  # IDLE, LOADING, EN_ROUTE, UNLOADING, RETURNING
var _chinook_state: String = "WAITING"  # WAITING, FLYING_TO_DEPOT, LOADING, FLYING_TO_LZ, UNLOADING, RETURNING
var _chinook_cargo: float = 0.0
var _chinook_rotor_speed: float = 0.0
const CHINOOK_ROTOR_MAX_SPEED := 15.0
const CHINOOK_CRUISE_ALTITUDE := 40.0
const CHINOOK_SPEED := 35.0  # m/s (~125 km/h)

# Bulldozer and road construction
var _bulldozer: Node3D = null
var _road_construction_state: String = "NOT_STARTED"  # NOT_STARTED, BUILDING, COMPLETE
var _road_construction_progress: float = 0.0
var _road_segments_cleared: int = 0

# Jungle along road route (for bulldozer to clear)
var _jungle_container: Node3D
var _jungle_trees: Array[Node3D] = []
const JUNGLE_WIDTH := 10.0  # Width of jungle strip on each side of road
const TREE_SPACING := 4.0  # Meters between trees


func _ready() -> void:
	# Initialize positions based on map_center (like clearing_test.gd)
	# Rear depot on west side, firebase on east-center
	REAR_DEPOT_POS = Vector3(map_center - 150.0, 0.0, map_center)  # West side
	FIREBASE_POS = Vector3(map_center + 80.0, 0.0, map_center + 30.0)  # East-center
	CHINOOK_WAITING_POS = Vector3(map_center - 180.0, CHINOOK_CRUISE_ALTITUDE, map_center - 40.0)  # Behind rear depot

	# DEFERRED SETUP: Allow first frame to render before heavy terrain generation
	# This prevents the scene from freezing during synchronous terrain init
	call_deferred("_deferred_setup")

	print("=== Supply Loop Test - GAME READY (Pillar 3) ===")


func _deferred_setup() -> void:
	## Heavy initialization deferred to prevent freeze on scene load
	# Setup environment (terrain generation)
	var setup: Dictionary = TestSceneBase.setup_environment(self, {
		"seed": 77777,
		"size": MAP_SIZE,
		"name": "Supply Loop Test",
		"camera_position": Vector3(map_center, 80.0, map_center + 100.0),
	})
	camera = setup.get("camera")

	# Query terrain height for base positions AFTER terrain is generated
	var terrain: Node = get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		REAR_DEPOT_POS.y = terrain.get_height_at(REAR_DEPOT_POS)
		FIREBASE_POS.y = terrain.get_height_at(FIREBASE_POS)
		# Chinook waiting position needs terrain height + cruise altitude
		var chinook_terrain_y: float = terrain.get_height_at(CHINOOK_WAITING_POS)
		CHINOOK_WAITING_POS.y = chinook_terrain_y + CHINOOK_CRUISE_ALTITUDE
		print("[SupplyTest] Adjusted base heights - Rear: %.1f, Firebase: %.1f, Chinook: %.1f" % [
			REAR_DEPOT_POS.y, FIREBASE_POS.y, CHINOOK_WAITING_POS.y])
	else:
		push_warning("[SupplyTest] TerrainIntegration not found - bases may be underground")

	# Create all test elements
	_create_road_network()
	# Spawn local jungle trees along road route for bulldozer to clear
	# Note: VegetationManager may also spawn trees, but these are explicit test trees
	_spawn_jungle_along_route()
	_create_rear_supply_point()
	_create_forward_firebase()
	_create_bulldozer()  # Bulldozer for road construction
	_create_supply_convoy()  # Creates convoy of trucks (waiting for road)
	_create_chinook_helicopter()  # CH-47 with real model
	_spawn_test_squads()
	_create_debug_hud()
	_register_depots_for_auto_roads()  # Enable automatic bulldozer road building

	# Setup camera targets - add first truck and chinook
	_camera_targets = [_rear_depot, _firebase]
	if not _supply_trucks.is_empty():
		_camera_targets.append(_supply_trucks[0])
	if _chinook:
		_camera_targets.append(_chinook)
	print("")
	print("TEST FLOW:")
	print("1. Press B - Bulldozer clears jungle for supply road")
	print("2. Trucks auto-dispatch when road is complete")
	print("3. Use F/G to select squads, Right-Click to move them")
	print("4. Move squads INTO the GREEN circle to receive resupply")
	print("5. Watch 10%% supply squads refill as trucks deliver!")
	print("")
	print("SUPPLY INFLUENCE: %.0fm radius around firebase (GREEN circle)" % FIREBASE_INFLUENCE_RADIUS)
	print("Units OUTSIDE the circle will NOT receive supply!")
	print("")
	print("B: BUILD ROAD | T: Convoy | H: Chinook | F/G: Select | Right-Click: Move")
	print("D/Click: Damage road | R: Repair | Tab: Focus | V: Spline viz")


func _process(delta: float) -> void:
	_simulate_supply_consumption(delta)
	_update_bulldozer_construction(delta)
	_update_convoy_loop(delta)
	_update_chinook_loop(delta)
	_update_hud()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_B:
				_start_road_construction()
			KEY_T:
				_manual_dispatch_convoy()
			KEY_H:
				_request_chinook_supply()
			KEY_U:
				_damage_random_road()
			KEY_R:
				_repair_all_roads()
			KEY_C:
				_add_truck_to_convoy()
			KEY_1:
				_consumption_rate_index = 0
			KEY_2:
				_consumption_rate_index = 1
			KEY_3:
				_consumption_rate_index = 2
			KEY_4:
				_consumption_rate_index = 3
			KEY_TAB:
				_cycle_camera_focus()
			KEY_V:
				_toggle_spline_visualizer()
			KEY_ESCAPE:
				_reset_test_state()

	# Left-click to damage road segment at click position
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_damage_road_at_click(event.position)

	# Right-click to move selected squad
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_move_squad_to_click(event.position)

	# F/G to cycle through squads
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			_cycle_squad_selection(-1)  # Previous
		elif event.keycode == KEY_G:
			_cycle_squad_selection(1)   # Next


# ============================================================================
# ROAD NETWORK
# ============================================================================

func _create_road_network() -> void:
	"""Setup road waypoints and splines - road visual created by bulldozer"""
	# Road waypoints between rear depot (west) and firebase (east)
	# All coordinates centered on map_center
	_road_waypoints = [
		REAR_DEPOT_POS + Vector3(20, 0, 0),
		Vector3(map_center - 100, 0, map_center + 15),
		Vector3(map_center - 50, 0, map_center + 25),
		Vector3(map_center, 0, map_center + 20),
		Vector3(map_center + 40, 0, map_center + 25),
		FIREBASE_POS + Vector3(-20, 0, 0),
	]

	# Get terrain reference for height sampling
	var terrain: Node = get_node_or_null("/root/TerrainIntegration")

	# Create TerrainSpline for smooth curves (trucks need this for movement)
	_road_spline = TerrainSpline.new()
	if terrain:
		_road_spline.set_terrain(terrain)
	_road_spline.set_waypoints(_road_waypoints)

	# Create return spline (reverse waypoints)
	var reverse_waypoints: Array[Vector3] = []
	for i in range(_road_waypoints.size() - 1, -1, -1):
		reverse_waypoints.append(_road_waypoints[i])
	_return_spline = TerrainSpline.new()
	if terrain:
		_return_spline.set_terrain(terrain)
	_return_spline.set_waypoints(reverse_waypoints)

	# Log spline info
	print("[SupplyTest] Road spline created: %.1fm length, max slope %.1f°" % [
		_road_spline.get_total_length(),
		_road_spline.get_max_slope_degrees()
	])

	# Check passability
	if not _road_spline.is_passable(30.0):
		push_warning("[SupplyTest] Road has slopes > 30° - may be impassable!")

	# Create roads container (road decal will be added when bulldozer completes)
	var roads_container := Node3D.new()
	roads_container.name = "Roads"
	add_child(roads_container)

	# NO ROAD DECAL - bulldozer will build the road
	# _road_decal = RoadDecalRenderer.create_for_spline(_road_spline, 4.0)
	# roads_container.add_child(_road_decal)
	print("[SupplyTest] Road decal NOT created - bulldozer must clear and build!")

	# Create spline visualizer for debug (shows planned route)
	_spline_visualizer = TerrainSplineVisualizer.create(_road_spline)
	_spline_visualizer.name = "SplineDebugViz"
	_spline_visualizer.visible = true  # Toggle with V key - shows where road WILL go
	roads_container.add_child(_spline_visualizer)

	# Create waypoint markers (show where bulldozer needs to go)
	var waypoints_container := Node3D.new()
	waypoints_container.name = "DebugWaypoints"
	roads_container.add_child(waypoints_container)

	for i in _road_waypoints.size():
		var marker := _create_waypoint_marker(i, _road_waypoints[i])
		waypoints_container.add_child(marker)
		_waypoint_markers.append(marker)


func _create_waypoint_marker(index: int, pos: Vector3) -> Node3D:
	"""Create numbered pole at waypoint"""
	var marker := Node3D.new()
	marker.name = "Waypoint_%d" % index
	marker.position = pos

	# Pole
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.15
	cyl.height = 4.0
	pole.mesh = cyl
	pole.position.y = 2.0

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.7, 0.1)  # Yellow
	pole.material_override = mat
	marker.add_child(pole)

	# Number label
	var label := Label3D.new()
	label.text = str(index)
	label.position.y = 4.5
	label.font_size = 64
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color.BLACK
	marker.add_child(label)

	return marker


func _spawn_jungle_along_route() -> void:
	"""Spawn dense jungle trees along the road route for bulldozer to clear.

	Uses actual 3D jungle models (jungle_light, jungle_medium, jungle_heavy GLBs)
	via TreeNode for proper visual fidelity.
	"""
	_jungle_container = Node3D.new()
	_jungle_container.name = "JungleTrees"
	add_child(_jungle_container)

	var terrain: Node = get_node_or_null("/root/TerrainIntegration")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77777  # Consistent tree placement

	# Tree types for variety - use actual 3D jungle models
	var tree_types: Array = [
		TreeNodeScript.TreeType.JUNGLE_LIGHT,
		TreeNodeScript.TreeType.JUNGLE_MEDIUM,
		TreeNodeScript.TreeType.JUNGLE_HEAVY,
	]

	# Spawn trees along each road segment
	for i in range(_road_waypoints.size() - 1):
		var start: Vector3 = _road_waypoints[i]
		var end: Vector3 = _road_waypoints[i + 1]
		var segment_dir: Vector3 = (end - start).normalized()
		var segment_length: float = start.distance_to(end)
		var perpendicular: Vector3 = Vector3(-segment_dir.z, 0, segment_dir.x)

		# Place trees along segment
		var distance: float = 0.0
		while distance < segment_length:
			var base_pos: Vector3 = start + segment_dir * distance

			# Place trees on both sides of road
			for side in [-1, 1]:
				# Random offset from road center
				var offset_dist: float = rng.randf_range(3.0, JUNGLE_WIDTH)
				var tree_pos: Vector3 = base_pos + perpendicular * offset_dist * side
				tree_pos.x += rng.randf_range(-2.0, 2.0)
				tree_pos.z += rng.randf_range(-2.0, 2.0)

				# Get terrain height
				if terrain and terrain.has_method("get_height_at"):
					tree_pos.y = terrain.get_height_at(tree_pos)

				# Choose random tree type (weighted toward medium/heavy for jungle feel)
				var type_roll: float = rng.randf()
				var tree_type: int
				if type_roll < 0.2:
					tree_type = tree_types[0]  # JUNGLE_LIGHT (20%)
				elif type_roll < 0.5:
					tree_type = tree_types[1]  # JUNGLE_MEDIUM (30%)
				else:
					tree_type = tree_types[2]  # JUNGLE_HEAVY (50%)

				# Random tree height
				var height: float = rng.randf_range(6.0, 14.0)

				# Create actual 3D jungle tree using TreeNode
				var tree: Node = TreeNodeScript.create(tree_type, tree_pos, height)
				if tree:
					_jungle_container.add_child(tree)
					_jungle_trees.append(tree)

			distance += TREE_SPACING + rng.randf_range(-1.0, 1.0)

	print("[SupplyTest] Spawned %d jungle trees using 3D models along road route" % _jungle_trees.size())


func _create_simple_tree(pos: Vector3, trunk_mat: Material, leaf_mat: Material, rng: RandomNumberGenerator) -> Node3D:
	"""Create a simple tree mesh for visual jungle"""
	var tree := Node3D.new()
	tree.name = "JungleTree"
	tree.position = pos

	# Random scale
	var scale_factor: float = rng.randf_range(0.8, 1.4)
	var height: float = rng.randf_range(6.0, 12.0) * scale_factor

	# Trunk
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.15 * scale_factor
	trunk_mesh.bottom_radius = 0.25 * scale_factor
	trunk_mesh.height = height * 0.6
	trunk.mesh = trunk_mesh
	trunk.material_override = trunk_mat
	trunk.position.y = height * 0.3
	tree.add_child(trunk)

	# Foliage (cone shape)
	var foliage := MeshInstance3D.new()
	var foliage_mesh := CylinderMesh.new()  # Cone approximation
	foliage_mesh.top_radius = 0.0
	foliage_mesh.bottom_radius = 2.5 * scale_factor
	foliage_mesh.height = height * 0.6
	foliage.mesh = foliage_mesh
	foliage.material_override = leaf_mat
	foliage.position.y = height * 0.7
	tree.add_child(foliage)

	# Random rotation
	tree.rotation.y = rng.randf() * TAU

	return tree


func _clear_trees_near_position(pos: Vector3, radius: float) -> int:
	"""Remove jungle trees within radius of position, returns count removed"""
	var removed: int = 0
	var to_remove: Array[Node3D] = []

	for tree in _jungle_trees:
		if not is_instance_valid(tree):
			continue
		var dist: float = tree.global_position.distance_to(pos)
		if dist < radius:
			to_remove.append(tree)

	for tree in to_remove:
		_jungle_trees.erase(tree)
		tree.queue_free()
		removed += 1

	return removed


func _damage_random_road() -> void:
	"""Damage a random road segment (visual + speed penalty)"""
	if _waypoint_markers.is_empty():
		return

	# Damage a segment (between waypoints)
	var segment_idx: int = randi() % (_waypoint_markers.size() - 1)

	# Add or increase damage
	var current_damage: float = _damaged_segments.get(segment_idx, 0.0)
	current_damage = minf(current_damage + 0.5, 1.0)
	_damaged_segments[segment_idx] = current_damage

	# Turn markers red to indicate damage
	var marker: Node3D = _waypoint_markers[segment_idx]
	var pole: MeshInstance3D = marker.get_node_or_null("MeshInstance3D")
	if pole and pole.material_override:
		# Color based on damage level: yellow -> orange -> red
		var color := Color(0.9, 0.7 - current_damage * 0.5, 0.1)
		pole.material_override.albedo_color = color

	var speed_reduction: int = int(current_damage * 70)
	print("[SupplyTest] Road damaged at segment %d (-%d%% speed)" % [segment_idx, speed_reduction])


func _repair_all_roads() -> void:
	"""Repair all road segments (restore yellow color and speed)"""
	_damaged_segments.clear()

	for marker in _waypoint_markers:
		var pole: MeshInstance3D = marker.get_node_or_null("MeshInstance3D")
		if pole and pole.material_override:
			pole.material_override.albedo_color = Color(0.9, 0.7, 0.1)

	print("[SupplyTest] All roads repaired - convoy speed restored")


func _try_damage_road_at_click(screen_pos: Vector2) -> void:
	"""Raycast from click position to damage road if hit"""
	if not camera:
		return

	# Raycast from camera
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var to: Vector3 = from + camera.project_ray_normal(screen_pos) * 1000.0

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return

	var hit_pos: Vector3 = result.position

	# Find nearest road segment to click
	var nearest_segment: int = -1
	var nearest_dist: float = 30.0  # Max distance from road to register click

	for i in range(_road_waypoints.size() - 1):
		var seg_start: Vector3 = _road_waypoints[i]
		var seg_end: Vector3 = _road_waypoints[i + 1]

		# Calculate distance from point to line segment
		var segment: Vector3 = seg_end - seg_start
		var t: float = clampf((hit_pos - seg_start).dot(segment) / segment.length_squared(), 0.0, 1.0)
		var closest_point: Vector3 = seg_start + t * segment
		var dist: float = hit_pos.distance_to(closest_point)

		if dist < nearest_dist:
			nearest_dist = dist
			nearest_segment = i

	if nearest_segment >= 0:
		_damage_road_segment(nearest_segment)


func _damage_road_segment(segment_idx: int) -> void:
	"""Damage a specific road segment"""
	if segment_idx < 0 or segment_idx >= _waypoint_markers.size() - 1:
		return

	# Add or increase damage
	var current_damage: float = _damaged_segments.get(segment_idx, 0.0)
	current_damage = minf(current_damage + 0.5, 1.0)
	_damaged_segments[segment_idx] = current_damage

	# Turn markers red to indicate damage
	var marker: Node3D = _waypoint_markers[segment_idx]
	var pole: MeshInstance3D = marker.get_node_or_null("MeshInstance3D")
	if pole and pole.material_override:
		# Color based on damage level: yellow -> orange -> red
		var color := Color(0.9, 0.7 - current_damage * 0.5, 0.1)
		pole.material_override.albedo_color = color

	var speed_reduction: int = int(current_damage * 70)
	print("[SupplyTest] Road segment %d damaged by click (-%d%% speed)" % [segment_idx, speed_reduction])


# ============================================================================
# REAR SUPPLY POINT
# ============================================================================

func _create_rear_supply_point() -> void:
	"""Create rear supply depot at map edge"""
	var rear_base := Node3D.new()
	rear_base.name = "RearSupplyPoint"
	rear_base.position = REAR_DEPOT_POS
	add_child(rear_base)

	# Visual depot building
	var depot_visual := _create_depot_visual(Color(0.2, 0.5, 0.2))
	rear_base.add_child(depot_visual)

	# Supply storage (simple script-based tracking)
	_rear_depot = rear_base
	_rear_depot.set_meta("supply_current", REAR_DEPOT_CAPACITY)
	_rear_depot.set_meta("supply_max", REAR_DEPOT_CAPACITY)
	_rear_depot.set_meta("name", "Rear Depot")

	# Helipad
	_rear_helipad = _create_helipad(Vector3(15, 0, 0))
	_rear_helipad.name = "RearHelipad"
	rear_base.add_child(_rear_helipad)

	_camera_targets.append(_rear_depot)
	print("[SupplyTest] Rear supply point created at %s" % REAR_DEPOT_POS)


func _create_depot_visual(color: Color) -> Node3D:
	"""Create visual representation of supply depot"""
	var depot := Node3D.new()
	depot.name = "DepotVisual"

	# Main building
	var building := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(12, 4, 8)
	building.mesh = box
	building.position.y = 2.0

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	building.material_override = mat
	depot.add_child(building)

	# Supply crates stacked
	for i in 3:
		var crate := MeshInstance3D.new()
		var crate_box := BoxMesh.new()
		crate_box.size = Vector3(2, 1.5, 2)
		crate.mesh = crate_box
		crate.position = Vector3(-4 + i * 3, 0.75, 6)

		var crate_mat := StandardMaterial3D.new()
		crate_mat.albedo_color = Color(0.5, 0.45, 0.3)
		crate.material_override = crate_mat
		depot.add_child(crate)

	return depot


func _create_helipad(offset: Vector3) -> Node3D:
	"""Create helipad visual"""
	var helipad := Node3D.new()
	helipad.position = offset

	# Pad surface
	var pad := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(15, 15)
	pad.mesh = plane
	pad.position.y = 0.05

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.3)
	pad.material_override = mat
	helipad.add_child(pad)

	# H marking (simple box)
	var h_mark := MeshInstance3D.new()
	var h_box := BoxMesh.new()
	h_box.size = Vector3(6, 0.1, 1)
	h_mark.mesh = h_box
	h_mark.position.y = 0.1

	var h_mat := StandardMaterial3D.new()
	h_mat.albedo_color = Color(0.9, 0.9, 0.9)
	h_mark.material_override = h_mat
	helipad.add_child(h_mark)

	return helipad


# ============================================================================
# FORWARD FIREBASE
# ============================================================================

const FIREBASE_INFLUENCE_RADIUS := 168.0  # TOC supply influence radius (168m)


func _create_forward_firebase() -> void:
	"""Create pre-built firebase with TOC, depot, helipad, and SUPPLY INFLUENCE CIRCLE"""
	var firebase := Node3D.new()
	firebase.name = "ForwardFirebase"
	firebase.position = FIREBASE_POS
	add_child(firebase)
	_firebase = firebase

	# Perimeter (sandbags around edge)
	_create_firebase_perimeter(firebase)

	# TOC (HQ building) - THE SUPPLY INFLUENCE SOURCE
	var toc := _create_toc_visual()
	toc.position = Vector3(0, 0, -15)
	firebase.add_child(toc)

	# Create Firebase influence zone visualization (the green circle)
	# This shows the area where units can receive supply
	_create_influence_circle(firebase)

	# Supply Depot
	var depot_visual := _create_depot_visual(Color(0.5, 0.4, 0.2))
	depot_visual.position = Vector3(15, 0, 0)
	firebase.add_child(depot_visual)

	_firebase_depot = Node3D.new()
	_firebase_depot.name = "FirebaseDepot"
	_firebase_depot.position = Vector3(15, 0, 0)
	_firebase_depot.set_meta("supply_current", INITIAL_FIREBASE_SUPPLY)
	_firebase_depot.set_meta("supply_max", FIREBASE_DEPOT_CAPACITY)
	_firebase_depot.set_meta("name", "Firebase Depot")
	firebase.add_child(_firebase_depot)

	# Helipad
	_firebase_helipad = _create_helipad(Vector3(-15, 0, 10))
	_firebase_helipad.name = "FirebaseHelipad"
	firebase.add_child(_firebase_helipad)

	print("[SupplyTest] Firebase created at %s with %.0fm supply influence radius" % [
		FIREBASE_POS, FIREBASE_INFLUENCE_RADIUS
	])
	print("[SupplyTest] Units within the GREEN CIRCLE receive supply from depot (%.0f/%.0f)" % [
		INITIAL_FIREBASE_SUPPLY, FIREBASE_DEPOT_CAPACITY
	])


func _register_depots_for_auto_roads() -> void:
	"""Register supply depots with SupplyChainManager for automatic road building.

	When two depots are registered, SupplyChainManager automatically creates
	BUILD_ROAD jobs between them, which the bulldozer's WorkerController picks up.
	"""
	var supply_chain_manager: Node = get_node_or_null("/root/SupplyChainManager")
	if not supply_chain_manager:
		push_warning("[SupplyTest] SupplyChainManager not found - auto roads disabled")
		return

	if not supply_chain_manager.has_method("manually_register_depot"):
		push_warning("[SupplyTest] SupplyChainManager missing manually_register_depot method")
		return

	# Register rear depot first (becomes main base)
	if _rear_depot:
		# Mark as Supply Depot type for SupplyChainManager
		_rear_depot.set_meta("building_type", 18)  # BuildingData.BuildingType.SUPPLY_DEPOT
		supply_chain_manager.manually_register_depot(_rear_depot)
		print("[SupplyTest] Registered rear depot for auto-road building")

	# Register firebase depot second (triggers road building to main base)
	if _firebase_depot:
		_firebase_depot.set_meta("building_type", 18)  # BuildingData.BuildingType.SUPPLY_DEPOT
		supply_chain_manager.manually_register_depot(_firebase_depot)
		print("[SupplyTest] Registered firebase depot - BUILD_ROAD jobs should be created")


func _create_influence_circle(parent: Node3D) -> void:
	"""Create visible supply influence circle (units inside this get resupplied)"""
	var influence_mesh := MeshInstance3D.new()
	influence_mesh.name = "SupplyInfluenceZone"

	# Create dashed circle mesh
	var mesh := _create_dashed_circle_mesh(FIREBASE_INFLUENCE_RADIUS, 64)
	influence_mesh.mesh = mesh
	influence_mesh.position.y = 0.3  # Slightly above terrain

	# Green material for supply zone (always visible in this test)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.85, 0.4, 0.6)  # Bright green, semi-transparent
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	influence_mesh.material_override = mat

	parent.add_child(influence_mesh)


func _create_dashed_circle_mesh(radius: float, segments: int = 64) -> ArrayMesh:
	"""Create a thick dashed circle mesh for visibility"""
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var line_width: float = 2.5  # Thick visible line
	var inner_r: float = radius - line_width
	var outer_r: float = radius

	for i in range(segments):
		# Only draw every other segment (dashed effect)
		if i % 2 == 0:
			var angle1: float = TAU * float(i) / float(segments)
			var angle2: float = TAU * float(i + 1) / float(segments)

			# Inner edge vertices
			var inner1 := Vector3(cos(angle1) * inner_r, 0, sin(angle1) * inner_r)
			var inner2 := Vector3(cos(angle2) * inner_r, 0, sin(angle2) * inner_r)

			# Outer edge vertices
			var outer1 := Vector3(cos(angle1) * outer_r, 0, sin(angle1) * outer_r)
			var outer2 := Vector3(cos(angle2) * outer_r, 0, sin(angle2) * outer_r)

			# Triangle 1
			st.add_vertex(inner1)
			st.add_vertex(outer1)
			st.add_vertex(inner2)

			# Triangle 2
			st.add_vertex(inner2)
			st.add_vertex(outer1)
			st.add_vertex(outer2)

	return st.commit()


func _create_firebase_perimeter(parent: Node3D) -> void:
	"""Create sandbag perimeter around firebase"""
	var radius: float = 35.0
	var segments: int = 12

	for i in segments:
		var angle: float = float(i) / segments * TAU
		var pos := Vector3(cos(angle) * radius, 0, sin(angle) * radius)

		var sandbag := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(6, 1.2, 1.5)
		sandbag.mesh = box
		sandbag.position = pos
		sandbag.position.y = 0.6
		sandbag.rotation.y = angle + PI * 0.5

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.50, 0.35)
		sandbag.material_override = mat
		parent.add_child(sandbag)


func _create_toc_visual() -> Node3D:
	"""Create TOC (Tactical Operations Center) building"""
	var toc := Node3D.new()
	toc.name = "TOC"

	# Main bunker
	var bunker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(10, 3, 8)
	bunker.mesh = box
	bunker.position.y = 1.5

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.38, 0.32)
	bunker.material_override = mat
	toc.add_child(bunker)

	# Antenna
	var antenna := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.1
	cyl.height = 8.0
	antenna.mesh = cyl
	antenna.position = Vector3(3, 7, 0)

	var ant_mat := StandardMaterial3D.new()
	ant_mat.albedo_color = Color(0.3, 0.3, 0.3)
	antenna.material_override = ant_mat
	toc.add_child(antenna)

	return toc


# ============================================================================
# BULLDOZER ROAD CONSTRUCTION
# ============================================================================

func _create_bulldozer() -> void:
	"""Create D7 bulldozer for road construction"""
	# Check if Bulldozer class exists
	if not ClassDB.class_exists("Bulldozer") and not ResourceLoader.exists("res://battle_system/units/bulldozer.gd"):
		push_warning("[SupplyTest] Bulldozer script not found - using placeholder")
		_create_placeholder_bulldozer()
		return

	# Load bulldozer script and create instance
	var BulldozerScript: GDScript = load("res://battle_system/units/bulldozer.gd")
	if not BulldozerScript:
		push_warning("[SupplyTest] Could not load Bulldozer script")
		_create_placeholder_bulldozer()
		return

	_bulldozer = BulldozerScript.new()
	_bulldozer.name = "D7_Bulldozer"
	# Position bulldozer ON THE ROAD PATH, slightly ahead of first waypoint
	# This ensures it's on the same terrain as the road (not in a valley)
	var first_waypoint: Vector3 = _road_waypoints[0] if not _road_waypoints.is_empty() else REAR_DEPOT_POS
	var second_waypoint: Vector3 = _road_waypoints[1] if _road_waypoints.size() > 1 else first_waypoint + Vector3(20, 0, 0)
	var road_direction: Vector3 = (second_waypoint - first_waypoint).normalized()
	# Spawn 10m along the road from first waypoint (on the road path, away from depot)
	_bulldozer.position = first_waypoint + road_direction * 10.0
	_bulldozer.faction = 0  # US_ARMY
	_bulldozer.allow_direct_commands = true  # Enable direct cut_path() for test scene
	add_child(_bulldozer)

	# Snap to terrain
	var terrain: Node = get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		_bulldozer.position.y = terrain.get_height_at(_bulldozer.position)

	# Add to camera targets
	_camera_targets.append(_bulldozer)

	print("[SupplyTest] D7 Bulldozer created - press B to start road construction")


func _create_placeholder_bulldozer() -> void:
	"""Create placeholder bulldozer visual"""
	_bulldozer = Node3D.new()
	_bulldozer.name = "D7_Bulldozer"
	# Position ON THE ROAD PATH, 10m along from first waypoint
	var first_waypoint: Vector3 = _road_waypoints[0] if not _road_waypoints.is_empty() else REAR_DEPOT_POS
	var second_waypoint: Vector3 = _road_waypoints[1] if _road_waypoints.size() > 1 else first_waypoint + Vector3(20, 0, 0)
	var road_direction: Vector3 = (second_waypoint - first_waypoint).normalized()
	_bulldozer.position = first_waypoint + road_direction * 10.0
	add_child(_bulldozer)

	# Hull
	var hull := MeshInstance3D.new()
	var hull_mesh := BoxMesh.new()
	hull_mesh.size = Vector3(3.0, 1.5, 4.0)
	hull.mesh = hull_mesh
	hull.position.y = 0.75

	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.85, 0.7, 0.2)  # CAT yellow
	hull.material_override = hull_mat
	_bulldozer.add_child(hull)

	# Blade
	var blade := MeshInstance3D.new()
	blade.name = "Blade"
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(4.0, 1.2, 0.3)
	blade.mesh = blade_mesh
	blade.position = Vector3(0, 0.6, 2.2)

	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.3, 0.3, 0.3)
	blade.material_override = blade_mat
	_bulldozer.add_child(blade)

	# Snap to terrain
	var terrain: Node = get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		_bulldozer.position.y = terrain.get_height_at(_bulldozer.position)

	# Store blade reference for animation
	_bulldozer.set_meta("blade", blade)
	_bulldozer.set_meta("blade_down", false)

	_camera_targets.append(_bulldozer)
	print("[SupplyTest] Placeholder bulldozer created")


func _start_road_construction() -> void:
	"""Start bulldozer road construction"""
	if _road_construction_state == "COMPLETE":
		print("[SupplyTest] Road already built!")
		return

	if _road_construction_state == "BUILDING":
		print("[SupplyTest] Road construction already in progress...")
		return

	_road_construction_state = "BUILDING"
	_road_construction_progress = 0.0
	_road_segments_cleared = 0

	# Lower blade
	if _bulldozer.has_meta("blade"):
		var blade: Node3D = _bulldozer.get_meta("blade")
		if blade:
			var tween: Tween = create_tween()
			tween.tween_property(blade, "position:y", 0.2, 0.5)
	elif _bulldozer.has_method("cut_path"):
		# Real bulldozer - use its cut_path method
		var waypoints: Array[Vector3] = []
		for wp in _road_waypoints:
			waypoints.append(wp)
		_bulldozer.cut_path(waypoints)

	print("[SupplyTest] BULLDOZER STARTED - Clearing jungle for supply route...")
	print("[SupplyTest] Watch the terrain clear as the bulldozer cuts the road!")


func _update_bulldozer_construction(delta: float) -> void:
	"""Update bulldozer road construction progress"""
	if _road_construction_state != "BUILDING":
		return

	if not is_instance_valid(_bulldozer):
		return

	# Real bulldozer handles its own movement - don't fight it
	# Just monitor for completion
	if _bulldozer.has_method("is_clearing"):
		# Check if bulldozer finished its path
		if not _bulldozer.is_clearing() and _bulldozer.state == _bulldozer.State.IDLE:
			_road_construction_state = "COMPLETE"
			_road_construction_progress = 1.0
			# Create road decal
			var roads_container: Node3D = get_node_or_null("Roads")
			if roads_container and not _road_decal:
				_road_decal = RoadDecalRenderer.create_for_spline(_road_spline, 4.0)
				_road_decal.name = "RoadDecal"
				roads_container.add_child(_road_decal)
				print("[SupplyTest] Road decal created - supply route is now visible!")
			print("[SupplyTest] ROAD CONSTRUCTION COMPLETE! Trucks can now use the supply route.")
		return  # Let real bulldozer handle movement

	# Calculate construction progress (placeholder bulldozer only)
	var total_distance: float = 0.0
	for i in range(_road_waypoints.size() - 1):
		total_distance += _road_waypoints[i].distance_to(_road_waypoints[i + 1])

	var target_segment: int = _road_segments_cleared
	if target_segment >= _road_waypoints.size() - 1:
		# Construction complete
		_road_construction_state = "COMPLETE"
		_road_construction_progress = 1.0

		# Raise blade
		if _bulldozer.has_meta("blade"):
			var blade: Node3D = _bulldozer.get_meta("blade")
			if blade:
				var tween: Tween = create_tween()
				tween.tween_property(blade, "position:y", 0.6, 0.5)

		# CREATE THE ROAD DECAL NOW - bulldozer cleared the path
		var roads_container: Node3D = get_node_or_null("Roads")
		if roads_container and not _road_decal:
			_road_decal = RoadDecalRenderer.create_for_spline(_road_spline, 4.0)
			_road_decal.name = "RoadDecal"
			roads_container.add_child(_road_decal)
			print("[SupplyTest] Road decal created - supply route is now visible!")

		print("[SupplyTest] ROAD CONSTRUCTION COMPLETE! Trucks can now use the supply route.")
		return

	# Move bulldozer toward current target
	var target_pos: Vector3 = _road_waypoints[target_segment + 1]
	var terrain: Node = get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		target_pos.y = terrain.get_height_at(target_pos)

	var direction: Vector3 = (target_pos - _bulldozer.position).normalized()
	var distance: float = _bulldozer.position.distance_to(target_pos)

	var bulldozer_speed: float = 6.0  # m/s

	if distance > 3.0:
		# Move toward target
		_bulldozer.position += direction * bulldozer_speed * delta

		# Face direction
		var look_dir := Vector3(direction.x, 0, direction.z)
		if look_dir.length() > 0.1:
			_bulldozer.rotation.y = atan2(look_dir.x, look_dir.z)

		# Snap to terrain
		if terrain and terrain.has_method("get_height_at"):
			_bulldozer.position.y = terrain.get_height_at(_bulldozer.position)

		# Clear vegetation as we go (via TerrainClearingSystem)
		var clearing_system: Node = get_node_or_null("/root/TerrainClearingSystem")
		if clearing_system and clearing_system.has_method("apply_clearing_damage"):
			clearing_system.apply_clearing_damage(_bulldozer.position, 6.0, delta * 2.0)

		# Clear local jungle trees as bulldozer passes
		var trees_cleared: int = _clear_trees_near_position(_bulldozer.position, 8.0)
		if trees_cleared > 0:
			print("[SupplyTest] Bulldozer cleared %d trees" % trees_cleared)
	else:
		# Reached segment target
		_road_segments_cleared += 1
		_road_construction_progress = float(_road_segments_cleared) / float(_road_waypoints.size() - 1)
		print("[SupplyTest] Road segment %d cleared (%.0f%% complete)" % [
			_road_segments_cleared, _road_construction_progress * 100
		])


# ============================================================================
# SUPPLY CONVOY (Multiple M35 Trucks)
# ============================================================================

func _create_supply_convoy() -> void:
	"""Create convoy of M35 supply trucks with real models"""
	# Start with 2 trucks
	for i in 2:
		_spawn_truck(i)

	# Convoy waits for road to be built
	_convoy_state = "WAITING_FOR_ROAD"
	print("[SupplyTest] Supply convoy created with %d trucks - WAITING for road construction (press B)" % _supply_trucks.size())


func _spawn_truck(convoy_index: int) -> Node3D:
	"""Spawn a single M35 truck with real model or fallback"""
	var truck := Node3D.new()
	truck.name = "SupplyTruck_%d" % convoy_index

	# Position trucks INSIDE the depot (parked formation)
	# They'll drive out when road construction completes
	var offset := Vector3(-4 + convoy_index * 4, 0, 2)  # Side-by-side inside depot
	truck.position = REAR_DEPOT_POS + offset
	add_child(truck)

	# Try to load real M35 model
	var model_scene: PackedScene = load(M35_TRUCK_MODEL)
	if model_scene:
		var model: Node3D = model_scene.instantiate()
		model.name = "M35Model"
		# Scale if needed (adjust based on actual model size)
		model.scale = Vector3(1.0, 1.0, 1.0)
		truck.add_child(model)
		print("[SupplyTest] Loaded M35 model for truck %d" % convoy_index)
	else:
		# Fallback to placeholder geometry
		_create_placeholder_truck(truck)
		print("[SupplyTest] Using placeholder for truck %d (model not found)" % convoy_index)

	# Initialize truck state - wait for road to be built
	truck.set_meta("state", "WAITING_FOR_ROAD")
	truck.set_meta("cargo", 0.0)
	truck.set_meta("spline_distance", 0.0)
	truck.set_meta("returning", false)
	truck.set_meta("convoy_index", convoy_index)
	truck.set_meta("base_speed", 12.0)  # m/s base speed (20% slower for realistic pacing)

	_supply_trucks.append(truck)
	return truck


func _create_placeholder_truck(truck: Node3D) -> void:
	"""Fallback placeholder truck geometry"""
	# Body
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.5, 2.0, 6.0)
	body.mesh = box
	body.position.y = 1.5

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.4, 0.3)  # OD green
	body.material_override = mat
	truck.add_child(body)

	# Cab
	var cab := MeshInstance3D.new()
	var cab_box := BoxMesh.new()
	cab_box.size = Vector3(2.3, 1.5, 2.0)
	cab.mesh = cab_box
	cab.position = Vector3(0, 2.75, -2)
	cab.material_override = mat
	truck.add_child(cab)

	# Wheels
	var wheel_positions: Array[Vector3] = [
		Vector3(-1.3, 0.5, -2), Vector3(1.3, 0.5, -2),
		Vector3(-1.3, 0.5, 1), Vector3(1.3, 0.5, 1),
		Vector3(-1.3, 0.5, 2.5), Vector3(1.3, 0.5, 2.5),
	]

	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.15, 0.15, 0.15)

	for wpos in wheel_positions:
		var wheel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.5
		cyl.bottom_radius = 0.5
		cyl.height = 0.4
		wheel.mesh = cyl
		wheel.position = wpos
		wheel.rotation.z = PI * 0.5
		wheel.material_override = wheel_mat
		truck.add_child(wheel)


func _add_truck_to_convoy() -> void:
	"""Add another truck to the convoy"""
	if _supply_trucks.size() >= 6:
		print("[SupplyTest] Convoy at max capacity (6 trucks)")
		return

	var new_truck := _spawn_truck(_supply_trucks.size() - 1)  # Already added in _spawn_truck

	# If convoy is at depot, position new truck there too
	if _convoy_state == "LOADING" or _convoy_state == "IDLE":
		var idx: int = new_truck.get_meta("convoy_index", 0)
		new_truck.position = REAR_DEPOT_POS + Vector3(0, 0, 10 + idx * 12)

	print("[SupplyTest] Added truck to convoy (now %d trucks)" % _supply_trucks.size())


func _update_convoy_loop(delta: float) -> void:
	"""Update all trucks in convoy along spline route"""
	if _supply_trucks.is_empty():
		return

	# Update each truck with convoy spacing
	for i in _supply_trucks.size():
		var truck: Node3D = _supply_trucks[i]
		if not is_instance_valid(truck):
			continue
		_update_single_truck(truck, delta, i)

	# Update overall convoy state based on lead truck
	if not _supply_trucks.is_empty() and is_instance_valid(_supply_trucks[0]):
		_convoy_state = _supply_trucks[0].get_meta("state", "IDLE")


func _update_single_truck(truck: Node3D, delta: float, convoy_index: int) -> void:
	"""Update a single truck's movement"""
	var state: String = truck.get_meta("state", "IDLE")
	var cargo: float = truck.get_meta("cargo", 0.0)
	var spline_dist: float = truck.get_meta("spline_distance", 0.0)
	var returning: bool = truck.get_meta("returning", false)
	var base_speed: float = truck.get_meta("base_speed", 12.0)

	match state:
		"WAITING_FOR_ROAD":
			# Trucks wait inside depot until road construction is complete
			if _road_construction_state == "COMPLETE":
				state = "LOADING"
				truck.set_meta("state", state)
				print("[SupplyTest] Truck %d: Road complete, beginning loading..." % convoy_index)

		"LOADING":
			# Load cargo over time
			cargo += 100.0 * delta
			if cargo >= TRUCK_SUPPLY_AMOUNT:
				cargo = TRUCK_SUPPLY_AMOUNT
				state = "EN_ROUTE"
				# Stagger convoy start based on index
				spline_dist = -convoy_index * 12.0  # Negative to delay start
				returning = false
			truck.set_meta("cargo", cargo)
			truck.set_meta("state", state)
			truck.set_meta("spline_distance", spline_dist)

		"EN_ROUTE":
			var spline: RefCounted = _return_spline if returning else _road_spline
			if not spline:
				return

			var spline_length: float = spline.get_total_length()

			# Wait for convoy spacing
			if spline_dist < 0:
				spline_dist += base_speed * delta
				truck.set_meta("spline_distance", spline_dist)
				return

			if spline_dist < spline_length:
				# Calculate speed based on road damage
				var speed: float = _get_truck_speed_at_distance(spline_dist, base_speed, spline_length)
				spline_dist += speed * delta

				# Get position and tangent from spline
				var new_pos: Vector3 = spline.get_position_at_distance(spline_dist)
				var tangent: Vector3 = spline.get_tangent_at_distance(spline_dist)

				# Update truck position
				truck.position = new_pos

				# Rotate to face tangent direction
				if tangent.length_squared() > 0.001:
					truck.rotation.y = atan2(tangent.x, tangent.z)

				truck.set_meta("spline_distance", spline_dist)
			else:
				# Reached destination
				if returning:
					state = "LOADING"
					truck.position = REAR_DEPOT_POS + Vector3(0, 0, 10 + convoy_index * 12)
				else:
					state = "UNLOADING"
					truck.position = FIREBASE_POS + Vector3(-25 - convoy_index * 8, 0, 0)
				spline_dist = 0.0
				truck.set_meta("state", state)
				truck.set_meta("spline_distance", spline_dist)

		"UNLOADING":
			var unload_amount: float = 100.0 * delta
			cargo -= unload_amount

			# Add to firebase depot
			var fb_supply: float = _firebase_depot.get_meta("supply_current", 0.0)
			var fb_max: float = _firebase_depot.get_meta("supply_max", FIREBASE_DEPOT_CAPACITY)
			fb_supply = minf(fb_supply + unload_amount, fb_max)
			_firebase_depot.set_meta("supply_current", fb_supply)

			if cargo <= 0:
				cargo = 0
				state = "EN_ROUTE"
				spline_dist = -convoy_index * 12.0  # Stagger return
				returning = true

			truck.set_meta("cargo", cargo)
			truck.set_meta("state", state)
			truck.set_meta("returning", returning)
			truck.set_meta("spline_distance", spline_dist)


func _get_truck_speed_at_distance(distance: float, base_speed: float, total_length: float) -> float:
	"""Calculate truck speed considering road damage"""
	# Check which segment we're in
	var segment_count: int = _road_waypoints.size() - 1
	if segment_count <= 0:
		return base_speed

	var segment_length: float = total_length / segment_count
	var current_segment: int = int(distance / segment_length)
	current_segment = clampi(current_segment, 0, segment_count - 1)

	# Apply damage penalty
	var damage: float = _damaged_segments.get(current_segment, 0.0)
	var speed_multiplier: float = 1.0 - (damage * 0.7)  # Max 70% speed reduction
	return base_speed * maxf(speed_multiplier, 0.3)


func _manual_dispatch_convoy() -> void:
	"""Force convoy to start a new supply run"""
	for i in _supply_trucks.size():
		var truck: Node3D = _supply_trucks[i]
		if is_instance_valid(truck):
			truck.set_meta("state", "LOADING")
			truck.set_meta("cargo", 0.0)
			truck.set_meta("spline_distance", 0.0)
			truck.set_meta("returning", false)
			truck.position = REAR_DEPOT_POS + Vector3(0, 0, 10 + i * 12)

	_convoy_state = "LOADING"
	print("[SupplyTest] Convoy manually dispatched (%d trucks)" % _supply_trucks.size())


# ============================================================================
# CH-47 CHINOOK HELICOPTER SUPPLY
# ============================================================================

func _create_chinook_helicopter() -> void:
	"""Create CH-47 Chinook helicopter with real model"""
	_chinook = Node3D.new()
	_chinook.name = "CH47_Chinook"
	_chinook.position = CHINOOK_WAITING_POS
	add_child(_chinook)

	# Try to load real Chinook model
	var model_scene: PackedScene = load(CH47_CHINOOK_MODEL)
	if model_scene:
		var model: Node3D = model_scene.instantiate()
		model.name = "ChinookModel"
		# Scale appropriately (CH-47 is ~30m long)
		model.scale = Vector3(1.0, 1.0, 1.0)
		_chinook.add_child(model)

		# Find rotor nodes for animation
		_find_and_store_rotors(model)
		print("[SupplyTest] Loaded CH-47 Chinook model")
	else:
		# Fallback to placeholder
		_create_placeholder_chinook(_chinook)
		print("[SupplyTest] Using placeholder Chinook (model not found)")

	# Initialize chinook state
	_chinook.set_meta("target_position", CHINOOK_WAITING_POS)
	_chinook_state = "WAITING"
	_chinook_cargo = 0.0


func _find_and_store_rotors(model: Node3D) -> void:
	"""Find rotor nodes in the Chinook model for animation"""
	# CH-47 has two main rotors - front and rear
	# Store references as metadata for rotation
	var front_rotor: Node3D = _find_node_recursive(model, "rotor")
	var rear_rotor: Node3D = _find_node_recursive(model, "rear")
	if front_rotor:
		_chinook.set_meta("front_rotor", front_rotor)
	if rear_rotor:
		_chinook.set_meta("rear_rotor", rear_rotor)


func _find_node_recursive(node: Node, name_contains: String) -> Node3D:
	"""Recursively find node containing name"""
	if name_contains.to_lower() in node.name.to_lower():
		if node is Node3D:
			return node
	for child in node.get_children():
		var found: Node3D = _find_node_recursive(child, name_contains)
		if found:
			return found
	return null


func _create_placeholder_chinook(parent: Node3D) -> void:
	"""Fallback placeholder Chinook geometry"""
	# Fuselage (larger, boxy like CH-47)
	var fuselage := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.0, 3.0, 15.0)
	fuselage.mesh = box
	fuselage.position.y = 1.5

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.25)  # OD green
	fuselage.material_override = mat
	parent.add_child(fuselage)

	# Front rotor disc
	var front_rotor := MeshInstance3D.new()
	front_rotor.name = "FrontRotor"
	var rotor_mesh := CylinderMesh.new()
	rotor_mesh.top_radius = 9.0
	rotor_mesh.bottom_radius = 9.0
	rotor_mesh.height = 0.15
	front_rotor.mesh = rotor_mesh
	front_rotor.position = Vector3(0, 4.0, -5.0)

	var rotor_mat := StandardMaterial3D.new()
	rotor_mat.albedo_color = Color(0.2, 0.2, 0.2, 0.4)
	rotor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	front_rotor.material_override = rotor_mat
	parent.add_child(front_rotor)
	parent.set_meta("front_rotor", front_rotor)

	# Rear rotor disc
	var rear_rotor := MeshInstance3D.new()
	rear_rotor.name = "RearRotor"
	rear_rotor.mesh = rotor_mesh.duplicate()
	rear_rotor.position = Vector3(0, 4.0, 5.0)
	rear_rotor.material_override = rotor_mat
	parent.add_child(rear_rotor)
	parent.set_meta("rear_rotor", rear_rotor)


func _update_chinook_loop(delta: float) -> void:
	"""Update CH-47 Chinook helicopter movement and state"""
	if not is_instance_valid(_chinook):
		return

	# Update rotor animation
	_update_chinook_rotors(delta)

	match _chinook_state:
		"WAITING":
			_chinook_hover_at_position(delta, CHINOOK_WAITING_POS)

		"FLYING_TO_DEPOT":
			var depot_pos := REAR_DEPOT_POS + Vector3(15, 0, 0)  # Helipad offset
			depot_pos.y = CHINOOK_CRUISE_ALTITUDE
			if _chinook_fly_toward(delta, depot_pos, CHINOOK_SPEED):
				_chinook_state = "LANDING_AT_DEPOT"

		"LANDING_AT_DEPOT":
			var ground_pos := REAR_DEPOT_POS + Vector3(15, 2.0, 0)
			if _chinook_descend_to(delta, ground_pos):
				_chinook_state = "LOADING"

		"LOADING":
			_chinook_cargo += 200.0 * delta
			if _chinook_cargo >= HELI_SUPPLY_AMOUNT:
				_chinook_cargo = HELI_SUPPLY_AMOUNT
				_chinook_state = "TAKING_OFF_DEPOT"

		"TAKING_OFF_DEPOT":
			var takeoff_pos := REAR_DEPOT_POS + Vector3(15, CHINOOK_CRUISE_ALTITUDE, 0)
			if _chinook_ascend_to(delta, takeoff_pos):
				_chinook_state = "FLYING_TO_LZ"

		"FLYING_TO_LZ":
			var lz_pos := FIREBASE_POS + Vector3(-15, CHINOOK_CRUISE_ALTITUDE, 10)
			if _chinook_fly_toward(delta, lz_pos, CHINOOK_SPEED):
				_chinook_state = "LANDING_AT_LZ"

		"LANDING_AT_LZ":
			var ground_pos := FIREBASE_POS + Vector3(-15, 2.0, 10)
			if _chinook_descend_to(delta, ground_pos):
				_chinook_state = "UNLOADING"

		"UNLOADING":
			var unload_amount: float = 200.0 * delta
			_chinook_cargo -= unload_amount

			# Add to firebase depot
			var fb_supply: float = _firebase_depot.get_meta("supply_current", 0.0)
			var fb_max: float = _firebase_depot.get_meta("supply_max", FIREBASE_DEPOT_CAPACITY)
			fb_supply = minf(fb_supply + unload_amount, fb_max)
			_firebase_depot.set_meta("supply_current", fb_supply)

			if _chinook_cargo <= 0:
				_chinook_cargo = 0
				_chinook_state = "TAKING_OFF_LZ"

		"TAKING_OFF_LZ":
			var takeoff_pos := FIREBASE_POS + Vector3(-15, CHINOOK_CRUISE_ALTITUDE, 10)
			if _chinook_ascend_to(delta, takeoff_pos):
				_chinook_state = "RETURNING"

		"RETURNING":
			if _chinook_fly_toward(delta, CHINOOK_WAITING_POS, CHINOOK_SPEED):
				_chinook_state = "WAITING"
				print("[SupplyTest] Chinook supply run complete")


func _update_chinook_rotors(delta: float) -> void:
	"""Spin Chinook rotors"""
	# Ramp up/down rotor speed based on state
	var target_speed: float = CHINOOK_ROTOR_MAX_SPEED
	if _chinook_state == "WAITING":
		target_speed = CHINOOK_ROTOR_MAX_SPEED * 0.8  # Slower idle
	_chinook_rotor_speed = lerpf(_chinook_rotor_speed, target_speed, delta * 2.0)

	# Rotate both rotors (counter-rotating on CH-47)
	var front_rotor: Node3D = _chinook.get_meta("front_rotor", null)
	var rear_rotor: Node3D = _chinook.get_meta("rear_rotor", null)

	if is_instance_valid(front_rotor):
		front_rotor.rotate_y(_chinook_rotor_speed * delta)
	if is_instance_valid(rear_rotor):
		rear_rotor.rotate_y(-_chinook_rotor_speed * delta)  # Counter-rotate


func _chinook_hover_at_position(delta: float, target: Vector3) -> void:
	"""Gentle hover drift at position"""
	var diff := target - _chinook.position
	if diff.length() > 1.0:
		_chinook.position = _chinook.position.lerp(target, delta * 0.5)


func _chinook_fly_toward(delta: float, target: Vector3, speed: float) -> bool:
	"""Fly toward target, returns true when arrived"""
	var direction: Vector3 = (target - _chinook.position).normalized()
	var distance: float = _chinook.position.distance_to(target)

	if distance > 5.0:
		# Move toward target
		var velocity := direction * speed
		if distance < 30.0:
			velocity *= distance / 30.0  # Slow down on approach
		_chinook.position += velocity * delta

		# Face direction of travel (horizontal only)
		var look_dir := Vector3(direction.x, 0, direction.z)
		if look_dir.length() > 0.1:
			var target_rot: float = atan2(look_dir.x, look_dir.z)
			_chinook.rotation.y = lerp_angle(_chinook.rotation.y, target_rot, delta * 2.0)
		return false
	else:
		_chinook.position = target
		return true


func _chinook_descend_to(delta: float, target: Vector3) -> bool:
	"""Descend vertically, returns true when landed"""
	var descent_speed := 6.0
	if _chinook.position.y > target.y + 0.5:
		_chinook.position.y -= descent_speed * delta
		# Also move horizontally to align
		_chinook.position.x = lerpf(_chinook.position.x, target.x, delta * 2.0)
		_chinook.position.z = lerpf(_chinook.position.z, target.z, delta * 2.0)
		return false
	else:
		_chinook.position = target
		return true


func _chinook_ascend_to(delta: float, target: Vector3) -> bool:
	"""Ascend vertically, returns true when at altitude"""
	var ascent_speed := 8.0
	if _chinook.position.y < target.y - 0.5:
		_chinook.position.y += ascent_speed * delta
		return false
	else:
		_chinook.position.y = target.y
		return true


func _request_chinook_supply() -> void:
	"""Request CH-47 Chinook supply run"""
	if _chinook_state != "WAITING":
		print("[SupplyTest] Chinook is busy (state: %s)" % _chinook_state)
		return

	_chinook_state = "FLYING_TO_DEPOT"
	_chinook_cargo = 0.0
	print("[SupplyTest] CH-47 Chinook dispatched for supply run (%.0f capacity)" % HELI_SUPPLY_AMOUNT)


# ============================================================================
# INFANTRY SQUADS (CONSUMERS)
# ============================================================================

# Selected squad for movement
var _selected_squad: Node3D = null
var _selected_squad_index: int = 0


func _spawn_test_squads() -> void:
	"""Spawn infantry squads OUTSIDE firebase - START AT 10% SUPPLY (need to move into zone)"""
	# Spawn OUTSIDE the influence circle so player must move them in
	# Firebase influence is 168m, so spawn 200m+ away from firebase center
	var squad_positions: Array[Vector3] = [
		FIREBASE_POS + Vector3(-200, 0, -50),   # Alpha - far west
		FIREBASE_POS + Vector3(-180, 0, 30),    # Bravo - northwest
		FIREBASE_POS + Vector3(-220, 0, -10),   # Charlie - far west
	]
	var squad_names: Array[String] = ["Alpha", "Bravo", "Charlie"]

	# Get terrain height for positioning
	var terrain: Node = get_node_or_null("/root/TerrainIntegration")

	for i in squad_positions.size():
		var squad := Node3D.new()
		squad.name = "RifleSquad_%s" % squad_names[i]
		squad.position = squad_positions[i]

		# Snap to terrain
		if terrain and terrain.has_method("get_height_at"):
			squad.position.y = terrain.get_height_at(squad.position)

		add_child(squad)

		# Track supply for this squad - START AT 10% (desperate need for resupply)
		squad.set_meta("supply_current", 10.0)  # 10% of 100
		squad.set_meta("supply_max", 100.0)
		squad.set_meta("squad_name", squad_names[i])
		squad.set_meta("in_supply_zone", false)  # Start outside zone

		# Visual - cluster of soldiers with rifles
		for j in 6:
			var soldier := MeshInstance3D.new()
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.3
			capsule.height = 1.8
			soldier.mesh = capsule
			soldier.position = Vector3(
				randf_range(-2, 2),
				0.9,
				randf_range(-2, 2)
			)
			var mat := StandardMaterial3D.new()
			# Color based on supply level (green = full, red = low)
			mat.albedo_color = Color(0.7, 0.3, 0.3)  # Start red (low supply)
			soldier.material_override = mat
			soldier.set_meta("is_soldier", true)
			squad.add_child(soldier)

		# Supply indicator label above squad
		var label := Label3D.new()
		label.name = "SupplyLabel"
		label.text = "10% [OUT]"
		label.position.y = 3.0
		label.font_size = 48
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(1, 0.3, 0.3)  # Red for low supply
		squad.add_child(label)

		# Selection indicator (hidden until selected)
		var select_ring := MeshInstance3D.new()
		select_ring.name = "SelectionRing"
		var torus := TorusMesh.new()
		torus.inner_radius = 3.0
		torus.outer_radius = 3.5
		select_ring.mesh = torus
		select_ring.rotation.x = -PI / 2
		select_ring.position.y = 0.1
		var ring_mat := StandardMaterial3D.new()
		ring_mat.albedo_color = Color(0.2, 0.8, 1.0, 0.8)
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		select_ring.material_override = ring_mat
		select_ring.visible = false
		squad.add_child(select_ring)

		_test_squads.append(squad)

	# Select first squad by default
	if not _test_squads.is_empty():
		_selected_squad = _test_squads[0]
		_selected_squad_index = 0
		_update_squad_selection_visual()

	print("[SupplyTest] Spawned %d rifle squads OUTSIDE firebase - ALL AT 10%% SUPPLY" % _test_squads.size())
	print("[SupplyTest] Use F/G to cycle squads, RIGHT-CLICK to move selected squad into the GREEN influence zone!")


func _update_squad_selection_visual() -> void:
	"""Update selection ring visibility"""
	for i in _test_squads.size():
		var squad: Node3D = _test_squads[i]
		if is_instance_valid(squad):
			var ring: Node3D = squad.get_node_or_null("SelectionRing")
			if ring:
				ring.visible = (squad == _selected_squad)


func _cycle_squad_selection(direction: int) -> void:
	"""Cycle through squads for selection"""
	if _test_squads.is_empty():
		return

	_selected_squad_index = (_selected_squad_index + direction + _test_squads.size()) % _test_squads.size()
	_selected_squad = _test_squads[_selected_squad_index]
	_update_squad_selection_visual()

	var squad_name: String = _selected_squad.get_meta("squad_name", "Unknown")
	var in_zone: bool = _selected_squad.get_meta("in_supply_zone", false)
	print("[SupplyTest] Selected: %s (in zone: %s) - Right-click to move" % [squad_name, in_zone])


func _move_squad_to_click(screen_pos: Vector2) -> void:
	"""Move selected squad to clicked world position"""
	if not _selected_squad or not camera:
		return

	# Raycast to find ground position
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var to: Vector3 = from + camera.project_ray_normal(screen_pos) * 1000.0

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return

	var target_pos: Vector3 = result.position

	# Get terrain height at target
	var terrain: Node = get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		target_pos.y = terrain.get_height_at(target_pos)

	# Move squad to position (instant for testing - could add walk animation)
	var squad_name: String = _selected_squad.get_meta("squad_name", "?")
	_selected_squad.position = target_pos

	# Check if now in supply zone
	var firebase_center: Vector3 = _firebase.global_position if is_instance_valid(_firebase) else FIREBASE_POS
	var distance: float = target_pos.distance_to(firebase_center)
	var now_in_zone: bool = distance <= FIREBASE_INFLUENCE_RADIUS

	print("[SupplyTest] %s moved to %.0f, %.0f (%.0fm from firebase, %s supply zone)" % [
		squad_name, target_pos.x, target_pos.z, distance,
		"IN" if now_in_zone else "OUTSIDE"
	])


func _simulate_supply_consumption(delta: float) -> void:
	"""Simulate squads consuming and receiving supply within INFLUENCE RADIUS"""
	_consumption_timer += delta
	if _consumption_timer < 1.0:
		return
	_consumption_timer = 0.0

	var rate: float = CONSUMPTION_RATES[_consumption_rate_index]
	var fb_supply: float = _firebase_depot.get_meta("supply_current", 0.0)

	# Process each squad - consume supply and potentially resupply from depot
	for squad in _test_squads:
		if not is_instance_valid(squad):
			continue

		var squad_supply: float = squad.get_meta("supply_current", 100.0)
		var squad_max: float = squad.get_meta("supply_max", 100.0)

		# Consume supply (simulating ammo/food usage)
		squad_supply = maxf(0.0, squad_supply - rate * 0.5)

		# Check if squad is within supply influence radius of firebase
		var firebase_center: Vector3 = _firebase.global_position if is_instance_valid(_firebase) else FIREBASE_POS
		var distance_to_firebase: float = squad.global_position.distance_to(firebase_center)
		var is_in_supply_zone: bool = distance_to_firebase <= FIREBASE_INFLUENCE_RADIUS

		# Only resupply if squad is WITHIN the green influence circle AND depot has supply
		if is_in_supply_zone and squad_supply < 80.0 and fb_supply > 0.0:
			var resupply_amount: float = minf(10.0, fb_supply)  # 10 supply per tick
			resupply_amount = minf(resupply_amount, squad_max - squad_supply)
			squad_supply += resupply_amount
			fb_supply -= resupply_amount
			squad.set_meta("in_supply_zone", true)
		else:
			squad.set_meta("in_supply_zone", is_in_supply_zone)

		squad.set_meta("supply_current", squad_supply)

		# Update visual indicators
		_update_squad_supply_visual(squad, squad_supply, squad_max, is_in_supply_zone)

	_firebase_depot.set_meta("supply_current", fb_supply)


func _update_squad_supply_visual(squad: Node3D, current: float, maximum: float, in_supply_zone: bool = true) -> void:
	"""Update squad's visual supply indicator"""
	var ratio: float = current / maximum if maximum > 0.0 else 0.0

	# Update label
	var label: Label3D = squad.get_node_or_null("SupplyLabel")
	if label:
		var zone_indicator: String = " [IN ZONE]" if in_supply_zone else " [OUT]"
		label.text = "%d%%%s" % [int(ratio * 100), zone_indicator]
		# Color: red -> yellow -> green
		if ratio > 0.6:
			label.modulate = Color(0.3, 0.9, 0.3)  # Green
		elif ratio > 0.3:
			label.modulate = Color(0.9, 0.8, 0.2)  # Yellow
		else:
			label.modulate = Color(1.0, 0.3, 0.3)  # Red

	# Update soldier colors based on supply
	for child in squad.get_children():
		if child is MeshInstance3D and child.has_meta("is_soldier"):
			var mat: StandardMaterial3D = child.material_override
			if mat:
				if ratio > 0.6:
					mat.albedo_color = Color(0.35, 0.45, 0.3)  # Healthy OD green
				elif ratio > 0.3:
					mat.albedo_color = Color(0.5, 0.45, 0.3)  # Slightly worn
				else:
					mat.albedo_color = Color(0.7, 0.35, 0.3)  # Low supply - reddish


# ============================================================================
# CAMERA
# ============================================================================

func _cycle_camera_focus() -> void:
	"""Cycle camera between points of interest"""
	_camera_target_index = (_camera_target_index + 1) % _camera_targets.size()
	var target: Node3D = _camera_targets[_camera_target_index]
	if target and camera:
		var target_pos: Vector3 = target.global_position
		camera.position = target_pos + Vector3(0, 40, 40)
		print("[SupplyTest] Camera focused on: %s" % target.name)


# ============================================================================
# HUD
# ============================================================================

func _create_debug_hud() -> void:
	"""Create debug HUD"""
	_hud_label = TestSceneBase.make_hud(self)

	# Supply depot bars (right side)
	var depot_panel := VBoxContainer.new()
	depot_panel.name = "DepotPanel"
	depot_panel.position = Vector2(get_viewport().size.x - 280, 20)
	$HUD.add_child(depot_panel)

	# Rear depot label
	var rear_label := Label.new()
	rear_label.name = "RearDepotLabel"
	rear_label.text = "Rear Depot: INFINITE"
	rear_label.add_theme_font_size_override("font_size", 14)
	depot_panel.add_child(rear_label)
	_depot_labels["rear"] = rear_label

	# Firebase depot label
	var fb_label := Label.new()
	fb_label.name = "FirebaseDepotLabel"
	fb_label.text = "Firebase: 0/0"
	fb_label.add_theme_font_size_override("font_size", 14)
	depot_panel.add_child(fb_label)
	_depot_labels["firebase"] = fb_label

	# Firebase progress bar
	var fb_bar := ProgressBar.new()
	fb_bar.name = "FirebaseBar"
	fb_bar.min_value = 0
	fb_bar.max_value = 100
	fb_bar.value = 50
	fb_bar.custom_minimum_size = Vector2(220, 20)
	depot_panel.add_child(fb_bar)
	_depot_labels["firebase_bar"] = fb_bar

	# Separator
	var sep := HSeparator.new()
	depot_panel.add_child(sep)

	# Convoy status label
	var convoy_label := Label.new()
	convoy_label.name = "ConvoyLabel"
	convoy_label.text = "Convoy: 0 trucks"
	convoy_label.add_theme_font_size_override("font_size", 14)
	depot_panel.add_child(convoy_label)
	_depot_labels["convoy"] = convoy_label

	# Chinook status label
	var chinook_label := Label.new()
	chinook_label.name = "ChinookLabel"
	chinook_label.text = "CH-47: WAITING"
	chinook_label.add_theme_font_size_override("font_size", 14)
	depot_panel.add_child(chinook_label)
	_depot_labels["chinook"] = chinook_label

	# Road damage label
	var road_label := Label.new()
	road_label.name = "RoadLabel"
	road_label.text = "Road: OK"
	road_label.add_theme_font_size_override("font_size", 14)
	depot_panel.add_child(road_label)
	_depot_labels["road"] = road_label

	# === BULLDOZER DEBUG PANEL (LEFT SIDE) ===
	var dozer_panel := VBoxContainer.new()
	dozer_panel.name = "BulldozerPanel"
	dozer_panel.position = Vector2(20, 300)  # Below main HUD
	$HUD.add_child(dozer_panel)

	var dozer_header := Label.new()
	dozer_header.text = "=== BULLDOZER DEBUG ==="
	dozer_header.add_theme_font_size_override("font_size", 16)
	dozer_header.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	dozer_panel.add_child(dozer_header)
	_depot_labels["dozer_header"] = dozer_header

	var dozer_state := Label.new()
	dozer_state.name = "DozerState"
	dozer_state.text = "State: --"
	dozer_state.add_theme_font_size_override("font_size", 14)
	dozer_panel.add_child(dozer_state)
	_depot_labels["dozer_state"] = dozer_state

	var dozer_job := Label.new()
	dozer_job.name = "DozerJob"
	dozer_job.text = "Job: --"
	dozer_job.add_theme_font_size_override("font_size", 14)
	dozer_panel.add_child(dozer_job)
	_depot_labels["dozer_job"] = dozer_job

	var dozer_pos := Label.new()
	dozer_pos.name = "DozerPos"
	dozer_pos.text = "Position: --"
	dozer_pos.add_theme_font_size_override("font_size", 14)
	dozer_panel.add_child(dozer_pos)
	_depot_labels["dozer_pos"] = dozer_pos

	var dozer_trees := Label.new()
	dozer_trees.name = "DozerTrees"
	dozer_trees.text = "Trees nearby: --"
	dozer_trees.add_theme_font_size_override("font_size", 14)
	dozer_panel.add_child(dozer_trees)
	_depot_labels["dozer_trees"] = dozer_trees

	var dozer_worker := Label.new()
	dozer_worker.name = "DozerWorker"
	dozer_worker.text = "Worker: --"
	dozer_worker.add_theme_font_size_override("font_size", 14)
	dozer_panel.add_child(dozer_worker)
	_depot_labels["dozer_worker"] = dozer_worker


func _update_hud() -> void:
	"""Update HUD displays"""
	var rate: float = CONSUMPTION_RATES[_consumption_rate_index]

	# Get lead truck spline progress info
	var spline_dist: float = 0.0
	var returning: bool = false
	if not _supply_trucks.is_empty() and is_instance_valid(_supply_trucks[0]):
		spline_dist = _supply_trucks[0].get_meta("spline_distance", 0.0)
		returning = _supply_trucks[0].get_meta("returning", false)

	var spline: RefCounted = _return_spline if returning else _road_spline
	var spline_len: float = spline.get_total_length() if spline else 1.0
	var progress_pct: float = (maxf(spline_dist, 0.0) / spline_len * 100.0) if spline_len > 0 else 0.0

	# Build road construction status
	var road_status: String = ""
	match _road_construction_state:
		"NOT_STARTED":
			road_status = "PRESS B TO BUILD ROAD"
		"BUILDING":
			road_status = "BUILDING: %.0f%%" % (_road_construction_progress * 100)
		"COMPLETE":
			road_status = "ROAD READY"

	# Get squad supply info
	var squad_info: String = ""
	for squad in _test_squads:
		if is_instance_valid(squad):
			var s_name: String = squad.get_meta("squad_name", "?")
			var s_supply: float = squad.get_meta("supply_current", 0.0)
			var in_zone: bool = squad.get_meta("in_supply_zone", true)
			var zone_text: String = "[IN]" if in_zone else "[OUT]"
			squad_info += "  %s: %.0f%% %s\n" % [s_name, s_supply, zone_text]

	# Get selected squad info
	var selected_name: String = "None"
	if _selected_squad:
		selected_name = _selected_squad.get_meta("squad_name", "?")

	var lines: PackedStringArray = [
		"PILLAR 3: PHYSICAL SUPPLY CHAINS",
		"",
		"Road: %s" % road_status,
		"Supply Zone: %.0fm radius (GREEN circle)" % FIREBASE_INFLUENCE_RADIUS,
		"",
		"Hotkeys:",
		"  B: Build road | T: Convoy | H: Chinook",
		"  F/G: Select squad | Right-Click: Move squad",
		"  D/Click: Damage road | R: Repair | 1-4: Rate",
		"",
		"Selected: %s | Route: %.0fm" % [selected_name, spline_len],
		"Consumption: %.1f/sec" % rate,
		"",
		"Squad Supply (IN = receiving resupply):",
		squad_info,
	]
	_hud_label.text = "\n".join(lines)

	# Update depot displays
	if _depot_labels.has("firebase"):
		var fb_supply: float = _firebase_depot.get_meta("supply_current", 0.0)
		var fb_max: float = _firebase_depot.get_meta("supply_max", FIREBASE_DEPOT_CAPACITY)
		var ratio: float = fb_supply / fb_max if fb_max > 0 else 0.0

		_depot_labels["firebase"].text = "Firebase: %.0f/%.0f" % [fb_supply, fb_max]

		if _depot_labels.has("firebase_bar"):
			var bar: ProgressBar = _depot_labels["firebase_bar"]
			bar.value = ratio * 100

			# Color based on level
			var style := StyleBoxFlat.new()
			if ratio > 0.5:
				style.bg_color = Color(0.2, 0.7, 0.2)  # Green
			elif ratio > 0.25:
				style.bg_color = Color(0.8, 0.7, 0.1)  # Yellow
			else:
				style.bg_color = Color(0.8, 0.2, 0.1)  # Red
			bar.add_theme_stylebox_override("fill", style)

	# Update convoy status
	if _depot_labels.has("convoy"):
		var total_cargo: float = 0.0
		for truck in _supply_trucks:
			if is_instance_valid(truck):
				total_cargo += truck.get_meta("cargo", 0.0)
		_depot_labels["convoy"].text = "Convoy: %d trucks | %s | %.0f cargo" % [
			_supply_trucks.size(), _convoy_state, total_cargo
		]

	# Update Chinook status
	if _depot_labels.has("chinook"):
		_depot_labels["chinook"].text = "CH-47: %s (%.0f cargo)" % [_chinook_state, _chinook_cargo]

	# Update road damage status
	if _depot_labels.has("road"):
		var damaged_count: int = _damaged_segments.size()
		if damaged_count > 0:
			var avg_damage: float = 0.0
			for dmg: float in _damaged_segments.values():
				avg_damage += dmg
			avg_damage /= damaged_count
			_depot_labels["road"].text = "Road: %d segments damaged (-%d%% avg speed)" % [
				damaged_count, int(avg_damage * 70)
			]
		else:
			_depot_labels["road"].text = "Road: OK (full speed)"

	# === UPDATE BULLDOZER DEBUG PANEL ===
	_update_bulldozer_debug()


func _update_bulldozer_debug() -> void:
	"""Update bulldozer debug panel with current state"""
	if not is_instance_valid(_bulldozer):
		if _depot_labels.has("dozer_state"):
			_depot_labels["dozer_state"].text = "State: NO BULLDOZER"
		return

	# Get bulldozer state
	var state_name: String = "UNKNOWN"
	if _bulldozer.has_method("get_state_name"):
		state_name = _bulldozer.get_state_name()
	elif "state" in _bulldozer:
		state_name = str(_bulldozer.state)

	if _depot_labels.has("dozer_state"):
		_depot_labels["dozer_state"].text = "State: %s" % state_name

	# Get current job info from WorkerController
	var job_info: String = "None"
	var worker_state: String = "N/A"
	var wc: Node = _bulldozer.get_node_or_null("WorkerController")
	if wc and is_instance_valid(wc):
		worker_state = str(wc.state) if "state" in wc else "?"
		if "current_job" in wc and wc.current_job and is_instance_valid(wc.current_job):
			var job = wc.current_job
			var job_type: String = str(job.job_type) if "job_type" in job else "?"
			var job_id: int = job.job_id if "job_id" in job else -1
			job_info = "#%d: %s" % [job_id, job_type]

	if _depot_labels.has("dozer_job"):
		_depot_labels["dozer_job"].text = "Job: %s" % job_info

	if _depot_labels.has("dozer_worker"):
		_depot_labels["dozer_worker"].text = "Worker: state=%s" % worker_state

	# Get position
	if _depot_labels.has("dozer_pos"):
		var pos: Vector3 = _bulldozer.global_position
		_depot_labels["dozer_pos"].text = "Position: (%.0f, %.0f, %.0f)" % [pos.x, pos.y, pos.z]

	# Count nearby trees
	if _depot_labels.has("dozer_trees"):
		var tree_count: int = _count_trees_near(_bulldozer.global_position, 20.0)
		_depot_labels["dozer_trees"].text = "Trees in 20m: %d | Local: %d" % [tree_count, _jungle_trees.size()]


func _count_trees_near(pos: Vector3, radius: float) -> int:
	"""Count trees within radius (from vegetation manager or local container)"""
	var count: int = 0

	# Check local jungle container
	for tree in _jungle_trees:
		if is_instance_valid(tree) and tree is Node3D:
			if tree.global_position.distance_to(pos) < radius:
				count += 1

	# Check vegetation manager groups
	for node in get_tree().get_nodes_in_group("trees"):
		if not is_instance_valid(node):
			continue
		if node is Node3D and node.global_position.distance_to(pos) < radius:
			count += 1

	return count


func _reset_test_state() -> void:
	"""Reset all test state"""
	# Reset firebase supply
	_firebase_depot.set_meta("supply_current", INITIAL_FIREBASE_SUPPLY)

	# Reset convoy
	for i in _supply_trucks.size():
		var truck: Node3D = _supply_trucks[i]
		if is_instance_valid(truck):
			truck.set_meta("state", "LOADING")
			truck.set_meta("cargo", 0.0)
			truck.set_meta("spline_distance", 0.0)
			truck.set_meta("returning", false)
			truck.position = REAR_DEPOT_POS + Vector3(0, 0, 10 + i * 12)
	_convoy_state = "LOADING"

	# Reset Chinook
	if is_instance_valid(_chinook):
		_chinook.position = CHINOOK_WAITING_POS
		_chinook_state = "WAITING"
		_chinook_cargo = 0.0

	# Repair roads
	_repair_all_roads()

	print("[SupplyTest] Test state reset - convoy and Chinook at starting positions")


func _toggle_spline_visualizer() -> void:
	"""Toggle spline debug visualizer visibility"""
	if _spline_visualizer:
		_spline_visualizer.visible = not _spline_visualizer.visible
		print("[SupplyTest] Spline visualizer: %s" % ("ON" if _spline_visualizer.visible else "OFF"))
