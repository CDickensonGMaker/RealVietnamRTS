extends Node
## class_name VCController  # ARCHIVED
## VCController - Viet Cong guerrilla AI
## Manages tunnel networks, ambushes, sappers, village operations, and guerrilla warfare tactics
## Implements hit-and-run, booby traps, mortar harassment, trail watching, and escape-and-fade

signal tunnel_created(entrance: Node3D)
signal ambush_sprung(position: Vector3, target: Node3D)
signal sapper_attack_started(firebase: Node3D)
signal vc_unit_spawned(unit: Node3D)
signal village_converted(village: Node3D)
signal booby_trap_placed(position: Vector3, trap_type: int)
signal booby_trap_triggered(position: Vector3, victim: Node3D)
signal mortar_harassment_started(target: Vector3)
signal trail_watcher_detected(unit: Node3D, direction: Vector3)
signal unit_faded_away(unit: Node3D, tunnel: Node3D)
signal propaganda_dropped(village: Node3D)

# =============================================================================
# ENUMS
# =============================================================================
enum TrapType {
	PUNJI_PIT,        # Spike trap, infantry damage
	GRENADE_TRIP,     # Tripwire grenade, area damage
	MINE,             # Anti-personnel mine, high damage
	SNARE,            # Slowing trap, no damage
	TIGER_TRAP,       # Large spike pit, vehicle damage
}

enum GuerrillaState {
	HIDING,           # Concealed, observing
	HARASSING,        # Hit-and-run attacks
	AMBUSHING,        # Waiting for target
	ATTACKING,        # Full engagement
	FADING,           # Escaping to tunnels
	RESUPPLYING,      # Getting supplies from village
}

# VC resources
var manpower: int = 100
var supplies: int = 50
var intelligence: int = 0  # Intel on US positions
var propaganda_leaflets: int = 20  # For village conversion

# Networks
var tunnel_network: Array = []  # Array of TunnelEntrance
var weapon_caches: Array[Node3D] = []
var village_sympathizers: Array[Node3D] = []

# Booby trap system
var placed_traps: Array = []  # Array of BoobyTrap
var trap_density_map: Dictionary = {}  # Vector2i -> trap count

# Trail watcher system
var trail_watchers: Array[Dictionary] = []  # Units watching trails
var detected_patrols: Array[Dictionary] = []  # Recently detected US patrols

# Hit-and-run tracking
var hit_run_cooldowns: Dictionary = {}  # Unit -> cooldown timer
var recent_engagement_positions: Array[Vector3] = []

# Mortar harassment
var mortar_teams: Array[Node3D] = []
var harassment_targets: Array[Dictionary] = []
var mortar_ammo: int = 50

# Active operations
var active_ambushes: Array[Dictionary] = []
var active_attacks: Array[Dictionary] = []
var pending_spawns: Array[Dictionary] = []
var fading_units: Array[Dictionary] = []  # Units escaping

# Tactical preferences
var aggression_level: float = 0.5  # 0.0 = defensive, 1.0 = aggressive
var night_preference: float = 0.8  # Prefer night operations
var trap_preference: float = 0.6  # How often to use traps vs direct combat
var fade_threshold: float = 0.4  # Casualties before fading away

# Timers
var patrol_check_timer: float = 0.0
var tunnel_spawn_timer: float = 0.0
var village_tax_timer: float = 0.0
var trap_check_timer: float = 0.0
var mortar_timer: float = 0.0
var trail_watch_timer: float = 0.0
var propaganda_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemy_controllers")
	_connect_signals()

func _connect_signals() -> void:
	BattleSignals.unit_died.connect(_on_unit_died)
	BattleSignals.unit_damaged.connect(_on_unit_damaged)

func _process(delta: float) -> void:
	_update_timers(delta)
	_check_ambush_opportunities()
	_process_pending_spawns(delta)
	_process_fading_units(delta)
	_process_hit_run_cooldowns(delta)
	_check_booby_traps()
	_process_mortar_harassment(delta)

