# The Decree — Full Game Audit
**Date:** 2026-07-06 · **Arbiter synthesis of:** logistics_diagnosis.md, performance_audit.md, architecture_audit_2026-07-06.md, discussion.md

## Verdict on the Summoner's Hypotheses
| # | Hypothesis | Verdict |
|---|---|---|
| H1 | Chicken-and-egg: bulldozer needs a road to cut the first road | **REFUTED as pathfinding** (no navmesh/road-gate exists). **CONFIRMED as topology**: first road is never *tasked* — `supply_chain_manager.gd:216-218` silently returns without a second depot/firebase anchor; no player road command exists. |
| H2 | Below-map spawn = terrain init race | **CONFIRMED** (heightmap, not navmesh): `get_height_at()` returns 0.0 before heightmap init; spawns trust it; reinforcements never sample height at all. Kicker: bad Y inflates 3-D job-distance scoring past the 150m search radius → **the spawn bug causes the idle-worker bug**. |
| H3 | Road visual never wired | **CONFIRMED**: `RoadDecalRenderer` (only user of dirt_road.png) is orphaned. Production visual `RoadSegmentNode` is untextured solid color, hidden until >10% job progress — and the job usually never exists/starts. |

## Why It Freezes
Squad-driven clearing advances every physics frame → ClearingSystem rewrites the terrain area **every tick** → `cell_updated` handled synchronously (`terrain_integration.gd:605`, no debounce) → vegetation MultiMesh chunks destroyed and rebuilt in GDScript 60×/sec, stacked with full chunk rebuilds + synchronous `create_trimesh_shape()` cooks. The batching path already exists five lines below the offending handler. Secondary: TestDaemon autoload doing main-thread file I/O every 1–2s; ~100 debug prints in hot paths; latent crash — `bulldozer.gd:357/392` calls non-existent `TerrainClearingSystem.apply_clearing_damage()` (unguarded).

## The Decree — Ordered Work

### Phase 0 — Preserve the work (today, 30 min)
1. **Commit and push the ~279-file uncommitted batch** (6 weeks of fixes exist only in the working tree — single point of total loss).
2. Delete root clutter: `nul`, `campaign.zip`, `tests.zip`, `test_scenes.zip`, `freezing big time.zip` (after checking the freeze zip for profiler captures).
3. Back up Beads (`bd export > backup.jsonl`) — `bd init` reported DB corruption warning.

### Phase 1 — Stop the bleeding (1–2 days)
4. **Debounce clearing→vegetation**: route `_on_cell_updated` through the existing 0.2s batch; write terrain state on stage transitions, not every tick. *(freeze fix, ~15 lines)*
5. **Coalesce chunk rebuilds**: mutate heights in place where possible; budget-check before completing a chunk; defer `create_trimesh_shape` to WorkerThreadPool or switch terrain to HeightMapShape3D. *(freeze fix)*
6. **Fix/guard `apply_clearing_damage`** on TerrainClearingSystem (implement forwarder or has_method-guard callers). *(latent crash)*
7. **Remove TestDaemon from autoloads**; gate debug prints in job/construction/clearing paths. *(quick wins)*

### Phase 2 — Close the logistics loop (the stuck feature, 2–4 days)
8. **Terrain-ready spawn gating** (extends Beads o2k): `terrain_ready` signal + deferred-spawn helper; `_snap_to_terrain` must not accept the 0.0 sentinel; reinforcement spawns must sample height.
9. **Job discovery on XZ distance** in `get_best_job_for_worker`/`_score_job` so height error can't hide jobs.
10. **First-road fallback anchor**: when no second depot/firebase exists, connect to parent firebase/rear base; log instead of silent return. Consider a direct player "cut road" command (Pillar 1 verb).
11. **One road pipeline**: RoadSegmentNode is canonical — give it the dirt texture, show planned outline at 0% progress; delete RoadDecalRenderer and the Bulldozer PATH_CUTTING branch.
12. **Convoys must use RoadNetwork** (currently straight-line; roads confer zero benefit — Pillar 3 breach vs ADR-0006).

### Phase 3 — Scale headroom + hygiene (1–2 weeks, after loop is verified)
13. Squad tiered update staggering (BT/morale/suppression @10Hz slices, animation LOD) per `docs/reference/rts_architecture_patterns.md`; throttle SpatialHashGrid rescan; cache terrain refs; fix projectile double-collision. (Epic zuf)
14. Fix phantom singletons (`DoctrineManager`, `TerrainFlatteningSystem` name mismatch, `UnitSpawner`; ReinforcementManager has zero refs) — Pillar 4 is currently dead at runtime.
15. Supply one-owner consolidation (4 competing implementations; Beads mbp) and promote a **real main scene** to replace test_combined.tscn.
16. Truth maintenance: fix CLAUDE.md directory/autoload tables; rewrite terrain-clearing.md to describe the job pipeline; resolve PRD vs GAME_BIBLE authority conflict (Chinook is implemented despite explicit exclusion — decide, then enforce).
17. Squad.gd decomposition (12x) rides with #13.

### Deferred (named sacrifice)
- **UI north star** (`docs/design/ui-vision.md`): no HUD build-out until Phases 1–2 verified in-game. Future HUD must be signal-driven (battle_hud.gd is already a group-scan offender).
- Village/tunnel/airplane systems (~3,700 LOC of MVP-excluded scope): freeze, don't extend.

## Pillar Health (from architecture audit)
P1 Carve the Map: WORKING (strongest). P2 Firebases: working-partial. P3 Supply: fragmented, no owner. P4 Doctrine: spec-only, dead at runtime. P5 War Continues: partial. Persistent map/save: spec-only.

## Laws Observed
Tradeoffs named in discussion.md. No decree item violates a Pillar; items 10–12 restore Pillar 1/3 integrity. Actionable items recorded in Beads. The Summoner holds final authority.
