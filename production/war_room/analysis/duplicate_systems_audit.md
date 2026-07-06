# Duplicate/Redundant Systems Audit

**Audit Date:** 2026-05-28
**Auditor:** Code Audit Agent
**Scope:** RealVietnamRTS autoloads and terrain/supply systems

---

## Executive Summary

This audit identified **6 areas of significant overlap or redundancy** in the codebase. The most critical issue is the terrain system fragmentation, where **5 separate terrain-related autoloads** exist with overlapping responsibilities. The supply system also shows duplication between `SupplyManager` and `SupplyChainManager`.

### Severity Rating
- **CRITICAL**: Terrain system fragmentation (5 autoloads with overlapping responsibilities)
- **MODERATE**: Supply system duplication (2 systems handling supply logistics)
- **LOW**: Clearing system layering (intentional forwarding pattern)

---

## Finding 1: Terrain System Fragmentation (CRITICAL)

### Files Involved
| Autoload | File | LOC | Purpose |
|----------|------|-----|---------|
| `TerrainEngine` | `terrain/core/terrain_engine.gd` | 763 | Heightmap generation (noise, erosion) |
| `UnifiedTerrain` | `terrain/core/unified_terrain_engine.gd` | 748 | "Single source of truth" terrain data |
| `TerrainIntegration` | `terrain/terrain_integration.gd` | 748 | Bridge between systems |
| `TerrainGrid` | (RefCounted, not autoload) | 860 | Gameplay grid queries |
| `TerrainManager` | (Node, created by TerrainIntegration) | 578 | Chunk streaming |

### Analysis

**TerrainEngine** (`terrain/core/terrain_engine.gd`):
- Focused on **procedural heightmap generation**
- Domain warping, ridged multifractal, hydraulic erosion
- Provides `heightmap_data: PackedFloat32Array`
- Has `get_height_at()` and `get_normal_at()` methods

**UnifiedTerrainEngine** (`terrain/core/unified_terrain_engine.gd`):
- Comments claim: "THE single source of truth for all terrain data"
- Duplicates most functionality from `TerrainGrid`
- Has its own elevation, slope, terrain_type, vegetation_density arrays
- Has `get_height_at()`, `get_normal_at()`, `is_passable()`, `is_buildable()`
- Creates its own `HeightmapStorage` internally

**TerrainIntegration** (`terrain/terrain_integration.gd`):
- Acts as a **facade/bridge** between all terrain systems
- Creates instances of `TerrainManager`, `VegetationManager`, `BillboardVegetation`
- Stores references to both `terrain_grid: RefCounted` AND `unified_terrain: Node`
- Has `get_height_at()` that prioritizes `unified_terrain` then falls back to `terrain_manager`

**TerrainGrid** (`terrain/core/terrain_grid.gd`):
- Also claims to be "SINGLE SOURCE OF TRUTH for all terrain data"
- Has elevation, slope, terrain_type, vegetation_density, clearing_stage arrays
- Nearly identical API to `UnifiedTerrainEngine`

### The Problem

1. **Two "single source of truth" systems exist simultaneously**: `TerrainGrid` and `UnifiedTerrainEngine`
2. **Both implement the same functionality**: elevation queries, terrain type, LOS, movement cost
3. **TerrainIntegration references both** and forwards calls inconsistently
4. **Data can become desynchronized** between the two systems

### Evidence of Confusion
```gdscript
# From TerrainIntegration.gd line 260-267
func get_height_at(world_pos: Vector3) -> float:
    # Prioritize UnifiedTerrain for proper Y values
    if unified_terrain and unified_terrain.has_method("get_height_at"):
        return unified_terrain.get_height_at(world_pos)
    # Fallback to terrain_manager
    if terrain_manager and terrain_manager.has_method("get_height_at"):
        return terrain_manager.get_height_at(world_pos)
```

### Recommendation

**MERGE** `UnifiedTerrainEngine` and `TerrainGrid` into a single system:

1. **Keep `TerrainEngine`** - It's a pure generator, not a runtime data store
2. **Keep `TerrainManager`** - Handles chunk streaming, a distinct responsibility
3. **Deprecate `TerrainGrid`** - Merge into `UnifiedTerrainEngine`
4. **Simplify `TerrainIntegration`** - Single reference to unified terrain

**Action Items:**
- [ ] Migrate all `TerrainGrid` callers to use `UnifiedTerrain`
- [ ] Remove duplicate arrays from one system
- [ ] Update `TerrainIntegration` to use only one terrain data store
- [ ] Remove `TerrainGrid` from codebase

---

## Finding 2: Supply System Duplication (MODERATE)

