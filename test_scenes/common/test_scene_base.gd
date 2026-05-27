extends RefCounted
class_name TestSceneBase
## TestSceneBase - Shared setup helpers for RealVietnamRTS test scenes.
##
## Each test scene calls TestSceneBase.setup_environment(scene, ...) at _ready
## to get: terrain initialized via TerrainIntegration, RTS camera with controls,
## lighting, and a standard play area.
##
## RTS controls come from autoloads:
##   - SelectionManager: Drag-box selection, control groups
##   - MoveOrderHandler: Right-click move/attack
##   - BattleHUD: Selection card, command panel, targeting overlay
##
## Usage:
##   func _ready() -> void:
##       TestSceneBase.setup_environment(self, {
##           "seed": 12345,
##           "size": 400.0,
##           "name": "Infantry Test",
##       })

const RTSCameraScript = preload("res://battle_system/camera/rts_camera.gd")


## Set up a complete test environment on the given scene.
## opts:
##   seed (int): heightmap seed
##   size (float): playable square size in meters (default 400)
##   name (String): label shown in console
##   add_camera (bool): create an RTS camera (default true)
##   light_yaw (float): sun direction in degrees
##   map_bounds (Vector2): map bounds for camera clamping (default uses size)
##   skip_terrain (bool): skip TerrainIntegration init (for scenes using local terrain)
static func setup_environment(scene: Node3D, opts: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}

	var seed_val: int = opts.get("seed", 42)
	var size: float = opts.get("size", 400.0)
	var scene_name: String = opts.get("name", "TestScene")
	var add_camera: bool = opts.get("add_camera", true)

	print("=== %s ===" % scene_name)
	print("Map size: %.0fm  Seed: %d" % [size, seed_val])

	# ---- Lighting ----
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, opts.get("light_yaw", 35.0), 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	scene.add_child(sun)

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.4, 0.6, 0.8)
	sky_mat.sky_horizon_color = Color(0.75, 0.85, 0.9)
	sky_mat.ground_horizon_color = Color(0.55, 0.55, 0.5)
	sky_mat.ground_bottom_color = Color(0.25, 0.25, 0.22)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	world_env.environment = env
	scene.add_child(world_env)

	# ---- RTS Camera with WASD, zoom, rotate controls ----
	var camera: Camera3D = null
	if add_camera:
		camera = RTSCameraScript.new()
		camera.name = "RTSCamera"
		# Support custom camera position for test scenes that need terrain in specific area
		var cam_pos: Vector3 = opts.get("camera_position", Vector3(0.0, 150.0, 150.0))
		camera.position = cam_pos
		camera.current = true
		# Set map bounds for camera clamping
		var half_size: float = size * 0.5
		camera.map_bounds_min = Vector3(-half_size, 0, -half_size)
		camera.map_bounds_max = Vector3(half_size, 500, half_size)  # High for tactical overview
		scene.add_child(camera)
		result["camera"] = camera
		print("[TestSceneBase] RTSCamera created with WASD/zoom/rotate controls")

	# ---- Terrain initialization via TerrainIntegration autoload ----
	var skip_terrain: bool = opts.get("skip_terrain", false)
	if not skip_terrain:
		var terrain := scene.get_node_or_null("/root/TerrainIntegration")
		if terrain and camera:
			if terrain.has_method("init_terrain"):
				terrain.init_terrain(camera, seed_val)
				print("[TestSceneBase] TerrainIntegration initialized")
		else:
			print("[TestSceneBase] WARNING: TerrainIntegration not available - using fallback ground")
			_create_fallback_ground(scene, size)
	else:
		print("[TestSceneBase] Skipping terrain init (scene manages its own terrain)")

	# RTS controls come from autoloads:
	#   - SelectionManager: handles selection (drag-box, control groups)
	#   - MoveOrderHandler: handles right-click move/attack
	#   - BattleHUD: handles UI (selection card, command panel)
	print("[TestSceneBase] RTS controls via autoloads (SelectionManager, MoveOrderHandler, BattleHUD)")

	return result