func _update_timers(delta: float) -> void:
	patrol_check_timer += delta
	tunnel_spawn_timer += delta
	village_tax_timer += delta
	trap_check_timer += delta
	mortar_timer += delta
	trail_watch_timer += delta
	propaganda_timer += delta

	# Check for patrolling US units to ambush
	if patrol_check_timer > 5.0:
		patrol_check_timer = 0.0
		_scan_for_patrol_targets()

	# Spawn reinforcements from tunnels
	if tunnel_spawn_timer > 60.0:
		tunnel_spawn_timer = 0.0
		_spawn_tunnel_reinforcements()

	# Collect supplies from villages
	if village_tax_timer > 180.0:
		village_tax_timer = 0.0
		_collect_village_taxes()

	# Place new traps periodically
	if trap_check_timer > 30.0:
		trap_check_timer = 0.0
		_consider_placing_traps()

	# Trail watchers report
	if trail_watch_timer > 10.0:
		trail_watch_timer = 0.0
		_update_trail_watchers()

	# Mortar harassment timing
	if mortar_timer > 45.0:
		mortar_timer = 0.0
		_consider_mortar_harassment()

	# Propaganda operations
	if propaganda_timer > 300.0:  # Every 5 minutes
		propaganda_timer = 0.0
		_conduct_propaganda_operation()

# =============================================================================
# TUNNEL NETWORK
# =============================================================================

func create_tunnel_entrance(position: Vector3) -> TunnelEntrance:
	var entrance: TunnelEntrance = TunnelEntrance.new()
	entrance.global_position = position
	get_tree().current_scene.add_child(entrance)
	tunnel_network.append(entrance)

	tunnel_created.emit(entrance)
	BattleSignals.vc_tunnel_spawned.emit(entrance)

	return entrance

func get_tunnel_near(position: Vector3, max_distance: float = 100.0) -> TunnelEntrance:
	var nearest: TunnelEntrance = null
	var nearest_dist := INF

	for tunnel in tunnel_network:
		if is_instance_valid(tunnel):
			var dist := position.distance_to(tunnel.global_position)
			if dist < nearest_dist and dist < max_distance:
				nearest_dist = dist
				nearest = tunnel

	return nearest

func spawn_from_tunnel(tunnel: TunnelEntrance, unit_type: int, count: int) -> Array[Node3D]:
	var spawned: Array[Node3D] = []

	for i in range(count):
		var unit := _create_vc_unit(unit_type)
		if unit:
			unit.global_position = tunnel.global_position + Vector3(
				randf_range(-3, 3), 0, randf_range(-3, 3)
			)
			get_tree().current_scene.add_child(unit)
			spawned.append(unit)
			vc_unit_spawned.emit(unit)

	return spawned

func _spawn_tunnel_reinforcements() -> void:
	if tunnel_network.is_empty() or manpower <= 0:
		return

	# Pick random tunnel
	var tunnel: TunnelEntrance = tunnel_network[randi() % tunnel_network.size()]
	if not is_instance_valid(tunnel):
		return

	# Spawn based on available manpower
	var spawn_count := mini(randi_range(3, 8), manpower)
	spawn_from_tunnel(tunnel, GameEnums.UnitType.VC_INFANTRY, spawn_count)
	manpower -= spawn_count

# =============================================================================
# AMBUSH SYSTEM
# =============================================================================

func _scan_for_patrol_targets() -> void:
	# Find US units that are isolated and can be ambushed
	var us_units := SpatialHashGrid.get_all_units_of_faction(GameEnums.Faction.US_ARMY)

	for unit in us_units:
		if not is_instance_valid(unit):
			continue

		# Check if unit is isolated (no friendlies nearby)
		var friendlies := SpatialHashGrid.get_friendlies_in_radius(
			unit.global_position, 50.0, GameEnums.Faction.US_ARMY
		)

		if friendlies.size() <= 1:  # Just this unit
			# Check if we have forces nearby to ambush
			var tunnel := get_tunnel_near(unit.global_position, 150.0)
			if tunnel and _should_ambush():
				_setup_ambush(unit, tunnel)
				break  # One ambush at a time

func _should_ambush() -> bool:
	# Prefer night ambushes
	if WeatherSystem.is_night():
		return randf() < aggression_level * night_preference

	# Daytime ambushes are riskier
	return randf() < aggression_level * 0.3

