# Firebase System GDD

> **Status**: `[LIVING]`
> **Last Updated**: 2026-05-21
> **Source Documents**: GAME_BIBLE.md Section 8, PRD.md Section 8
> **Pillar**: 2 (Network of Firebases)

---

## 1. Overview

The firebase system handles the creation, management, and networking of forward operating bases. A firebase is defined by placing an HQ building, which creates an influence radius where automated logistics, construction, and morale bonuses apply. Players can build a maximum of 4-6 firebases simultaneously, forcing strategic choices about positioning. No two firebases look the same - the player designs each one using paint/drag perimeter tools.

---

## 2. Player Fantasy

You are an engineer-commander, surveying terrain and deciding exactly where your bunkers go. You paint sandbag perimeters, place MG nests with overlapping fields of fire, and position your TOC for maximum observation. When the attack comes, the firebase you designed either holds or it doesn't. The satisfaction is in the construction as much as the defense.

---

## 3. Detailed Rules

### 3.1 Firebase Definition

A firebase is created when an **HQ Building** is placed:
- Command Post (basic)
- TOC - Tactical Operations Center (advanced)
- Firebase HQ (standard)

The HQ building creates an **influence radius** - a circular zone where special rules apply.

### 3.2 HQ Influence Radius

Within the influence radius:
| Benefit | Effect |
|---------|--------|
| Auto-supply | Squads automatically receive ammo/water from depot |
| Morale bonus | +1.0 morale/sec for all friendly units |
| Auto-construction | Engineers build without direct commands |
| Fire at will | Defensive structures engage automatically |
| Building slots | Only positions inside radius count toward firebase level |

| HQ Type | Influence Radius | Building Slots | Sight Bonus |
|---------|------------------|----------------|-------------|
| Command Post | 100m | 8 | +0m |
| TOC | 150m | 12 | +100m |
| Firebase HQ | 150m | 12 | +50m |

### 3.3 Firebase Limit

**Maximum 4-6 firebases active simultaneously.**

This is a hard cap. Placing a 7th HQ building requires abandoning an existing firebase first. The limit forces strategic choices about network topology.

### 3.4 Firebase Levels

Firebases progress through levels based on completed buildings:

| Level | Name | Building Threshold | Unlocks |
|-------|------|-------------------|---------|
| 1 | Patrol Base | 1-4 buildings | Basic defense |
| 2 | Fire Support Base | 5-8 buildings | Artillery support |
| 3 | Major Firebase | 9-12 buildings | Full logistics hub |

### 3.5 Terrain Clearing States

Terrain must be cleared before building (see Terrain Clearing GDD):

| State | Can Build | Movement Speed | Notes |
|-------|-----------|----------------|-------|
| JUNGLE | No | 50% | Must clear first |
| PARTIALLY_CLEARED | Basic only | 75% | Sandbags, wire, foxholes |
| CLEARED | Yes | 100% | All buildings allowed |
| FORTIFIED | Yes | 100% | Enhanced defense bonus |

### 3.6 Construction Stages

Buildings progress through stages:

| Stage | Time % | Visual State | Function |
|-------|--------|--------------|----------|
| FOUNDATION | 25% | Stakes and markers | No function |
| STRUCTURE | 50% | Framing visible | No function |
| FINISHING | 25% | Nearly complete | Partial function |
| COMPLETE | 100% | Finished | Full function |

### 3.7 Outposts (Informal Positions)

Players can build defensive structures **outside** firebase influence radius:
- No influence radius bonuses
- No auto-supply (manual resupply required)
- No morale bonus
- No auto-construction (direct engineer commands)
- Purely defensive positions (sandbags, wire, foxholes, bunkers)

---

## 4. Formulas

### 4.1 Influence Radius Calculation

```
# Base radius from HQ type
base_radius = hq_building.influence_radius

# No modifiers in MVP - fixed radius per HQ type
final_radius = base_radius
```

### 4.2 Firebase Level Calculation

```
building_count = count_buildings_in_radius(hq_position, influence_radius)

if building_count >= 9:
    firebase_level = 3  # Major Firebase
elif building_count >= 5:
    firebase_level = 2  # Fire Support Base
else:
    firebase_level = 1  # Patrol Base
```

### 4.3 Supply Distribution

```
for squad in squads_in_radius:
    if squad.ammo < squad.max_ammo:
        supply_needed = squad.max_ammo - squad.ammo
        supply_available = firebase.supply_depot.ammo
        supply_transfer = min(supply_needed, supply_available, SUPPLY_RATE_PER_SEC * delta)
        squad.ammo += supply_transfer
        firebase.supply_depot.ammo -= supply_transfer
```

### 4.4 Morale Bonus Application

```
for unit in units_in_radius:
    unit.morale_modifier += FIREBASE_MORALE_BONUS  # +1.0/sec
```

---

## 5. Edge Cases

### 5.1 HQ Destruction
- If HQ building is destroyed, influence radius disappears immediately
- All bonuses stop (no auto-supply, no morale bonus)
- Buildings remain but don't count toward firebase level
- Rebuilding HQ restores the firebase

### 5.2 Overlapping Firebases
- Units in overlapping influence radii receive bonuses from both
- Morale bonuses stack (up to cap)
- Supply flows from nearest depot with available supply

### 5.3 Firebase Abandonment
- To place 7th firebase when at cap, player must "Abandon" one
- Abandoned firebase's HQ is destroyed (can be rebuilt later)
- Buildings remain but lose firebase status

