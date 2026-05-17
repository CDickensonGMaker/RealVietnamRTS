## vietnam_terrain.gd - Procedural terrain generation for Vietnam War maps
## Generates authentic Vietnam terrain with jungle, rice paddies, mountains, etc.
## Adapted from Daggerfall terrain system for RTS scale
class_name VietnamTerrain
extends RefCounted


## Grid configuration - larger cells for RTS scale
const GRID_SIZE: int = 17              # 17x17 vertices per cell (289 total)
const CELL_SIZE: float = 200.0         # Larger cells for RTS scale (was 100)

## Height settings - Vietnam has dramatic elevation changes
const DEFAULT_MIN_HEIGHT: float = 0.0
const DEFAULT_MAX_HEIGHT: float = 50.0

## Noise settings
const NOISE_SEED: int = 1965          # Year of Ia Drang

## Edge blending settings
const BLEND_DISTANCE: int = 4          # Vertices from edge to blend over


## =============================================================================
## REGION PRESETS - Based on real Vietnam geography
## =============================================================================
const HEIGHT_PRESETS: Dictionary = {
	"central_highlands": {
		"min_height": 200.0,
		"max_height": 1500.0,
		"noise_frequency": 0.008,      # Larger, rolling hills
		"base_elevation": 500.0,       # Starting elevation
		"terrain_bias": 0.3,           # Favor hills
	},
	"a_shau_valley": {
		"min_height": 300.0,           # Valley floor
		"max_height": 1800.0,          # Mountain flanks
		"noise_frequency": 0.004,      # Long, narrow valley shape
		"base_elevation": 400.0,
		"valley_width": 1500.0,        # 1.5km valley floor
		"valley_direction": Vector2(0, 1),  # North-South
	},
	"mekong_delta": {
		"min_height": -2.0,            # Below sea level areas
		"max_height": 50.0,            # Essentially flat
		"noise_frequency": 0.02,       # Very subtle variation
		"base_elevation": 0.0,
		"water_table": 0.0,            # Wet terrain
	},
	"ia_drang": {
		"min_height": 200.0,
		"max_height": 732.0,           # Chu Pong massif height
		"noise_frequency": 0.006,
		"base_elevation": 300.0,
		"clearing_locations": ["lz_xray", "lz_albany", "plei_me"],
	},
	"khe_sanh": {
		"min_height": 400.0,
		"max_height": 1200.0,
		"noise_frequency": 0.007,
		"base_elevation": 500.0,
		"plateau_center": Vector2(0, 0),
		"plateau_radius": 500.0,       # Combat base plateau
	},
	"hue": {
		"min_height": 0.0,
		"max_height": 30.0,            # Coastal city
		"noise_frequency": 0.015,
		"base_elevation": 5.0,
		"urban_density": 0.8,
		"river_path": "perfume_river",
	},
	"hamburger_hill": {
		"min_height": 300.0,
		"max_height": 937.0,           # Hill 937 (Ap Bia Mountain)
		"noise_frequency": 0.005,
		"base_elevation": 350.0,
		"peak_location": Vector2(0, 0),
		"peak_steepness": 0.7,
	},
	"default": {
		"min_height": 0.0,
		"max_height": 100.0,
		"noise_frequency": 0.01,
		"base_elevation": 20.0,
	},
}


## =============================================================================
## TERRAIN TYPE DEFINITIONS
## =============================================================================
enum TerrainType {
	TRIPLE_CANOPY,
	SINGLE_CANOPY,
	ELEPHANT_GRASS,
	RICE_PADDY,
	BAMBOO,
	HILL,
	MOUNTAIN,
	RIVER,
	CLEARED,
	VILLAGE,
	ROAD,
	WATER,
	SWAMP,
}