func _setup_ambush(target: Node3D, tunnel: TunnelEntrance) -> void:
	var ambush := {
		"target": target,
		"tunnel": tunnel,
		"phase": "preparing",
		"timer": 0.0,
		"ambush_force": [],
	}

	# Spawn ambush force from tunnel
	var force_size := randi_range(6, 15)
	ambush.ambush_force = spawn_from_tunnel(tunnel, GameEnums.UnitType.VC_INFANTRY, force_size)

	active_ambushes.append(ambush)

func spring_ambush(ambush: Dictionary) -> void:
	ambush.phase = "attacking"

	var target: Node3D = ambush.target
	if not is_instance_valid(target):
		return

	# Order ambush force to attack
	for unit in ambush.ambush_force:
		if is_instance_valid(unit) and unit.has_method("attack"):
			unit.attack(target)

	ambush_sprung.emit(target.global_position, target)
	BattleSignals.vc_ambush_triggered.emit(target.global_position, target)

func _check_ambush_opportunities() -> void:
	for ambush in active_ambushes:
		if ambush.phase == "preparing":
			var target: Node3D = ambush.target
			if not is_instance_valid(target):
				active_ambushes.erase(ambush)
				continue

			# Spring ambush when target is close to tunnel
			var tunnel: TunnelEntrance = ambush.tunnel
			if is_instance_valid(tunnel):
				var dist := target.global_position.distance_to(tunnel.global_position)
				if dist < 30.0:
					spring_ambush(ambush)

# =============================================================================
# SAPPER ATTACKS
# =============================================================================

func launch_sapper_attack(target_firebase: Node3D) -> void:
	if manpower < 10:
		return

	# Spawn sapper team
	var tunnel := get_tunnel_near(target_firebase.global_position)
	if not tunnel:
		return

	var sappers := spawn_from_tunnel(tunnel, GameEnums.UnitType.VC_SAPPERS, 6)

	var attack := {
		"target": target_firebase,
		"sappers": sappers,
		"phase": "infiltrating",
		"breach_point": Vector3.ZERO,
	}

	active_attacks.append(attack)
	sapper_attack_started.emit(target_firebase)
	BattleSignals.vc_sappers_breaching.emit(target_firebase)

	manpower -= 6

# =============================================================================
# VILLAGE OPERATIONS
# =============================================================================

func add_sympathizer_village(village: Node3D) -> void:
	if village not in village_sympathizers:
		village_sympathizers.append(village)

func _collect_village_taxes() -> void:
	for village in village_sympathizers:
		if is_instance_valid(village):
			# Collect supplies and recruits
			supplies += 10
			manpower += randi_range(1, 3)

			if village.has_method("vc_taxation"):
				village.vc_taxation()

			BattleSignals.village_vc_tax.emit(village)

func convert_village(village: Node3D) -> void:
	if village not in village_sympathizers:
		village_sympathizers.append(village)
		village_converted.emit(village)

# =============================================================================
# BOOBY TRAP SYSTEM
# =============================================================================

func place_trap(position: Vector3, trap_type: TrapType) -> BoobyTrap:
	if supplies < _get_trap_cost(trap_type):
		return null

	var trap: BoobyTrap = BoobyTrap.new()
	trap.position = position
	trap.trap_type = trap_type
	trap.damage = _get_trap_damage(trap_type)
	trap.detection_radius = _get_trap_detection_radius(trap_type)
	trap.is_armed = true

	placed_traps.append(trap)
	supplies -= _get_trap_cost(trap_type)

	# Track density to avoid clustering
	var grid_pos := Vector2i(int(position.x / 20.0), int(position.z / 20.0))
	trap_density_map[grid_pos] = trap_density_map.get(grid_pos, 0) + 1

	booby_trap_placed.emit(position, trap_type)
	return trap

func _get_trap_cost(trap_type: TrapType) -> int:
	match trap_type:
		TrapType.PUNJI_PIT: return 2
		TrapType.GRENADE_TRIP: return 5
		TrapType.MINE: return 8
		TrapType.SNARE: return 1
		TrapType.TIGER_TRAP: return 10
		_: return 5

