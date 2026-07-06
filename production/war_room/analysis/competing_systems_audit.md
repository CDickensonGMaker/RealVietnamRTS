# Competing Systems Audit Report

**Date:** 2026-05-28
**Auditor:** Code Analysis Agent
**Scope:** AI, Terrain, Units, Construction, Combat

---

## Executive Summary

This audit identifies **competing systems** across 5 domains in RealVietnamRTS. Overall, the codebase shows **good architecture discipline** with clear role documentation in most areas. The primary issues are:

1. **Terrain Domain**: Well-resolved - UnifiedTerrainEngine clearly wins, TerrainEngine is legacy
2. **Clearing Domain**: Well-resolved - ClearingSystem is authoritative, TerrainClearingSystem is a thin forwarder
3. **AI Domain**: Well-layered - No competition, complementary systems (Controllers + BehaviorTrees + UtilityScorers)
4. **Construction Domain**: Well-documented - Clear role separation between ConstructionManager, JobSystem, WorkerController
5. **Combat Domain**: Well-separated - CombatManager handles combat resolution, DamageSystem handles terrain deformation

**Verdict: No critical competing system issues found. Architecture is sound.**

---

## Domain 1: AI Systems

### Systems Identified

| System | File | Purpose |
|--------|------|---------|
| `EnemyAIController` | `battle_system/ai/enemy_ai_controller.gd` | Base AI controller with wave spawning, basic behaviors |
| `VCController` | `battle_system/ai/vc_controller.gd` | VC-specific AI (extends EnemyAIController) |
| `NVAController` | `battle_system/ai/nva_controller.gd` | NVA-specific AI (extends EnemyAIController) |
| `BehaviorTree` | `battle_system/ai/behavior_tree/behavior_tree.gd` | Behavior tree framework |
| `UtilityScorer` | `battle_system/ai/utility/utility_scorer.gd` | Utility-based decision scoring |
| `SquadBehaviors` | `battle_system/ai/squad_behaviors.gd` | Squad behavior presets using BT |

### Competition Analysis: **NONE - Well-Layered**

The AI systems are **complementary, not competing**:

```
Layer 1: EnemyAIController (base)
    |
    +-- VCController (guerrilla specialization)
    +-- NVAController (conventional specialization)
        |
        Uses: BehaviorTree + UtilityScorer for decisions
              SquadBehaviors for preset behaviors
```

**Inheritance is clean:**
- `VCController extends EnemyAIController` (line 1)
- `NVAController extends EnemyAIController` (line 1)

**Role Separation:**
- Controllers handle faction-specific state machines and wave management
- BehaviorTree handles individual unit decision-making
- UtilityScorer handles option evaluation
- SquadBehaviors provides preset behavior tree factories

### Recommendation: **NO ACTION REQUIRED**

The AI architecture is well-designed with clear responsibilities.

---

## Domain 2: Terrain Systems

### Systems Identified

| System | File | Purpose | LOC |
|--------|------|---------|-----|
| `TerrainEngine` | `terrain/core/terrain_engine.gd` | Heightmap generation (noise, erosion) | 763 |
| `UnifiedTerrainEngine` | `terrain/core/unified_terrain_engine.gd` | Single source of truth for terrain data | 748 |

### Competition Analysis: **RESOLVED - UnifiedTerrainEngine Wins**

The documentation in `UnifiedTerrainEngine` is explicit (lines 1-13):

```gdscript
## UnifiedTerrainEngine - THE single source of truth for all terrain data.
##
## Key differences from old system:
##   1. grid_to_world() returns ACTUAL Y values (samples heightmap)
##   2. modify_terrain() syncs BOTH heightmap AND gameplay grid
##   3. Vegetation clearing emits signals with instance info for actual removal
##
## Merges functionality from:
##   - HeightmapStorage (2m resolution for mesh generation)
##   - TerrainGrid (4m resolution for gameplay queries)
##   - Vegetation instance tracking
```

**TerrainEngine Role:**
- Procedural heightmap GENERATION (noise algorithms, erosion simulation)
- Outputs to HeightmapStorage which feeds UnifiedTerrainEngine

**UnifiedTerrainEngine Role:**
- Runtime queries and modification
- Coordinate conversion with actual Y values
- Clearing stage tracking
- Building footprint validation

**Integration Point:**
```gdscript
# UnifiedTerrainEngine receives heightmap from TerrainEngine
func init_from_heightmap(heightmap: HeightmapStorageClass) -> void:
    _heightmap = heightmap
    _build_gameplay_grid_from_heightmap()
```

