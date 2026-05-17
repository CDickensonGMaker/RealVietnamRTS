extends SubViewportContainer
class_name TacticalMinimap
## Tactical Minimap - Top-down view of the battlefield
## Shows units, structures, fog of war, LZs, and camera view
## Integrates with FogOfWar system and BattleSignals

const MilitaryTheme = preload("res://battle_system/ui/military_theme.gd")

# =============================================================================
# CONFIGURATION
# =============================================================================

@export var map_size: Vector2 = Vector2(1000, 1000)  # World units
@export var update_interval: float = 0.1  # Seconds between redraws

# =============================================================================
# MARKER COLORS (per requirements)
# =============================================================================

const COLOR_PLAYER_UNIT := Color(0.2, 0.8, 0.2)       # Green: Player units
const COLOR_ENEMY_KNOWN := Color(0.8, 0.2, 0.2)       # Red: Known enemies
const COLOR_HELICOPTER := Color(0.2, 0.6, 0.9)        # Blue: Helicopters
const COLOR_CONVOY := Color(0.9, 0.7, 0.2)            # Yellow: Convoys/transports
const COLOR_STRUCTURE := Color(0.5, 0.5, 0.5)         # Gray: Structures/buildings
const COLOR_LZ := Color(0.9, 0.5, 0.1)                # Orange: LZs

# Fog colors (military theme)
const COLOR_FOG_UNEXPLORED := Color(0.05, 0.06, 0.05, 0.95)
const COLOR_FOG_SHROUD := Color(0.12, 0.14, 0.10, 0.6)
const COLOR_FOG_VISIBLE := Color(0.2, 0.22, 0.18, 0.0)

# Camera frustum
const COLOR_CAMERA_FRUSTUM := Color(1.0, 1.0, 1.0, 0.8)

# =============================================================================
# STATE
# =============================================================================

var _viewport: SubViewport
var _camera: Camera3D
var _canvas: Control
var _update_timer: float = 0.0

# References
var _main_camera: Camera3D
var _fog_of_war: Node  # FogOfWar reference

# Unit tracking (populated via BattleSignals)
var _tracked_units: Dictionary = {}  # node_id -> {node, faction, type}

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_setup_viewport()
	_setup_canvas()
	_connect_signals()

	# Defer finding main camera until scene tree is ready
	await get_tree().process_frame
	_find_main_camera()
	_find_fog_of_war()
	_auto_detect_map_size()

	print("[TacticalMinimap] Initialized with map size: %s" % map_size)


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= update_interval:
		_update_timer = 0.0
		if _canvas:
			_canvas.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_handle_click(mouse_event.position)
			accept_event()


# =============================================================================
# SETUP
# =============================================================================

func _setup_viewport() -> void:
	# Check for existing SubViewport child or create one
	_viewport = get_node_or_null("SubViewport") as SubViewport
	if not _viewport:
		_viewport = SubViewport.new()
		_viewport.name = "SubViewport"
		add_child(_viewport)

	# Configure viewport
	_viewport.size = Vector2i(256, 256)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED

	# Create orthographic camera looking down
	_camera = Camera3D.new()
	_camera.name = "MinimapCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = maxf(map_size.x, map_size.y)
	_camera.position = Vector3(map_size.x / 2.0, 150.0, map_size.y / 2.0)
	_camera.rotation.x = -PI / 2.0  # Look straight down
	_camera.far = 300.0
	_camera.near = 0.1
	_camera.current = true
	_camera.cull_mask = 0  # Don't render 3D scene, we draw markers on canvas
	_viewport.add_child(_camera)


func _setup_canvas() -> void:
	# Create drawing canvas overlay
	_canvas = Control.new()
	_canvas.name = "MinimapCanvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.draw.connect(_on_canvas_draw)


func _connect_signals() -> void:
	# Connect to BattleSignals for unit tracking
	var battle_signals: Node = get_node_or_null("/root/BattleSignals")
	if battle_signals:
		if battle_signals.has_signal("unit_spawned"):
			battle_signals.unit_spawned.connect(_on_unit_spawned)
		if battle_signals.has_signal("unit_died"):
			battle_signals.unit_died.connect(_on_unit_died)
		if battle_signals.has_signal("helicopter_dispatched"):
			battle_signals.helicopter_dispatched.connect(_on_helicopter_dispatched)
		if battle_signals.has_signal("helicopter_destroyed"):
			battle_signals.helicopter_destroyed.connect(_on_helicopter_destroyed)
		if battle_signals.has_signal("convoy_departed"):
			battle_signals.convoy_departed.connect(_on_convoy_departed)
		if battle_signals.has_signal("convoy_arrived"):
			battle_signals.convoy_arrived.connect(_on_convoy_arrived)
	else:
		push_warning("[TacticalMinimap] BattleSignals autoload not found")


