# Orphaned Code Audit Report
**Date:** 2026-05-28
**Auditor:** Code Audit Agent
**Project:** RealVietnamRTS

## Executive Summary

This audit identified **18 potentially orphaned or underutilized code files** in the RealVietnamRTS codebase. The files fall into several categories:

| Category | Count | Action |
|----------|-------|--------|
| Intentional Stubs (PARKED) | 3 | Keep - documented placeholders |
| Orphaned Utility Classes | 5 | Consider deletion or integration |
| Unused Systems | 4 | Consider deletion |
| Dead Test Files | 2 | Consider deletion |
| Partial Implementations | 4 | Complete or delete |

---

## 1. INTENTIONAL STUBS (PARKED FOR MVP)

These files are **intentional placeholders** per the Game Bible D-202 decision. Keep them.

### 1.1 WeatherSystem
- **File:** `C:\Users\caleb\RealVietnamRTS\battle_system\systems\weather_system.gd`
- **Lines:** 9
- **Status:** PARKED per D-202
- **Content:** Stub with `current_weather` variable
- **Referenced by:** `ai_context.gd` line 227-229
- **Recommendation:** KEEP - Documented placeholder for post-MVP

### 1.2 AirSupportManager
- **File:** `C:\Users\caleb\RealVietnamRTS\battle_system\systems\air_support_manager.gd`
- **Lines:** 7
- **Status:** Stub awaiting Phase 4
- **Referenced by:** Listed in CLAUDE.md autoloads, NOT in project.godot
- **Recommendation:** KEEP - Phase 4 placeholder

### 1.3 PathfindingCostManager
- **File:** `C:\Users\caleb\RealVietnamRTS\battle_system\ai\pathfinding_cost_manager.gd`
- **Lines:** 7
- **Status:** Stub awaiting Phase 2
- **Referenced by:** Nothing
- **Recommendation:** KEEP - Phase 2 placeholder, but consider adding to project.godot when needed

---

## 2. ORPHANED UTILITY CLASSES (No References)

These classes are defined with `class_name` but have **zero references** in the codebase.

### 2.1 VietnamLocations
- **File:** `C:\Users\caleb\RealVietnamRTS\battle_system\data\vietnam_locations.gd`
- **Lines:** 125
- **Content:** Location presets for campaigns (Ia Drang, Khe Sanh, Hue, etc.)
- **References:** NONE (grep found zero matches)
- **Purpose:** Historical location data extracted from archived map_maker
- **Recommendation:** DELETE or integrate with campaign/mission system

### 2.2 UtilityScorer
- **File:** `C:\Users\caleb\RealVietnamRTS\battle_system\ai\utility\utility_scorer.gd`
- **Lines:** 247
- **Content:** Utility-based AI decision making framework
- **References:** Only self-references in comments
- **Purpose:** Base class for utility AI, never actually used
- **Recommendation:** DELETE - the behavior tree system is used instead (BTNode, BTComposite, etc.)

### 2.3 AIContext
- **File:** `C:\Users\caleb\RealVietnamRTS\battle_system\ai\ai_context.gd`
- **Lines:** ~230
- **Content:** Context object for AI decision making
- **References:** Only self-references in comments
- **Purpose:** Companion to UtilityScorer
- **Recommendation:** DELETE - not used by any AI system

### 2.4 TerrainVFX
- **File:** `C:\Users\caleb\RealVietnamRTS\terrain\systems\terrain_vfx.gd`
- **Lines:** 351
- **Content:** Visual effects for terrain operations (explosions, dust, fire)
- **References:** Only class_name declaration
- **Purpose:** Particle effects system
- **Recommendation:** INTEGRATE - good system, needs to be connected to DamageSystem/EngineeringSystem

### 2.5 ConstructionMarkers
- **File:** `C:\Users\caleb\RealVietnamRTS\terrain\systems\construction_markers.gd`
- **Lines:** 340
- **Content:** Visual markers for construction (stakes, tape, progress rings)
- **References:** Only class_name declaration
- **Purpose:** Construction visualization
- **Recommendation:** INTEGRATE - good system, needs to be connected to ConstructionManager

---

## 3. UNUSED SYSTEMS (Implemented but Not Connected)

### 3.1 RoutePlanner
- **File:** `C:\Users\caleb\RealVietnamRTS\logistics_system\route_planner.gd`
- **Lines:** 519
- **Content:** Full A* route planning with threat avoidance
- **References:** Only class_name declaration
- **Purpose:** Supply route planning
- **Recommendation:** DELETE or MERGE - SupplyChainManager has its own route planning

