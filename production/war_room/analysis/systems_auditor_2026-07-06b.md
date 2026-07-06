# Systems Auditor Report — 2026-07-06 (Session B)
**Lens:** technical-director / systems audit
**Scope:** All game code excluding reference/, addons/, _archive/, .beads/, assets/
**Method:** Read-only. Every claim carries file:line evidence gathered this session.

---

## Executive Summary

The codebase is not suffering from missing systems — it is suffering from **too many
parallel systems, most of them unwired**. The running game (test_combined.tscn) uses a
private convoy state machine, private depot supply stored in node *metadata*, and a
locally-instanced terrain manager synced by hand to two other autoloaded terrain engines.
Meanwhile the "real" systems (ConvoyManager, ReinforcementManager, AIDirector, SaveManager,
WeatherSystem, ResourceFlowSystem) are never instanced at all and are reached only through
phantom `/root/` lookups that silently return null. This is the exact mechanical cause of
"random systems" bugs: half the features run on harness code, half no-op silently.

**Top 5 unification actions, ranked by player-facing impact:**

1. **Declare ONE terrain source of truth and delete the rest.** Three components each
   claim to be the single source of truth (`unified_terrain_engine.gd:3`,
   `terrain_grid.gd:4`, `terrain_integration.gd:7`) while `TerrainEngine`, `UnifiedTerrain`,
   and `TerrainIntegration` are all simultaneously autoloaded (`project.godot:30,33,34`)
   and test_combined instances a *fourth* (`test_combined.gd:52,282`) and hand-syncs it
   (`test_combined.gd:318-337`). Every height/clearing/passability mismatch a player sees
   traces here.
2. **Promote test_combined.gd game logic into real systems.** The supply convoy, the
   Chinook, depot creation, and squad supply consumption exist ONLY inside the 1740-line
   test harness that is the main scene (`project.godot:19`). The game currently ships as
   its own test scaffold.
3. **Unify supply into one pool + one depot registry.** Depots are tracked in four places
   (SupplyManager, SupplyChainManager, EntityCache, test_combined metadata) and actual
   depot stock lives in `set_meta("supply_current", …)` (`test_combined.gd:1096`) that
   `SupplyManager.get_supply_at()` cannot read (`supply_manager.gd:249-257`) —
   resupply logic randomly no-ops.
4. **Register or delete the phantom singletons.** 16 `/root/` lookups target 11 names that
   are not in `[autoload]`; entire subsystems (reinforcements, saves, enemy AI director,
   doctrine, audio) silently do nothing. CLAUDE.md's autoload table lists four autoloads
   that don't exist, actively generating more phantom code.
5. **One fortification pipeline.** Bunkers/trenches/MG nests have two parallel
   implementations — `fortification_system/*` (referenced only by a test scene) and the
   BuildingData + PlacedBuilding + component pipeline (the live one,
   `construction_zone.gd:480-500`). The trench/bunker garrison tropes the Summoner wants
   cannot be built cleanly until one pipeline wins.

---

## Known Issues Status Table

