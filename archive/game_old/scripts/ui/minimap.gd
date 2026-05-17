extends SubViewportContainer
## Minimap - Top-down view of the battlefield
## Shows units, structures, fog of war, and intel markers

@export var map_size: Vector2 = Vector2(200, 200)
@export var update_interval: float = 0.1

# Colors
const COLOR_PLAYER_UNIT := Color(0.2, 0.8, 0.2)
const COLOR_ENEMY_UNIT := Color(0.8, 0.2, 0.2)
const COLOR_ENEMY_VISIBLE := Color(1.0, 0.2, 0.2)
const COLOR_STRUCTURE := Color(0.6, 0.6, 0.4)
const COLOR_LZ := Color(0.8, 0.5, 0.1)
const COLOR_CONVOY := Color(0.9, 0.7, 0.2)
const COLOR_HELICOPTER := Color(0.2, 0.6, 0.9)
const COLOR_INTEL_FRESH := Color(1.0, 0.3, 0.3)
const COLOR_INTEL_STALE := Color(0.5, 0.3, 0.3)
const COLOR_FOG := Color(0.1, 0.12, 0.1)
const COLOR_EXPLORED := Color(0.2, 0.25, 0.2)
const COLOR_VISIBLE := Color(0.3, 0.35, 0.25)

var viewport: SubViewport
var camera: Camera3D
var canvas: Control
var update_timer: float = 0.0

# Click handling
var main_camera: Camera3D


func _ready() -> void:
	viewport = $SubViewport if has_node("SubViewport") else null

	if viewport:
		_setup_minimap_camera()
		_setup_canvas()

	# Find main camera for click-to-focus
	await get_tree().process_frame
	main_camera = get_viewport().get_camera_3d()


func _setup_minimap_camera() -> void:
	camera = Camera3D.new()
	camera.name = "MinimapCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = max(map_size.x, map_size.y)
	camera.position = Vector3(map_size.x / 2, 100, map_size.y / 2)
	camera.rotation.x = -PI / 2  # Look straight down
	camera.far = 200
	camera.current = true
	viewport.add_child(camera)


func _setup_canvas() -> void:
	canvas = Control.new()
	canvas.name = "MinimapCanvas"
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	canvas.draw.connect(_on_canvas_draw)


func _process(delta: float) -> void:
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		if canvas:
			canvas.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_minimap_click(event.position)


func _handle_minimap_click(click_pos: Vector2) -> void:
	# Convert click position to world position
	var minimap_size := size
	var normalized := click_pos / minimap_size
	var world_pos := Vector3(
		normalized.x * map_size.x,
		0,
		normalized.y * map_size.y
	)

	# Move main camera to this position
	if main_camera and main_camera.has_method("focus_on"):
		main_camera.focus_on(world_pos)


