class_name BattleLogPanel extends PanelContainer
## Scrolling battle log (bottom strip) fed entirely by BattleSignals events.
## Signal-driven: no polling, no group scans. Entries are timestamped with
## mission time and color-coded by category (combat, logistics, construction).

const MilitaryTheme = preload("res://battle_system/ui/military_theme.gd")

const MAX_ENTRIES := 50
const FONT_SIZE := 12

## Minimum seconds between repeated entries of the same throttle key
const THROTTLE_WINDOW := 5.0

var player_faction: int = 0  # GameEnums.Faction.US_ARMY

var _log_label: RichTextLabel
var _entries: PackedStringArray = []
var _elapsed: float = 0.0
var _throttle_times: Dictionary = {}  # key: String -> last entry time
## Signal connections made in _ready, disconnected in _exit_tree
var _connections: Array[Array] = []  # [Signal, Callable] pairs


func _ready() -> void:
	add_theme_stylebox_override("panel", MilitaryTheme.create_panel_stylebox())
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)

	var header := Label.new()
	header.text = "BATTLE LOG"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	vbox.add_child(header)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_active = true
	_log_label.scroll_following = true
	_log_label.fit_content = false
	_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	vbox.add_child(_log_label)

	_connect_bus()


func _process(delta: float) -> void:
	# Mission clock only; stops with game pause. No UI work here.
	_elapsed += delta


func _exit_tree() -> void:
	for pair in _connections:
		var sig: Signal = pair[0]
		var callable: Callable = pair[1]
		if sig.is_connected(callable):
			sig.disconnect(callable)
	_connections.clear()


# =============================================================================
# PUBLIC API
# =============================================================================

## Append an entry with mission timestamp. Colors from MilitaryTheme.
func log_entry(message: String, color: Color = MilitaryTheme.COL_TEXT_PRIMARY, throttle_key: String = "") -> void:
	if throttle_key != "":
		var last: float = _throttle_times.get(throttle_key, -THROTTLE_WINDOW)
		if _elapsed - last < THROTTLE_WINDOW:
			return
		_throttle_times[throttle_key] = _elapsed

	var minutes: int = int(_elapsed) / 60
	var seconds: int = int(_elapsed) % 60
	var line := "[color=#%s]%02d:%02d[/color]  [color=#%s]%s[/color]" % [
		MilitaryTheme.COL_TEXT_SECONDARY.to_html(false),
		minutes, seconds,
		color.to_html(false), message,
	]
	_entries.append(line)
	if _entries.size() > MAX_ENTRIES:
		_entries.remove_at(0)
	_log_label.text = "\n".join(_entries)


# =============================================================================
# SIGNAL WIRING
# =============================================================================

func _connect_bus() -> void:
	if not BattleSignals:
		return
	_bus(BattleSignals.enemy_spotted, _on_enemy_spotted)
	_bus(BattleSignals.unit_died, _on_unit_died)
	_bus(BattleSignals.firebase_under_attack, _on_firebase_under_attack)
	_bus(BattleSignals.ambush_triggered, _on_ambush_triggered)
	_bus(BattleSignals.wave_incoming, _on_wave_incoming)
	_bus(BattleSignals.wave_defeated, _on_wave_defeated)
	_bus(BattleSignals.artillery_barrage_incoming, _on_artillery_incoming)
	_bus(BattleSignals.sapper_assault_detected, _on_sapper_assault)
	_bus(BattleSignals.supply_line_cut, _on_supply_line_cut)
	_bus(BattleSignals.supply_line_restored, _on_supply_line_restored)
	_bus(BattleSignals.helicopter_destroyed, _on_helicopter_destroyed)
	_bus(BattleSignals.supply_delivered, _on_supply_delivered)
	_bus(BattleSignals.supply_refunded, _on_supply_refunded)
	_bus(BattleSignals.convoy_departed, _on_convoy_departed)
	_bus(BattleSignals.convoy_arrived, _on_convoy_arrived)
	_bus(BattleSignals.reinforcement_arrived, _on_reinforcement_arrived)
	_bus(BattleSignals.construction_complete, _on_construction_complete)
	_bus(BattleSignals.building_destroyed, _on_building_destroyed)
	_bus(BattleSignals.firebase_established, _on_firebase_established)
	_bus(BattleSignals.firebase_activated, _on_firebase_activated)
	_bus(BattleSignals.objective_complete, _on_objective_complete)
	_bus(BattleSignals.mission_started, _on_mission_started)


func _bus(sig: Signal, callable: Callable) -> void:
	sig.connect(callable)
	_connections.append([sig, callable])


# =============================================================================
# NAME HELPERS
# =============================================================================

func _unit_label(unit: Node3D) -> String:
	if not is_instance_valid(unit):
		return "Unit"
	var data: Variant = unit.get("data") if "data" in unit else null
	if data is Resource and "display_name" in data and data.display_name != "":
		return data.display_name
	return String(unit.name).capitalize()


func _unit_faction(unit: Node3D) -> int:
	if not is_instance_valid(unit):
		return -1
	var data: Variant = unit.get("data") if "data" in unit else null
	if data is Resource and "faction" in data:
		return data.faction
	return -1


