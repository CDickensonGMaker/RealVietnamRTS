# ADR-0013: AI Director System

## Status
Proposed

## Context

RealVietnamRTS uses a Left 4 Dead-style AI Director to create dynamic, responsive enemy encounters. The Director monitors player state and adjusts attack frequency, intensity, and type to maintain tension without overwhelming or boring the player.

### Requirements to Address
| TR-ID | Requirement |
|-------|-------------|
| TR-COR-040 | AI Director monitors: firebase integrity, supply status, casualty rate, defensive coverage, player idle time |
| TR-COR-041 | AI Director outputs: attack frequency (5-15 min), intensity (1-4 squads), direction (weak points), type |
| TR-COR-042 | AI escalation: Early (0-15min) 1-2 squads, Mid (15-35min) 2-3 squads+mortars, Late (35+min) 3-4 squads+sappers |
| TR-COR-043 | VC tactics: night attack, sapper raid, mortar harassment, human wave, convoy ambush |

## Decision

### AI Director Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AIDirector                                   │
│                      (Autoload Singleton)                            │
├─────────────────────────────────────────────────────────────────────┤
│  State Monitors:                                                     │
│    - _firebase_monitor: FirebaseMonitor                             │
│    - _supply_monitor: SupplyMonitor                                 │
│    - _combat_monitor: CombatMonitor                                 │
│    - _coverage_monitor: CoverageMonitor                             │
│    - _idle_monitor: IdleMonitor                                     │
├─────────────────────────────────────────────────────────────────────┤
│  Decision Engine:                                                    │
│    + calculate_threat_level() -> float                              │
│    + select_attack_type() -> AttackType                             │
│    + select_attack_direction() -> Vector3                           │
│    + determine_attack_intensity() -> int                            │
│    + schedule_next_attack() -> void                                 │
├─────────────────────────────────────────────────────────────────────┤
│  Attack Spawner:                                                     │
│    + spawn_attack(config: AttackConfig) -> void                     │
│    + get_spawn_points(direction: Vector3) -> Array[Vector3]         │
└─────────────────────────────────────────────────────────────────────┘
```

### Director Inputs (TR-COR-040)

```gdscript
class_name AIDirector extends Node

## Monitoring intervals
const MONITOR_INTERVAL := 5.0  # Seconds between state updates
const ATTACK_CHECK_INTERVAL := 30.0  # Seconds between attack scheduling checks

## Current state values (0.0 - 1.0 normalized)
var _firebase_integrity: float = 1.0    # Health of player firebases
var _supply_status: float = 1.0         # Supply chain health
var _casualty_rate: float = 0.0         # Recent player losses
var _defensive_coverage: float = 1.0    # Defensive structure coverage
var _player_idle_time: float = 0.0      # Seconds since last player action

## Derived threat level
var _threat_level: float = 0.5          # 0.0 = player struggling, 1.0 = player dominant

func _monitor_state() -> void:
    """Update all monitoring values (TR-COR-040)"""
    _firebase_integrity = _calculate_firebase_integrity()
    _supply_status = _calculate_supply_status()
    _casualty_rate = _calculate_casualty_rate()
    _defensive_coverage = _calculate_defensive_coverage()
    _player_idle_time = _calculate_idle_time()

    _threat_level = _calculate_threat_level()

func _calculate_firebase_integrity() -> float:
    """Monitor firebase health and damage state"""
    var firebases := FirebaseSystem.get_player_firebases()
    if firebases.is_empty():
        return 0.0

    var total_health := 0.0
    var max_health := 0.0

    for fb in firebases:
        total_health += fb.get_total_health()
        max_health += fb.get_max_health()

    return total_health / max_health if max_health > 0 else 0.0