## Fallback flat ground when TerrainIntegration is not present.
## Useful when testing scenes in isolation.
static func _create_fallback_ground(scene: Node3D, size: float) -> void:
	var ground := StaticBody3D.new()
	ground.name = "FallbackGround"
	ground.collision_layer = 1

	var mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	mesh_inst.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.2)
	mesh_inst.material_override = mat
	ground.add_child(mesh_inst)

	var coll := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 0.4, size)
	coll.shape = box
	coll.position.y = -0.2
	ground.add_child(coll)

	scene.add_child(ground)


## Build a simple obstacle field for pathfinding tests.
## buildings: array of Vector3 positions
## sizes: parallel array of Vector3 box sizes (or empty for default)
static func spawn_obstacle_buildings(scene: Node3D, positions: Array, sizes: Array = []) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for i in positions.size():
		var pos: Vector3 = positions[i]
		var size: Vector3 = sizes[i] if i < sizes.size() else Vector3(8.0, 5.0, 8.0)

		var body := StaticBody3D.new()
		body.name = "Building_%d" % i
		body.add_to_group("obstacles")
		body.collision_layer = 1
		body.position = pos

		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.position.y = size.y * 0.5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.45, 0.4)
		mi.material_override = mat
		body.add_child(mi)

		var coll := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		coll.shape = shape
		coll.position.y = size.y * 0.5
		body.add_child(coll)

		# Snap to terrain if available
		var terrain := scene.get_node_or_null("/root/TerrainIntegration")
		if terrain and terrain.has_method("get_height_at"):
			body.position.y = terrain.get_height_at(pos)

		scene.add_child(body)
		result.append(body)
	return result


## Place range markers along an axis to visualize firing distances.
## origin: starting point
## direction: unit vector along which to place markers
## distances: array of meters where to put each marker
static func spawn_range_markers(scene: Node3D, origin: Vector3, direction: Vector3, distances: Array) -> void:
	for d in distances:
		var pos: Vector3 = origin + direction.normalized() * float(d)
		var marker := MeshInstance3D.new()
		marker.name = "RangeMarker_%dm" % int(d)
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.1
		mesh.bottom_radius = 0.4
		mesh.height = 3.0
		marker.mesh = mesh
		marker.position = pos
		marker.position.y += 1.5

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.7, 0.2)
		marker.material_override = mat
		scene.add_child(marker)

		# Snap to terrain
		var terrain := scene.get_node_or_null("/root/TerrainIntegration")
		if terrain and terrain.has_method("get_height_at"):
			marker.position.y = terrain.get_height_at(pos) + 1.5


