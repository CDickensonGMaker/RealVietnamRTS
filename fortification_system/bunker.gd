class_name Bunker extends Node3D
## Bunker - Fortified fighting position that garrisons infantry.
##
## Three states relevant to gameplay:
##   - EMPTY: no garrison, cannot fire. Pure cover, blocks LOS minimally.
##   - GARRISONED: holds 1+ squads. Garrison fires *from* the bunker; rate is
##     a function of how full the bunker is. Garrison takes much-reduced damage.
##   - DESTROYED: structural HP depleted. Garrison is killed.
##
## A bunker is NOT a Squad. It's a structure that gives a hosted squad
## protection and fixed firing arcs. Loading/unloading happens via
## load_squad() / unload_squad().
##
## Bunker variants are determined by the bunker_type field (matches
## firebase_system/building_data.gd BuildingType enum where relevant).

signal squad_loaded(squad: Node3D)
signal squad_unloaded(squad: Node3D)
signal bunker_destroyed(bunker: Bunker)
signal garrison_killed(killed_count: int)

enum BunkerType {
	GENERIC_BUNKER,        # Hardened fighting position
	SANDBAG_BUNKER,        # Light cover
	CONEX_BUNKER,          # Heavy steel container
	MACHINE_GUN_NEST,      # MG emplacement
	MORTAR_PIT,            # Mortar position
	COMMAND_BUNKER,        # Higher capacity, command bonuses (future)
}

@export var bunker_type: BunkerType = BunkerType.GENERIC_BUNKER
@export var bunker_name: String = "Bunker"
@export var max_garrison_capacity: int = 1  # Squads (not soldiers)
@export var max_health: float = 800.0
@export var damage_reduction: float = 0.7  # 70% damage reduction for garrison
@export var firing_arc_degrees: float = 180.0  # Fixed firing arc (0 = omni)
@export var firing_arc_yaw_degrees: float = 0.0  # Direction the arc points (world yaw)
@export var fire_rate_per_full_capacity: float = 1.0  # 1.0 = full fire rate when fully crewed

## State
var current_health: float = 800.0
var garrison: Array[Node3D] = []
var faction: int = 0  # GameEnums.Faction
var is_player_controlled: bool = true

## Visual
var _structure_mesh: MeshInstance3D = null


func _ready() -> void:
	add_to_group("bunkers")
	add_to_group("fortifications")
	add_to_group("all_units")
	if is_player_controlled:
		add_to_group("player_structures")
		add_to_group("selectable_units")
	else:
		add_to_group("enemy_structures")

	current_health = max_health
	_build_placeholder_visual()


func _build_placeholder_visual() -> void:
	_structure_mesh = MeshInstance3D.new()
	_structure_mesh.name = "Structure"

	var mesh: Mesh
	match bunker_type:
		BunkerType.SANDBAG_BUNKER:
			var b := BoxMesh.new()
			b.size = Vector3(4.0, 1.5, 4.0)
			mesh = b
		BunkerType.CONEX_BUNKER:
			var b := BoxMesh.new()
			b.size = Vector3(6.0, 2.5, 2.5)  # Shipping container shape
			mesh = b
		BunkerType.MACHINE_GUN_NEST:
			var b := BoxMesh.new()
			b.size = Vector3(3.0, 1.2, 3.0)
			mesh = b
		BunkerType.MORTAR_PIT:
			# Circular pit - use cylinder
			var c := CylinderMesh.new()
			c.top_radius = 2.5
			c.bottom_radius = 2.5
			c.height = 0.8
			mesh = c
		BunkerType.COMMAND_BUNKER:
			var b := BoxMesh.new()
			b.size = Vector3(8.0, 2.5, 6.0)
			mesh = b
		_:
			var b := BoxMesh.new()
			b.size = Vector3(4.0, 2.0, 3.5)
			mesh = b

	_structure_mesh.mesh = mesh
	_structure_mesh.position.y = (mesh.size.y if mesh is BoxMesh else (mesh as CylinderMesh).height) * 0.5

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.4, 0.35)  # Concrete-sandbag color
	_structure_mesh.material_override = mat
	add_child(_structure_mesh)

	# Static collision body
	var body := StaticBody3D.new()
	body.name = "Body"
	var coll := CollisionShape3D.new()
	if mesh is BoxMesh:
		var shape := BoxShape3D.new()
		shape.size = (mesh as BoxMesh).size
		coll.shape = shape
	elif mesh is CylinderMesh:
		var shape := CylinderShape3D.new()
		shape.radius = (mesh as CylinderMesh).top_radius
		shape.height = (mesh as CylinderMesh).height
		coll.shape = shape
	coll.position.y = _structure_mesh.position.y
	body.add_child(coll)
	body.collision_layer = 1  # Terrain/static
	add_child(body)