func _get_trap_damage(trap_type: TrapType) -> float:
	match trap_type:
		TrapType.PUNJI_PIT: return 30.0
		TrapType.GRENADE_TRIP: return 60.0
		TrapType.MINE: return 100.0
		TrapType.SNARE: return 0.0  # Slowing only
		TrapType.TIGER_TRAP: return 150.0
		_: return 50.0

func _get_trap_detection_radius(trap_type: TrapType) -> float:
	match trap_type:
		TrapType.PUNJI_PIT: return 2.0
		TrapType.GRENADE_TRIP: return 3.0
		TrapType.MINE: return 1.5
		TrapType.SNARE: return 2.5
		TrapType.TIGER_TRAP: return 3.5
		_: return 2.0

func _check_booby_traps() -> void:
	var triggered: Array = []

	for trap in placed_traps:
		if not trap.is_armed:
			continue

		# Check for US units stepping on trap
		var nearby := SpatialHashGrid.get_enemies_in_radius(
			trap.position, trap.detection_radius, GameEnums.Faction.VC
		)

		for unit in nearby:
			if not is_instance_valid(unit):
				continue

			# Check if unit is moving (stationary units may spot trap)
			var velocity := Vector3.ZERO
			if unit.has_method("get_velocity"):
				velocity = unit.get_velocity()

			# Moving units are more likely to trigger
			var trigger_chance := 0.8 if velocity.length() > 0.5 else 0.3

			# Engineers have chance to spot traps
			if unit.has_method("is_engineer") and unit.is_engineer():
				trigger_chance *= 0.4

			if randf() < trigger_chance:
				_trigger_trap(trap, unit)
				triggered.append(trap)
				break

	# Remove triggered traps
	for trap in triggered:
		placed_traps.erase(trap)

func _trigger_trap(trap: BoobyTrap, victim: Node3D) -> void:
	trap.is_armed = false

	booby_trap_triggered.emit(trap.position, victim)

	# Apply damage
	if victim.has_method("take_damage"):
		victim.take_damage(trap.damage, null)

	# Area effect for explosive traps
	if trap.trap_type in [TrapType.GRENADE_TRIP, TrapType.MINE]:
		var area_victims := SpatialHashGrid.get_all_units_in_radius(trap.position, 5.0)
		for av in area_victims:
			if is_instance_valid(av) and av != victim and av.has_method("take_damage"):
				var dist := av.global_position.distance_to(trap.position)
				var falloff := 1.0 - (dist / 5.0)
				av.take_damage(trap.damage * falloff * 0.5, null)

		BattleSignals.explosion.emit(trap.position, 5.0, trap.damage)

	# Snare effect - slow the unit
	if trap.trap_type == TrapType.SNARE and victim.has_method("apply_slow"):
		victim.apply_slow(0.5, 10.0)  # 50% slow for 10 seconds

	# Update intel - we now know there's US activity here
	intelligence += 5

func _consider_placing_traps() -> void:
	if supplies < 5 or randf() > trap_preference:
		return

	# Find good trap locations - along trails, near known US patrol routes
	var trap_candidates: Array[Vector3] = []

	# Near roads and trails
	for pos in recent_engagement_positions:
		var offset := Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
		trap_candidates.append(pos + offset)

	# Near firebases (approach routes)
	var firebases := get_tree().get_nodes_in_group("firebases")
	for fb in firebases:
		if fb is Node3D:
			var fb_node: Node3D = fb
			for i in range(3):
				var angle := randf() * TAU
				var distance := randf_range(50, 150)
				var pos := fb_node.global_position + Vector3(
					cos(angle) * distance, 0, sin(angle) * distance
				)
				trap_candidates.append(pos)

	# Pick best location (low density)
	var best_pos: Vector3 = Vector3.ZERO
	var lowest_density := 999

	for pos in trap_candidates:
		var grid_pos := Vector2i(int(pos.x / 20.0), int(pos.z / 20.0))
		var density: int = trap_density_map.get(grid_pos, 0)
		if density < lowest_density:
			lowest_density = density
			best_pos = pos

	if best_pos != Vector3.ZERO and lowest_density < 3:
		# Choose trap type based on location and supplies
		var trap_type := TrapType.PUNJI_PIT
		if supplies > 20:
			trap_type = [TrapType.PUNJI_PIT, TrapType.GRENADE_TRIP, TrapType.MINE].pick_random()
		place_trap(best_pos, trap_type)