## Terrain properties lookup
const TERRAIN_PROPERTIES: Dictionary = {
	TerrainType.TRIPLE_CANOPY: {
		"name": "Triple Canopy Jungle",
		"height_min": 100.0,
		"height_max": 800.0,
		"speed_modifier": 0.3,
		"concealment": 1.0,
		"clearable": true,
		"vegetation_density": 0.9,
	},
	TerrainType.SINGLE_CANOPY: {
		"name": "Single Canopy",
		"height_min": 50.0,
		"height_max": 600.0,
		"speed_modifier": 0.6,
		"concealment": 0.7,
		"clearable": true,
		"vegetation_density": 0.6,
	},
	TerrainType.ELEPHANT_GRASS: {
		"name": "Elephant Grass",
		"height_min": 0.0,
		"height_max": 200.0,
		"speed_modifier": 0.8,
		"concealment": 0.5,
		"clearable": true,
		"fire_hazard": true,
		"vegetation_density": 0.95,
	},
	TerrainType.RICE_PADDY: {
		"name": "Rice Paddy",
		"height_min": 0.0,
		"height_max": 50.0,
		"speed_modifier": 0.7,
		"concealment": 0.2,
		"clearable": false,
		"wet_terrain": true,
		"vegetation_density": 0.1,
	},
	TerrainType.BAMBOO: {
		"name": "Bamboo Forest",
		"height_min": 50.0,
		"height_max": 400.0,
		"speed_modifier": 0.5,
		"concealment": 0.8,
		"clearable": true,
		"vegetation_density": 0.8,
	},
	TerrainType.HILL: {
		"name": "Hill",
		"height_min": 200.0,
		"height_max": 800.0,
		"speed_modifier": 0.9,
		"concealment": 0.4,
		"height_advantage": true,
		"vegetation_density": 0.3,
	},
	TerrainType.MOUNTAIN: {
		"name": "Mountain",
		"height_min": 500.0,
		"height_max": 2500.0,
		"speed_modifier": 0.4,
		"concealment": 0.3,
		"impassable_areas": true,
		"vegetation_density": 0.1,
	},
	TerrainType.RIVER: {
		"name": "River",
		"height_min": 0.0,
		"height_max": 0.0,
		"speed_modifier": 0.0,
		"concealment": 0.0,
		"fordable": false,
		"vegetation_density": 0.0,
	},
	TerrainType.CLEARED: {
		"name": "Cleared Area",
		"height_min": 0.0,
		"height_max": 800.0,
		"speed_modifier": 1.0,
		"concealment": 0.0,
		"buildable": true,
		"vegetation_density": 0.0,
	},
	TerrainType.VILLAGE: {
		"name": "Village",
		"height_min": 0.0,
		"height_max": 200.0,
		"speed_modifier": 1.0,
		"concealment": 0.5,
		"has_civilians": true,
		"vegetation_density": 0.2,
	},
	TerrainType.ROAD: {
		"name": "Road/Trail",
		"height_min": 0.0,
		"height_max": 1000.0,
		"speed_modifier": 1.25,
		"concealment": 0.1,
		"ambush_risk": true,
		"vegetation_density": 0.0,
	},
	TerrainType.WATER: {
		"name": "Open Water",
		"height_min": 0.0,
		"height_max": 0.0,
		"speed_modifier": 0.0,
		"concealment": 0.0,
		"impassable": true,
		"vegetation_density": 0.0,
	},
	TerrainType.SWAMP: {
		"name": "Swamp",
		"height_min": 0.0,
		"height_max": 20.0,
		"speed_modifier": 0.5,
		"concealment": 0.6,
		"wet_terrain": true,
		"vegetation_density": 0.4,
	},
}


## =============================================================================
## GENERATION METHODS
## =============================================================================

## Generate complete terrain for a cell
## Returns: Dictionary with "node" (Node3D), "heights" (PackedFloat32Array)
static func generate(
	cell_x: int,
	cell_z: int,
	preset_name: String = "default",
	terrain_type: TerrainType = TerrainType.SINGLE_CANOPY,
	material: Material = null,
	blend_edges: Dictionary = {}
) -> Dictionary:
	var preset: Dictionary = HEIGHT_PRESETS.get(preset_name, HEIGHT_PRESETS["default"])

	# Generate height grid with edge blending
	var heights: PackedFloat32Array = _generate_height_grid(cell_x, cell_z, preset, blend_edges)

	# Create root node
	var root := Node3D.new()
	root.name = "VietnamTerrain"

	# Create and add mesh
	var mesh_instance: MeshInstance3D = _create_mesh(heights, material, terrain_type)
	root.add_child(mesh_instance)

	# Create and add collision
	var collision: StaticBody3D = _create_collision(heights)
	root.add_child(collision)

	# Store metadata for external access
	root.set_meta("heights", heights)
	root.set_meta("grid_size", GRID_SIZE)
	root.set_meta("cell_size", CELL_SIZE)
	root.set_meta("terrain_type", terrain_type)
	root.set_meta("preset", preset_name)

	return {
		"node": root,
		"heights": heights,
		"terrain_type": terrain_type,
	}


