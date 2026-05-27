extends Node3D
## Infantry Test Scene - Combat AI Test
##
## Tests:
## - Squad formation and movement
## - AI auto-engagement (SquadCommanderAI + ThreatHeatmap)
## - Cover-seeking under fire
## - Suppression and morale response
## - Firing range with markers at 25m, 100m, 200m, 300m, 550m (M16 max)
## - Pathfinding around buildings
## - Slope-aware movement
##
## Controls (via autoloads):
## - WASD: Pan camera
## - Mouse wheel: Zoom
## - Middle-drag: Rotate/tilt camera
## - Left-click drag: Select squads
## - Right-click: Move selected units
## - Shift+click: Add to selection
## - A: Toggle attack-move mode
##
## Test controls:
## - F: Spawn additional enemy squad
## - G: Spawn enemy squad on opposite side (flank test)
## - T: Toggle AI debug overlay
## - R: Reset test (clear all units and respawn)

const TestSceneBase = preload("res://test_scenes/common/test_scene_base.gd")
const Squad = preload("res://battle_system/nodes/squad.gd")
const SquadData = preload("res://battle_system/data/squad_data.gd")

var player_squads: Array[Node3D] = []
var enemy_squads: Array[Node3D] = []
var target_dummies: Array[Node3D] = []
var _debug_overlay_visible: bool = false

## Combat Test Configuration
const COMBAT_RANGE: float = 80.0  # Distance between US and VC squads
const US_SPAWN_POS := Vector3(0.0, 0.0, 30.0)  # US position (south)
const VC_SPAWN_POS := Vector3(0.0, 0.0, -50.0)  # VC position (north)


func _ready() -> void:
	TestSceneBase.setup_environment(self, {
		"seed": 11111,
		"size": 400.0,
		"name": "Infantry Combat AI Test",
	})

	# Create cleared combat area (no jungle in the firefight zone)
	_clear_combat_area()

	# Some cover objects in the combat zone
	_spawn_cover_objects()

	# Spawn US rifle squad (player-controlled)
	var terrain := get_node_or_null("/root/TerrainIntegration")
	var us_squad: Node3D = _make_squad(true, GameEnums.Faction.US_ARMY)
	add_child(us_squad)
	var us_pos := US_SPAWN_POS
	if terrain and terrain.has_method("get_height_at"):
		us_pos.y = terrain.get_height_at(us_pos) + 0.1
	us_squad.global_position = us_pos
	player_squads.append(us_squad)

	# Spawn VC rifle squad (AI-controlled via SquadCommanderAI)
	var vc_squad: Node3D = _make_squad(false, GameEnums.Faction.VC)
	add_child(vc_squad)
	var vc_pos := VC_SPAWN_POS
	if terrain and terrain.has_method("get_height_at"):
		vc_pos.y = terrain.get_height_at(vc_pos) + 0.1
	vc_squad.global_position = vc_pos
	enemy_squads.append(vc_squad)

	# Connect signals for debug
	_connect_debug_signals(us_squad)
	_connect_debug_signals(vc_squad)

	# Print instructions
	print("")
	print("=" .repeat(60))
	print("  INFANTRY COMBAT AI TEST")
	print("=" .repeat(60))
	print("")
	print("  US Rifle Squad spawned at %s (player-controlled)" % us_pos)
	print("  VC Rifle Squad spawned at %s (AI-controlled)" % vc_pos)
	print("")
	print("  Distance: %.0fm - within M16 range (550m) and AK47 range (400m)" % US_SPAWN_POS.distance_to(VC_SPAWN_POS))
	print("")
	print("  The VC squad should:")
	print("    1. Detect the US squad via SquadCommanderAI")
	print("    2. Acquire target and begin engaging")
	print("    3. Seek cover if suppressed")
	print("    4. Respond to threat level via ThreatHeatmap")
	print("")
	print("  Controls:")
	print("    F - Spawn additional VC squad")
	print("    G - Spawn VC squad on flank (east)")
	print("    T - Toggle AI debug overlay")
	print("    R - Reset test")
	print("")
	print("=" .repeat(60))


func _clear_combat_area() -> void:
	# Clear vegetation in a 200m radius around combat zone
	var center := (US_SPAWN_POS + VC_SPAWN_POS) / 2.0
	if TerrainClearingSystem and TerrainClearingSystem.has_method("clear_area"):
		TerrainClearingSystem.clear_area(center, 100.0)
	elif TerrainClearingSystem and TerrainClearingSystem.has_method("apply_clearing_damage"):
		TerrainClearingSystem.apply_clearing_damage(center, 100.0, 1.0)


func _spawn_cover_objects() -> void:
	# Spawn some sandbag positions in the combat zone
	var cover_positions: Array = [
		Vector3(-15.0, 0.0, 0.0),  # West cover
		Vector3(15.0, 0.0, 0.0),   # East cover
		Vector3(0.0, 0.0, -10.0),  # North of center
		Vector3(0.0, 0.0, 10.0),   # South of center
	]
	for pos in cover_positions:
		TestSceneBase.spawn_cover_at(self, pos)