## Create a starter HQ base - a cleared area with 60s Army base structures.
## Returns a Dictionary with spawn_points Array for placing units inside the base.
## center: world position for base center
## size: approximate diameter of base (default 60m)
static func spawn_starter_hq(scene: Node3D, center: Vector3, size: float = 60.0) -> Dictionary:
	var result: Dictionary = {"spawn_points": [], "buildings": []}
	var terrain := scene.get_node_or_null("/root/TerrainIntegration")
	var half_size: float = size * 0.5

	# Get base height from terrain
	var base_height: float = 0.0
	if terrain and terrain.has_method("get_height_at"):
		base_height = terrain.get_height_at(center)

	# Create cleared flat ground plane
	var ground := StaticBody3D.new()
	ground.name = "HQ_Ground"
	ground.collision_layer = 1

	var ground_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	ground_mesh.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.45, 0.40, 0.30)  # Packed dirt color
	ground_mesh.material_override = ground_mat
	ground.add_child(ground_mesh)

	var ground_coll := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(size, 0.5, size)
	ground_coll.shape = ground_box
	ground_coll.position.y = -0.25
	ground.add_child(ground_coll)

	scene.add_child(ground)
	ground.global_position = Vector3(center.x, base_height + 0.1, center.z)
	result["buildings"].append(ground)

	# Clear vegetation in this area if terrain system supports it
	if terrain and terrain.has_method("prepare_building_site"):
		terrain.prepare_building_site(center, Vector2(size, size))

	# === PERIMETER SANDBAGS (4 walls with gaps for entry) ===
	var sandbag_positions: Array = [
		# North wall (with gap in center)
		Vector3(-half_size * 0.7, 0, -half_size + 2),
		Vector3(half_size * 0.7, 0, -half_size + 2),
		# South wall (with gap in center)
		Vector3(-half_size * 0.7, 0, half_size - 2),
		Vector3(half_size * 0.7, 0, half_size - 2),
		# East wall
		Vector3(half_size - 2, 0, -half_size * 0.5),
		Vector3(half_size - 2, 0, 0),
		Vector3(half_size - 2, 0, half_size * 0.5),
		# West wall
		Vector3(-half_size + 2, 0, -half_size * 0.5),
		Vector3(-half_size + 2, 0, 0),
		Vector3(-half_size + 2, 0, half_size * 0.5),
	]

	for pos in sandbag_positions:
		var sandbag := _create_sandbag_wall(center + pos, base_height)
		scene.add_child(sandbag)
		result["buildings"].append(sandbag)

	# === BARBED WIRE (corners and gaps) ===
	var wire_positions: Array = [
		Vector3(-half_size + 5, 0, -half_size + 5),
		Vector3(half_size - 5, 0, -half_size + 5),
		Vector3(-half_size + 5, 0, half_size - 5),
		Vector3(half_size - 5, 0, half_size - 5),
	]

	for pos in wire_positions:
		var wire := _create_barbed_wire(center + pos, base_height)
		scene.add_child(wire)
		result["buildings"].append(wire)

	# === WATCHTOWERS (2 corners) ===
	var tower_positions: Array = [
		Vector3(-half_size + 8, 0, -half_size + 8),
		Vector3(half_size - 8, 0, half_size - 8),
	]

	for pos in tower_positions:
		var tower := _create_watchtower(center + pos, base_height)
		scene.add_child(tower)
		result["buildings"].append(tower)

	# === BARRACKS / HOOTCHES (2 tents) ===
	var barracks_positions: Array = [
		Vector3(-10, 0, 5),
		Vector3(10, 0, 5),
	]

	for pos in barracks_positions:
		var barracks := _create_hootch(center + pos, base_height)
		scene.add_child(barracks)
		result["buildings"].append(barracks)

	# === SPAWN POINTS (inside the base) ===
	for i in 6:
		var angle: float = float(i) * (TAU / 6.0)
		var radius: float = size * 0.2
		var spawn_pos := Vector3(
			center.x + cos(angle) * radius,
			base_height + 0.1,
			center.z + sin(angle) * radius
		)
		result["spawn_points"].append(spawn_pos)

	print("[TestSceneBase] Created starter HQ at %s (%.0fm)" % [center, size])
	return result


## Create a sandbag wall segment - tries to load actual model, falls back to placeholder
static func _create_sandbag_wall(pos: Vector3, base_y: float) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = "Sandbag_Light"
	wall.collision_layer = 1
	wall.add_to_group("structures")

	# Try to load actual model
	var model_loaded: bool = false
	const MODEL_PATH: String = "res://assets/models/structures/firebase/sandbag_light.glb"
	if ResourceLoader.exists(MODEL_PATH):
		var model_scene: PackedScene = load(MODEL_PATH)
		if model_scene:
			var model_instance: Node3D = model_scene.instantiate()
			wall.add_child(model_instance)
			model_loaded = true

	# Fall back to placeholder box if no model
	if not model_loaded:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(8.0, 1.2, 1.5)
		mesh.mesh = box
		mesh.position.y = 0.6
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.50, 0.35)  # Sandbag tan
		mesh.material_override = mat
		wall.add_child(mesh)

	# Collision shape always needed
	var coll := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(8.0, 1.2, 1.5)
	coll.shape = shape
	coll.position.y = 0.6
	wall.add_child(coll)

	wall.position = Vector3(pos.x, base_y, pos.z)
	return wall


## Create barbed wire obstacle
static func _create_barbed_wire(pos: Vector3, base_y: float) -> StaticBody3D:
	var wire := StaticBody3D.new()
	wire.name = "Barbed_Wire"
	wire.collision_layer = 1
	wire.add_to_group("obstacles")

	# Coiled wire representation
	var mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.8
	mesh.mesh = torus
	mesh.position.y = 0.5
	mesh.rotation.x = PI * 0.5  # Lay flat
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.3)  # Dark metal
	mesh.material_override = mat
	wire.add_child(mesh)

	var coll := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.0
	shape.height = 1.0
	coll.shape = shape
	coll.position.y = 0.5
	wire.add_child(coll)

	wire.position = Vector3(pos.x, base_y, pos.z)
	return wire


