# Logistics Specialist Diagnosis: Supply-Route / Road-Cutting Loop

**Author:** Logistics Specialist Architect (War Room audit)
**Date:** 2026-07-06
**Scope:** DIAGNOSIS ONLY. No game code was modified.
**Systems traced:** `firebase_system/terrain_clearing.gd`, `firebase_system/road_decal_renderer.gd`,
`firebase_system/nodes/road_segment_node.gd`, `firebase_system/construction_manager.gd`,
`firebase_system/job_system/{job_system,worker_controller,unified_job}.gd`,
`logistics_system/supply_chain_manager.gd`, `reinforcement_system/convoy_manager.gd`,
`reinforcement_system/reinforcement_manager.gd`, `battle_system/units/bulldozer.gd`,
`battle_system/nodes/squad.gd`, `terrain/core/unified_terrain_engine.gd`,
`terrain/terrain_integration.gd`, `scenes/test_combined.gd`, `project.godot`.

---

## Executive Summary

All three reported bugs are real, but two of the three user hypotheses are wrong about
*mechanism* even where the *symptom* is confirmed. The road-cutting loop is fully
job-driven (CLEAR_TERRAIN -> FLATTEN_AREA -> BUILD_ROAD), not the `update_road_cutting()`
pseudocode from the GDD — that function does not exist in the codebase.

- **H1 (bulldozer needs road access -> chicken-and-egg pathing fail): REFUTED as stated.**
  There is no road-access gate and no navmesh; bulldozers/engineers move freely off-road via
  direct-position + terrain-snap. The GDD's "requires road access / very slow off-road" line is
  aspirational and unimplemented. The *real* cause of "bulldozer idles instead of cutting the
  first road" is that road-cut jobs are **only** created by `SupplyChainManager` when a
  **Supply Depot** is placed/completed. There is no player-facing "cut a road" command, and the
  bulldozer's own `cut_path()` is deliberately disabled when a WorkerController is present. No
  depot -> no BUILD_ROAD job -> nothing for the bulldozer to find -> idle.

