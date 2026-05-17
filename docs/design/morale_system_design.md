# Morale System Design Document

## Design Goals

1. **Tactical Depth** - Suppression creates opportunities for flanking
2. **Realistic Behavior** - Troops react to fire, seek cover, break under pressure
3. **Unit Differentiation** - Elite units more resilient than conscripts
4. **Combined Arms** - MGs suppress, infantry advances, armor breaks stalemates

---

## Core Concepts

### Suppression vs Morale

| Aspect | Suppression | Morale |
|--------|-------------|--------|
| Scope | Individual squad | Broader unit state |
| Trigger | Incoming fire | Casualties, suppression, isolation |
| Recovery | Seconds | Minutes to hours |
| Effect | Accuracy, movement | Willingness to fight |

For simplicity, we implement **suppression** as the primary mechanic, with **morale states** derived from sustained suppression + casualties.

---

## Suppression Mechanics

### Suppression Sources (Fear IDs)
Based on Spring 1944 research:

```gdscript
enum FearType {
    SMALL_ARMS,      # Rifles, SMGs - low suppression
    MACHINE_GUN,     # MGs - high sustained suppression
    MORTAR,          # Small explosions - moderate AOE
    ARTILLERY,       # Large explosions - high AOE
    NAPALM,          # Extreme - terror effect
    SNIPER,          # Precision fear - "someone's watching"
}

const FEAR_VALUES = {
    FearType.SMALL_ARMS: 2,
    FearType.MACHINE_GUN: 5,
    FearType.MORTAR: 8,
    FearType.ARTILLERY: 15,
    FearType.NAPALM: 25,
    FearType.SNIPER: 10,
}

const FEAR_AOE = {
    FearType.SMALL_ARMS: 3.0,   # Minimal
    FearType.MACHINE_GUN: 8.0,   # Beat zone
    FearType.MORTAR: 15.0,
    FearType.ARTILLERY: 25.0,
    FearType.NAPALM: 30.0,
    FearType.SNIPER: 5.0,
}
```

### Suppression Application

```gdscript
func apply_suppression(amount: float, source_type: FearType) -> void:
    var fear_mult = FEAR_VALUES[source_type]
    var raw_suppression = amount * fear_mult * 0.01

    # Apply training modifier
    raw_suppression *= get_training_modifier()

    # Apply cover modifier
    raw_suppression *= get_cover_suppression_modifier()

    suppression_level += raw_suppression
    suppression_level = clampf(suppression_level, 0.0, 1.0)

    _update_suppression_state()
```

### Suppression States

```gdscript
enum SuppressionState {
    NORMAL,      # 0.0 - 0.3: Full effectiveness
    CAUTIOUS,    # 0.3 - 0.5: Reduced accuracy, seeking cover
    SUPPRESSED,  # 0.5 - 0.8: Prone, minimal fire, won't advance
    PINNED,      # 0.8 - 1.0: Can't fire, frozen in place
}

func _get_suppression_state() -> SuppressionState:
    if suppression_level < 0.3:
        return SuppressionState.NORMAL
    elif suppression_level < 0.5:
        return SuppressionState.CAUTIOUS
    elif suppression_level < 0.8:
        return SuppressionState.SUPPRESSED
    else:
        return SuppressionState.PINNED
```

### Suppression Effects

| State | Accuracy | Move Speed | Can Attack | Can Move |
|-------|----------|------------|------------|----------|
| Normal | 100% | 100% | Yes | Yes |
| Cautious | 75% | 80% | Yes | Yes |
| Suppressed | 40% | 50% | Limited | Crawl only |
| Pinned | 10% | 0% | No | No |

### Suppression Decay

```gdscript
const BASE_DECAY_RATE = 0.05  # Per second

func _process_suppression(delta: float) -> void:
    if suppression_level <= 0:
        return

    var decay = BASE_DECAY_RATE * delta

    # Training affects recovery
    decay *= get_training_recovery_modifier()

    # Cover accelerates recovery
    if is_in_cover:
        decay *= 1.5

    # NCO nearby accelerates recovery
    if has_nearby_nco():
        decay *= 1.3

    suppression_level -= decay
    suppression_level = maxf(suppression_level, 0.0)

    _update_suppression_state()
```