func _on_canvas_draw() -> void:
	if not canvas:
		return

	var minimap_size := size

	# Draw background (fog)
	canvas.draw_rect(Rect2(Vector2.ZERO, minimap_size), COLOR_FOG)

	# Draw explored areas from IntelDirector
	_draw_fog_of_war(minimap_size)

	# Draw structures
	for structure in GameManager.structures:
		if is_instance_valid(structure):
			var pos := _world_to_minimap(structure.global_position, minimap_size)
			canvas.draw_rect(Rect2(pos - Vector2(3, 3), Vector2(6, 6)), COLOR_STRUCTURE)

	# Draw player units
	for squad in GameManager.player_squads:
		if is_instance_valid(squad):
			var pos := _world_to_minimap(squad.global_position, minimap_size)
			canvas.draw_circle(pos, 4, COLOR_PLAYER_UNIT)

	# Draw helicopters
	for heli_node: Node in get_tree().get_nodes_in_group("helicopters"):
		var heli := heli_node as Node3D
		if heli and is_instance_valid(heli):
			var pos := _world_to_minimap(heli.global_position, minimap_size)
			canvas.draw_circle(pos, 5, COLOR_HELICOPTER)

	# Draw convoys
	for convoy_node: Node in get_tree().get_nodes_in_group("convoys"):
		var convoy := convoy_node as Node3D
		if convoy and is_instance_valid(convoy):
			var pos := _world_to_minimap(convoy.global_position, minimap_size)
			canvas.draw_rect(Rect2(pos - Vector2(4, 2), Vector2(8, 4)), COLOR_CONVOY)

	# Draw visible enemies (from fog of war)
	var fog_renderer: Node = get_tree().current_scene.get_node_or_null("GameWorld/FogOfWar/FogOfWarRenderer")
	for enemy_node: Node in get_tree().get_nodes_in_group("enemy"):
		var enemy := enemy_node as Node3D
		if enemy and is_instance_valid(enemy):
			# Check if enemy is in visible area
			if fog_renderer and fog_renderer.is_position_visible(enemy.global_position):
				var pos := _world_to_minimap(enemy.global_position, minimap_size)
				canvas.draw_circle(pos, 3, COLOR_ENEMY_VISIBLE)

	# Draw enemy contacts from intel
	var contacts: Array = IntelDirector.get_all_contacts()
	for i: int in range(contacts.size()):
		var contact: Variant = contacts[i]
		var contact_pos: Vector3 = contact.position
		var contact_id: int = contact.id
		var contact_type: String = contact.contact_type
		var pos := _world_to_minimap(contact_pos, minimap_size)
		var color := COLOR_INTEL_STALE if IntelDirector.is_intel_stale(contact_id) else COLOR_INTEL_FRESH

		# Different shapes for different contact types
		match contact_type:
			"camp":
				canvas.draw_rect(Rect2(pos - Vector2(4, 4), Vector2(8, 8)), color, false, 2.0)
			"mortar", "aa":
				_draw_triangle(pos, 5, color)
			_:
				canvas.draw_circle(pos, 3, color)

	# Draw camera view frustum
	_draw_camera_view(minimap_size)


func _draw_fog_of_war(minimap_size: Vector2) -> void:
	# Draw explored cells
	var cell_size := minimap_size / (map_size / IntelDirector.fog_resolution)

	var explored_keys: Array = IntelDirector.explored_cells.keys()
	for i: int in range(explored_keys.size()):
		var cell: Vector2i = explored_keys[i]
		var world_pos := Vector3(
			cell.x * IntelDirector.fog_resolution,
			0,
			cell.y * IntelDirector.fog_resolution
		)
		var minimap_pos := _world_to_minimap(world_pos, minimap_size)

		var is_visible: bool = IntelDirector.visible_cells.get(cell, false)
		var color := COLOR_VISIBLE if is_visible else COLOR_EXPLORED
		canvas.draw_rect(Rect2(minimap_pos, cell_size), color)


func _draw_camera_view(minimap_size: Vector2) -> void:
	if not main_camera:
		return

	# Get camera position and approximate view bounds
	var cam_pos := main_camera.global_position
	var center := _world_to_minimap(Vector3(cam_pos.x, 0, cam_pos.z), minimap_size)

	# Approximate view size based on camera height
	var view_size := cam_pos.y * 0.8  # Rough approximation
	var half_size := _world_to_minimap(Vector3(view_size, 0, view_size), minimap_size) - _world_to_minimap(Vector3.ZERO, minimap_size)

	var rect := Rect2(center - half_size / 2, half_size)
	canvas.draw_rect(rect, Color.WHITE, false, 1.0)


func _draw_triangle(center: Vector2, size: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -size),
		center + Vector2(-size * 0.866, size * 0.5),
		center + Vector2(size * 0.866, size * 0.5)
	])
	canvas.draw_polygon(points, [color])


func _world_to_minimap(world_pos: Vector3, minimap_size: Vector2) -> Vector2:
	return Vector2(
		(world_pos.x / map_size.x) * minimap_size.x,
		(world_pos.z / map_size.y) * minimap_size.y
	)
