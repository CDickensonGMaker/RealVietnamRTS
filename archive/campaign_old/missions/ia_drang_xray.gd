extends Node
class_name IaDrangXRayMission
## Ia Drang Valley - LZ X-Ray Mission
## November 14-16, 1965
## The first major battle between US and NVA forces

signal mission_started()
signal objective_updated(objective_id: String, status: String)
signal mission_complete(result: String)
signal mission_failed(reason: String)

# =============================================================================
# MISSION CONFIGURATION
# =============================================================================
const MISSION_NAME := "LZ X-Ray"
const MISSION_BRIEFING := """
November 14, 1965 - Ia Drang Valley, Central Highlands

Lieutenant Colonel Hal Moore leads the 1st Battalion, 7th Cavalry into
Landing Zone X-Ray at the base of the Chu Pong Massif. Unknown to the
Americans, three NVA regiments are positioned in the mountains above.

MISSION: Establish and hold LZ X-Ray against determined NVA assault.

OBJECTIVES:
- Establish defensive perimeter
- Hold LZ for 24 hours (simulated as waves)
- Maintain combat effectiveness above 50%

HISTORICAL NOTE: This battle tested the concept of Air Cavalry tactics
and saw the first use of B-52 Arc Light strikes in support of ground troops.
"""

# Wave configuration - historically accurate enemy composition
const MISSION_WAVES: Array[Dictionary] = [
	# Wave 1: Initial probe (1030 hours)
	{
		"name": "Initial Contact",
		"nva_infantry": 20,
		"delay": 30.0,
		"approach": "west",
		"briefing": "NVA scouts have made contact. Expect probing attacks.",
	},
	# Wave 2: First assault (1230 hours)
	{
		"name": "First Assault",
		"nva_infantry": 40,
		"nva_heavy": 5,
		"delay": 120.0,
		"approach": "west",
		"briefing": "NVA forces are massing for assault from the Chu Pong.",
	},
	# Wave 3: Human wave assault (1430 hours)
	{
		"name": "Human Wave",
		"nva_infantry": 80,
		"nva_heavy": 10,
		"delay": 180.0,
		"approach": "southwest",
		"briefing": "BROKEN ARROW imminent! Mass NVA assault underway!",
	},
	# Wave 4: Night probe (2000 hours)
	{
		"name": "Night Probe",
		"nva_infantry": 30,
		"nva_sappers": 10,
		"delay": 240.0,
		"approach": "all",
		"briefing": "Night has fallen. Expect infiltration attempts.",
	},
	# Wave 5: Dawn assault (0630 hours, Day 2)
	{
		"name": "Dawn Assault",
		"nva_infantry": 100,
		"nva_heavy": 15,
		"delay": 300.0,
		"approach": "north",
		"briefing": "Dawn assault! All positions stand to!",
	},
	# Wave 6: Final push (1000 hours, Day 2)
	{
		"name": "Final Push",
		"nva_infantry": 60,
		"nva_heavy": 20,
		"delay": 360.0,
		"approach": "all",
		"briefing": "NVA throwing everything at us! Hold the line!",
	},
]

# Starting forces - historically accurate
const STARTING_FORCES := {
	"rifle_platoons": 4,      # A, B, C, D companies represented
	"weapons_squads": 2,      # Heavy weapons
	"engineers": 1,           # Combat engineers
	"mortar_teams": 2,        # 81mm mortars
}

# Map configuration
const MAP_SIZE := Vector2(300, 300)
const LZ_CENTER := Vector3(150, 0, 150)
const CHU_PONG_DIRECTION := Vector3(-1, 0, -0.5).normalized()  # Southwest

# =============================================================================
# MISSION STATE
# =============================================================================
var current_wave: int = 0
var wave_timer: float = 0.0
var wave_active: bool = false
var enemies_remaining: int = 0

var is_started: bool = false
var is_complete: bool = false
var is_failed: bool = false

var player_firebase: Firebase = null
var initial_garrison_count: int = 0
var broken_arrow_called: bool = false

# Objectives
var objectives: Dictionary = {
	"establish_lz": {"complete": false, "description": "Establish LZ X-Ray"},
	"survive_waves": {"complete": false, "description": "Survive all enemy waves"},
	"maintain_strength": {"complete": false, "description": "Maintain combat effectiveness"},
}