---

## Training System

### Training Levels
Based on Warno research:

```gdscript
enum TrainingLevel {
    CONSCRIPT,    # Poorly trained militia
    REGULAR,      # Standard infantry
    VETERAN,      # Experienced soldiers
    ELITE,        # Special forces, Rangers
}

const TRAINING_MODIFIERS = {
    TrainingLevel.CONSCRIPT: {
        "suppression_mult": 1.5,    # Takes 50% more suppression
        "recovery_mult": 0.5,       # Recovers 50% slower
        "break_threshold": 0.6,     # Breaks at 60% suppression
        "accuracy_bonus": 0.0,
    },
    TrainingLevel.REGULAR: {
        "suppression_mult": 1.0,
        "recovery_mult": 1.0,
        "break_threshold": 0.8,
        "accuracy_bonus": 0.0,
    },
    TrainingLevel.VETERAN: {
        "suppression_mult": 0.8,
        "recovery_mult": 1.3,
        "break_threshold": 0.9,
        "accuracy_bonus": 0.1,
    },
    TrainingLevel.ELITE: {
        "suppression_mult": 0.5,
        "recovery_mult": 2.0,
        "break_threshold": 1.0,  # Never breaks, only pins
        "accuracy_bonus": 0.2,
    },
}
```

---

## Morale System

### Morale Factors

```gdscript
var base_morale: float = 1.0  # Full morale

# Factors that reduce morale
var casualty_penalty: float = 0.0      # Per casualty taken
var isolation_penalty: float = 0.0     # No friendly units nearby
var sustained_suppression: float = 0.0 # Time under fire

# Factors that boost morale
var nco_bonus: float = 0.0             # NCO/officer nearby
var cover_bonus: float = 0.0           # In defensive position
var recent_kills: float = 0.0          # Successful combat

func get_effective_morale() -> float:
    var morale = base_morale

    morale -= casualty_penalty
    morale -= isolation_penalty
    morale -= sustained_suppression

    morale += nco_bonus
    morale += cover_bonus
    morale += recent_kills

    return clampf(morale, 0.0, 1.0)
```

### Morale States

```gdscript
enum MoraleState {
    HIGH,      # > 0.8: Aggressive, willing to assault
    STEADY,    # 0.5 - 0.8: Normal operations
    SHAKEN,    # 0.3 - 0.5: Defensive only, no assault
    BROKEN,    # < 0.3: Retreating, ignores orders
}
```

### Breaking & Routing

```gdscript
func check_morale_break() -> void:
    var effective_morale = get_effective_morale()
    var break_threshold = TRAINING_MODIFIERS[training].break_threshold

    if suppression_level >= break_threshold and effective_morale < 0.3:
        _trigger_rout()

func _trigger_rout() -> void:
    morale_state = MoraleState.BROKEN
    # Find nearest cover or friendly position
    var retreat_target = _find_retreat_position()
    _flee_to(retreat_target)

    # Emit signal for voice lines, UI
    BattleSignals.unit_routed.emit(self)
```

---

## NCO/Leadership System

### Fear Shield (Spring 1944)

```gdscript
class_name LeadershipAura extends Node3D

@export var aura_radius: float = 15.0
@export var suppression_reduction: float = 0.3  # 30% less suppression
@export var recovery_bonus: float = 0.5         # 50% faster recovery
@export var morale_bonus: float = 0.2           # +0.2 morale

func _physics_process(delta: float) -> void:
    var nearby = SpatialHashGrid.get_friendlies_in_radius(
        global_position, aura_radius, faction
    )

    for unit in nearby:
        if unit == self:
            continue
        _apply_leadership_buff(unit)

func _apply_leadership_buff(unit: Node3D) -> void:
    if unit.has_method("set_nco_bonus"):
        unit.set_nco_bonus(morale_bonus)
    if unit.has_method("set_recovery_modifier"):
        unit.set_recovery_modifier(recovery_bonus)
```

