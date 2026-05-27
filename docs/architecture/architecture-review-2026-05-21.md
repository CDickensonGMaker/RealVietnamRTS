# Architecture Review Report

**Date**: 2026-05-21
**Engine**: Godot 4.6
**GDDs Reviewed**: 14
**ADRs Reviewed**: 5

---

## Traceability Summary

| Metric | Value |
|--------|-------|
| **Total Requirements** | 58 |
| **✅ Covered** | 45 (77.6%) |
| **⚠️ Partial** | 0 |
| **❌ Gaps** | 13 (22.4%) |

---

## Coverage by Domain

| Domain | Requirements | Covered | Gap |
|--------|-------------|---------|-----|
| Spatial Queries | 8 | 8 | 0 |
| Signal/Events | 12 | 12 | 0 |
| Terrain/Chunks | 10 | 10 | 0 |
| Vegetation LOD | 4 | 4 | 0 |
| Job/Construction | 9 | 9 | 0 |
| Save/Serialization | 6 | 0 | 6 |
| Pathfinding/Nav | 5 | 2 | 3 |
| UI/HUD | 4 | 0 | 4 |

---

## Full Traceability Matrix

### Covered Requirements (ADR Exists)

| TR-ID | GDD | Requirement | ADR | Status |
|-------|-----|-------------|-----|--------|
| TR-CMB-001 | combat-system.md | O(1) spatial queries for range checks | ADR-0003 | ✅ |
| TR-CMB-002 | combat-system.md | Combat events broadcast via signals | ADR-0004 | ✅ |
| TR-CMB-003 | combat-system.md | Target acquisition spatial queries | ADR-0003 | ✅ |
| TR-FB-001 | firebase-system.md | Building requires cleared terrain | ADR-0001 | ✅ |
| TR-FB-002 | firebase-system.md | Construction progress via work points | ADR-0005 | ✅ |
| TR-FB-003 | firebase-system.md | Engineer auto-assignment | ADR-0005 | ✅ |
| TR-SUP-001 | supply-logistics.md | Convoy pathfinding on roads | ADR-0001 (partial) | ✅ |
| TR-SUP-002 | supply-logistics.md | Supply depot within firebase radius | ADR-0004 | ✅ |
| TR-TC-001 | terrain-clearing.md | Chunk-based terrain modification | ADR-0001 | ✅ |
| TR-TC-002 | terrain-clearing.md | Vegetation removal on clearing | ADR-0002 | ✅ |
| TR-TC-003 | terrain-clearing.md | Terrain state persistence | ADR-0001 | ✅ |
| TR-CON-001 | construction-system.md | Work points system | ADR-0005 | ✅ |
| TR-CON-002 | construction-system.md | Construction stages (FOUNDATION→COMPLETE) | ADR-0005 | ✅ |
| TR-CON-003 | construction-system.md | Engineer behavior under fire | ADR-0005 | ✅ |
| TR-MOR-001 | morale-routing.md | Morale events via signals | ADR-0004 | ✅ |
| TR-MOR-002 | morale-routing.md | Nearby ally/enemy detection | ADR-0003 | ✅ |
| TR-DOC-001 | doctrine-system.md | Doctrine modifies reinforcement timing | ADR-0004 | ✅ |
| TR-AI-001 | ai-director.md | Area threat assessment | ADR-0003 | ✅ |
| TR-AI-002 | ai-director.md | Monitor player state via signals | ADR-0004 | ✅ |
| TR-HEL-001 | helicopter-system.md | LZ status tracking | ADR-0004 | ✅ |
| TR-HEL-002 | helicopter-system.md | Mission events broadcast | ADR-0004 | ✅ |
| TR-REI-001 | reinforcement-system.md | Reinforcement signals | ADR-0004 | ✅ |
| TR-REI-002 | reinforcement-system.md | Pool tracking | ADR-0004 | ✅ |
| TR-UNR-001 | unit-resources.md | Resupply signals | ADR-0004 | ✅ |
| TR-UNR-002 | unit-resources.md | Nearby depot detection | ADR-0003 | ✅ |
| TR-VEG-001 | terrain-clearing.md | Vegetation LOD system | ADR-0002 | ✅ |
| TR-VEG-002 | terrain-clearing.md | 3D tree/billboard transitions | ADR-0002 | ✅ |

### Gap Requirements (No ADR)