# =============================================================================
# HIT-AND-RUN TACTICS
# =============================================================================

func initiate_hit_and_run(attackers: Array[Node3D], target: Node3D) -> void:
	## Launch a quick attack then fade away

	if attackers.is_empty() or not is_instance_valid(target):
		return

	# Record engagement position for future trap placement
	recent_engagement_positions.append(target.global_position)
	if recent_engagement_positions.size() > 20:
		recent_engagement_positions.pop_front()

	# Order quick attack
	for unit in attackers:
		if not is_instance_valid(unit):
			continue

		if unit.has_method("set_engagement_mode"):
			unit.set_engagement_mode("hit_and_run")

		if unit.has_method("attack"):
			unit.attack(target)

		# Set cooldown - this unit will fade after brief engagement
		hit_run_cooldowns[unit] = 8.0  # 8 seconds of combat then fade

func _process_hit_run_cooldowns(delta: float) -> void:
	var to_fade: Array[Node3D] = []

	for unit: Node3D in hit_run_cooldowns.keys():
		if not is_instance_valid(unit):
			hit_run_cooldowns.erase(unit)
			continue

		hit_run_cooldowns[unit] -= delta

		if hit_run_cooldowns[unit] <= 0:
			to_fade.append(unit)
			hit_run_cooldowns.erase(unit)

	# Initiate fade for units that have finished their engagement window
	for unit in to_fade:
		_initiate_fade(unit)

func _initiate_fade(unit: Node3D) -> void:
	## Unit attempts to escape to nearest tunnel

	if not is_instance_valid(unit):
		return

	var nearest_tunnel := get_tunnel_near(unit.global_position, 200.0)
	if not nearest_tunnel:
		# No tunnel nearby - try to hide in jungle instead
		_hide_in_terrain(unit)
		return

	var fade_data := {
		"unit": unit,
		"target_tunnel": nearest_tunnel,
		"phase": "retreating",
		"timer": 0.0,
	}
	fading_units.append(fade_data)

	# Order unit to move to tunnel
	if unit.has_method("move_to"):
		unit.move_to(nearest_tunnel.global_position)

	if unit.has_method("set_state"):
		unit.set_state(GuerrillaState.FADING)

func _hide_in_terrain(unit: Node3D) -> void:
	## Unit hides in jungle/terrain when no tunnel available

	if unit.has_method("enter_stealth"):
		unit.enter_stealth()

	# Find dense terrain to hide in
	var hide_direction := -unit.global_position.normalized()  # Away from center
	hide_direction.y = 0
	var hide_pos := unit.global_position + hide_direction * 50.0

	if unit.has_method("move_to"):
		unit.move_to(hide_pos)

func _process_fading_units(delta: float) -> void:
	var completed: Array[int] = []

	for i in range(fading_units.size()):
		var fade: Dictionary = fading_units[i]
		var unit: Node3D = fade.unit
		var tunnel: TunnelEntrance = fade.target_tunnel

		if not is_instance_valid(unit):
			completed.append(i)
			continue

		if not is_instance_valid(tunnel):
			# Tunnel destroyed, just hide
			_hide_in_terrain(unit)
			completed.append(i)
			continue

		# Check if unit reached tunnel
		var dist := unit.global_position.distance_to(tunnel.global_position)
		if dist < 5.0:
			# Unit disappears into tunnel
			unit_faded_away.emit(unit, tunnel)

			# Recover manpower
			if unit.has_method("get_squad_size"):
				manpower += unit.get_squad_size()
			else:
				manpower += 1

			unit.queue_free()
			completed.append(i)

	# Remove completed fades (reverse order)
	for i in range(completed.size() - 1, -1, -1):
		fading_units.remove_at(completed[i])

func _on_unit_damaged(unit: Node3D, damage: float, source: Node3D) -> void:
	## Check if VC units should fade after taking casualties

	if not is_instance_valid(unit):
		return

	if not unit.is_in_group("vc_units"):
		return

	# Check health ratio
	var health_ratio := 1.0
	if unit.has_method("get_health_ratio"):
		health_ratio = unit.get_health_ratio()

	# Fade if casualties exceed threshold
	if health_ratio < fade_threshold and randf() < 0.7:
		_initiate_fade(unit)

