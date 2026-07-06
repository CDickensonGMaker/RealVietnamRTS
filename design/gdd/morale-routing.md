# Morale & Routing System GDD

> **Status**: `[LIVING]`
> **Last Updated**: 2026-05-21
> **Source Documents**: PRD.md Section 7
> **Pillar**: 5 (The War Continues)
> **Reference Implementation**: BP_RTS_Dark_Shadows/battle_system/morale/

---

## 1. Overview

The morale system tracks unit psychological state and determines routing behavior. Units under sustained fire, surrounded, or dehydrated will eventually break and flee. Broken units attempt to return to the nearest firebase; shattered units go rogue in survival mode. This creates dramatic moments - watching a squad break and run, or hold the line against overwhelming odds - without instant squad wipes.

---

## 2. Player Fantasy

Your squads are soldiers, not robots. When the mortars start falling and casualties mount, you watch morale bars drain. A squad in a good bunker with overlapping fire support holds steady. An isolated squad in the open breaks and runs. You feel the weight of command - good positions save lives, bad positions break men. When a shattered squad comes stumbling back to the firebase, you know you pushed too hard.

---

## 3. Detailed Rules

### 3.1 Morale States

| State | Morale Value | Combat Effectiveness | Behavior |
|-------|--------------|---------------------|----------|
| **STEADY** | 70-100 | 100% | Normal operations, follows all orders |
| **WAVERING** | 40-70 | 90% | Slightly impaired, may hesitate |
| **SHAKEN** | 20-40 | 75% | Significantly impaired, reduced accuracy |
| **BROKEN** | 0-20 | 30% | Routing behavior activated |

### 3.2 Squad Morale Aggregation

Individual soldiers have morale. Squad state is determined by percentage of soldiers in each state:
- **STEADY**: 50%+ soldiers in STEADY state
- **WAVERING**: 50%+ soldiers in WAVERING or higher
- **SHAKEN**: 50%+ soldiers in SHAKEN or higher
- **BROKEN**: 50%+ soldiers in BROKEN state
- **SHATTERED**: 80%+ soldiers in BROKEN state (special state)

### 3.3 Continuous Morale Modifiers (per second)

| Modifier | Effect | Notes |
|----------|--------|-------|
| Under fire | -0.3/sec | Taking ranged fire from enemy |
| Surrounded | -1.25/sec | Enemies detected on 3+ sides |
| Dehydrated (low water) | -0.5/sec | Water below 20% |
| Near firebase | +1.0/sec | Within influence radius |
| Near allies | +0.5/sec | Per nearby friendly squad (max +1.5) |
| Winning engagement | +0.6/sec | Inflicting more casualties than taking |
| Natural recovery (safe) | +1.0/sec | No enemies within detection range |
| In cover | +0.2/sec | Occupying defensive position |
| Garrisoned | +0.3/sec | Inside building/bunker |

### 3.4 One-Time Morale Events

| Event | Morale Change | Notes |
|-------|---------------|-------|
| Nearby ally killed | -3 | Within 20m |
| Squad leader killed | -15 | Severe blow to cohesion |
| Flanked/ambushed | -8 | Surprise attack |
| Reinforcements arrive | +10 | Fresh troops boost morale |
| Enemy unit routed | +5 | Seeing enemy flee is encouraging |
| Firebase established | +5 | Sense of security |
| Air support arrives | +8 | "The cavalry's here" |
| Supply delivered | +3 | Basic needs met |
| Building completed | +2 | Visible progress |

### 3.5 Routing Behavior (Total War-style)

When squad reaches BROKEN state:

**Stage 1: Routing**
1. Squad disengages from combat
2. Ignores player commands (except Rally if available)
3. Attempts to move toward nearest firebase
4. Will not fire back (focused on fleeing)
5. Takes increased damage (no cover bonus while routing)

**Stage 2: Rally Attempt**
- If routing squad reaches firebase influence radius: Begin recovery
- Recovery rate: +2.0 morale/sec when safe
- Can return to SHAKEN state and become controllable again

**Stage 3: Shattered (if 80%+ broken)**
- Squad enters SHATTERED state
- Completely ignores all orders
- Individual soldiers scatter in random directions
- Cannot rally - effectively combat-ineffective
- May be medevac'd for replacement (post-MVP)

---

## 4. Formulas

### 4.1 Morale Update (per frame)

```gdscript
func update_morale(delta: float) -> void:
    var modifier := 0.0

    # Continuous modifiers
    if is_under_fire():
        modifier -= 0.3
    if is_surrounded():
        modifier -= 1.25
    if water_percent < 0.2:
        modifier -= 0.5
    if is_in_firebase_radius():
        modifier += 1.0
    modifier += min(nearby_friendly_count * 0.5, 1.5)
    if is_winning_engagement():
        modifier += 0.6
    if is_safe():
        modifier += 1.0
    if is_in_cover():
        modifier += 0.2
    if is_garrisoned():
        modifier += 0.3

    morale = clampf(morale + modifier * delta, 0.0, 100.0)
    update_morale_state()
```

### 4.2 Surrounded Check

```gdscript
func is_surrounded() -> bool:
    var enemy_directions := 0
    var sectors := [false, false, false, false]  # N, E, S, W

    for enemy in get_nearby_enemies(DETECTION_RANGE):
        var angle := position.angle_to_point(enemy.position)
        var sector := int((angle + PI) / (PI / 2)) % 4
        sectors[sector] = true

    enemy_directions = sectors.count(true)
    return enemy_directions >= 3
```

### 4.3 Combat Effectiveness

