# Combat System GDD

> **Status**: `[LIVING]`
> **Last Updated**: 2026-05-21
> **Source Documents**: GAME_BIBLE.md Section 11, PRD.md Section 11
> **Pillar**: 5 (The War Continues)

---

## 1. Overview

The combat system handles all damage, suppression, cover, and engagement mechanics. It uses a Steel Division-style approach where casualties accumulate over time rather than instant kills, making cover meaningful without being instant-death without it. Combat is largely automated - squads engage enemies in range automatically - with player focus on positioning and force composition.

---

## 2. Player Fantasy

You are a commander watching your defensive positions hold or break. Good bunker placement and overlapping fields of fire mean the difference between an easy repulse and a desperate last stand. You see tracers, hear the distinct crack of M16s versus AK-47s, watch suppression pin attackers in the open. The satisfaction comes from building a position that works, not from clicking faster than your opponent.

---

## 3. Detailed Rules

### 3.1 Lethality Model

**Steel Division style**: Casualties accumulate over time. A full squad wipe takes 30-60 seconds of sustained fire. This creates time for:
- Player reaction and repositioning
- Suppression effects to matter
- Reinforcement decisions
- Tactical retreats

### 3.2 Cover System

| Cover Type | Damage Reduction | Movement Speed | Notes |
|------------|------------------|----------------|-------|
| None (open) | 0% | 100% | Fully exposed |
| Light (jungle) | 25% | 80% | Natural vegetation cover |
| Partial (sandbags) | 50% | 50% | Standard defensive position |
| Heavy (bunker) | 75% | 0% (stationary) | Strong defensive structure |

**Cover Detection**: Units automatically use nearby cover. Cover bonus applies based on the attacker's angle - flanking reduces cover effectiveness.

### 3.3 Suppression System

Units under heavy fire become suppressed:
- **Movement speed**: Reduced 50%
- **Accuracy**: Reduced 50%
- **Morale drain**: Accelerated (see Morale system)
- **Visual indicator**: Unit hunkers down, "suppressed" icon appears

**Suppression Sources**: Heavy weapons (M60, M2, DShK) generate more suppression than small arms. Explosives generate high suppression in area.

### 3.4 Auto-Defense Behavior

All defensive structures and garrisoned squads use **fire at will**:
- Engage any enemy within weapon range automatically
- No complex ROE system (keep it simple)
- Priority: Closest threat within range
- Bunker/MG nest engagement arcs defined at placement

### 3.5 Damage Types

| Type | Source | Primary Use | Notes |
|------|--------|-------------|-------|
| Small Arms | M16, AK-47, SKS | Anti-infantry | Standard infantry weapons |
| Heavy MG | M2 .50cal, M60, DShK | Suppression + damage | High suppression output |
| Explosive | Mortars, grenades, M79 | Area damage | Splash radius |
| Armor-Piercing | M72 LAW, RPG-7 | Anti-vehicle | Minimal splash |
| Incendiary | Napalm (post-MVP) | Area denial | Terrain modification |

### 3.6 Engagement Ranges

| Weapon | Effective Range | Maximum Range | ROF |
|--------|-----------------|---------------|-----|
| M16 | 300m | 500m | 700 rpm (semi-auto in game) |
| AK-47 | 300m | 400m | 600 rpm |
| M60 | 500m | 800m | 550 rpm |
| M2 .50cal | 800m | 1500m | 450 rpm |
| M79 | 350m | 400m | 6 rpm |
| 81mm Mortar | 100m-3500m | 4500m | 15 rpm |
| RPG-7 | 150m | 300m | 4 rpm |

---

## 4. Formulas

### 4.1 Damage Calculation

```
base_damage = weapon.damage
cover_multiplier = 1.0 - cover.damage_reduction
range_falloff = 1.0 if distance < effective_range else max(0.5, 1.0 - (distance - effective_range) / (max_range - effective_range))
accuracy = shooter.base_accuracy * suppression_penalty * range_falloff

final_damage = base_damage * cover_multiplier * accuracy
```

### 4.2 Suppression Accumulation

```
suppression_gain = weapon.suppression_value * (1.0 - cover.suppression_resist)
current_suppression = clamp(current_suppression + suppression_gain, 0, 100)

# Suppression decay when not under fire (per second)
suppression_decay = 5.0 if in_cover else 2.0
```

### 4.3 Hit Chance

```
base_hit_chance = 0.7  # 70% base
range_modifier = 1.0 - (distance / weapon.max_range) * 0.3
cover_modifier = 1.0 - target_cover.hit_penalty
suppression_modifier = 1.0 - (shooter.suppression / 200.0)  # 50% penalty at full suppression
movement_modifier = 0.7 if target.is_moving else 1.0

final_hit_chance = base_hit_chance * range_modifier * cover_modifier * suppression_modifier * movement_modifier
```

### 4.4 Squad Casualty Tracking