## Generate heightmap based on preset and cell coordinates
static func generate_heightmap(
	coords: Vector2i,
	preset_name: String = "default",
	terrain_type: TerrainType = TerrainType.SINGLE_CANOPY
) -> PackedFloat32Array:
	var preset: Dictionary = HEIGHT_PRESETS.get(preset_name, HEIGHT_PRESETS["default"])
	return _generate_height_grid(coords.x, coords.y, preset, {})


## Get height at local position using bilinear interpolation
static func get_height_at(
	heights: PackedFloat32Array,
	local_x: float,
	local_z: float
) -> float:
	var half_size: float = CELL_SIZE * 0.5
	var step: float = CELL_SIZE / (GRID_SIZE - 1)

	# Convert local position to grid position
	var grid_x: float = (local_x + half_size) / step
	var grid_z: float = (local_z + half_size) / step

	# Clamp to valid range
	grid_x = clampf(grid_x, 0.0, GRID_SIZE - 1.0)
	grid_z = clampf(grid_z, 0.0, GRID_SIZE - 1.0)

	# Get integer grid coordinates
	var x0: int = int(grid_x)
	var z0: int = int(grid_z)
	var x1: int = mini(x0 + 1, GRID_SIZE - 1)
	var z1: int = mini(z0 + 1, GRID_SIZE - 1)

	# Get fractional parts for interpolation
	var fx: float = grid_x - x0
	var fz: float = grid_z - z0

	# Get heights at four corners
	var h00: float = heights[z0 * GRID_SIZE + x0]
	var h10: float = heights[z0 * GRID_SIZE + x1]
	var h01: float = heights[z1 * GRID_SIZE + x0]
	var h11: float = heights[z1 * GRID_SIZE + x1]

	# Bilinear interpolation
	var h0: float = lerpf(h00, h10, fx)
	var h1: float = lerpf(h01, h11, fx)
	return lerpf(h0, h1, fz)


## =============================================================================
## INTERNAL GENERATION METHODS
## =============================================================================