# References
var main_scene: Node3D = null
var player_units: Node3D = null
var enemy_units: Node3D = null

# =============================================================================
# INITIALIZATION
# =============================================================================

func setup(main: Node3D) -> void:
	main_scene = main
	player_units = main.get_node("GameWorld/Units/PlayerUnits")
	enemy_units = main.get_node("GameWorld/Units/EnemyUnits")

func start_mission() -> void:
	if is_started:
		return

	is_started = true

	print("=" .repeat(60))
	print("MISSION: %s" % MISSION_NAME)
	print("=" .repeat(60))
	print(MISSION_BRIEFING)
	print("=" .repeat(60))

	# Create firebase
	_create_lz_xray()

	# Deploy initial forces
	_deploy_initial_forces()

	# Mark first objective complete
	_complete_objective("establish_lz")

	# Start first wave timer
	wave_timer = MISSION_WAVES[0].delay
	current_wave = 0

	mission_started.emit()
	BattleSignals.mission_started.emit(MISSION_NAME)

	print("First wave in %.0f seconds!" % wave_timer)

func _create_lz_xray() -> void:
	player_firebase = Firebase.new()
	player_firebase.firebase_name = "LZ X-Ray"
	player_firebase.firebase_callsign = "X-RAY"
	player_firebase.global_position = LZ_CENTER

	var firebases := main_scene.get_node("GameWorld/Firebases")
	firebases.add_child(player_firebase)

	# Add visual
	var visual := CSGBox3D.new()
	visual.size = Vector3(40, 0.3, 40)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.45, 0.35)
	visual.material = mat
	player_firebase.add_child(visual)

	# Create perimeter defenses
	_create_perimeter()

func _create_perimeter() -> void:
	# Sandbag positions in circular perimeter
	for i in range(12):
		var angle := (TAU / 12) * i
		var pos := LZ_CENTER + Vector3(cos(angle) * 30, 0, sin(angle) * 30)

		# Wire obstacle
		var wire_start := pos + Vector3(cos(angle + 0.2) * 5, 0, sin(angle + 0.2) * 5)
		var wire_end := pos + Vector3(cos(angle - 0.2) * 5, 0, sin(angle - 0.2) * 5)
		player_firebase.add_wire_segment(wire_start, wire_end)

	# Claymores facing Chu Pong (likely attack direction)
	for i in range(6):
		var angle := PI + (PI / 6) * (i - 2.5)  # Southwest arc
		var pos := LZ_CENTER + Vector3(cos(angle) * 40, 0, sin(angle) * 40)
		var direction := Vector3(cos(angle), 0, sin(angle))
		player_firebase.place_claymore(pos, direction)

func _deploy_initial_forces() -> void:
	var positions := _get_perimeter_positions()

	# Deploy rifle platoons
	for i in range(STARTING_FORCES.rifle_platoons):
		var pos: Vector3 = positions[i % positions.size()]
		var squad := _create_squad(GameEnums.UnitType.RIFLE_PLATOON, pos, true)
		player_firebase.add_to_garrison(squad)

	# Deploy weapons squads
	for i in range(STARTING_FORCES.weapons_squads):
		var angle := PI + (PI / 4) * i  # Southwest positions
		var pos := LZ_CENTER + Vector3(cos(angle) * 20, 0, sin(angle) * 20)
		var squad := _create_squad(GameEnums.UnitType.WEAPONS_SQUAD, pos, true)
		player_firebase.add_to_garrison(squad)

	# Deploy engineers (center for flexibility)
	for i in range(STARTING_FORCES.engineers):
		var pos := LZ_CENTER + Vector3(5, 0, 0)
		var squad := _create_squad(GameEnums.UnitType.ENGINEERS, pos, true)
		player_firebase.add_to_garrison(squad)

	initial_garrison_count = player_firebase.get_garrison_strength()
	print("Garrison deployed: %d soldiers" % initial_garrison_count)

func _get_perimeter_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for i in range(8):
		var angle := (TAU / 8) * i
		var pos := LZ_CENTER + Vector3(cos(angle) * 25, 0, sin(angle) * 25)
		positions.append(pos)
	return positions