| # | Prior issue | Status 2026-07-06 | Evidence |
|---|-------------|-------------------|----------|
| 1 | TerrainGrid vs UnifiedTerrainEngine duplication (map_maker/ vs terrain/) | **MUTATED, WORSE.** map_maker/ is gone (dir no longer exists), but there are now **three autoloaded terrain systems plus two instanced ones**, and three files claim "single source of truth" | `project.godot:30` (TerrainEngine), `:33` (UnifiedTerrain), `:34` (TerrainIntegration); `terrain/core/unified_terrain_engine.gd:3` "THE single source of truth"; `terrain/core/terrain_grid.gd:4` "SINGLE SOURCE OF TRUTH"; `terrain/terrain_integration.gd:7` "Uses TerrainGrid as the SINGLE SOURCE OF TRUTH"; TerrainIntegration instances TerrainManager/Vegetation (`terrain_integration.gd:80-92`); test_combined instances its own TerrainManager (`test_combined.gd:52,282`) and hand-syncs (`:318-337`). Usage split: 87 lookups of `/root/TerrainIntegration`, 19 `/root/UnifiedTerrain`, 4 `/root/TerrainEngine` |
| 2 | Squad.gd god object (3749 LOC) | **CONFIRMED, GREW to 3766 LOC.** Mixes: movement+separation (`squad.gd:439-590`), combat/per-soldier fire/melee (`:764-1015`), suppressive fire (`:1036-1117`), clearing work (`:1122-1236`), suppression received (`:1241-1412`), cover seeking (`:1415-1614`), water/resources (`:1619-1745`), resupply (`:1782-2041`), morale+routing (`:2090-2438`), model loading/outline shaders/faction tint (`:2627-3120`), collision setup (`:3124`), animation LOD/piece anim (`:3264-3462`), behavior trees (`:3466-3660`), worker controller (`:3666-3742`) | `wc -l` = 3766; function map above |
| 3 | Supply depot double-tracking | **CONFIRMED, now QUADRUPLE-tracked.** (a) `SupplyManager.supply_points` mixes firebases+depots (`supply_manager.gd:14,56-79`) and owns `global_supply` pool (`:18`); (b) `SupplyChainManager._supply_depots` + `_main_base_depot` separate registry (`supply_chain_manager.gd:27-28`), roads only but re-registers depots (`:133-160`); (c) `EntityCache._supply_depots` group cache (`entity_cache.gd:75-82`); (d) test_combined depot stock in node metadata (`test_combined.gd:1096-1097`). `placed_building.gd` (the actual depot script, `supply_depot.tscn:3`) has **zero** supply fields — grep "supply" returns nothing — so `SupplyManager.get_supply_at()` (`supply_manager.gd:249-257`) reads 0 from every real depot. ResourceFlowSystem (`logistics_system/resource_flow_system.gd`, 336 LOC, a third global pool) has **zero references anywhere** — orphaned |
| 4 | Phantom singleton lookups | **CONFIRMED — 16 lookups, 11 unregistered names.** Full list below | See "Phantom Singleton Inventory" |
| 5 | test_combined.gd harness as main scene | **CONFIRMED — 1740 LOC, is the registered main scene** (`project.godot:19`). Game logic living in it itemized below | See "New Findings" F-01 |

### Phantom Singleton Inventory (lookup → non-registered name)

Registered autoloads for cross-check: project.godot:26-65 (28 entries).

| Phantom name | Lookup site(s) | Note |
|---|---|---|
| `AIDirector` | `core/save_manager.gd:192` | `battle_system/ai/ai_director.gd` exists (613 LOC), never instanced |
| `MissionManager` | `core/save_manager.gd:197` | `campaign/mission_manager.gd` exists, never instanced |
| `DoctrineManager` | `core/save_manager.gd:211`, `:320` | `battle_system/systems/doctrine_manager.gd` exists, never instanced |
| `FogOfWar` | `campaign/mission_objective.gd:472` | `terrain/systems/fog_of_war.gd` exists, not autoloaded |
| `InsertionManager` | `reinforcement_system/reinforcement_manager.gd:166`, `test_daemon/daemon_autoload.gd:1428` | exists, not autoloaded (CLAUDE.md wrongly says it is) |
| `ConvoyManager` | `reinforcement_system/supply_manager.gd:164` | exists, never instanced; fallback group scan `supply_manager.gd:167` also finds nothing |
| `AudioManager` | `battle_system/systems/veterancy_tracker.gd:379` | `battle_system/systems/audio_manager.gd` exists, never instanced |
| `TerrainManager` | `battle_system/ui/tactical_minimap.gd:168` | TerrainManager is a scene-instanced class, never at /root |
| `TerrainFlatteningSystem` | `test_daemon/daemon_autoload.gd:854`, `:913` | autoload is named `TerrainFlattening` (project.godot:38) — name mismatch |
| `UnitSpawner` | `test_daemon/daemon_autoload.gd:1343` | no such class/file found |
| `TestDaemon` | `scenes/test_combined.gd:130` | `test_daemon/daemon_autoload.gd` (1664 LOC) not autoloaded |

---

## New Findings

