# AI Director System GDD

> **Status**: `[LIVING]`
> **Last Updated**: 2026-05-21
> **Source Documents**: PRD.md Section 12
> **Reference**: Left 4 Dead AI Director

---

## 1. Overview

The AI Director is a dynamic system that monitors player stress and adapts enemy attack intensity accordingly. Rather than scripted waves, the Director observes player state - firebase integrity, supply status, casualties, defensive coverage - and adjusts attack frequency, intensity, direction, and type in response. This creates tension without unfair difficulty spikes.

---

## 2. Player Fantasy

The enemy is smart. When you're spread thin, they probe your weak points. When you're dug in and ready, they switch to harassment. You never feel like you're fighting a script - you feel like you're fighting an opponent who's watching you, adapting. The war feels alive.

---

## 3. Detailed Rules

### 3.1 Director Inputs (What It Monitors)

| Input | Measurement | Range |
|-------|-------------|-------|
| Firebase integrity | % of firebases NOT under attack | 0-100% |
| Supply status | Average supply level across all firebases | 0-100% |
| Casualty rate | Recent losses (last 5 minutes) | 0-50+ casualties |
| Defensive coverage | % of firebase perimeter with defensive structures | 0-100% |
| Player idle time | Time since last player command | 0-300+ seconds |
| Mission progress | % of objectives completed | 0-100% |
| Unit distribution | Concentration vs spread of player forces | Score |
| Morale status | Average morale across all squads | 0-100 |

### 3.2 Director Outputs (What It Controls)

| Output | Range | Notes |
|--------|-------|-------|
| Attack frequency | 5-15 min between waves | Longer when player stressed |
| Attack intensity | 1-4 squads per wave | More when player doing well |
| Attack direction | Weak point targeting | Probes undermanned sectors |
| Attack type | Infantry/sapper/mortar/multi | Varies by context |
| Reinforcement rate | 0.5x-1.5x | Scales enemy reinforcements |
| Special events | Tunnel discoveries, ambushes | Triggered contextually |

### 3.3 Stress Calculation

The Director calculates a **Player Stress Score** (0-100):

```
stress = 0

# Firebase pressure (0-30 points)
stress += (firebases_under_attack / total_firebases) * 30

# Supply pressure (0-20 points)
stress += (1.0 - avg_supply_percent) * 20

# Casualty pressure (0-20 points)
stress += min(recent_casualties / 10, 1.0) * 20

# Morale pressure (0-15 points)
stress += (1.0 - avg_morale_percent) * 15

# Idle penalty (0-15 points, negative stress if player not commanding)
stress += min(idle_time / 60, 1.0) * 15

final_stress = clamp(stress, 0, 100)
```

### 3.4 Director Behavior by Stress Level

| Stress | Director Behavior |
|--------|-------------------|
| 0-25 (Low) | Aggressive attacks, multiple directions, short intervals |
| 25-50 (Medium) | Balanced attacks, single direction, moderate intervals |
| 50-75 (High) | Reduced intensity, harassment only, longer intervals |
| 75-100 (Critical) | Minimal attacks, recovery window, potential lull |

### 3.5 Escalation Over Mission Time

The Director escalates baseline intensity over mission duration:

| Mission Phase | Time Range | Baseline Intensity |
|---------------|------------|-------------------|
| **Early** | 0-15 min | Probing attacks, 1-2 squads, single direction |
| **Mid** | 15-35 min | Coordinated attacks, 2-3 squads, mortars support |
| **Late** | 35-60 min | Full assaults, 3-4 squads, sappers, multi-direction |
| **Endgame** | 60+ min | Maximum intensity, special events, final push |

---

## 4. Attack Types

### 4.1 Infantry Assault
- **Composition**: 2-4 VC/NVA infantry squads
- **Behavior**: Direct attack on firebase perimeter
- **Trigger**: Default attack type
- **Counter**: Defensive positions, overlapping fire

### 4.2 Sapper Raid
- **Composition**: 1-2 sapper cells
- **Behavior**: Infiltrate through wire, target ammo/fuel depots
- **Trigger**: Player has valuable structures undefended
- **Counter**: Wire obstacles, patrols, observation towers

### 4.3 Mortar Harassment
- **Composition**: 1-2 mortar teams, 1 infantry squad (protection)
- **Behavior**: Indirect fire on firebase, withdraw if pursued
- **Trigger**: Player is well-defended, Director needs pressure
- **Counter**: Counter-battery fire, aggressive patrolling

### 4.4 Multi-Direction Attack
- **Composition**: 2-3 squads per direction, 2-3 directions
- **Behavior**: Simultaneous attacks from multiple angles
- **Trigger**: Late mission, player is concentrated in one area
- **Counter**: Reserve forces, balanced defensive coverage

### 4.5 Human Wave (NVA Main Force only)
- **Composition**: 4+ squads in single wave
- **Behavior**: Massed assault ignoring casualties
- **Trigger**: Mission climax, player firebase is weak
- **Counter**: Sustained defensive fire, artillery, air support

---

## 5. VC Tactical Patterns (Historical)

