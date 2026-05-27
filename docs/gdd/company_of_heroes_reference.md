# Company of Heroes 1 Design Reference

**Purpose:** War-room reference document for RealVietnamRTS agents. Documents CoH1 mechanics relevant to our pillars with implementation guidance.

**Last Updated:** 2026-05-25

---

## Table of Contents

1. [Doctrine System & Tech Trees](#1-doctrine-system--tech-trees)
2. [Building Placement System](#2-building-placement-system)
3. [Dynamic Cover System](#3-dynamic-cover-system)
4. [Suppression Mechanics](#4-suppression-mechanics)
5. [Garrison System](#5-garrison-system)
6. [Territory Control (Reference Only)](#6-territory-control-reference-only)
7. [RealVietnamRTS Implementation Guide](#7-realvietnamrts-implementation-guide)

---

## 1. Doctrine System & Tech Trees

### 1.1 Command Point Accumulation

CoH1 uses **Command Points (CP)** as a meta-progression currency earned during battle:

| CP Source | Amount | Notes |
|-----------|--------|-------|
| Time passage | 1 CP / ~2 min | Baseline accumulation |
| Enemy units killed | Variable | Scales with unit value |
| Territory captured | Small bonus | Encourages aggression |
| Veterancy gains | Small bonus | Rewards preservation |

**Design Lesson:** CP creates a "second clock" alongside resources. Even a losing player accumulates CP, ensuring access to late-game abilities.

### 1.2 Doctrine Selection

Each faction has **3 doctrines** (called "Companies" for US, "Doctrines" for Wehrmacht):

**US Army Doctrines:**
| Doctrine | Theme | Key Unlocks |
|----------|-------|-------------|
| Infantry Company | Elite infantry, off-map support | Rangers, artillery barrage |
| Airborne Company | Paratroopers, air power | Paradrop, P-47 strafing run |
| Armor Company | Tank superiority | Calliope, tank crew abilities |

**Wehrmacht Doctrines:**
| Doctrine | Theme | Key Unlocks |
|----------|-------|-------------|
| Defensive Doctrine | Fortifications, AT | For the Fatherland!, 88mm flak |
| Blitzkrieg Doctrine | Speed, aggression | Stormtroopers, Tiger Ace |
| Terror Doctrine | Suppression, fear | Propaganda War, V1 rocket |

### 1.3 Doctrine Tree Structure

Each doctrine has a **branching tree** with 3-4 tiers:

```
Tier 1 (1-2 CP)     Tier 2 (2-4 CP)     Tier 3 (4-6 CP)     Tier 4 (6-8 CP)
    [A]                 [C]                 [E]                 [G]
     |                   |                   |
    [B]                 [D]                 [F]
```

**Rules:**
- Must unlock Tier N before accessing Tier N+1
- Some branches are mutually exclusive (pick A OR B)
- Some abilities are one-time purchases, others are repeatable call-ins
- Unlocks persist for the match duration

### 1.4 Unlock Categories

| Category | Examples | Behavior |
|----------|----------|----------|
| **Passive Abilities** | Veterancy bonuses, sight range | Always active once unlocked |
| **Active Abilities** | Artillery barrage, strafing run | Cooldown-based, costs munitions |
| **Unit Unlocks** | Rangers, Tiger tank | Adds unit to production queue |
| **Global Upgrades** | Shared veterancy | Affects all existing units |

### 1.5 RealVietnamRTS Doctrine Adaptation

Our doctrine system (per Game Bible D-105) differs:
- **Pre-mission selection** (not mid-battle unlocking)
- **Cards unlock units AND required buildings**
- **No CP system** - doctrine is fixed at mission start

**What to borrow:**
- Doctrine themes that change playstyle (Air Cav vs Mechanized)
- Mutually exclusive choices that force meaningful tradeoffs
- Passive bonuses tied to doctrine identity

**What to skip:**
- Mid-battle CP accumulation (conflicts with "Doctrine Over Spam" pillar)
- Purchasable call-in abilities (we use cooldown-based air support instead)

---

## 2. Building Placement System

### 2.1 Buildable Zones

CoH1 restricts base buildings to the **HQ sector**:

| Zone Type | What Can Build | Restrictions |
|-----------|----------------|--------------|
| HQ Sector | All base buildings | Limited footprint, strategic placement |
| Owned Territory | Defensive structures only | Sandbags, wire, mines, bunkers |
| Enemy/Neutral | Nothing | Must capture first |

**Design Lesson:** Constraining where buildings can go creates meaningful layout decisions.

### 2.2 Spacing & Snapping

**Grid-Based Placement:**
- Buildings snap to an invisible grid (approximately 4m cells)
- Prevents overlapping structures
- Ensures pathfinding clearance

**Collision Rules:**
| Check | Behavior |
|-------|----------|
| Building-to-building | Minimum gap enforced |
| Building-to-terrain | Must be on valid ground |
| Building-to-road | Roads must remain passable |
| Building-to-resource | Cannot block capture points |

**Visual Feedback:**
- Green ghost = valid placement
- Red ghost = invalid placement
- Rotation via scroll wheel or hotkey

### 2.3 Linear Structure Placement (Wire, Sandbags)

For drag-to-place structures:

1. Click start point
2. Drag to end point (preview shows length)
3. Release to confirm
4. Engineers walk the line, building segments

**Segment Logic:**
```
Total Length = distance(start, end)
Segment Count = ceil(Total Length / SEGMENT_SIZE)
Build Time = Segment Count * TIME_PER_SEGMENT
```

### 2.4 Build Queue & Priority

- Engineers can queue multiple build orders (Shift+click)
- Nearest engineer auto-assigned to new build jobs
- Multiple engineers on same structure = faster completion
- Damaged structures can be repaired by any engineer

---

## 3. Dynamic Cover System

### 3.1 CoH1 Cover Model

CoH1 uses a **3-tier** cover system:

| Cover Level | Icon | Damage Reduction | Accuracy Penalty to Attacker |
|-------------|------|------------------|------------------------------|
| **Negative** | Red shield | +25% damage taken | None |
| **None** | No icon | 0% | None |
| **Light (Yellow)** | Yellow shield | -25% damage | -25% accuracy |
| **Heavy (Green)** | Green shield | -50% damage | -50% accuracy |

**Cover Sources:**
| Source | Cover Level | Notes |
|--------|-------------|-------|
| Craters | Heavy | Created by explosions |
| Sandbags | Heavy | Player-built |
| Stone walls | Heavy | Map feature |
| Hedgerows | Light | Can be destroyed |
| Wooden fences | Light | Easily destroyed |
| Wrecked vehicles | Heavy | Persistent battlefield debris |
| Building walls | Heavy | Directional |

### 3.2 Directional Cover

Cover in CoH1 is **directional**:
- Unit must be facing cover OR cover must be between unit and attacker
- Flanking bypasses cover bonuses
- Promotes tactical maneuvering

```
     Enemy
       |
       v
   [COVER]  <-- Cover blocks shots from this direction
       |
     Unit (protected)

vs.

   Enemy -----> Unit (flanked, no cover bonus)
                 |
              [COVER] (wrong side)
```

### 3.3 RealVietnamRTS 4-Tier Cover System

**Proposed tiers for our game:**

| Tier | Name | Damage Reduction | Stealth Bonus | Examples |
|------|------|------------------|---------------|----------|
| 0 | **Terrible** | 0% | +10% | Tall grass, rice paddies (standing) |
| 1 | **Light** | 25% | +25% | Bamboo thickets, wooden fences, foxholes |
| 2 | **Good** | 50% | +40% | Shell craters, sandbags, stone walls |
| 3 | **Heavy** | 75% | +60% | Bunkers, concrete, building interiors |

**Key Difference from CoH1:** We add **Terrible** cover for concealment-only terrain (tall grass hides you but doesn't stop bullets).

### 3.4 Dynamic Cover from Terrain Deformation

**Crater Generation:**
| Explosion Source | Crater Size | Cover Level |
|------------------|-------------|-------------|
| Grenade/mortar | Small (2m) | Good |
| Artillery shell | Medium (4m) | Good |
| Bomb/napalm | Large (6m) | Heavy (rim) / Terrible (center, burned) |
| B-52 Arc Light | Massive (10m+) | Heavy (rim) / None (center, moonscape) |

**Implementation Concept:**
```gdscript
# When explosion occurs
func create_crater(position: Vector3, radius: float, explosion_type: int) -> void:
    # Deform terrain heightmap
    terrain_engine.deform_crater(position, radius, CRATER_DEPTH)

    # Add cover zone
    var cover_zone := CoverZone.new()
    cover_zone.position = position
    cover_zone.radius = radius
    cover_zone.cover_level = _get_crater_cover(explosion_type)
    cover_zone.is_dynamic = true
    CoverSystem.register_zone(cover_zone)

    # Craters persist for mission duration
    persistent_craters.append(cover_zone)

func _get_crater_cover(explosion_type: int) -> int:
    match explosion_type:
        ExplosionType.GRENADE, ExplosionType.MORTAR:
            return CoverLevel.GOOD
        ExplosionType.ARTILLERY:
            return CoverLevel.GOOD
        ExplosionType.BOMB:
            return CoverLevel.HEAVY  # Rim provides excellent cover
        _:
            return CoverLevel.LIGHT
```

### 3.5 Vegetation as Concealment vs. Cover

**Critical Distinction:**

| Terrain | Concealment (Stealth) | Cover (Damage Reduction) |
|---------|----------------------|-------------------------|
| Tall elephant grass | High | Terrible (0%) |
| Bamboo thicket | High | Light (25%) |
| Dense jungle | Very High | Light-Good (25-50%) |
| Triple canopy | Maximum | Good (50%) |
| Cleared jungle | None | None |

**Design Principle:** Grass hides you until you shoot. Then it provides zero protection from return fire. This creates asymmetric ambush dynamics perfect for Vietnam.

```gdscript
# Vegetation cover calculation
func get_vegetation_cover(unit: Node3D, attacker: Node3D) -> Dictionary:
    var vegetation_type := terrain.get_vegetation_at(unit.position)

    return {
        "concealment": VEGETATION_CONCEALMENT[vegetation_type],
        "cover": VEGETATION_COVER[vegetation_type],
        "revealed_on_fire": vegetation_type in [VegType.GRASS, VegType.BAMBOO]
    }
```

---

## 4. Suppression Mechanics

### 4.1 CoH1 Suppression Model

**Suppression** is accumulated damage to unit morale, separate from HP:

| Suppression State | Icon | Effects |
|-------------------|------|---------|
| **Normal** | None | Full accuracy, full speed |
| **Suppressed** | Yellow | -50% accuracy, -50% speed, seeks cover |
| **Pinned** | Red | Cannot move, cannot fire, -75% accuracy if forced |

**Suppression Sources:**
| Weapon Type | Suppression per Hit | Notes |
|-------------|---------------------|-------|
| Rifle | Low (2-5) | Accumulated over time |
| SMG | Very Low (1-2) | Close range only |
| MG | High (15-25) | Primary suppression tool |
| Mortar | Very High (30-50) | Area suppression |
| Tank MG | High (15-20) | Continuous fire |
| Tank cannon | Extreme (50+) | Instant pin on near-miss |

### 4.2 Suppression Accumulation & Decay

```
Suppression Formula:
  Current Suppression += Incoming Suppression * (1 - Cover Modifier)

  If Current Suppression > SUPPRESS_THRESHOLD (50):
    State = SUPPRESSED
  If Current Suppression > PIN_THRESHOLD (100):
    State = PINNED

Decay Formula (per second):
  If in cover: Suppression -= 5/sec
  If in open: Suppression -= 2/sec
  If moving: Suppression -= 1/sec (slower recovery)
```

### 4.3 Breaking Suppression

| Method | Effectiveness | Risk |
|--------|---------------|------|
| Wait in cover | Slow but safe | Enemy can flank |
| Retreat | Immediate but loses ground | Vulnerable during retreat |
| Smoke | Blocks LOS, resets engagement | Costs munitions |
| Counter-suppression | Kill the MG | Requires other units |
| Flank | Bypass suppression arc | Risky movement |

### 4.4 MG Suppression Arcs

MGs have a **fixed firing arc** (typically 60-90 degrees):

```
                    MG
                   /  \
                  /    \
                 /      \
                /  ARC   \
               /   60°    \
              /__________\

Units in arc = suppressed
Units outside arc = safe approach
```

**Tactical Implications:**
- Flanking MGs is the primary counter
- Multiple MGs with overlapping arcs create kill zones
- MGs must "set up" before firing (deploy time)

### 4.5 RealVietnamRTS Suppression Adaptation

Our suppression system should emphasize:

1. **MG dominance** - M60 and M2 .50cal as primary suppression tools
2. **Mortar area suppression** - 60mm and 81mm for zone denial
3. **Jungle ambush dynamics** - First shots from concealment don't suppress (attacker doesn't know where fire is coming from)
4. **Training level affects recovery** - Elite units recover faster (per Game Bible)

```gdscript
# Suppression with training modifier
func apply_suppression(unit: Node3D, amount: float, source: Node3D) -> void:
    var cover_mod := CoverSystem.get_cover_modifier(unit, source)
    var training_mod := _get_training_resistance(unit.training_level)

    var final_suppression := amount * (1.0 - cover_mod) * training_mod
    unit.current_suppression += final_suppression

    _update_suppression_state(unit)

func _get_training_resistance(level: int) -> float:
    # Higher training = more suppression resistance
    match level:
        TrainingLevel.CONSCRIPT: return 1.2  # Takes MORE suppression
        TrainingLevel.REGULAR: return 1.0
        TrainingLevel.VETERAN: return 0.85
        TrainingLevel.ELITE: return 0.7  # Takes LESS suppression
        _: return 1.0
```

---

## 5. Garrison System

### 5.1 CoH1 Garrison Rules

**Garrisonable Structures:**
| Structure Type | Capacity | Fire Points | Notes |
|----------------|----------|-------------|-------|
| Small building | 1 squad | 4 | Windows on each side |
| Medium building | 2 squads | 6 | Better coverage |
| Large building | 3 squads | 8 | Major strongpoint |
| Bunker | 1 squad | 2-4 | Player-built, upgradeable |
| Trench | 2 squads | Continuous | Linear garrison |

### 5.2 Garrison Mechanics

**Entering:**
- Right-click building with infantry selected
- Squad runs to nearest entrance
- ~2 second enter animation
- Squad becomes "inside" and invisible

**Firing:**
- Soldiers auto-assign to fire points (windows/slots)
- Can only fire in direction of their fire point
- Heavy weapons (MG) get priority fire points
- Grenades can be thrown from garrison

**Benefits:**
| Benefit | Value |
|---------|-------|
| Cover | Heavy (green) from all directions |
| Protection | Building absorbs damage first |
| Elevation | +sight range, +accuracy |

**Vulnerabilities:**
| Threat | Effect |
|--------|--------|
| Flamethrower | Massive damage, forces evacuation |
| Satchel charge | Building destruction |
| Artillery | Building collapse kills all inside |
| Tank cannon | Penetrates walls, kills inside |

### 5.3 Exiting Garrison

**Voluntary Exit:**
- Order squad to move outside
- Exit from nearest door to destination
- Brief vulnerability during exit animation

**Forced Exit:**
- Building destroyed = all units die
- Building on fire = forced evacuation (units take damage)
- Flamethrower = panic evacuation

### 5.4 RealVietnamRTS Garrison Implementation

```gdscript
class_name GarrisonableStructure extends BaseStructure

@export var max_squads: int = 2
@export var fire_positions: Array[Marker3D] = []
@export var entry_points: Array[Marker3D] = []

var garrisoned_squads: Array[Node3D] = []

signal squad_entered(squad: Node3D)
signal squad_exited(squad: Node3D)
signal garrison_destroyed

func can_garrison(squad: Node3D) -> bool:
    if garrisoned_squads.size() >= max_squads:
        return false
    if not squad.is_in_group("infantry"):
        return false
    if squad.faction != self.faction and self.faction != GameEnums.Faction.NEUTRAL:
        return false
    return true

func enter_garrison(squad: Node3D) -> void:
    if not can_garrison(squad):
        return

    garrisoned_squads.append(squad)
    squad.set_garrison(self)
    squad.visible = false
    _assign_fire_positions(squad)
    squad_entered.emit(squad)

func exit_garrison(squad: Node3D, exit_position: Vector3) -> void:
    if squad not in garrisoned_squads:
        return

    var exit_point := _get_nearest_exit(exit_position)
    garrisoned_squads.erase(squad)
    squad.clear_garrison()
    squad.global_position = exit_point.global_position
    squad.visible = true
    _release_fire_positions(squad)
    squad_exited.emit(squad)

func _on_structure_destroyed() -> void:
    # All garrisoned units die
    for squad in garrisoned_squads:
        squad.take_lethal_damage("garrison_collapse")
    garrisoned_squads.clear()
    garrison_destroyed.emit()

func _assign_fire_positions(squad: Node3D) -> void:
    var soldiers := squad.get_soldiers()
    var available_positions := fire_positions.filter(
        func(pos): return not pos.has_meta("assigned")
    )

    for i in mini(soldiers.size(), available_positions.size()):
        available_positions[i].set_meta("assigned", soldiers[i])
        soldiers[i].fire_position = available_positions[i]
```

### 5.5 Fire Position Arcs

Each fire position has a limited arc:

```gdscript
class_name FirePosition extends Marker3D

@export var arc_degrees: float = 90.0
@export var arc_direction: Vector3 = Vector3.FORWARD

func can_fire_at(target: Vector3) -> bool:
    var to_target := (target - global_position).normalized()
    var forward := global_transform.basis * arc_direction
    var angle := rad_to_deg(forward.angle_to(to_target))
    return angle <= arc_degrees / 2.0
```

---

## 6. Territory Control (Reference Only)

> **Note:** Per user request, we're documenting CoH1's capture points for reference but NOT implementing resource-generating points. Our logistics system handles resources differently.

### 6.1 CoH1 Capture Point System

**Point Types:**
| Point | Resource | Capture Time |
|-------|----------|--------------|
| Strategic Point | +5 Manpower | 30 sec |
| Fuel Point | +10 Fuel | 45 sec |
| Munitions Point | +10 Munitions | 45 sec |
| Victory Point | Win condition | 60 sec |

### 6.2 Potential Use for RealVietnamRTS

If we use capture points, they would provide **map control only**:

| Point Type | Effect | No Effect |
|------------|--------|-----------|
| Observation Post | +Sight range in area | No resources |
| Road Junction | Enables convoy routing | No resources |
| LZ Site | Enables helicopter landing | No resources |
| Village | Denies VC staging | No resources |

**Resources come from supply chain (Pillar 3), not capture points.**

---

## 7. RealVietnamRTS Implementation Guide

### 7.1 Priority Implementation Order

Based on Game Bible pillars, implement in this order:

| Priority | System | Pillar Served |
|----------|--------|---------------|
| 1 | Dynamic Cover (4-tier) | Pillar 2 (Firebase defense) |
| 2 | Suppression | Pillar 2, 5 (Auto-defense) |
| 3 | Garrison | Pillar 2 (Bunkers matter) |
| 4 | Building Placement | Pillar 2 (Paint/drag perimeter) |
| 5 | Doctrine Passives | Pillar 4 (Force composition) |

### 7.2 Cover System Implementation Checklist

- [ ] Define 4 cover tiers in GameEnums
- [ ] Create CoverZone resource type
- [ ] Implement directional cover calculation
- [ ] Hook crater generation to cover zone creation
- [ ] Add vegetation concealment vs. cover distinction
- [ ] Integrate with combat damage calculation
- [ ] Add visual indicators (cover icons like CoH)

### 7.3 Suppression System Checklist

- [ ] Add suppression property to squad base class
- [ ] Define suppression thresholds (suppressed/pinned)
- [ ] Implement per-weapon suppression values
- [ ] Add training-based recovery rates
- [ ] Implement MG arc suppression zones
- [ ] Add behavior changes for suppressed/pinned states
- [ ] Create suppression recovery in cover

### 7.4 Garrison System Checklist

- [ ] Create GarrisonableStructure base class
- [ ] Define fire positions in bunker/building scenes
- [ ] Implement enter/exit animations
- [ ] Add garrison damage reduction
- [ ] Implement flamethrower/satchel vulnerabilities
- [ ] Wire garrison state to combat targeting

### 7.5 Key Constants to Define

```gdscript
# cover_constants.gd
const COVER_DAMAGE_REDUCTION := {
    CoverLevel.TERRIBLE: 0.0,
    CoverLevel.LIGHT: 0.25,
    CoverLevel.GOOD: 0.50,
    CoverLevel.HEAVY: 0.75,
}

const COVER_STEALTH_BONUS := {
    CoverLevel.TERRIBLE: 0.10,
    CoverLevel.LIGHT: 0.25,
    CoverLevel.GOOD: 0.40,
    CoverLevel.HEAVY: 0.60,
}

# suppression_constants.gd
const SUPPRESS_THRESHOLD := 50.0
const PIN_THRESHOLD := 100.0
const MAX_SUPPRESSION := 150.0

const SUPPRESSION_DECAY := {
    "in_cover": 5.0,
    "in_open": 2.0,
    "moving": 1.0,
}

const WEAPON_SUPPRESSION := {
    "M16": 3.0,
    "M60": 20.0,
    "M2_50cal": 25.0,
    "81mm_mortar": 40.0,
    "AK47": 4.0,
    "RPD": 18.0,
}
```

---

## Summary: What to Borrow vs. Skip

### Borrow from CoH1

| Mechanic | Why |
|----------|-----|
| Directional cover system | Rewards flanking, tactical depth |
| Suppression with thresholds | Creates MG value, squad preservation |
| Garrison mechanics | Bunkers become meaningful strongpoints |
| Building placement grids | Clean placement UX |
| Crater-as-cover | Dynamic battlefield evolution |

### Skip from CoH1

| Mechanic | Why |
|----------|-----|
| Resource-generating capture points | Conflicts with Pillar 3 (physical supply) |
| Mid-battle doctrine unlocks | Conflicts with Pillar 4 (pre-mission deck) |
| Fast unit production | Conflicts with Pillar 4 (reinforcement timing) |
| Small map scale | We need multi-firebase networks |

---

*End of document. For Eugen Systems reference, see `eugen_systems_reference.md`.*