### F-01 — CRITICAL — Game logic lives in the test harness (main scene)
**Evidence:** `scenes/test_combined.gd` (1740 LOC), registered main scene `project.godot:19`.
- **Convoy state machine:** `_convoy_state` string FSM (`:109`), truck update loop (`:1383-1543`), dispatch (`:1519`), placeholder truck factory (`:1221`). The real `ConvoyManager` (`reinforcement_system/convoy_manager.gd`) is never instanced.
- **Chinook flight FSM:** spawn (`:1245`), rotor anim (`:1613`), hover/fly/descend/ascend verbs (`:1629-1698`), supply request (`:1681`). Duplicates `helicopter_system/` (helicopter.gd, heli_mission.gd, insertion_manager.gd — all unwired).
- **Terrain bootstrap + global sync:** local TerrainManager (`:52,282-316`), `_sync_terrain_with_globals` (`:318-337`), terrain type init (`:339-357`) — bootstrap responsibilities that belong in a game/bootstrap scene or in UnifiedTerrain itself.
- **Squad supply loop via metadata:** `_update_squad_supply` (`:1700-1729`) consumes/refills `squad.get_meta("supply_current")` while Squad has its own internal supply system (`squad.gd:1619-2041`, `add_supply:1980`) — two supply models on the same units.
- **Depot creation + supply stock in metas:** `:1087-1106`.
**Canonical:** systems in their own directories; test_combined reduced to scene setup only.
**Migration:** create `game/bootstrap.gd` scene owning terrain init; move convoy FSM into ConvoyManager; move Chinook FSM into helicopter_system; delete metadata supply in favor of Squad internals + depot storage.

### F-02 — CRITICAL — Four terrain systems, three "single sources of truth"
**Evidence:** see Known Issue #1. Additional hazard: TerrainIntegration silently creates
*duplicate* ClearingSystem/DamageSystem instances if the autoloads are missing
(`terrain_integration.gd:95-107`) — split-brain when test scenes run standalone.
**Canonical:** `UnifiedTerrain` (unified_terrain_engine.gd) — it already merges
HeightmapStorage + TerrainGrid + vegetation tracking (`unified_terrain_engine.gd:10-14`).
**Should die:** `TerrainEngine` autoload (generation → becomes a library called by
UnifiedTerrain), `TerrainGrid` as an independently-owned grid (fold into UnifiedTerrain),
TerrainIntegration demoted to a thin deprecated facade that forwards to UnifiedTerrain
(87 call sites migrate incrementally).
**Migration:** 1) route TerrainIntegration's public API to UnifiedTerrain internally;
2) move heightmap generation behind `UnifiedTerrain.generate()`; 3) delete the `.new()`
fallbacks at `terrain_integration.gd:95-107`.

### F-03 — CRITICAL — Dead manager layer: entire subsystems never instanced
**Evidence (zero inbound references anywhere):**
- `reinforcement_system/reinforcement_manager.gd` — root of Pillar-4 reinforcements, unreferenced
- `core/save_manager.gd` — save system unreachable (and internally reads only phantom singletons)
- `battle_system/systems/weather_system.gd`, `air_support_manager.gd`, `audio_manager.gd`, `rts_controller.gd`, `doctrine_manager.gd` — unreferenced (audio/doctrine referenced only via phantom lookups)
- `battle_system/ai/ai_director.gd` (613 LOC) — only ref is phantom `save_manager.gd:192`; therefore `vc_controller.gd`, `nva_controller.gd`, `ambush_manager.gd`, `siege_manager.gd` (its children) are all dead — **there is no live enemy strategic AI**
- `campaign/mission_manager.gd` — only ref is dead save_manager → campaign layer dead
- CLAUDE.md "Autoloads" table lists `AirSupportManager`, `WeatherSystem`, `ReinforcementManager`, `InsertionManager` as autoloads; none are in `project.godot:23-65`. Doc rot is generating new phantom code.
**Recommendation:** per subsystem, either register-and-wire (reinforcements, enemy AI are MVP-relevant) or move to _archive/. Fix CLAUDE.md table in the same commit.