### 5.4 Partial Coverage
- Building must have center point inside radius to count
- Units receive bonuses if their center is inside radius
- Edge cases resolved by center-point check

### 5.5 Building Destruction
- Destroyed building no longer counts toward firebase level
- Firebase can "level down" if buildings destroyed
- Ruins remain until engineers clear them

---

## 6. Dependencies

| System | Dependency Type | Notes |
|--------|-----------------|-------|
| **Construction System** | Required | Building placement and completion |
| **Terrain Clearing** | Required | Cleared terrain required for building |
| **Supply Logistics** | Bidirectional | Firebase distributes supply; supply flows to firebase |
| **Morale System** | Consumer | Firebase provides morale bonus |
| **Unit Resources** | Consumer | Firebase handles auto-resupply |
| **Combat System** | Consumer | Defensive structures fire at will |

---

## 7. Tuning Knobs

| Parameter | Default | Range | Notes |
|-----------|---------|-------|-------|
| `max_firebases` | 5 | 4-6 | Hard cap on simultaneous firebases |
| `base_influence_radius` | 150m | 100-200m | Standard HQ influence |
| `firebase_morale_bonus` | 1.0/sec | 0.5-2.0 | Morale recovery in radius |
| `auto_supply_rate` | 5/sec | 2-10 | Supply transfer rate |
| `level_2_threshold` | 5 | 4-6 | Buildings for Fire Support Base |
| `level_3_threshold` | 9 | 8-12 | Buildings for Major Firebase |

---

## 8. Acceptance Criteria

### Core Functionality
- [ ] Placing HQ building creates a firebase with influence radius
- [ ] Influence radius is visually indicated (ground decal or shader)
- [ ] Maximum 4-6 firebases can exist simultaneously
- [ ] Attempting to place 7th HQ prompts abandonment of existing firebase

### Influence Radius Effects
- [ ] Squads inside radius auto-resupply from supply depot
- [ ] Units inside radius receive morale bonus (+1.0/sec)
- [ ] Engineers auto-construct queued buildings inside radius
- [ ] Defensive structures fire at will inside radius

### Firebase Levels
- [ ] Firebase level calculated from building count in radius
- [ ] Level indicator shown on HQ building and minimap
- [ ] Level transitions trigger appropriate UI feedback

### Outposts
- [ ] Sandbags, wire, foxholes, bunkers can be built outside radius
- [ ] Outpost positions receive no influence bonuses
- [ ] Manual resupply required for outpost garrisons

### Destruction & Recovery
- [ ] Destroying HQ removes influence radius immediately
- [ ] Buildings remain when HQ destroyed (just lose firebase status)
- [ ] Rebuilding HQ at same location restores firebase

---

## Building Reference

### Firebase Building Categories (from CLAUDE.md)

| Category | Count | Description |
|----------|-------|-------------|
| Firebase Perimeter | 10 | Defensive positions (bunkers, wire, towers) |
| Firebase Support | 10 | Logistics (helipads, ammo, fuel, medical, comms) |
| Firebase Living | 7 | Living quarters (hootch, mess hall, latrines) |
| Firebase Heavy | 6 | Artillery and vehicle positions |

### Building Costs (Player-Constructible)

| Building | Supply | Work Stages | Notes |
|----------|--------|-------------|-------|
| Sandbag Wall | 5 | [20, 20, 10] | Basic cover |
| Bunker | 40 | [40, 60, 40] | Garrison 8 |
| Sandbag Bunker | 25 | [25, 35, 25] | Garrison 4, PSP cover |
| CONEX Bunker | 45 | [30, 50, 30] | Garrison 6, armored |
| MG Nest | 30 | [30, 40, 30] | Auto-fire 500m range |
| Mortar Pit | 35 | [30, 50, 30] | Indirect fire 3.5km |
| Wire Obstacle | 10 | [15, 15, 10] | Slows 70%, 2 DPS |
| Triple Concertina | 15 | [20, 20, 15] | Slows 80%, 4 DPS |
| Watchtower | 25 | [30, 40, 30] | +60m sight, Garrison 2 |
| Observation Tower | 30 | [35, 45, 30] | +80m sight, 8m tall |
| Helipad | 50 | [40, 50, 40] | Landing zone |
| PSP Helipad | 60 | [45, 55, 45] | Steel matting, 15x15m |
| Ammo Bunker | 45 | [40, 60, 40] | Explosive hazard |
| Fuel Depot | 40 | [35, 50, 35] | Flammable |
| Medical Station | 35 | [30, 50, 30] | Heals wounded |
| TOC | 80 | [60, 80, 60] | +100m sight, HQ |
| Commo Bunker | 50 | [40, 60, 40] | Calls air support |
| Hootch | 20 | [20, 30, 20] | Living quarters |
| Mess Hall | 45 | [40, 60, 40] | Flammable |
| Artillery Pit | 100 | [60, 100, 60] | 105mm howitzer 11km |
| 155mm Howitzer Pit | 120 | [70, 120, 70] | 155mm howitzer 14.6km |
| Tank Revetment | 60 | [50, 70, 50] | Vehicle protection |

### Destruction States

| State | Description |
|-------|-------------|
| INTACT | Fully operational |
| DAMAGED | Reduced effectiveness, visual damage |
| BURNED | Fire damage, wooden structures |
| RUINS | Major structural damage |
| DESTROYED | Non-functional |
| EXPLODED | Ammunition/fuel explosions |
| COLLAPSED | Structural collapse |
| CRATERED | Bomb/artillery damage |
