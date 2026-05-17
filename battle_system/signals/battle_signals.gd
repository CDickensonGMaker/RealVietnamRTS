extends Node
## Battle Signals - Central signal bus for Vietnam Firebase Defense
## Trimmed for MVP - add signals as systems are implemented per phase

# =============================================================================
# UNIT SIGNALS (Phase 2)
# =============================================================================
signal unit_spawned(unit: Node3D, faction: int)
signal unit_died(unit: Node3D, killer: Node3D)
signal unit_damaged(unit: Node3D, damage: float, source: Node3D)
signal unit_selected(unit: Node3D)
signal unit_deselected(unit: Node3D)

# =============================================================================
# COMBAT SIGNALS (Phase 2)
# =============================================================================
signal unit_attacked(attacker: Node3D, target: Node3D, weapon_id: String)
signal unit_suppressed(target: Node3D, amount: float, source: Node3D)
signal projectile_impact(position: Vector3, damage_type: int)
signal artillery_called(position: Vector3, weapon_id: String, rounds: int)
signal napalm_strike_called(start_pos: Vector3, end_pos: Vector3)
signal napalm_impact(position: Vector3, radius: float)

# =============================================================================
# FIREBASE SIGNALS (Phase 3)
# =============================================================================
signal firebase_established(firebase: Node3D)
signal firebase_under_attack(firebase: Node3D, attacker: Node3D)

# =============================================================================
# CONSTRUCTION SIGNALS (Phase 3)
# =============================================================================
signal construction_started(zone: Node3D, building_type: int)
signal construction_complete(building: Node3D)
signal terrain_cleared(position: Vector3, radius: float)

# =============================================================================
# SUPPLY SIGNALS (Phase 3)
# =============================================================================
signal convoy_departed(convoy: Node3D)
signal convoy_arrived(convoy: Node3D, destination: Node3D)
signal supply_delivered(destination: Node3D, amount: float)

# =============================================================================
# HELICOPTER SIGNALS (Phase 4)
# =============================================================================
signal helicopter_dispatched(helicopter: Node3D, mission_name: String)
signal helicopter_landed(helicopter: Node3D, lz: Node3D)
signal helicopter_destroyed(helicopter: Node3D)
signal request_medevac(position: Vector3, unit: Node3D)
signal request_extraction(lz: Node3D, unit_count: int)
signal insertion_complete(troops: Array, lz: Node3D)

# =============================================================================
# REINFORCEMENT SIGNALS (Phase 4)
# =============================================================================
signal reinforcement_requested(unit_type: int, destination: Node3D)
signal reinforcement_arrived(unit: Node3D, destination: Node3D)

# =============================================================================
# MISSION SIGNALS (Phase 5)
# =============================================================================
signal mission_started(mission_name: String)
signal objective_complete(objective_id: String)
signal mission_complete(victory: bool)

# =============================================================================
# AI SIGNALS (Phase 5)
# =============================================================================
signal wave_incoming(wave_number: int, enemy_count: int)
signal wave_defeated(wave_number: int)
signal enemy_spotted(enemy: Node3D, by_unit: Node3D)

# =============================================================================
# NVA SIEGE SIGNALS (Phase 6)
# =============================================================================
signal siege_started(target: Node3D)
signal siege_broken(target: Node3D, success: bool)
signal human_wave_launched(position: Vector3, count: int)
signal artillery_barrage_incoming(position: Vector3)
signal sapper_assault_detected(count: int)
signal aa_threat_detected(position: Vector3, range: float)
signal supply_line_cut(firebase: Node3D)
signal supply_line_restored(firebase: Node3D)

# =============================================================================
# VC GUERRILLA SIGNALS (Phase 6)
# =============================================================================
signal ambush_triggered(position: Vector3, attackers: int)
signal tunnel_attack_launched(position: Vector3, count: int)
signal trap_triggered(trap: Node3D, victim: Node3D)
signal trap_discovered(trap: Node3D)
signal civilian_ambush_sprung(village: Node3D, attackers: int)
signal vc_ambush_triggered(position: Vector3, target_count: int)

# =============================================================================
# VILLAGE SIGNALS (Phase 6)
# =============================================================================
signal village_allegiance_changed(village: Node3D, new_allegiance: int)
signal village_attacked(village: Node3D, attacker: Node3D)
signal civilian_casualty(village: Node3D, killer: Node3D)
signal hearts_and_minds_update(pro_us: int, pro_vc: int, neutral: int)

# =============================================================================
# SOG SIGNALS (Phase 6)
# =============================================================================
signal sog_team_inserted(team: Node3D, position: Vector3)
signal sog_team_compromised(team: Node3D)
signal sog_extraction_requested(team: Node3D, position: Vector3)
signal sog_mission_complete(team: Node3D, success: bool)

# =============================================================================
# PROJECTILE SIGNALS
# =============================================================================
signal projectile_fired(from: Vector3, to: Vector3)

# =============================================================================
# UI SIGNALS
# =============================================================================
signal selection_changed(selected_units: Array)

func _ready() -> void:
	print("[BattleSignals] Signal bus initialized")
