extends Label
## WaveIndicator - Shows current wave and time until next assault

var ai_director: Node
var flash_timer: float = 0.0
var is_flashing: bool = false


func _ready() -> void:
	await get_tree().process_frame
	ai_director = get_node_or_null("/root/Main/Directors/AIDirector")

	if ai_director:
		ai_director.assault_wave_starting.connect(_on_wave_starting)
		ai_director.assault_wave_ended.connect(_on_wave_ended)


func _process(delta: float) -> void:
	_update_display()

	if is_flashing:
		flash_timer += delta
		modulate.a = 0.5 + sin(flash_timer * 10) * 0.5

		if flash_timer > 3.0:
			is_flashing = false
			modulate.a = 1.0


func _update_display() -> void:
	if not ai_director:
		text = "Waiting..."
		return

	var wave: int = ai_director.get_current_wave()
	var next_time: float = ai_director.get_time_until_next_wave()

	if next_time <= 0:
		text = "WAVE %d - INCOMING!" % wave
	else:
		var minutes := int(next_time) / 60
		var seconds := int(next_time) % 60
		text = "Wave %d - Next: %d:%02d" % [wave, minutes, seconds]


func _on_wave_starting(wave_number: int, _direction: Vector3) -> void:
	is_flashing = true
	flash_timer = 0.0
	add_theme_color_override("font_color", Color.RED)


func _on_wave_ended(_wave_number: int, _success: bool) -> void:
	is_flashing = false
	modulate.a = 1.0
	remove_theme_color_override("font_color")
