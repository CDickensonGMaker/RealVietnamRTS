# Construction System GDD

> **Status**: `[LIVING]`
> **Last Updated**: 2026-05-21
> **Source Documents**: GAME_BIBLE.md Section 10, PRD.md Section 10
> **Pillar**: 2 (Network of Firebases)

---

## 1. Overview

The construction system handles all building placement, construction progress, and engineer automation. Inside firebase influence radius, engineers auto-construct queued buildings. Outside the radius, players directly command engineer squads to build. Players use paint/drag tools for perimeter structures (sandbags, wire) and point-and-click for discrete buildings (bunkers, towers). Every structure requires supply to build and cleared terrain to place.

---

## 2. Player Fantasy

You design your firebase from the ground up. Paint sandbag walls to define your perimeter, place MG nests with overlapping fields of fire, position bunkers at the approaches. Engineers work automatically within the wire - you just queue what you want built. For forward positions outside the firebase, you command engineers directly, watching them work under fire to finish that critical bunker before the next attack.

---

## 3. Detailed Rules

### 3.1 Who Can Build What

| Builder | Inside Firebase Radius | Outside Firebase Radius |
|---------|------------------------|-------------------------|
| **Any Squad** | Sandbags, Foxholes, Wire | Sandbags, Foxholes, Wire |
| **Engineer Squad** | All buildings (auto-build) | All buildings (manual command) |
| **Bulldozer** | Roads, large clearing | Roads, large clearing |

### 3.2 Building Categories

**Perimeter Structures (Paint/Drag)**
- Sandbag Wall
- Wire Obstacle
- Triple Concertina
- Foxhole

**Discrete Buildings (Point-Click)**
- Bunker (all variants)
- MG Nest
- Mortar Pit
- Watchtower / Observation Tower
- Helipad
- Supply Depot
- Command Post / TOC
- Artillery Pit
- Tank Revetment

### 3.3 Terrain Requirements

| Terrain State | Can Build | Building Types |
|---------------|-----------|----------------|
| JUNGLE | No | None |
| PARTIALLY_CLEARED | Limited | Sandbags, Wire, Foxholes only |
| CLEARED | Yes | All buildings |
| FORTIFIED | Yes | All buildings + defense bonus |

### 3.4 Construction Stages

Every building progresses through four stages:

| Stage | % Complete | Visual | Function |
|-------|------------|--------|----------|
| FOUNDATION | 0-25% | Stakes, markers, outline | None |
| STRUCTURE | 25-50% | Framing, basic shape | None |
| FINISHING | 50-75% | Nearly complete | Partial (50% effectiveness) |
| COMPLETE | 75-100% | Finished | Full functionality |

### 3.5 Work Points System

Construction progress is measured in **work points**. Engineers contribute work points over time:

```
work_per_second = engineer_count * WORK_RATE_PER_ENGINEER
progress_percent = (accumulated_work / total_work_required) * 100
```

| Parameter | Value |
|-----------|-------|
| WORK_RATE_PER_ENGINEER | 1.0 work/second |
| Engineers per squad | 8 |
| Squad work rate | 8.0 work/second |

### 3.6 Engineer Behavior Under Fire

When engineers are under fire during construction:
1. **Pause construction** - Cannot work while suppressed
2. **Seek cover** - Move to nearest cover position
3. **Return fire** - If capable (limited combat effectiveness)
4. **Resume when safe** - Continue construction when suppression ends

### 3.7 Auto-Build (Inside Firebase Radius)

When inside firebase influence radius:
1. Player queues buildings via build menu
2. Available engineers auto-assigned to construction
3. Engineers path to build site automatically
4. Construction proceeds without player commands
5. On completion, engineers move to next queued building

### 3.8 Manual Build (Outside Firebase Radius)

When outside firebase influence radius:
1. Player selects engineer squad
2. Player gives explicit build command
3. Engineers move to location and build
4. Player must monitor progress and reassign

---

## 4. Building Data

### 4.1 Player-Constructible Buildings