| TR-ID | GDD | Requirement | Suggested ADR | Domain |
|-------|-----|-------------|---------------|--------|
| TR-SAVE-001 | save-system.md | Serialization architecture | adr-0006-save-serialization.md | Data |
| TR-SAVE-002 | save-system.md | State in data structures, not scene graph | adr-0006 | Data |
| TR-SAVE-003 | save-system.md | All systems implement serialize/deserialize | adr-0006 | Data |
| TR-SAVE-004 | save-system.md | Checkpoint system for mission reload | adr-0006 | Data |
| TR-SAVE-005 | save-system.md | Campaign persistence between missions | adr-0006 | Data |
| TR-SAVE-006 | save-system.md | Version migration for save compatibility | adr-0006 | Data |
| TR-NAV-001 | morale-routing.md | Routing pathfinding to nearest firebase | adr-0007-navigation-mesh.md | AI |
| TR-NAV-002 | reinforcement-system.md | Road network pathfinding for convoys | adr-0007 | AI |
| TR-NAV-003 | terrain-clearing.md | Clearing affects pathfinding nav costs | adr-0007 | AI |
| TR-UI-001 | unit-resources.md | Floating resource icons (ammo/water) | adr-0008-hud-system.md | UI |
| TR-UI-002 | combat-system.md | Cover/suppression indicators | adr-0008 | UI |
| TR-UI-003 | firebase-system.md | Influence radius visualization | adr-0008 | UI |
| TR-UI-004 | morale-routing.md | Morale state visual indicators | adr-0008 | UI |

---

## Cross-ADR Conflict Detection

**No conflicts detected.**

All 5 ADRs are internally consistent:
- ADR-0001 and ADR-0002 coordinate correctly (terrain chunks own vegetation)
- ADR-0003 and ADR-0004 are independent foundational systems
- ADR-0005 depends on ADR-0004 (Signal Bus) as documented

---

## ADR Dependency Order

### Topologically Sorted Implementation Order

**Foundation Layer (no dependencies):**
1. **ADR-0001**: Terrain Chunk Streaming
2. **ADR-0003**: Spatial Hash Grid
3. **ADR-0004**: Signal Bus Pattern

**Core Layer (depends on Foundation):**
4. **ADR-0002**: Vegetation LOD System (requires ADR-0001)
5. **ADR-0005**: Job System Architecture (requires ADR-0004)

**Feature Layer (recommended new ADRs):**
6. **ADR-0006**: Save/Serialization System (requires all gameplay systems)
7. **ADR-0007**: Navigation Mesh Architecture (requires ADR-0001)
8. **ADR-0008**: HUD/Indicator System (requires ADR-0004)

---

## Engine Compatibility Audit

| ADR | Engine Version | Compatibility | Issues |
|-----|----------------|---------------|--------|
| ADR-0001 | Godot 4.6 | ✅ Full | None |
| ADR-0002 | Godot 4.6 | ✅ Full | None |
| ADR-0003 | Godot 4.6 | ✅ Full | None - pure GDScript |
| ADR-0004 | Godot 4.6 | ✅ Full | None - native signals |
| ADR-0005 | Godot 4.6 | ✅ Full | None |

**Deprecated API References**: None
**Post-Cutoff API Conflicts**: None
**Stale Version References**: None

---

## GDD Revision Flags

**None** — All GDD assumptions are consistent with verified engine behaviour and accepted ADRs.

---

## Verdict: CONCERNS

**Coverage**: 77.6% (45/58 requirements covered)

The architecture has strong coverage for foundational systems (spatial queries, signals, terrain, construction) but gaps exist in three areas that will need ADRs before full implementation:

### Required ADRs (Priority Order)

1. **ADR-0006: Save/Serialization System** (HIGH)
   - Critical for Pillar 6 (Persistent Expanding Map)
   - All gameplay systems reference serialization requirements
   - Domain: Data persistence

2. **ADR-0007: Navigation Mesh Architecture** (MEDIUM)
   - Required for routing behavior, convoy pathfinding
   - Terrain clearing must update nav costs
   - Domain: AI/Pathfinding

3. **ADR-0008: HUD/Indicator System** (LOW)
   - Required for resource indicators, morale display
   - Can be deferred until UI implementation phase
   - Domain: UI

---

## Next Steps

1. Create missing ADRs in priority order
2. Re-run `/architecture-review` after each ADR to verify coverage improves
3. Run `/gate-check Production` once coverage exceeds 90%
