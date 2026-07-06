# Performance Audit — RealVietnamRTS
**Architect:** Performance Analyst (War Room)
**Date:** 2026-07-06
**Scope:** Diagnosis only. No game code modified.
**Budget context:** Target 60 FPS (16.67 ms), 300–500 units, AI budget 2–3 ms/frame (per GAME_BIBLE / technical-preferences).

---

## Executive Summary

The freezes are **not** caused by the leads from prior audits (group scans, missing spatial hash). The SpatialHashGrid **is** integrated (autoload, used by Squad for separation/targeting), and navmesh rebakes are **disabled** (`terrain_manager.gd:314` is commented out). The real killers are two clearing-path defects plus unbounded per-squad per-frame work:

1. **CRITICAL — Terrain clearing re-materializes vegetation MultiMeshes every physics frame.** `Squad._process_clearing()` advances the clearing zone 60×/sec, and every single advance triggers a full `TerrainGrid` area rewrite → `cell_updated` signal → **synchronous** per-chunk vegetation regeneration (`regenerate_chunk` + grass MultiMesh rebuild + node `queue_free`/re-add + a `print()` per chunk). One clearing squad forces 1–4 chunks × thousands of tree/grass transforms rebuilt in interpreted GDScript **every frame**. This alone explains "freezing big time" during clearing/road work.

2. **CRITICAL — Bulldozer calls a method that does not exist, every physics frame.** `bulldozer.gd:357` and `:392` call `TerrainClearingSystem.apply_clearing_damage(...)` unguarded; the autoload (`firebase_system/terrain_clearing.gd`, 129 lines, read in full) has **no such method**. While a bulldozer clears or cuts a road path this raises a script error 60×/sec — error/console spam is one of the most expensive things you can do in a debug Godot session, and the feature silently does nothing.

3. **HIGH — Every squad runs its full subsystem stack every physics frame** (morale + 30 m spatial query, cover, resources, blackboard sync, per-soldier piece animation, terrain snap). `AITickManager` exists but only staggers `SquadCommanderAI`. At 300–500 squads this is far past the 2–3 ms AI budget even before combat.

Fixing items 1 and 2 (both small, surgical changes) should eliminate the hard freezes. Item 3 caps the steady-state frame time so the unit-count target becomes reachable.

---

## Ranked Findings

### CRITICAL-1: Per-frame vegetation chunk re-materialization during terrain clearing
**The freeze.** Full call chain, every physics frame per clearing squad:

- `battle_system/nodes/squad.gd:1134-1136` — `_process_clearing()` calls `terrain.advance_clearing(zone_id, CLEARING_RATE * delta)` **every physics frame** while clearing.
- `terrain/terrain_integration.gd:398-401` — forwards to `ClearingSystem.advance_clearing`.
- `terrain/systems/clearing_system.gd:106-126` — `advance_clearing()` ends with `_update_terrain_grid(zone)` on **every call** (line 126), not just on stage transitions.
- `terrain/core/terrain_grid.gd:612-629` — `set_clearing_stage_area()` rewrites every cell in the zone (r=15 m → ~44 cells at 4 m cells) then `cell_updated.emit(region)` — every frame.
- `terrain/terrain_integration.gd:605-607` — `_on_terrain_grid_updated()` calls `_on_vegetation_updated(region)` **synchronously, with no debounce** (unlike the `_on_unified_terrain_modified` path at :610-621, which correctly batches at 0.2 s).
- `terrain/terrain_integration.gd:556-568` — for each affected chunk (1–4 chunks for a 15 m zone on 64 m chunks): `vegetation_manager.regenerate_chunk(coord, heightmap)` **and** `billboard_vegetation.generate_for_chunk(...)`.
- `terrain/vegetation/vegetation_manager.gd:424-434` — `regenerate_chunk` = rebuild terrain types from grid + `clear_chunk_visuals` (**queue_free of live MultiMeshInstance3D nodes**) + `_materialize_vegetation` + `_materialize_grass`.
- `terrain/vegetation/vegetation_manager.gd:622-670, 674-721` — materialization builds `PackedFloat32Array` buffers of 12 floats × N instances **in GDScript** (jungle chunks carry hundreds–thousands of trees plus grass), allocates new `MultiMesh` + `MultiMeshInstance3D` nodes, and **prints a line per chunk** (`:668`).