func _create_squad(unit_type: int, position: Vector3, is_player: bool) -> Squad:
	var squad := Squad.new()
	squad.faction = GameEnums.Faction.US_ARMY if is_player else GameEnums.Faction.NVA

	match unit_type:
		GameEnums.UnitType.RIFLE_PLATOON:
			squad.unit_data = VietnamUnitData.create_rifle_platoon()
		GameEnums.UnitType.WEAPONS_SQUAD:
			squad.unit_data = VietnamUnitData.create_weapons_squad()
		GameEnums.UnitType.ENGINEERS:
			squad.unit_data = VietnamUnitData.create_engineers()
		GameEnums.UnitType.NVA_INFANTRY:
			squad.unit_data = VietnamUnitData.create_nva_infantry()
		GameEnums.UnitType.NVA_HEAVY_WEAPONS:
			squad.unit_data = VietnamUnitData.create_nva_heavy_weapons()
		_:
			squad.unit_data = VietnamUnitData.create_rifle_platoon()

	squad.global_position = position

	var parent := player_units if is_player else enemy_units
	parent.add_child(squad)

	# Add visual
	var visual := CSGCylinder3D.new()
	visual.radius = 1.0
	visual.height = 2.0
	visual.position = Vector3(0, 1, 0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.4, 0.2) if is_player else Color(0.4, 0.35, 0.25)
	visual.material = mat
	squad.add_child(visual)

	return squad

# =============================================================================
# WAVE SYSTEM
# =============================================================================

func process(delta: float) -> void:
	if not is_started or is_complete or is_failed:
		return

	if current_wave >= MISSION_WAVES.size():
		# All waves complete!
		_check_victory()
		return

	if wave_active:
		enemies_remaining = enemy_units.get_child_count()
		if enemies_remaining == 0:
			_wave_defeated()
	else:
		wave_timer -= delta
		if wave_timer <= 0:
			_spawn_wave(current_wave)

	# Check failure conditions
	_check_failure()

func _spawn_wave(wave_index: int) -> void:
	var wave_data: Dictionary = MISSION_WAVES[wave_index]

	print("")
	print("=" .repeat(40))
	print("WAVE %d: %s" % [wave_index + 1, wave_data.name])
	print(wave_data.briefing)
	print("=" .repeat(40))

	var spawn_positions := _get_spawn_positions(wave_data.get("approach", "west"))

	# Spawn NVA Infantry
	var nva_count: int = wave_data.get("nva_infantry", 0)
	for i in range(nva_count):
		var pos: Vector3 = spawn_positions[i % spawn_positions.size()]
		pos += Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))
		_create_squad(GameEnums.UnitType.NVA_INFANTRY, pos, false)

	# Spawn NVA Heavy Weapons
	var heavy_count: int = wave_data.get("nva_heavy", 0)
	for i in range(heavy_count):
		var pos: Vector3 = spawn_positions[i % spawn_positions.size()]
		pos += Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		_create_squad(GameEnums.UnitType.NVA_HEAVY_WEAPONS, pos, false)

	# Spawn sappers if present
	var sapper_count: int = wave_data.get("nva_sappers", 0)
	for i in range(sapper_count):
		var pos: Vector3 = spawn_positions[i % spawn_positions.size()]
		pos += Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		# Sappers would use VC_SAPPERS or a dedicated NVA sapper type
		_create_squad(GameEnums.UnitType.VC_SAPPERS, pos, false)

	wave_active = true
	enemies_remaining = enemy_units.get_child_count()

	BattleSignals.wave_started.emit(wave_index + 1)
	print("Enemies deployed: %d" % enemies_remaining)

	# Wave 3 should trigger Broken Arrow check
	if wave_index == 2 and not broken_arrow_called:
		print("BROKEN ARROW AUTHORIZED - Call in all available air support!")

func _get_spawn_positions(direction: String) -> Array[Vector3]:
	var positions: Array[Vector3] = []

	match direction:
		"west":
			for i in range(4):
				positions.append(Vector3(20, 0, 100 + i * 40))
		"southwest":
			for i in range(4):
				positions.append(Vector3(20 + i * 20, 0, 20 + i * 20))
		"north":
			for i in range(4):
				positions.append(Vector3(100 + i * 40, 0, 280))
		"all":
			positions.append(Vector3(20, 0, 150))   # West
			positions.append(Vector3(150, 0, 280))  # North
			positions.append(Vector3(280, 0, 150))  # East
			positions.append(Vector3(150, 0, 20))   # South
		_:
			positions.append(Vector3(20, 0, 150))

	return positions

