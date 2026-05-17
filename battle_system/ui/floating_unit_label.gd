extends Node3D
class_name FloatingUnitLabel
## Enhanced floating label for units - replaces FloatingHealthBar.
## Shows NATO symbol placeholder, veterancy, HP, ammo, suppression, and name.
## Scales based on camera distance for readability at different zoom levels.

const MilitaryTheme = preload("res://battle_system/ui/military_theme.gd")

# =============================================================================
# CONFIGURATION
# =============================================================================

## Height above unit
@export var label_offset: float = 2.5

## Update rate (10Hz = 0.1s interval for performance)
const UPDATE_INTERVAL: float = 0.1

## Zoom thresholds for detail levels
const ZOOM_FULL: float = 30.0       # < 30m: Full visual stack
const ZOOM_MEDIUM: float = 60.0     # 30-60m: 70% size, hide name
const ZOOM_MINIMAL: float = 90.0    # 60-90m: 50% size, hide suppression/ammo
# > 90m: 4x4 dot only

# =============================================================================
# STATE
# =============================================================================

var _target_unit: Node3D = null
var _update_timer: float = 0.0
var _cached_camera_dist: float = 30.0

## Cached values to avoid redundant updates
var _cached_health_ratio: float = 1.0
var _cached_suppression: float = 0.0
var _cached_ammo_ratio: float = 1.0
var _cached_vet_level: int = 0
var _cached_faction: int = 0

## Culling optimization
var _is_culled: bool = false
const CULL_DISTANCE: float = 200.0  # Beyond this, fully pause updates

# =============================================================================
# VISUAL COMPONENTS
# =============================================================================

## SubViewport for Control-based UI rendered to 3D
var _viewport: SubViewport
var _viewport_sprite: Sprite3D

## Control tree root
var _ui_root: Control

## Placeholders (ColorRect for easy art replacement later)
var _symbol_slot: ColorRect        # 32x32 NATO symbol
var _echelon_slot: ColorRect       # 32x8 size amplifier
var _veterancy_slot: ColorRect     # 8x16 chevron indicator

## Bars and indicators
var _hp_bar_bg: ColorRect
var _hp_bar_fill: ColorRect
var _ammo_dot: ColorRect           # 4x4, visible when ammo < 50%
var _suppression_chevron: ColorRect  # 8x8, visible when suppression > 10%

## Labels
var _name_label: Label
var _hp_text: Label


func _ready() -> void:
	_setup_viewport()
	_setup_ui()
	visible = false


func _process(delta: float) -> void:
	if not is_instance_valid(_target_unit):
		queue_free()
		return

	# Update position to follow unit
	global_position = _target_unit.global_position + Vector3(0, label_offset, 0)

	# Billboard - face camera
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		look_at(camera.global_position, Vector3.UP)
		_cached_camera_dist = global_position.distance_to(camera.global_position)

		# Culling optimization - pause updates beyond CULL_DISTANCE
		var should_cull: bool = _cached_camera_dist > CULL_DISTANCE
		if should_cull != _is_culled:
			_is_culled = should_cull
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED if _is_culled else SubViewport.UPDATE_WHEN_VISIBLE
			_viewport_sprite.visible = not _is_culled

	# Skip updates if culled
	if _is_culled:
		return

	# Throttled updates (10Hz)
	_update_timer -= delta
	if _update_timer <= 0.0:
		_update_timer = UPDATE_INTERVAL
		_update_visuals()


func _setup_viewport() -> void:
	# SubViewport for rendering Control UI to 3D
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(64, 48)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.gui_disable_input = true
	add_child(_viewport)

	# Sprite3D to display the viewport
	_viewport_sprite = Sprite3D.new()
	_viewport_sprite.texture = _viewport.get_texture()
	_viewport_sprite.pixel_size = 0.02  # Scale factor
	_viewport_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_viewport_sprite.no_depth_test = true
	_viewport_sprite.render_priority = 10
	add_child(_viewport_sprite)


