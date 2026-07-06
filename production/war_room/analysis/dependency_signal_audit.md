# Dependency and Signal Audit Report
**Date:** 2026-05-28
**Scope:** RealVietnamRTS Codebase

---

## Executive Summary

This audit identifies **dependency issues**, **signal problems**, and **god objects** in the RealVietnamRTS codebase. Key findings:

| Category | Issues Found | Severity |
|----------|--------------|----------|
| Autoload Order Dependencies | 3 | Medium |
| Orphaned Signals | 14 | Low |
| Tight Coupling | 5 | Medium |
| God Objects | 5 | High |
| Circular Dependencies | 0 | - |

---

## 1. Autoload Dependency Analysis

### Autoload Order (from project.godot - ACTUAL)

```
 1. GameEnums          - No dependencies (pure enums)
 2. BattleSignals      - No dependencies (pure signals)
 3. JobSystem          - Depends on: BattleSignals, SupplyManager (25), ClearingSystem (9)
 4. SelectionManager   - Depends on: BattleSignals
 5. MoveOrderHandler   - Depends on: SelectionManager
 6. CombatManager      - Depends on: BattleSignals, SpatialHashGrid (17), CoverSystem (18), VeterancyTracker (20)
 7. TerrainEngine      - No dependencies
 8. DamageSystem       - No dependencies
 9. ClearingSystem     - No dependencies
10. UnifiedTerrain     - No dependencies
11. TerrainIntegration - Depends on: ClearingSystem, DamageSystem, UnifiedTerrain
12. TreeNodeManager    - Depends on: ClearingSystem
13. VegetationLODManager - No dependencies
14. TerrainClearingSystem - Depends on: ClearingSystem, BattleSignals
15. ConstructionManager - Depends on: BattleSignals, SupplyManager (25), JobSystem (3)
16. TerrainFlattening  - Depends on: UnifiedTerrain
17. SpatialHashGrid    - Depends on: BattleSignals
18. CoverSystem        - Depends on: TerrainIntegration (11), GameEnums
19. RosterManager      - No dependencies
20. VeterancyTracker   - No dependencies
21. FloatingLabelManager - Depends on: BattleSignals
22. BattleHUD          - Depends on: BattleSignals
23. SquadBehaviors     - Depends on: BattleSignals
24. TestDaemon         - Depends on: multiple systems
25. SupplyManager      - Depends on: BattleSignals
26. RoadNetwork        - No dependencies
27. SupplyChainManager - Depends on: BattleSignals, JobSystem (3), RoadNetwork (26)
28. AITickManager      - Depends on: BattleSignals
```

### ISSUES FOUND

#### Issue 1: CombatManager references unavailable autoloads (Line 155-156)
**File:** `C:\Users\caleb\RealVietnamRTS\battle_system\systems\combat_manager.gd`
```gdscript
_cover_system = get_node_or_null("/root/CoverSystem")      # Index 18
_veterancy_tracker = get_node_or_null("/root/VeterancyTracker")  # Index 20
```
CombatManager is at index 6, but CoverSystem (18) and VeterancyTracker (20) load later.
**Impact:** Caching fails, falls back to get_node_or_null each call.
**Fix:** Move caching to first use, or move CombatManager after these systems.

#### Issue 2: ConstructionManager depends on later autoloads
**File:** `C:\Users\caleb\RealVietnamRTS\firebase_system\construction_manager.gd`
```gdscript
var supply_mgr := get_node_or_null("/root/SupplyManager")  # Index 25
```
ConstructionManager is at index 15, SupplyManager at 25.
**Impact:** Always null in _ready(), works at runtime.

#### Issue 3: SpatialHashGrid connects to BattleSignals at ready
**File:** `C:\Users\caleb\RealVietnamRTS\battle_system\ai\spatial_hash_grid.gd`
```gdscript
if BattleSignals:
    BattleSignals.unit_spawned.connect(_on_unit_spawned)
```
SpatialHashGrid is at index 17, BattleSignals at 2 - this works correctly.

---

## 2. Signal Analysis

### BattleSignals Signal Bus Inventory (195 lines)

**Total Signals Defined:** 68