| Building | Supply | Work Required | Work Stages | Function |
|----------|--------|---------------|-------------|----------|
| Sandbag Wall | 5 | 50 | [20, 20, 10] | Basic cover segment |
| Wire Obstacle | 10 | 40 | [15, 15, 10] | Slows 70%, 2 DPS |
| Triple Concertina | 15 | 55 | [20, 20, 15] | Slows 80%, 4 DPS |
| Foxhole | Free | 30 | [10, 10, 10] | Infantry fighting position |
| Bunker | 40 | 140 | [40, 60, 40] | Garrison 8, heavy cover |
| Sandbag Bunker | 25 | 85 | [25, 35, 25] | Garrison 4, partial cover |
| CONEX Bunker | 45 | 110 | [30, 50, 30] | Garrison 6, armored |
| MG Nest | 30 | 100 | [30, 40, 30] | Auto-fire 500m range |
| Mortar Pit | 35 | 110 | [30, 50, 30] | Indirect fire 3.5km |
| Watchtower | 25 | 100 | [30, 40, 30] | +60m sight, Garrison 2 |
| Observation Tower | 30 | 110 | [35, 45, 30] | +80m sight, 8m tall |
| Helipad | 50 | 130 | [40, 50, 40] | Landing zone |
| PSP Helipad | 60 | 145 | [45, 55, 45] | Reinforced, 15x15m |
| Ammo Bunker | 45 | 140 | [40, 60, 40] | Supply storage, explosive |
| Fuel Depot | 40 | 120 | [35, 50, 35] | Fuel storage, flammable |
| Medical Station | 35 | 110 | [30, 50, 30] | Heals wounded |
| Command Post | 80 | 200 | [60, 80, 60] | HQ building |
| TOC | 80 | 200 | [60, 80, 60] | +100m sight, HQ |
| Commo Bunker | 50 | 140 | [40, 60, 40] | Air support calls |
| Hootch | 20 | 70 | [20, 30, 20] | Living quarters |
| Mess Hall | 45 | 140 | [40, 60, 40] | Flammable |
| Artillery Pit | 100 | 220 | [60, 100, 60] | 105mm, 11km range |
| 155mm Howitzer Pit | 120 | 260 | [70, 120, 70] | 155mm, 14.6km range |
| Tank Revetment | 60 | 170 | [50, 70, 50] | Vehicle protection |

### 4.2 Terrain Modification

| Action | Tool | Work Required | Notes |
|--------|------|---------------|-------|
| Clear jungle (small) | Engineer det-cord | 60 work | ~8 seconds with squad |
| Clear jungle (large) | Bulldozer | 30 work | ~15 seconds |
| Cut road (100m) | Bulldozer | 180 work | ~90 seconds |
| Prepare LZ | Engineer or Bulldozer | 90 work | ~11 seconds |
| Repair cratered road | Engineer | 120 work | ~15 seconds |

---

## 5. Formulas

### 5.1 Construction Progress

```gdscript
func update_construction(delta: float) -> void:
    if is_under_fire or assigned_engineers == 0:
        return  # No progress while suppressed or unmanned

    var work_this_frame := assigned_engineers * WORK_RATE_PER_ENGINEER * delta
    accumulated_work += work_this_frame

    var progress := accumulated_work / total_work_required
    update_construction_stage(progress)

    if progress >= 1.0:
        complete_construction()
```

### 5.2 Construction Stage Determination

```gdscript
func update_construction_stage(progress: float) -> void:
    if progress < 0.25:
        current_stage = ConstructionStage.FOUNDATION
    elif progress < 0.50:
        current_stage = ConstructionStage.STRUCTURE
    elif progress < 0.75:
        current_stage = ConstructionStage.FINISHING
    else:
        current_stage = ConstructionStage.COMPLETE
```

### 5.3 Build Time Estimation

```gdscript
func estimate_build_time(building_type: BuildingType, engineer_count: int) -> float:
    var total_work := building_type.work_required
    var work_rate := engineer_count * WORK_RATE_PER_ENGINEER
    return total_work / work_rate  # seconds
```

### 5.4 Supply Check

