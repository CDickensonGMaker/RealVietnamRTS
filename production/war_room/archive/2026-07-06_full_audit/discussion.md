# The Debate — Full Game Audit 2026-07-06

## Points of Agreement (all architects)
1. The logistics-loop bugs and the freezes share one epicenter: the **clear/flatten/build path**. Fixing that path fixes both complaints.
2. The spec (`terrain-clearing.md`) and the code have diverged badly — `update_road_cutting()` was never written; the real pipeline is JobSystem-based (CLEAR_TERRAIN → FLATTEN_AREA → BUILD_ROAD → RoadSegmentNode).
3. Prior fix plans were partially executed and never committed: SpatialHashGrid integration and EntityCache exist and work; but ~279 working-tree changes have sat unpushed since ~2026-05-29.

## Conflicts Raised and Resolutions

### C1: Is the bulldozer's missing `apply_clearing_damage()` firing in production?
- *Logistics Specialist:* dead code — WorkerController blocks direct commands.
- *Performance Analyst:* fires 60×/sec, error spam tanks FPS.
- **Arbiter adjudication (verified inline):** `clear_zone()`/`cut_path()` at `bulldozer.gd:586/618` are guarded by `_worker_controller and not allow_direct_commands`. AND `test_combined.gd:609` spawns "bulldozers" via `_spawn_squad(us_bulldozer_data, ...)` — they are **Squads, not Bulldozer instances**. Verdict: the missing method is a latent crash (any Bulldozer-class scene with direct commands), not the main-scene freeze. The main-scene freeze comes from the **Squad clearing path** (`squad.gd:1134` → ClearingSystem per-tick rewrite → synchronous vegetation regen at `terrain_integration.gd:605`). Fix both; expect the freeze relief from the Squad path.

### C2: Primary freeze mechanism — vegetation regen vs chunk rebuild?
- One pass blamed `terrain_flattening.gd` → full chunk rebuild + `create_trimesh_shape()` cook; the other blamed `clearing_system.gd:126` per-tick writes → undebounced `regenerate_chunk()`.
- **Resolution:** complementary, same family. Clearing floods `cell_updated` 60×/sec (vegetation path, no debounce — while `_on_unified_terrain_modified` five lines below already batches at 0.2s); flatten/clear progress also drives chunk rebuilds whose budget loop always completes ≥1 full chunk (incl. synchronous trimesh cook). Decree: debounce at the source (stage transitions / 0.2s batch) AND coalesce chunk rebuilds + move collision cook off main thread.

### C3: Is SpatialHashGrid integrated or not?
- **Resolution:** integrated for combat/separation (May plan Phase 1/3 done), but `SpatialHashGrid._process` still re-scans every unit every frame, and EntityCache is bypassed by a dozen callers. Integration ≠ optimization; both follow-ups stand.

### C4: H1 chicken-and-egg — real or not?
- **Resolution:** REFUTED as pathfinding (no navmesh, no road-access gate exists at all); CONFIRMED as topology: `supply_chain_manager.gd:216-218` silently returns when no second depot/firebase anchor exists, so the FIRST road is never tasked. Plus worker job discovery uses full 3-D distance with 150m radius, so a unit stranded at Y=0 (spawn race) sees no jobs — the spawn bug *causes* the idle bug.

## Devil's Advocate — What Is Sacrificed
- **Debouncing clearing visuals** sacrifices per-frame visual fidelity of jungle melting away; at 0.2s batching no player will notice. Accepted.
- **Committing the 6-week batch wholesale** sacrifices clean history for safety of work. Accepted — one large checkpoint commit beats losing 279 files.
- **Consolidating supply to one owner** sacrifices the working ad-hoc loop in test_combined that currently demos Pillar 3; a real main scene must reach parity before deleting the harness. Sequenced accordingly.
- **Deferring Squad decomposition (12x)** again: the god object remains a tax on every future feature. Named and accepted — freeze fixes and loop closure come first; decomposition rides with the staggering refactor.
- **The UI north star (docs/design/ui-vision.md)** is explicitly deferred: no HUD work until the loop is fixed and the main scene is real; the concept binds future UI to signal-driven implementation (battle_hud is already an offender).