### F-04 — HIGH — Two fortification implementations (blocks trench/bunker tropes)
**Evidence:** `fortification_system/{bunker,trench,mortar_pit,machine_gun_nest}.gd` are
referenced ONLY by `test_scenes/static_defenses/static_defenses_test.gd`;
`fortification_system/watchtower.gd` referenced by nothing. The live pipeline is
BuildingData → PlacedBuilding scenes (`game/scenes/buildings/*.tscn`) + components
attached at construction: `construction_zone.gd:480-488` (GarrisonableStructure),
`:492-500` (loads `fortification_system/defensive_structure.gd`).
**Canonical:** component pipeline (GarrisonableStructure + FortificationDefensiveStructure
on PlacedBuilding scenes).
**Should die:** the standalone monolith classes (bunker.gd 463+, machine_gun_nest.gd 622,
mortar_pit.gd 780, trench.gd, watchtower.gd) — port any unique behavior (fire ports,
trench occupancy) into the components, then archive.

### F-05 — HIGH — Duplicate `DefensiveStructure` classes with colliding names
**Evidence:** `firebase_system/nodes/defensive_structure.gd:1` declares
`class_name DefensiveStructure` (856 LOC; zero external instantiations — its own factory
at `:848-850` is called by nobody) vs `fortification_system/defensive_structure.gd:1`
`class_name FortificationDefensiveStructure` (the one actually instanced,
`construction_zone.gd:492`). UI code looks nodes up by child name "DefensiveStructure"
(`selection_manager.gd:247`, `building_selection_card.gd:335,386`), which works only
because construction_zone renames the fortification component (`construction_zone.gd:495`).
**Canonical:** fortification_system version. **Should die:** firebase_system/nodes copy;
then rename `FortificationDefensiveStructure` → `DefensiveStructure`.

### F-06 — HIGH — Two squad implementations, three truck implementations
**Evidence:** `battle_system/nodes/infantry_squad.gd` + `soldier.gd` used only by
`helicopter_system/test/*` and `battle_system/ai/auto_cover_behavior.gd`; canonical squad
is `squad.gd` (12 preload sites incl. `move_order_handler.gd:5`,
`reinforcement_manager.gd:12`). Trucks: `reinforcement_system/supply_truck.gd` (681 LOC,
referenced by deployable_fob + test_combined) vs `battle_system/units/transport_truck.gd`
(742 LOC, **zero references — orphan**) vs test_combined's placeholder truck factory
(`test_combined.gd:1189-1244`).
**Canonical:** squad.gd (until decomposed); supply_truck.gd.
**Should die:** transport_truck.gd, infantry_squad.gd+soldier.gd (fix auto_cover_behavior
to target Squad), placeholder truck factory.

### F-07 — MED — Orphaned files (verified zero inbound .gd/.tscn references)
- `logistics_system/resource_flow_system.gd` (336 LOC)
- `logistics_system/ferry_manager.gd`, `ferry_route.gd`
- `battle_system/units/transport_truck.gd` (742 LOC)
- `firebase_system/nodes/defensive_structure.gd` (856 LOC)
- `fortification_system/watchtower.gd`
- `scenes/main.tscn` — **also broken**: references `res://scenes/main.gd` (`main.tscn:3`) which does not exist on disk
- `test_daemon/daemon_autoload.gd` (1664 LOC) — not autoloaded; only ref is the phantom lookup `test_combined.gd:130`
- Dead-by-transitivity (see F-03): save_manager, reinforcement_manager, ai_director subtree, mission_manager, weather_system, air_support_manager, audio_manager, rts_controller, doctrine_manager
**Recommendation:** move to `_archive/` (git preserves history); do not delete BuildingData-referenced scenes.

### F-08 — MED — Inconsistent `take_damage` contract across 29 implementations
**Evidence:** 29 `func take_damage` definitions found. Signatures diverge:
`(amount, source: Node)` (squad.gd:681), `(amount)` only (`fortification_system/bunker.gd:463`),
`(amount, damage_type: String)` (`construction_zone.gd:775`, `destructible_cover.gd:83`).
Any shared damage-dealing code (projectile.gd, CombatManager) calling with two args will
runtime-error or silently mismatch on the String-typed variants.
**Recommendation:** one `Damageable` contract (amount, source, type) enforced via a shared
component or interface convention; CombatManager as the single damage entry point.