```
squad.soldiers -= floor(accumulated_damage / soldier_hp)
accumulated_damage = accumulated_damage % soldier_hp

if squad.soldiers <= 0:
    squad.destroy()
elif squad.soldiers <= squad.max_soldiers * 0.5:
    squad.morale -= 10  # Half-strength morale hit
```

---

## 5. Edge Cases

### 5.1 Friendly Fire
- **Disabled for MVP**: No friendly fire between player units
- Post-MVP consideration: Artillery and air strikes could cause friendly casualties

### 5.2 Garrison Combat
- Garrisoned squads receive building's cover bonus
- Building takes structural damage when garrisoned squad is attacked
- If building destroyed, garrisoned squad takes 50% casualties and is ejected

### 5.3 Vehicle vs Infantry
- Vehicles are immune to small arms (except open-topped like M113)
- Infantry with AT weapons (LAW, RPG) can damage vehicles
- Vehicles deal high suppression to infantry via MG

### 5.4 Melee/Close Combat
- No melee system - closest range is 10m
- Sappers have bonus damage vs structures at close range

### 5.5 Night Combat
- Engagement range reduced 40%
- Accuracy reduced 20%
- VC/NVA receive +25% effectiveness bonus

### 5.6 Retreating Units
- Units routing away from combat do not return fire
- Routing units have reduced defense (no cover bonus)

---

## 6. Dependencies

| System | Dependency Type | Notes |
|--------|-----------------|-------|
| **Spatial Hash Grid** | Required | O(1) unit queries for range checks |
| **Signal Bus** | Required | Combat events broadcast |
| **Morale System** | Bidirectional | Combat affects morale; morale affects combat |
| **Cover System** | Required | Cover detection and bonuses |
| **Unit Resources** | Required | Ammo consumption per shot |
| **AI Director** | Consumer | Director monitors combat outcomes |

---

## 7. Tuning Knobs

| Parameter | Default | Range | Notes |
|-----------|---------|-------|-------|
| `base_hit_chance` | 0.7 | 0.5-0.9 | Global accuracy baseline |
| `suppression_decay_rate` | 5.0/sec | 2.0-10.0 | How fast suppression fades |
| `casualty_time_target` | 45 sec | 30-60 | Time to wipe a squad under sustained fire |
| `cover_damage_reduction_heavy` | 0.75 | 0.6-0.85 | Bunker protection |
| `cover_damage_reduction_partial` | 0.50 | 0.4-0.6 | Sandbag protection |
| `cover_damage_reduction_light` | 0.25 | 0.15-0.35 | Jungle protection |
| `suppression_movement_penalty` | 0.5 | 0.3-0.7 | Speed reduction when suppressed |
| `suppression_accuracy_penalty` | 0.5 | 0.3-0.7 | Accuracy reduction when suppressed |
| `range_falloff_factor` | 0.5 | 0.3-0.7 | Minimum damage at max range |

---

## 8. Acceptance Criteria

### Core Functionality
- [ ] Squads automatically engage enemies within weapon range
- [ ] Damage is reduced based on target's cover type
- [ ] Suppression accumulates under heavy fire and decays over time
- [ ] Suppressed units move slower and shoot less accurately
- [ ] Squad strength decreases as soldiers are killed
- [ ] Squad is destroyed when all soldiers are killed

### Cover System
- [ ] Units seek nearby cover automatically
- [ ] Cover bonus applies based on attacker's angle (flanking reduces cover)
- [ ] Heavy cover (bunker) provides 75% damage reduction
- [ ] Light cover (jungle) provides 25% damage reduction

### Weapon Differentiation
- [ ] M16 and AK-47 have distinct sound and visual effects
- [ ] Heavy MGs generate high suppression
- [ ] AT weapons damage vehicles but not infantry effectively
- [ ] Mortars deal area damage with splash radius

### Performance
- [ ] Combat calculations complete within frame budget (16.67ms total)
- [ ] 200+ units in simultaneous combat maintains 60 FPS
- [ ] Spatial hash queries are O(1) for range checks

### Balance
- [ ] A full squad wipe takes 30-60 seconds of sustained fire
- [ ] Entrenched defenders have meaningful advantage over attackers
- [ ] Suppression creates tactical decision points (suppress then flank)

---

## Weapon Reference Data

From CLAUDE.md weapon balance table:

| Weapon | Damage | Range (m) | ROF | Suppression |
|--------|--------|-----------|-----|-------------|
| M16 | 15 | 300 | 700 | 5 |
| M60 | 25 | 500 | 550 | 30 |
| M79 | 80 | 350 | 6 | 40 |
| M72 LAW | 200 | 200 | 0.5 | 50 |
| AK47 | 18 | 300 | 600 | 6 |
| RPG7 | 250 | 150 | 4 | 60 |
| M102 Howitzer | 500 | 11000 | 3 | 100 |
| Napalm | 150 | Area | N/A | 100 |
