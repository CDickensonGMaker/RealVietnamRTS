extends Node
class_name SaveManager
## SaveManager - Handles save/load operations and auto-save
## Per PRD: Saves at mission start, map expansion, 10-minute auto-save

signal save_started
signal save_completed(save_path: String)
signal save_failed(error: String)
signal load_started
signal load_completed
signal load_failed(error: String)
signal autosave_triggered

const SAVE_DIR := "user://saves/"
const AUTOSAVE_INTERVAL := 600.0  # 10 minutes
const MAX_AUTOSAVES := 3

## Auto-save state
var _autosave_timer: float = 0.0
var _autosave_enabled: bool = true
var _autosave_count: int = 0

## Current save info
var current_save_path: String = ""
var last_save_time: float = 0.0


func _ready() -> void:
	# Ensure save directory exists
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	# Connect to mission signals for checkpoint saves
	if BattleSignals:
		BattleSignals.mission_started.connect(_on_mission_started)

	print("[SaveManager] Initialized - Autosave every %.0f seconds" % AUTOSAVE_INTERVAL)


func _process(delta: float) -> void:
	if _autosave_enabled:
		_autosave_timer += delta
		if _autosave_timer >= AUTOSAVE_INTERVAL:
			_autosave_timer = 0.0
			_trigger_autosave()


# =============================================================================
# SAVE OPERATIONS
# =============================================================================

## Save game to file
func save_game(save_name: String = "") -> bool:
	save_started.emit()

	# Generate save name if not provided
	if save_name.is_empty():
		save_name = "save_%s" % Time.get_datetime_string_from_system().replace(":", "-")

	var save_path: String = SAVE_DIR + save_name + ".sav"

	# Collect game state
	var save_data: Dictionary = _collect_save_data()

	# Serialize to JSON
	var json_string: String = JSON.stringify(save_data, "\t")

	# Write to file
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if not file:
		var error := "Failed to open save file: %s" % save_path
		save_failed.emit(error)
		push_error("[SaveManager] " + error)
		return false

	file.store_string(json_string)
	file.close()

	current_save_path = save_path
	last_save_time = Time.get_ticks_msec() / 1000.0

	save_completed.emit(save_path)
	print("[SaveManager] Game saved: %s" % save_path)
	return true


## Quick save
func quick_save() -> bool:
	return save_game("quicksave")


## Auto-save
func _trigger_autosave() -> void:
	autosave_triggered.emit()

	_autosave_count = (_autosave_count % MAX_AUTOSAVES) + 1
	var save_name: String = "autosave_%d" % _autosave_count

	if save_game(save_name):
		print("[SaveManager] Auto-save complete: autosave_%d" % _autosave_count)


## Checkpoint save (mission events)
func checkpoint_save(reason: String) -> bool:
	var save_name: String = "checkpoint_%s_%s" % [
		reason,
		Time.get_datetime_string_from_system().replace(":", "-")
	]
	return save_game(save_name)


func _on_mission_started(_mission_name: String) -> void:
	checkpoint_save("mission_start")
	_autosave_timer = 0.0  # Reset autosave timer


# =============================================================================
# LOAD OPERATIONS
# =============================================================================

## Load game from file
func load_game(save_path: String) -> bool:
	load_started.emit()

	if not FileAccess.file_exists(save_path):
		var error := "Save file not found: %s" % save_path
		load_failed.emit(error)
		push_error("[SaveManager] " + error)
		return false

	# Read file
	var file := FileAccess.open(save_path, FileAccess.READ)
	if not file:
		var error := "Failed to open save file: %s" % save_path
		load_failed.emit(error)
		push_error("[SaveManager] " + error)
		return false

	var json_string: String = file.get_as_text()
	file.close()

	# Parse JSON
	var json := JSON.new()
	var parse_result: Error = json.parse(json_string)
	if parse_result != OK:
		var error := "Failed to parse save file: %s" % json.get_error_message()
		load_failed.emit(error)
		push_error("[SaveManager] " + error)
		return false

	var save_data: Dictionary = json.data

	# Validate save data
	if not _validate_save_data(save_data):
		var error := "Invalid save data format"
		load_failed.emit(error)
		push_error("[SaveManager] " + error)
		return false

	# Apply save data
	_apply_save_data(save_data)

	current_save_path = save_path
	load_completed.emit()
	print("[SaveManager] Game loaded: %s" % save_path)
	return true


## Quick load
func quick_load() -> bool:
	return load_game(SAVE_DIR + "quicksave.sav")


# =============================================================================
# SAVE DATA COLLECTION
# =============================================================================

func _collect_save_data() -> Dictionary:
	var data := {
		"version": "1.0",
		"timestamp": Time.get_datetime_string_from_system(),
		"game_time": 0.0,
		"mission": {},
		"firebases": [],
		"units": [],
		"buildings": [],
		"terrain": {},
		"resources": {},
		"doctrine": "",
	}

	# Game time
	var ai_director: Node = get_node_or_null("/root/AIDirector")
	if ai_director and ai_director.has_method("get"):
		data["game_time"] = ai_director.game_time

	# Mission state
	var mission_manager: Node = get_node_or_null("/root/MissionManager")
	if mission_manager and mission_manager.current_mission:
		var mission = mission_manager.current_mission
		data["mission"] = {
			"id": mission.mission_id,
			"elapsed_time": mission.elapsed_time,
			"completed_objectives": mission.completed_objectives,
			"failed_objectives": mission.failed_objectives,
			"supply_remaining": mission.supply_remaining,
			"units_lost": mission.units_lost,
			"enemies_killed": mission.enemies_killed,
		}

	# Doctrine
	var doctrine_manager: Node = get_node_or_null("/root/DoctrineManager")
	if doctrine_manager and doctrine_manager.current_doctrine:
		data["doctrine"] = doctrine_manager.current_doctrine.doctrine_id

	# Firebases
	var firebases: Array[Node] = get_tree().get_nodes_in_group("firebases")
	for fb in firebases:
		if is_instance_valid(fb):
			data["firebases"].append(_serialize_firebase(fb))

	# Units
	var units: Array[Node] = get_tree().get_nodes_in_group("player_units")
	for unit in units:
		if is_instance_valid(unit):
			data["units"].append(_serialize_unit(unit))

	return data