func _calculate_supply_status() -> float:
    """Monitor supply chain health"""
    var depots := SupplyChainManager.get_all_depots()
    if depots.is_empty():
        return 0.0

    var total_supply := 0.0
    var max_supply := 0.0

    for depot in depots:
        total_supply += depot.current_supply
        max_supply += depot.max_supply

    # Also factor in road network integrity
    var road_health := RoadNetwork.get_network_integrity()

    return (total_supply / max_supply * 0.7 + road_health * 0.3) if max_supply > 0 else 0.0

func _calculate_casualty_rate() -> float:
    """Calculate recent player casualty rate"""
    var recent_losses := CombatManager.get_player_losses_last_5_minutes()
    var total_forces := CombatManager.get_player_total_forces()

    # Normalize: 50% losses in 5 min = 1.0
    var loss_ratio := recent_losses / (total_forces * 0.5) if total_forces > 0 else 0.0
    return clampf(loss_ratio, 0.0, 1.0)

func _calculate_defensive_coverage() -> float:
    """Calculate how well defended the firebases are"""
    var firebases := FirebaseSystem.get_player_firebases()
    if firebases.is_empty():
        return 0.0

    var total_coverage := 0.0

    for fb in firebases:
        # Check defensive structure presence
        var has_bunkers := fb.count_buildings_of_type("bunker") > 0
        var has_mg_nests := fb.count_buildings_of_type("mg_nest") > 0
        var has_wire := fb.count_buildings_of_type("wire") > 0
        var has_watchtower := fb.count_buildings_of_type("watchtower") > 0

        # Calculate coverage score
        var coverage := 0.0
        if has_bunkers: coverage += 0.3
        if has_mg_nests: coverage += 0.3
        if has_wire: coverage += 0.2
        if has_watchtower: coverage += 0.2

        total_coverage += coverage

    return total_coverage / firebases.size()

func _calculate_idle_time() -> float:
    """Calculate how long since player issued commands"""
    return InputTracker.get_seconds_since_last_command()

func _calculate_threat_level() -> float:
    """
    Calculate overall threat level (how much pressure to apply).
    High value = player is doing well, apply more pressure
    Low value = player is struggling, ease up
    """
    # Weighted combination of factors
    var threat := 0.0

    # Player doing well indicators (increase threat)
    threat += _firebase_integrity * 0.25       # Healthy bases = more attacks
    threat += _supply_status * 0.20            # Good supply = more attacks
    threat += _defensive_coverage * 0.20       # Good defenses = harder attacks
    threat += (1.0 - _casualty_rate) * 0.20    # Low casualties = more attacks

    # Player idle = poke them
    if _player_idle_time > 60.0:
        threat += 0.15

    return clampf(threat, 0.0, 1.0)
```

### Director Outputs (TR-COR-041)

```gdscript
## Attack frequency bounds (TR-COR-041)
const MIN_ATTACK_INTERVAL := 300.0   # 5 minutes minimum
const MAX_ATTACK_INTERVAL := 900.0   # 15 minutes maximum

## Attack intensity bounds (TR-COR-041)
const MIN_SQUADS := 1
const MAX_SQUADS := 4

enum AttackType {
    PROBE,              # Light reconnaissance
    ASSAULT,            # Standard attack
    MORTAR_HARASSMENT,  # Indirect fire only
    SAPPER_RAID,        # Infiltration and sabotage
    HUMAN_WAVE,         # Mass assault
    CONVOY_AMBUSH,      # Attack supply line
    NIGHT_ATTACK,       # Stealth assault
}

func schedule_next_attack() -> void:
    """Schedule the next enemy attack based on current state"""
    var interval := _calculate_attack_interval()
    var timer := get_tree().create_timer(interval)
    timer.timeout.connect(_execute_scheduled_attack)

func _calculate_attack_interval() -> float:
    """Calculate time until next attack (TR-COR-041: 5-15 minutes)"""
    # Higher threat level = more frequent attacks
    var t := _threat_level
    var interval := lerpf(MAX_ATTACK_INTERVAL, MIN_ATTACK_INTERVAL, t)

    # Add randomness (+-20%)
    interval *= randf_range(0.8, 1.2)

    return interval