static func _generate_height_grid(
	cell_x: int,
	cell_z: int,
	preset: Dictionary,
	blend_edges: Dictionary
) -> PackedFloat32Array:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = preset.get("noise_frequency", 0.01)
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	noise.seed = NOISE_SEED

	var heights := PackedFloat32Array()
	heights.resize(GRID_SIZE * GRID_SIZE)

	var step: float = CELL_SIZE / (GRID_SIZE - 1)
	var min_height: float = preset.get("min_height", DEFAULT_MIN_HEIGHT)
	var max_height: float = preset.get("max_height", DEFAULT_MAX_HEIGHT)
	var base_elevation: float = preset.get("base_elevation", 0.0)

	# Get blend flags
	var blend_north: bool = blend_edges.get("north", false)
	var blend_south: bool = blend_edges.get("south", false)
	var blend_east: bool = blend_edges.get("east", false)
	var blend_west: bool = blend_edges.get("west", false)

	# Check for special terrain features
	var has_valley: bool = preset.has("valley_direction")
	var valley_dir: Vector2 = preset.get("valley_direction", Vector2.ZERO)
	var valley_width: float = preset.get("valley_width", 1000.0)

	var has_plateau: bool = preset.has("plateau_center")
	var plateau_center: Vector2 = preset.get("plateau_center", Vector2.ZERO)
	var plateau_radius: float = preset.get("plateau_radius", 500.0)

	var has_peak: bool = preset.has("peak_location")
	var peak_location: Vector2 = preset.get("peak_location", Vector2.ZERO)
	var peak_steepness: float = preset.get("peak_steepness", 0.5)

	for z in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			# Calculate world-space coordinates
			var world_x: float = cell_x * CELL_SIZE + x * step
			var world_z: float = cell_z * CELL_SIZE + z * step

			# Sample noise at world coordinates
			var noise_value: float = noise.get_noise_2d(world_x, world_z)

			# Base height from noise (normalized to 0-1)
			var normalized_noise: float = (noise_value + 1.0) * 0.5
			var height: float = lerpf(min_height, max_height, normalized_noise)

			# Apply valley modifier
			if has_valley:
				var distance_to_valley: float = _distance_to_line(
					Vector2(world_x, world_z),
					Vector2.ZERO,
					valley_dir
				)
				var valley_factor: float = clampf(distance_to_valley / valley_width, 0.0, 1.0)
				height = lerpf(min_height, height, valley_factor)

			# Apply plateau modifier
			if has_plateau:
				var distance_to_center: float = Vector2(world_x, world_z).distance_to(plateau_center)
				if distance_to_center < plateau_radius:
					var plateau_factor: float = 1.0 - (distance_to_center / plateau_radius)
					var plateau_height: float = (min_height + max_height) * 0.4
					height = lerpf(height, plateau_height, plateau_factor * 0.7)

			# Apply peak modifier (for Hamburger Hill, etc.)
			if has_peak:
				var distance_to_peak: float = Vector2(world_x, world_z).distance_to(peak_location)
				var peak_influence: float = 1000.0  # Influence radius
				if distance_to_peak < peak_influence:
					var peak_factor: float = 1.0 - (distance_to_peak / peak_influence)
					peak_factor = pow(peak_factor, 2.0 - peak_steepness)
					height = lerpf(height, max_height, peak_factor)

			# Add base elevation
			height += base_elevation

			# Apply edge blending
			var blend: float = 1.0

			if blend_north and z < BLEND_DISTANCE:
				blend = minf(blend, float(z) / float(BLEND_DISTANCE))
			if blend_south and z >= GRID_SIZE - BLEND_DISTANCE:
				blend = minf(blend, float(GRID_SIZE - 1 - z) / float(BLEND_DISTANCE))
			if blend_west and x < BLEND_DISTANCE:
				blend = minf(blend, float(x) / float(BLEND_DISTANCE))
			if blend_east and x >= GRID_SIZE - BLEND_DISTANCE:
				blend = minf(blend, float(GRID_SIZE - 1 - x) / float(BLEND_DISTANCE))

			# Blend towards base elevation at edges
			height = lerpf(base_elevation, height, blend)

			heights[z * GRID_SIZE + x] = height

	return heights


static func _distance_to_line(point: Vector2, line_origin: Vector2, line_dir: Vector2) -> float:
	var normalized_dir: Vector2 = line_dir.normalized()
	var to_point: Vector2 = point - line_origin
	var projection_length: float = to_point.dot(normalized_dir)
	var projection: Vector2 = line_origin + normalized_dir * projection_length
	return point.distance_to(projection)


static func _create_mesh(
	heights: PackedFloat32Array,
	material: Material,
	terrain_type: TerrainType
) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var step: float = CELL_SIZE / (GRID_SIZE - 1)
	var half_size: float = CELL_SIZE * 0.5

	# Generate vertices
	for z in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var height: float = heights[z * GRID_SIZE + x]
			vertices.append(Vector3(
				x * step - half_size,
				height,
				z * step - half_size
			))
			uvs.append(Vector2(
				float(x) / (GRID_SIZE - 1),
				float(z) / (GRID_SIZE - 1)
			))

	# Generate indices
	for z in range(GRID_SIZE - 1):
		for x in range(GRID_SIZE - 1):
			var tl: int = z * GRID_SIZE + x
			var tr: int = tl + 1
			var bl: int = (z + 1) * GRID_SIZE + x
			var br: int = bl + 1

			# Two triangles per quad
			indices.append(tl)
			indices.append(tr)
			indices.append(bl)

			indices.append(tr)
			indices.append(br)
			indices.append(bl)

	# Calculate normals
	normals.resize(vertices.size())
	for i in range(normals.size()):
		normals[i] = Vector3.ZERO

	for i in range(0, indices.size(), 3):
		var i0: int = indices[i]
		var i1: int = indices[i + 1]
		var i2: int = indices[i + 2]

		var v0: Vector3 = vertices[i0]
		var v1: Vector3 = vertices[i1]
		var v2: Vector3 = vertices[i2]

		var normal: Vector3 = (v1 - v0).cross(v2 - v0).normalized()

		normals[i0] += normal
		normals[i1] += normal
		normals[i2] += normal

	for i in range(normals.size()):
		if normals[i].length_squared() > 0.0001:
			normals[i] = normals[i].normalized()
		else:
			normals[i] = Vector3.UP

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Terrain"
	mesh_instance.mesh = mesh

	if material:
		mesh_instance.material_override = material
	else:
		# Create default terrain material
		mesh_instance.material_override = _create_default_material(terrain_type)

	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	return mesh_instance