| Category | Count | Purpose |
|----------|-------|---------|
| Unit Signals | 5 | Spawn, death, damage, selection |
| Morale Signals | 4 | Routing, rallying, morale breaks |
| Combat Signals | 8 | Attacks, suppression, projectiles |
| Firebase Signals | 4 | Established, activated, under attack |
| Construction Signals | 5 | Started, complete, terrain cleared |
| Supply Signals | 4 | Convoy, delivered, consumed |
| Helicopter Signals | 5 | Dispatched, landed, extraction |
| Reinforcement Signals | 2 | Requested, arrived |
| Mission Signals | 3 | Started, objective, complete |
| AI Signals | 3 | Wave incoming, defeated, spotted |
| NVA Siege Signals | 8 | Various siege events |
| VC Guerrilla Signals | 6 | Ambush, tunnel, trap events |
| Village Signals | 4 | Allegiance, attacked, casualties |
| SOG Signals | 4 | Insertion, compromise, extraction |
| UI Signals | 2 | Selection, construction site click |
| Vehicle Component Signals | 4 | Damage, crew, ammo |
| Supply Truck Signals | 3 | Departed, arrived, ambushed |
| Gunship Signals | 3 | Attack run, winchester, RTB |
| Medevac Signals | 3 | Dispatched, loaded, delivered |
| Reputation Signals | 3 | Changed, war crime, medal |
| Tunnel Signals | 5 | Discovered, collapsed, cleared |
| Route Planning Signals | 4 | Calculated, blocked, threat |

### ORPHANED SIGNALS (Defined but never connected or emitted)

| Signal | Status | Notes |
|--------|--------|-------|
| `siege_started` | ORPHANED | Defined but no connection found |
| `siege_broken` | ORPHANED | Defined but no connection found |
| `human_wave_launched` | ORPHANED | Defined but no connection found |
| `artillery_barrage_incoming` | ORPHANED | Defined but no connection found |
| `sapper_assault_detected` | ORPHANED | Defined but no connection found |
| `aa_threat_detected` | ORPHANED | Defined but no connection found |
| `sog_team_inserted` | ORPHANED | Defined but no connection found |
| `sog_team_compromised` | ORPHANED | Defined but no connection found |
| `sog_extraction_requested` | ORPHANED | Defined but no connection found |
| `sog_mission_complete` | ORPHANED | Defined but no connection found |
| `route_calculated` | ORPHANED | Defined but no connection found |
| `route_blocked` | ORPHANED | Defined but no connection found |
| `threat_cleared` | ORPHANED | Emitted but never connected |
| `projectile_fired` | PARTIAL | Emitted by 4 files, connected by 1 (audio_manager) |

### Signals with Sparse Connection Coverage

| Signal | Emitters | Connectors | Gap |
|--------|----------|------------|-----|
| `unit_routing` | 1 (squad.gd) | 1 (ai_director.gd) | OK |
| `unit_rallied` | 1 (squad.gd) | 0 | MISSING |
| `melee_attack` | 1 (squad.gd) | 0 | MISSING |
| `wave_defeated` | 0 | 0 | UNUSED |
| `convoy_departed` | 1 | 0 | MISSING |

### LOCAL SIGNALS vs BattleSignals

Several managers define local signals that duplicate or shadow BattleSignals:

**CombatManager** (C:\Users\caleb\RealVietnamRTS\battle_system\systems\combat_manager.gd)
```gdscript
signal combat_started(attacker: Node, defender: Node)
signal damage_dealt(target: Node, amount: float, source: Node, weapon: String)
signal unit_suppressed(target: Node, amount: float)
signal unit_killed(target: Node, killer: Node)
signal ammo_depleted(unit: Node)
```
**Issue:** Duplicates BattleSignals.unit_attacked, unit_damaged, unit_suppressed, unit_died, unit_ammo_depleted

**SupplyManager** (C:\Users\caleb\RealVietnamRTS\reinforcement_system\supply_manager.gd)
```gdscript
signal supply_requested(destination: Node3D, amount: float)
signal supply_delivered(destination: Node3D, amount: float)
signal supply_shortage(location: Node3D)
signal supply_route_established(origin: Node3D, destination: Node3D)
signal global_supply_changed(new_amount: float)
```
**Issue:** `supply_delivered` duplicates BattleSignals.supply_delivered

**ConstructionManager** (C:\Users\caleb\RealVietnamRTS\firebase_system\construction_manager.gd)
```gdscript
signal construction_queued(firebase: Node3D, building_type: int)
signal construction_started(firebase: Node3D, zone: Node3D)
signal construction_progress(zone: Node3D, progress: float)
signal construction_complete(firebase: Node3D, building: Node3D)
signal construction_failed(firebase: Node3D, reason: String)
```
**Note:** These extend BattleSignals for local use - acceptable pattern.

