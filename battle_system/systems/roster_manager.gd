extends Node
## Autoload that manages the player's persistent company roster.
## Tracks units that survive between missions with their veterancy state.
## Persistence methods are stubbed for future campaign system integration.

# =============================================================================
# SIGNALS
# =============================================================================

## Emitted when roster changes (unit added/removed/updated)
signal roster_changed()

## Emitted when a unit is registered from the roster
signal unit_deployed(unit: Node3D, roster_id: String)

## Emitted when a unit dies and is removed from roster
signal unit_lost(roster_id: String, unit_name: String)

# =============================================================================
# STATE
# =============================================================================

## Currently selected tactic for the mission (set before battle starts)
var active_tactic: TacticData = null

## The persistent roster: roster_id -> entry dictionary
## Each entry: {
##   "display_name": String,
##   "unit_data_path": String (resource path to SquadData.tres),
##   "veterancy_state": Dictionary (serialized VeterancyState),
##   "is_alive": bool,
##   "last_mission_id": String,
##   "custom_name": String (player-assigned nickname),
##   "battle_count": int,
## }
var roster: Dictionary = {}

## Maps unit instance_id -> roster_id for quick lookup during battle
var _active_units: Dictionary = {}

## Current mission ID (for tracking which mission units participated in)
var _current_mission_id: String = ""

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	print("[RosterManager] Initialized")


# =============================================================================
# MISSION LIFECYCLE
# =============================================================================

## Called when a new mission starts
func start_mission(mission_id: String) -> void:
	_current_mission_id = mission_id
	_active_units.clear()
	print("[RosterManager] Mission started: %s" % mission_id)


## Called when mission ends - writes back all surviving units
func record_mission_complete() -> void:
	var _vet_tracker: Node = get_node_or_null("/root/VeterancyTracker")

	for uid: int in _active_units:
		var roster_id: String = _active_units[uid]
		if roster_id.is_empty():
			continue

		if not roster_id in roster:
			continue

		var entry: Dictionary = roster[roster_id]
		if not entry.get("is_alive", true):
			continue

		# Try to get the unit's current veterancy state
		# Note: unit may have been freed if battle ended, so this is best-effort
		entry["last_mission_id"] = _current_mission_id
		entry["battle_count"] = entry.get("battle_count", 0) + 1

	_active_units.clear()
	roster_changed.emit()
	print("[RosterManager] Mission complete. Roster updated.")


# =============================================================================
# UNIT DEPLOYMENT
# =============================================================================

## Registers a unit when it's deployed to the battlefield.
## If roster_id is provided and exists in roster, restores veterancy state.
## If roster_id is empty, this unit is session-only (not persisted).
func register_unit_on_deploy(unit: Node3D, roster_id: String = "") -> void:
	if not is_instance_valid(unit):
		return

	var uid: int = unit.get_instance_id()
	_active_units[uid] = roster_id

	# If this is a rostered unit, restore veterancy
	if not roster_id.is_empty() and roster_id in roster:
		var entry: Dictionary = roster[roster_id]
		var vet_state: VeterancyState = null

		if "veterancy_state" in entry and entry["veterancy_state"] is Dictionary:
			vet_state = VeterancyState.from_dict(entry["veterancy_state"])

		# Register with veterancy tracker
		var vet_tracker: Node = get_node_or_null("/root/VeterancyTracker")
		if vet_tracker != null:
			vet_tracker.register_unit(unit, vet_state)

		unit_deployed.emit(unit, roster_id)
		print("[RosterManager] Deployed rostered unit: %s" % entry.get("display_name", roster_id))
	else:
		# Session-only unit - just register with default veterancy
		var vet_tracker: Node = get_node_or_null("/root/VeterancyTracker")
		if vet_tracker != null:
			vet_tracker.register_unit(unit, null)


## Records when a unit dies - marks roster entry as dead
func record_unit_death(unit: Node3D) -> void:
	if not is_instance_valid(unit):
		return

	var uid: int = unit.get_instance_id()
	var roster_id: String = _active_units.get(uid, "")

	if roster_id.is_empty():
		# Session-only unit, no roster to update
		_active_units.erase(uid)
		return

	if roster_id in roster:
		var entry: Dictionary = roster[roster_id]
		var unit_name: String = entry.get("display_name", roster_id)
		entry["is_alive"] = false
		entry["last_mission_id"] = _current_mission_id

		# Save final veterancy state
		var vet_tracker: Node = get_node_or_null("/root/VeterancyTracker")
		if vet_tracker != null:
			var state: VeterancyState = vet_tracker.get_state(unit)
			if state != null:
				entry["veterancy_state"] = state.to_dict()

		unit_lost.emit(roster_id, unit_name)
		roster_changed.emit()
		print("[RosterManager] Unit KIA: %s" % unit_name)

	_active_units.erase(uid)


