extends Node
## class_name TunnelNetwork  # ARCHIVED
## TunnelNetwork - VC underground tunnel complex system
## Famous Cu Chi-style tunnels with multiple levels, caches, and escape routes

signal tunnel_discovered(entrance: TunnelEntrance)
signal tunnel_destroyed(entrance: TunnelEntrance)
signal tunnel_collapsed(position: Vector3)
signal tunnel_spawn(entrance: TunnelEntrance, units: Array)
signal tunnel_transit(unit: Node3D, from_entrance: TunnelEntrance, to_entrance: TunnelEntrance)
signal cache_discovered(cache: SupplyCache)
signal tunnel_rat_operation_started(entrance: TunnelEntrance)
signal tunnel_rat_operation_complete(entrance: TunnelEntrance, result: Dictionary)
signal vc_escaped(unit: Node3D, exit: TunnelEntrance)

# All tunnel entrances in this network
var entrances: Array[TunnelEntrance] = []

# Network properties
var network_id: String = "tunnel_network_1"
var network_name: String = "Cu Chi Complex"
var is_connected_to_ho_chi_minh_trail: bool = false
var network_depth: int = 3  # Number of levels (1-3)
var network_integrity: float = 100.0  # 0-100, damage affects functionality

# Spawn capacity
var max_spawn_rate: int = 10  # Units per minute
var current_spawn_rate: int = 0
var spawn_cooldown: float = 0.0

# Underground features
var supply_caches: Array[SupplyCache] = []
var medical_stations: Array[Vector3] = []  # Underground medical areas
var command_bunkers: Array[Vector3] = []   # Underground command posts
var ventilation_shafts: Array[Vector3] = []  # Can be used to detect/gas tunnels

# Discovery and mapping
var known_entrances: Array[TunnelEntrance] = []
var mapped_sections: float = 0.0  # 0-100, how much of network is mapped

# Transit system
var units_in_transit: Array[Dictionary] = []
const TRANSIT_SPEED: float = 2.0  # Units per second (crawling underground)

# Tunnel Rat operations
var tunnel_rat_teams_inside: Array[Dictionary] = []
var defenses_active: bool = true  # Booby traps, scorpions, etc.

func _ready() -> void:
	add_to_group("tunnel_networks")
	BattleSignals.vc_tunnel_spawned.emit(self)

func _process(delta: float) -> void:
	if spawn_cooldown > 0:
		spawn_cooldown -= delta

	# Reset spawn rate every minute
	if spawn_cooldown <= 0:
		current_spawn_rate = 0
		spawn_cooldown = 60.0

	_process_transit(delta)
	_process_tunnel_rat_operations(delta)
	_repair_network(delta)

func _process_transit(delta: float) -> void:
	## Process units moving through tunnels
	var completed: Array[int] = []

	for i in range(units_in_transit.size()):
		var transit: Dictionary = units_in_transit[i]
		transit.progress += TRANSIT_SPEED * delta

		var distance: float = transit.distance
		if transit.progress >= distance:
			# Unit arrives at destination
			_complete_transit(transit)
			completed.append(i)

	for i in range(completed.size() - 1, -1, -1):
		units_in_transit.remove_at(completed[i])

func _complete_transit(transit: Dictionary) -> void:
	var unit: Node3D = transit.unit
	var exit: TunnelEntrance = transit.destination

	if not is_instance_valid(unit) or not is_instance_valid(exit) or exit.is_destroyed:
		return

	# Emerge from exit
	unit.global_position = exit.global_position + Vector3(
		randf_range(-2, 2), 0, randf_range(-2, 2)
	)
	unit.visible = true

	if unit.has_method("on_tunnel_exit"):
		unit.on_tunnel_exit(exit)

	tunnel_transit.emit(unit, transit.origin, exit)
	exit.unit_emerged.emit(unit)

func _process_tunnel_rat_operations(delta: float) -> void:
	## Process active tunnel rat clearing operations
	var completed: Array[int] = []

	for i in range(tunnel_rat_teams_inside.size()):
		var op: Dictionary = tunnel_rat_teams_inside[i]
		op.timer += delta

		# Check for hazards
		if defenses_active and randf() < 0.01 * delta:  # 1% per second chance of danger
			op.team_casualties += 1
			op.hazards_encountered.append(_get_random_hazard())

		# Progress mapping
		if op.timer >= op.duration:
			completed.append(i)
			_complete_tunnel_rat_operation(op)

	for i in range(completed.size() - 1, -1, -1):
		tunnel_rat_teams_inside.remove_at(completed[i])

