class_name ResourceStrip extends PanelContainer
## Top-center resource readout: supply stock plus rate per minute.
## Stock updates are event-driven (SupplyManager.global_supply_changed).
## Rate/min comes from 1-second stock samples over a rolling 60s window,
## so it reflects actual net flow regardless of which systems move supply.

const MilitaryTheme = preload("res://battle_system/ui/military_theme.gd")

const SAMPLE_INTERVAL := 1.0
const RATE_WINDOW_SAMPLES := 61  # 60 seconds of history + current

var _supply_manager: Node = null
var _stock_label: Label
var _rate_label: Label
var _samples: PackedFloat32Array = []
var _sample_timer: Timer


func _ready() -> void:
	add_theme_stylebox_override("panel", MilitaryTheme.create_panel_stylebox())
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)
	add_child(hbox)

	var title := Label.new()
	title.text = "SUPPLY"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	hbox.add_child(title)

	_stock_label = Label.new()
	_stock_label.add_theme_font_size_override("font_size", 14)
	_stock_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_PRIMARY)
	hbox.add_child(_stock_label)

	_rate_label = Label.new()
	_rate_label.add_theme_font_size_override("font_size", 12)
	_rate_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	hbox.add_child(_rate_label)

	_supply_manager = get_node_or_null("/root/SupplyManager")
	if _supply_manager and _supply_manager.has_signal("global_supply_changed"):
		_supply_manager.global_supply_changed.connect(_on_global_supply_changed)

	_sample_timer = Timer.new()
	_sample_timer.wait_time = SAMPLE_INTERVAL
	_sample_timer.autostart = true
	_sample_timer.timeout.connect(_on_sample_tick)
	add_child(_sample_timer)

	_refresh_stock()
	_on_sample_tick()


func _exit_tree() -> void:
	if _supply_manager and _supply_manager.has_signal("global_supply_changed"):
		if _supply_manager.global_supply_changed.is_connected(_on_global_supply_changed):
			_supply_manager.global_supply_changed.disconnect(_on_global_supply_changed)


# =============================================================================
# INTERNALS
# =============================================================================

func _current_stock() -> float:
	if _supply_manager and _supply_manager.has_method("get_global_supply"):
		return _supply_manager.get_global_supply()
	return 0.0


func _refresh_stock() -> void:
	if not _supply_manager:
		_stock_label.text = "--"
		return
	var max_supply: float = _supply_manager.max_global_supply if "max_global_supply" in _supply_manager else 0.0
	if max_supply > 0.0:
		_stock_label.text = "%d / %d" % [int(_current_stock()), int(max_supply)]
	else:
		_stock_label.text = "%d" % int(_current_stock())


func _on_global_supply_changed(_new_amount: float) -> void:
	_refresh_stock()


func _on_sample_tick() -> void:
	_samples.append(_current_stock())
	if _samples.size() > RATE_WINDOW_SAMPLES:
		_samples.remove_at(0)
	_refresh_stock()
	_update_rate_label()


func _update_rate_label() -> void:
	if _samples.size() < 2:
		_rate_label.text = ""
		return
	var elapsed: float = float(_samples.size() - 1) * SAMPLE_INTERVAL
	var rate_per_min: float = (_samples[_samples.size() - 1] - _samples[0]) / elapsed * 60.0
	if absf(rate_per_min) < 0.5:
		_rate_label.text = "±0/min"
		_rate_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	elif rate_per_min > 0.0:
		_rate_label.text = "+%d/min" % int(roundf(rate_per_min))
		_rate_label.add_theme_color_override("font_color", MilitaryTheme.COL_STATE_WORKING)
	else:
		_rate_label.text = "%d/min" % int(roundf(rate_per_min))
		_rate_label.add_theme_color_override("font_color", MilitaryTheme.COL_HEALTH_LOW)
