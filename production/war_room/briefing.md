# War Room Briefing — Full Game Audit
**Date:** 2026-07-06
**Summoner:** Caleb
**Session:** Fable 5 full audit (logistics loop + performance + whole-game)

## The Query
Full audit of RealVietnamRTS with two focal points:

1. **Logistics loop bugs** (diagnose before fixing):
   - Engineer/bulldozer units sometimes spawn below the terrain surface.
   - When spawned correctly, they don't perform clear-and-build-road behavior (idle / fail to path / never trigger `update_road_cutting()`).
   - Terrain clears but no visible dirt road appears.
2. **Major slowdowns** during every playtest (see `freezing big time.zip` in repo root).

## Summoner's Hypotheses (to confirm or refute)
- **H1 (chicken-and-egg):** Bulldozers require road access per spec; the FIRST road out of a firebase has no road to path on → silent pathfinding failure.
- **H2 (timing):** Below-map spawns are a navmesh/terrain-chunk init-order issue — ground-Y query runs before TerrainClearingSystem readies the chunk.
- **H3 (missing visual step):** `update_road_cutting()` only sets cells to CLEARED; road decal/mesh may never be triggered. Note: `firebase_system/road_decal_renderer.gd` exists — wired or orphaned?

## Architects Summoned
- **Logistics Specialist** — trace spawn logic, road-cut tasking, off-road pathing, road visuals → `analysis/logistics_diagnosis.md`
- **Performance Analyst** — rank frame-time offenders, identify freeze cause → `analysis/performance_audit.md`
- **Technical Director** — whole-game delta audit vs 2026-05-28, duplicate systems, pillar status → `analysis/architecture_audit_2026-07-06.md`

## Known Prior Context (Beads + archives)
- Spawn height timing already tracked (RealVietnamRTS-o2k) — likely same root as bug 1.
- ~40 files call `get_nodes_in_group` in `_process` (h4d); SpatialHashGrid integration incomplete (1a8); perf epic (zuf).
- Squad.gd god object 3,749 LOC (12x); TerrainGrid/UnifiedTerrain duplicate (eiu).
- Supply loop core mechanic previously PROVEN WORKING (trucks → firebase → squad resupply within 168m).
- Prior perf plan exists: `production/war_room/performance_fix_plan.md` (2026-05-29) — check what was/wasn't executed.

## Constraints
- Diagnose first; no code changes until findings reviewed by the Summoner.
- GAME_BIBLE.md pillars govern all decisions; scope discipline is strict.
- Performance targets: 60 FPS with 300–500 units, 16.67ms frame budget, 3km×3km map.