func _place_label(node: Node3D) -> String:
	if not is_instance_valid(node):
		return "position"
	return String(node.name).capitalize()


func _building_type_label(building_type: int) -> String:
	var keys: Array = GameEnums.BuildingType.keys() if "BuildingType" in GameEnums else []
	if building_type >= 0 and building_type < keys.size():
		return String(keys[building_type]).capitalize()
	return "Building"


# =============================================================================
# EVENT HANDLERS
# =============================================================================

func _on_enemy_spotted(_enemy: Node3D, _by_unit: Node3D) -> void:
	log_entry("Enemy spotted", MilitaryTheme.COL_STATE_SUPPRESSED, "enemy_spotted")


func _on_unit_died(unit: Node3D, _killer: Node3D) -> void:
	if _unit_faction(unit) == player_faction:
		log_entry("%s lost" % _unit_label(unit), MilitaryTheme.COL_STATE_COMBAT)
	else:
		log_entry("%s destroyed" % _unit_label(unit), MilitaryTheme.COL_TEXT_PRIMARY, "enemy_killed")


func _on_firebase_under_attack(firebase: Node3D, _attacker: Node3D) -> void:
	log_entry("%s under attack!" % _place_label(firebase), MilitaryTheme.COL_STATE_COMBAT, "fb_attack")


func _on_ambush_triggered(_position: Vector3, attackers: int) -> void:
	log_entry("Ambush! %d attackers" % attackers, MilitaryTheme.COL_STATE_COMBAT)


func _on_wave_incoming(wave_number: int, enemy_count: int) -> void:
	log_entry("Wave %d incoming - %d enemies" % [wave_number, enemy_count], MilitaryTheme.COL_STATE_COMBAT)


func _on_wave_defeated(wave_number: int) -> void:
	log_entry("Wave %d defeated" % wave_number, MilitaryTheme.COL_TEXT_HIGHLIGHT)


func _on_artillery_incoming(_position: Vector3) -> void:
	log_entry("Incoming artillery barrage!", MilitaryTheme.COL_STATE_COMBAT, "arty_incoming")


func _on_sapper_assault(count: int) -> void:
	log_entry("Sapper assault detected - %d sappers" % count, MilitaryTheme.COL_STATE_COMBAT)


func _on_supply_line_cut(firebase: Node3D) -> void:
	log_entry("Supply line to %s cut" % _place_label(firebase), MilitaryTheme.COL_STATE_COMBAT)


func _on_supply_line_restored(firebase: Node3D) -> void:
	log_entry("Supply line to %s restored" % _place_label(firebase), MilitaryTheme.COL_STATE_WORKING)


func _on_helicopter_destroyed(helicopter: Node3D) -> void:
	log_entry("%s shot down" % _unit_label(helicopter), MilitaryTheme.COL_STATE_COMBAT)


func _on_supply_delivered(destination: Node3D, amount: float) -> void:
	log_entry("+%d supply delivered to %s" % [int(amount), _place_label(destination)], MilitaryTheme.COL_STATE_WORKING, "supply_delivered")


func _on_supply_refunded(amount: float, reason: String) -> void:
	log_entry("+%d supply refunded (%s cancelled)" % [int(amount), reason], MilitaryTheme.COL_STATE_WORKING)


func _on_convoy_departed(_convoy: Node3D) -> void:
	log_entry("Supply convoy departed", MilitaryTheme.COL_TEXT_PRIMARY, "convoy_departed")


func _on_convoy_arrived(_convoy: Node3D, destination: Node3D) -> void:
	log_entry("Supply convoy arrived at %s" % _place_label(destination), MilitaryTheme.COL_STATE_WORKING)


func _on_reinforcement_arrived(unit: Node3D, _destination: Node3D) -> void:
	log_entry("%s reinforcements arrived" % _unit_label(unit), MilitaryTheme.COL_STATE_WORKING)


func _on_construction_complete(building: Node3D) -> void:
	log_entry("%s construction complete" % _place_label(building), MilitaryTheme.COL_TEXT_PRIMARY)


func _on_building_destroyed(_zone: Node3D, building_type: int) -> void:
	log_entry("%s destroyed" % _building_type_label(building_type), MilitaryTheme.COL_STATE_COMBAT)


func _on_firebase_established(firebase: Node3D) -> void:
	log_entry("%s established" % _place_label(firebase), MilitaryTheme.COL_TEXT_HIGHLIGHT)


func _on_firebase_activated(firebase: Node3D) -> void:
	log_entry("%s operational" % _place_label(firebase), MilitaryTheme.COL_TEXT_HIGHLIGHT)


func _on_objective_complete(objective_id: String) -> void:
	log_entry("Objective complete: %s" % objective_id.capitalize(), MilitaryTheme.COL_TEXT_HIGHLIGHT)


func _on_mission_started(mission_name: String) -> void:
	log_entry("Mission started: %s" % mission_name, MilitaryTheme.COL_TEXT_HIGHLIGHT)
