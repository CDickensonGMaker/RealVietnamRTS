# ADR-0010: Combat System

## Status
Proposed

## Context

RealVietnamRTS combat must deliver the Steel Division lethality feel while supporting the game's defensive focus. Units under fire must seek cover, suppression must meaningfully impact effectiveness, and auto-defense structures must engage without player micromanagement.

### Combat Design Goals (from GAME_BIBLE.md)
- **Steel Division lethality**: Full squad wipe takes 30-60 seconds of sustained fire
- **Cover matters**: Units in heavy cover survive significantly longer
- **Suppression as control**: Suppressed units can't advance effectively
- **Auto-defense**: Garrisoned positions and defensive structures engage automatically
- **Four damage types**: Different weapons effective against different targets

### Requirements to Address
| TR-ID | Requirement |
|-------|-------------|
| TR-COR-001 | Cover system: NONE (0%), LIGHT (25%), PARTIAL (50%), HEAVY (75%) damage reduction |
| TR-COR-002 | Suppression reduces movement speed 50% and accuracy 50% |
| TR-COR-003 | Steel Division lethality tuning (30-60 second squad wipe) |
| TR-COR-004 | Four damage types: Small Arms, Heavy MG, Explosive, Armor-Piercing |
| TR-COR-005 | Auto-defense: defensive structures and garrisoned squads use fire-at-will |
| TR-COR-006 | Squads track individual soldier casualties |
| TR-COR-007 | Standing orders: Guard, Patrol, Aggressive, Hold Fire |

## Decision

### Combat Resolution Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        CombatManager                                 │
│                      (Autoload Singleton)                            │
├─────────────────────────────────────────────────────────────────────┤
│  + process_attack(attacker, target, weapon_data) -> DamageResult    │
│  + apply_damage(target, damage_result) -> void                      │
│  + calculate_suppression(target, weapon_data) -> float              │
│  + resolve_burst(attacker, targets[], weapon_data) -> void          │
├─────────────────────────────────────────────────────────────────────┤
│  Uses: SpatialHashGrid (target acquisition)                         │
│        WeaponData (damage values)                                   │
│        CoverSystem (damage reduction)                               │
│        BattleSignals (events)                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### Cover System

Four cover levels with damage reduction modifiers:

```gdscript
enum CoverLevel { NONE, LIGHT, PARTIAL, HEAVY }

const COVER_DAMAGE_REDUCTION := {
    CoverLevel.NONE: 0.0,      # Full damage
    CoverLevel.LIGHT: 0.25,    # 25% reduction
    CoverLevel.PARTIAL: 0.50,  # 50% reduction
    CoverLevel.HEAVY: 0.75,    # 75% reduction
}

const COVER_SUPPRESSION_REDUCTION := {
    CoverLevel.NONE: 0.0,
    CoverLevel.LIGHT: 0.15,
    CoverLevel.PARTIAL: 0.30,
    CoverLevel.HEAVY: 0.50,
}
```

**Cover Detection**: Units query nearby cover objects via SpatialHashGrid. Cover effectiveness depends on angle to attacker:
- Cover between unit and attacker: Full effectiveness
- Cover at 45°+ angle: Half effectiveness
- Cover behind unit: No effect

```gdscript
func get_cover_level(unit: Node3D, attacker_pos: Vector3) -> CoverLevel:
    var cover_objects := _get_cover_objects_near(unit.global_position, 3.0)
    var best_cover := CoverLevel.NONE

    for cover in cover_objects:
        var angle := _angle_between_positions(
            unit.global_position,
            cover.global_position,
            attacker_pos
        )
        if angle < 45.0:
            best_cover = maxi(best_cover, cover.cover_level)
        elif angle < 90.0:
            best_cover = maxi(best_cover, cover.cover_level - 1)

    return best_cover
```

### Damage Types