### Leadership Death Impact

When NCO/officer killed:
1. Nearby units take immediate suppression spike
2. Leadership buffs removed
3. Temporary morale penalty

```gdscript
func _on_leader_killed(leader: Node3D) -> void:
    var affected = SpatialHashGrid.get_friendlies_in_radius(
        leader.global_position, 20.0, faction
    )

    for unit in affected:
        # Immediate suppression spike
        if unit.has_method("apply_suppression"):
            unit.apply_suppression(10.0, FearType.SMALL_ARMS)

        # Morale penalty
        if unit.has_method("apply_morale_penalty"):
            unit.apply_morale_penalty(0.2, 30.0)  # -0.2 for 30 seconds
```

---

## Cover & Suppression Interaction

### Cover Suppression Modifier

```gdscript
func get_cover_suppression_modifier() -> float:
    match current_cover:
        CoverType.NONE:
            return 1.0
        CoverType.LIGHT:  # Hedgerow, sandbags
            return 0.7
        CoverType.HEAVY:  # Trench, bunker
            return 0.4
        CoverType.FORTIFIED:  # Concrete bunker
            return 0.2
```

### Prone State

When suppressed, infantry go prone:
1. Hitbox lowered (harder to hit)
2. Accuracy reduced (can't aim well)
3. Movement restricted (crawl only)

```gdscript
func _update_prone_state() -> void:
    var should_be_prone = suppression_level >= 0.5

    if should_be_prone and not is_prone:
        _go_prone()
    elif not should_be_prone and is_prone and suppression_level < 0.3:
        _stand_up()

func _go_prone() -> void:
    is_prone = true
    # Adjust collision shape
    collision_shape.scale.y = 0.4
    collision_shape.position.y = 0.2
    # Visual
    if _animator:
        _animator.set_state("prone")
```

---

## Integration Points

### Weapon Data

```gdscript
# In VietnamWeaponData
@export var fear_type: FearType = FearType.SMALL_ARMS
@export var suppression_per_hit: float = 1.0
@export var suppression_per_near_miss: float = 0.5
```

### Combat Manager

```gdscript
func _on_projectile_near_unit(projectile, unit, distance) -> void:
    if distance < 3.0:  # Near miss
        var weapon_data = projectile.weapon_data
        var suppression = weapon_data.suppression_per_near_miss
        unit.apply_suppression(suppression, weapon_data.fear_type)

func _on_unit_hit(attacker, target, damage, weapon_data) -> void:
    var suppression = weapon_data.suppression_per_hit
    target.apply_suppression(suppression, weapon_data.fear_type)

    # Apply AOE suppression
    var aoe = FEAR_AOE[weapon_data.fear_type]
    var nearby = SpatialHashGrid.get_units_in_radius(
        target.global_position, aoe
    )
    for unit in nearby:
        if unit != target:
            var dist_factor = 1.0 - (unit.global_position.distance_to(
                target.global_position) / aoe)
            unit.apply_suppression(suppression * dist_factor * 0.5,
                weapon_data.fear_type)
```

---

## Vietnam-Specific Considerations

### Faction Differences

| Faction | Training | Morale Modifier | Notes |
|---------|----------|-----------------|-------|
| US Army | Regular-Veteran | Standard | Well-supplied, air support |
| ARVN | Conscript-Regular | -0.1 | Variable quality |
| VC | Regular-Veteran | +0.1 | High motivation, guerrilla |
| NVA | Regular-Elite | Standard | Professional military |

### Special Conditions

1. **Night Combat** - Higher suppression, slower recovery
2. **Ambush** - Initial suppression spike to ambushed units
3. **Friendly Fire** - Severe morale penalty
4. **Medevac** - Seeing wounded evacuated improves morale

---

## UI Requirements

### Per-Unit Indicators
- Suppression meter (color-coded)
- Morale state icon
- Prone/cover status

### Audio Cues
- "Taking fire!" callouts
- Panic screams when pinned
- "Get down!" when suppressed
- Rally calls from NCOs