| Tactic | When Used | Behavior |
|--------|-----------|----------|
| **Night attack** | After sunset | +25% effectiveness, reduced visibility |
| **Sapper raid** | Valuable targets undefended | Infiltrate, demolish, withdraw |
| **Mortar harassment** | Player well-defended | Indirect fire, no assault |
| **Human wave** | Player weakened | Mass assault, morale bonus |
| **Ambush** | Supply convoy en route | Attack convoy on road |
| **Probe** | Early mission | Test defenses, identify weak points |

---

## 6. Formulas

### 6.1 Attack Interval Calculation

```gdscript
func calculate_next_attack_interval() -> float:
    var base_interval := 10.0 * 60.0  # 10 minutes in seconds
    var stress_modifier := 1.0 + (player_stress / 100.0)  # 1.0 to 2.0
    var escalation_modifier := 1.0 - (mission_time / (90.0 * 60.0)) * 0.5  # 1.0 to 0.5

    var interval := base_interval * stress_modifier * escalation_modifier
    return clampf(interval, 5.0 * 60.0, 15.0 * 60.0)  # 5-15 minutes
```

### 6.2 Attack Intensity Calculation

```gdscript
func calculate_attack_intensity() -> int:
    var base_squads := 2
    var stress_modifier := 1.0 - (player_stress / 100.0) * 0.5  # 1.0 to 0.5
    var escalation_bonus := int(mission_time / (20.0 * 60.0))  # +1 squad every 20 min

    var squads := int(base_squads * stress_modifier) + escalation_bonus
    return clampi(squads, 1, 4)
```

### 6.3 Attack Direction Selection

```gdscript
func select_attack_direction() -> Vector3:
    var weak_sectors := []

    for sector in get_firebase_sectors():
        var coverage := calculate_sector_coverage(sector)
        if coverage < WEAK_SECTOR_THRESHOLD:
            weak_sectors.append(sector)

    if weak_sectors.size() > 0:
        return weak_sectors.pick_random().direction
    else:
        return get_random_sector().direction
```

---

## 7. Tuning Knobs

| Parameter | Default | Range | Notes |
|-----------|---------|-------|-------|
| `base_attack_interval` | 10 min | 5-15 min | Time between attacks at medium stress |
| `min_attack_interval` | 5 min | 3-8 min | Minimum time between attacks |
| `max_attack_interval` | 15 min | 10-20 min | Maximum time between attacks |
| `base_attack_squads` | 2 | 1-3 | Squads per attack at medium stress |
| `max_attack_squads` | 4 | 3-6 | Maximum squads per attack |
| `stress_weight_firebase` | 30 | 20-40 | Weight of firebase pressure in stress |
| `stress_weight_supply` | 20 | 10-30 | Weight of supply pressure in stress |
| `stress_weight_casualties` | 20 | 10-30 | Weight of casualty pressure in stress |
| `weak_sector_threshold` | 0.3 | 0.2-0.5 | Coverage below this is "weak" |
| `night_attack_bonus` | 0.25 | 0.15-0.35 | VC effectiveness bonus at night |

---

## 8. Acceptance Criteria

### Core Functionality
- [ ] Director monitors player state (firebases, supply, casualties, morale)
- [ ] Director calculates player stress score (0-100)
- [ ] Attack frequency inversely proportional to stress
- [ ] Attack intensity proportional to player strength

### Attack Variety
- [ ] Director selects from multiple attack types
- [ ] Sapper raids target undefended high-value structures
- [ ] Mortar harassment used against well-defended positions
- [ ] Multi-direction attacks used against concentrated forces

### Escalation
- [ ] Attack intensity increases over mission time
- [ ] Early phase (0-15 min) has probing attacks only
- [ ] Late phase (35+ min) has coordinated multi-squad attacks
- [ ] Endgame (60+ min) has maximum intensity

### Weak Point Targeting
- [ ] Director identifies undermanned firebase sectors
- [ ] Attacks preferentially target weak sectors
- [ ] Director adapts to player repositioning

### Recovery Windows
- [ ] High stress (75+) triggers attack lull
- [ ] Player has time to regroup when overwhelmed
- [ ] Lulls are temporary, not permanent

### Balance
- [ ] Player feels challenged but not overwhelmed
- [ ] Good defensive positioning is rewarded
- [ ] Spread-thin mistakes are punished
- [ ] No unfair difficulty spikes

---

## Dependencies

| System | Dependency Type | Notes |
|--------|-----------------|-------|
| **Combat System** | Consumer | Tracks casualties, combat outcomes |
| **Firebase System** | Consumer | Monitors firebase integrity |
| **Supply Logistics** | Consumer | Monitors supply levels |
| **Morale System** | Consumer | Monitors unit morale |
| **Spatial Hash Grid** | Required | Unit position queries |
| **Pathfinding** | Required | Attack route planning |

---

## Implementation Notes

### Spawn Locations
- **Tunnel entrances**: Primary spawn for VC
- **Map edges**: Secondary spawn, indicates infiltration
- **Off-map staging**: NVA Main Force attacks

### Attack Coordination
- Squads assigned to attack group
- Group moves together until contact
- Individual squad AI takes over during combat

### Retreat Behavior
- If attack fails (>50% casualties), survivors retreat
- Retreating units despawn at map edge or tunnel
- Director records attack outcome for learning
