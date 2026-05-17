extends Node
## Move Order Handler - Processes right-click move and attack commands
## Works with SelectionManager to move/attack with selected units

const Squad = preload("res://battle_system/nodes/squad.gd")
const MoveMarkerManager = preload("res://battle_system/ui/move_marker_manager.gd")

## Attack-move mode: units move toward target while engaging enemies in range
var _attack_move_pending: bool = false

## Move marker manager reference
var _marker_manager: Node = null

## Emitted when attack-move mode changes
signal attack_move_mode_changed(enabled: bool)


func _ready() -> void:
	# Create marker manager
	_marker_manager = MoveMarkerManager.new()
	_marker_manager.name = "MoveMarkerManager"
	add_child(_marker_manager)
	print("[MoveOrderHandler] Initialized with move markers")


func _input(event: InputEvent) -> void:
	# A key toggles attack-move mode
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_A:
			_attack_move_pending = not _attack_move_pending
			attack_move_mode_changed.emit(_attack_move_pending)
			if _attack_move_pending:
				print("[MoveOrderHandler] Attack-move mode ENABLED (click to issue)")
			else:
				print("[MoveOrderHandler] Attack-move mode DISABLED")
			return
		# Escape cancels attack-move mode
		if event.keycode == KEY_ESCAPE and _attack_move_pending:
			_attack_move_pending = false
			attack_move_mode_changed.emit(false)
			print("[MoveOrderHandler] Attack-move mode CANCELLED")
			return

	# Right-click to issue move/attack order
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click(event.position)


func _handle_right_click(screen_pos: Vector2) -> void:
	# Check if we have selected units (access autoload safely)
	var sel_mgr: Node = get_node_or_null("/root/SelectionManager")
	if not sel_mgr or not sel_mgr.has_selection():
		return

	var selected: Array[Node3D] = sel_mgr.get_selected_units()

	# First, check if clicking on an enemy unit
	var enemy_target: Node3D = _raycast_enemy(screen_pos, selected)
	if enemy_target:
		_issue_attack_orders(selected, enemy_target)
		return

	# Get target position
	var target: Vector3 = _raycast_ground(screen_pos)
	if target == Vector3.INF:
		return

	# Check for Shift+Right-Click = clearing order (engineers only)
	if Input.is_key_pressed(KEY_SHIFT):
		if _issue_clearing_orders(selected, target):
			return  # Clearing orders issued

	# Check for attack-move mode
	if _attack_move_pending:
		_issue_attack_move_orders(selected, target)
		_attack_move_pending = false
		attack_move_mode_changed.emit(false)
		return

	# Otherwise, issue move orders
	_issue_move_orders(selected, target)


func _issue_attack_orders(units: Array[Node3D], enemy: Node3D) -> void:
	"""Issue attack orders to all selected units"""
	for unit in units:
		if not is_instance_valid(unit):
			continue
		# Only player units can receive attack orders
		if unit.has_method("get") and unit.get("is_player_controlled"):
			if not unit.is_player_controlled:
				continue
		if unit.has_method("attack"):
			unit.attack(enemy)
			print("[MoveOrderHandler] %s attacking %s" % [unit.name, enemy.name])
		elif unit.has_method("move_to"):
			# Fallback: move toward enemy
			unit.move_to(enemy.global_position)


func _issue_move_orders(units: Array[Node3D], target: Vector3) -> void:
	"""Issue move orders to all selected units"""
	# Stop any current attacks
	for unit in units:
		if unit.has_method("stop_attack"):
			unit.stop_attack()

	# Calculate formation positions for multiple units
	var positions: Array[Vector3] = _calculate_formation_positions(target, units.size())

	for i in units.size():
		var unit: Node3D = units[i]
		if unit.has_method("move_to"):
			var move_pos: Vector3 = positions[i] if i < positions.size() else target
			unit.move_to(move_pos)
			print("[MoveOrderHandler] %s moving to %s" % [unit.name, move_pos])

	# Spawn move markers at formation positions
	_spawn_move_markers(positions, false)


func _issue_attack_move_orders(units: Array[Node3D], target: Vector3) -> void:
	"""Issue attack-move orders to all selected units (move while engaging enemies)"""
	# Calculate formation positions for multiple units
	var positions: Array[Vector3] = _calculate_formation_positions(target, units.size())

	for i in units.size():
		var unit: Node3D = units[i]
		var move_pos: Vector3 = positions[i] if i < positions.size() else target

		if unit.has_method("attack_move_to"):
			unit.attack_move_to(move_pos)
			print("[MoveOrderHandler] %s attack-moving to %s" % [unit.name, move_pos])
		elif unit.has_method("move_to"):
			# Fallback: regular move if attack_move_to not implemented
			unit.move_to(move_pos)
			print("[MoveOrderHandler] %s moving to %s (attack-move not supported)" % [unit.name, move_pos])

	# Spawn attack-move markers (orange color)
	_spawn_move_markers(positions, true)


