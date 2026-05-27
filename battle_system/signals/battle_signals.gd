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
# MORALE SIGNALS (Phase 3)
# =============================================================================
signal unit_routing(unit: Node3D)
signal unit_rallied(unit: Node3D)
signal unit_morale_broken(unit: Node3D, morale_state: String)
signal nearby_squad_destroyed(position: Vector3, faction: int)

# =============================================================================
# COMBAT SIGNALS (Phase 2)
# =============================================================================
signal unit_attacked(attacker: Node3D, target: Node3D, weapon_id: String)
signal melee_attack(attacker: Node3D, target: Node3D, damage: float)  ## Close combat bayonet/hand-to-hand
signal unit_suppressed(target: Node3D, amount: float, source: Node3D)
signal unit_ammo_depleted(unit: Node3D)  ## Emitted when unit runs out of ammo and cannot fire
signal projectile_impact(position: Vector3, damage_type: int)
signal artillery_called(position: Vector3, weapon_id: String, rounds: int)
signal napalm_strike_called(start_pos: Vector3, end_pos: Vector3)
signal napalm_impact(position: Vector3, radius: float)
signal bomb_dropped(start_pos: Vector3, target_pos: Vector3, plane_velocity: Vector3)

# =============================================================================
# FIREBASE SIGNALS (Phase 3-4)
# =============================================================================
signal firebase_established(firebase: Node3D)
signal firebase_activated(firebase: Node3D)  ## HQ building completed, firebase now provides supply/morale
signal firebase_deactivated(firebase: Node3D)  ## HQ building destroyed, firebase offline
signal firebase_under_attack(firebase: Node3D, attacker: Node3D)

# =============================================================================
# CONSTRUCTION SIGNALS (Phase 3)
# =============================================================================
signal construction_started(zone: Node3D, building_type: int)
signal construction_complete(building: Node3D)
signal terrain_cleared(position: Vector3, radius: float)
signal building_selected(building: Node3D)
signal building_destroyed(zone: Node3D, building_type: int)

# =============================================================================
# SUPPLY SIGNALS (Phase 3)
# =============================================================================
signal convoy_departed(convoy: Node3D)
signal convoy_arrived(convoy: Node3D, destination: Node3D)
signal supply_delivered(destination: Node3D, amount: float)
signal supply_consumed(firebase: Node3D, amount: float, reason: String)  ## Emitted when supply is spent (construction, resupply units)
signal supply_refunded(amount: float, reason: String)  ## Emitted when construction is cancelled and supply returned

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
signal construction_site_clicked(site: Node3D, building_type: int, progress: float)

# =============================================================================
# VEHICLE COMPONENT SIGNALS (Phase 15 - Men of War style)
# =============================================================================
signal vehicle_component_damaged(vehicle: Node3D, component_type: int, current_hp: float)
signal vehicle_component_destroyed(vehicle: Node3D, component_type: int)
signal vehicle_crew_killed(vehicle: Node3D, position: int)
signal vehicle_ammo_explosion(vehicle: Node3D, position: Vector3)

# =============================================================================
# SUPPLY TRUCK SIGNALS (Phase 4)
# =============================================================================
signal supply_truck_departed(truck: Node3D, depot: Node3D, firebase: Node3D)
signal supply_truck_arrived(truck: Node3D, firebase: Node3D, supply_amount: float)
signal supply_truck_ambushed(truck: Node3D, position: Vector3)

# =============================================================================
# GUNSHIP SIGNALS (Phase 5)
# =============================================================================
signal gunship_attack_run(gunship: Node3D, target: Node3D)
signal gunship_winchester(gunship: Node3D)  # Out of ammo
signal gunship_rtb(gunship: Node3D, reason: String)

# =============================================================================
# MEDEVAC SIGNALS (Phase 6)
# =============================================================================
signal medevac_dispatched(medevac: Node3D, pickup_pos: Vector3)
signal medevac_patient_loaded(medevac: Node3D, patient: Node3D)
signal medevac_patient_delivered(medevac: Node3D, patient: Node3D, hospital: Node3D)

# =============================================================================
# REPUTATION SIGNALS (Phase 8)
# =============================================================================
signal reputation_changed(total: float, delta: float, reason: String)
signal war_crime_committed(incident_type: int, position: Vector3)
signal medal_awarded(medal_name: String)

# =============================================================================
# TUNNEL SIGNALS (Phase 9-10)
# =============================================================================
signal tunnel_discovered(entrance: Node3D, discoverer: Node3D)
signal tunnel_collapsed(segment: Node3D)
signal tunnel_rat_entered(tunnel_rat: Node3D, entrance: Node3D)
signal tunnel_segment_cleared(tunnel_rat: Node3D, segment: Node3D)
signal tunnel_intel_gathered(tunnel_rat: Node3D, intel_type: String)

# =============================================================================
# ROUTE PLANNING SIGNALS (Phase 14)
# =============================================================================
signal route_calculated(route_id: int, start: Vector3, end: Vector3, path: PackedVector3Array)
signal route_blocked(route_id: int, blocked_position: Vector3)
signal threat_detected(position: Vector3, threat_level: int)
signal threat_cleared(position: Vector3)

func _ready() -> void:
	print("[BattleSignals] Signal bus initialized")