### Files Involved
| Autoload | File | LOC | Purpose |
|----------|------|-----|---------|
| `SupplyManager` | `reinforcement_system/supply_manager.gd` | 292 | Global supply pool, route management |
| `SupplyChainManager` | `logistics_system/supply_chain_manager.gd` | 461 | Auto-road building between depots |

### Analysis

**SupplyManager**:
- Manages `global_supply` pool (off-map resources)
- Tracks `supply_points` (firebases, depots)
- Creates `SupplyRoute` objects for automated deliveries
- Provides `request_supply()`, `establish_supply_route()`
- Located in `reinforcement_system/` directory

**SupplyChainManager**:
- Tracks `_supply_depots` specifically
- Auto-builds roads between depots when constructed
- Creates `BUILD_ROAD` jobs via JobSystem
- Located in `logistics_system/` directory

### The Problem

1. **Both track supply depots** but in different arrays
2. **SupplyManager.supply_points** vs **SupplyChainManager._supply_depots**
3. **Depot registration happens twice**: SupplyManager via group lookup, SupplyChainManager via construction events
4. **Different directories** suggest two separate feature areas that evolved independently

### Overlap Evidence
```gdscript
# SupplyManager.gd line 260-264
func get_all_supply_depots() -> Array[Node3D]:
    var depots: Array[Node3D] = []
    var depot_nodes: Array[Node] = get_tree().get_nodes_in_group("supply_depots")
    ...

# SupplyChainManager.gd line 373-380
func get_all_depots() -> Array[Node3D]:
    var result: Array[Node3D] = []
    for depot: Node3D in _supply_depots:
        ...
```

### Recommendation

**KEEP BOTH** with clear separation of concerns:

1. **SupplyManager**: Resource management (supply pool, consumption, delivery scheduling)
2. **SupplyChainManager**: Infrastructure management (road building, depot connectivity)

**Action Items:**
- [ ] SupplyChainManager should query SupplyManager for depot list, not maintain its own
- [ ] Add `SupplyManager.get_depots()` as the canonical source
- [ ] SupplyChainManager subscribes to `SupplyManager.supply_point_registered` signal
- [ ] Consider renaming to `RoadConstructionManager` to clarify purpose

---

## Finding 3: Clearing System Layering (LOW - Intentional)

### Files Involved
| Autoload | File | LOC | Purpose |
|----------|------|-----|---------|
| `ClearingSystem` | `terrain/systems/clearing_system.gd` | 376 | Core clearing logic, zone management |
| `TerrainClearingSystem` | `firebase_system/terrain_clearing.gd` | 130 | Thin forwarder for firebase system |

### Analysis

**ClearingSystem**:
- Core implementation: zones, stages, vegetation updates
- Writes to `TerrainGrid` for clearing state
- Has `ClearingZone` inner class with full state
- Progressive clearing: JUNGLE -> PARTIALLY_CLEARED -> CLEARED -> FORTIFIED

**TerrainClearingSystem**:
- Explicit comment: "Thin forwarder to ClearingSystem autoload"
- Comment: "Per ARCHITECTURE.md: NO duplicate state"
- Connects to ClearingSystem signals and forwards them
- Provides convenience methods like `instant_clear()`

### Assessment

This is **intentional architectural layering**, not duplication:
- `ClearingSystem` is the core terrain implementation
- `TerrainClearingSystem` is the firebase/construction system's API adapter
- Signal forwarding maintains loose coupling between systems

### Recommendation

**KEEP AS-IS** - This is a proper facade pattern.

**Minor cleanup:**
- [ ] Ensure both systems appear in the same documentation section
- [ ] Add cross-reference comments between files

---

## Finding 4: Vegetation LOD Management Overlap (LOW)

### Files Involved
| Autoload | File | LOC | Purpose |
|----------|------|-----|---------|
| `VegetationLODManager` | `terrain/vegetation/vegetation_lod_manager.gd` | 210 | 3D tree visibility based on distance |
| `TreeNodeManager` | `terrain/vegetation/tree_node_manager.gd` | 241 | Individual tree nodes for clearing |

### Analysis

**VegetationLODManager**:
- Manages visibility of **all 3D trees** based on camera distance
- Hysteresis to prevent flickering (show at 200m, hide at 250m)
- Uses `_tree_visibility: Dictionary` to track state

**TreeNodeManager**:
- Creates **individual TreeNode instances** for clearing operations
- Spawns trees only in active clearing zones
- Connects to `VegetationLODManager` for distance culling

### Assessment

These serve **complementary purposes**:
- VegetationLODManager: General LOD for MultiMesh vegetation
- TreeNodeManager: Interactive trees for clearing gameplay

### Recommendation

**KEEP BOTH** - Different responsibilities.

**Clarification needed:**
- [ ] Document relationship between VegetationManager (MultiMesh), VegetationLODManager (visibility), and TreeNodeManager (interactive)

