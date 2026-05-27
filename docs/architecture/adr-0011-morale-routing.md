# ADR-0011: Morale and Routing System

## Status
Proposed

## Context

RealVietnamRTS uses morale as a core combat mechanic to create realistic squad behavior. Units under pressure break and flee, creating emergent gameplay where firebase placement and supply lines directly impact combat effectiveness. The morale system draws inspiration from Total War routing mechanics.

### Requirements to Address
| TR-ID | Requirement |
|-------|-------------|
| TR-COR-010 | Four morale states: STEADY (70-100), WAVERING (40-70), SHAKEN (20-40), BROKEN (0-20) |
| TR-COR-011 | Continuous modifiers: under fire -0.3/sec, surrounded -1.25/sec, dehydrated -0.5/sec |
| TR-COR-012 | Positive modifiers: near firebase +1.0/sec, near allies +0.5/sec, winning +0.6/sec |
| TR-COR-013 | One-time events: ally killed -3, squad leader killed -15, flanked -8, reinforcements +10 |
| TR-COR-014 | BROKEN units (50%+ soldiers broken) attempt return to nearest firebase |
| TR-COR-015 | SHATTERED units (80%+ broken) go rogue - ignore orders, survival mode |
| TR-COR-016 | Routed units can recover after 5+ seconds without contact in safe area |
| TR-COR-017 | SHATTERED squads cannot rally - combat-ineffective until medevac |

## Decision

### Morale Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                       MoraleSystem                                   │
│                    (Autoload Singleton)                              │
├─────────────────────────────────────────────────────────────────────┤
│  + update_morale(unit: Node3D, delta: float) -> void                │
│  + apply_morale_event(unit: Node3D, event: MoraleEvent) -> void     │
│  + get_morale_state(morale: float) -> MoraleState                   │
│  + check_routing(unit: Node3D) -> bool                              │
├─────────────────────────────────────────────────────────────────────┤
│  Uses: SpatialHashGrid (nearby units)                               │
│        FirebaseSystem (safe zone detection)                         │
│        BattleSignals (events)                                       │
│        NavigationServer3D (flee pathfinding)                        │
└─────────────────────────────────────────────────────────────────────┘
```

### Morale States (TR-COR-010)

```gdscript
enum MoraleState {
    STEADY,     # 70-100: Full effectiveness, normal behavior
    WAVERING,   # 40-70: Accuracy -15%, may seek cover automatically
    SHAKEN,     # 20-40: Accuracy -30%, movement -25%, may refuse risky orders
    BROKEN,     # 0-20: Routing to firebase, minimal combat effectiveness
}

const MORALE_THRESHOLDS := {
    MoraleState.STEADY: 70.0,
    MoraleState.WAVERING: 40.0,
    MoraleState.SHAKEN: 20.0,
    MoraleState.BROKEN: 0.0,
}

func get_morale_state(morale: float) -> MoraleState:
    if morale >= MORALE_THRESHOLDS[MoraleState.STEADY]:
        return MoraleState.STEADY
    elif morale >= MORALE_THRESHOLDS[MoraleState.WAVERING]:
        return MoraleState.WAVERING
    elif morale >= MORALE_THRESHOLDS[MoraleState.SHAKEN]:
        return MoraleState.SHAKEN
    else:
        return MoraleState.BROKEN
```

### Continuous Morale Modifiers (TR-COR-011, TR-COR-012)

```gdscript
## Negative modifiers (applied per second)
const MODIFIER_UNDER_FIRE := -0.3         # TR-COR-011
const MODIFIER_SURROUNDED := -1.25        # TR-COR-011 (3+ enemy squads in 50m)
const MODIFIER_DEHYDRATED := -0.5         # TR-COR-011 (water resource empty)
const MODIFIER_LOW_AMMO := -0.2           # Low ammo stress
const MODIFIER_CASUALTIES_RECENT := -0.4  # Lost soldier in last 10 seconds
const MODIFIER_OUTNUMBERED := -0.3        # Enemy > 2x friendlies nearby

## Positive modifiers (applied per second)
const MODIFIER_NEAR_FIREBASE := 1.0       # TR-COR-012 (within influence radius)
const MODIFIER_NEAR_ALLIES := 0.5         # TR-COR-012 (2+ friendly squads in 30m)
const MODIFIER_WINNING := 0.6             # TR-COR-012 (enemy casualties > friendly)
const MODIFIER_IN_COVER := 0.3            # In HEAVY cover
const MODIFIER_FULL_STRENGTH := 0.2       # No casualties
const MODIFIER_GOOD_SUPPLY := 0.1         # Full ammo and water