func _on_unit_died(unit: Node3D, killer: Node3D) -> void:
	## Track VC losses, consider fading remaining units

	if not unit.is_in_group("vc_units"):
		return

	# Record engagement position
	recent_engagement_positions.append(unit.global_position)

	# Check if nearby VC should fade
	var nearby_vc := SpatialHashGrid.get_friendlies_in_radius(
		unit.global_position, 30.0, GameEnums.Faction.VC
	)

	# If we lost too many in this area, fade remaining
	var fade_chance := 0.3 if nearby_vc.size() > 5 else 0.6
	if randf() < fade_chance:
		for vc in nearby_vc:
			if is_instance_valid(vc) and vc not in fading_units.map(func(f): return f.unit):
				_initiate_fade(vc)

# =============================================================================
# MORTAR HARASSMENT
# =============================================================================

func register_mortar_team(mortar: Node3D) -> void:
	if mortar not in mortar_teams:
		mortar_teams.append(mortar)

func _consider_mortar_harassment() -> void:
	if mortar_teams.is_empty() or mortar_ammo <= 0:
		return

	# Prefer night harassment
	if not WeatherSystem.is_night() and randf() > 0.3:
		return

	# Find harassment targets
	var targets: Array[Dictionary] = []

	# Firebases are primary targets
	for fb in get_tree().get_nodes_in_group("firebases"):
		if fb is Node3D:
			var fb_node: Node3D = fb
			targets.append({
				"position": fb_node.global_position,
				"priority": 3,
				"type": "firebase"
			})

	# US unit concentrations
	var us_units := SpatialHashGrid.get_all_units_of_faction(GameEnums.Faction.US_ARMY)
	var concentration_map: Dictionary = {}

	for unit in us_units:
		if not is_instance_valid(unit):
			continue
		var grid := Vector2i(int(unit.global_position.x / 30), int(unit.global_position.z / 30))
		concentration_map[grid] = concentration_map.get(grid, 0) + 1

	for grid: Vector2i in concentration_map.keys():
		if concentration_map[grid] >= 3:
			targets.append({
				"position": Vector3(grid.x * 30.0 + 15.0, 0, grid.y * 30.0 + 15.0),
				"priority": 2,
				"type": "concentration"
			})

	if targets.is_empty():
		return

	# Pick target and harass
	targets.sort_custom(func(a, b): return a.priority > b.priority)
	var target: Dictionary = targets[0]

	_execute_mortar_harassment(target.position)

func _execute_mortar_harassment(target: Vector3) -> void:
	if mortar_teams.is_empty() or mortar_ammo <= 0:
		return

	# Find closest mortar team
	var best_mortar: Node3D = null
	var best_dist := INF

	for mortar in mortar_teams:
		if not is_instance_valid(mortar):
			continue
		var dist := mortar.global_position.distance_to(target)
		if dist < best_dist and dist < 500.0:  # Mortar range
			best_dist = dist
			best_mortar = mortar

	if not best_mortar:
		return

	mortar_harassment_started.emit(target)

	# Fire 3-6 rounds then displace
	var rounds := randi_range(3, 6)
	rounds = mini(rounds, mortar_ammo)
	mortar_ammo -= rounds

	for i in range(rounds):
		var scatter := Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))
		var impact := target + scatter

		# Schedule delayed impacts
		var delay := 2.0 + i * 1.5
		_schedule_mortar_impact(impact, delay)

	# Displace mortar team after firing (shoot and scoot)
	var displace_pos := best_mortar.global_position + Vector3(
		randf_range(-50, 50), 0, randf_range(-50, 50)
	)
	if best_mortar.has_method("move_to"):
		# Delay before displacing
		await get_tree().create_timer(rounds * 1.5 + 1.0).timeout
		if is_instance_valid(best_mortar):
			best_mortar.move_to(displace_pos)