func _get_random_hazard() -> String:
	var hazards: Array[String] = ["punji_trap", "grenade_trap", "scorpion", "snake", "vc_defender", "collapse"]
	return hazards[randi() % hazards.size()]

func _complete_tunnel_rat_operation(op: Dictionary) -> void:
	var result := {
		"success": op.team_casualties < op.team_size,
		"casualties": op.team_casualties,
		"caches_found": op.caches_found,
		"tunnels_mapped": op.tunnels_mapped,
		"hazards": op.hazards_encountered,
	}

	# Update network state
	mapped_sections = minf(100.0, mapped_sections + op.tunnels_mapped)

	# Optionally destroy section
	if op.destroy:
		_damage_network(op.entrance, 30.0)

	tunnel_rat_operation_complete.emit(op.entrance, result)

func _repair_network(delta: float) -> void:
	## VC slowly repair tunnel damage
	if network_integrity < 100.0:
		network_integrity = minf(100.0, network_integrity + 0.1 * delta)

# =============================================================================
# ENTRANCE MANAGEMENT
# =============================================================================

func add_entrance(position: Vector3, entrance_type: int = 0) -> TunnelEntrance:
	var entrance := TunnelEntrance.new()
	entrance.global_position = position
	entrance.network = self
	entrance.entrance_type = entrance_type
	add_child(entrance)
	entrances.append(entrance)

	entrance.discovered.connect(_on_entrance_discovered)
	entrance.destroyed.connect(_on_entrance_destroyed)

	return entrance

func create_network_layout(center: Vector3, size: int = 5) -> void:
	## Generate a tunnel network with multiple entrances
	for i in range(size):
		var angle := TAU * float(i) / float(size)
		var distance := randf_range(30, 80)
		var pos := center + Vector3(cos(angle) * distance, 0, sin(angle) * distance)

		var entrance_type := 0  # Standard
		if i == 0:
			entrance_type = 1  # Main entrance
		elif randf() < 0.3:
			entrance_type = 2  # Emergency exit

		add_entrance(pos, entrance_type)

	# Add central command bunker
	command_bunkers.append(center)

func remove_entrance(entrance: TunnelEntrance) -> void:
	entrances.erase(entrance)
	known_entrances.erase(entrance)

func get_entrance_near(position: Vector3, max_distance: float) -> TunnelEntrance:
	var nearest: TunnelEntrance = null
	var nearest_dist := INF

	for entrance in entrances:
		if entrance.is_destroyed:
			continue

		var dist := position.distance_to(entrance.global_position)
		if dist < nearest_dist and dist <= max_distance:
			nearest_dist = dist
			nearest = entrance

	return nearest

func get_hidden_entrance_near(position: Vector3, max_distance: float) -> TunnelEntrance:
	## Get undiscovered entrance
	for entrance in entrances:
		if entrance.is_destroyed or entrance.is_discovered:
			continue

		var dist := position.distance_to(entrance.global_position)
		if dist <= max_distance:
			return entrance

	return null

func get_random_exit(excluding: TunnelEntrance = null) -> TunnelEntrance:
	## Get random undestroyed entrance for exit
	var valid: Array[TunnelEntrance] = []

	for entrance in entrances:
		if entrance != excluding and not entrance.is_destroyed:
			valid.append(entrance)

	if valid.is_empty():
		return null

	return valid[randi() % valid.size()]

func get_farthest_exit(from: TunnelEntrance) -> TunnelEntrance:
	## Get the farthest entrance from the given one (best escape route)
	var farthest: TunnelEntrance = null
	var farthest_dist := 0.0

	for entrance in entrances:
		if entrance == from or entrance.is_destroyed:
			continue

		var dist := from.global_position.distance_to(entrance.global_position)
		if dist > farthest_dist:
			farthest_dist = dist
			farthest = entrance

	return farthest

# =============================================================================
# UNDERGROUND TRANSIT
# =============================================================================

func move_unit_through_tunnel(unit: Node3D, from: TunnelEntrance, to: TunnelEntrance) -> bool:
	## Move a unit through the tunnel network
	if not is_instance_valid(unit) or from.is_destroyed or to.is_destroyed:
		return false

	if network_integrity < 30.0:
		return false  # Too damaged

	# Hide unit while in tunnel
	unit.visible = false

	if unit.has_method("on_tunnel_enter"):
		unit.on_tunnel_enter(from)

	var distance := from.global_position.distance_to(to.global_position)

	var transit := {
		"unit": unit,
		"origin": from,
		"destination": to,
		"distance": distance,
		"progress": 0.0,
	}

	units_in_transit.append(transit)
	return true