func _setup_ui() -> void:
	# Root control
	_ui_root = Control.new()
	_ui_root.custom_minimum_size = Vector2(64, 48)
	_viewport.add_child(_ui_root)

	# Symbol slot (32x32 NATO symbol placeholder)
	_symbol_slot = ColorRect.new()
	_symbol_slot.name = "SymbolSlot"
	_symbol_slot.custom_minimum_size = Vector2(32, 32)
	_symbol_slot.size = Vector2(32, 32)
	_symbol_slot.position = Vector2(16, 0)
	_symbol_slot.color = MilitaryTheme.COL_FACTION_US
	_ui_root.add_child(_symbol_slot)

	# Echelon slot (32x8 above symbol)
	_echelon_slot = ColorRect.new()
	_echelon_slot.name = "EchelonSlot"
	_echelon_slot.custom_minimum_size = Vector2(32, 4)
	_echelon_slot.size = Vector2(32, 4)
	_echelon_slot.position = Vector2(16, -6)
	_echelon_slot.color = Color(0.5, 0.5, 0.5, 0.5)
	_echelon_slot.visible = false  # Hidden by default
	_ui_root.add_child(_echelon_slot)

	# Veterancy slot (8x16 to the left of symbol)
	_veterancy_slot = ColorRect.new()
	_veterancy_slot.name = "VeterancySlot"
	_veterancy_slot.custom_minimum_size = Vector2(8, 16)
	_veterancy_slot.size = Vector2(8, 16)
	_veterancy_slot.position = Vector2(6, 8)
	_veterancy_slot.color = MilitaryTheme.COL_VET[0]
	_ui_root.add_child(_veterancy_slot)

	# HP bar background (40x3)
	_hp_bar_bg = ColorRect.new()
	_hp_bar_bg.custom_minimum_size = Vector2(40, 3)
	_hp_bar_bg.size = Vector2(40, 3)
	_hp_bar_bg.position = Vector2(12, 34)
	_hp_bar_bg.color = Color(0.1, 0.1, 0.1, 0.8)
	_ui_root.add_child(_hp_bar_bg)

	# HP bar fill
	_hp_bar_fill = ColorRect.new()
	_hp_bar_fill.custom_minimum_size = Vector2(40, 3)
	_hp_bar_fill.size = Vector2(40, 3)
	_hp_bar_fill.position = Vector2(12, 34)
	_hp_bar_fill.color = MilitaryTheme.COL_HEALTH_FULL
	_ui_root.add_child(_hp_bar_fill)

	# Ammo dot (4x4, visible when ammo < 50%)
	_ammo_dot = ColorRect.new()
	_ammo_dot.name = "AmmoDot"
	_ammo_dot.custom_minimum_size = Vector2(4, 4)
	_ammo_dot.size = Vector2(4, 4)
	_ammo_dot.position = Vector2(54, 34)
	_ammo_dot.color = MilitaryTheme.COL_AMMO_LOW
	_ammo_dot.visible = false
	_ui_root.add_child(_ammo_dot)

	# Suppression chevron (8x8, visible when suppression > 10%)
	_suppression_chevron = ColorRect.new()
	_suppression_chevron.name = "SuppressionChevron"
	_suppression_chevron.custom_minimum_size = Vector2(8, 8)
	_suppression_chevron.size = Vector2(8, 8)
	_suppression_chevron.position = Vector2(50, 12)
	_suppression_chevron.color = MilitaryTheme.COL_SUPPRESSION
	_suppression_chevron.visible = false
	_ui_root.add_child(_suppression_chevron)

	# Unit name label (10pt, below HP bar)
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.position = Vector2(0, 38)
	_name_label.size = Vector2(64, 10)
	_name_label.add_theme_font_size_override("font_size", 8)
	_name_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_PRIMARY)
	_ui_root.add_child(_name_label)

	# HP text (above HP bar)
	_hp_text = Label.new()
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_text.position = Vector2(12, 28)
	_hp_text.size = Vector2(40, 8)
	_hp_text.add_theme_font_size_override("font_size", 6)
	_hp_text.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	_hp_text.visible = false
	_ui_root.add_child(_hp_text)


## Attach to a unit and begin tracking
func setup(unit: Node3D) -> void:
	_target_unit = unit
	visible = true

	# Connect to unit signals
	if unit.has_signal("health_changed"):
		unit.health_changed.connect(_on_health_changed)
	if unit.has_signal("suppression_changed"):
		unit.suppression_changed.connect(_on_suppression_changed)

	# Initial data extraction
	_extract_unit_data()
	_update_visuals()


func _extract_unit_data() -> void:
	if not is_instance_valid(_target_unit):
		return

	# Get faction
	if _target_unit.has_method("get") and _target_unit.get("data") != null:
		var data: Resource = _target_unit.data
		if data and "faction" in data:
			_cached_faction = data.faction

	# Get name
	var display_name: String = _target_unit.name
	if _target_unit.has_method("get") and _target_unit.get("data") != null:
		var data: Resource = _target_unit.data
		if data and "display_name" in data:
			display_name = data.display_name
	_name_label.text = display_name

	# Get health
	if _target_unit.has_method("get"):
		var current: Variant = _target_unit.get("current_health")
		var maximum: Variant = _target_unit.get("max_health")
		if current != null and maximum != null:
			_cached_health_ratio = float(current) / float(maximum) if maximum > 0 else 0.0

		var supp: Variant = _target_unit.get("suppression_level")
		if supp != null:
			_cached_suppression = float(supp)

		var ammo: Variant = _target_unit.get("current_ammo")
		var max_ammo: Variant = _target_unit.get("max_ammo")
		if ammo != null and max_ammo != null:
			_cached_ammo_ratio = float(ammo) / float(max_ammo) if max_ammo > 0 else 1.0

	# Get veterancy
	if _target_unit.has_method("get") and _target_unit.get("veterancy") != null:
		var vet_state: Resource = _target_unit.veterancy
		if vet_state and "level" in vet_state:
			_cached_vet_level = vet_state.level
	else:
		# Try to get from VeterancyTracker
		var vet_tracker: Node = get_node_or_null("/root/VeterancyTracker")
		if vet_tracker and vet_tracker.has_method("get_state"):
			var state: Resource = vet_tracker.get_state(_target_unit)
			if state and "level" in state:
				_cached_vet_level = state.level