func _serialize_firebase(fb: Node3D) -> Dictionary:
	var fb_data := {
		"name": fb.name,
		"position": _vec3_to_array(fb.global_position),
		"level": 0,
		"supply_level": 0.0,
		"health": 0.0,
		"is_active": false,
		"buildings": [],
	}

	if fb.has_method("get"):
		if fb.get("level") != null:
			fb_data["level"] = fb.level
		if fb.get("supply_level") != null:
			fb_data["supply_level"] = fb.supply_level
		if fb.get("current_health") != null:
			fb_data["health"] = fb.current_health

	if fb.has_method("is_active"):
		fb_data["is_active"] = fb.is_active()

	# Serialize buildings in firebase
	if fb.has_method("get") and fb.get("construction_zones") != null:
		for zone in fb.construction_zones:
			if zone.is_complete() and zone.building_data:
				fb_data["buildings"].append({
					"type": zone.building_data.building_type,
					"position": _vec3_to_array(zone.global_position),
				})

	return fb_data


func _serialize_unit(unit: Node3D) -> Dictionary:
	var unit_data := {
		"name": unit.name,
		"position": _vec3_to_array(unit.global_position),
		"rotation": unit.rotation.y,
		"health": 100.0,
		"max_health": 100.0,
		"morale": 100.0,
		"ammo": 0,
		"water": 0,
		"unit_type": -1,
		"veterancy": 0,
	}

	if unit.has_method("get"):
		if unit.get("current_health") != null:
			unit_data["health"] = unit.current_health
		if unit.get("max_health") != null:
			unit_data["max_health"] = unit.max_health
		if unit.get("current_ammo") != null:
			unit_data["ammo"] = unit.current_ammo
		if unit.get("current_water") != null:
			unit_data["water"] = unit.current_water

	if unit.has_method("get_morale"):
		unit_data["morale"] = unit.get_morale()

	if unit.has_method("get") and unit.get("data") != null and unit.data:
		unit_data["unit_type"] = unit.data.unit_type

	return unit_data


# =============================================================================
# SAVE DATA APPLICATION
# =============================================================================

func _validate_save_data(data: Dictionary) -> bool:
	"""Validate save data has required fields"""
	var required: Array[String] = ["version", "timestamp"]
	for field in required:
		if not data.has(field):
			return false
	return true


func _apply_save_data(data: Dictionary) -> void:
	"""Apply loaded save data to game state"""
	# This would need to be implemented based on how the game
	# handles scene setup. For now, emit signals that other
	# systems can listen to.

	print("[SaveManager] Applying save data...")

	# Set doctrine
	if data.has("doctrine") and not data["doctrine"].is_empty():
		var doctrine_manager: Node = get_node_or_null("/root/DoctrineManager")
		if doctrine_manager and doctrine_manager.has_method("set_doctrine_by_id"):
			doctrine_manager.set_doctrine_by_id(data["doctrine"])

	# Note: Full implementation would require spawning units,
	# rebuilding firebases, etc. This is a framework for expansion.


# =============================================================================
# UTILITY
# =============================================================================

func _vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _array_to_vec3(a: Array) -> Vector3:
	if a.size() >= 3:
		return Vector3(a[0], a[1], a[2])
	return Vector3.ZERO


# =============================================================================
# PUBLIC API
# =============================================================================

## Get list of available saves
func get_save_list() -> Array[Dictionary]:
	var saves: Array[Dictionary] = []

	var dir := DirAccess.open(SAVE_DIR)
	if not dir:
		return saves

	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name != "":
		if file_name.ends_with(".sav"):
			var save_path: String = SAVE_DIR + file_name
			var file := FileAccess.open(save_path, FileAccess.READ)
			if file:
				var json_string: String = file.get_as_text()
				file.close()

				var json := JSON.new()
				if json.parse(json_string) == OK:
					var data: Dictionary = json.data
					saves.append({
						"path": save_path,
						"name": file_name.replace(".sav", ""),
						"timestamp": data.get("timestamp", "Unknown"),
						"mission": data.get("mission", {}).get("id", "Unknown"),
					})

		file_name = dir.get_next()

	dir.list_dir_end()

	# Sort by timestamp (newest first)
	saves.sort_custom(func(a, b): return a["timestamp"] > b["timestamp"])

	return saves


## Delete a save file
func delete_save(save_path: String) -> bool:
	if FileAccess.file_exists(save_path):
		var err := DirAccess.remove_absolute(save_path)
		return err == OK
	return false


## Enable/disable auto-save
func set_autosave_enabled(enabled: bool) -> void:
	_autosave_enabled = enabled


## Get autosave status
func is_autosave_enabled() -> bool:
	return _autosave_enabled
