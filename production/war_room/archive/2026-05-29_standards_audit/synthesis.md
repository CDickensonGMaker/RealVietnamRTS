# WAR ROOM SYNTHESIS: Full Codebase Audit

**Date:** 2026-05-28
**Session Type:** Code Audit - Duplicates, Competing Systems, Orphaned Code
**Codebase Stats:** 219 GDScript files, ~97,000 lines of code

---

## THE DECREE

The Council has audited the RealVietnamRTS codebase and delivers the following findings. Overall, the architecture is **sound with good documentation discipline**. Key issues are concentrated in two areas: **terrain system fragmentation** and **god object accumulation**.

---

## CRITICAL FINDINGS

### 1. Terrain System Fragmentation (CRITICAL)

**Problem:** Two systems both claim to be "THE single source of truth":
- `TerrainGrid` (terrain/core/terrain_grid.gd)
- `UnifiedTerrainEngine` (terrain/core/unified_terrain_engine.gd)

**Evidence:**
- Both implement `get_height_at()`, `is_passable()`, `is_buildable()`
- `TerrainIntegration` has fallback logic checking both
- Data can become desynchronized

**Decree:** MERGE TerrainGrid into UnifiedTerrainEngine
- [ ] Migrate all TerrainGrid callers
- [ ] Remove duplicate arrays
- [ ] Simplify TerrainIntegration facade

### 2. God Object: Squad.gd (CRITICAL)

**Problem:** 3,749 lines handling 10+ concerns
- Movement, combat, health, suppression, animation, veterancy, clearing, AI, selection, formations

**Decree:** SPLIT into component nodes
- SquadMovement (~500 LOC)
- SquadCombat (~800 LOC)
- SquadMorale (~400 LOC)
- SquadAnimator (~300 LOC)
- SquadConstructor (~400 LOC)
- Squad base (~500 LOC)

---

## MODERATE FINDINGS

### 3. Supply System Duplication

**Problem:** Both track supply depots separately:
- `SupplyManager.supply_points` (group lookup)
- `SupplyChainManager._supply_depots` (construction events)

**Decree:** Consolidate depot tracking
- [ ] SupplyChainManager queries SupplyManager for depots
- [ ] Remove duplicate tracking array
- [ ] Consider renaming to `RoadConstructionManager`

### 4. Autoload Order Issues

**Problem:** CombatManager (index 6) caches CoverSystem (18) and VeterancyTracker (20) - always null at _ready()

**Decree:** Reorder autoloads in project.godot
- Move terrain systems before battle systems
- Move SupplyManager before ConstructionManager
- See dependency_signal_audit.md for recommended order

### 5. Orphaned Signals (14 signals)

**Problem:** Signals defined in BattleSignals but never connected:
- siege_started, siege_broken, human_wave_launched (NVA siege)
- sog_team_inserted, sog_team_compromised (SOG system)
- route_calculated, route_blocked (convoy pathfinding)

**Decree:** DEFER - These support post-MVP systems

---

## LOW PRIORITY FINDINGS

### 6. Orphaned Code Files (DELETE)

| File | Lines | Reason |
|------|-------|--------|
| battle_system/camera/battle_camera.gd | ~200 | RTSCamera is active |
| battle_system/data/vietnam_locations.gd | 125 | Zero references |
| battle_system/ai/utility/utility_scorer.gd | 247 | Behavior tree used instead |
| battle_system/ai/ai_context.gd | ~230 | Companion to UtilityScorer |
| logistics_system/route_planner.gd | 519 | SupplyChainManager has own routing |
| tests/linear_placement_test/*.gd | ~200 | Obsolete tests |

**Total cleanup:** ~1,500 lines

### 7. Integrate Disconnected Systems

| File | Action |
|------|--------|
| terrain/systems/terrain_vfx.gd | Connect to DamageSystem |
| terrain/systems/construction_markers.gd | Connect to ConstructionManager |
| battle_system/systems/audio_manager.gd | Add to project.godot autoloads |

### 8. Fortification vs Firebase Overlap

Two directories have overlapping defensive structure implementations:
- `fortification_system/` - bunker.gd, trench.gd
- `firebase_system/nodes/` - defensive_structure.gd, trench_node.gd

**Decree:** Consolidate into firebase_system

---

## ARCHITECTURE STRENGTHS (No Action Needed)

| Domain | Status | Notes |
|--------|--------|-------|
| AI Systems | CLEAN | Well-layered inheritance (Controller -> BT -> Utility) |
| Clearing Systems | CLEAN | ClearingSystem authoritative, TerrainClearingSystem is forwarder |
| Construction | CLEAN | JobSystem and ConstructionManager have documented role separation |
| Combat/Damage | CLEAN | CombatManager (units) vs DamageSystem (terrain) clear |

---

## ACTION PLAN

### Phase 1: Safe Deletions (Low Risk)
1. Delete orphaned files (6 files, ~1,500 LOC)
2. Delete obsolete tests (linear_placement_test/)

### Phase 2: Consolidation
3. Merge TerrainGrid into UnifiedTerrainEngine
4. SupplyChainManager uses SupplyManager depot list
5. Consolidate fortification_system into firebase_system

### Phase 3: Refactoring
6. Split Squad.gd into components
7. Split JobSystem into Registry/Factory/Validator
8. Fix autoload ordering in project.godot

### Phase 4: Integration
9. Connect TerrainVFX to combat system
10. Connect ConstructionMarkers to ConstructionManager
11. Add AudioManager to autoloads

---

## METRICS

| Metric | Current | After Cleanup |
|--------|---------|---------------|
| GDScript files | 219 | ~210 |
| Lines of code | 97,000 | ~92,000 |
| God objects (>500 LOC) | 15 | Target: 5 |
| Orphaned files | 18 | 0 |
| Duplicate systems | 3 | 0 |

---

## FILES ANALYZED

Four parallel audit agents examined:
1. **Duplicate Systems** - 343 lines of findings
2. **Orphaned Code** - 325 lines of findings
3. **Competing Systems** - 340 lines of findings
4. **Dependencies/Signals** - 519 lines of findings

Full reports in: `production/war_room/analysis/`

---

*The Council has spoken. The architecture is sound; the entropy is manageable.*