```gdscript
func get_combat_effectiveness() -> float:
    match morale_state:
        MoraleState.STEADY:
            return 1.0
        MoraleState.WAVERING:
            return 0.9
        MoraleState.SHAKEN:
            return 0.75
        MoraleState.BROKEN:
            return 0.3
    return 1.0
```

### 4.4 Squad State Aggregation

```gdscript
func update_squad_state() -> void:
    var broken_count := 0
    var shaken_count := 0

    for soldier in soldiers:
        if soldier.morale_state == MoraleState.BROKEN:
            broken_count += 1
        elif soldier.morale_state == MoraleState.SHAKEN:
            shaken_count += 1

    var broken_percent := float(broken_count) / soldiers.size()
    var shaken_percent := float(shaken_count + broken_count) / soldiers.size()

    if broken_percent >= 0.8:
        squad_state = SquadState.SHATTERED
    elif broken_percent >= 0.5:
        squad_state = SquadState.BROKEN
    elif shaken_percent >= 0.5:
        squad_state = SquadState.SHAKEN
    else:
        squad_state = SquadState.STEADY
```

---

## 5. Edge Cases

### 5.1 Squad Leader Death
- Squad leader is first soldier (index 0) by convention
- Death triggers -15 morale hit to entire squad
- New leader promoted (no mechanical effect, just flavor)

### 5.2 Last Man Standing
- Single soldier remaining has separate morale calculation
- Higher chance of breaking (isolation penalty)
- May surrender (post-MVP) or fight to death

### 5.3 Vehicle Crews
- Vehicles have crew morale tracked separately
- Crew abandons vehicle at BROKEN state
- Abandoned vehicle becomes capturable (post-MVP)

### 5.4 Garrisoned Units Breaking
- Garrisoned units that break exit the building
- Then follow normal routing behavior
- Building is not abandoned (just ungarrisoned)

### 5.5 Routing into Enemy
- Routing units that encounter enemies during retreat:
  - Attempt to path around
  - If no path, surrender or die
  - Will not fight back while routing

### 5.6 Firebase Under Attack
- Firebase influence bonus still applies even during attack
- But under_fire penalty also applies
- Net effect depends on attack intensity

---

## 6. Dependencies

| System | Dependency Type | Notes |
|--------|-----------------|-------|
| **Combat System** | Required | Combat events trigger morale changes |
| **Unit Resources** | Required | Water level affects morale |
| **Firebase System** | Required | Firebase provides morale bonus |
| **Spatial Hash Grid** | Required | Nearby ally/enemy detection |
| **Pathfinding** | Required | Routing requires pathfinding to firebase |

---

## 7. Tuning Knobs

| Parameter | Default | Range | Notes |
|-----------|---------|-------|-------|
| `under_fire_penalty` | -0.3/sec | -0.1 to -0.5 | How fast morale drains under fire |
| `surrounded_penalty` | -1.25/sec | -0.5 to -2.0 | Penalty when surrounded |
| `dehydration_penalty` | -0.5/sec | -0.2 to -1.0 | Low water morale drain |
| `firebase_bonus` | +1.0/sec | +0.5 to +2.0 | Recovery rate near firebase |
| `ally_bonus` | +0.5/sec | +0.2 to +0.8 | Per nearby friendly (max 3) |
| `recovery_rate_safe` | +1.0/sec | +0.5 to +2.0 | Recovery when safe |
| `broken_threshold` | 20 | 10-30 | Morale value for BROKEN state |
| `shattered_threshold` | 0.8 | 0.7-0.9 | % broken soldiers for SHATTERED |
| `squad_leader_death_penalty` | -15 | -10 to -25 | One-time hit on leader death |

---

## 8. Acceptance Criteria

### Core Functionality
- [ ] Units have morale value (0-100) that changes over time
- [ ] Morale state (STEADY/WAVERING/SHAKEN/BROKEN) affects combat effectiveness
- [ ] Continuous modifiers (fire, surrounded, dehydrated, allies) apply per-second
- [ ] One-time events (casualties, flanking) cause immediate morale changes

### Routing Behavior
- [ ] Units at BROKEN state attempt to flee toward nearest firebase
- [ ] Routing units ignore player commands
- [ ] Routing units do not fire back
- [ ] SHATTERED units scatter randomly and cannot rally

### Recovery
- [ ] Units can recover morale when safe (no enemies nearby)
- [ ] Firebase influence radius accelerates recovery
- [ ] Routing units that reach firebase can recover to SHAKEN

### Visual Feedback
- [ ] Morale bar visible on selected units
- [ ] State indicator (icon or color) shows current morale state
- [ ] Routing units have distinct animation/posture
- [ ] SHATTERED state clearly indicated

### Balance
- [ ] Well-positioned squads maintain STEADY state under moderate fire
- [ ] Isolated, surrounded squads break within 30-60 seconds
- [ ] Recovery from BROKEN to STEADY takes 60-90 seconds in safety

---

## Visual Indicators

| State | Bar Color | Icon | Animation |
|-------|-----------|------|-----------|
| STEADY | Green | None | Normal stance |
| WAVERING | Yellow | Exclamation | Nervous glances |
| SHAKEN | Orange | Warning | Ducking frequently |
| BROKEN | Red | Running man | Routing animation |
| SHATTERED | Dark red | Skull | Scattered running |

---

## Historical Context

Morale and routing were critical factors in Vietnam combat:
- **Ambush psychology**: Surprise attacks caused disproportionate morale damage
- **Firebase security**: Soldiers fought better near established positions
- **Unit cohesion**: Buddy pairs and small teams maintained morale
- **Leadership**: Squad leader casualties could break entire squads
- **Isolation fear**: Cut-off units often broke faster than engaged ones
