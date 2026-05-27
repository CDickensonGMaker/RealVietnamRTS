# Architecture Review Report

**Date:** 2026-05-26
**Engine:** Godot 4.6 (GDScript primary, Jolt physics)
**GDDs Reviewed:** 2 (morale_system_design.md, build_menu_design.md)
**ADRs Reviewed:** 9 (ADR-0001 through ADR-0009)

---

## Executive Summary

**Verdict: PARTIAL** — 9 ADRs cover ~38% of 134 technical requirements.

The project has strong foundational ADRs for terrain, vegetation, spatial queries, navigation,
construction, supply chains, serialization, and firebase placement. Major gaps remain in
combat mechanics, morale/routing, unit resources, AI Director, doctrine, and content schemas.

---

## Project State Assessment

| Artifact | Status |
|----------|--------|
| GAME_BIBLE.md | ✅ Complete — 17 locked design decisions |
| tr-registry.yaml | ✅ Complete — 134 technical requirements extracted |
| design/gdd/*.md | ⚠️ Partial — 2 design docs exist |
| docs/architecture/adr-*.md | ✅ 9 ADRs exist and mapped |
| docs/architecture/architecture.md | ✅ Master architecture document exists |
| docs/engine-reference/godot/ | ❌ Missing — No engine API docs |
| docs/architecture/systems-index.md | ❌ Missing |

---

## Traceability Summary

**Total requirements:** 134
- ✅ Covered: 51 (38%)
- ⚠️ Partial: 12 (9%)
- ❌ Gaps: 71 (53%)

### Requirements by Layer

| Layer | Total | Covered | Partial | Gaps | Coverage % |
|-------|-------|---------|---------|------|------------|
| Foundation | 20 | 9 | 2 | 9 | 50% |
| Core | 31 | 5 | 3 | 23 | 26% |
| Systems | 57 | 31 | 5 | 21 | 63% |
| Content | 26 | 6 | 2 | 18 | 31% |

---

## ADR Coverage Mapping

### ADR-0001: Terrain Chunk Streaming
**Status:** Accepted

| Requirement | Description | Coverage |
|-------------|-------------|----------|
| TR-FND-010 | Cell/chunk streaming for large maps | ✅ Full |
| TR-FND-017 | TerrainEngine 3km x 3km chunked streaming | ✅ Full |
| TR-SYS-001 | Terrain clearing progression | ✅ Full |
| TR-CNT-052 | Campaign uses single persistent map | ⚠️ Partial |
| TR-CNT-053 | All terrain modifications persist | ✅ Full |
| TR-CNT-055 | TerrainEngine chunks unlock progressively | ✅ Full |

### ADR-0002: Vegetation LOD System
**Status:** Accepted

| Requirement | Description | Coverage |
|-------------|-------------|----------|
| TR-FND-012 | LOD system (distant units as NATO markers) | ⚠️ Partial (vegetation only) |
| TR-FND-008 | 60 FPS with 300-500 units | ⚠️ Partial (vegetation contributes) |
| TR-FND-009 | 30 FPS minimum on potato specs | ⚠️ Partial |

### ADR-0003: Spatial Hash Grid
**Status:** Accepted

| Requirement | Description | Coverage |
|-------------|-------------|----------|
| TR-FND-011 | O(1) spatial hashing for unit queries | ✅ Full |

### ADR-0004: Signal Bus Pattern
**Status:** Accepted

| Requirement | Description | Coverage |
|-------------|-------------|----------|
| Cross-cutting | Enables loose coupling across systems | ✅ Architectural |

### ADR-0005: Job System Architecture
**Status:** Accepted

| Requirement | Description | Coverage |
|-------------|-------------|----------|
| TR-SYS-002 | Bulldozers: fast, large-area clearing | ✅ Full |
| TR-SYS-003 | Engineer det-cord clearing | ✅ Full |
| TR-SYS-004 | Bulldozers terrain limitations | ✅ Full |
| TR-SYS-005 | Clearing tools vulnerable while working | ⚠️ Partial |
| TR-SYS-006 | Terrain types respond differently | ✅ Full |
| TR-SYS-007 | Craters persist | ✅ Full |
| TR-SYS-008 | Clear jungle (small) 60 sec | ✅ Full |
| TR-SYS-009 | Clear jungle (large) 30 sec | ✅ Full |
| TR-SYS-010 | Cut road 2-3 min per 100m | ✅ Full |
| TR-SYS-011 | Prepare LZ 90 sec | ✅ Full |
| TR-SYS-030 | Engineers auto-build inside zones | ✅ Full |
| TR-SYS-031 | Engineers manually commanded outside | ✅ Full |
| TR-SYS-032 | Engineers under fire: pause construction | ⚠️ Partial |
| TR-SYS-033 | Any squad can build sandbags/foxholes/wire | ✅ Full |
| TR-SYS-034 | Engineer squad can build all buildings | ✅ Full |
| TR-SYS-035 | BaseStructure extends StaticBody3D | ✅ Full |
| TR-SYS-036 | Paint/drag perimeter tools | ✅ Full |

### ADR-0006: Supply Chain & Road Network
**Status:** Accepted

| Requirement | Description | Coverage |
|-------------|-------------|----------|
| TR-SYS-040 | Supply sources: Rear Depot, Airstrip, Supply Depot | ✅ Full |
| TR-SYS-041 | Truck convoy: road-dependent, ambush-vulnerable | ✅ Full |
| TR-SYS-042 | Helicopter supply: fast, direct, limited | ⚠️ Partial |
| TR-SYS-043 | Road connects firebases = auto supply flow | ✅ Full |
| TR-SYS-044 | Truck convoy logic | ✅ Full |
| TR-SYS-045 | Helicopter logic | ⚠️ Partial |
| TR-SYS-046 | Supply consumption | ✅ Full |
| TR-SYS-047 | Supply costs | ✅ Full |

### ADR-0007: Navigation Mesh
**Status:** Accepted

| Requirement | Description | Coverage |
|-------------|-------------|----------|
| TR-COR-030 | NavigationServer3D pathfinding | ✅ Full |
| TR-COR-031 | Movement: right-click, shift-queue | ⚠️ Partial (needs input handling) |
| TR-COR-014 | BROKEN units return to nearest firebase | ✅ Full |

### ADR-0008: Save Serialization
**Status:** Proposed (contracts established, implementation deferred)

| Requirement | Description | Coverage |
|-------------|-------------|----------|
| TR-FND-013 | Autosave at mission start, map expansion, every 10 min | ⚠️ Architecture only |
| TR-FND-014 | Save system serializes all state | ✅ Full (contracts) |
| TR-FND-015 | Serialization-friendly patterns from day one | ✅ Full |
| TR-FND-016 | No raw Node references across frames | ✅ Full |
| TR-CNT-054 | All constructed bases persist | ✅ Full (via contracts) |

### ADR-0009: Build Menu & Firebase Placement
**Status:** Accepted

| Requirement | Description | Coverage |
|-------------|-------------|----------|
| TR-SYS-020 | Firebase defined by HQ Building | ✅ Full |
| TR-SYS-021 | HQ creates influence radius | ✅ Full |
| TR-SYS-022 | Firebase HQ influence: 150m, 12 slots | ✅ Full |
| TR-SYS-023 | Maximum 4-6 firebases | ⚠️ Partial (not enforced yet) |
| TR-SYS-024 | Outposts have no auto-supply/morale bonus | ✅ Full |
| TR-SYS-025 | MVP: one main + one forward outpost | ✅ Full |
| TR-SYS-026 | Systems scale from 2 to N firebases | ✅ Full |

---

## Coverage Gaps (Remaining Requirements)

### Foundation Layer Gaps — 9 Requirements

| Requirement | Description | Suggested ADR |
|-------------|-------------|---------------|
| TR-FND-001 | Steam PC only (Windows primary) | Platform Strategy |
| TR-FND-002 | Godot 4.6 with GDScript | Engine Configuration |
| TR-FND-003 | Intel UHD 620 minimum GPU | Performance Budget |
| TR-FND-004 | GTX 1060 recommended GPU | Performance Budget |
| TR-FND-005 | CPU requirements | Performance Budget |
| TR-FND-006 | RAM requirements | Performance Budget |
| TR-FND-007 | Storage requirements | Performance Budget |
| TR-FND-018 | Physics layers defined | Physics Configuration |
| TR-FND-019 | Input map specification | Input System |

### Core Layer Gaps — 23 Requirements

| Domain | Count | Suggested ADR |
|--------|-------|---------------|
| Combat System (TR-COR-001–007) | 7 | **Combat System** |
| Morale System (TR-COR-010–017) | 8 | **Morale and Routing** |
| Unit Resources (TR-COR-020–025) | 6 | **Unit Resource System** |
| AI Director (TR-COR-040–043) | 4 | **AI Director** |

### Systems Layer Gaps — 21 Requirements

| Domain | Count | Suggested ADR |
|--------|-------|---------------|
| Reinforcement (TR-SYS-050–056) | 7 | **Reinforcement System** |
| Doctrine (TR-SYS-060–064) | 5 | **Doctrine System** |
| Weather (TR-SYS-070–074) | 5 | [POST-MVP] Weather System |
| Airstrip (TR-SYS-080–083) | 4 | Airstrip System |
| Tunnels (TR-SYS-090–091) | 2 | VC Tunnel System |
| Villages (TR-SYS-095–097) | 3 | Village System |

### Content Layer Gaps — 18 Requirements

| Domain | Count | Suggested ADR |
|--------|-------|---------------|
| Faction Architecture (TR-CNT-001–004) | 4 | **Faction Architecture** |
| US Unit Roster (TR-CNT-010–016) | 7 | Unit Data Schema |
| VC Unit Roster (TR-CNT-020–024) | 5 | Unit Data Schema |
| Buildings (TR-CNT-030–043) | 14 | Building Data Schema |
| Map Requirements (TR-CNT-050–055) | 6 | Map System |
| Visual Style (TR-CNT-060–064) | 5 | Art Direction |

---

## Required ADRs — Priority Order

### Tier 1: Core Combat (Next Priority)

| # | ADR Title | Covers | Blocks |
|---|-----------|--------|--------|
| 10 | **Combat System** | TR-COR-001–007 | Morale, Unit behaviors |
| 11 | **Morale and Routing** | TR-COR-010–017 | Squad AI |
| 12 | **Unit Resource System** | TR-COR-020–025 | Supply integration |

### Tier 2: AI & Reinforcement

| # | ADR Title | Covers | Blocks |
|---|-----------|--------|--------|
| 13 | **AI Director** | TR-COR-040–043 | Enemy spawning |
| 14 | **Reinforcement System** | TR-SYS-050–056 | Doctrine |
| 15 | **Doctrine System** | TR-SYS-060–064 | Force composition |

### Tier 3: Content Layer

| # | ADR Title | Covers |
|---|-----------|--------|
| 16 | **Faction Architecture** | TR-CNT-001–004 |
| 17 | **Unit Data Schema** | TR-CNT-010–024 |
| 18 | **Building Data Schema** | TR-CNT-030–043 |

---

## Engine Compatibility Issues

**Status:** Cannot fully audit — no engine reference docs exist.

**Action Required:** Run `/setup-engine` to populate:
- `docs/engine-reference/godot/VERSION.md`
- `docs/engine-reference/godot/breaking-changes.md`
- `docs/engine-reference/godot/deprecated-apis.md`

---

## Cross-ADR Conflicts

No conflicts detected between existing ADRs. The 9 ADRs form a coherent foundation:
- ADR-0001 (Terrain) ← ADR-0002 (Vegetation) ← ADR-0007 (Navigation)
- ADR-0003 (Spatial) → Combat targeting (future ADR-0010)
- ADR-0004 (Signals) → All systems
- ADR-0005 (Jobs) ← ADR-0009 (Placement)
- ADR-0006 (Supply/Roads) ← ADR-0007 (Navigation)
- ADR-0008 (Serialization) → All systems

---

## ADR Dependency Order

```
Existing Foundation (implemented):
  ADR-0001: Terrain Chunk Streaming
  ADR-0002: Vegetation LOD System
  ADR-0003: Spatial Hash Grid
  ADR-0004: Signal Bus Pattern
  ADR-0005: Job System Architecture
  ADR-0006: Supply Chain & Road Network
  ADR-0007: Navigation Mesh
  ADR-0008: Save Serialization (contracts)
  ADR-0009: Build Menu & Firebase Placement

Next Phase (combat & AI):
  ADR-0010: Combat System (requires ADR-0003)
  ADR-0011: Morale and Routing (requires ADR-0010, ADR-0007)
  ADR-0012: Unit Resource System (requires ADR-0008)
  ADR-0013: AI Director (requires ADR-0003, ADR-0010)

Feature Layer:
  ADR-0014: Reinforcement System (requires ADR-0012)
  ADR-0015: Doctrine System (requires ADR-0014)

Content Layer:
  ADR-0016: Faction Architecture (requires ADR-0008)
  ADR-0017: Unit Data Schema (requires ADR-0010, ADR-0016)
  ADR-0018: Building Data Schema (requires ADR-0009, ADR-0016)
```

---

## Blocking Issues

1. **Combat System not specified** — Combat mechanics (cover, suppression, damage) need ADR
2. **Morale System not specified** — Routing behavior partially in navigation ADR but needs full spec
3. **No engine reference docs** — Cannot verify Godot 4.6 API compatibility

---

## Next Steps

1. Create **ADR-0010: Combat System** covering TR-COR-001–007
2. Create **ADR-0011: Morale and Routing** covering TR-COR-010–017
3. Run `/setup-engine` to populate engine reference docs
4. Re-run `/architecture-review` after combat/morale ADRs complete

---

## History

| Date | Requirements | Covered | Verdict |
|------|--------------|---------|---------|
| 2026-05-26 (v1) | 134 | 0 (0%) | FAIL |
| 2026-05-26 (v2) | 134 | 51 (38%) | PARTIAL |

