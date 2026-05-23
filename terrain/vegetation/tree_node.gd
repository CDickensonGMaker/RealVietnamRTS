class_name TreeNode
extends Area3D
## TreeNode - An individual interactable tree in the world
##
## Trees are spawned as nodes sitting on terrain. They can be:
## - Highlighted when targeted for clearing
## - Destroyed when a ClearingZone overlaps them
## - Selected/inspected by the player
##
## This replaces pure MultiMesh trees for nearby/interactable vegetation.

signal tree_cleared(tree: TreeNode)
signal tree_targeted(tree: TreeNode, targeted: bool)

## Tree visual types
enum TreeType { JUNGLE, BAMBOO, PALM, RUBBER, JUNGLE_LIGHT, JUNGLE_MEDIUM, JUNGLE_HEAVY }

## Jungle density model paths (match VegetationManager)
const JUNGLE_MODEL_PATHS := {
	TreeType.JUNGLE_LIGHT: "res://assets/models/terrain/foliage/jungle_light.glb",
	TreeType.JUNGLE_MEDIUM: "res://assets/models/terrain/foliage/jungle_medium.glb",
	TreeType.JUNGLE_HEAVY: "res://assets/models/terrain/foliage/jungle_heavy.glb",
}

## Cached loaded scenes for jungle models
static var _jungle_scenes: Dictionary = {}  # TreeType -> PackedScene

## Current tree type
@export var tree_type: TreeType = TreeType.JUNGLE

## Whether this tree is currently targeted for clearing
var is_targeted: bool = false

## Whether this tree is being cleared (animation in progress)
var is_clearing: bool = false

## Worker that has claimed this tree to fell it (null = unclaimed).
## Prevents two workers from chopping the same tree.
var claimed_by: Node = null

## Visual components (set up in _ready or by spawner)
var mesh_instance: MeshInstance3D
var highlight_mesh: MeshInstance3D

## Collision shape for area detection
var collision_shape: CollisionShape3D

## Materials for highlighting
var _normal_material: Material = null
var _highlight_material: StandardMaterial3D = null


func _ready() -> void:
	# Set up collision layers
	# Layer 8 = vegetation (bit 128)
	collision_layer = 128
	collision_mask = 256  # Layer 9 (clearing zones) - detect when zones overlap us

	# Connect to area signals for clearing zone detection
	area_entered.connect(_on_area_entered)

	# Add to vegetation group for easy queries
	add_to_group("vegetation")
	add_to_group("trees")

	# Snap to terrain height
	_snap_to_terrain()

	# Set up highlight material if not already done
	if not _highlight_material:
		_highlight_material = StandardMaterial3D.new()
		_highlight_material.albedo_color = Color(1.0, 0.8, 0.2, 1.0)  # Golden highlight
		_highlight_material.emission_enabled = true
		_highlight_material.emission = Color(1.0, 0.6, 0.0)
		_highlight_material.emission_energy_multiplier = 0.3


func _snap_to_terrain() -> void:
	## Position this tree on the terrain surface
	var terrain = get_node_or_null("/root/UnifiedTerrain")
	if terrain and terrain.has_method("get_height_at"):
		position.y = terrain.get_height_at(global_position)
		return

	var terrain_intg = get_node_or_null("/root/TerrainIntegration")
	if terrain_intg and terrain_intg.has_method("get_height_at"):
		position.y = terrain_intg.get_height_at(global_position)


func _on_area_entered(area: Area3D) -> void:
	## When a clearing zone overlaps this tree, start clearing
	if area.is_in_group("clearing_zones"):
		_start_clear()


## Set whether this tree is targeted for clearing (visual feedback)
func set_targeted(targeted: bool) -> void:
	if is_targeted == targeted:
		return

	is_targeted = targeted
	tree_targeted.emit(self, targeted)

	# Update visual
	if mesh_instance:
		if targeted and _highlight_material:
			# Save current material before highlighting
			if not _normal_material:
				_normal_material = mesh_instance.material_override
			mesh_instance.material_override = _highlight_material
		elif _normal_material:
			# Restore original material
			mesh_instance.material_override = _normal_material


## Whether this tree is available to be claimed/felled
func is_claimed() -> bool:
	return is_instance_valid(claimed_by)


## Claim this tree for a worker. Returns false if already felling or claimed by someone else.
func claim(worker: Node) -> bool:
	if is_clearing:
		return false
	if is_instance_valid(claimed_by) and claimed_by != worker:
		return false
	claimed_by = worker
	set_targeted(true)
	return true


