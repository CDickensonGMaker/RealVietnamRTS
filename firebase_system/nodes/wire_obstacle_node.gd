class_name WireObstacleNode
extends Area3D
## WireObstacleNode - Barbed/concertina wire obstacle
##
## Wire obstacles:
## - Slow down enemies passing through
## - Deal damage over time to enemies
## - Are faction-aware (don't hurt friendlies)
## - Can be destroyed by sappers or explosives

signal wire_placed()
signal wire_progress(progress: float)
signal wire_complete()
signal enemy_damaged(enemy: Node3D, damage: float)
signal wire_destroyed()

## Faction that owns this wire (enemies will be damaged)
@export var owner_faction: int = 0  # GameEnums.Faction.US_ARMY

## Wire type affects damage and slowdown
enum WireType { BARBED, CONCERTINA, TRIPLE_CONCERTINA }
@export var wire_type: WireType = WireType.BARBED

## Wire dimensions
@export var length: float = 6.0
@export var width: float = 2.0

## Stats based on wire type
const WIRE_STATS: Dictionary = {
	WireType.BARBED: {"damage_per_sec": 2.0, "slowdown": 0.7, "health": 50.0},
	WireType.CONCERTINA: {"damage_per_sec": 4.0, "slowdown": 0.8, "health": 75.0},
	WireType.TRIPLE_CONCERTINA: {"damage_per_sec": 6.0, "slowdown": 0.9, "health": 100.0},
}

## Current placement progress (0.0 to 1.0)
var current_progress: float = 0.0

## Whether placement has started
var is_placing: bool = false

## Whether wire is complete
var is_complete: bool = false

## Current health
var health: float = 50.0
var max_health: float = 50.0

## Units currently in the wire
var units_inside: Array[Node3D] = []

## Visual components
var wire_mesh: MeshInstance3D
var post_mesh: MeshInstance3D
var outline_mesh: MeshInstance3D

## Collision shape
var collision_shape: CollisionShape3D
var box_shape: BoxShape3D

## Materials
var _wire_material: StandardMaterial3D
var _post_material: StandardMaterial3D
var _outline_material: StandardMaterial3D

## Damage tick timer
var _damage_timer: float = 0.0
const DAMAGE_INTERVAL: float = 0.5


func _ready() -> void:
	# Set up collision layers
	# Layer 7 = buildings (bit 64)
	collision_layer = 64
	collision_mask = 2 | 4 | 8  # Detect US, VC, NVA units

	# Add to groups
	add_to_group("wire_obstacles")
	add_to_group("obstacles")

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Initialize stats from wire type
	var stats: Dictionary = WIRE_STATS.get(wire_type, WIRE_STATS[WireType.BARBED])
	max_health = stats.health
	health = max_health

	# Create collision shape
	_setup_collision()

	# Create visuals
	_setup_visuals()

	# Snap to terrain
	_snap_to_terrain()


func _process(delta: float) -> void:
	if not is_complete or units_inside.is_empty():
		return

	# Damage enemies periodically
	_damage_timer += delta
	if _damage_timer >= DAMAGE_INTERVAL:
		_damage_timer = 0.0
		_damage_enemies()


func _setup_collision() -> void:
	collision_shape = CollisionShape3D.new()
	box_shape = BoxShape3D.new()
	box_shape.size = Vector3(length, 1.0, width)
	collision_shape.shape = box_shape
	collision_shape.position.y = 0.5
	add_child(collision_shape)


func _setup_visuals() -> void:
	# Wire material (rusty metal)
	_wire_material = StandardMaterial3D.new()
	_wire_material.albedo_color = Color(0.4, 0.35, 0.3)
	_wire_material.metallic = 0.7
	_wire_material.roughness = 0.6

	# Post material (wood)
	_post_material = StandardMaterial3D.new()
	_post_material.albedo_color = Color(0.45, 0.35, 0.25)
	_post_material.metallic = 0.0
	_post_material.roughness = 0.9

	# Create wire mesh (starts invisible)
	wire_mesh = MeshInstance3D.new()
	wire_mesh.material_override = _wire_material
	wire_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	wire_mesh.visible = false
	add_child(wire_mesh)

	# Create post mesh
	post_mesh = MeshInstance3D.new()
	post_mesh.material_override = _post_material
	post_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	post_mesh.visible = false
	add_child(post_mesh)

	# Outline material
	_outline_material = StandardMaterial3D.new()
	_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_material.albedo_color = Color(0.6, 0.2, 0.2, 0.5)
	_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Create outline
	outline_mesh = MeshInstance3D.new()
	outline_mesh.mesh = _create_outline_mesh()
	outline_mesh.material_override = _outline_material
	outline_mesh.position.y = 0.05
	add_child(outline_mesh)