func _on_health_changed(current: float, maximum: float) -> void:
	_cached_health_ratio = current / maximum if maximum > 0 else 0.0


func _on_suppression_changed(level: float) -> void:
	_cached_suppression = level


func _update_visuals() -> void:
	if not is_instance_valid(_target_unit):
		return

	# Apply zoom-based scaling and detail hiding
	_apply_zoom_scaling()

	# Update faction color on symbol
	_symbol_slot.color = MilitaryTheme.faction_color(_cached_faction)

	# Update veterancy color
	_veterancy_slot.color = MilitaryTheme.veterancy_color(_cached_vet_level)

	# Update HP bar
	var hp_width: float = 40.0 * _cached_health_ratio
	_hp_bar_fill.size.x = hp_width
	_hp_bar_fill.color = MilitaryTheme.health_color(_cached_health_ratio)

	# Update ammo dot visibility
	_ammo_dot.visible = _cached_ammo_ratio < 0.5 and _cached_camera_dist < ZOOM_MINIMAL
	if _ammo_dot.visible:
		_ammo_dot.color = MilitaryTheme.ammo_color(_cached_ammo_ratio)

	# Update suppression chevron visibility
	_suppression_chevron.visible = _cached_suppression > 0.1 and _cached_camera_dist < ZOOM_MINIMAL

	# Refresh ammo/suppression from unit each update
	if _target_unit.has_method("get"):
		var ammo: Variant = _target_unit.get("current_ammo")
		var max_ammo: Variant = _target_unit.get("max_ammo")
		if ammo != null and max_ammo != null:
			_cached_ammo_ratio = float(ammo) / float(max_ammo) if max_ammo > 0 else 1.0

		var supp: Variant = _target_unit.get("suppression_level")
		if supp != null:
			_cached_suppression = float(supp)


func _apply_zoom_scaling() -> void:
	var scale_factor: float
	var show_name: bool
	var show_details: bool
	var show_minimal: bool

	if _cached_camera_dist < ZOOM_FULL:
		# Full detail
		scale_factor = 1.0
		show_name = true
		show_details = true
		show_minimal = false
	elif _cached_camera_dist < ZOOM_MEDIUM:
		# Medium detail
		scale_factor = 0.7
		show_name = false
		show_details = true
		show_minimal = false
	elif _cached_camera_dist < ZOOM_MINIMAL:
		# Minimal detail
		scale_factor = 0.5
		show_name = false
		show_details = false
		show_minimal = false
	else:
		# Dot only (beyond 90m)
		scale_factor = 0.25
		show_name = false
		show_details = false
		show_minimal = true

	# Apply scale
	_viewport_sprite.pixel_size = 0.02 * scale_factor

	# Toggle visibility
	_name_label.visible = show_name
	_suppression_chevron.visible = show_details and _cached_suppression > 0.1
	_ammo_dot.visible = show_details and _cached_ammo_ratio < 0.5

	# In minimal mode, hide everything but symbol
	if show_minimal:
		_hp_bar_bg.visible = false
		_hp_bar_fill.visible = false
		_veterancy_slot.visible = false
	else:
		_hp_bar_bg.visible = true
		_hp_bar_fill.visible = true
		_veterancy_slot.visible = true


## Force show the label
func show_label() -> void:
	visible = true


## Get the target unit
func get_target_unit() -> Node3D:
	return _target_unit


## Clean up signal connections when removed from tree
func _exit_tree() -> void:
	if is_instance_valid(_target_unit):
		if _target_unit.has_signal("health_changed"):
			if _target_unit.health_changed.is_connected(_on_health_changed):
				_target_unit.health_changed.disconnect(_on_health_changed)
		if _target_unit.has_signal("suppression_changed"):
			if _target_unit.suppression_changed.is_connected(_on_suppression_changed):
				_target_unit.suppression_changed.disconnect(_on_suppression_changed)
