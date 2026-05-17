extends Node3D
class_name Village
## Village - Vietnamese village with allegiance system (hearts and minds)

signal allegiance_changed(old_allegiance: int, new_allegiance: int)
signal civic_action_performed(squad: Node3D)
signal vc_tax_collected()
signal village_attacked(attacker: Node3D)
signal population_changed(new_population: int)

@export var village_name: String = "Village"
@export var population: int = 100
@export var initial_allegiance: int = GameEnums.VillageAllegiance.NEUTRAL

# Allegiance
var allegiance: int = GameEnums.VillageAllegiance.NEUTRAL
var us_influence: float = 0.0  # 0.0 to 1.0
var vc_presence: float = 0.0   # 0.0 to 1.0

# Resources
var food_production: int = 10  # Food per cycle
var supplies_stockpiled: int = 0

# Status
var is_contested: bool = false
var under_attack: bool = false
var has_vc_cadre: bool = false  # VC political officer present

# Intel
var reported_vc_activity: bool = false
var intel_timer: float = 0.0

func _ready() -> void:
	add_to_group("villages")
	allegiance = initial_allegiance
	_update_allegiance()
	_create_visual()

func _create_visual() -> void:
	## Create placeholder village visual

	# Main hut cluster
	for i in range(3):
		var hut := CSGBox3D.new()
		hut.size = Vector3(4, 2.5, 4)

		var angle := (TAU / 3) * i
		var offset := Vector3(cos(angle) * 6, 1.25, sin(angle) * 6)
		hut.global_position = global_position + offset

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.45, 0.3)
		hut.material = mat

		add_child(hut)

		# Roof
		var roof := CSGBox3D.new()
		roof.size = Vector3(5, 0.5, 5)
		roof.position = Vector3(0, 1.5, 0)

		var roof_mat := StandardMaterial3D.new()
		roof_mat.albedo_color = Color(0.4, 0.35, 0.2)
		roof.material = roof_mat

		hut.add_child(roof)

	# Village center area
	var center := CSGCylinder3D.new()
	center.radius = 4.0
	center.height = 0.1
	center.global_position = global_position

	var center_mat := StandardMaterial3D.new()
	center_mat.albedo_color = Color(0.5, 0.4, 0.25)
	center.material = center_mat

	add_child(center)

func _process(delta: float) -> void:
	_update_influence(delta)
	_update_intel(delta)

# =============================================================================
# ALLEGIANCE SYSTEM
# =============================================================================

func get_allegiance() -> int:
	return allegiance

func get_allegiance_name() -> String:
	match allegiance:
		GameEnums.VillageAllegiance.NEUTRAL:
			return "Neutral"
		GameEnums.VillageAllegiance.PRO_US:
			return "Pro-US"
		GameEnums.VillageAllegiance.PRO_VC:
			return "Pro-VC"
		GameEnums.VillageAllegiance.CONTESTED:
			return "Contested"
		_:
			return "Unknown"

func _update_allegiance() -> void:
	var old_allegiance := allegiance

	# Determine allegiance based on influence
	if us_influence > 0.6 and vc_presence < 0.3:
		allegiance = GameEnums.VillageAllegiance.PRO_US
		is_contested = false
	elif vc_presence > 0.6 and us_influence < 0.3:
		allegiance = GameEnums.VillageAllegiance.PRO_VC
		is_contested = false
	elif us_influence > 0.3 and vc_presence > 0.3:
		allegiance = GameEnums.VillageAllegiance.CONTESTED
		is_contested = true
	else:
		allegiance = GameEnums.VillageAllegiance.NEUTRAL
		is_contested = false

	if old_allegiance != allegiance:
		allegiance_changed.emit(old_allegiance, allegiance)
		BattleSignals.village_allegiance_changed.emit(self, old_allegiance, allegiance)

func _update_influence(delta: float) -> void:
	# Natural decay of influence
	us_influence = maxf(0.0, us_influence - 0.001 * delta)
	vc_presence = maxf(0.0, vc_presence - 0.001 * delta)

	# VC cadre increases presence
	if has_vc_cadre:
		vc_presence = minf(1.0, vc_presence + 0.005 * delta)

	_update_allegiance()

# =============================================================================
# HEARTS AND MINDS (US INFLUENCE)
# =============================================================================

func apply_civic_action(squad: Node3D) -> void:
	## US squad performs civic action (hearts and minds)
	us_influence = minf(1.0, us_influence + 0.1)
	vc_presence = maxf(0.0, vc_presence - 0.05)

	_update_allegiance()

	civic_action_performed.emit(squad)
	BattleSignals.village_civic_action.emit(self, squad)

func provide_medical_aid() -> void:
	## Medical team provides aid to village
	us_influence = minf(1.0, us_influence + 0.15)
	population = mini(population + 5, 200)  # Better health

	_update_allegiance()

func distribute_supplies(amount: int) -> void:
	## Distribute supplies to villagers
	us_influence = minf(1.0, us_influence + 0.05 * (amount / 10.0))
	supplies_stockpiled += amount

	_update_allegiance()

# =============================================================================
# VC OPERATIONS
# =============================================================================

func vc_taxation() -> void:
	## VC collects taxes (food, supplies, recruits)
	vc_presence = minf(1.0, vc_presence + 0.1)
	us_influence = maxf(0.0, us_influence - 0.05)

	# VC takes supplies
	var tax := mini(supplies_stockpiled, 20)
	supplies_stockpiled -= tax

	_update_allegiance()

	vc_tax_collected.emit()
	BattleSignals.village_vc_tax.emit(self)