func _snap_to_terrain() -> void:
	var terrain: Node = get_node_or_null("/root/UnifiedTerrain")
	if terrain and terrain.has_method("get_height_at"):
		position.y = terrain.get_height_at(global_position)
		return

	var terrain_intg: Node = get_node_or_null("/root/TerrainIntegration")
	if terrain_intg and terrain_intg.has_method("get_height_at"):
		position.y = terrain_intg.get_height_at(global_position)


func _on_body_entered(body: Node3D) -> void:
	if not is_complete:
		return

	if body.is_in_group("all_units") or body.is_in_group("squads"):
		if body not in units_inside:
			units_inside.append(body)
			_apply_slowdown(body, true)


func _on_body_exited(body: Node3D) -> void:
	if body in units_inside:
		units_inside.erase(body)
		_apply_slowdown(body, false)


func _apply_slowdown(unit: Node3D, entering: bool) -> void:
	## Apply or remove slowdown from unit
	var stats: Dictionary = WIRE_STATS.get(wire_type, WIRE_STATS[WireType.BARBED])
	var slowdown_mult: float = 1.0 - stats.slowdown  # Convert to multiplier

	if unit.has_method("set_movement_modifier"):
		if entering:
			unit.set_movement_modifier(slowdown_mult)
		else:
			unit.set_movement_modifier(1.0)
	elif "movement_speed_modifier" in unit:
		unit.movement_speed_modifier = slowdown_mult if entering else 1.0


func _damage_enemies() -> void:
	## Damage enemy units inside the wire
	var stats: Dictionary = WIRE_STATS.get(wire_type, WIRE_STATS[WireType.BARBED])
	var damage: float = stats.damage_per_sec * DAMAGE_INTERVAL

	for unit in units_inside:
		if not is_instance_valid(unit):
			continue

		# Check if enemy
		if not _is_enemy(unit):
			continue

		# Apply damage
		if unit.has_method("take_damage"):
			unit.take_damage(damage, self)
			enemy_damaged.emit(unit, damage)
		elif "health" in unit:
			unit.health -= damage
			enemy_damaged.emit(unit, damage)


func _is_enemy(unit: Node3D) -> bool:
	## Check if unit is enemy to wire owner
	var unit_faction: int = -1

	if unit.has_method("get_faction"):
		unit_faction = unit.get_faction()
	elif "faction" in unit:
		unit_faction = unit.faction
	elif "data" in unit and unit.data and "faction" in unit.data:
		unit_faction = unit.data.faction
	else:
		return false  # Can't determine faction, don't damage

	# Different faction = enemy
	return unit_faction != owner_faction


## Add work progress (called by workers)
## Returns true if placement is complete
func add_work(amount: float) -> bool:
	if not is_placing:
		is_placing = true
		wire_placed.emit()

	var new_progress: float = minf(current_progress + amount, 1.0)

	if new_progress != current_progress:
		current_progress = new_progress
		_update_visuals()
		wire_progress.emit(current_progress)

	if current_progress >= 1.0:
		_complete()
		return true

	return false


func _update_visuals() -> void:
	# Show wire after 10% progress
	if current_progress > 0.1:
		post_mesh.visible = true
		post_mesh.mesh = _create_post_mesh(current_progress)

	if current_progress > 0.3:
		wire_mesh.visible = true
		wire_mesh.mesh = _create_wire_mesh(current_progress)

	# Fade outline
	_outline_material.albedo_color.a = lerpf(0.5, 0.1, current_progress)


func _complete() -> void:
	is_placing = false
	is_complete = true

	# Final visual update
	post_mesh.mesh = _create_post_mesh(1.0)
	wire_mesh.mesh = _create_wire_mesh(1.0)

	# Hide outline
	outline_mesh.visible = false

	wire_complete.emit()
	print("[WireObstacle] Complete! Type %d at %s" % [wire_type, global_position])


## Take damage (from sappers, explosives, etc.)
func take_damage(amount: float, _source: Node = null) -> void:
	health -= amount

	# Visual damage feedback
	_wire_material.albedo_color = Color(
		lerpf(0.4, 0.6, 1.0 - health / max_health),
		lerpf(0.35, 0.25, 1.0 - health / max_health),
		lerpf(0.3, 0.2, 1.0 - health / max_health)
	)

	if health <= 0:
		_destroy()


func _destroy() -> void:
	wire_destroyed.emit()

	# Release trapped units
	for unit in units_inside:
		if is_instance_valid(unit):
			_apply_slowdown(unit, false)

	print("[WireObstacle] Destroyed at %s" % global_position)
	queue_free()