func determine_attack_intensity() -> int:
    """Determine number of squads for attack (TR-COR-041: 1-4 squads)"""
    var mission_time := MissionManager.get_elapsed_minutes()
    var base_intensity: int

    # TR-COR-042: Escalation over time
    if mission_time < 15:
        base_intensity = randi_range(1, 2)  # Early: 1-2 squads
    elif mission_time < 35:
        base_intensity = randi_range(2, 3)  # Mid: 2-3 squads
    else:
        base_intensity = randi_range(3, 4)  # Late: 3-4 squads

    # Modify by threat level
    if _threat_level > 0.8:
        base_intensity += 1
    elif _threat_level < 0.3:
        base_intensity -= 1

    return clampi(base_intensity, MIN_SQUADS, MAX_SQUADS)

func select_attack_direction() -> Vector3:
    """Select attack direction targeting weak points (TR-COR-041)"""
    var firebases := FirebaseSystem.get_player_firebases()
    if firebases.is_empty():
        return Vector3.FORWARD

    # Find weakest firebase
    var weakest_fb: Node3D = null
    var weakest_score := INF

    for fb in firebases:
        var score := _calculate_defense_score(fb)
        if score < weakest_score:
            weakest_score = score
            weakest_fb = fb

    # Find weakest direction around that firebase
    var weak_direction := _find_weakest_approach(weakest_fb)

    return weak_direction

func _find_weakest_approach(firebase: Node3D) -> Vector3:
    """Find the direction with least defensive coverage"""
    var directions := [
        Vector3.FORWARD, Vector3.BACK,
        Vector3.LEFT, Vector3.RIGHT,
        Vector3(1, 0, 1).normalized(),
        Vector3(1, 0, -1).normalized(),
        Vector3(-1, 0, 1).normalized(),
        Vector3(-1, 0, -1).normalized(),
    ]

    var best_direction := Vector3.FORWARD
    var lowest_defense := INF

    for dir in directions:
        var check_pos := firebase.global_position + dir * 100.0
        var defense_value := _get_defense_at_direction(firebase, dir)

        if defense_value < lowest_defense:
            lowest_defense = defense_value
            best_direction = dir

    return best_direction

func _get_defense_at_direction(firebase: Node3D, direction: Vector3) -> float:
    """Calculate defensive strength in a direction"""
    var defense := 0.0
    var check_positions := []

    # Sample points in this direction
    for dist in [30.0, 60.0, 90.0]:
        check_positions.append(firebase.global_position + direction * dist)

    for pos in check_positions:
        # Check for defensive structures
        var structures := SpatialHashGrid.get_structures_in_radius(pos, 20.0)
        for s in structures:
            if s.is_defensive:
                defense += s.defense_value

        # Check for units
        var units := SpatialHashGrid.get_friendlies_in_radius(
            pos, 30.0, GameEnums.Faction.US_ARMY
        )
        defense += units.size() * 10.0

    return defense
```

### Attack Types (TR-COR-043)

```gdscript
func select_attack_type() -> AttackType:
    """Select attack type based on situation (TR-COR-043)"""
    var mission_time := MissionManager.get_elapsed_minutes()
    var is_night := TimeOfDayManager.is_night()

    # Build weighted options
    var options: Array[Dictionary] = []

    # Always available
    options.append({"type": AttackType.PROBE, "weight": 20})
    options.append({"type": AttackType.ASSAULT, "weight": 30})

    # Mortar harassment (TR-COR-043)
    if mission_time > 10:
        options.append({"type": AttackType.MORTAR_HARASSMENT, "weight": 25})

    # Sapper raid (TR-COR-043) - more likely late game
    if mission_time > 20:
        var sapper_weight := 15 + int(mission_time / 10)
        options.append({"type": AttackType.SAPPER_RAID, "weight": sapper_weight})

    # Human wave (TR-COR-043) - only when player is doing well
    if mission_time > 25 and _threat_level > 0.7:
        options.append({"type": AttackType.HUMAN_WAVE, "weight": 15})

    # Convoy ambush (TR-COR-043) - only if convoys active
    if SupplyChainManager.has_active_convoys():
        options.append({"type": AttackType.CONVOY_AMBUSH, "weight": 20})

    # Night attack (TR-COR-043) - only at night
    if is_night:
        options.append({"type": AttackType.NIGHT_ATTACK, "weight": 35})

    return _weighted_random_select(options)