```gdscript
func can_afford_building(building_type: BuildingType) -> bool:
    var firebase := get_nearest_firebase(build_position)
    if firebase == null:
        return false
    return firebase.supply_depot.current >= building_type.supply_cost
```

---

## 6. Edge Cases

### 6.1 Building Placement Collision
- Buildings cannot overlap
- Minimum spacing enforced (varies by building type)
- Placement preview shows valid/invalid

### 6.2 Engineer Death During Construction
- If all engineers die, construction pauses
- Progress is preserved
- New engineers can resume

### 6.3 Supply Depletion Mid-Build
- Construction continues if supply was deducted at start
- Supply is consumed when construction begins, not completes

### 6.4 Building Destruction During Construction
- Partial structures can be destroyed
- No refund of supply
- Must restart construction from 0%

### 6.5 Terrain State Change
- If terrain reverts (e.g., jungle regrowth - post-MVP), buildings remain
- New construction still requires cleared terrain

### 6.6 Queue Overflow
- Maximum 10 buildings in queue per firebase
- Additional commands rejected with notification

---

## 7. Dependencies

| System | Dependency Type | Notes |
|--------|-----------------|-------|
| **Terrain Clearing** | Required | Must clear before building |
| **Supply Logistics** | Required | Buildings cost supply |
| **Firebase System** | Required | Auto-build within radius |
| **Combat System** | Required | Suppression pauses construction |
| **Unit System** | Required | Engineer squads perform work |

---

## 8. Tuning Knobs

| Parameter | Default | Range | Notes |
|-----------|---------|-------|-------|
| `work_rate_per_engineer` | 1.0/sec | 0.5-2.0 | Individual engineer work rate |
| `max_build_queue` | 10 | 5-20 | Max queued buildings per firebase |
| `suppression_work_penalty` | 1.0 | 0.5-1.0 | Work multiplier when suppressed (1.0 = no work) |
| `partial_function_threshold` | 0.5 | 0.4-0.7 | Progress % for partial function |
| `placement_spacing_multiplier` | 1.2 | 1.0-1.5 | Min spacing as multiplier of building size |

---

## 9. Acceptance Criteria

### Core Functionality
- [ ] Players can place buildings via build menu
- [ ] Engineers auto-assign to construction inside firebase radius
- [ ] Engineers require direct commands outside firebase radius
- [ ] Construction progress advances based on engineer count
- [ ] Buildings transition through 4 visual stages

### Paint/Drag Tools
- [ ] Sandbags can be painted as continuous perimeter
- [ ] Wire obstacles can be dragged to define defensive lines
- [ ] Foxholes can be placed with click
- [ ] Visual preview shows placement before confirming

### Supply Integration
- [ ] Building placement checks supply availability
- [ ] Supply deducted when construction begins
- [ ] Insufficient supply shows warning
- [ ] Buildings cannot be placed without supply

### Combat Interaction
- [ ] Suppressed engineers stop construction
- [ ] Engineers seek cover when under fire
- [ ] Construction resumes when safe
- [ ] Partial buildings can be destroyed

### Auto-Build System
- [ ] Queue system for multiple buildings
- [ ] Engineers auto-path to next queued building
- [ ] Queue can be reordered/cancelled
- [ ] Visual indicator of queue status

### Visual Feedback
- [ ] Construction progress bar on building
- [ ] Stage-appropriate visual model
- [ ] Engineer working animation
- [ ] Completion notification

---

## Build Menu Organization

**Category: Perimeter**
- Sandbag Wall (drag)
- Wire Obstacle (drag)
- Triple Concertina (drag)
- Foxhole (click)

**Category: Defensive**
- Bunker
- Sandbag Bunker
- CONEX Bunker
- MG Nest
- Mortar Pit
- Watchtower
- Observation Tower

**Category: Logistics**
- Helipad
- PSP Helipad
- Ammo Bunker
- Fuel Depot
- Supply Depot

**Category: Command**
- Command Post
- TOC
- Commo Bunker
- Medical Station

**Category: Living**
- Hootch
- Mess Hall

**Category: Heavy** (Doctrine-restricted)
- Artillery Pit
- 155mm Howitzer Pit
- Tank Revetment