func _schedule_mortar_impact(position: Vector3, delay: float) -> void:
	await get_tree().create_timer(delay).timeout

	# Apply damage to units in area
	var victims := SpatialHashGrid.get_all_units_in_radius(position, 8.0)
	for victim in victims:
		if is_instance_valid(victim) and victim.has_method("take_damage"):
			var dist := victim.global_position.distance_to(position)
			var falloff := 1.0 - (dist / 8.0)
			victim.take_damage(60.0 * falloff, null)  # 82mm mortar damage

	BattleSignals.explosion.emit(position, 8.0, 60.0)
	BattleSignals.artillery_impact.emit(position)

func _process_mortar_harassment(delta: float) -> void:
	# Clean up invalid mortar teams
	mortar_teams = mortar_teams.filter(func(m): return is_instance_valid(m))

# =============================================================================
# TRAIL WATCHER SYSTEM
# =============================================================================

func deploy_trail_watcher(position: Vector3, watch_direction: Vector3) -> Node3D:
	## Deploy a concealed observer to watch trails/roads

	if manpower < 1:
		return null

	var watcher := _create_vc_unit(GameEnums.UnitType.VC_LOCAL_FORCE)
	if not watcher:
		return null

	watcher.global_position = position
	get_tree().current_scene.add_child(watcher)

	# Enter stealth mode
	if watcher.has_method("enter_stealth"):
		watcher.enter_stealth()

	var watcher_data := {
		"unit": watcher,
		"position": position,
		"watch_direction": watch_direction.normalized(),
		"detection_range": 80.0,
		"last_report_time": 0.0,
	}
	trail_watchers.append(watcher_data)

	manpower -= 1
	return watcher

func _update_trail_watchers() -> void:
	var current_time := Time.get_ticks_msec() / 1000.0

	for i in range(trail_watchers.size() - 1, -1, -1):
		var watcher: Dictionary = trail_watchers[i]
		var unit: Node3D = watcher.unit

		if not is_instance_valid(unit):
			trail_watchers.remove_at(i)
			continue

		# Check for US units in watch cone
		var detected := _scan_watch_cone(watcher)
		if not detected.is_empty():
			# Report detection
			if current_time - watcher.last_report_time > 30.0:  # Rate limit reports
				for target in detected:
					var direction: Vector3 = target.global_position - unit.global_position
					trail_watcher_detected.emit(target, direction.normalized())
					intelligence += 2

					# Add to detected patrols for ambush planning
					detected_patrols.append({
						"unit": target,
						"position": target.global_position,
						"direction": direction.normalized(),
						"time": current_time,
					})

				watcher.last_report_time = current_time

	# Clean old patrol detections (older than 2 minutes)
	detected_patrols = detected_patrols.filter(
		func(p): return current_time - p.time < 120.0
	)

func _scan_watch_cone(watcher: Dictionary) -> Array[Node3D]:
	var results: Array[Node3D] = []
	var position: Vector3 = watcher.position
	var direction: Vector3 = watcher.watch_direction
	var range_val: float = watcher.detection_range

	var nearby := SpatialHashGrid.get_enemies_in_radius(
		position, range_val, GameEnums.Faction.VC
	)

	for unit in nearby:
		if not is_instance_valid(unit):
			continue

		# Check if in watch cone (60 degree cone)
		var to_unit := (unit.global_position - position).normalized()
		var dot := direction.dot(to_unit)

		if dot > 0.5:  # Within 60 degree cone
			results.append(unit)

	return results

# =============================================================================
# PROPAGANDA OPERATIONS
# =============================================================================

func _conduct_propaganda_operation() -> void:
	if propaganda_leaflets <= 0 or village_sympathizers.is_empty():
		return

	# Target neutral villages near sympathizer villages
	var all_villages := get_tree().get_nodes_in_group("villages")
	var neutral_targets: Array[Node3D] = []

	for village in all_villages:
		if village not in village_sympathizers and village is Node3D:
			var v_node: Node3D = village
			# Check if near a sympathizer village
			for sympathizer in village_sympathizers:
				if is_instance_valid(sympathizer):
					var s_node: Node3D = sympathizer
					if v_node.global_position.distance_to(s_node.global_position) < 200.0:
						neutral_targets.append(v_node)
						break

	if neutral_targets.is_empty():
		return

	# Conduct propaganda in one village
	var target: Node3D = neutral_targets.pick_random()
	propaganda_leaflets -= 1

	propaganda_dropped.emit(target)

	# Shift village allegiance toward VC
	if target.has_method("shift_allegiance"):
		target.shift_allegiance(GameEnums.Faction.VC, 0.1)

	# Chance to convert to sympathizer
	if randf() < 0.2:
		convert_village(target)