func _issue_clearing_orders(units: Array[Node3D], target: Vector3) -> bool:
	"""Issue clearing orders to engineer units. Returns true if any orders were issued."""
	var orders_issued: bool = false

	# Check if target has vegetation to clear
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_vegetation_density"):
		var density: float = terrain.get_vegetation_density(target)
		if density < 0.2:
			print("[MoveOrderHandler] Target already cleared (density: %.2f)" % density)
			return false

	for unit in units:
		if not is_instance_valid(unit):
			continue

		# Only player-controlled engineers can clear
		if unit.has_method("get") and unit.get("is_player_controlled"):
			if not unit.is_player_controlled:
				continue

		# Check if unit can clear (has can_build capability)
		if unit.has_method("can_clear") and unit.can_clear():
			if unit.has_method("start_clearing"):
				# Stop any other activities
				if unit.has_method("stop_attack"):
					unit.stop_attack()
				if unit.has_method("stop_clearing"):
					unit.stop_clearing()

				unit.start_clearing(target, 15.0)  # 15m clearing radius
				orders_issued = true
				print("[MoveOrderHandler] %s clearing at %s" % [unit.name, target])

	return orders_issued


func _raycast_enemy(screen_pos: Vector2, selected_units: Array[Node3D]) -> Node3D:
	"""Raycast to find enemy unit under cursor"""
	var camera: Camera3D = _get_camera()
	if not camera:
		return null

	var viewport: Viewport = get_viewport()
	var world_3d: World3D = viewport.get_world_3d() if viewport else null
	if not world_3d:
		return null

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var ray_end: Vector3 = ray_origin + ray_dir * 1000

	var space: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	# Check unit layers (2=US, 4=VC, 8=NVA)
	query.collision_mask = 2 | 4 | 8
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var result: Dictionary = space.intersect_ray(query)
	if result and result.has("collider"):
		var hit: Node = result.collider
		# Walk up to find the squad node
		var squad: Node3D = _find_squad_parent(hit)
		if squad:
			# Check if it's an enemy (not in our selection and different faction)
			if squad not in selected_units:
				# Check if enemy faction
				if squad.has_method("get") and squad.get("is_player_controlled") != null:
					if not squad.is_player_controlled:
						return squad
				# Also check if it's in enemy_units group
				if squad.is_in_group("enemy_units"):
					return squad

	return null


func _find_squad_parent(node: Node) -> Node3D:
	"""Walk up the tree to find a Squad node"""
	var current: Node = node
	while current:
		if current is CharacterBody3D and current.has_method("attack"):
			return current as Node3D
		if current.is_in_group("all_units"):
			return current as Node3D
		current = current.get_parent()
	return null


func _raycast_ground(screen_pos: Vector2) -> Vector3:
	var camera: Camera3D = _get_camera()
	if not camera:
		return Vector3.INF

	var viewport: Viewport = get_viewport()
	var world_3d: World3D = viewport.get_world_3d() if viewport else null
	if not world_3d:
		return Vector3.INF

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var ray_end: Vector3 = ray_origin + ray_dir * 1000

	var space: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1  # Terrain layer only

	var result: Dictionary = space.intersect_ray(query)
	if result:
		return result.position

	# Fallback: intersect with Y=0 plane
	if ray_dir.y != 0:
		var t: float = -ray_origin.y / ray_dir.y
		if t > 0:
			return ray_origin + ray_dir * t

	return Vector3.INF


func _calculate_formation_positions(center: Vector3, count: int) -> Array[Vector3]:
	"""Calculate spread positions for multiple units in a line formation"""
	var positions: Array[Vector3] = []

	if count <= 1:
		positions.append(center)
		return positions

	var spacing: float = 2.5  # Meters between units
	var total_width: float = spacing * (count - 1)
	var start_x: float = -total_width / 2.0

	for i in count:
		var offset := Vector3(start_x + i * spacing, 0, 0)
		positions.append(center + offset)

	return positions


func _get_camera() -> Camera3D:
	var cameras: Array[Node] = get_tree().get_nodes_in_group("battle_camera")
	return cameras[0] as Camera3D if cameras.size() > 0 else null


func _spawn_move_markers(positions: Array[Vector3], is_attack_move: bool) -> void:
	"""Spawn Steel Division style move markers at destination positions"""
	if not _marker_manager:
		return

	for pos in positions:
		_marker_manager.spawn_marker(pos, true, is_attack_move)