func _weighted_random_select(options: Array[Dictionary]) -> AttackType:
    """Select from weighted options"""
    var total_weight := 0
    for opt in options:
        total_weight += opt.weight

    var roll := randi() % total_weight
    var cumulative := 0

    for opt in options:
        cumulative += opt.weight
        if roll < cumulative:
            return opt.type

    return AttackType.ASSAULT  # Fallback
```

### Attack Execution

```gdscript
class AttackConfig:
    var attack_type: AttackType
    var intensity: int  # Number of squads
    var direction: Vector3
    var target_firebase: Node3D
    var spawn_points: Array[Vector3]
    var unit_composition: Array[String]

func _execute_scheduled_attack() -> void:
    """Execute a scheduled attack"""
    var config := AttackConfig.new()
    config.attack_type = select_attack_type()
    config.intensity = determine_attack_intensity()
    config.direction = select_attack_direction()
    config.target_firebase = _get_target_firebase()
    config.spawn_points = _get_spawn_points(config.direction, config.target_firebase)
    config.unit_composition = _get_unit_composition(config.attack_type, config.intensity)

    spawn_attack(config)

    # Schedule next attack
    schedule_next_attack()

    BattleSignals.ai_attack_started.emit(config)

func spawn_attack(config: AttackConfig) -> void:
    """Spawn enemy units for attack"""
    match config.attack_type:
        AttackType.PROBE:
            _spawn_probe(config)
        AttackType.ASSAULT:
            _spawn_assault(config)
        AttackType.MORTAR_HARASSMENT:
            _spawn_mortar_team(config)
        AttackType.SAPPER_RAID:
            _spawn_sappers(config)
        AttackType.HUMAN_WAVE:
            _spawn_human_wave(config)
        AttackType.CONVOY_AMBUSH:
            _spawn_convoy_ambush(config)
        AttackType.NIGHT_ATTACK:
            _spawn_night_attack(config)

func _spawn_assault(config: AttackConfig) -> void:
    """Standard assault with infantry squads"""
    for i in config.intensity:
        var spawn_pos := config.spawn_points[i % config.spawn_points.size()]
        var squad := _instantiate_vc_squad("vc_infantry")
        squad.global_position = spawn_pos
        squad.set_attack_target(config.target_firebase)

        # Add to scene
        get_tree().current_scene.add_child(squad)

func _spawn_mortar_team(config: AttackConfig) -> void:
    """Mortar harassment - indirect fire from distance"""
    var mortar_pos := config.spawn_points[0] + Vector3(0, 0, 50)  # Further back
    var mortar := _instantiate_vc_squad("vc_mortar")
    mortar.global_position = mortar_pos
    mortar.set_indirect_fire_target(config.target_firebase.global_position)

    get_tree().current_scene.add_child(mortar)

    # Add security element
    var security := _instantiate_vc_squad("vc_infantry")
    security.global_position = mortar_pos + Vector3(10, 0, 0)
    security.set_guard_target(mortar)
    get_tree().current_scene.add_child(security)

func _spawn_sappers(config: AttackConfig) -> void:
    """Sapper raid - infiltration and sabotage"""
    var sapper_squad := _instantiate_vc_squad("vc_sapper")
    sapper_squad.global_position = config.spawn_points[0]
    sapper_squad.set_infiltration_target(config.target_firebase)
    sapper_squad.enable_stealth_mode()

    get_tree().current_scene.add_child(sapper_squad)
