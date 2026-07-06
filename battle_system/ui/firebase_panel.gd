class_name FirebasePanel extends PanelContainer
## Right-side selected-firebase panel: name, level, HP bar, supply bar,
## and structures list vs slot cap (per ui-vision.md concept).
## Focus follows firebase lifecycle signals; structure list rebuilds on
## events. HP/supply bars refresh on a 1s timer only while visible
## (Firebase has no per-point change signals). No group scans.
## Support-request cooldowns deferred until AirSupportManager exposes them.

const MilitaryTheme = preload("res://battle_system/ui/military_theme.gd")

const LEVEL_NAMES: Array[String] = ["Patrol Base", "Fire Support Base", "Major Firebase"]
const REFRESH_INTERVAL := 1.0
const MAX_STRUCTURE_ROWS := 8

var _firebase: Node3D = null

var _name_label: Label
var _level_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _supply_bar: ProgressBar
var _supply_label: Label
var _structures_header: Label
var _structures_list: Label
var _refresh_timer: Timer
## Bus connections made in _ready, disconnected in _exit_tree
var _bus_connections: Array[Array] = []  # [Signal, Callable] pairs


func _ready() -> void:
	add_theme_stylebox_override("panel", MilitaryTheme.create_panel_stylebox())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_HIGHLIGHT)
	vbox.add_child(_name_label)

	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 11)
	_level_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	vbox.add_child(_level_label)

	_hp_bar = _make_bar(vbox, MilitaryTheme.COL_HEALTH_FULL)
	_hp_label = _make_bar_label(vbox)
	_supply_bar = _make_bar(vbox, MilitaryTheme.COL_AMMO_FULL)
	_supply_label = _make_bar_label(vbox)

	_structures_header = Label.new()
	_structures_header.add_theme_font_size_override("font_size", 11)
	_structures_header.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	vbox.add_child(_structures_header)

	_structures_list = Label.new()
	_structures_list.add_theme_font_size_override("font_size", 11)
	_structures_list.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_PRIMARY)
	vbox.add_child(_structures_list)

	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = REFRESH_INTERVAL
	_refresh_timer.timeout.connect(_refresh_bars)
	add_child(_refresh_timer)

	if BattleSignals:
		_bus(BattleSignals.firebase_established, _on_firebase_established)
		_bus(BattleSignals.firebase_activated, _on_firebase_activated)
		_bus(BattleSignals.firebase_deactivated, _on_firebase_deactivated)
		_bus(BattleSignals.building_selected, _on_building_selected)
		_bus(BattleSignals.construction_complete, _on_construction_complete)


func _bus(sig: Signal, callable: Callable) -> void:
	sig.connect(callable)
	_bus_connections.append([sig, callable])


func _exit_tree() -> void:
	for pair in _bus_connections:
		var sig: Signal = pair[0]
		var callable: Callable = pair[1]
		if sig.is_connected(callable):
			sig.disconnect(callable)
	_bus_connections.clear()
	_disconnect_firebase()


# =============================================================================
# PUBLIC API
# =============================================================================

## Focus the panel on a firebase (null hides the panel)
func set_firebase(firebase: Node3D) -> void:
	if firebase == _firebase:
		return
	_disconnect_firebase()
	_firebase = firebase

	if not is_instance_valid(_firebase):
		_firebase = null
		visible = false
		_refresh_timer.stop()
		return

	if _firebase.has_signal("firebase_level_changed"):
		_firebase.firebase_level_changed.connect(_on_level_changed)
	if _firebase.has_signal("building_constructed"):
		_firebase.building_constructed.connect(_on_building_constructed)
	if _firebase.has_signal("firebase_destroyed"):
		_firebase.firebase_destroyed.connect(_on_firebase_destroyed)

	visible = true
	_refresh_timer.start()
	_refresh_all()


func get_firebase() -> Node3D:
	return _firebase


# =============================================================================
# UI CONSTRUCTION HELPERS
# =============================================================================

