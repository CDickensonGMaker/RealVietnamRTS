extends Control
## SelectionBox - Visual feedback for box selection
## Draws a rectangle while dragging to select units

var start_pos: Vector2 = Vector2.ZERO
var end_pos: Vector2 = Vector2.ZERO
var is_selecting: bool = false

var box_color := Color(0.2, 1.0, 0.2, 0.3)
var border_color := Color(0.2, 1.0, 0.2, 0.8)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if Input.is_action_pressed("select"):
		if not is_selecting:
			start_pos = get_viewport().get_mouse_position()
			is_selecting = true

		end_pos = get_viewport().get_mouse_position()
		queue_redraw()
	elif is_selecting:
		is_selecting = false
		queue_redraw()


func _draw() -> void:
	if not is_selecting:
		return

	var rect := Rect2(start_pos, end_pos - start_pos).abs()

	# Only draw if significant size
	if rect.size.length() < 5:
		return

	# Draw filled rectangle
	draw_rect(rect, box_color)

	# Draw border
	draw_rect(rect, border_color, false, 2.0)


func get_selection_rect() -> Rect2:
	return Rect2(start_pos, end_pos - start_pos).abs()