```gdscript
enum DamageType {
    SMALL_ARMS,     # Rifles, pistols, SMGs
    HEAVY_MG,       # .50 cal, vehicle MGs
    EXPLOSIVE,      # Grenades, mortars, artillery
    ARMOR_PIERCING  # LAW, RPG, tank rounds
}

const DAMAGE_TYPE_MODIFIERS := {
    # [target_type] = {damage_type: modifier}
    "infantry": {
        DamageType.SMALL_ARMS: 1.0,
        DamageType.HEAVY_MG: 1.2,
        DamageType.EXPLOSIVE: 1.5,
        DamageType.ARMOR_PIERCING: 0.8,  # Overkill, some wasted
    },
    "light_vehicle": {
        DamageType.SMALL_ARMS: 0.1,
        DamageType.HEAVY_MG: 0.5,
        DamageType.EXPLOSIVE: 0.8,
        DamageType.ARMOR_PIERCING: 1.5,
    },
    "armor": {
        DamageType.SMALL_ARMS: 0.0,
        DamageType.HEAVY_MG: 0.0,
        DamageType.EXPLOSIVE: 0.3,
        DamageType.ARMOR_PIERCING: 1.0,
    },
    "structure": {
        DamageType.SMALL_ARMS: 0.05,
        DamageType.HEAVY_MG: 0.1,
        DamageType.EXPLOSIVE: 1.0,
        DamageType.ARMOR_PIERCING: 0.5,
    },
}
```

### Suppression System

Suppression is a float value 0.0-100.0 affecting unit effectiveness:

```gdscript
## Suppression thresholds and effects
const SUPPRESSION_THRESHOLDS := {
    "light": 25.0,    # 15% accuracy penalty, normal movement
    "medium": 50.0,   # 30% accuracy penalty, 25% movement penalty
    "heavy": 75.0,    # 50% accuracy penalty, 50% movement penalty (TR-COR-002)
    "pinned": 90.0,   # Cannot move, minimal return fire
}

func get_accuracy_modifier(suppression: float) -> float:
    if suppression >= SUPPRESSION_THRESHOLDS.pinned:
        return 0.1
    elif suppression >= SUPPRESSION_THRESHOLDS.heavy:
        return 0.5  # TR-COR-002
    elif suppression >= SUPPRESSION_THRESHOLDS.medium:
        return 0.7
    elif suppression >= SUPPRESSION_THRESHOLDS.light:
        return 0.85
    return 1.0

func get_movement_modifier(suppression: float) -> float:
    if suppression >= SUPPRESSION_THRESHOLDS.pinned:
        return 0.0
    elif suppression >= SUPPRESSION_THRESHOLDS.heavy:
        return 0.5  # TR-COR-002
    elif suppression >= SUPPRESSION_THRESHOLDS.medium:
        return 0.75
    return 1.0
```

**Suppression Decay**: Suppression decays naturally when not under fire:
- Base decay: 5.0 per second
- In cover bonus: +3.0 per second
- Near firebase bonus: +2.0 per second

**Suppression Application**:
```gdscript
func apply_suppression(target: Node3D, weapon_data: WeaponData) -> void:
    var base_suppression := weapon_data.suppression_value
    var cover := get_cover_level(target, _last_attacker_pos)
    var reduction := COVER_SUPPRESSION_REDUCTION[cover]
    var final_suppression := base_suppression * (1.0 - reduction)

    target.add_suppression(final_suppression)
    BattleSignals.unit_suppressed.emit(target, target.suppression)
```

### Squad Casualty Tracking (TR-COR-006)

Each squad tracks individual soldiers:

```gdscript
class_name Squad extends CharacterBody3D

var soldiers_max: int = 10      # Starting squad size
var soldiers_alive: int = 10    # Current alive
var soldiers_wounded: int = 0   # Wounded but not dead
var health_per_soldier: float = 100.0

func take_damage(amount: float, damage_type: DamageType) -> void:
    var remaining := amount
    while remaining > 0 and soldiers_alive > 0:
        var damage_to_soldier := minf(remaining, health_per_soldier)
        remaining -= damage_to_soldier

        # Check if soldier dies
        if randf() < (damage_to_soldier / health_per_soldier):
            soldiers_alive -= 1
            BattleSignals.soldier_killed.emit(self, soldiers_alive)

            # Check squad wipe
            if soldiers_alive <= 0:
                _on_squad_wiped()
                return
```

### Lethality Tuning (TR-COR-003)

To achieve 30-60 second squad wipe time:

```gdscript
## Baseline combat parameters for Steel Division feel
const BASE_HIT_CHANCE := 0.15           # 15% base hit rate at optimal range
const RANGE_FALLOFF_START := 0.7        # Accuracy starts falling at 70% max range
const DAMAGE_PER_HIT := 25.0            # Damage per successful hit
const HEALTH_PER_SOLDIER := 100.0       # HP per soldier

## Example: M16 at 200m against unprotected infantry
## Fire rate: 700 RPM / 60 = 11.67 rounds/sec per soldier
## Hit chance at 200m (66% of 300m range): ~12%
## Hits per second per shooter: 11.67 * 0.12 = 1.4
## Damage per second per shooter: 1.4 * 25 = 35
## Time to kill 1 soldier: 100 / 35 = ~3 seconds
## 10-man squad with 3 shooters: 10 * 3 / 3 = 10 seconds minimum
## With cover, suppression, return fire: 30-60 seconds achieved
```

### Auto-Defense System (TR-COR-005)

Defensive structures and garrisoned squads engage automatically:

```gdscript
class_name AutoDefenseController extends Node

@export var engagement_range: float = 500.0
@export var target_priority: Array[String] = ["sapper", "infantry", "vehicle", "armor"]
@export var fire_arc: float = 90.0  # Degrees (0 = fixed forward, 360 = all directions)

var _current_target: Node3D = null
var _target_scan_timer: float = 0.0
const SCAN_INTERVAL := 0.5

func _process(delta: float) -> void:
    _target_scan_timer += delta
    if _target_scan_timer >= SCAN_INTERVAL:
        _target_scan_timer = 0.0
        _scan_for_targets()

    if _current_target and is_instance_valid(_current_target):
        _engage_target()

func _scan_for_targets() -> void:
    var enemies := SpatialHashGrid.get_enemies_in_radius(
        global_position,
        engagement_range,
        _owner_faction
    )

    # Filter by fire arc
    enemies = enemies.filter(func(e): return _is_in_fire_arc(e))

    # Sort by priority
    enemies.sort_custom(_compare_priority)

    if enemies.size() > 0:
        _current_target = enemies[0]
    else:
        _current_target = null

func _is_in_fire_arc(target: Node3D) -> bool:
    if fire_arc >= 360.0:
        return true
    var angle_to_target := _get_angle_to(target.global_position)
    return absf(angle_to_target) <= fire_arc / 2.0
```

### Standing Orders (TR-COR-007)

```gdscript
enum StandingOrder {
    GUARD,       # Hold position, engage enemies in range
    PATROL,      # Move between waypoints, engage enemies
    AGGRESSIVE,  # Pursue enemies, prioritize offense
    HOLD_FIRE,   # Do not engage, stealth mode
}

func apply_standing_order(order: StandingOrder) -> void:
    match order:
        StandingOrder.GUARD:
            _enable_auto_defense = true
            _pursuit_enabled = false
            _stealth_mode = false
        StandingOrder.PATROL:
            _enable_auto_defense = true
            _pursuit_enabled = false
            _patrol_active = true
        StandingOrder.AGGRESSIVE:
            _enable_auto_defense = true
            _pursuit_enabled = true
            _engagement_range *= 1.5
        StandingOrder.HOLD_FIRE:
            _enable_auto_defense = false
            _stealth_mode = true
```

## Consequences

