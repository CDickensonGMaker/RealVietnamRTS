extends Node
## TerrainClearingSystem - Autoload singleton
## Access via: TerrainClearingSystem.is_cleared(pos)
##
## Thin forwarder to ClearingSystem autoload.
## Per ARCHITECTURE.md: NO duplicate state - all queries go to ClearingSystem.

## Signals for backward compatibility
signal clearing_started(position: Vector3, radius: float)
signal clearing_progress(position: Vector3, progress: float)
signal clearing_complete(position: Vector3, radius: float)

## Uses shared ClearingState.Stage enum (terrain/clearing_state.gd) as single source of truth
const ClearingState = preload("res://terrain/clearing_state.gd")

## Cell size (m) used to coalesce repeated apply_clearing_damage() calls at nearby
## positions into a single shared ClearingSystem zone (bulldozers/fire call ~60Hz).
const DAMAGE_ZONE_CELL := 8.0

## Maps a quantized world cell -> ClearingSystem zone_id so continuous clearing at one
## spot advances an existing zone instead of leaking a new zone every frame.
var _damage_zones: Dictionary = {}  # Vector2i -> int (zone_id)


func _ready() -> void:
	# Connect to ClearingSystem signals to forward them
	if is_instance_valid(ClearingSystem):
		ClearingSystem.clearing_started.connect(_on_clearing_started)
		ClearingSystem.clearing_progress.connect(_on_clearing_progress)
		ClearingSystem.clearing_completed.connect(_on_clearing_completed)
	else:
		push_warning("[TerrainClearingSystem] ClearingSystem autoload not found")

	print("[TerrainClearingSystem] Initialized (delegating to ClearingSystem)")


func _exit_tree() -> void:
	# Disconnect signals on cleanup
	if is_instance_valid(ClearingSystem):
		if ClearingSystem.clearing_started.is_connected(_on_clearing_started):
			ClearingSystem.clearing_started.disconnect(_on_clearing_started)
		if ClearingSystem.clearing_progress.is_connected(_on_clearing_progress):
			ClearingSystem.clearing_progress.disconnect(_on_clearing_progress)
		if ClearingSystem.clearing_completed.is_connected(_on_clearing_completed):
			ClearingSystem.clearing_completed.disconnect(_on_clearing_completed)


## =============================================================================
## PUBLIC API - All queries forwarded to ClearingSystem
## =============================================================================

func is_cleared(position: Vector3) -> bool:
	"""Check if position is cleared for building"""
	if is_instance_valid(ClearingSystem):
		return ClearingSystem.is_position_cleared(position)
	return false


func get_clearing_state(position: Vector3) -> ClearingState.Stage:
	"""Get the clearing state at a position"""
	if is_instance_valid(ClearingSystem):
		return ClearingSystem.get_zone_stage_at(position)
	return ClearingState.Stage.JUNGLE


func mark_area_cleared(bounds: AABB) -> void:
	"""Called by JobManager when CLEAR_TERRAIN job completes.
	This is the critical method that syncs clearing state between JobNode and ClearingSystem."""
	var center := bounds.get_center()
	var radius := maxf(bounds.size.x, bounds.size.z) * 0.5  # Half of largest dimension

	# Create zone in ClearingSystem and set to CLEARED
	if is_instance_valid(ClearingSystem):
		var zone_id := ClearingSystem.create_zone(center, radius)
		if zone_id >= 0:
			ClearingSystem.set_zone_stage(zone_id, ClearingState.Stage.CLEARED)
			print("[TerrainClearingSystem] mark_area_cleared: zone %d at %s (r=%.1f)" % [zone_id, center, radius])
		else:
			push_error("[TerrainClearingSystem] Failed to create zone for mark_area_cleared at %s" % center)

	# Emit signals
	clearing_complete.emit(center, radius)
	if is_instance_valid(BattleSignals):
		BattleSignals.terrain_cleared.emit(center, radius)


func instant_clear(position: Vector3, radius: float = 10.0) -> void:
	"""Instantly clear an area (for napalm, explosions, etc.)"""
	# Create zone and immediately set to CLEARED stage
	if is_instance_valid(ClearingSystem):
		var zone_id: int = ClearingSystem.create_zone(position, radius)
		if zone_id >= 0:
			ClearingSystem.set_zone_stage(zone_id, ClearingState.Stage.CLEARED)

	# Emit signals
	clearing_complete.emit(position, radius)

	if is_instance_valid(BattleSignals):
		BattleSignals.terrain_cleared.emit(position, radius)

	print("[TerrainClearingSystem] Instant clear at %s" % position)


func get_cleared_area_count() -> int:
	"""Get total number of cleared areas"""
	if is_instance_valid(ClearingSystem):
		return ClearingSystem.zones.size()
	return 0


func apply_clearing_damage(world_pos: Vector3, radius: float, amount: float) -> void:
	"""Progressive clearing at a world position (bulldozer clearing, road cutting, fire).
	Delegates to ClearingSystem, coalescing repeated calls at the same spot into one zone
	that we advance, rather than creating a zone per call. amount = progress this step
	(0-1 per clearing stage). Callers (bulldozer.gd:357/392, fire_hazard.gd:238) rely on
	this signature existing on the TerrainClearingSystem autoload."""
	if not is_instance_valid(ClearingSystem):
		return

	var key := Vector2i(
		int(floor(world_pos.x / DAMAGE_ZONE_CELL)),
		int(floor(world_pos.z / DAMAGE_ZONE_CELL))
	)

	var zone_id: int = _damage_zones.get(key, -1)

	# Create a fresh zone if we have none for this cell, or the cached one was removed.
	if zone_id < 0 or not ClearingSystem.zones.has(zone_id):
		zone_id = ClearingSystem.create_zone(world_pos, maxf(radius, DAMAGE_ZONE_CELL * 0.5))
		if zone_id < 0:
			return
		_damage_zones[key] = zone_id

	ClearingSystem.advance_clearing(zone_id, amount)


## =============================================================================
## SIGNAL FORWARDING FROM CLEARINGSYSTEM
## =============================================================================

func _on_clearing_started(zone_id: int, position: Vector3) -> void:
	# Forward with radius (lookup zone for radius)
	var radius := 10.0
	if is_instance_valid(ClearingSystem) and ClearingSystem.zones.has(zone_id):
		radius = ClearingSystem.zones[zone_id].radius
	clearing_started.emit(position, radius)


func _on_clearing_progress(zone_id: int, progress: float) -> void:
	# Forward with position
	if is_instance_valid(ClearingSystem) and ClearingSystem.zones.has(zone_id):
		var zone = ClearingSystem.zones[zone_id]  # ClearingZone inner class
		clearing_progress.emit(zone.center, progress)


func _on_clearing_completed(zone_id: int) -> void:
	# Forward with position and radius
	if is_instance_valid(ClearingSystem) and ClearingSystem.zones.has(zone_id):
		var zone = ClearingSystem.zones[zone_id]  # ClearingZone inner class
		clearing_complete.emit(zone.center, zone.radius)

		if is_instance_valid(BattleSignals):
			BattleSignals.terrain_cleared.emit(zone.center, zone.radius)