func _find_main_camera() -> void:
	_main_camera = get_viewport().get_camera_3d()
	if not _main_camera:
		push_warning("[TacticalMinimap] Main camera not found")


func _find_fog_of_war() -> void:
	# Search for FogOfWar node in scene
	_fog_of_war = _find_node_by_class("FogOfWar")
	if not _fog_of_war:
		# Try common paths
		var scene: Node = get_tree().current_scene
		if scene:
			_fog_of_war = scene.get_node_or_null("FogOfWar")
			if not _fog_of_war:
				_fog_of_war = scene.get_node_or_null("GameWorld/FogOfWar")


func _auto_detect_map_size() -> void:
	# Try to get map size from TerrainManager
	var terrain_manager: Node = get_node_or_null("/root/TerrainManager")
	if terrain_manager and "map_size" in terrain_manager:
		var size_val = terrain_manager.map_size
		if size_val is float:
			map_size = Vector2(size_val, size_val)
			print("[TacticalMinimap] Auto-detected map size from TerrainManager: %s" % map_size)
			return

	# Try TerrainIntegration
	var terrain_integration: Node = get_node_or_null("/root/TerrainIntegration")
	if terrain_integration:
		if terrain_integration.has_method("get_map_size"):
			var size_val = terrain_integration.get_map_size()
			if size_val is Vector2:
				map_size = size_val
			elif size_val is float:
				map_size = Vector2(size_val, size_val)
			print("[TacticalMinimap] Auto-detected map size from TerrainIntegration: %s" % map_size)
			return
		elif "map_size" in terrain_integration:
			var size_val = terrain_integration.map_size
			if size_val is float:
				map_size = Vector2(size_val, size_val)
				print("[TacticalMinimap] Auto-detected map size from TerrainIntegration: %s" % map_size)
				return

	# Try to get from main camera bounds
	if _main_camera and "map_bounds_max" in _main_camera:
		var bounds: Vector3 = _main_camera.map_bounds_max
		if bounds.x > 100 and bounds.z > 100:
			map_size = Vector2(bounds.x, bounds.z)
			print("[TacticalMinimap] Auto-detected map size from camera bounds: %s" % map_size)
			return


func _find_node_by_class(class_name_str: String) -> Node:
	var nodes: Array[Node] = get_tree().get_nodes_in_group("fog_of_war")
	if nodes.size() > 0:
		return nodes[0]

	# Fallback: search scene tree
	var root: Node = get_tree().current_scene
	if root:
		return _recursive_find_class(root, class_name_str)
	return null


func _recursive_find_class(node: Node, class_name_str: String) -> Node:
	if node.get_class() == class_name_str or node.name == class_name_str:
		return node
	for child in node.get_children():
		var result: Node = _recursive_find_class(child, class_name_str)
		if result:
			return result
	return null


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_unit_spawned(unit: Node3D, faction: int) -> void:
	if not is_instance_valid(unit):
		return
	var unit_type: String = _determine_unit_type(unit)
	_tracked_units[unit.get_instance_id()] = {
		"node": unit,
		"faction": faction,
		"type": unit_type,
	}


func _on_unit_died(unit: Node3D, _killer: Node3D) -> void:
	if is_instance_valid(unit):
		_tracked_units.erase(unit.get_instance_id())


func _on_helicopter_dispatched(helicopter: Node3D, _mission_name: String) -> void:
	if not is_instance_valid(helicopter):
		return
	_tracked_units[helicopter.get_instance_id()] = {
		"node": helicopter,
		"faction": 0,  # Assume player
		"type": "helicopter",
	}


func _on_helicopter_destroyed(helicopter: Node3D) -> void:
	if is_instance_valid(helicopter):
		_tracked_units.erase(helicopter.get_instance_id())


func _on_convoy_departed(convoy: Node3D) -> void:
	if not is_instance_valid(convoy):
		return
	_tracked_units[convoy.get_instance_id()] = {
		"node": convoy,
		"faction": 0,  # Assume player
		"type": "convoy",
	}


func _on_convoy_arrived(convoy: Node3D, _destination: Node3D) -> void:
	if is_instance_valid(convoy):
		_tracked_units.erase(convoy.get_instance_id())