## Create watchtower
static func _create_watchtower(pos: Vector3, base_y: float) -> StaticBody3D:
	var tower := StaticBody3D.new()
	tower.name = "Watchtower"
	tower.collision_layer = 1
	tower.add_to_group("structures")

	# Wooden post legs (4 corners)
	var leg_positions: Array = [
		Vector3(-1.5, 0, -1.5),
		Vector3(1.5, 0, -1.5),
		Vector3(-1.5, 0, 1.5),
		Vector3(1.5, 0, 1.5),
	]

	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = Color(0.4, 0.3, 0.2)  # Wood brown

	for leg_pos in leg_positions:
		var leg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.15
		cyl.bottom_radius = 0.15
		cyl.height = 6.0
		leg.mesh = cyl
		leg.position = leg_pos
		leg.position.y = 3.0
		leg.material_override = leg_mat
		tower.add_child(leg)

	# Platform on top
	var platform := MeshInstance3D.new()
	var plat_box := BoxMesh.new()
	plat_box.size = Vector3(4.0, 0.3, 4.0)
	platform.mesh = plat_box
	platform.position.y = 6.0
	platform.material_override = leg_mat
	tower.add_child(platform)

	# Sandbag parapet on platform
	var parapet := MeshInstance3D.new()
	var parapet_box := BoxMesh.new()
	parapet_box.size = Vector3(4.5, 1.0, 4.5)
	parapet.mesh = parapet_box
	parapet.position.y = 6.5
	var parapet_mat := StandardMaterial3D.new()
	parapet_mat.albedo_color = Color(0.55, 0.50, 0.35)
	parapet.material_override = parapet_mat
	tower.add_child(parapet)

	# Collision for whole tower
	var coll := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.0, 7.0, 4.0)
	coll.shape = shape
	coll.position.y = 3.5
	tower.add_child(coll)

	tower.position = Vector3(pos.x, base_y, pos.z)
	return tower


## Create a hootch / barracks tent
static func _create_hootch(pos: Vector3, base_y: float) -> StaticBody3D:
	var hootch := StaticBody3D.new()
	hootch.name = "Hootch"
	hootch.collision_layer = 1
	hootch.add_to_group("structures")

	# Main tent body (prism approximated with box)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(6.0, 2.5, 4.0)
	body.mesh = box
	body.position.y = 1.25
	var canvas_mat := StandardMaterial3D.new()
	canvas_mat.albedo_color = Color(0.5, 0.55, 0.4)  # OD green canvas
	body.material_override = canvas_mat
	hootch.add_child(body)

	# Sandbag base
	var base_mesh := MeshInstance3D.new()
	var base_box := BoxMesh.new()
	base_box.size = Vector3(7.0, 0.8, 5.0)
	base_mesh.mesh = base_box
	base_mesh.position.y = 0.4
	var sandbag_mat := StandardMaterial3D.new()
	sandbag_mat.albedo_color = Color(0.55, 0.50, 0.35)
	base_mesh.material_override = sandbag_mat
	hootch.add_child(base_mesh)

	# Collision
	var coll := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(6.0, 3.0, 4.0)
	coll.shape = shape
	coll.position.y = 1.5
	hootch.add_child(coll)

	hootch.position = Vector3(pos.x, base_y, pos.z)
	return hootch


## Spawn a cover object at position (sandbag wall)
static func spawn_cover_at(scene: Node3D, pos: Vector3) -> StaticBody3D:
	var terrain := scene.get_node_or_null("/root/TerrainIntegration")
	var base_y: float = 0.0
	if terrain and terrain.has_method("get_height_at"):
		base_y = terrain.get_height_at(pos)
	return _create_sandbag_wall(pos, base_y)


## Create a HUD overlay with a label that scene can update.
static func make_hud(scene: Node3D) -> Label:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	canvas.layer = 10
	scene.add_child(canvas)

	var label := Label.new()
	label.name = "InfoLabel"
	label.position = Vector2(20, 20)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 4)
	canvas.add_child(label)
	return label
