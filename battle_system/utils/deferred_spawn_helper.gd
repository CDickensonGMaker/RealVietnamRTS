class_name DeferredSpawnHelper
extends RefCounted
## DeferredSpawnHelper - Terrain-ready aware ground placement.
##
## Serves Pillar 2/3 loop reliability: units spawn during the async terrain
## init window, when get_height_at() returns a 0.0 sentinel. Trusting that
## sentinel plants units at Y=0, below any hill (Vietnam terrain reaches ~280m).
##
## This helper defers height sampling until the terrain facade reports ready
## (via the `terrain_ready` signal + `is_terrain_ready()` on /root/TerrainIntegration),
## then samples the real surface height. All access is defensive so the code
## degrades gracefully when the terrain API is absent.

const _TERRAIN_PATH := "/root/TerrainIntegration"


## Resolve a ground position for a desired XZ location.
## If terrain is not ready, awaits `terrain_ready`, then samples get_height_at.
## Returns the corrected Vector3 (desired.x, height, desired.z).
## NOTE: This is a coroutine - callers must `await` it. For fire-and-forget
## placement of an existing node, use snap_to_ground_when_ready() instead.
static func resolve_ground_position(host: Node, desired: Vector3) -> Vector3:
	if not is_instance_valid(host):
		return desired

	var terrain: Node = host.get_node_or_null(_TERRAIN_PATH)
	if not terrain:
		return desired  # No terrain facade - trust caller's Y

	# Wait for async heightmap init if the readiness API reports not-ready.
	if terrain.has_method("is_terrain_ready") and not terrain.is_terrain_ready():
		if terrain.has_signal("terrain_ready"):
			await terrain.terrain_ready

	return _sample(terrain, desired)


## Best-effort synchronous ground sample (no await).
## Returns corrected Y when terrain is ready, otherwise returns `desired`
## UNCHANGED (never writes the 0.0 sentinel).
static func sample_ground_now(host: Node, desired: Vector3) -> Vector3:
	if not is_instance_valid(host):
		return desired

	var terrain: Node = host.get_node_or_null(_TERRAIN_PATH)
	if not terrain or not terrain.has_method("get_height_at"):
		return desired

	# Not ready yet - don't trust the 0.0 fallback, keep the caller's Y.
	if terrain.has_method("is_terrain_ready") and not terrain.is_terrain_ready():
		return desired

	return _sample(terrain, desired)


## Fire-and-forget: correct a spawned unit's Y once terrain is ready.
## Call WITHOUT await - runs in the background. Preserves the unit's current
## XZ, only rewrites Y. Guards validity across the await boundary.
static func snap_to_ground_when_ready(host: Node, unit: Node3D) -> void:
	if not is_instance_valid(host) or not is_instance_valid(unit):
		return

	var terrain: Node = host.get_node_or_null(_TERRAIN_PATH)
	if not terrain or not terrain.has_method("get_height_at"):
		return

	if terrain.has_method("is_terrain_ready") and not terrain.is_terrain_ready():
		if terrain.has_signal("terrain_ready"):
			await terrain.terrain_ready

	if not is_instance_valid(unit):
		return

	var pos: Vector3 = unit.global_position
	unit.global_position = _sample(terrain, pos)


static func _sample(terrain: Node, pos: Vector3) -> Vector3:
	var h: float = terrain.get_height_at(pos)
	return Vector3(pos.x, h, pos.z)