---

## Finding 5: Terrain Flattening vs Clearing (LOW)

### Files Involved
| Autoload | File | LOC | Purpose |
|----------|------|-----|---------|
| `TerrainFlattening` | `firebase_system/terrain_flattening.gd` | 260 | FLATTEN_AREA job visual progression |
| `ClearingSystem` | `terrain/systems/clearing_system.gd` | 376 | CLEAR_TERRAIN job progression |

### Analysis

**TerrainFlattening**:
- Handles `FLATTEN_AREA` job type
- Modifies terrain height progressively
- Creates `FlatteningOperation` with original heights cached

**ClearingSystem**:
- Handles `CLEAR_TERRAIN` job type
- Removes vegetation progressively
- Also flattens terrain via `_apply_stage_changes()`

### Overlap

Both systems can modify terrain height:
```gdscript
# ClearingSystem._apply_stage_changes() line 179-183
var flatten_func := func(current_height: float, falloff_amount: float) -> float:
    var blend: float = flattening * falloff_amount
    return lerp(current_height, target_height, blend)
terrain_manager.modify_terrain(zone.center, zone.radius, flatten_func)
```

### Recommendation

**KEEP BOTH** with clarified purposes:
- `TerrainFlattening`: Pure terrain height modification (for helipads, artillery pits)
- `ClearingSystem`: Vegetation clearing (may include light flattening as side effect)

**Action Items:**
- [ ] ClearingSystem should not call `terrain_manager.modify_terrain()` for height changes
- [ ] Clearing jobs should dispatch separate FLATTEN_AREA jobs if flattening needed
- [ ] Or: ClearingSystem only sets vegetation density, TerrainFlattening only modifies height

---

## Finding 6: Damage System Cover Overlap (LOW)

### Files Involved
| Autoload | File | LOC | Purpose |
|----------|------|-----|---------|
| `DamageSystem` | `terrain/systems/damage_system.gd` | 417 | Terrain deformation, crater cover |
| `CoverSystem` | `battle_system/systems/cover_system.gd` | (not read) | Static cover evaluation |

### Analysis

**DamageSystem** has crater cover functionality:
```gdscript
# DamageSystem.gd line 318-325
const CRATER_COVER_VALUES: Dictionary = {
    DamageType.SMALL_EXPLOSION: 0.3,     # Grenade crater - light cover
    DamageType.MEDIUM_EXPLOSION: 0.5,    # Artillery shell - moderate cover
    ...
}

func get_crater_cover(world_pos: Vector3) -> float:
```

This overlaps with what `CoverSystem` would provide for general cover queries.

### Recommendation

**Investigate CoverSystem** before deciding:
- [ ] Read `CoverSystem` implementation
- [ ] Determine if it should aggregate crater cover from DamageSystem
- [ ] Ensure consistent cover values across systems

---

## Summary of Action Items

### Critical (Terrain Fragmentation)
1. [ ] Merge `TerrainGrid` into `UnifiedTerrainEngine`
2. [ ] Update all callers to use single terrain data source
3. [ ] Simplify `TerrainIntegration` facade
4. [ ] Remove redundant `get_height_at()` implementations

### Moderate (Supply Duplication)
5. [ ] SupplyChainManager should use SupplyManager's depot list
6. [ ] Remove duplicate depot tracking array
7. [ ] Consider renaming to clarify purpose

### Low Priority
8. [ ] Document vegetation system relationships
9. [ ] Clarify TerrainFlattening vs ClearingSystem height modification
10. [ ] Integrate crater cover with CoverSystem

---

## Autoload Count Analysis

Current autoload count: **27 autoloads** (from project.godot)

By category:
- **Battle/Combat**: GameEnums, BattleSignals, SpatialHashGrid, CombatManager, CoverSystem, SquadBehaviors, VeterancyTracker, AITickManager
- **Terrain**: TerrainEngine, UnifiedTerrain, TerrainIntegration, DamageSystem, ClearingSystem, TerrainFlattening
- **Vegetation**: TreeNodeManager, VegetationLODManager, TerrainClearingSystem
- **Construction/Firebase**: JobSystem, ConstructionManager
- **UI**: SelectionManager, MoveOrderHandler, FloatingLabelManager, BattleHUD
- **Supply/Logistics**: SupplyManager, RoadNetwork, SupplyChainManager
- **Roster**: RosterManager
- **Testing**: TestDaemon

**Recommended removals/consolidations:**
1. Remove `TerrainGrid` (merge into UnifiedTerrain) - saves 1 potential autoload
2. Keep but simplify terrain autoloads from 6 to 4

This would reduce effective terrain autoloads and eliminate the "two sources of truth" problem.