func _connect_debug_signals(squad: Node3D) -> void:
	if squad.has_signal("suppression_changed"):
		squad.suppression_changed.connect(_on_suppression_changed.bind(squad))
	if squad.has_signal("target_acquired"):
		squad.target_acquired.connect(_on_target_acquired.bind(squad))
	if squad.has_signal("started_firing"):
		squad.started_firing.connect(_on_started_firing.bind(squad))
	if squad.has_signal("stopped_firing"):
		squad.stopped_firing.connect(_on_stopped_firing.bind(squad))


func _make_squad(player: bool, faction: int = GameEnums.Faction.US_ARMY) -> Node3D:
	var squad: Squad = Squad.new()
	var data := SquadData.new()

	# Configure based on faction
	match faction:
		GameEnums.Faction.US_ARMY:
			data.display_name = "US Rifle Squad"
			data.faction = GameEnums.Faction.US_ARMY
			squad.primary_weapon = "m16"
		GameEnums.Faction.VC:
			data.display_name = "VC Infantry"
			data.faction = GameEnums.Faction.VC
			squad.primary_weapon = "ak47"
		GameEnums.Faction.NVA:
			data.display_name = "NVA Infantry"
			data.faction = GameEnums.Faction.NVA
			squad.primary_weapon = "ak47"
		_:
			data.display_name = "Infantry Squad"
			data.faction = faction
			squad.primary_weapon = "ak47"

	data.squad_size = 10
	data.health_per_soldier = 100.0
	data.attack_range = 300.0  # M16/AK47 effective range
	data.move_speed = 5.0
	data.training_level = 1  # REGULAR
	# Slope parameters: infantry has the highest verticality
	data.max_slope = 0.65          # Can climb up to ~60 degrees
	data.slope_speed_penalty = 0.7 # At max slope, moves at 30% speed
	data.can_capture = true
	squad.data = data
	squad.is_player_controlled = player

	# Add to groups for selection and unit management
	squad.add_to_group("all_units")
	if player:
		squad.add_to_group("player_units")
		squad.add_to_group("selectable_units")
	else:
		squad.add_to_group("enemy_units")

	return squad


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed:
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_F:
			_spawn_enemy_squad(Vector3(0.0, 0.0, -100.0))  # North
		KEY_G:
			_spawn_enemy_squad(Vector3(80.0, 0.0, -20.0))  # East flank
		KEY_T:
			_toggle_debug_overlay()
		KEY_R:
			_reset_test()


func _spawn_enemy_squad(spawn_pos: Vector3) -> void:
	var squad: Node3D = _make_squad(false, GameEnums.Faction.VC)
	add_child(squad)
	# Place on terrain surface
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		spawn_pos.y = terrain.get_height_at(spawn_pos) + 0.1
	squad.global_position = spawn_pos
	enemy_squads.append(squad)
	_connect_debug_signals(squad)
	print("[InfantryTest] Spawned VC squad at %s - AI will engage autonomously" % spawn_pos)


func _toggle_debug_overlay() -> void:
	_debug_overlay_visible = not _debug_overlay_visible
	# TODO: Implement threat heatmap visualization
	print("[InfantryTest] Debug overlay: %s" % ("ON" if _debug_overlay_visible else "OFF"))

	if _debug_overlay_visible and AITickManager:
		var stats: Dictionary = AITickManager.get_perf_stats()
		print("  Registered commanders: %d" % stats.get("registered_commanders", 0))
		print("  Heatmap cells: %d" % stats.get("heatmap_cells", 0))
		print("  Last tick: %.1fms" % stats.get("last_tick_ms", 0.0))


func _reset_test() -> void:
	print("[InfantryTest] Resetting test...")
	# Remove all squads
	for squad in player_squads:
		if is_instance_valid(squad):
			squad.queue_free()
	for squad in enemy_squads:
		if is_instance_valid(squad):
			squad.queue_free()
	player_squads.clear()
	enemy_squads.clear()
	# Respawn after a frame
	call_deferred("_ready")


func _on_suppression_changed(amount: float, squad: Node) -> void:
	var name: String = squad.data.display_name if squad.data else squad.name
	print("[Combat] %s suppression: %.0f%%" % [name, amount * 100.0])


func _on_target_acquired(target: Node, squad: Node) -> void:
	var squad_name: String = squad.data.display_name if squad.data else squad.name
	var target_name: String = "Unknown"
	if target and target.has_method("get") and target.data:
		target_name = target.data.display_name
	print("[Combat] %s acquired target: %s" % [squad_name, target_name])


func _on_started_firing(target: Node, squad: Node) -> void:
	var squad_name: String = squad.data.display_name if squad.data else squad.name
	print("[Combat] %s ENGAGING!" % squad_name)


func _on_stopped_firing(squad: Node) -> void:
	var squad_name: String = squad.data.display_name if squad.data else squad.name
	print("[Combat] %s ceased fire" % squad_name)


func _on_slope_blocked(pos: Vector3, slope: float, squad: Node) -> void:
	print("[Movement] %s blocked by slope %.2f at %s" % [squad.name, slope, pos])