---

## 3. Tight Coupling Problems

### Problem 1: Direct function calls bypassing signal bus

**File:** `C:\Users\caleb\RealVietnamRTS\battle_system\systems\selection_manager.gd`
```gdscript
# Line 254-258 - Direct BattleSignals emission instead of method call
BattleSignals.building_selected.emit(zone)
BattleSignals.building_selected.emit(building)
BattleSignals.building_selected.emit(collider)
```
**Issue:** Selection manager directly emits signals; should use central signal bus pattern consistently.

### Problem 2: TerrainIntegration creates child instances of autoloads

**File:** `C:\Users\caleb\RealVietnamRTS\terrain\terrain_integration.gd`
```gdscript
# Lines 86-98
clearing_system = get_node_or_null("/root/ClearingSystem")
if not clearing_system:
    clearing_system = ClearingSystemClass.new()  # Creates LOCAL instance
    add_child(clearing_system)

damage_system = get_node_or_null("/root/DamageSystem")
if not damage_system:
    damage_system = DamageSystemClass.new()  # Creates LOCAL instance
    add_child(damage_system)
```
**Issue:** If autoloads fail to load, local instances are created without autoload registration, causing state fragmentation.

### Problem 3: ConstructionZone emits signals directly

**File:** `C:\Users\caleb\RealVietnamRTS\firebase_system\construction_zone.gd`
```gdscript
# Line 272, 380, 841
BattleSignals.construction_started.emit(self, data.building_type)
BattleSignals.construction_complete.emit(completed_building)
BattleSignals.building_destroyed.emit(self, building_data.building_type if building_data else -1)
```
**Issue:** Scene nodes should emit local signals that managers forward to BattleSignals, not emit directly.

### Problem 4: Multiple terrain clearing entry points

Three different systems handle clearing:
1. `ClearingSystem` (terrain/systems/clearing_system.gd) - authoritative
2. `TerrainClearingSystem` (firebase_system/terrain_clearing.gd) - forwarder
3. `TreeNodeManager` (terrain/vegetation/tree_node_manager.gd) - visual trees

**Issue:** Code sometimes calls ClearingSystem directly, sometimes TerrainClearingSystem. Should consolidate.

### Problem 5: JobSystem and ConstructionManager overlap

Both systems handle building construction with different responsibilities:
- `JobSystem`: Creates build jobs, tracks workers
- `ConstructionManager`: Manages construction queues, engineer assignment

**Issue:** `ConstructionManager.enqueue_build_with_prerequisites()` and `JobSystem.create_build_job()` both create build jobs.

---

## 4. God Objects

### Files Over 500 LOC (Guideline Violation)

| File | LOC | Status |
|------|-----|--------|
| `battle_system/nodes/squad.gd` | 3,749 | CRITICAL |
| `firebase_system/building_data.gd` | 2,268 | Data file - OK |
| `firebase_system/job_system/job_system.gd` | 1,874 | CRITICAL |
| `firebase_system/job_system/worker_controller.gd` | 1,396 | HIGH |
| `battle_system/ui/battle_hud.gd` | 1,280 | HIGH |
| `firebase_system/placement_controller.gd` | 1,234 | HIGH |
| `battle_system/ui/blueprint_ghost.gd` | 1,141 | HIGH |
| `terrain/vegetation/vegetation_manager.gd` | 1,103 | HIGH |
| `battle_system/data/vietnam_weapon_data.gd` | 994 | Data file - OK |
| `battle_system/combat/projectile.gd` | 900 | HIGH |
| `firebase_system/construction_zone.gd` | 883 | HIGH |
| `terrain/core/terrain_grid.gd` | 859 | HIGH |
| `firebase_system/nodes/defensive_structure.gd` | 856 | HIGH |
| `terrain/systems/road_network.gd` | 851 | HIGH |
| `firebase_system/construction_manager.gd` | 791 | HIGH |
| `terrain/terrain_integration.gd` | 747 | HIGH |
| `battle_system/data/game_enums.gd` | 717 | Data file - OK |
| `battle_system/systems/combat_manager.gd` | 686 | HIGH |

### God Object 1: Squad (3,749 LOC) - CRITICAL

**File:** `C:\Users\caleb\RealVietnamRTS\battle_system\nodes\squad.gd`