### Recommendation: **DOCUMENT THE PIPELINE**

Add a comment to TerrainEngine clarifying:
```gdscript
## TerrainEngine - Procedural heightmap GENERATION
## Outputs: HeightmapStorage -> fed to UnifiedTerrainEngine for runtime
## DO NOT use for runtime queries - use UnifiedTerrainEngine instead
```

---

## Domain 3: Clearing Systems

### Systems Identified

| System | File | Purpose | LOC |
|--------|------|---------|-----|
| `ClearingSystem` | `terrain/systems/clearing_system.gd` | Zone-based clearing management | 376 |
| `TerrainClearingSystem` | `firebase_system/terrain_clearing.gd` | Thin forwarder (autoload) | 130 |

### Competition Analysis: **RESOLVED - ClearingSystem is Authoritative**

`TerrainClearingSystem` explicitly documents its role (lines 1-6):

```gdscript
## TerrainClearingSystem - Autoload singleton
## Access via: TerrainClearingSystem.is_cleared(pos)
##
## Thin forwarder to ClearingSystem autoload.
## Per ARCHITECTURE.md: NO duplicate state - all queries go to ClearingSystem.
```

**Delegation Pattern:**
```gdscript
func is_cleared(position: Vector3) -> bool:
    if is_instance_valid(ClearingSystem):
        return ClearingSystem.is_position_cleared(position)
    return false
```

**Signal Forwarding:**
```gdscript
func _ready() -> void:
    if is_instance_valid(ClearingSystem):
        ClearingSystem.clearing_started.connect(_on_clearing_started)
        ClearingSystem.clearing_progress.connect(_on_clearing_progress)
        ClearingSystem.clearing_completed.connect(_on_clearing_completed)
```

**Why Both Exist:**
- `ClearingSystem` is the implementation (handles zones, stage progression)
- `TerrainClearingSystem` is the public API facade (backward compatibility, signal signature adaptation)

### Recommendation: **NO ACTION REQUIRED**

The pattern is intentional and well-documented. TerrainClearingSystem adapts zone_id-based signals to position-based signals for consumers.

---

## Domain 4: Construction Systems

### Systems Identified

| System | File | Purpose | LOC |
|--------|------|---------|-----|
| `ConstructionManager` | `firebase_system/construction_manager.gd` | Firebase building slots (ConstructionZone) | 792 |
| `JobSystem` | `firebase_system/job_system/job_system.gd` | Job creation/tracking/completion | 1875 |

### Competition Analysis: **RESOLVED - Clear Role Documentation**

`ConstructionManager` has explicit role clarification (lines 5-12):

```gdscript
## ROLE CLARIFICATION (2026-05-19):
## - ConstructionManager handles ConstructionZone system (firebase building slots)
## - JobSystem handles clearing/building jobs via WorkerController
## - Worker assignment handled by WorkerController (bottom-up job finding)
##
## This manager does NOT directly assign workers or manage job queues.
## Those responsibilities belong to JobSystem and WorkerController.
```

`JobSystem` also declares authority (lines 1-5):

```gdscript
## JobSystem - Single Authoritative Job Manager
## Replaces: JobManager + BuilderAI job management + ConstructionManager job parts
##
## KEY PRINCIPLE: This is the ONLY system that creates, tracks, and manages jobs.
## Workers find jobs via heuristic scoring (bottom-up), not assigned by manager (top-down).
```

**Responsibility Matrix:**

| Concern | Owner |
|---------|-------|
| Firebase level/upgrade logic | ConstructionManager |
| ConstructionZone slot management | ConstructionManager |
| Building slot validation | ConstructionManager |
| Job creation (CLEAR_TERRAIN, BUILD, TRENCH) | JobSystem |
| Job tracking and completion | JobSystem |
| Worker-to-job matching | WorkerController (bottom-up) |
| Visual job nodes (ClearingZoneNode, etc.) | JobSystem creates, workers interact |

### Recommendation: **NO ACTION REQUIRED**

The role clarification comments are excellent. Both systems have non-overlapping responsibilities.

---

## Domain 5: Combat / Damage Systems

### Systems Identified

| System | File | Purpose | LOC |
|--------|------|---------|-----|
| `CombatManager` | `battle_system/systems/combat_manager.gd` | Combat resolution, weapon firing, suppression | 687 |
| `DamageSystem` | `terrain/systems/damage_system.gd` | Terrain deformation, craters, scar decals | 417 |