func _wave_defeated() -> void:
	wave_active = false
	current_wave += 1

	BattleSignals.wave_defeated.emit(current_wave)

	if current_wave >= MISSION_WAVES.size():
		print("All waves defeated!")
	else:
		wave_timer = MISSION_WAVES[current_wave].delay
		print("Wave %d defeated! Next wave in %.0f seconds." % [current_wave, wave_timer])

# =============================================================================
# OBJECTIVE TRACKING
# =============================================================================

func _complete_objective(objective_id: String) -> void:
	if objectives.has(objective_id) and not objectives[objective_id].complete:
		objectives[objective_id].complete = true
		print("OBJECTIVE COMPLETE: %s" % objectives[objective_id].description)
		objective_updated.emit(objective_id, "complete")
		BattleSignals.mission_objective_complete.emit(objective_id)

func _check_victory() -> void:
	if enemies_remaining > 0:
		return

	# Check combat effectiveness
	var current_strength := player_firebase.get_garrison_strength()
	var effectiveness := float(current_strength) / float(initial_garrison_count)

	if effectiveness >= 0.5:
		_complete_objective("maintain_strength")

	_complete_objective("survive_waves")

	is_complete = true
	print("")
	print("=" .repeat(60))
	print("MISSION COMPLETE: %s" % MISSION_NAME)
	print("Combat Effectiveness: %.0f%%" % (effectiveness * 100))
	if not broken_arrow_called:
		print("BONUS: No Broken Arrow called!")
	print("=" .repeat(60))

	mission_complete.emit("victory")
	BattleSignals.mission_complete.emit(MISSION_NAME, "victory")

func _check_failure() -> void:
	# Check if all garrison wiped
	var current_strength := player_firebase.get_garrison_strength()
	var effectiveness := float(current_strength) / float(initial_garrison_count)

	if effectiveness < 0.1:
		is_failed = true
		print("")
		print("=" .repeat(60))
		print("MISSION FAILED: LZ X-Ray overrun")
		print("=" .repeat(60))

		mission_failed.emit("LZ overrun")
		BattleSignals.mission_failed.emit(MISSION_NAME, "LZ overrun")

# =============================================================================
# PLAYER ACTIONS
# =============================================================================

func call_broken_arrow() -> void:
	## Call in danger close air support
	if broken_arrow_called:
		return

	broken_arrow_called = true
	print("BROKEN ARROW! BROKEN ARROW! All available aircraft to LZ X-Ray!")

	# Call in massive air support
	BattleSignals.airstrike_requested.emit(
		GameEnums.AirStrikeType.CLOSE_AIR_SUPPORT,
		LZ_CENTER + CHU_PONG_DIRECTION * 50
	)

	# Delay then call more
	await main_scene.get_tree().create_timer(10.0).timeout
	BattleSignals.airstrike_requested.emit(
		GameEnums.AirStrikeType.NAPALM_RUN,
		LZ_CENTER + CHU_PONG_DIRECTION * 80
	)

func request_medevac() -> void:
	## Request medevac for wounded
	if player_firebase.has_helipad() or true:  # Emergency medevac
		print("Medevac requested - Dustoff inbound!")
		BattleSignals.reinforcement_requested.emit(
			GameEnums.UnitType.RIFLE_PLATOON,  # Replacement troops
			player_firebase
		)

# =============================================================================
# STATUS
# =============================================================================

func get_status() -> Dictionary:
	return {
		"mission": MISSION_NAME,
		"wave": current_wave + 1,
		"total_waves": MISSION_WAVES.size(),
		"enemies_remaining": enemies_remaining,
		"garrison_strength": player_firebase.get_garrison_strength() if player_firebase else 0,
		"initial_strength": initial_garrison_count,
		"effectiveness": float(player_firebase.get_garrison_strength()) / float(initial_garrison_count) if player_firebase and initial_garrison_count > 0 else 0.0,
		"broken_arrow_called": broken_arrow_called,
		"objectives": objectives.duplicate(),
	}