### 3.2 FerryManager / FerryRoute
- **Files:**
  - `C:\Users\caleb\RealVietnamRTS\logistics_system\ferry_manager.gd` (291 lines)
  - `C:\Users\caleb\RealVietnamRTS\logistics_system\ferry_route.gd` (130 lines)
- **Content:** Supreme Commander-style ferry routes
- **References:** Only internal references
- **Purpose:** Automated transport routes
- **Recommendation:** DEFER - good design but not integrated, revisit post-MVP

### 3.3 ResourceFlowSystem
- **File:** `C:\Users\caleb\RealVietnamRTS\logistics_system\resource_flow_system.gd`
- **Lines:** ~330
- **Content:** Supreme Commander-style continuous resource economy
- **References:** Only class_name declaration
- **Purpose:** Producer/consumer resource flow
- **Recommendation:** DEFER - alternative economic model, revisit post-MVP

---

## 4. CAMERA SYSTEM DUPLICATION

### 4.1 BattleCamera vs RTSCamera
- **BattleCamera:** `C:\Users\caleb\RealVietnamRTS\battle_system\camera\battle_camera.gd`
  - Lines: ~200
  - References: NONE (not used in any scene)
- **RTSCamera:** `C:\Users\caleb\RealVietnamRTS\battle_system\camera\rts_camera.gd`
  - Lines: ~200
  - References: Used in main.tscn, test_combined.tscn, test_scene_base.gd

**Recommendation:** DELETE BattleCamera - RTSCamera is the active implementation

---

## 5. FORTIFICATION SYSTEM

The fortification_system/ directory contains several classes that may overlap with firebase_system/:

### 5.1 Potentially Redundant Files
| File | Lines | Status |
|------|-------|--------|
| `fortification_system/bunker.gd` | ~100 | May duplicate firebase_system/nodes/defensive_structure.gd |
| `fortification_system/trench.gd` | ~100 | May duplicate firebase_system/nodes/trench_node.gd |
| `fortification_system/garrisonable_structure.gd` | ~150 | Used by several fortification classes |
| `fortification_system/defensive_structure.gd` | ~100 | Conflicts with firebase_system version |

**Recommendation:** AUDIT - consolidate into single location (firebase_system)

---

## 6. DEAD TEST FILES