## Get progress as 0.0 - 1.0
func get_progress() -> float:
	return current_progress


## Create wire mesh
func _create_wire_mesh(progress: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var hl: float = length * 0.5
	var hw: float = width * 0.5
	var wire_rows: int = 3 if wire_type == WireType.TRIPLE_CONCERTINA else (2 if wire_type == WireType.CONCERTINA else 1)
	var wire_height: float = 0.8 if wire_type == WireType.BARBED else 0.6

	# Draw wire strands
	var sections: int = int(progress * 8) + 2
	var section_length: float = length / float(sections)

	for row in range(wire_rows):
		var z_offset: float = -hw + hw * 2 * float(row) / float(maxf(wire_rows - 1, 1))
		if wire_rows == 1:
			z_offset = 0

		for i in range(sections):
			var x1: float = -hl + i * section_length
			var x2: float = x1 + section_length

			# Main horizontal wire
			for h in range(3):  # 3 horizontal strands
				var y: float = 0.2 + h * (wire_height / 3.0)
				st.add_vertex(Vector3(x1, y, z_offset))
				st.add_vertex(Vector3(x2, y, z_offset))

			# Diagonal cross-wires
			if i % 2 == 0:
				st.add_vertex(Vector3(x1, 0.2, z_offset))
				st.add_vertex(Vector3(x2, wire_height, z_offset))
			else:
				st.add_vertex(Vector3(x1, wire_height, z_offset))
				st.add_vertex(Vector3(x2, 0.2, z_offset))

	return st.commit()


## Create post mesh
func _create_post_mesh(progress: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hl: float = length * 0.5
	var hw: float = width * 0.5
	var post_count: int = int(progress * 4) + 2
	var post_spacing: float = length / float(post_count - 1)
	var post_radius: float = 0.04
	var post_height: float = 1.0

	for i in range(post_count):
		var x: float = -hl + i * post_spacing

		# Add posts at front and back of wire width
		_add_post(st, Vector3(x, 0, -hw * 0.8), post_height, post_radius)
		if width > 1.0:
			_add_post(st, Vector3(x, 0, hw * 0.8), post_height, post_radius)

	st.generate_normals()
	return st.commit()


func _add_post(st: SurfaceTool, base: Vector3, height: float, radius: float) -> void:
	## Add a simple rectangular post
	var segments: int = 4
	for i in range(segments):
		var angle1: float = TAU * float(i) / float(segments)
		var angle2: float = TAU * float(i + 1) / float(segments)

		var x1: float = cos(angle1) * radius
		var z1: float = sin(angle1) * radius
		var x2: float = cos(angle2) * radius
		var z2: float = sin(angle2) * radius

		# Side face
		st.add_vertex(base + Vector3(x1, 0, z1))
		st.add_vertex(base + Vector3(x2, 0, z2))
		st.add_vertex(base + Vector3(x2, height, z2))

		st.add_vertex(base + Vector3(x1, 0, z1))
		st.add_vertex(base + Vector3(x2, height, z2))
		st.add_vertex(base + Vector3(x1, height, z1))


## Create outline mesh
func _create_outline_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var hl: float = length * 0.5
	var hw: float = width * 0.5

	# Rectangle outline
	st.add_vertex(Vector3(-hl, 0, -hw))
	st.add_vertex(Vector3(hl, 0, -hw))

	st.add_vertex(Vector3(hl, 0, -hw))
	st.add_vertex(Vector3(hl, 0, hw))

	st.add_vertex(Vector3(hl, 0, hw))
	st.add_vertex(Vector3(-hl, 0, hw))

	st.add_vertex(Vector3(-hl, 0, hw))
	st.add_vertex(Vector3(-hl, 0, -hw))

	# X pattern to indicate obstacle
	st.add_vertex(Vector3(-hl, 0, -hw))
	st.add_vertex(Vector3(hl, 0, hw))

	st.add_vertex(Vector3(hl, 0, -hw))
	st.add_vertex(Vector3(-hl, 0, hw))

	return st.commit()


## Factory: Create a wire obstacle at a position
static func create(world_position: Vector3, type: WireType = WireType.BARBED, wire_length: float = 6.0, faction: int = 0, rotation_y: float = 0.0) -> WireObstacleNode:
	var wire := WireObstacleNode.new()
	wire.position = world_position
	wire.wire_type = type
	wire.length = wire_length
	wire.owner_faction = faction
	if rotation_y != 0.0:
		wire.rotate_y(rotation_y)
	return wire