# =============================================================================
# ROSTER MANAGEMENT
# =============================================================================

## Adds a new unit to the roster
func add_to_roster(
	roster_id: String,
	display_name: String,
	unit_data_path: String,
	starting_level: int = 0
) -> void:
	if roster_id.is_empty():
		push_error("[RosterManager] Cannot add unit with empty roster_id")
		return

	var vet_state: VeterancyState = VeterancyState.create_at_level(starting_level)

	roster[roster_id] = {
		"display_name": display_name,
		"unit_data_path": unit_data_path,
		"veterancy_state": vet_state.to_dict(),
		"is_alive": true,
		"last_mission_id": "",
		"custom_name": "",
		"battle_count": 0,
	}

	roster_changed.emit()


## Removes a unit from the roster entirely
func remove_from_roster(roster_id: String) -> void:
	if roster_id in roster:
		roster.erase(roster_id)
		roster_changed.emit()


## Gets a roster entry by ID
func get_roster_entry(roster_id: String) -> Dictionary:
	return roster.get(roster_id, {})


## Returns array of all alive roster IDs
func get_alive_roster_ids() -> Array[String]:
	var alive: Array[String] = []
	for rid: String in roster:
		var entry: Dictionary = roster[rid]
		if entry.get("is_alive", false):
			alive.append(rid)
	return alive


## Returns count of alive units in roster
func get_alive_count() -> int:
	var count: int = 0
	for rid: String in roster:
		if roster[rid].get("is_alive", false):
			count += 1
	return count


## Sets a custom nickname for a rostered unit
func set_custom_name(roster_id: String, custom_name: String) -> void:
	if roster_id in roster:
		roster[roster_id]["custom_name"] = custom_name
		roster_changed.emit()


# =============================================================================
# PERSISTENCE (STUBBED)
# =============================================================================

## Saves roster to disk as JSON
func save_to_disk(path: String = "user://roster.json") -> bool:
	var save_data: Dictionary = {
		"version": 1,
		"roster": roster,
		"active_tactic_id": active_tactic.tactic_id if active_tactic else "",
	}

	var json_string: String = JSON.stringify(save_data, "\t")

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[RosterManager] Failed to open file for writing: %s" % path)
		return false

	file.store_string(json_string)
	file.close()

	print("[RosterManager] Saved roster to: %s" % path)
	return true


## Loads roster from disk JSON
func load_from_disk(path: String = "user://roster.json") -> bool:
	if not FileAccess.file_exists(path):
		print("[RosterManager] No roster file found at: %s" % path)
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[RosterManager] Failed to open file for reading: %s" % path)
		return false

	var json_string: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	var error: Error = json.parse(json_string)
	if error != OK:
		push_error("[RosterManager] JSON parse error: %s" % json.get_error_message())
		return false

	var data: Variant = json.get_data()
	if not data is Dictionary:
		push_error("[RosterManager] Invalid roster file format")
		return false

	var save_data: Dictionary = data
	var version: int = save_data.get("version", 0)

	if version != 1:
		push_warning("[RosterManager] Unknown roster version: %d" % version)

	roster = save_data.get("roster", {})

	# Note: active_tactic needs to be loaded by the campaign system
	# since it references a TacticData resource

	roster_changed.emit()
	print("[RosterManager] Loaded roster from: %s (%d units)" % [path, roster.size()])
	return true


## Clears the entire roster (for new campaign)
func clear_roster() -> void:
	roster.clear()
	_active_units.clear()
	active_tactic = null
	roster_changed.emit()


# =============================================================================
# DEBUG
# =============================================================================

func print_roster_summary() -> void:
	print("=== ROSTER SUMMARY ===")
	print("Total units: %d" % roster.size())
	print("Alive: %d" % get_alive_count())
	print("Active tactic: %s" % (active_tactic.display_name if active_tactic else "None"))
	for rid: String in roster:
		var entry: Dictionary = roster[rid]
		var status: String = "ALIVE" if entry.get("is_alive", false) else "KIA"
		var vet: Dictionary = entry.get("veterancy_state", {})
		var level: int = vet.get("level", 0)
		print("  [%s] %s - Level %d (%s)" % [status, entry.get("display_name", rid), level, rid])
	print("======================")