**Responsibilities (10+ distinct concerns):**
- Movement and pathfinding
- Combat targeting and firing
- Health and damage
- Suppression and morale
- Animation
- Veterancy
- Clearing/building (engineer capability)
- AI behaviors
- Selection visuals
- Formation handling

**Recommendation:** Split into component nodes:
- `SquadMovement` - pathfinding, formation (~500 LOC)
- `SquadCombat` - targeting, firing, damage (~800 LOC)
- `SquadMorale` - suppression, veterancy, routing (~400 LOC)
- `SquadAnimator` - animation states (~300 LOC)
- `SquadConstructor` - clearing, building for engineers (~400 LOC)
- `Squad` base - composition, state management (~500 LOC)

### God Object 2: JobSystem (1,874 LOC) - CRITICAL

**File:** `C:\Users\caleb\RealVietnamRTS\firebase_system\job_system\job_system.gd`

**Responsibilities:**
- Job creation (6 types: BUILD_STRUCTURE, CLEAR_TERRAIN, FLATTEN_AREA, DIG_TRENCH, LAY_WIRE, BUILD_ROAD, FILL_CRATER)
- Job tracking and state management
- Worker assignment scoring
- Terrain flattening helpers
- Placement validation (6 error types)
- Bridge placement validation
- Job node creation/management
- Terrain signal connections

**Recommendation:** Split into:
- `JobRegistry` - tracking, state management, queries (~400 LOC)
- `JobFactory` - creation of different job types (~400 LOC)
- `PlacementValidator` - placement validation, bridge validation (~500 LOC)
- `WorkerMatcher` - assignment scoring algorithm (~200 LOC)
- `JobSystem` orchestrator - wiring, process loop (~300 LOC)

### God Object 3: WorkerController (1,396 LOC) - HIGH

**File:** `C:\Users\caleb\RealVietnamRTS\firebase_system\job_system\worker_controller.gd`

**Responsibilities:**
- Worker state machine
- Job finding
- Work execution (chopping, carving, building)
- Path following
- Animation control
- Tool management

**Recommendation:** Split into:
- `WorkerStateMachine` - state transitions (~300 LOC)
- `WorkerJobFinder` - job selection heuristics (~200 LOC)
- `WorkerTools` - chopping, carving, building execution (~600 LOC)
- `WorkerController` - orchestration (~300 LOC)

### God Object 4: TerrainIntegration (747 LOC)

**File:** `C:\Users\caleb\RealVietnamRTS\terrain\terrain_integration.gd`

**Responsibilities:**
- Creates and wires terrain subsystems
- Signal forwarding
- Public API for height, slope, cover
- Building site preparation
- Vegetation clearing
- Terrain dirty region batching

**Recommendation:** This is a legitimate facade pattern but still over limit. Consider:
- `TerrainQueries` - read-only terrain queries (~200 LOC)
- `TerrainModifier` - write operations (clearing, damage) (~200 LOC)
- `TerrainIntegration` - wiring, signal forwarding (~300 LOC)

### God Object 5: ConstructionManager (791 LOC)

**File:** `C:\Users\caleb\RealVietnamRTS\firebase_system\construction_manager.gd`

**Responsibilities:**
- Construction queues
- Active constructions
- Job integration
- Engineer auto-assignment
- Building spawning
- HQ building firebase activation
- Scene-placed building registration

**Recommendation:** Already has `JobSystem` overlap. Consider:
- Move job creation to JobSystem (it already handles this)
- Keep only construction zone management here (~400 LOC)
- Move HQ/firebase activation to Firebase class (~100 LOC)

---

## 5. Dependency Graph

```
                    [GameEnums]
                         |
                    [BattleSignals]
                    /     |      \
                   /      |       \
        [SpatialHashGrid] |  [SelectionManager]
              |           |        |
        [CombatManager]   |  [MoveOrderHandler]
              |           |
        [CoverSystem]-----+
              |
    [TerrainIntegration]
         /    |    \
        /     |     \
[ClearingSystem] | [DamageSystem]
        |         |
[TerrainClearingSystem]
        |
[ConstructionManager]----[SupplyManager]
        |
    [JobSystem]
        |
[SupplyChainManager]
```

### No Circular Dependencies Found

All dependency arrows point downward/outward. The architecture correctly:
- Places pure data (GameEnums) at top
- Places signal bus (BattleSignals) second
- Systems query downward dependencies

---

## 6. Recommendations

### Priority 1: Fix Autoload Order (Quick Fix)

