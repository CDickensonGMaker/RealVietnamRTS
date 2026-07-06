# Architecture Audit — RealVietnamRTS Whole-Game Health
**Role:** Technical Director (War Room Council)
**Date:** 2026-07-06
**Baseline:** Full audit of 2026-05-28 (CODE_AUDIT_REPORT.md, AUDIT_FINDINGS_SUMMARY.txt, production/war_room/analysis/*)
**Scope:** Delta verification, structure map, autoloads, pillar health, risk register. DIAGNOSIS ONLY — no game code modified.

---

## 1. Executive Summary

The codebase is **211 GDScript files, ~95.7K LOC** (excl. addons/.godot). Since the last audit, real remediation happened — orphan deletion, autoload reordering, EntityCache introduction — **but almost none of it is committed**. The last commit is `ad1071e` (2026-05-29); the last file modification is 2026-05-29 21:54. The project has been **dormant for ~5.5 weeks with 279 uncommitted working-tree changes**, including 21 file deletions and the entire autoload restructure. This is the single largest risk in the project right now: one careless `git checkout .` or disk failure erases six weeks of cleanup.

The second headline finding: **the game does not have a game.** `project.godot` sets `run/main_scene="res://scenes/test_combined.tscn"`, whose 1,740-LOC script hand-rolls its own terrain setup, convoy state machine, and a CH-47 Chinook supply loop — bypassing `helicopter_system/`, `reinforcement_system/`, and `logistics_system/` entirely, and violating both the project's own Godot-first rules (everything built via `.new()` in code) and the PRD's MVP exclusions (Chinook is explicitly excluded in PRD §21.4).

Third: **Pillar 4 (Doctrine) is dead at runtime.** `battle_system/systems/doctrine_manager.gd` exists but is never autoloaded or instantiated; `core/save_manager.gd` queries `/root/DoctrineManager` which is always null. Same pattern for `/root/InsertionManager` and the entire `ReinforcementManager` (zero references anywhere in scenes or scripts). Two of the game's pillars exist only as specs and unreachable code.

Verdict: **CONCERNS — stabilize before building.** The delta shows good instincts (cleanup was correctly targeted) but the structural debts named in May — terrain dual-source-of-truth, Squad god object, supply fragmentation — are all still open, and a new one (test-scene-as-game) has calcified.

---

## 2. Delta Since Last Audit (2026-05-28 → 2026-07-06)

### 2.1 Activity profile
- **Commits since baseline:** 2 (`9b2cdee` auto-road creation, `ad1071e` remove unused building types, both 2026-05-28/29).
- **Uncommitted working tree:** 279 changes (modified/deleted/untracked), all dated ≤ 2026-05-29. No file in the repo has been touched since. The "delta" is one uncommitted mega-batch, not committed history.

### 2.2 Prior findings — FIXED (but uncommitted)
| Finding (May audit) | Status today | Evidence |
|---|---|---|
| Wrong autoload order | **FIXED — uncommitted** | `git diff HEAD -- project.godot` shows full reorder into dependency tiers (PURE DATA → TERRAIN → BATTLE → SUPPLY → CONSTRUCTION → AI → UI → DEBUG) with comments. JobSystem now after SupplyManager, UI last. |
| Orphaned files (6) | **MOSTLY FIXED — uncommitted deletions** | GONE: `battle_system/ai/ai_context.gd`, `battle_system/ai/utility/utility_scorer.gd`, `battle_system/camera/battle_camera.gd`, `battle_system/data/vietnam_locations.gd`, `logistics_system/route_planner.gd`. Deletions sit in the working tree as ` D` entries. |
| Group-scan lookups | **PARTIALLY FIXED** | New `EntityCache` autoload (`battle_system/systems/entity_cache.gd`), 13 `/root/EntityCache` call sites; `SupplyManager` now prefers it over `get_nodes_in_group()`. |
| SelectionManager unused | **FIXED** | Now accessed 11× via `get_node_or_null("/root/SelectionManager")`; `selection_manager.gd` modified in working tree. |
| Unused building enums | **FIXED — committed** | `ad1071e` removed AMMO_BUNKER, FUEL_DEPOT, RADAR_DOME. |

### 2.3 Prior findings — STILL OPEN
| Finding | Status today | Evidence |
|---|---|---|
| TerrainGrid vs UnifiedTerrain duplication (**CRITICAL** in May) | **OPEN** | `terrain/core/terrain_grid.gd` (859 LOC) and `terrain/core/unified_terrain_engine.gd` both alive; both still claim "single source of truth"; `terrain/terrain_integration.gd` still bridges both. TerrainGrid referenced from `firebase_system/job_system/job_system.gd`, `terrain/systems/clearing_system.gd`, `terrain/vegetation/vegetation_manager.gd`, `scenes/test_combined.gd`. |
| Squad.gd god object | **OPEN** | `battle_system/nodes/squad.gd` = **3,667 LOC** (was 3,749; net −82). 7.3× the project's own 500-LOC forbidden-pattern limit. |
| Duplicate depot tracking | **OPEN** | `logistics_system/supply_chain_manager.gd:27` still holds `var _supply_depots: Array[Node3D]` while `reinforcement_system/supply_manager.gd:14` holds `supply_points`. Two registries, two registration paths. |
| Weak signal cleanup | **OPEN** | Only 9 files codebase-wide implement `_exit_tree`; `squad.gd` has 9 `connect()` vs 2 disconnect/is_connected sites. |
| MoveOrderHandler / FloatingLabelManager unused autoloads | **OPEN** | 0 references by name or `/root/` path; both still registered in `project.godot`. |
| Zip clutter (`campaign.zip`) | **WORSE** | Now 4 zips + `nul` (see §3.4). |

### 2.4 NEW issues since baseline
1. **Uncommitted-work exposure (CRITICAL):** all §2.2 fixes plus large edits to `firebase_system/building_data.gd` (88 KB), `construction_zone.gd`, `scenes/test_combined.gd`, `test_daemon/daemon_autoload.gd` exist only in the working tree.
2. **Test harness is the shipped game (CRITICAL):** main scene = `scenes/test_combined.tscn`; its script duplicates supply/convoy/helicopter logic (see §3.2).
3. **Phantom autoload references (HIGH):** code queries `/root/DoctrineManager` (`core/save_manager.gd:211,320`), `/root/InsertionManager` (`reinforcement_system/reinforcement_manager.gd:165`, `test_daemon/daemon_autoload.gd:1428`), `/root/TerrainFlatteningSystem` (`test_daemon/daemon_autoload.gd:854,913` — the autoload is named `TerrainFlattening`), `/root/UnitSpawner` (`daemon_autoload.gd:1343`). None are registered; every call silently returns null via `get_node_or_null`, so features no-op without error.
4. **Stale CLAUDE.md architecture (HIGH for an agent-driven project):** the Key Directories table lists `sog_system/` and `map_maker/` — **neither exists**. The autoload table lists ReinforcementManager, InsertionManager, AirSupportManager, WeatherSystem as autoloads — **none are registered** — and omits ~19 that are. Every AI agent session ingests this wrong map.

---

## 3. Duplicate / Overlapping Systems

### 3.1 System folder map (files / LOC)
| Folder | .gd files | LOC | Health |
|---|---|---|---|
| battle_system | 94 | 38,007 | Core; contains god object + misc UI/AI/data — doing too much |
| firebase_system | 24 | 15,082 | Active, healthy commit trail; 5 files >800 LOC |
| terrain | 33 | 13,199 | Fragmented (3 engines + facade) |
| helicopter_system | 9 | 3,387 | **Unwired** — `insertion_manager.gd` (805 LOC) referenced by no scene |
| fortification_system | 7 | 3,316 | Overlaps firebase_system (see 3.3) |
| reinforcement_system | 4 | 1,832 | **Dead at runtime** — ReinforcementManager referenced nowhere |
| tunnel_system | 5 | 1,680 | Built, MVP-excluded content |
| village_system | 4 | 1,456 | Built, disconnected, MVP-excluded (unchanged since May) |
| logistics_system | 4 | 1,419 | 1 autoload + 3 deferred orphans (ferry_manager, ferry_route, resource_flow_system) |
| campaign | 3 | 1,200 | Spec-only data classes |
| airplane_system | 2 | 613 | Fixed-wing — not in MVP roster |
| core | 1 | 400 | `save_manager.gd` — never autoloaded, Pillar 6 dead |
| game | 0 | 0 | Scenes only (61 building .tscn) — fine |

### 3.2 Supply: FOUR competing implementations (HIGH)
The May audit found two; there are now effectively four:
1. `reinforcement_system/supply_manager.gd` — global pool, `supply_points` registry, routes. (Wrong directory: it is logistics, not reinforcement.)
2. `logistics_system/supply_chain_manager.gd` — own `_supply_depots` registry, auto-road building.
3. `reinforcement_system/convoy_manager.gd` — convoy delivery; referenced only by supply_manager and road_network.
4. **`scenes/test_combined.gd`** — hand-rolled `_convoy_state` machine plus a full Chinook supply loop (`_chinook_state`, `_request_chinook_supply()`, `_create_chinook_helicopter()`, lines ~115–1210) that bypasses all three systems above **and** `helicopter_system/insertion_manager.gd`.

Pillar 3 is the game's identity, and there is no canonical answer to "who owns supply?" Any new supply feature written today lands in the wrong place by default.

### 3.3 Fortification vs Firebase (MEDIUM — unchanged since May)
- `fortification_system/defensive_structure.gd` **and** `firebase_system/nodes/defensive_structure.gd` both exist (name collision, divergent implementations).
- `fortification_system/mortar_pit.gd` (780 LOC), `bunker.gd`, `trench.gd`, `machine_gun_nest.gd`, `watchtower.gd` vs firebase_system's trench_node/wire_obstacle_node/building scenes.
- fortification_system is referenced from outside only by `firebase_system/construction_zone.gd` and one archived test. Consolidation target confirmed; no movement since May.

### 3.4 Terrain (HIGH — unchanged since May)
Three engines + facade all autoloaded: `TerrainEngine` (generation), `UnifiedTerrain` (source-of-truth #1), `TerrainGrid` (source-of-truth #2, not autoloaded but instantiated), `TerrainIntegration` (facade, **97** `/root/TerrainIntegration` call sites — the de facto API). Additionally `scenes/test_combined.gd:293` creates its **own local `TerrainManager.new()`**, sidestepping the autoloaded stack. The May recommendation (merge TerrainGrid into UnifiedTerrain, thin the facade) was never executed, and the 97-call-site facade makes it costlier every week.

### 3.5 Root clutter & dead weight (MEDIUM)
- **Zips in repo root (~3.3 MB):** `campaign.zip` (May 20), `test_scenes.zip` (May 26), `freezing big time.zip` (May 27), `tests.zip` (May 28). These are ad-hoc backups of directories that still exist — pure noise, and "freezing big time.zip" is a debugging artifact.
- **File named `nul` (0 bytes, May 21):** `NUL` is a Windows reserved device name; this file was almost certainly created by a `> nul` redirect in the wrong shell. It can break checkouts, archiving tools, and some Windows APIs. Delete via `\\?\` path or Git Bash `rm nul`.
- **Untracked temp assets:** `assets/models/structures/firebase/trench_modular_tmp*.{jpg,png}` (4 temp-named textures), `.blend1` backup files in `assets/models/structures/infrastructure/`.
- **Test sprawl:** `tests/`, `test_scenes/` (incl. `_archive/` with 2,172-LOC `supply_loop_test.gd`), `test_daemon/` (1,664-LOC autoload), plus the two test zips. Three test roots + archives with no runner-of-record.
- **Deferred orphans retained** (deliberate per May decision, still unlabeled in code): `logistics_system/ferry_manager.gd`, `ferry_route.gd`, `resource_flow_system.gd`, `firebase_system/deployable_fob.gd`.

### 3.6 File-size discipline (HIGH)
`technical-preferences.md` forbids files >500 LOC. **25 production files violate it**, topped by `squad.gd` (3,667), `building_data.gd` (2,232), `job_system.gd` (1,874), `test_combined.gd` (1,740 — the main scene), `daemon_autoload.gd` (1,664), `worker_controller.gd` (1,396), `battle_hud.gd` (1,280), `placement_controller.gd` (1,234).

---

## 4. Autoload Review

**Count: 29** (was 27 at last audit — grew despite the recommendation to cut 10).

### 4.1 Ordering — FIXED (uncommitted)
Current `project.godot` groups autoloads in dependency tiers with comments; ordering hazards from May (JobSystem before SupplyManager, UI mid-list) are resolved. This is the correct fix — it must be committed.

### 4.2 Usage verdicts (by name refs + `/root/` path refs)
| Autoload | Verdict |
|---|---|
| GameEnums, BattleSignals, TerrainIntegration (97), JobSystem (40), UnifiedTerrain (22), SupplyManager (18), EntityCache (20), ClearingSystem, SpatialHashGrid, CombatManager, ConstructionManager, SelectionManager (11), VeterancyTracker (9), RoadNetwork (7), TerrainClearingSystem, TreeNodeManager, VegetationLODManager, CoverSystem, RosterManager, BattleHUD, AITickManager, SquadBehaviors, SupplyChainManager, DamageSystem, TerrainEngine | **USED** (varying degrees; several ≤4 refs) |
| **MoveOrderHandler** | **UNUSED — 0 refs.** Remove or wire. |
| **FloatingLabelManager** | **UNUSED — 0 refs.** Remove or wire. |
| **TerrainFlattening** | **BROKEN NAME** — only lookups are `/root/TerrainFlatteningSystem` (daemon_autoload.gd:854,913) → always null. |
| TestDaemon | Debug-only; 1,664 LOC autoload shipping in the runtime config. |

### 4.3 Phantom autoloads (registered nowhere, queried by code)
`DoctrineManager`, `InsertionManager`, `ReinforcementManager` (implied), `UnitSpawner`, `TerrainFlatteningSystem`. Because every access uses `get_node_or_null`, these fail **silently** — doctrine save/load, gunship insertion, and daemon spawning quietly no-op. This is the most insidious defect class in the project: the null-safe style mandated by coding standards is masking configuration rot.

### 4.4 Structural judgment
29 singletons for a solo project is too many, and the split is incoherent: `TerrainClearingSystem` and `TerrainFlattening` (firebase_system files) sit in the terrain tier; `SupplyManager` lives in `reinforcement_system/`; UI autoloads exist while the actual game UI is built inline in `test_combined.gd`. Target: **≤18** after removing the 2 unused, fixing/absorbing TerrainFlattening, merging the terrain stack, and demoting TestDaemon to a debug-only scene.

---

## 5. Pillar Implementation Status

Note the **document authority conflict**: PRD.md ("supersedes GAME_BIBLE.md", Six Pillars, 2026-05-20) vs CLAUDE.md ("GAME_BIBLE.md is the single source of truth", Five Pillars). Assessed against the PRD's six.

| Pillar | Status | Evidence |
|---|---|---|
| **P1 Carve the Map** | **WORKING** — strongest pillar | ClearingSystem, JobSystem, flattening, tree-felling, bulldozer (`battle_system/units/bulldozer.gd`); dense May commit trail (`24cefd0` freeze fix, `fb6aa62` tree-felling). |
| **P2 Network of Firebases** | **WORKING (partial)** | firebase_system 15K LOC: placement_controller, construction_zone, scene-based buildings (`ca3dd80`), TOC activation (`642486a`), building cards (`acf43dc`). Fortification overlap (§3.3) is the debt. |
| **P3 Physical Supply Chains** | **PARTIAL — fragmented** | Depot auto-roads committed (`9b2cdee`); convoy + Chinook loop working *only inside the test harness*. Four competing implementations (§3.2); ConvoyManager and helicopter_system unwired. |
| **P4 Doctrine Over Spam** | **SPEC-ONLY / DEAD** | `doctrine_manager.gd` + `doctrine_data.gd` exist; never registered or instantiated. Doctrine ADRs written (`fc10c74`). Reinforcement pipeline (ReinforcementManager, InsertionManager) has zero live references. |
| **P5 The War Continues** | **PARTIAL** | Auto-fire defenses exist (mg_nest, fortification weapons, ambush/siege managers); patrol logic present in AI controllers and `squad_behaviors.gd`. Player-facing standing orders/convoy schedules not evident outside the test harness. |
| **P6 Persistent Expanding Map** | **SPEC-ONLY** | `core/save_manager.gd` (400 LOC) never autoloaded; its doctrine hook is null; no persistence path is reachable from the running game. `design/gdd/save-system.md` exists. |

### Scope creep vs Bible discipline
- **Chinook**: PRD §21.4 explicitly excludes it; the main scene implements a CH-47 supply loop with a dedicated model (`assets/models/helicopters/ch47_chinook.glb`, untracked). Commit `f41734c` even acknowledges the pivot to Hueys — code was not brought in line.
- **MVP-excluded systems already built**: village_system (1,456 LOC — civic action excluded), tunnel_system (1,680 LOC — VC buildings are MVP but full tunnel network AI is beyond the 4-unit VC roster), airplane_system (613 LOC — fixed-wing not in MVP roster). SOG was correctly deleted.
- **Asset creep**: untracked blends/temp textures, `addons/building_viewer/` tool, ordnance models — content production running ahead of a playable loop.
- 18 GDD specs in `design/gdd/` vs roughly 2.5 pillars actually reachable in a running build. The documentation machine is outpacing the game.

---

## 6. Risk Register (for a solo dev, ordered)

| # | Risk | Sev | Detail |
|---|---|---|---|
| R1 | **Six weeks of uncommitted work** | **CRITICAL** | 279 working-tree changes, incl. all audit remediation. Single point of loss; also blocks any safe refactoring (no clean baseline to diff against). |
| R2 | **Test harness is the game** | **CRITICAL** | `test_combined.tscn` as main scene concentrates terrain init, UI, convoy, and Chinook logic in one 1,740-LOC script. Every new feature grafted here deepens the hole; nothing is reusable for a real mission scene. |
| R3 | **Silent phantom-singleton failures** | **HIGH** | 5 unregistered names queried via `get_node_or_null` — doctrine persistence, insertions, flattening tests all no-op invisibly. Cheap to fix, expensive to debug later. |
| R4 | **Supply ownership undefined** | **HIGH** | 4 implementations (§3.2). Pillar 3 is the game's thesis; building more on this foundation multiplies rework. |
| R5 | **Terrain dual source of truth** | **HIGH** | TerrainGrid vs UnifiedTerrain, 97-call-site facade, plus a rogue local TerrainManager in the main scene. Desync bugs (heights, buildability) will be unattributable. |
| R6 | **Squad.gd god object (3,667 LOC)** | **HIGH** | Every unit feature funnels through one file; 9 connects vs 2 disconnects; merge conflicts with yourself, and AI agents editing it risk collateral damage. |
| R7 | **Stale steering docs (CLAUDE.md, Bible-vs-PRD authority)** | **MEDIUM** | This project is developed largely by AI agents that trust CLAUDE.md; its directory map and autoload table are wrong, so agents are being actively misled every session. |
| R8 | **Autoload sprawl (29)** | **MEDIUM** | 2 dead, 1 mis-named, several ≤4 refs; startup cost and hidden coupling (the May freeze bug was partly this). |
| R9 | **Repo hygiene** | **LOW** | 4 root zips, `nul` reserved-name file, `.blend1`/tmp textures, 3 test roots + `_archive/`. |
| R10 | **Signal cleanup debt** | **LOW (latent)** | 9 `_exit_tree` implementations across 211 files; will surface as dangling-reference crashes once units are created/destroyed at scale (300–500 unit target). |

---

## 7. Recommended Sequencing

**Phase 0 — Preserve (hours, do first, no debate):**
1. Commit the working tree — ideally as 3–4 logical commits (orphan deletions; autoload reorder; building/construction changes; assets) — and **push**. If sorting is too costly, one WIP commit beats zero.
2. Delete `nul` (Git Bash: `rm nul`), move the 4 zips out of the repo (or delete — git is the backup), remove `.blend1` and `trench_modular_tmp*` temp files.

**Phase 1 — Truth (1–2 days):**
3. Fix phantom refs: rename lookups to `TerrainFlattening`; either register `DoctrineManager`/`InsertionManager` or delete the dead call sites; make these lookups fail loudly in debug builds (assert/push_error) so config rot can't hide again.
4. Remove `MoveOrderHandler` and `FloatingLabelManager` from autoloads (or wire them).
5. Rewrite CLAUDE.md's directory map + autoload table to match reality; add one line to PRD/Bible declaring which document is authoritative (recommend: PRD for design, Bible for pillars/exclusions).

**Phase 2 — One owner per domain (1–2 weeks, the real work):**
6. **Supply:** decree a canonical stack — recommend `logistics_system/` owns everything: move `supply_manager.gd` + `convoy_manager.gd` there, make SupplyChainManager consume SupplyManager's registry (delete `_supply_depots`), then extract test_combined's convoy/Chinook logic into `helicopter_system`/`logistics_system` proper (and swap CH-47 → Huey per `f41734c`).
7. **Terrain:** execute the May plan — merge TerrainGrid into UnifiedTerrain, migrate the 97 TerrainIntegration call sites behind a slimmed facade, kill the rogue local TerrainManager in the main scene.
8. **Main scene:** promote `scenes/main.tscn` to the real entry; carve test_combined.gd into scene-composed pieces (per the project's own Godot-first rules). Keep test harnesses under `test_scenes/` only.

**Phase 3 — Then, and only then, features:**
9. Register DoctrineManager + build the doctrine runtime (unlocks Pillar 4 — currently the cheapest dead pillar to revive since data + manager already exist).
10. Squad.gd decomposition (movement / combat / formation / garrison components) — schedule as its own epic; do not attempt opportunistically.
11. Enforce the 500-LOC rule and `_exit_tree` cleanup on all files touched during Phase 2 (ratchet, don't big-bang).

**Do not** start village/tunnel/airplane integration, new helicopter types, or campaign persistence until Phases 0–2 are done. The Bible's scope discipline rules already say this; the codebase just needs to obey them.

---
*Filed by the Technical Director for Council deliberation. Companion baseline: `production/war_room/analysis/duplicate_systems_audit.md`, `orphaned_code_audit.md`, `AUDIT_FINDINGS_SUMMARY.txt`.*