func _determine_unit_type(unit: Node3D) -> String:
	if unit.is_in_group("helicopters"):
		return "helicopter"
	if unit.is_in_group("convoys"):
		return "convoy"
	if unit.is_in_group("structures") or unit.is_in_group("buildings"):
		return "structure"
	if unit.is_in_group("lz") or unit.is_in_group("landing_zones"):
		return "lz"
	return "infantry"


# =============================================================================
# CLICK HANDLING
# =============================================================================

func _handle_click(click_pos: Vector2) -> void:
	var minimap_size: Vector2 = size
	if minimap_size.x <= 0 or minimap_size.y <= 0:
		return

	# Convert click to world position
	var normalized: Vector2 = click_pos / minimap_size
	var world_pos := Vector3(
		normalized.x * map_size.x,
		0.0,
		normalized.y * map_size.y
	)

	# Move main camera to clicked position
	if _main_camera:
		if _main_camera.has_method("focus_on"):
			_main_camera.focus_on(world_pos)
		elif _main_camera.has_method("set_focus_position"):
			_main_camera.set_focus_position(world_pos)
		else:
			# Direct position update (preserve height)
			var cam_height: float = _main_camera.global_position.y
			_main_camera.global_position = Vector3(world_pos.x, cam_height, world_pos.z)

	print("[TacticalMinimap] Camera focused on: %s" % world_pos)


# =============================================================================
# DRAWING
# =============================================================================

func _on_canvas_draw() -> void:
	if not _canvas:
		return

	var minimap_size: Vector2 = size
	if minimap_size.x <= 0 or minimap_size.y <= 0:
		return

	# Draw background
	_canvas.draw_rect(Rect2(Vector2.ZERO, minimap_size), COLOR_FOG_UNEXPLORED)

	# Draw fog of war overlay
	_draw_fog_of_war(minimap_size)

	# Draw structures (gray)
	_draw_structures(minimap_size)

	# Draw LZs (orange)
	_draw_lzs(minimap_size)

	# Draw convoys (yellow)
	_draw_convoys(minimap_size)

	# Draw player units (green)
	_draw_player_units(minimap_size)

	# Draw known enemies (red)
	_draw_enemies(minimap_size)

	# Draw helicopters (blue)
	_draw_helicopters(minimap_size)

	# Draw camera frustum (white rectangle)
	_draw_camera_frustum(minimap_size)

	# Draw border
	_canvas.draw_rect(Rect2(Vector2.ZERO, minimap_size), MilitaryTheme.COL_PANEL_BORDER, false, 2.0)


func _draw_fog_of_war(minimap_size: Vector2) -> void:
	if not _fog_of_war:
		return

	# Get fog texture info
	if not _fog_of_war.has_method("get_fog_state"):
		return

	var texture_size: int = 32  # Sample at lower resolution for performance
	var cell_width: float = minimap_size.x / float(texture_size)
	var cell_height: float = minimap_size.y / float(texture_size)
	var world_cell_x: float = map_size.x / float(texture_size)
	var world_cell_y: float = map_size.y / float(texture_size)

	for y in range(texture_size):
		for x in range(texture_size):
			var world_pos := Vector3(
				(float(x) + 0.5) * world_cell_x,
				0.0,
				(float(y) + 0.5) * world_cell_y
			)

			var fog_state: int = _fog_of_war.get_fog_state(world_pos)
			var color: Color

			match fog_state:
				0:  # UNEXPLORED
					color = COLOR_FOG_UNEXPLORED
				1:  # SHROUD
					color = COLOR_FOG_SHROUD
				2:  # VISIBLE
					color = COLOR_FOG_VISIBLE
				_:
					color = COLOR_FOG_UNEXPLORED

			if color.a > 0.01:
				var rect := Rect2(
					Vector2(float(x) * cell_width, float(y) * cell_height),
					Vector2(cell_width + 1.0, cell_height + 1.0)  # +1 to prevent gaps
				)
				_canvas.draw_rect(rect, color)