**Quantified:** 60 Hz × (1–4 chunks) × (O(thousands) transform-buffer rebuild + node churn + print). Conservatively tens of ms per frame per clearing squad; several squads/bulldozers clearing at once compounds it. Secondary consumer: the same `cell_updated` also feeds `JobSystem._on_terrain_modified` (`firebase_system/job_system/job_system.gd:92-98`) — that side is correctly coalesced, proving the debounce pattern already exists in the codebase.

**Expected impact of fix:** eliminates the multi-second hitches during clearing/road cutting.

### CRITICAL-2: Bulldozer calls nonexistent `apply_clearing_damage` every frame
- `battle_system/units/bulldozer.gd:356-357` (CLEARING) and `:391-392` (PATH_CUTTING): `TerrainClearingSystem.apply_clearing_damage(global_position, ..., rate * delta)` — **no `has_method` guard**.
- `firebase_system/terrain_clearing.gd` (the `TerrainClearingSystem` autoload) defines only `is_cleared / get_clearing_state / mark_area_cleared / instant_clear / get_cleared_area_count` — **`apply_clearing_damage` does not exist anywhere** in the project except behind `has_method` guards (`fire_hazard.gd:236`, `infantry_test.gd:110`) and the archived test.
- Result: a script runtime error 60×/sec for the entire duration of any bulldozer clear or road-cut. In the editor, each error is formatted, stack-traced and pushed to the debugger — this alone can drop a session to single-digit FPS ("road cutting freezes"). Same file: `bulldozer.gd:376-377` references `set_terrain_state`, which also exists nowhere (guarded, so it silently no-ops — the FLATTENING result is never applied).

### HIGH-1: Squad god-object runs everything every physics frame, no tick staggering
`battle_system/nodes/squad.gd:326-388` (`_physics_process`) unconditionally runs, per squad per frame:
- `_sync_blackboard()` (`:3395-3435+`) — ~25 dictionary writes/frame, then `behavior_tree.update(delta)`.
- `_process_resources` (`:1564`) — timer-gated internally (OK).
- `_process_morale` (`:2105`) — **not** timer-gated: `_update_morale_modifiers()` every frame → `_find_nearest_firebase()` (EntityCache linear scan of firebases, `battle_system/systems/entity_cache.gd:128-143`) **and** `_count_nearby_allies()` (`:2157-2173`) → `SpatialHashGrid.get_units_in_radius(pos, 30.0)` — a fresh typed-Array allocation + 9–25 cell scan + `is_in_group()` string checks per neighbor, **every frame per squad**. Also `_update_morale_indicator()` (`:2177-2206`) writes Label3D text/modulate every frame.
- `_process_cover_behavior` (`:1356`) — timer-gated check (2 s TTL cache in CoverSystem, OK), but `CoverSystem.find_nearest_cover` (`battle_system/systems/cover_system.gd:126-141`) does `get_nodes_in_group` over all cover groups with full distance loop per cover-seeking squad.
- `_calculate_separation` (`:480-510`) — a second `get_units_in_radius` allocation per frame (movement **or** idle separation, `:441`, `:515`).
- `_update_animation` (`:3267`) → `_update_piece_animation` (`:3309-3319`) — `animator.update(delta)` per soldier (up to 12) in GDScript, no distance/LOD gating.
- `_snap_to_terrain` (`:472-476`) — `get_node_or_null("/root/TerrainIntegration")` **string-path lookup every call**, called 1–3× per squad per frame (also `bulldozer.gd:543-546`).

**Quantified:** 300 squads → ≥600 spatial-grid queries + ≥600 typed-array allocations + 3,600 piece-animator updates + 300 label writes **per frame**. `AITickManager` is an autoload but the only registration is `SquadCommanderAI` (`squad.gd:2070-2072`); nothing else in the game uses it (only reader: `infantry_test.gd:219`).

### HIGH-2: AIDirector full battlefield scan every frame
`battle_system/ai/ai_director.gd:127-144` — `_process` runs `_update_stress` + `_assess_battlefield` **every frame**:
- 5× `get_tree().get_nodes_in_group(...)` per frame (`:162, :174, :262, :273, :284` — firebases ×2, player_units ×2, enemy_units ×1).
- Iterates every player and enemy unit twice per frame with reflection-style `has_method("get")/get("current_health")` property access.
**Quantified:** at 400 units ≈ 800+ reflective property reads + 5 group-array builds per frame — likely 1–3 ms/frame alone. Trivially throttleable to 0.5–1 s with zero gameplay difference.

