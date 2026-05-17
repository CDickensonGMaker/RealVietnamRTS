extends Node
## PatrolSystem - Handles patrol route drawing and management
## Allows player to draw waypoint paths on the map

signal patrol_started(squad: Node3D)
signal patrol_waypoint_added(position: Vector3)
signal patrol_completed(squad: Node3D, waypoints: Array)
signal patrol_cancelled

# State
var is_drawing: bool = false
var current_waypoints: Array[Vector3] = []
var selected_squad: Node3D = null

# Visual
var waypoint_markers: Array[Node3D] = []
var line_renderer: ImmediateMesh
var line_mesh_instance: MeshInstance3D

# References
var camera: Camera3D
var selection_manager: Node

# Settings
@export var min_waypoint_distance: float = 5.0
@export var max_waypoints: int = 10
@export var waypoint_color := Color(0.2, 0.8, 0.2)
@export var line_color := Color(0.2, 0.8, 0.2, 0.7)


func _ready() -> void:
	_setup_line_renderer()

	await get_tree().process_frame
	camera = get_viewport().get_camera_3d()
	selection_manager = get_node_or_null("/root/Main/SelectionManager")


func _setup_line_renderer() -> void:
	line_mesh_instance = MeshInstance3D.new()
	line_mesh_instance.name = "PatrolLineRenderer"

	line_renderer = ImmediateMesh.new()
	line_mesh_instance.mesh = line_renderer

	var material := StandardMaterial3D.new()
	material.albedo_color = line_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mesh_instance.material_override = material

	add_child(line_mesh_instance)


func _unhandled_input(event: InputEvent) -> void:
	# Start patrol mode with P key when units selected
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_P:
			_toggle_patrol_mode()
		elif event.keycode == KEY_ESCAPE and is_drawing:
			cancel_patrol()

	# Add waypoints while drawing
	if is_drawing:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_add_waypoint_at_mouse()
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_finish_patrol()


func _process(_delta: float) -> void:
	if is_drawing:
		_update_line_preview()


func _toggle_patrol_mode() -> void:
	if is_drawing:
		cancel_patrol()
		return

	# Check if we have selected squads
	if not selection_manager:
		return

	var selected: Array = selection_manager.get_selected_units()
	if selected.is_empty():
		return

	# Start patrol drawing
	selected_squad = selected[0] as Node3D
	is_drawing = true
	current_waypoints.clear()

	# Add squad's current position as first waypoint
	current_waypoints.append(selected_squad.global_position)
	_create_waypoint_marker(selected_squad.global_position)

	patrol_started.emit(selected_squad)


func _add_waypoint_at_mouse() -> void:
	if not camera:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse_pos)
	var to := from + camera.project_ray_normal(mouse_pos) * 500.0

	# Raycast to ground
	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)  # Terrain layer
	var result := space_state.intersect_ray(query)

	if result:
		var pos: Vector3 = result.position

		# Check minimum distance from last waypoint
		if not current_waypoints.is_empty():
			var last := current_waypoints[-1]
			if pos.distance_to(last) < min_waypoint_distance:
				return

		# Check max waypoints
		if current_waypoints.size() >= max_waypoints:
			return

		current_waypoints.append(pos)
		_create_waypoint_marker(pos)
		patrol_waypoint_added.emit(pos)


func _create_waypoint_marker(pos: Vector3) -> void:
	var marker := CSGSphere3D.new()
	marker.radius = 0.5
	marker.material = StandardMaterial3D.new()
	(marker.material as StandardMaterial3D).albedo_color = waypoint_color
	(marker.material as StandardMaterial3D).emission_enabled = true
	(marker.material as StandardMaterial3D).emission = waypoint_color
	marker.global_position = pos + Vector3(0, 0.5, 0)

	add_child(marker)
	waypoint_markers.append(marker)

	# Add number label
	var label := Label3D.new()
	label.text = str(waypoint_markers.size())
	label.font_size = 48
	label.position = Vector3(0, 1, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.add_child(label)


func _update_line_preview() -> void:
	line_renderer.clear_surfaces()

	if current_waypoints.size() < 2:
		return

	line_renderer.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)

	for wp in current_waypoints:
		line_renderer.surface_add_vertex(wp + Vector3(0, 0.5, 0))

	# Add preview line to mouse position
	if camera:
		var mouse_pos := get_viewport().get_mouse_position()
		var from := camera.project_ray_origin(mouse_pos)
		var to := from + camera.project_ray_normal(mouse_pos) * 500.0

		var plane := Plane(Vector3.UP, 0)
		var intersection_result: Variant = plane.intersects_ray(from, to - from)
		if intersection_result:
			var intersection: Vector3 = intersection_result as Vector3
			line_renderer.surface_add_vertex(intersection + Vector3(0, 0.5, 0))

	# Close the loop (connect last to first)
	if current_waypoints.size() > 1:
		line_renderer.surface_add_vertex(current_waypoints[0] + Vector3(0, 0.5, 0))

	line_renderer.surface_end()


func _finish_patrol() -> void:
	if current_waypoints.size() < 2:
		cancel_patrol()
		return

	# Assign patrol to squad
	if selected_squad and selected_squad.has_method("set_patrol_route"):
		# Remove first waypoint (current position)
		var route: Array[Vector3] = []
		for i in range(1, current_waypoints.size()):
			route.append(current_waypoints[i])

		selected_squad.set_patrol_route(route)
		patrol_completed.emit(selected_squad, route)

	_cleanup_drawing()


func cancel_patrol() -> void:
	_cleanup_drawing()
	patrol_cancelled.emit()


func _cleanup_drawing() -> void:
	is_drawing = false
	current_waypoints.clear()
	selected_squad = null

	# Remove waypoint markers
	for marker in waypoint_markers:
		marker.queue_free()
	waypoint_markers.clear()

	# Clear line
	line_renderer.clear_surfaces()


func get_active_patrols() -> Dictionary:
	## Returns dictionary of squad -> waypoints for all patrolling units
	var patrols := {}

	for squad in GameManager.player_squads:
		if is_instance_valid(squad) and squad.has_method("get"):
			var waypoints = squad.get("patrol_waypoints")
			if waypoints and not waypoints.is_empty():
				patrols[squad] = waypoints

	return patrols
