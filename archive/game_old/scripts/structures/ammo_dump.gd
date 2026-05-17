extends BaseStructure
class_name AmmoDump
## Ammo Dump - Speeds up ammo resupply for nearby squads

@export var resupply_radius: float = 20.0
@export var resupply_rate: float = 10.0  # Ammo per second
@export var ammo_capacity: float = 200.0  # Total ammo stored

var current_ammo: float
var resupply_timer: float = 0.0
const RESUPPLY_TICK: float = 1.0


func _ready() -> void:
	super._ready()
	structure_name = "Ammo Dump"
	max_health = 40.0
	armor = 2.0
	current_health = max_health

	current_ammo = ammo_capacity

	# Ammo dumps are explosive!
	add_to_group("explosive")


func _process(delta: float) -> void:
	super._process(delta)

	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	if current_ammo <= 0:
		return

	resupply_timer += delta
	if resupply_timer >= RESUPPLY_TICK:
		resupply_timer = 0.0
		_resupply_nearby_units()


func _resupply_nearby_units() -> void:
	for squad in GameManager.player_squads:
		if not is_instance_valid(squad):
			continue

		var dist := global_position.distance_to(squad.global_position)
		if dist > resupply_radius:
			continue

		# Check if needs ammo
		if squad.has_method("get_ammo_percent"):
			var ammo_pct: float = squad.get_ammo_percent()
			if ammo_pct < 1.0 and squad.has_method("add_ammo"):
				var amount := minf(resupply_rate, current_ammo)
				squad.add_ammo(amount)
				current_ammo -= amount

				if current_ammo <= 0:
					break


func take_damage(amount: float, attacker: Node = null) -> void:
	super.take_damage(amount, attacker)

	# Ammo dump explodes violently when destroyed
	if current_health <= 0:
		_explode()


func _explode() -> void:
	# Deal damage to nearby units (both friend and foe)
	var explosion_radius := 15.0
	var explosion_damage := 80.0

	for node: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node):
			continue

		var unit := node as Node3D
		if not unit:
			continue

		var dist := global_position.distance_to(unit.global_position)
		if dist > explosion_radius:
			continue

		# Damage falloff
		var falloff := 1.0 - (dist / explosion_radius)
		var dmg := explosion_damage * falloff

		if unit.has_method("take_damage"):
			unit.call("take_damage", dmg, self)

	# Visual effect
	_spawn_big_explosion()


func _spawn_big_explosion() -> void:
	var explosion := CSGSphere3D.new()
	explosion.radius = 5.0
	explosion.global_position = global_position + Vector3(0, 2, 0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.6, 0)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.4, 0)
	mat.emission_energy_multiplier = 5.0
	explosion.material = mat

	get_tree().current_scene.add_child(explosion)

	var tween := create_tween()
	tween.tween_property(explosion, "radius", 8.0, 0.3)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tween.tween_callback(explosion.queue_free)


func get_ammo_percent() -> float:
	return current_ammo / ammo_capacity


func refill(amount: float) -> void:
	current_ammo = minf(current_ammo + amount, ammo_capacity)