### HIGH-3: Possible double behavior-tree update
`battle_system/ai/squad_behaviors.gd:29-37` — the `SquadBehaviors` **autoload** updates every registered tree in `_process`, while `squad.gd:331-333` **also** calls `behavior_tree.update(delta)` in `_physics_process`. If `assign_behavior` hands the same `BehaviorTree` to both (squad stores it and SquadBehaviors keeps it in `_squad_trees`), every tree ticks twice per frame — 2× AI cost and potential double-issued actions. Needs a one-line trace to confirm which reference `squad.behavior_tree` holds.

### MEDIUM-1: Group scans still widespread; EntityCache under-used
131 `get_nodes_in_group` occurrences across 46 .gd files (measured this audit). Most are event-driven or timer-gated (better than the prior "40 files in _process" lead), but per-frame/per-event hot ones remain: `cover_system.gd:132,150` (per cover query per squad), `clearing_system.gd:368` (`_notify_jungle_zones` per clear event), `tree_node_manager.gd:96` (iterates entire "trees" group with per-tree distance math on every spawn request), `tactical_minimap.gd` (8 scans per redraw). `EntityCache` (`battle_system/systems/entity_cache.gd`) implements exactly the right dirty-flag pattern but only caches firebases/depots/LZs/HQs — not units or cover.

### MEDIUM-2: Session-length degradation — signal & cache hygiene
Measured this audit: **311 `.connect(` vs 13 `.disconnect(`** across the project; only **9 files** implement `_exit_tree` (squad.gd does clean up its one global connection at `:320-323`). Transient nodes (projectiles, effects, UI cards) connecting to autoload signals keep the autoload's connection list growing; Godot drops connections on object free, but any lambda/bound-argument connection to a long-lived autoload pins objects. Additionally: `CoverSystem._unit_cover_cache` (keyed by instance-id, `cover_system.gd:59-75`) is never pruned; `VegetationLODManager._tracked_trees` (`vegetation_lod_manager.gd:20-23`) only compacts during its 10 Hz sweep; `SpatialHashGrid._cells` never sheds empty cell arrays. Consistent with "gets worse the longer the playtest runs."

### MEDIUM-3: Per-frame allocations & string building
- Every `SpatialHashGrid.get_units_in_radius/get_enemies_in_radius` call allocates a new `Array[Node3D]` (`spatial_hash_grid.gd:110-142`) — hundreds/frame at scale (see HIGH-1).
- Main scene (`scenes/test_combined.gd:919-957` — note the **shipping main scene is a test arena**, `project.godot: run/main_scene="res://scenes/test_combined.tscn"`) rebuilds the whole HUD string with ~10 concatenations + 2 `get_node_or_null` path lookups **every frame**.
- `squad.gd` `_sync_blackboard` — ~25 Dictionary key writes per squad per frame.

### MEDIUM-4: Console/print load in hot paths
`print()` in per-frame-reachable code: `vegetation_manager.gd:668` (fires every frame during clearing — see CRITICAL-1), plus 26 prints in squad.gd, 42 in battle_hud.gd, 31 in placement_controller.gd, 81 in the main test_combined.gd, 28 in job_system.gd (many event-driven but frequent during construction). No global debug flag; `TestDaemon` autoload (`test_daemon/daemon_autoload.gd`) always runs, writing health JSON to disk every 2 s even in normal play.

### MEDIUM-5: Three coexisting terrain systems
Autoloads: `TerrainEngine` (flagged 0-usage in the 2026-05-18 audit, still registered), `UnifiedTerrain`, and `TerrainIntegration` (which owns `TerrainManager` + `TerrainGrid` + `ClearingSystem` wiring). Height data lives in **three** places (TerrainEngine/UnifiedTerrain heightmap, `terrain_manager.heightmap` — a `.duplicate()` copy at `terrain_manager.gd:167`, and `TerrainGrid._elevation`), kept in sync via `update_region_from_heightmap` on every modification (`terrain_integration.gd:613-614`). Each chunk rebuild also re-cooks a trimesh collision shape (`terrain_chunk.gd:290`). Rebuilds are at least budgeted (8 ms/frame, `terrain_manager.gd:53`) — but 8 ms is half the frame budget while active.