func install_vc_cadre() -> void:
	## VC installs political cadre
	has_vc_cadre = true
	vc_presence = minf(1.0, vc_presence + 0.2)
	_update_allegiance()

func remove_vc_cadre() -> void:
	## Remove VC cadre (through combat or civic action)
	has_vc_cadre = false

func recruit_vc() -> int:
	## VC recruits from village
	if allegiance != GameEnums.VillageAllegiance.PRO_VC:
		return 0

	var recruits := randi_range(1, 5)
	recruits = mini(recruits, population / 20)  # Max 5% of population
	population -= recruits

	population_changed.emit(population)
	return recruits

# =============================================================================
# COMBAT
# =============================================================================

func report_attack(attacker: Node3D) -> void:
	under_attack = true

	village_attacked.emit(attacker)
	BattleSignals.village_attacked.emit(self, attacker)

	# Attacks by US reduce influence
	if attacker.has_method("get_faction"):
		if GameEnums.is_us_faction(attacker.get_faction()):
			us_influence = maxf(0.0, us_influence - 0.2)
			_update_allegiance()

func apply_collateral_damage(amount: float) -> void:
	## Collateral damage from combat
	population = maxi(0, population - int(amount))
	us_influence = maxf(0.0, us_influence - amount * 0.01)

	population_changed.emit(population)
	_update_allegiance()

# =============================================================================
# INTELLIGENCE
# =============================================================================

func _update_intel(delta: float) -> void:
	intel_timer += delta

	# Pro-US villages report VC activity
	if allegiance == GameEnums.VillageAllegiance.PRO_US and intel_timer > 60.0:
		intel_timer = 0.0
		_report_vc_activity()

func _report_vc_activity() -> void:
	if vc_presence > 0.3:
		reported_vc_activity = true
		# Report to IntelDirector
		# IntelDirector.receive_village_intel(self, "VC activity detected")

func provide_intel() -> Dictionary:
	## Get intel from friendly village
	if allegiance != GameEnums.VillageAllegiance.PRO_US:
		return {}

	return {
		"vc_presence": vc_presence,
		"has_cadre": has_vc_cadre,
		"recent_activity": reported_vc_activity,
	}

# =============================================================================
# UTILITIES
# =============================================================================

func get_status() -> Dictionary:
	return {
		"name": village_name,
		"population": population,
		"allegiance": get_allegiance_name(),
		"us_influence": us_influence,
		"vc_presence": vc_presence,
		"contested": is_contested,
		"has_vc_cadre": has_vc_cadre,
	}

func shift_allegiance(toward_faction: int, amount: float) -> void:
	## Shift village allegiance toward a faction

	if GameEnums.is_us_faction(toward_faction):
		us_influence = minf(1.0, us_influence + amount)
		vc_presence = maxf(0.0, vc_presence - amount * 0.5)
	else:
		vc_presence = minf(1.0, vc_presence + amount)
		us_influence = maxf(0.0, us_influence - amount * 0.5)

	_update_allegiance()

# =============================================================================
# PRODUCTION & RESOURCES
# =============================================================================

func get_food_production() -> int:
	## Get village food production per cycle
	var base := food_production

	# Pro-US villages have better production
	if allegiance == GameEnums.VillageAllegiance.PRO_US:
		base = int(base * 1.2)

	# War disrupts production
	if under_attack or is_contested:
		base = int(base * 0.5)

	return base

func collect_supplies() -> int:
	## Collect available supplies from village
	var available := supplies_stockpiled
	supplies_stockpiled = 0
	return available

func add_supplies(amount: int) -> void:
	supplies_stockpiled += amount

# =============================================================================
# SEARCH OPERATIONS
# =============================================================================

func conduct_search(search_squad: Node3D) -> Dictionary:
	## US squad searches village for VC

	var result := {
		"vc_found": false,
		"weapons_found": 0,
		"cadre_captured": false,
		"civilians_angered": false,
	}

	# Chance to find VC based on presence
	if randf() < vc_presence * 0.5:
		result.vc_found = true
		result.weapons_found = randi_range(1, 5)

	# Chance to find cadre
	if has_vc_cadre and randf() < 0.3:
		result.cadre_captured = true
		has_vc_cadre = false
		vc_presence = maxf(0.0, vc_presence - 0.3)

	# Aggressive searches anger civilians
	if randf() < 0.4:
		result.civilians_angered = true
		us_influence = maxf(0.0, us_influence - 0.1)

	_update_allegiance()
	return result

func relocate_population() -> int:
	## Forcibly relocate village population (Strategic Hamlet Program)
	## This is historically accurate but reduces US influence

	var relocated := population / 2
	population -= relocated

	# Major impact on influence
	us_influence = maxf(0.0, us_influence - 0.4)
	vc_presence = maxf(0.0, vc_presence - 0.2)  # Also removes VC

	_update_allegiance()
	population_changed.emit(population)

	return relocated

# =============================================================================
# DEFENSE
# =============================================================================

func has_local_defense() -> bool:
	## Check if village has local defense forces
	return allegiance == GameEnums.VillageAllegiance.PRO_US and population > 50

func get_defense_strength() -> int:
	## Get village self-defense capability
	if not has_local_defense():
		return 0

	return population / 10  # 10% of population can fight

func arm_local_defense() -> void:
	## Provide weapons to village defense force
	if allegiance == GameEnums.VillageAllegiance.PRO_US:
		us_influence = minf(1.0, us_influence + 0.1)
		_update_allegiance()