func _make_bar(parent: Control, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", MilitaryTheme.create_progress_bg_stylebox())
	bar.add_theme_stylebox_override("fill", MilitaryTheme.create_progress_fill_stylebox(fill_color))
	parent.add_child(bar)
	return bar


func _make_bar_label(parent: Control) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	parent.add_child(label)
	return label


# =============================================================================
# REFRESH
# =============================================================================

func _refresh_all() -> void:
	if not is_instance_valid(_firebase):
		set_firebase(null)
		return

	var fb_name: String = _firebase.firebase_name if "firebase_name" in _firebase else String(_firebase.name)
	_name_label.text = fb_name.to_upper()

	var level: int = _firebase.level if "level" in _firebase else 0
	var level_name: String = LEVEL_NAMES[level] if level >= 0 and level < LEVEL_NAMES.size() else "Unknown"
	_level_label.text = "Level %d - %s" % [level + 1, level_name]

	_refresh_bars()
	_refresh_structures()


func _refresh_bars() -> void:
	if not is_instance_valid(_firebase):
		set_firebase(null)
		return

	var hp: float = _firebase.current_health if "current_health" in _firebase else 0.0
	var hp_max: float = _firebase.total_health if "total_health" in _firebase else 1.0
	_hp_bar.max_value = maxf(hp_max, 1.0)
	_hp_bar.value = hp
	_hp_label.text = "HP  %d / %d" % [int(hp), int(hp_max)]
	_hp_bar.add_theme_stylebox_override("fill",
		MilitaryTheme.create_progress_fill_stylebox(MilitaryTheme.health_color(hp / maxf(hp_max, 1.0))))

	var supply: float = _firebase.supply_level if "supply_level" in _firebase else 0.0
	var supply_max: float = _firebase.max_supply if "max_supply" in _firebase else 1.0
	_supply_bar.max_value = maxf(supply_max, 1.0)
	_supply_bar.value = supply
	_supply_label.text = "SUPPLY  %d / %d" % [int(supply), int(supply_max)]


func _refresh_structures() -> void:
	if not is_instance_valid(_firebase):
		return

	var buildings: Array[Node3D] = _firebase.buildings if "buildings" in _firebase else []
	var max_zones: int = _firebase.get_max_zones() if _firebase.has_method("get_max_zones") else 0

	# Count structures by display name
	var counts: Dictionary = {}
	var valid_total: int = 0
	for building in buildings:
		if not is_instance_valid(building):
			continue
		valid_total += 1
		var label: String = String(building.name).capitalize()
		counts[label] = int(counts.get(label, 0)) + 1

	_structures_header.text = "STRUCTURES  %d / %d" % [valid_total, max_zones]

	var lines: PackedStringArray = []
	var keys: Array = counts.keys()
	keys.sort()
	for key in keys:
		if lines.size() >= MAX_STRUCTURE_ROWS:
			lines.append("+ %d more..." % (keys.size() - MAX_STRUCTURE_ROWS))
			break
		var count: int = counts[key]
		lines.append("%dx %s" % [count, key] if count > 1 else String(key))
	_structures_list.text = "\n".join(lines) if lines.size() > 0 else "None"


# =============================================================================
# EVENT HANDLERS
# =============================================================================

func _disconnect_firebase() -> void:
	if not is_instance_valid(_firebase):
		return
	if _firebase.has_signal("firebase_level_changed") and _firebase.firebase_level_changed.is_connected(_on_level_changed):
		_firebase.firebase_level_changed.disconnect(_on_level_changed)
	if _firebase.has_signal("building_constructed") and _firebase.building_constructed.is_connected(_on_building_constructed):
		_firebase.building_constructed.disconnect(_on_building_constructed)
	if _firebase.has_signal("firebase_destroyed") and _firebase.firebase_destroyed.is_connected(_on_firebase_destroyed):
		_firebase.firebase_destroyed.disconnect(_on_firebase_destroyed)


func _on_firebase_established(firebase: Node3D) -> void:
	# First firebase takes focus automatically; later ones only if none focused
	if _firebase == null:
		set_firebase(firebase)


func _on_firebase_activated(firebase: Node3D) -> void:
	set_firebase(firebase)


func _on_firebase_deactivated(firebase: Node3D) -> void:
	if firebase == _firebase:
		_refresh_all()


func _on_building_selected(building: Node3D) -> void:
	# Focus the firebase a selected building belongs to (future click-selection)
	if not is_instance_valid(building):
		return
	var owning_fb: Variant = building.get("owning_firebase") if "owning_firebase" in building else null
	if owning_fb is Node3D:
		set_firebase(owning_fb)


func _on_construction_complete(_building: Node3D) -> void:
	if is_instance_valid(_firebase):
		_refresh_structures()


func _on_level_changed(_firebase_ref: Node3D, _new_level: int) -> void:
	_refresh_all()


func _on_building_constructed(_firebase_ref: Node3D, _building: Node3D) -> void:
	_refresh_structures()


func _on_firebase_destroyed(_firebase_ref: Node3D) -> void:
	set_firebase(null)