func _draw_structures(minimap_size: Vector2) -> void:
	# Draw from tracked units
	for data in _tracked_units.values():
		if data.type != "structure":
			continue
		var node: Node3D = data.node as Node3D
		if not is_instance_valid(node):
			continue
		if not _is_visible_to_player(node.global_position):
			continue
		var pos: Vector2 = _world_to_minimap(node.global_position, minimap_size)
		_canvas.draw_rect(Rect2(pos - Vector2(3, 3), Vector2(6, 6)), COLOR_STRUCTURE)

	# Also check structure groups
	for node in get_tree().get_nodes_in_group("structures"):
		var structure: Node3D = node as Node3D
		if not structure or not is_instance_valid(structure):
			continue
		if not _is_visible_to_player(structure.global_position):
			continue
		var pos: Vector2 = _world_to_minimap(structure.global_position, minimap_size)
		_canvas.draw_rect(Rect2(pos - Vector2(3, 3), Vector2(6, 6)), COLOR_STRUCTURE)


func _draw_lzs(minimap_size: Vector2) -> void:
	# Draw LZs from groups
	for group_name in ["lz", "landing_zones", "helipads"]:
		for node in get_tree().get_nodes_in_group(group_name):
			var lz: Node3D = node as Node3D
			if not lz or not is_instance_valid(lz):
				continue
			var pos: Vector2 = _world_to_minimap(lz.global_position, minimap_size)
			# Draw diamond shape for LZ
			_draw_diamond(pos, 5.0, COLOR_LZ)


func _draw_convoys(minimap_size: Vector2) -> void:
	# From tracked units
	for data in _tracked_units.values():
		if data.type != "convoy":
			continue
		var node: Node3D = data.node as Node3D
		if not is_instance_valid(node):
			continue
		var pos: Vector2 = _world_to_minimap(node.global_position, minimap_size)
		_canvas.draw_rect(Rect2(pos - Vector2(4, 2), Vector2(8, 4)), COLOR_CONVOY)

	# Also check convoy groups
	for node in get_tree().get_nodes_in_group("convoys"):
		var convoy: Node3D = node as Node3D
		if not convoy or not is_instance_valid(convoy):
			continue
		var pos: Vector2 = _world_to_minimap(convoy.global_position, minimap_size)
		_canvas.draw_rect(Rect2(pos - Vector2(4, 2), Vector2(8, 4)), COLOR_CONVOY)


func _draw_player_units(minimap_size: Vector2) -> void:
	# Get player faction (0 = US_ARMY, 1 = ARVN are friendly)
	var friendly_factions: Array[int] = [0, 1]

	# From tracked units
	for data in _tracked_units.values():
		if data.type in ["structure", "helicopter", "convoy", "lz"]:
			continue
		if not data.faction in friendly_factions:
			continue
		var node: Node3D = data.node as Node3D
		if not is_instance_valid(node):
			continue
		var pos: Vector2 = _world_to_minimap(node.global_position, minimap_size)
		_canvas.draw_circle(pos, 4.0, COLOR_PLAYER_UNIT)

	# Also check squad groups
	for node in get_tree().get_nodes_in_group("player_units"):
		var unit: Node3D = node as Node3D
		if not unit or not is_instance_valid(unit):
			continue
		var pos: Vector2 = _world_to_minimap(unit.global_position, minimap_size)
		_canvas.draw_circle(pos, 4.0, COLOR_PLAYER_UNIT)

	for node in get_tree().get_nodes_in_group("friendly"):
		var unit: Node3D = node as Node3D
		if not unit or not is_instance_valid(unit):
			continue
		var pos: Vector2 = _world_to_minimap(unit.global_position, minimap_size)
		_canvas.draw_circle(pos, 4.0, COLOR_PLAYER_UNIT)


func _draw_enemies(minimap_size: Vector2) -> void:
	# Enemy factions (2 = VC, 3 = NVA)
	var enemy_factions: Array[int] = [2, 3]

	# From tracked units
	for data in _tracked_units.values():
		if data.type in ["structure", "helicopter", "convoy", "lz"]:
			continue
		if not data.faction in enemy_factions:
			continue
		var node: Node3D = data.node as Node3D
		if not is_instance_valid(node):
			continue
		# Only show if visible to player
		if not _is_visible_to_player(node.global_position):
			continue
		var pos: Vector2 = _world_to_minimap(node.global_position, minimap_size)
		_canvas.draw_circle(pos, 3.0, COLOR_ENEMY_KNOWN)

	# Also check enemy groups
	for group_name in ["enemy", "enemies", "vc", "nva"]:
		for node in get_tree().get_nodes_in_group(group_name):
			var enemy: Node3D = node as Node3D
			if not enemy or not is_instance_valid(enemy):
				continue
			# Only show if visible to player
			if not _is_visible_to_player(enemy.global_position):
				continue
			var pos: Vector2 = _world_to_minimap(enemy.global_position, minimap_size)
			_canvas.draw_circle(pos, 3.0, COLOR_ENEMY_KNOWN)