### Positive
- **Steel Division feel**: Lethality tuning achieves intended engagement duration
- **Cover is meaningful**: 75% damage reduction makes positioning critical
- **Suppression as control**: Heavy suppression halves effectiveness (TR-COR-002)
- **Auto-defense reduces micro**: MG nests and bunkers engage without orders
- **Squad granularity**: Individual soldier tracking enables veterancy and morale

### Negative
- **Cover detection complexity**: Angle calculations every combat tick
- **Performance overhead**: Many simultaneous engagements stress spatial queries
- **Balance tuning required**: Damage values need extensive playtesting
- **State management**: Suppression, cover, casualties create complex state

### Mitigations
- Cache cover calculations per-frame (cover doesn't move)
- Use SpatialHashGrid for efficient enemy queries
- Expose tuning constants in WeaponData resources
- Track suppression as single float, effects via thresholds

## ADR Dependencies

- **ADR-0003 (Spatial Hash Grid)**: Target acquisition via `get_enemies_in_radius()`
- **ADR-0004 (Signal Bus)**: Combat events via BattleSignals
- **ADR-0007 (Navigation)**: Movement affected by suppression
- **ADR-0008 (Serialization)**: Combat state must serialize

## Engine Compatibility

**Godot 4.6** - Implementation uses:
- `CharacterBody3D` for units
- `Area3D` for cover zones and damage areas
- `RayCast3D` for line-of-sight checks
- `Timer` for burst fire and cooldowns
- Standard GDScript math (`atan2`, `Vector3.angle_to`)

## GDD Requirements Addressed

| Requirement | How Addressed |
|-------------|---------------|
| TR-COR-001 | `COVER_DAMAGE_REDUCTION` dictionary with NONE/LIGHT/PARTIAL/HEAVY |
| TR-COR-002 | `get_movement_modifier()` and `get_accuracy_modifier()` at heavy suppression |
| TR-COR-003 | Lethality constants tuned for 30-60 second squad wipe |
| TR-COR-004 | `DamageType` enum with `DAMAGE_TYPE_MODIFIERS` matrix |
| TR-COR-005 | `AutoDefenseController` component for structures/garrisons |
| TR-COR-006 | `Squad.soldiers_alive` tracking with per-hit casualty rolls |
| TR-COR-007 | `StandingOrder` enum with GUARD/PATROL/AGGRESSIVE/HOLD_FIRE |

## Implementation Files

| File | Purpose |
|------|---------|
| `battle_system/systems/combat_manager.gd` | CombatManager autoload (attack resolution) |
| `battle_system/systems/cover_system.gd` | Cover detection and calculation |
| `battle_system/systems/suppression_system.gd` | Suppression application and decay |
| `battle_system/data/weapon_data.gd` | WeaponData resource with damage values |
| `battle_system/components/auto_defense_controller.gd` | Auto-engage behavior |
| `battle_system/nodes/squad.gd` | Squad with soldier tracking |

## Key Signals

```gdscript
## BattleSignals additions for combat
signal attack_started(attacker: Node3D, target: Node3D, weapon: WeaponData)
signal damage_dealt(target: Node3D, amount: float, damage_type: int)
signal soldier_killed(squad: Node3D, remaining: int)
signal squad_wiped(squad: Node3D)
signal unit_suppressed(unit: Node3D, suppression_level: float)
signal suppression_cleared(unit: Node3D)
signal cover_changed(unit: Node3D, old_cover: int, new_cover: int)
```

## Validation Criteria

- [ ] Infantry in HEAVY cover survives 3x longer than in NONE
- [ ] Suppression at 75+ reduces movement and accuracy by 50%
- [ ] Full squad wipe against unprotected targets takes 30-60 seconds
- [ ] MG nests auto-engage enemies within arc without player input
- [ ] Standing orders properly toggle auto-defense and pursuit
- [ ] Soldier casualties tracked individually with signals
- [ ] Cover angle affects effectiveness (90°+ = no benefit)