### Competition Analysis: **NO COMPETITION - Different Domains**

**CombatManager handles:**
- Weapon firing and projectiles
- Hit chance calculation
- Damage resolution (unit health)
- Suppression mechanics
- Ammo consumption
- Artillery/napalm strikes

**DamageSystem handles:**
- Terrain heightmap deformation
- Crater creation (depress heightmap)
- Visual scar decals
- Vegetation clearing on explosion
- Crater cover system (Men of War style)

**Integration Point:**
CombatManager calls DamageSystem for terrain effects:

```gdscript
# In CombatManager, artillery/napalm strikes would trigger:
# DamageSystem.apply_damage(position, DamageType.MEDIUM_EXPLOSION)
```

**Naming Consideration:**
The name "DamageSystem" could be confusing since it sounds like it handles unit damage. Consider renaming to `TerrainDamageSystem` or `CraterSystem` for clarity.

### Recommendation: **CONSIDER RENAME**

```gdscript
# Current: DamageSystem
# Proposed: TerrainDamageSystem or CraterSystem
```

This would make the separation crystal clear: CombatManager = unit damage, TerrainDamageSystem = terrain damage.

---

## Unit Management Systems

### Systems Identified

| System | File | Purpose |
|--------|------|---------|
| `SelectionManager` | `battle_system/systems/selection_manager.gd` | Click/drag/control group selection |
| `SpatialHashGrid` | Autoload | Efficient unit queries by position |

### Competition Analysis: **NO COMPETITION**

`SelectionManager` is the sole selection system handling:
- Click selection (single unit)
- Drag-box selection (multiple units)
- Control groups (0-9 hotkeys)
- Double-click select-all-of-type

`SpatialHashGrid` is orthogonal - provides efficient spatial queries for:
- Finding units in radius
- Finding enemies/friendlies near position
- Combat range checks

### Recommendation: **NO ACTION REQUIRED**

---

## Summary of Recommendations

| Domain | Status | Action |
|--------|--------|--------|
| AI Systems | Clean | None |
| Terrain Systems | Clean | Add clarifying comment to TerrainEngine |
| Clearing Systems | Clean | None |
| Construction Systems | Clean | None |
| Combat/Damage | Clean | Consider renaming DamageSystem to TerrainDamageSystem |
| Unit Management | Clean | None |

### Priority Actions

1. **(Optional) Rename DamageSystem** - Low priority, cosmetic clarity improvement
2. **(Optional) Document TerrainEngine role** - Add comment noting it's generation-only

### Architecture Strengths Observed

1. **Explicit role documentation** - JobSystem and ConstructionManager have dated role clarification comments
2. **Single source of truth patterns** - UnifiedTerrainEngine explicitly claims authority
3. **Thin forwarder pattern** - TerrainClearingSystem properly delegates without duplicating state
4. **Clean inheritance** - VCController/NVAController extend EnemyAIController correctly
5. **Complementary systems** - BehaviorTree + UtilityScorer work together, not against each other

---

## Files Analyzed

```
C:\Users\caleb\RealVietnamRTS\battle_system\ai\enemy_ai_controller.gd
C:\Users\caleb\RealVietnamRTS\battle_system\ai\vc_controller.gd
C:\Users\caleb\RealVietnamRTS\battle_system\ai\nva_controller.gd
C:\Users\caleb\RealVietnamRTS\battle_system\ai\behavior_tree\behavior_tree.gd
C:\Users\caleb\RealVietnamRTS\battle_system\ai\utility\utility_scorer.gd
C:\Users\caleb\RealVietnamRTS\battle_system\ai\squad_behaviors.gd
C:\Users\caleb\RealVietnamRTS\terrain\core\terrain_engine.gd
C:\Users\caleb\RealVietnamRTS\terrain\core\unified_terrain_engine.gd
C:\Users\caleb\RealVietnamRTS\terrain\systems\clearing_system.gd
C:\Users\caleb\RealVietnamRTS\firebase_system\terrain_clearing.gd
C:\Users\caleb\RealVietnamRTS\terrain\systems\damage_system.gd
C:\Users\caleb\RealVietnamRTS\battle_system\systems\combat_manager.gd
C:\Users\caleb\RealVietnamRTS\firebase_system\construction_manager.gd
C:\Users\caleb\RealVietnamRTS\firebase_system\job_system\job_system.gd
C:\Users\caleb\RealVietnamRTS\battle_system\systems\selection_manager.gd
```
