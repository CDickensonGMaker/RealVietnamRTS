extends Label
## DebugHUD - Shows debug information during development
## FPS, unit counts, supply info, wave status

var update_interval: float = 0.25
var update_timer: float = 0.0


func _process(delta: float) -> void:
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		_update_display()


func _update_display() -> void:
	var lines: Array[String] = []

	# FPS
	lines.append("FPS: %d" % Engine.get_frames_per_second())

	# Units
	var player_count: int = GameManager.player_squads.size()
	var enemy_count: int = get_tree().get_nodes_in_group("enemy_units").size()
	lines.append("Units: %d / %d" % [player_count, enemy_count])

	# Structures
	lines.append("Structures: %d" % GameManager.structures.size())

	# Supplies
	lines.append("Supplies: %d" % GameManager.supplies)

	# Game time
	lines.append("Time: %s" % GameManager.get_formatted_time())

	# AI Director info
	var ai_director: Node = get_node_or_null("/root/Main/Directors/AIDirector")
	if ai_director:
		var wave: int = ai_director.get_current_wave()
		var next_wave: float = ai_director.get_time_until_next_wave()
		var difficulty: float = ai_director.get_difficulty_level()
		lines.append("Wave: %d (D:%.1f)" % [wave, difficulty])
		lines.append("Next: %.0fs" % next_wave)

	text = "\n".join(lines)