```

### Escalation System (TR-COR-042)

```gdscript
enum MissionPhase {
    EARLY,   # 0-15 minutes
    MID,     # 15-35 minutes
    LATE,    # 35+ minutes
}

func get_current_phase() -> MissionPhase:
    var minutes := MissionManager.get_elapsed_minutes()
    if minutes < 15:
        return MissionPhase.EARLY
    elif minutes < 35:
        return MissionPhase.MID
    else:
        return MissionPhase.LATE

func _get_unit_composition(attack_type: AttackType, intensity: int) -> Array[String]:
    """Get unit types based on phase and attack type (TR-COR-042)"""
    var phase := get_current_phase()
    var units: Array[String] = []

    match phase:
        MissionPhase.EARLY:
            # 1-2 squads, basic infantry only
            for i in intensity:
                units.append("vc_infantry")

        MissionPhase.MID:
            # 2-3 squads + mortars
            for i in intensity - 1:
                units.append("vc_infantry")
            units.append("vc_mortar")

        MissionPhase.LATE:
            # 3-4 squads + sappers
            for i in intensity - 1:
                units.append("vc_infantry")
            if attack_type == AttackType.SAPPER_RAID:
                units.append("vc_sapper")
            else:
                units.append("vc_lmg")  # LMG support

    return units
```

## Consequences

### Positive
- **Dynamic pacing**: Attacks respond to player state
- **Fair difficulty**: Eases up when player struggles
- **Varied tactics**: Multiple attack types prevent monotony
- **Escalation**: Difficulty ramps over mission time
- **Weak point targeting**: Creates tactical decisions

### Negative
- **Tuning complexity**: Many parameters to balance
- **Predictability risk**: Players may learn patterns
- **State tracking overhead**: Multiple monitors running

### Mitigations
- Expose tuning constants for iteration
- Add randomness to intervals and types
- Cache expensive calculations
- Log attack decisions for debugging

## ADR Dependencies

- **ADR-0003 (Spatial Hash Grid)**: Defensive coverage queries
- **ADR-0006 (Supply Chain)**: Convoy ambush targeting
- **ADR-0009 (Firebase)**: Firebase health monitoring
- **ADR-0010 (Combat)**: Casualty tracking

## Engine Compatibility

**Godot 4.6** - Uses Timers, signals, standard GDScript patterns.

## GDD Requirements Addressed

| Requirement | How Addressed |
|-------------|---------------|
| TR-COR-040 | `_monitor_state()` with firebase, supply, casualty, coverage, idle tracking |
| TR-COR-041 | `schedule_next_attack()` (5-15 min), `determine_attack_intensity()` (1-4), `select_attack_direction()` |
| TR-COR-042 | `MissionPhase` enum with EARLY/MID/LATE escalation in `_get_unit_composition()` |
| TR-COR-043 | `AttackType` enum with night_attack, sapper_raid, mortar_harassment, human_wave, convoy_ambush |

## Implementation Files

| File | Purpose |
|------|---------|
| `battle_system/ai/ai_director.gd` | AIDirector autoload |
| `battle_system/ai/attack_config.gd` | AttackConfig data class |
| `battle_system/ai/vc_spawner.gd` | Enemy unit spawning |

## Key Signals

```gdscript
signal ai_attack_started(config: AttackConfig)
signal ai_attack_ended(config: AttackConfig, result: int)
signal ai_phase_changed(old_phase: int, new_phase: int)
signal ai_threat_level_changed(new_level: float)
```

## Validation Criteria

- [ ] Attacks occur every 5-15 minutes
- [ ] Attack intensity scales from 1-2 (early) to 3-4 (late)
- [ ] Mortar harassment available after 10 minutes
- [ ] Sappers appear after 20 minutes
- [ ] Attacks target weakest firebase direction
- [ ] Convoy ambushes only when convoys exist
- [ ] Night attacks only during night
- [ ] Threat level adjusts attack frequency