- **H2 (below-map spawn = terrain/chunk init timing): CONFIRMED in mechanism** (with one
  correction: there is no navmesh — it's a heightmap-readiness issue). `get_height_at()` returns
  a hard `0.0` fallback before the heightmap is initialized, and the heightmap is built
  *asynchronously* (`await`) after autoloads/spawns. Units that spawn or snap during that window
  are slammed to Y=0, i.e. below any surface with elevation > 0 (Vietnam terrain reaches ~280m).

- **H3 (dirt-road visual never implemented; `road_decal_renderer.gd` orphaned): CONFIRMED
  orphaned + PARTIAL.** `RoadDecalRenderer` (the one that loads `dirt_road.png`) is dead code —
  nothing in game code instantiates it. The road visual that IS wired is `RoadSegmentNode`, which
  draws a **solid-color** mesh (no texture) and is only made visible after workers apply >=10%
  BUILD_ROAD work. So "terrain clears but no road texture" = the textured renderer is orphaned,
  and the solid-color proxy only shows if the job actually gets worked (which H1/H2 can prevent).

---

## H1 — "Bulldozer requires road access to reach the work site" — REFUTED (as stated)

**Verdict: REFUTED for the stated mechanism. A different, real defect explains the symptom.**

### Evidence the movement layer has no road requirement
- `battle_system/units/bulldozer.gd:416-458` (`_move_toward`): movement is direct — slope sample,
  rotate toward target, `velocity = forward * speed`, `move_and_slide()`. The only gate is
  **slope** (`_cached_slope > max_slope` at line 431 emits `path_blocked_by_slope`). There is no
  check for "am I on a road," and no off-road speed penalty tied to roads.
- `battle_system/nodes/squad.gd:464-467`: infantry move via `global_position += velocity * delta`
  then `_snap_to_terrain()`. No navmesh, no road dependency.
- `firebase_system/job_system/worker_controller.gd:196-289` (`_process_moving`): workers path to a
  job's work position over open terrain, with proactive jungle detection
  (`_check_terrain_ahead`, lines 390-423) and auto path-clearing flatten jobs
  (`_start_path_clearing`, lines 426-488). Jungle/slope are handled by spawning clear/flatten
  jobs — never by requiring a pre-existing road.
- `docs/gdd terrain-clearing.md:53` states bulldozers "Requires road access to reach work site
  (or very slow off-road)." **This is not implemented anywhere** — grep for road-vs-offroad speed
  differentiation in movement returns nothing. It is a design intent, not code.

### The real reason a bulldozer "never cuts the first road"
- Road jobs are created **exclusively** by `logistics_system/supply_chain_manager.gd`:
  - `_on_job_created` (lines 72-89) fires only for `BUILD_STRUCTURE` jobs whose `building_type`
    is `SUPPLY_DEPOT` (`_is_supply_depot_type`, lines 91-93), then calls
    `_auto_build_road_to_position`.
  - `_register_depot` (lines 133-159) auto-builds a road only when `_supply_depots.size() > 1`.
  - `_create_road_jobs` (lines 329-390) is the only producer of `BUILD_ROAD` jobs.
- There is **no player command** that creates a standalone road-cut job from a firebase outward.
  The bulldozer's manual `cut_path()` is explicitly disabled under WorkerController control:
  `battle_system/units/bulldozer.gd:617-620` (`push_warning("...use job system for cut_path")`
  and early `return`).
- Consequence: if the player places one firebase/depot and expects to task a bulldozer to carve a
  road out, **no BUILD_ROAD job is ever produced**, so `WorkerController._find_work`
  (`worker_controller.gd:537-572`) finds nothing and the unit stays IDLE. This is the actual
  "idles / never triggers road cutting" symptom — a *missing job-creation trigger*, not a
  pathfinding chicken-and-egg.

### Secondary note on job gating (relevant to "fail to path")
- `create_road_job` (`job_system.gd:1354-1390`) attaches CLEAR_TERRAIN (+ optional FLATTEN)
  prerequisites via `_create_prerequisites`. `UnifiedJob.can_be_worked()`
  (`unified_job.gd:344-354`) returns false until every prerequisite is COMPLETE. So a BUILD_ROAD
  job through jungle is PENDING until its clear job finishes. This is correct behavior, but it
  means the road only becomes workable (and visible) after clearing completes — reinforcing the
  H3 timing coupling below.

---

## H2 — "Below-map spawn = terrain/chunk init timing" — CONFIRMED (mechanism)

**Verdict: CONFIRMED in mechanism. Correction: there is no navmesh — it is a heightmap-readiness
race, exactly the "spawn height timing" issue noted in prior Beads memory.**

### The 0.0 fallback
- `terrain/core/unified_terrain_engine.gd:252-255`:
  ```
  func get_height_at(world_pos: Vector3) -> float:
      if not _heightmap:
          return 0.0
      return _heightmap.sample_world(world_pos.x, world_pos.z)
  ```
  Before `_heightmap` exists, every height query returns **0.0**.
- `_heightmap` is only assigned in `init_from_heightmap` (`unified_terrain_engine.gd:108-113`),
  which sets `_is_initialized = true` and emits `terrain_ready`.

### The async window
- `scenes/test_combined.gd:168` `await _setup_local_terrain_async()`, then `:311`
  `await local_terrain.generate_terrain(42)`, then `:322-323`
  `unified_terrain.init_from_heightmap(local_terrain.heightmap)`. The heightmap is therefore
  populated **after** an `await` chain — several frames into scene load, after autoloads have run.
- Autoload order (`project.godot:29-57`) starts terrain autoloads early, but their `_heightmap`
  stays null until that deferred `init_from_heightmap` call. Any spawn/snap in between reads 0.0.

### Spawn code trusts destination Y and does not re-snap
- `reinforcement_system/reinforcement_manager.gd:243-256`: sets
  `unit.position = spawn_pos + offset` where `spawn_pos = request.destination.global_position`
  (line 241) and `offset.y = 0` (line 249). It **never calls `get_height_at` and never snaps.**
  If the destination node is itself at Y=0 (because it was placed before terrain init) or terrain
  isn't ready, the unit is planted at Y=0.

### Unconditional snap slams units to 0 during the window
- `battle_system/nodes/squad.gd:472-476` (`_snap_to_terrain`) and
  `battle_system/units/bulldozer.gd:543-546`: both do
  `global_position.y = terrain.get_height_at(global_position)` with no readiness guard. During the
  not-ready window this forces Y=0. With real surface elevation > 0, the unit ends up **below** the
  surface.
- Self-correction exists (idle/moving units re-snap every physics frame once terrain is ready —
  `squad.gd:514-530`, `bulldozer.gd:341`), so for actively-processing units the below-terrain
  state is usually transient. It **persists** for:
  - Hidden reinforcements spawned with `set_physics_process(false)`
    (`reinforcement_manager.gd:253-254`) that are revealed at a destination anchored at Y=0.
  - Any unit whose destination/parent was itself mis-placed at Y=0 during the same race.

**Net:** H2's root cause is the heightmap `0.0` fallback combined with async init and spawn code
that neither queries height nor waits for `terrain_ready`. The "navmesh/chunk" framing is
inaccurate (no navmesh in this project; movement is direct-position), but the "terrain not
initialized before a ground-Y query" framing is correct.

---

## H3 — "Dirt road visual never wired; RoadDecalRenderer orphaned" — CONFIRMED + PARTIAL

**Verdict: CONFIRMED that `road_decal_renderer.gd` is orphaned. PARTIAL because a different,
solid-color road visual (`RoadSegmentNode`) IS wired — but it is textureless and only shows once
the job is actually worked.**

### RoadDecalRenderer is dead code
- Grep for `RoadDecalRenderer` / `create_for_job` / `create_for_waypoints` / `create_for_spline`
  across `firebase_system/` and `logistics_system/` returns matches **only inside
  `road_decal_renderer.gd` itself**. No autoload, scene, or other script instantiates it.
- It is the only consumer of the dirt texture: `ROAD_TEXTURE_PATH =
  "res://assets/textures/terrain/dirt_road.png"` (`road_decal_renderer.gd:15`, loaded at 51-52).
  Because the class is never instantiated, **`dirt_road.png` is never applied to anything** — this
  is precisely "no visible dirt road texture appears."

### The visual that IS wired: RoadSegmentNode (solid color, progress-gated)
- `firebase_system/job_system/job_system.gd:246-259` (`_create_job_node`, BUILD_ROAD branch) and
  `:1384-1387` (`create_road_job`) instantiate `RoadSegmentNode` for every BUILD_ROAD job.
- `firebase_system/nodes/road_segment_node.gd:69-98` (`_setup_visuals`): the road mesh uses a
  **solid** `StandardMaterial3D` with `albedo_color = Color(0.5,0.4,0.3)` (line 72) — no
  `albedo_texture`. It is created `visible = false` (line 80).
- `road_segment_node.gd:189-212` (`add_work` / `_update_visuals`): the mesh is only shown once
  `current_progress > 0.1`. Work is delivered by `JobSystem._add_work_to_node`
  (`job_system.gd:755-759`) which forwards worker progress to the node.
- Therefore the road becomes visible only if a worker actually applies BUILD_ROAD work. If the job
  is gated behind an unfinished CLEAR_TERRAIN prereq, or no worker reaches it, or (per H1) no job
  was ever created, **nothing renders** — matching "terrain clears but no road appears."

### Bonus disconnect found (convoys ignore roads)
- `reinforcement_system/convoy_manager.gd:269-282` (`_generate_route`) builds a straight-line
  `lerp` route and **never queries `RoadNetwork`**. Per ADR-0006 convoys were meant to path via
  `RoadNetwork.find_path`. This `ConvoyManager` is entirely disconnected from the road graph, so
  even a completed road provides no benefit to these convoys. (The ADR's road-aware pathing lives
  in a separate `SupplyTruck` class; the two supply movers are not unified.) Flagged as an open
  issue, not a direct cause of the three reported bugs.

---

## Root-Cause Chain (how the bugs interact)

1. **Heightmap async init -> 0.0 fallback (H2).** Terrain autoloads exist but `_heightmap` is
   populated several frames later via an `await` chain in `test_combined.gd`. Any spawn or
   `_snap_to_terrain` in that window reads `get_height_at() == 0.0`. Units (and any node placed by
   trusting `destination.global_position`) land at Y=0, below surfaces with elevation > 0.

2. **Road behavior is job-triggered only by depot placement (H1's real form).** The clear-and-cut
   road loop is CLEAR_TERRAIN -> FLATTEN_AREA -> BUILD_ROAD, produced solely by
   `SupplyChainManager` on Supply Depot creation. With no depot (or only one), no BUILD_ROAD job
   exists, so idle bulldozers/engineers find no work. The GDD's `update_road_cutting()` and
   "requires road access" are not in the code at all.

3. **Even a valid road job renders nothing until worked, and never with a texture (H3).** The
   textured `RoadDecalRenderer` is orphaned; the wired `RoadSegmentNode` is solid-color and hidden
   until >=10% BUILD_ROAD progress. So the visual is doubly fragile: it depends on (a) a job
   existing (blocked by #2) and (b) a worker reaching and working it (which #2 and, transiently,
   #1's prereq gating undermine). The result the player sees — terrain clears (CLEAR_TERRAIN
   completes and removes billboards via `job_system.gd:985-991`) but no road strip appears.

The three bugs are mutually reinforcing: the spawn-height race (H2) can strand the very workers
that would clear/build; the missing road-cut trigger (H1) means the job often never exists; and
even when it does, the road visual is textureless and progress-gated (H3).

---

## Proposed Fix Directions (design-level, no code)

1. **Gate ground-Y queries on terrain readiness.**
   - Give `get_height_at()` a "not ready" contract (return `NAN` / a sentinel, or expose
     `is_ready()`), and have spawn/snap callers **defer to `terrain_ready`** before placing or
     snapping units. Cheapest: have `reinforcement_manager._spawn_units` and both `_snap_to_terrain`
     implementations skip the snap (leave prior Y) when terrain is not initialized, rather than
     writing 0.0.

2. **Make spawn code query height explicitly.**
   - `reinforcement_manager._spawn_units` should call `get_height_at(spawn_pos)` (once terrain is
     ready) instead of trusting `destination.global_position.y`. Same for any hidden-then-revealed
     reinforcement: re-snap on reveal.

3. **Add a first-class "cut road" job trigger.**
   - Provide a player order (drag a road path, or "connect firebase A -> B") that calls the
     existing `SupplyChainManager.force_build_road` / `JobSystem.create_road_job`. This removes the
     dependency on placing a second Supply Depot to get any road at all, and matches the GDD's
     "player draws path" intent. Keep the job-based execution; just add the entry point.

4. **Resolve the road-visual ownership.**
   - Decide on ONE road renderer. Either (a) retire `RoadDecalRenderer` and give `RoadSegmentNode`
     the `dirt_road.png` texture + UVs it currently lacks, or (b) wire `RoadDecalRenderer` into the
     BUILD_ROAD job (it already has `create_for_job`) and retire the solid-color mesh. Do not keep
     both. Whichever survives should show a faint "planned road" ghost before work starts so the
     player gets feedback even at 0% progress.

5. **Unify convoy pathing with RoadNetwork.**
   - Point `ConvoyManager._generate_route` at `RoadNetwork.find_path` (or consolidate on
     `SupplyTruck`) so finished roads actually benefit supply movement — otherwise the whole
     carve-a-road loop has no payoff for this convoy class (Pillar 3).

---

## Open Questions (need a decision / further trace)

1. **Which road renderer is canonical?** `RoadDecalRenderer` (textured, orphaned) vs
   `RoadSegmentNode` (solid, wired). Needs an owner decision before either is fixed.
2. **Is the async terrain init in `test_combined.gd` representative of the shipping mission flow,**
   or a test-scene artifact? If missions init terrain synchronously before spawns, H2 may be
   test-only. Prior Beads "spawn height timing" + "vegetation timing" notes suggest it recurs.
3. **Should road cutting be player-directed or purely automatic (depot-to-depot)?** The GDD implies
   player-drawn roads; the code implements only automatic depot linking. This is a Pillar-1/Pillar-3
   design call that gates fix #3.
4. **Two supply movers** (`reinforcement_system/convoy_manager.gd` straight-line vs ADR-0006
   `SupplyTruck` + `RoadNetwork`): are both intended to ship, or should they be consolidated?
5. **Does the destination anchor (firebase/LZ) get a correct Y itself?** If firebases are also
   placed during the terrain-not-ready window, they inherit Y=0 and propagate it to spawned units —
   worth confirming firebase placement timing vs `terrain_ready`.