### LOW: Confirmed non-issues (leads that did NOT hold up)
- **SpatialHashGrid is integrated** (autoload in project.godot; used by squad separation `:488`, auto-engage `:613`, ally counting `:2162`). Its `_process` re-bins all units each frame (`spatial_hash_grid.gd:27-43`) — fine at 500 units.
- **No navmesh rebakes at runtime**: the only `NavigationServer3D` bake call (`terrain_chunk.gd:316`) is reachable only via `bake_navigation()`, whose sole caller is commented out (`terrain_manager.gd:314`). Navmesh is not the freeze source.
- Physics tick rate: no override in project.godot (default 60); Jolt per Godot 4.6 default. No debug/verbose settings found.
- Most managers (JobSystem, SupplyManager, InsertionManager, minimap, LOD manager, TestDaemon polling) are correctly timer-gated.

---

## Likely Cause(s) of the Freezes

1. **During clearing / road cutting (the "freezing big time" state):** CRITICAL-1 — synchronous per-frame vegetation chunk re-materialization (thousands of MultiMesh transforms rebuilt in GDScript + node churn + print spam, 60×/sec per clearing unit), compounded by CRITICAL-2 (bulldozer script-error spam at 60 Hz) whenever a bulldozer is the one doing it.
2. **Steady-state slowdown that scales with army size:** HIGH-1 + HIGH-2 — every squad's full per-frame stack (double spatial queries, morale scans, per-soldier animators) plus AIDirector's per-frame battlefield census. This burns the frame budget before rendering starts, so any spike (chunk rebuild at 8 ms, construction burst) tips into visible stutter.
3. **Worsens over a session:** MEDIUM-2 growth (signal lists, cover cache, tracked-tree arrays, spatial-grid cells) plus MEDIUM-4 console volume.

---

## Top 5 Recommended Fixes (design-level, impact ÷ effort)

1. **Debounce clearing-driven visual updates** (fixes CRITICAL-1, ~15 lines).
   In `clearing_system.gd:advance_clearing`, call `_update_terrain_grid(zone)` only on **stage transitions** (inside the `zone.progress >= 1.0` branch), not every tick; and/or route `terrain_integration.gd:_on_terrain_grid_updated` through the **existing** `_terrain_dirty_regions` + 0.2 s batch used by `_on_unified_terrain_modified`. The debounce pattern already exists 5 lines below the offending handler.

2. **Fix or guard the bulldozer clearing API** (fixes CRITICAL-2, ~20 lines).
   Implement `apply_clearing_damage(pos, radius, amount)` on `TerrainClearingSystem` (delegate to a ClearingSystem zone create-or-advance), or change bulldozer to the zone API squads use — and throttle it to ~4 Hz, not 60 Hz. Also resolve the phantom `set_terrain_state`. This both removes the error storm and makes bulldozer clearing actually function.

3. **Stagger squad subsystem ticks** (fixes HIGH-1, medium effort, biggest steady-state win).
   Move `_process_morale`/`_update_morale_modifiers` (incl. `_count_nearby_allies`) and `_update_morale_indicator` to a 0.25–0.5 s timer (the file already uses this pattern for cover/resources/auto-engage); reuse one separation query result per frame instead of separate movement/idle calls; cache the `TerrainIntegration` node reference in `_ready` instead of `get_node_or_null` per frame; gate piece-animator updates by camera distance (Animation LOD at 30/80/150 m is already specified in CLAUDE.md). Route all of it through the existing, unused `AITickManager` buckets.

4. **Throttle AIDirector and extend EntityCache** (fixes HIGH-2, ~10 lines).
   Run `_update_stress`/`_assess_battlefield` on a 0.5–1 s timer, and add `player_units`/`enemy_units` cached arrays to `EntityCache` (signal-invalidated, same as firebases) so the director and HUD stop rebuilding group arrays.

5. **Silence hot-path logging and audit the double BT tick** (fixes MEDIUM-4 + HIGH-3, small effort).
   Add a project-wide `DEBUG_LOGS` flag; remove/gate `vegetation_manager.gd:668` and all prints reachable per-frame; disable `TestDaemon` outside test runs. While in there, confirm whether `SquadBehaviors._process` and `Squad._physics_process` tick the same `BehaviorTree` twice and remove one path.

**Follow-on (not top-5 but queued):** prune `CoverSystem._unit_cover_cache` on `unit_died`; consolidate the three terrain height stores (pick UnifiedTerrain per the migration plan, retire the unused `TerrainEngine` autoload); move the main scene off `test_combined.tscn` for real playtests.