static func _create_default_material(terrain_type: TerrainType) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()

	# Set color based on terrain type
	match terrain_type:
		TerrainType.TRIPLE_CANOPY, TerrainType.SINGLE_CANOPY:
			mat.albedo_color = Color(0.15, 0.35, 0.1)  # Dark jungle green
		TerrainType.ELEPHANT_GRASS:
			mat.albedo_color = Color(0.45, 0.55, 0.2)  # Yellowish grass
		TerrainType.RICE_PADDY:
			mat.albedo_color = Color(0.3, 0.4, 0.2)  # Wet green
		TerrainType.BAMBOO:
			mat.albedo_color = Color(0.25, 0.45, 0.15)  # Bamboo green
		TerrainType.HILL:
			mat.albedo_color = Color(0.35, 0.4, 0.25)  # Grassy hill
		TerrainType.MOUNTAIN:
			mat.albedo_color = Color(0.4, 0.35, 0.3)  # Rocky brown
		TerrainType.CLEARED:
			mat.albedo_color = Color(0.5, 0.4, 0.3)  # Bare earth
		TerrainType.ROAD:
			mat.albedo_color = Color(0.4, 0.35, 0.25)  # Dirt road
		TerrainType.SWAMP:
			mat.albedo_color = Color(0.2, 0.3, 0.15)  # Murky green
		_:
			mat.albedo_color = Color(0.3, 0.4, 0.2)  # Default green

	return mat


static func _create_collision(heights: PackedFloat32Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1  # terrain layer
	body.collision_mask = 0

	var faces := PackedVector3Array()
	var step: float = CELL_SIZE / (GRID_SIZE - 1)
	var half_size: float = CELL_SIZE * 0.5

	for z in range(GRID_SIZE - 1):
		for x in range(GRID_SIZE - 1):
			var tl := Vector3(
				x * step - half_size,
				heights[z * GRID_SIZE + x],
				z * step - half_size
			)
			var tr := Vector3(
				(x + 1) * step - half_size,
				heights[z * GRID_SIZE + (x + 1)],
				z * step - half_size
			)
			var bl := Vector3(
				x * step - half_size,
				heights[(z + 1) * GRID_SIZE + x],
				(z + 1) * step - half_size
			)
			var br := Vector3(
				(x + 1) * step - half_size,
				heights[(z + 1) * GRID_SIZE + (x + 1)],
				(z + 1) * step - half_size
			)

			faces.append(tl)
			faces.append(tr)
			faces.append(bl)

			faces.append(tr)
			faces.append(br)
			faces.append(bl)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape"
	collision.shape = shape
	body.add_child(collision)

	return body


## =============================================================================
## UTILITY METHODS
## =============================================================================

static func get_terrain_speed_modifier(terrain_type: TerrainType) -> float:
	var props: Dictionary = TERRAIN_PROPERTIES.get(terrain_type, {})
	return props.get("speed_modifier", 1.0)


static func get_terrain_concealment(terrain_type: TerrainType) -> float:
	var props: Dictionary = TERRAIN_PROPERTIES.get(terrain_type, {})
	return props.get("concealment", 0.0)


static func get_vegetation_density(terrain_type: TerrainType) -> float:
	var props: Dictionary = TERRAIN_PROPERTIES.get(terrain_type, {})
	return props.get("vegetation_density", 0.0)


static func is_clearable(terrain_type: TerrainType) -> bool:
	var props: Dictionary = TERRAIN_PROPERTIES.get(terrain_type, {})
	return props.get("clearable", false)


static func is_buildable(terrain_type: TerrainType) -> bool:
	return terrain_type == TerrainType.CLEARED


static func get_preset_names() -> Array[String]:
	var names: Array[String] = []
	for key in HEIGHT_PRESETS.keys():
		names.append(key)
	return names