func calculate_morale_delta(unit: Node3D, delta: float) -> float:
    var morale_change := 0.0

    # Negative modifiers
    if _is_under_fire(unit):
        morale_change += MODIFIER_UNDER_FIRE
    if _is_surrounded(unit):
        morale_change += MODIFIER_SURROUNDED
    if unit.is_dehydrated():
        morale_change += MODIFIER_DEHYDRATED
    if unit.is_low_ammo():
        morale_change += MODIFIER_LOW_AMMO
    if _had_recent_casualty(unit):
        morale_change += MODIFIER_CASUALTIES_RECENT
    if _is_outnumbered(unit):
        morale_change += MODIFIER_OUTNUMBERED

    # Positive modifiers
    if _is_near_firebase(unit):
        morale_change += MODIFIER_NEAR_FIREBASE
    if _has_nearby_allies(unit):
        morale_change += MODIFIER_NEAR_ALLIES
    if _is_winning_locally(unit):
        morale_change += MODIFIER_WINNING
    if _is_in_heavy_cover(unit):
        morale_change += MODIFIER_IN_COVER
    if unit.is_full_strength():
        morale_change += MODIFIER_FULL_STRENGTH
    if unit.has_good_supply():
        morale_change += MODIFIER_GOOD_SUPPLY

    return morale_change * delta

func _is_surrounded(unit: Node3D) -> bool:
    var enemies := SpatialHashGrid.get_enemies_in_radius(
        unit.global_position, 50.0, unit.faction
    )
    # Check if enemies are in multiple directions
    if enemies.size() < 3:
        return false
    var angles: Array[float] = []
    for enemy in enemies:
        angles.append(atan2(
            enemy.global_position.x - unit.global_position.x,
            enemy.global_position.z - unit.global_position.z
        ))
    angles.sort()
    # Surrounded if enemies span 180+ degrees
    var max_gap := 0.0
    for i in range(angles.size()):
        var gap := angles[(i + 1) % angles.size()] - angles[i]
        if i == angles.size() - 1:
            gap += TAU
        max_gap = maxf(max_gap, gap)
    return max_gap < PI  # Less than 180 degree gap = surrounded
```

### One-Time Morale Events (TR-COR-013)

```gdscript
enum MoraleEvent {
    ALLY_KILLED,          # -3
    SQUAD_LEADER_KILLED,  # -15
    FLANKED,              # -8
    AMBUSHED,             # -10
    FRIENDLY_FIRE,        # -5
    REINFORCEMENTS,       # +10
    OBJECTIVE_CAPTURED,   # +15
    ENEMY_ROUTED,         # +8
    AIR_SUPPORT_ARRIVED,  # +12
    RESUPPLIED,           # +5
}

const MORALE_EVENT_VALUES := {
    MoraleEvent.ALLY_KILLED: -3.0,
    MoraleEvent.SQUAD_LEADER_KILLED: -15.0,
    MoraleEvent.FLANKED: -8.0,
    MoraleEvent.AMBUSHED: -10.0,
    MoraleEvent.FRIENDLY_FIRE: -5.0,
    MoraleEvent.REINFORCEMENTS: 10.0,
    MoraleEvent.OBJECTIVE_CAPTURED: 15.0,
    MoraleEvent.ENEMY_ROUTED: 8.0,
    MoraleEvent.AIR_SUPPORT_ARRIVED: 12.0,
    MoraleEvent.RESUPPLIED: 5.0,
}

func apply_morale_event(unit: Node3D, event: MoraleEvent) -> void:
    var change := MORALE_EVENT_VALUES[event]
    unit.morale = clampf(unit.morale + change, 0.0, 100.0)

    var old_state := unit.morale_state
    var new_state := get_morale_state(unit.morale)

    if new_state != old_state:
        unit.morale_state = new_state
        BattleSignals.morale_state_changed.emit(unit, old_state, new_state)
        _handle_state_transition(unit, old_state, new_state)

    BattleSignals.morale_event.emit(unit, event, change)
```

### Routing Behavior (TR-COR-014, TR-COR-015)

```gdscript
## Routing thresholds
const BROKEN_THRESHOLD := 0.5   # 50% of soldiers at BROKEN morale
const SHATTERED_THRESHOLD := 0.8  # 80% of soldiers at BROKEN morale

enum RoutingState {
    NONE,       # Normal operation
    ROUTING,    # Fleeing to firebase (TR-COR-014)
    SHATTERED,  # Ignore orders, survival mode (TR-COR-015)
}

func check_routing(unit: Node3D) -> RoutingState:
    if unit.morale_state != MoraleState.BROKEN:
        return RoutingState.NONE

    var broken_ratio := _get_broken_soldier_ratio(unit)

    if broken_ratio >= SHATTERED_THRESHOLD:
        return RoutingState.SHATTERED  # TR-COR-015
    elif broken_ratio >= BROKEN_THRESHOLD:
        return RoutingState.ROUTING    # TR-COR-014
    else:
        return RoutingState.NONE