### F-09 — MED — Signal bus bypasses / scene reach-ins
**Evidence:** 13 system files call `get_tree().current_scene` to find/attach nodes
(ai_director, ambush_manager, nva_controller, vc_controller, selection_manager,
veterancy_tracker, tactical_minimap, construction_manager, insertion_manager,
convoy_manager, reinforcement_manager, tunnel_entrance, tunnel_network). Discovery via
ad-hoc groups instead of signals/EntityCache: `supply_manager.gd:167`
("convoy_managers" group — empty), `supply_manager.gd:49` ("supply_managers" group).
**Recommendation:** spawn requests and entity discovery go through BattleSignals +
EntityCache; systems never address the scene tree directly.

### F-10 — LOW — Autoload load-order and doc hazards
**Evidence:** `project.godot:29` comment claims the terrain section has "no BattleSignals
dependency" but `terrain_integration.gd:554,610` and `firebase_system/terrain_clearing.gd`
use BattleSignals (order is still safe — BattleSignals loads at `:27` — but the comment
invites a future unsafe reorder). `firebase_system/terrain_clearing.gd` and
`terrain_flattening.gd` are terrain-domain autoloads living in firebase_system/ (boundary
violation, `project.godot:37-38`). `BattleHUD` as an autoload (`project.godot:65`) makes
UI global state — a HUD is scene furniture, not a singleton; test_combined additionally
manages its own `battle_hud` reference (`test_combined.gd:82`).

---

## Proposed Workstreams (discrete, independently shippable)

1. **WS-1 Terrain Unification:** Make UnifiedTerrain the sole terrain authority: route
   TerrainIntegration's API through it, fold TerrainEngine generation behind
   `UnifiedTerrain.generate()`, delete TerrainGrid's independent ownership and the
   duplicate-instance fallbacks (`terrain_integration.gd:95-107`). Exit: exactly one
   heightmap and one gameplay grid exist at runtime.
2. **WS-2 Harness Extraction:** Move convoy FSM, Chinook FSM, depot creation, and terrain
   bootstrap out of test_combined.gd into ConvoyManager / helicopter_system / a new
   `game/bootstrap.tscn`; register needed managers as autoloads. Exit: test_combined.gd
   < 300 LOC of pure scene setup.
3. **WS-3 Supply Unification:** One depot registry (EntityCache), one pool + routing owner
   (SupplyManager), real storage fields on `placed_building.gd`; delete metadata supply and
   archive ResourceFlowSystem (or adopt it wholesale and delete SupplyManager's pool — pick
   one). Exit: `get_supply_at(depot)` returns the same number every system sees.
4. **WS-4 Phantom Purge:** For each of the 11 phantom names: register the autoload, fix the
   name (`TerrainFlatteningSystem`→`TerrainFlattening`), or delete the lookup + dead
   subsystem. Update CLAUDE.md autoload table to match project.godot. Exit: zero
   `/root/` lookups target unregistered names.
5. **WS-5 Fortification Pipeline:** Port trench occupancy / bunker fire-port behavior from
   fortification_system monoliths into GarrisonableStructure + DefensiveStructure
   components; archive the monoliths; resolve the DefensiveStructure name collision.
   Exit: one code path builds, garrisons, and fires every fortification. (Direct enabler
   for the RTS-tropes decree.)
6. **WS-6 Squad Decomposition:** Extract from squad.gd into child components: visuals/
   animation (~900 LOC), morale/routing (~350), supply/water (~420), leaving movement +
   combat + orders. Exit: squad.gd < 1500 LOC, no behavior change (verify with existing
   test scenes).
7. **WS-7 Orphan Archive Sweep:** Move the F-07 list to `_archive/`, fix or delete broken
   `scenes/main.tscn`, standardize the `take_damage` contract (F-08) while touching each
   remaining unit file. Exit: every .gd in the repo is reachable from the main scene,
   an autoload, or a .tscn.