func escape_through_tunnel(unit: Node3D, from_position: Vector3) -> TunnelEntrance:
	## VC unit attempts to escape through nearest tunnel
	var entrance := get_entrance_near(from_position, 30.0)
	if not entrance:
		return null

	var exit := get_farthest_exit(entrance)
	if not exit:
		return null

	if move_unit_through_tunnel(unit, entrance, exit):
		vc_escaped.emit(unit, exit)
		return exit

	return null

func get_units_in_transit() -> int:
	return units_in_transit.size()

func get_transit_progress(unit: Node3D) -> float:
	## Get how far through transit a unit is (0-1)
	for transit in units_in_transit:
		if transit.unit == unit:
			return transit.progress / transit.distance
	return -1.0

# =============================================================================
# SPAWNING
# =============================================================================

func can_spawn(count: int) -> bool:
	return current_spawn_rate + count <= max_spawn_rate

func request_spawn(entrance: TunnelEntrance, unit_type: int, count: int) -> Array[Node3D]:
	if not can_spawn(count):
		count = max_spawn_rate - current_spawn_rate

	if count <= 0:
		return []

	var units: Array[Node3D] = []
	current_spawn_rate += count

	for i in range(count):
		var unit := _create_unit(unit_type)
		if unit:
			unit.global_position = entrance.global_position + Vector3(
				randf_range(-2, 2), 0, randf_range(-2, 2)
			)
			get_tree().current_scene.add_child(unit)
			units.append(unit)

	tunnel_spawn.emit(entrance, units)
	return units

func _create_unit(unit_type: int) -> Node3D:
	# Delegate to VCController for consistency
	var vc := get_tree().get_first_node_in_group("vc_controller") as VCController
	if vc:
		return vc._create_vc_unit(unit_type)

	# Fallback placeholder
	var placeholder := CharacterBody3D.new()
	placeholder.add_to_group("enemy_units")
	placeholder.set_meta("faction", GameEnums.Faction.VC)
	return placeholder

# =============================================================================
# DISCOVERY
# =============================================================================

func _on_entrance_discovered(entrance: TunnelEntrance) -> void:
	if entrance not in known_entrances:
		known_entrances.append(entrance)
	tunnel_discovered.emit(entrance)
	BattleSignals.vc_tunnel_spawned.emit(entrance)

func _on_entrance_destroyed(entrance: TunnelEntrance) -> void:
	entrances.erase(entrance)
	known_entrances.erase(entrance)
	_damage_network(entrance, 15.0)
	tunnel_destroyed.emit(entrance)

func get_discovered_count() -> int:
	return known_entrances.size()

func get_total_count() -> int:
	return entrances.size()

func get_undiscovered_count() -> int:
	return entrances.size() - known_entrances.size()

# =============================================================================
# TUNNEL RAT OPERATIONS
# =============================================================================

func send_tunnel_rats(entrance: TunnelEntrance, team_size: int = 2,
					  duration: float = 120.0, destroy: bool = false) -> void:
	## Send tunnel rat team to explore/destroy tunnel section
	if entrance.is_destroyed or entrance not in entrances:
		return

	var operation := {
		"entrance": entrance,
		"team_size": team_size,
		"team_casualties": 0,
		"timer": 0.0,
		"duration": duration,
		"destroy": destroy,
		"caches_found": 0,
		"tunnels_mapped": randf_range(5.0, 15.0),
		"hazards_encountered": [],
	}

	tunnel_rat_teams_inside.append(operation)
	tunnel_rat_operation_started.emit(entrance)

func gas_tunnel(entrance: TunnelEntrance) -> void:
	## Use CS gas to force VC out of tunnels
	if entrance.is_destroyed:
		return

	# Flush out any units in transit near this entrance
	for transit in units_in_transit:
		if transit.origin == entrance or transit.destination == entrance:
			var unit: Node3D = transit.unit
			if is_instance_valid(unit):
				# Unit emerges coughing
				unit.visible = true
				unit.global_position = entrance.global_position
				if unit.has_method("apply_suppression"):
					unit.apply_suppression(50.0)

	# Temporarily disable entrance
	entrance.cooldown = 60.0

	# Disable defenses temporarily
	defenses_active = false
	get_tree().create_timer(30.0).timeout.connect(func(): defenses_active = true)