func _get_broken_soldier_ratio(unit: Node3D) -> float:
    # Track individual soldier morale (simplified: use squad morale as proxy)
    # In full implementation, each soldier would have individual morale
    if unit.morale <= 20.0:  # BROKEN threshold
        return 1.0 - (unit.morale / 20.0)  # 0 morale = 100% broken
    return 0.0

func _handle_routing(unit: Node3D, routing_state: RoutingState) -> void:
    match routing_state:
        RoutingState.ROUTING:
            # Find nearest firebase and flee (TR-COR-014)
            var firebase := FirebaseSystem.get_nearest_firebase(
                unit.global_position, unit.faction
            )
            if firebase:
                unit.flee_to(firebase.global_position)
                BattleSignals.squad_routing.emit(unit, firebase)
            else:
                # No firebase - flee toward map edge
                unit.flee_to(_get_retreat_direction(unit))

        RoutingState.SHATTERED:
            # Ignore all orders, survival mode (TR-COR-015)
            unit.clear_orders()
            unit.set_ai_mode(AIMode.SURVIVAL)
            unit.can_receive_orders = false
            BattleSignals.squad_shattered.emit(unit)
```

### Rally Recovery (TR-COR-016, TR-COR-017)

```gdscript
const RALLY_TIME_REQUIRED := 5.0  # Seconds without contact (TR-COR-016)
const RALLY_SAFE_DISTANCE := 100.0  # Must be this far from enemies
const RALLY_FIREBASE_BONUS := 2.0  # Rally twice as fast near firebase

func process_rally(unit: Node3D, delta: float) -> void:
    if unit.routing_state == RoutingState.SHATTERED:
        # SHATTERED cannot rally (TR-COR-017)
        return

    if unit.routing_state != RoutingState.ROUTING:
        return

    # Check safe conditions
    var enemies_nearby := SpatialHashGrid.get_enemies_in_radius(
        unit.global_position, RALLY_SAFE_DISTANCE, unit.faction
    )

    if enemies_nearby.size() > 0:
        # Not safe, reset rally timer
        unit._rally_timer = 0.0
        return

    # Accumulate rally time
    var rally_rate := 1.0
    if _is_near_firebase(unit):
        rally_rate = RALLY_FIREBASE_BONUS

    unit._rally_timer += delta * rally_rate

    if unit._rally_timer >= RALLY_TIME_REQUIRED:
        # Rally successful (TR-COR-016)
        _rally_unit(unit)

func _rally_unit(unit: Node3D) -> void:
    unit.routing_state = RoutingState.NONE
    unit.morale = 30.0  # Rally to SHAKEN, not STEADY
    unit.can_receive_orders = true
    unit._rally_timer = 0.0

    BattleSignals.squad_rallied.emit(unit)
```

### SHATTERED State Handling (TR-COR-017)

```gdscript
## SHATTERED squads are combat-ineffective until medevac/mission end
func _handle_shattered(unit: Node3D) -> void:
    # Mark as combat-ineffective
    unit.is_combat_effective = false
    unit.can_receive_orders = false

    # Enter survival AI mode
    unit.set_ai_mode(AIMode.SURVIVAL)

    # Disable weapons (token return fire only)
    unit.weapon_effectiveness = 0.1

    # Movement toward safety only
    var safest_direction := _calculate_safest_direction(unit)
    unit.set_waypoint(unit.global_position + safest_direction * 50.0)

    # Can only recover via:
    # 1. Medevac extraction
    # 2. Mission end
    # 3. Manual recovery command at firebase (post-MVP)

func _calculate_safest_direction(unit: Node3D) -> Vector3:
    var enemies := SpatialHashGrid.get_enemies_in_radius(
        unit.global_position, 200.0, unit.faction
    )

    if enemies.size() == 0:
        # No enemies, head toward firebase
        var firebase := FirebaseSystem.get_nearest_firebase(
            unit.global_position, unit.faction
        )
        if firebase:
            return (firebase.global_position - unit.global_position).normalized()
        return Vector3.BACK

    # Calculate direction away from enemies
    var away_vector := Vector3.ZERO
    for enemy in enemies:
        var to_enemy := enemy.global_position - unit.global_position
        away_vector -= to_enemy.normalized() / to_enemy.length()

    return away_vector.normalized() if away_vector.length() > 0.01 else Vector3.BACK