Reorder project.godot autoloads:
```ini
[autoload]
# Pure data first
GameEnums="*res://battle_system/data/game_enums.gd"

# Signal bus second
BattleSignals="*res://battle_system/signals/battle_signals.gd"

# Terrain systems (no BattleSignals dependency)
TerrainEngine="*res://terrain/core/terrain_engine.gd"
DamageSystem="*res://terrain/systems/damage_system.gd"
ClearingSystem="*res://terrain/systems/clearing_system.gd"
UnifiedTerrain="*res://terrain/core/unified_terrain_engine.gd"
TerrainIntegration="*res://terrain/terrain_integration.gd"
TreeNodeManager="*res://terrain/vegetation/tree_node_manager.gd"
VegetationLODManager="*res://terrain/vegetation/vegetation_lod_manager.gd"
TerrainClearingSystem="*res://firebase_system/terrain_clearing.gd"
TerrainFlattening="*res://firebase_system/terrain_flattening.gd"
RoadNetwork="*res://terrain/systems/road_network.gd"

# Battle systems (depend on BattleSignals)
SpatialHashGrid="*res://battle_system/ai/spatial_hash_grid.gd"
VeterancyTracker="*res://battle_system/systems/veterancy_tracker.gd"
RosterManager="*res://battle_system/systems/roster_manager.gd"
CoverSystem="*res://battle_system/systems/cover_system.gd"
CombatManager="*res://battle_system/systems/combat_manager.gd"
SelectionManager="*res://battle_system/systems/selection_manager.gd"
MoveOrderHandler="*res://battle_system/systems/move_order_handler.gd"

# Supply systems
SupplyManager="*res://reinforcement_system/supply_manager.gd"

# Construction systems (depend on SupplyManager, ClearingSystem)
JobSystem="*res://firebase_system/job_system/job_system.gd"
ConstructionManager="*res://firebase_system/construction_manager.gd"
SupplyChainManager="*res://logistics_system/supply_chain_manager.gd"

# AI systems
SquadBehaviors="*res://battle_system/ai/squad_behaviors.gd"
AITickManager="*res://battle_system/ai/ai_tick_manager.gd"

# UI systems (last - depend on everything)
FloatingLabelManager="*res://battle_system/ui/floating_label_manager.gd"
BattleHUD="*res://battle_system/ui/battle_hud.gd"

# Debug
TestDaemon="*res://test_daemon/daemon_autoload.gd"
```

### Priority 2: Consolidate Signal Emissions

Add helper methods to BattleSignals for commonly emitted signal clusters:

```gdscript
## In battle_signals.gd

func emit_unit_spawned(unit: Node3D, faction: int) -> void:
    unit_spawned.emit(unit, faction)

func emit_unit_died(unit: Node3D, killer: Node3D) -> void:
    unit_died.emit(unit, killer)

func emit_unit_damaged(unit: Node3D, damage: float, source: Node3D) -> void:
    unit_damaged.emit(unit, damage, source)
```

### Priority 3: Remove Duplicate Local Signals

CombatManager should not define its own signals. Remove:
```gdscript
# REMOVE THESE from combat_manager.gd
signal combat_started(attacker: Node, defender: Node)
signal damage_dealt(target: Node, amount: float, source: Node, weapon: String)
signal unit_suppressed(target: Node, amount: float)
signal unit_killed(target: Node, killer: Node)
```

### Priority 4: Split Squad God Object

Create component scripts that Squad owns:
- `res://battle_system/components/combat_component.gd`
- `res://battle_system/components/morale_component.gd`
- `res://battle_system/components/movement_component.gd`

Target: Squad.gd under 500 LOC after refactor.

### Priority 5: Clean Up Orphaned Signals

Either connect these signals to systems or remove them:
- `siege_started`, `siege_broken`, `human_wave_launched` - For NVA siege system
- `sog_*` signals - For SOG system (MVP-excluded)
- `route_*` signals - For convoy pathfinding

---

## 7. Summary

The codebase has a **good architectural foundation** with:
- Centralized signal bus (BattleSignals)
- Clear autoload separation
- No circular dependencies

**Key issues to address:**
1. Fix autoload ordering for CombatManager cache optimization
2. Split Squad.gd (3,749 LOC) into components
3. Remove duplicate local signals from CombatManager
4. Consolidate clearing system entry points
5. Clean up or remove 14 orphaned signals

**Estimated refactoring effort:** 2-3 days