func collapse_tunnel(entrance: TunnelEntrance) -> void:
	## Use explosives to collapse tunnel section
	if entrance.is_destroyed:
		return

	entrance.destroy()

	# May collapse connected entrances
	for other in entrances:
		if other != entrance and not other.is_destroyed:
			if entrance.global_position.distance_to(other.global_position) < 20.0:
				if randf() < 0.3:  # 30% chance to collapse nearby
					other.destroy()

	_damage_network(entrance, 25.0)
	tunnel_collapsed.emit(entrance.global_position)

func flood_tunnel() -> void:
	## Attempt to flood entire network (requires water source nearby)
	network_integrity = 0.0
	defenses_active = false

	# Kill all units in transit
	for transit in units_in_transit:
		var unit: Node3D = transit.unit
		if is_instance_valid(unit) and unit.has_method("take_damage"):
			unit.take_damage(999.0, null)

	units_in_transit.clear()

	# Disable all entrances temporarily
	for entrance in entrances:
		entrance.cooldown = 300.0  # 5 minutes

func _damage_network(source: TunnelEntrance, amount: float) -> void:
	network_integrity = maxf(0.0, network_integrity - amount)

	# Reduced spawn rate when damaged
	if network_integrity < 50.0:
		max_spawn_rate = int(10 * (network_integrity / 100.0))

func get_network_status() -> Dictionary:
	return {
		"name": network_name,
		"integrity": network_integrity,
		"entrances_total": entrances.size(),
		"entrances_discovered": known_entrances.size(),
		"entrances_destroyed": 0,  # Would track this
		"mapped_percentage": mapped_sections,
		"connected_to_trail": is_connected_to_ho_chi_minh_trail,
		"caches": supply_caches.size(),
		"units_in_transit": units_in_transit.size(),
	}

# =============================================================================
# SUPPLY CACHES
# =============================================================================

func add_supply_cache(position: Vector3, supplies: int = 50, weapons: int = 10) -> SupplyCache:
	var cache := SupplyCache.new()
	cache.position = position
	cache.supplies = supplies
	cache.weapons = weapons
	supply_caches.append(cache)
	return cache

func discover_cache(cache: SupplyCache) -> void:
	cache.is_discovered = true
	cache_discovered.emit(cache)

func seize_cache(cache: SupplyCache) -> Dictionary:
	## US forces seize a discovered cache
	var contents := {
		"supplies": cache.supplies,
		"weapons": cache.weapons,
		"documents": cache.has_documents,
	}

	supply_caches.erase(cache)
	return contents

func get_total_cached_supplies() -> int:
	var total := 0
	for cache in supply_caches:
		total += cache.supplies
	return total

# =============================================================================
# NETWORK CONNECTIONS
# =============================================================================

func connect_to_trail() -> void:
	## Connect to Ho Chi Minh trail for unlimited reinforcements
	is_connected_to_ho_chi_minh_trail = true
	max_spawn_rate = 20

func disconnect_from_trail() -> void:
	## Trail connection severed (by bombing, etc.)
	is_connected_to_ho_chi_minh_trail = false
	max_spawn_rate = 10

func is_functional() -> bool:
	return network_integrity > 10.0 and not entrances.is_empty()

# =============================================================================
# TACTICAL FUNCTIONS
# =============================================================================

func launch_tunnel_attack(target: Node3D) -> Array[Node3D]:
	## Launch surprise attack from nearest hidden entrance
	var nearest := get_hidden_entrance_near(target.global_position, 100.0)
	if not nearest:
		nearest = get_entrance_near(target.global_position, 100.0)

	if not nearest or nearest.is_destroyed:
		return []

	# Spawn assault force
	var attackers := request_spawn(nearest, GameEnums.UnitType.VC_INFANTRY, 10)

	# Order to attack
	for attacker in attackers:
		if attacker.has_method("attack"):
			attacker.attack(target)

	BattleSignals.vc_tunnel_attack_started.emit(target, nearest)
	return attackers

func provide_escape_route(units: Array[Node3D]) -> int:
	## Provide escape route for retreating VC
	var escaped := 0

	for unit in units:
		if is_instance_valid(unit):
			var result := escape_through_tunnel(unit, unit.global_position)
			if result:
				escaped += 1

	return escaped


# =============================================================================
# TUNNEL ENTRANCE CLASS
# =============================================================================