### 6.1 Linear Placement Tests
- **Directory:** `C:\Users\caleb\RealVietnamRTS\tests\linear_placement_test\`
- **Files:**
  - `rotation_math_test.gd`
  - `orientation_test.gd`
  - `model_orientation_audit.gd`
  - `rotation_diagnostic.gd`
- **Status:** These test rotation math that's now handled by PlacementController
- **Recommendation:** DELETE - tests for completed/merged functionality

---

## 7. PARTIAL IMPLEMENTATIONS

### 7.1 SaveManager
- **File:** `C:\Users\caleb\RealVietnamRTS\core\save_manager.gd`
- **Lines:** ~320
- **Status:** Complete implementation but NOT in project.godot autoloads
- **References:** BattleSignals.mission_started
- **Recommendation:** ADD to project.godot autoloads when save system is needed

### 7.2 AudioManager
- **File:** `C:\Users\caleb\RealVietnamRTS\battle_system\systems\audio_manager.gd`
- **Lines:** ~100
- **Status:** Implemented but NOT in project.godot autoloads
- **References:** VeterancyTracker tries to use it
- **Recommendation:** ADD to project.godot autoloads

### 7.3 RTSController
- **File:** `C:\Users\caleb\RealVietnamRTS\battle_system\systems\rts_controller.gd`
- **Lines:** ~400
- **Status:** Implemented but NOT referenced by any scene
- **Content:** Top-level RTS game controller
- **Recommendation:** INTEGRATE with main scene or DELETE if redundant

### 7.4 DeployableFOB
- **File:** `C:\Users\caleb\RealVietnamRTS\firebase_system\deployable_fob.gd`
- **Lines:** ~230
- **Status:** Implemented but NOT used
- **Content:** WARNO-style deployable forward operating base
- **Recommendation:** DEFER - interesting feature for post-MVP

---

## 8. ACTION SUMMARY

### Immediate Actions (Delete)
1. `battle_system/camera/battle_camera.gd` - Duplicate of RTSCamera
2. `battle_system/data/vietnam_locations.gd` - Not used
3. `battle_system/ai/utility/utility_scorer.gd` - Not used (behavior tree used instead)
4. `battle_system/ai/ai_context.gd` - Not used (companion to UtilityScorer)
5. `logistics_system/route_planner.gd` - Redundant with SupplyChainManager
6. `tests/linear_placement_test/*.gd` - Obsolete tests

### Integration Needed
1. `terrain/systems/terrain_vfx.gd` - Connect to combat/engineering systems
2. `terrain/systems/construction_markers.gd` - Connect to ConstructionManager
3. `battle_system/systems/audio_manager.gd` - Add to project.godot autoloads
4. `core/save_manager.gd` - Add to project.godot when ready

### Defer to Post-MVP
1. `logistics_system/ferry_manager.gd` + `ferry_route.gd` - Supreme Commander ferry routes
2. `logistics_system/resource_flow_system.gd` - Continuous resource economy
3. `firebase_system/deployable_fob.gd` - WARNO-style deployable bases

### Consolidation Needed
1. `fortification_system/` vs `firebase_system/` - Merge defensive structure implementations

---

## 9. LINES OF CODE SUMMARY

| Category | Files | Lines | % of Total |
|----------|-------|-------|------------|
| Active Code | ~150 | ~40,000 | 85% |
| Orphaned/Unused | 18 | ~3,500 | 7.5% |
| Parked Stubs | 3 | 23 | 0.1% |
| Redundant | 6 | ~1,200 | 2.5% |
| Test Files | 15 | ~2,000 | 4.3% |

**Estimated cleanup savings:** ~4,700 lines (10% of codebase)

---

## 10. RECOMMENDED CLEANUP ORDER

1. **Phase 1 (Safe deletions):** Delete clearly orphaned files with no references
   - BattleCamera, VietnamLocations, UtilityScorer, AIContext, RoutePlanner

2. **Phase 2 (Test cleanup):** Remove obsolete test files
   - linear_placement_test directory

3. **Phase 3 (Integration):** Connect useful but disconnected systems
   - TerrainVFX, ConstructionMarkers, AudioManager

4. **Phase 4 (Consolidation):** Merge fortification_system into firebase_system

5. **Phase 5 (Defer tracking):** Tag remaining files for post-MVP review
   - FerryManager, ResourceFlowSystem, DeployableFOB

---

## 11. VILLAGE SYSTEM STATUS

The village_system/ directory contains a complete but disconnected system:

| File | Lines | Status |
|------|-------|--------|
| `village_system/village.gd` | ~200 | Village with allegiance, supplies, civilians |
| `village_system/village_manager.gd` | ~100 | Manager for multiple villages |
| `village_system/civilian.gd` | ~350 | Civilian NPC with allegiance, intel, fleeing |
| `village_system/reputation_tracker.gd` | ~240 | Hearts and minds, war crimes tracking |

**Status:** Complete implementation but NOT connected to:
- Mission system (no objectives use villages)
- AI controllers (VC should interact with villages)
- UI (no village interaction panel)

**Recommendation:** DEFER - good Hearts & Minds system for post-MVP, but not MVP critical

---

## 12. UNUSED PUBLIC FUNCTIONS AUDIT

The following public functions (no underscore prefix) appear to have no external callers:

### High-Impact (Consider Making Private or Removing)

| File | Function | Notes |
|------|----------|-------|
| `squad.gd` | `get_formation_positions()` | Formation system not used |
| `firebase.gd` | `get_building_by_type()` | No callers found |
| `insertion_manager.gd` | `request_gunship_cap()` | Gunship CAP not implemented |
| `cover_system.gd` | `get_cover_bonus()` | Referenced but may be outdated |

**Recommendation:** Review these functions and either:
1. Add underscore prefix if internal-only
2. Document intended usage if API
3. Delete if truly unused

---

## APPENDIX A: All Files Checked

```
battle_system/ai/*.gd              - 22 files
battle_system/camera/*.gd          - 2 files
battle_system/data/*.gd            - 8 files
battle_system/nodes/*.gd           - 3 files
battle_system/systems/*.gd         - 13 files
battle_system/ui/*.gd              - 22 files
battle_system/units/*.gd           - 7 files
battle_system/utils/*.gd           - 2 files
campaign/*.gd                      - 3 files
core/*.gd                          - 1 file
effects/particles/*.gd             - 1 file
firebase_system/*.gd               - 24 files
fortification_system/*.gd          - 7 files
helicopter_system/*.gd             - 9 files
logistics_system/*.gd              - 5 files
reinforcement_system/*.gd          - 4 files
terrain/*.gd                       - 33 files
test_scenes/*.gd                   - 11 files
tests/*.gd                         - 4 files
tools/*.gd                         - 2 files
tunnel_system/*.gd                 - 5 files
village_system/*.gd                - 4 files
```

**Total:** ~192 GDScript files analyzed