## Release a claim. If worker is given, only releases if it owns the claim.
func release(worker: Node = null) -> void:
	if worker != null and claimed_by != worker:
		return
	claimed_by = null
	set_targeted(false)


## Start the clearing animation and destruction
func _start_clear() -> void:
	if is_clearing:
		return

	is_clearing = true

	# Quick fall animation
	var tween := create_tween()
	tween.set_parallel(true)

	# Tip over (rotate around X or Z axis randomly)
	var fall_axis := Vector3.RIGHT if randf() > 0.5 else Vector3.FORWARD
	var fall_rotation := Quaternion(fall_axis, PI * 0.4)  # 72 degrees
	tween.tween_property(self, "quaternion", quaternion * fall_rotation, 0.5)

	# Shrink slightly
	tween.tween_property(self, "scale", scale * 0.8, 0.5)

	# Fade out (if material supports it)
	if mesh_instance and mesh_instance.material_override:
		var mat := mesh_instance.material_override as StandardMaterial3D
		if mat:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			tween.tween_property(mat, "albedo_color:a", 0.0, 0.5)

	# Emit signal and queue free after animation
	tween.chain().tween_callback(_finish_clear)


func _finish_clear() -> void:
	tree_cleared.emit(self)
	queue_free()


## Create a simple procedural tree mesh
static func create_procedural_mesh(type: TreeType, height: float = 8.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Tree color based on type
	var trunk_color := Color(0.4, 0.25, 0.1)
	var leaf_color: Color
	match type:
		TreeType.JUNGLE:
			leaf_color = Color(0.1, 0.4, 0.1)
		TreeType.BAMBOO:
			leaf_color = Color(0.2, 0.5, 0.2)
			trunk_color = Color(0.3, 0.4, 0.2)
		TreeType.PALM:
			leaf_color = Color(0.15, 0.45, 0.15)
		TreeType.RUBBER:
			leaf_color = Color(0.2, 0.35, 0.15)

	var trunk_height := height * 0.4
	var trunk_radius := height * 0.05
	var canopy_height := height * 0.6
	var canopy_radius := height * 0.25

	# Simple trunk (cylinder approximation with 6 sides)
	var segments := 6
	for i in range(segments):
		var angle1 := TAU * float(i) / float(segments)
		var angle2 := TAU * float(i + 1) / float(segments)

		var x1 := cos(angle1) * trunk_radius
		var z1 := sin(angle1) * trunk_radius
		var x2 := cos(angle2) * trunk_radius
		var z2 := sin(angle2) * trunk_radius

		st.set_color(trunk_color)
		# Bottom triangle
		st.add_vertex(Vector3(x1, 0, z1))
		st.add_vertex(Vector3(x2, 0, z2))
		st.add_vertex(Vector3(x1, trunk_height, z1))
		# Top triangle
		st.add_vertex(Vector3(x2, 0, z2))
		st.add_vertex(Vector3(x2, trunk_height, z2))
		st.add_vertex(Vector3(x1, trunk_height, z1))

	# Simple canopy (cone)
	st.set_color(leaf_color)
	var canopy_base := trunk_height
	var canopy_top := trunk_height + canopy_height

	for i in range(segments):
		var angle1 := TAU * float(i) / float(segments)
		var angle2 := TAU * float(i + 1) / float(segments)

		var x1 := cos(angle1) * canopy_radius
		var z1 := sin(angle1) * canopy_radius
		var x2 := cos(angle2) * canopy_radius
		var z2 := sin(angle2) * canopy_radius

		# Side triangles (cone surface)
		st.add_vertex(Vector3(x1, canopy_base, z1))
		st.add_vertex(Vector3(x2, canopy_base, z2))
		st.add_vertex(Vector3(0, canopy_top, 0))

		# Bottom cap
		st.add_vertex(Vector3(0, canopy_base, 0))
		st.add_vertex(Vector3(x1, canopy_base, z1))
		st.add_vertex(Vector3(x2, canopy_base, z2))

	st.generate_normals()
	return st.commit()


## Factory: Create a TreeNode with mesh and collision
static func create(type: TreeType, world_position: Vector3, height: float = 8.0) -> TreeNode:
	var tree := TreeNode.new()
	tree.tree_type = type
	tree.position = world_position

	# For jungle density types, try to load external model
	if type in [TreeType.JUNGLE_LIGHT, TreeType.JUNGLE_MEDIUM, TreeType.JUNGLE_HEAVY]:
		var model: Node3D = _load_jungle_model(type)
		if model:
			# Scale model to match height
			var model_aabb := _get_model_aabb(model)
			var scale_factor := height / maxf(model_aabb.size.y, 0.1)
			model.scale = Vector3.ONE * scale_factor
			tree.add_child(model)
			tree.mesh_instance = _find_mesh_instance(model)

			# Create collision based on model size
			tree.collision_shape = CollisionShape3D.new()
			var cylinder := CylinderShape3D.new()
			cylinder.radius = maxf(model_aabb.size.x, model_aabb.size.z) * 0.5 * scale_factor
			cylinder.height = height
			tree.collision_shape.shape = cylinder
			tree.collision_shape.position.y = height * 0.5
			tree.add_child(tree.collision_shape)

			return tree

	# Fallback: Create procedural mesh
	tree.mesh_instance = MeshInstance3D.new()
	tree.mesh_instance.mesh = create_procedural_mesh(type, height)
	tree.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	tree.add_child(tree.mesh_instance)

	# Create collision (cylinder)
	tree.collision_shape = CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = height * 0.15
	cylinder.height = height
	tree.collision_shape.shape = cylinder
	tree.collision_shape.position.y = height * 0.5
	tree.add_child(tree.collision_shape)

	return tree


## Fallback green material for trees without proper textures
static var _fallback_material: StandardMaterial3D = null

## Get or create fallback material
static func _get_fallback_material() -> StandardMaterial3D:
	if _fallback_material == null:
		_fallback_material = StandardMaterial3D.new()
		_fallback_material.albedo_color = Color(0.15, 0.4, 0.12)  # Jungle green
		_fallback_material.roughness = 0.8
		_fallback_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Double-sided for foliage
	return _fallback_material


## Load jungle model from GLB file
static func _load_jungle_model(type: TreeType) -> Node3D:
	if not JUNGLE_MODEL_PATHS.has(type):
		return null

	# Check cache first
	if _jungle_scenes.has(type):
		var scene: PackedScene = _jungle_scenes[type]
		if scene:
			var instance := scene.instantiate()
			_ensure_materials(instance)
			return instance

	# Load from file
	var path: String = JUNGLE_MODEL_PATHS[type]
	if not ResourceLoader.exists(path):
		push_warning("[TreeNode] Jungle model not found: %s" % path)
		return null

	var scene := load(path) as PackedScene
	if not scene:
		push_warning("[TreeNode] Failed to load jungle model: %s" % path)
		return null

	# Cache the scene
	_jungle_scenes[type] = scene
	var instance := scene.instantiate()
	_ensure_materials(instance)
	return instance


## Ensure all mesh instances have valid materials (fallback to green if missing/broken)
static func _ensure_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			# Check if any surface has a valid texture/albedo
			var has_valid_material := false
			for i in range(mi.mesh.get_surface_count()):
				var mat: Material = mi.get_surface_override_material(i)
				if mat == null:
					mat = mi.mesh.surface_get_material(i)
				if mat is StandardMaterial3D:
					var std_mat := mat as StandardMaterial3D
					# Check if it has a valid albedo texture or non-default color
					if std_mat.albedo_texture != null or std_mat.albedo_color != Color.WHITE:
						has_valid_material = true
						break
				elif mat != null:
					has_valid_material = true
					break

			# If no valid materials found, apply fallback
			if not has_valid_material:
				mi.material_override = _get_fallback_material()

	# Recurse to children
	for child in node.get_children():
		_ensure_materials(child)


## Get AABB from a model node
static func _get_model_aabb(model: Node3D) -> AABB:
	var mesh_instance := _find_mesh_instance(model)
	if mesh_instance and mesh_instance.mesh:
		return mesh_instance.mesh.get_aabb()
	return AABB(Vector3.ZERO, Vector3(1, 8, 1))


## Find first MeshInstance3D in a node tree
static func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var result := _find_mesh_instance(child)
		if result:
			return result
	return null


## Factory: Create a TreeNode from terrain type (maps to appropriate jungle density)
static func create_from_terrain_type(terrain_type: int, world_position: Vector3, height: float = 8.0) -> TreeNode:
	# Map terrain types to tree types
	# TerrainType: 3=LIGHT_JUNGLE, 4=MEDIUM_JUNGLE, 5=HEAVY_JUNGLE
	var tree_type: TreeType
	match terrain_type:
		3:  # LIGHT_JUNGLE
			tree_type = TreeType.JUNGLE_LIGHT
		4:  # MEDIUM_JUNGLE
			tree_type = TreeType.JUNGLE_MEDIUM
		5:  # HEAVY_JUNGLE
			tree_type = TreeType.JUNGLE_HEAVY
		_:
			tree_type = TreeType.JUNGLE  # Fallback to procedural

	return create(tree_type, world_position, height)