class TunnelEntrance:
	extends Node3D

	signal discovered()
	signal destroyed()
	signal unit_emerged(unit: Node3D)
	signal unit_entered(unit: Node3D)

	# Entrance types
	enum EntranceType {
		STANDARD,       # Normal concealed entrance
		MAIN,           # Larger, main entrance
		EMERGENCY,      # Small emergency exit
		TRAPDOOR,       # Spider hole style
		UNDERWATER,     # Exits into river/pond
	}

	var network: TunnelNetwork = null
	var entrance_type: int = EntranceType.STANDARD
	var is_discovered: bool = false
	var is_destroyed: bool = false
	var cooldown: float = 0.0
	var concealment_level: float = 0.8  # 0-1, how hidden

	# Visual
	var visual_mesh: MeshInstance3D = null

	func _ready() -> void:
		add_to_group("tunnel_entrances")
		_create_visual()

	func _process(delta: float) -> void:
		if cooldown > 0:
			cooldown -= delta

	func _create_visual() -> void:
		## Create subtle visual hint for entrance
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.8
		mesh.bottom_radius = 1.0
		mesh.height = 0.3

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.25, 0.2, 0.5)  # Dirt colored
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

		visual_mesh = MeshInstance3D.new()
		visual_mesh.mesh = mesh
		visual_mesh.material_override = mat
		visual_mesh.position.y = -0.1  # Slightly below ground

		add_child(visual_mesh)

		# Hide until discovered
		if not is_discovered:
			visual_mesh.visible = false

	func discover() -> void:
		if not is_discovered:
			is_discovered = true
			if visual_mesh:
				visual_mesh.visible = true
			discovered.emit()

	func destroy() -> void:
		if not is_destroyed:
			is_destroyed = true

			# Create destruction effect
			if visual_mesh:
				var mat := visual_mesh.material_override as StandardMaterial3D
				if mat:
					mat.albedo_color = Color(0.2, 0.2, 0.2)

			destroyed.emit()
			if network:
				network.remove_entrance(self)

	func can_use() -> bool:
		return not is_destroyed and cooldown <= 0

	func spawn_unit(unit_type: int) -> Node3D:
		if not can_use() or not network:
			return null

		var units := network.request_spawn(self, unit_type, 1)
		if not units.is_empty():
			unit_emerged.emit(units[0])
			return units[0]
		return null

	func spawn_units(unit_type: int, count: int) -> Array[Node3D]:
		if not can_use() or not network:
			return []

		return network.request_spawn(self, unit_type, count)

	func enter_tunnel(unit: Node3D, destination: TunnelEntrance = null) -> bool:
		if not can_use() or not network:
			return false

		if destination == null:
			destination = network.get_random_exit(self)

		if destination == null:
			return false

		unit_entered.emit(unit)
		return network.move_unit_through_tunnel(unit, self, destination)

	func get_detection_chance(searcher_distance: float) -> float:
		## Chance of detecting this entrance
		if is_discovered or is_destroyed:
			return 1.0  # Already known

		var base_chance := 1.0 - concealment_level
		var distance_factor := maxf(0.0, 1.0 - searcher_distance / 20.0)

		# Entrance type affects detection
		match entrance_type:
			EntranceType.TRAPDOOR:
				base_chance *= 0.5  # Harder to find
			EntranceType.UNDERWATER:
				base_chance *= 0.3  # Very hard to find
			EntranceType.MAIN:
				base_chance *= 1.5  # Easier to find

		return clampf(base_chance * distance_factor, 0.0, 1.0)

	func search_for_entrance(searcher: Node3D) -> bool:
		## Attempt to discover this entrance
		var distance := global_position.distance_to(searcher.global_position)
		var chance := get_detection_chance(distance)

		if randf() < chance:
			discover()
			return true
		return false

# =============================================================================
# SUPPLY CACHE CLASS
# =============================================================================

class SupplyCache:
	extends RefCounted

	var position: Vector3 = Vector3.ZERO
	var supplies: int = 50
	var weapons: int = 10
	var ammo: int = 100
	var medical: int = 20
	var has_documents: bool = false  # Intel value
	var is_discovered: bool = false
	var is_booby_trapped: bool = true

	static func create(pos: Vector3, size: String = "medium") -> SupplyCache:
		var cache := SupplyCache.new()
		cache.position = pos

		match size:
			"small":
				cache.supplies = 20
				cache.weapons = 5
				cache.ammo = 50
			"medium":
				cache.supplies = 50
				cache.weapons = 10
				cache.ammo = 100
			"large":
				cache.supplies = 100
				cache.weapons = 25
				cache.ammo = 200
				cache.has_documents = true

		return cache

	func get_total_value() -> int:
		return supplies + weapons * 5 + ammo + medical * 3