```

### Morale Effectiveness Modifiers

```gdscript
## How morale state affects unit effectiveness
func get_accuracy_modifier_from_morale(state: MoraleState) -> float:
    match state:
        MoraleState.STEADY: return 1.0
        MoraleState.WAVERING: return 0.85
        MoraleState.SHAKEN: return 0.70
        MoraleState.BROKEN: return 0.30
    return 1.0

func get_movement_modifier_from_morale(state: MoraleState) -> float:
    match state:
        MoraleState.STEADY: return 1.0
        MoraleState.WAVERING: return 1.0
        MoraleState.SHAKEN: return 0.75
        MoraleState.BROKEN: return 1.2  # Running away faster!
    return 1.0

func can_execute_order(unit: Node3D, order: Order) -> bool:
    match unit.morale_state:
        MoraleState.STEADY:
            return true
        MoraleState.WAVERING:
            return true
        MoraleState.SHAKEN:
            # May refuse risky orders
            if order.is_risky():
                return randf() > 0.3  # 30% chance to refuse
            return true
        MoraleState.BROKEN:
            return false  # Cannot follow orders
    return false
```

## Consequences

### Positive
- **Realistic morale cascade**: One squad breaking can trigger others
- **Firebase importance**: Proximity to firebase directly affects morale recovery
- **Supply chain stakes**: Running out of water causes morale drain
- **Auto-behavior**: Routing happens automatically when conditions warrant
- **Recovery possible**: Non-shattered units can rally with time

### Negative
- **Complexity**: Many factors affecting morale require tracking
- **Performance**: Per-unit checks for nearby enemies/allies every frame
- **Balance sensitivity**: Morale modifiers need extensive tuning
- **Player frustration**: Units refusing orders can feel unfair

### Mitigations
- Cache spatial queries, update at 10Hz not every frame
- Expose modifiers as tuning constants
- Clear UI indicators for morale state and reasons
- Audio callouts when morale events trigger

## ADR Dependencies

- **ADR-0003 (Spatial Hash Grid)**: Nearby unit detection for modifiers
- **ADR-0004 (Signal Bus)**: Morale events via BattleSignals
- **ADR-0007 (Navigation)**: Flee pathfinding to firebase
- **ADR-0010 (Combat System)**: Suppression affects morale indirectly

## Engine Compatibility

**Godot 4.6** - Implementation uses:
- `NavigationAgent3D` for flee pathfinding
- Standard GDScript state machines
- Timer-based rally tracking
- Signal-driven event propagation

## GDD Requirements Addressed

| Requirement | How Addressed |
|-------------|---------------|
| TR-COR-010 | `MoraleState` enum with STEADY/WAVERING/SHAKEN/BROKEN thresholds |
| TR-COR-011 | `MODIFIER_UNDER_FIRE`, `MODIFIER_SURROUNDED`, `MODIFIER_DEHYDRATED` constants |
| TR-COR-012 | `MODIFIER_NEAR_FIREBASE`, `MODIFIER_NEAR_ALLIES`, `MODIFIER_WINNING` constants |
| TR-COR-013 | `MoraleEvent` enum with `MORALE_EVENT_VALUES` dictionary |
| TR-COR-014 | `check_routing()` with `BROKEN_THRESHOLD` triggering flee to firebase |
| TR-COR-015 | `RoutingState.SHATTERED` with survival AI mode |
| TR-COR-016 | `process_rally()` with 5-second safe timer |
| TR-COR-017 | SHATTERED units set `is_combat_effective = false`, cannot rally |

## Implementation Files

| File | Purpose |
|------|---------|
| `battle_system/systems/morale_system.gd` | MoraleSystem autoload |
| `battle_system/nodes/squad.gd` | Squad morale properties and behaviors |
| `battle_system/ai/routing_controller.gd` | Flee/survival AI behavior |

## Key Signals

```gdscript
## BattleSignals additions for morale
signal morale_changed(unit: Node3D, old_value: float, new_value: float)
signal morale_state_changed(unit: Node3D, old_state: int, new_state: int)
signal morale_event(unit: Node3D, event: int, change: float)
signal squad_routing(unit: Node3D, target_firebase: Node3D)
signal squad_shattered(unit: Node3D)
signal squad_rallied(unit: Node3D)
```

## Validation Criteria

- [ ] Unit under sustained fire drops from STEADY to BROKEN in ~60 seconds
- [ ] Unit near firebase recovers morale 1.0/sec
- [ ] Squad leader death causes -15 morale instantly
- [ ] BROKEN unit (50%+ broken soldiers) flees toward nearest firebase
- [ ] SHATTERED unit ignores all orders
- [ ] Routing unit rallies after 5+ seconds without enemy contact
- [ ] SHATTERED unit cannot rally (remains combat-ineffective)
- [ ] Surrounded unit loses morale at -1.25/sec
