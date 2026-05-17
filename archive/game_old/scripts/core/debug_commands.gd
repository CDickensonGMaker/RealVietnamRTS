extends Node
## DebugCommands - Development tools and cheats
## Press keys to test various game features

@export var enabled: bool = true

var enemy_spawner: Node


func _ready() -> void:
	if not enabled:
		set_process_unhandled_input(false)
		return

	await get_tree().process_frame
	enemy_spawner = get_node_or_null("/root/Main/EnemySpawner")


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
				_spawn_test_enemies()
			KEY_F2:
				_add_supplies()
			KEY_F3:
				_spawn_rifle_squad()
			KEY_F4:
				_trigger_wave()
			KEY_F5:
				_toggle_god_mode()
			KEY_F9:
				_print_debug_info()


func _spawn_test_enemies() -> void:
	print("[DEBUG] Spawning test enemies")

	if enemy_spawner and enemy_spawner.has_method("spawn_test_enemies"):
		var firebase_pos := Vector3(100, 0, 100)
		enemy_spawner.spawn_test_enemies(5, firebase_pos, 50.0)
	else:
		print("[DEBUG] Enemy spawner not found")


func _add_supplies() -> void:
	print("[DEBUG] Adding 100 supplies")
	GameManager.add_supplies(100)


func _spawn_rifle_squad() -> void:
	print("[DEBUG] Spawning rifle squad")

	var command_post: Node3D = GameManager.command_post
	if command_post and command_post.has_method("queue_spawn"):
		# Give free supplies first
		GameManager.add_supplies(20)
		command_post.queue_spawn("rifle_squad")
	else:
		print("[DEBUG] Command post not found or invalid")


func _trigger_wave() -> void:
	print("[DEBUG] Triggering enemy wave")

	var ai_director: Node = get_node_or_null("/root/Main/Directors/AIDirector")
	if ai_director:
		# Force next wave timer to 0
		ai_director.wave_timer = ai_director.next_wave_time
	else:
		print("[DEBUG] AI Director not found")


func _toggle_god_mode() -> void:
	print("[DEBUG] God mode toggle (not implemented)")
	# Would make player units invulnerable


func _print_debug_info() -> void:
	print("=== DEBUG INFO ===")
	print("Game State: ", GameManager.current_state)
	print("Supplies: ", GameManager.supplies, " / ", GameManager.max_supply_storage)
	print("Player Squads: ", GameManager.player_squads.size())
	print("Structures: ", GameManager.structures.size())
	print("Enemy Units: ", get_tree().get_nodes_in_group("enemy_units").size())
	print("Game Time: ", GameManager.get_formatted_time())

	var ai_director: Node = get_node_or_null("/root/Main/Directors/AIDirector")
	if ai_director:
		print("Current Wave: ", ai_director.get_current_wave())
		print("Next Wave In: ", ai_director.get_time_until_next_wave())
		print("Difficulty: ", ai_director.get_difficulty_level())

	print("==================")