# =============================================================================
# GARRISON MANAGEMENT
# =============================================================================

func can_load(squad: Node3D) -> bool:
	if not squad:
		return false
	if garrison.size() >= max_garrison_capacity:
		return false
	# Squad must be within 5m
	if global_position.distance_to(squad.global_position) > 5.0:
		return false
	return true


## Load a squad into the bunker. Returns true on success.
func load_squad(squad: Node3D) -> bool:
	if not can_load(squad):
		return false
	garrison.append(squad)
	# Hide visual but keep firing through bunker
	squad.visible = false
	if squad.has_method("set"):
		squad.set("is_in_cover", true)
	squad_loaded.emit(squad)
	return true


## Unload a squad. Squad reappears at unload_position (defaults to 4m in front).
func unload_squad(squad: Node3D, unload_position: Vector3 = Vector3.INF) -> bool:
	if not squad in garrison:
		return false
	garrison.erase(squad)

	if unload_position == Vector3.INF:
		# Default: place 4m in front of bunker (using firing arc direction)
		var arc_dir := Vector3(sin(deg_to_rad(firing_arc_yaw_degrees)), 0, cos(deg_to_rad(firing_arc_yaw_degrees)))
		unload_position = global_position + arc_dir * 4.0

	squad.global_position = unload_position
	squad.visible = true
	if squad.has_method("set"):
		squad.set("is_in_cover", false)
	squad_unloaded.emit(squad)
	return true


func unload_all() -> Array[Node3D]:
	var unloaded: Array[Node3D] = []
	for s in garrison.duplicate():
		if unload_squad(s):
			unloaded.append(s)
	return unloaded


# =============================================================================
# COMBAT
# =============================================================================

## Garrison effectiveness: 0.0 (empty) to 1.0 (fully crewed).
## Drives fire rate of contained squads.
func get_garrison_effectiveness() -> float:
	if max_garrison_capacity <= 0:
		return 0.0
	return float(garrison.size()) / float(max_garrison_capacity)


## Check if target_pos is within firing arc.
func is_in_firing_arc(target_pos: Vector3) -> bool:
	if firing_arc_degrees >= 360.0:
		return true
	var to_target: Vector3 = target_pos - global_position
	to_target.y = 0
	if to_target.length() < 0.1:
		return true
	var target_yaw: float = atan2(to_target.x, to_target.z)
	var arc_center: float = deg_to_rad(firing_arc_yaw_degrees)
	var half_arc: float = deg_to_rad(firing_arc_degrees * 0.5)
	var diff: float = abs(angle_difference(arc_center, target_yaw))
	return diff <= half_arc


func take_damage(amount: float) -> void:
	# Structural HP is reduced first
	current_health = max(0.0, current_health - amount)

	# Garrison takes reduced damage proportional to remaining structural HP
	# (a collapsing bunker offers less protection)
	var structural_ratio: float = current_health / max_health
	var damage_to_garrison: float = amount * (1.0 - damage_reduction) * (1.0 - structural_ratio * 0.5)

	# Distribute damage to garrison squads
	for squad in garrison:
		if is_instance_valid(squad) and squad.has_method("take_damage"):
			squad.take_damage(damage_to_garrison / float(max(1, garrison.size())))

	if current_health <= 0.0:
		_collapse()


func _collapse() -> void:
	# Kill all garrison
	var killed_count: int = 0
	for squad in garrison:
		if is_instance_valid(squad) and squad.has_method("take_damage"):
			squad.take_damage(99999.0)
			killed_count += 1
	garrison.clear()
	garrison_killed.emit(killed_count)
	bunker_destroyed.emit(self)
	queue_free()


func is_destroyed() -> bool:
	return current_health <= 0.0


func get_garrison() -> Array[Node3D]:
	return garrison