# =============================================================================
# UNIT CREATION
# =============================================================================

func _create_vc_unit(unit_type: int) -> Node3D:
	var scenes := {
		GameEnums.UnitType.VC_INFANTRY: "res://battle_system/nodes/vc_squad.tscn",
		GameEnums.UnitType.VC_SAPPERS: "res://battle_system/nodes/vc_sappers.tscn",
		GameEnums.UnitType.VC_MORTAR: "res://battle_system/nodes/vc_mortar.tscn",
		GameEnums.UnitType.VC_LOCAL_FORCE: "res://battle_system/nodes/vc_local.tscn",
	}

	var scene_path: String = scenes.get(unit_type, "")
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		# Create placeholder
		var placeholder := CharacterBody3D.new()
		placeholder.add_to_group("enemy_units")
		placeholder.add_to_group("vc_units")
		placeholder.set_meta("faction", GameEnums.Faction.VC)
		return placeholder

	var scene := load(scene_path) as PackedScene
	return scene.instantiate()

func _process_pending_spawns(delta: float) -> void:
	# Process any delayed spawns
	var completed: Array[int] = []

	for i in range(pending_spawns.size()):
		var spawn: Dictionary = pending_spawns[i]
		spawn.timer -= delta

		if spawn.timer <= 0:
			_execute_spawn(spawn)
			completed.append(i)

	for i in range(completed.size() - 1, -1, -1):
		pending_spawns.remove_at(completed[i])

func _execute_spawn(spawn: Dictionary) -> void:
	var unit := _create_vc_unit(spawn.unit_type)
	if unit:
		unit.global_position = spawn.position
		get_tree().current_scene.add_child(unit)
		vc_unit_spawned.emit(unit)


# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

func get_guerrilla_state_for_time() -> GuerrillaState:
	## Determine overall guerrilla posture based on time of day

	if WeatherSystem.is_night():
		if aggression_level > 0.6:
			return GuerrillaState.HARASSING
		else:
			return GuerrillaState.AMBUSHING
	else:
		return GuerrillaState.HIDING

func set_aggression_level(level: float) -> void:
	aggression_level = clampf(level, 0.0, 1.0)

func get_active_operation_count() -> int:
	return active_ambushes.size() + active_attacks.size() + fading_units.size()

func resupply_from_trail(amount: int) -> void:
	## Ho Chi Minh Trail resupply
	supplies += amount
	mortar_ammo += amount / 5
	propaganda_leaflets += amount / 10

# =============================================================================
# TUNNEL ENTRANCE CLASS
# =============================================================================

class TunnelEntrance extends Node3D:

	signal discovered()
	signal destroyed()

	var is_discovered: bool = false
	var is_destroyed: bool = false
	var cooldown: float = 0.0
	var spawn_capacity: int = 20  # Max units that can spawn per cycle
	var current_occupants: int = 0

	func _ready() -> void:
		add_to_group("tunnel_entrances")
		add_to_group("vc_structures")

	func discover() -> void:
		is_discovered = true
		discovered.emit()
		BattleSignals.vc_tunnel_spawned.emit(self)  # Alert US forces

	func destroy() -> void:
		is_destroyed = true
		destroyed.emit()

		# Explosion effect
		BattleSignals.explosion.emit(global_position, 5.0, 50.0)

		# Kill any occupants
		if current_occupants > 0:
			# These VC are lost
			pass

		queue_free()

	func can_spawn(count: int) -> bool:
		return not is_destroyed and cooldown <= 0.0 and spawn_capacity >= count

	func start_cooldown(duration: float = 30.0) -> void:
		cooldown = duration

	func _process(delta: float) -> void:
		if cooldown > 0:
			cooldown -= delta


# =============================================================================
# BOOBY TRAP CLASS
# =============================================================================

class BoobyTrap:
	var position: Vector3
	var trap_type: int  # TrapType enum
	var damage: float
	var detection_radius: float
	var is_armed: bool = true