func _draw_helicopters(minimap_size: Vector2) -> void:
	# From tracked units
	for data in _tracked_units.values():
		if data.type != "helicopter":
			continue
		var node: Node3D = data.node as Node3D
		if not is_instance_valid(node):
			continue
		var pos: Vector2 = _world_to_minimap(node.global_position, minimap_size)
		# Draw helicopter as filled circle with ring
		_canvas.draw_circle(pos, 5.0, COLOR_HELICOPTER)
		_canvas.draw_arc(pos, 6.0, 0.0, TAU, 16, COLOR_HELICOPTER, 1.5)

	# Also check helicopter groups
	for node in get_tree().get_nodes_in_group("helicopters"):
		var heli: Node3D = node as Node3D
		if not heli or not is_instance_valid(heli):
			continue
		var pos: Vector2 = _world_to_minimap(heli.global_position, minimap_size)
		_canvas.draw_circle(pos, 5.0, COLOR_HELICOPTER)
		_canvas.draw_arc(pos, 6.0, 0.0, TAU, 16, COLOR_HELICOPTER, 1.5)


func _draw_camera_frustum(minimap_size: Vector2) -> void:
	if not _main_camera:
		return

	var cam_pos: Vector3 = _main_camera.global_position
	var center: Vector2 = _world_to_minimap(Vector3(cam_pos.x, 0.0, cam_pos.z), minimap_size)

	# Estimate view size based on camera height and FOV
	var view_size_world: float
	if _main_camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		view_size_world = _main_camera.size
	else:
		# Perspective: estimate based on height
		view_size_world = cam_pos.y * 2.0 * tan(deg_to_rad(_main_camera.fov / 2.0))

	# Convert to minimap scale
	var half_size: Vector2 = Vector2(
		(view_size_world / map_size.x) * minimap_size.x * 0.5,
		(view_size_world / map_size.y) * minimap_size.y * 0.5
	)

	# Clamp to reasonable bounds
	half_size = half_size.clamp(Vector2(10, 10), minimap_size * 0.5)

	var rect := Rect2(center - half_size, half_size * 2.0)
	_canvas.draw_rect(rect, COLOR_CAMERA_FRUSTUM, false, 1.5)


func _draw_diamond(center: Vector2, size: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -size),      # Top
		center + Vector2(size, 0),       # Right
		center + Vector2(0, size),       # Bottom
		center + Vector2(-size, 0),      # Left
	])
	_canvas.draw_polygon(points, [color])


# =============================================================================
# UTILITY
# =============================================================================

func _world_to_minimap(world_pos: Vector3, minimap_size: Vector2) -> Vector2:
	return Vector2(
		(world_pos.x / map_size.x) * minimap_size.x,
		(world_pos.z / map_size.y) * minimap_size.y
	)


func _is_visible_to_player(world_pos: Vector3) -> bool:
	if not _fog_of_war:
		return true  # No fog, everything visible

	if _fog_of_war.has_method("is_position_visible"):
		return _fog_of_war.is_position_visible(world_pos)

	if _fog_of_war.has_method("get_fog_state"):
		var state: int = _fog_of_war.get_fog_state(world_pos)
		return state == 2  # FogState.VISIBLE

	return true


# =============================================================================
# PUBLIC API
# =============================================================================

## Set the world map size
func set_map_size(new_size: Vector2) -> void:
	map_size = new_size
	if _camera:
		_camera.size = maxf(map_size.x, map_size.y)
		_camera.position = Vector3(map_size.x / 2.0, 150.0, map_size.y / 2.0)


## Set reference to the FogOfWar system
func set_fog_of_war(fog: Node) -> void:
	_fog_of_war = fog


## Set reference to the main camera
func set_main_camera(camera: Camera3D) -> void:
	_main_camera = camera


## Register a unit manually (alternative to BattleSignals)
func register_unit(unit: Node3D, faction: int, unit_type: String = "infantry") -> void:
	if not is_instance_valid(unit):
		return
	_tracked_units[unit.get_instance_id()] = {
		"node": unit,
		"faction": faction,
		"type": unit_type,
	}


## Unregister a unit manually
func unregister_unit(unit: Node3D) -> void:
	if is_instance_valid(unit):
		_tracked_units.erase(unit.get_instance_id())


## Force a redraw
func refresh() -> void:
	if _canvas:
		_canvas.queue_redraw()
