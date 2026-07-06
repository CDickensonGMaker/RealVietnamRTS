# RTS Tropes Gap Analysis — 2026-07-06 (Session B)
**Architect:** rts-tropes-analyst (game-designer + UX lens)
**Scope:** Standard RTS conventions vs. current codebase. READ-ONLY audit; evidence cited as file:line.
**Excluded from search:** reference/, addons/, _archive/.
**Pillar frame:** Fortifications/garrison serve Pillar 2 (Network of Firebases) and Pillar 5 (The War Continues).

---

## 1. Status Table

Legend: PRESENT = works in the active gameplay path. PARTIAL = exists but incomplete or only partially wired. MISSING = absent from the active path (dead/orphaned code noted where it exists).

### A. Building Placement UX

| Trope | Status | Evidence | Gap |
|---|---|---|---|
| Ghost preview w/ valid/invalid coloring | PRESENT | `firebase_system/placement_controller.gd:636-665` → `BlueprintGhost.PlacementState` VALID/INVALID/WARNING; per-segment coloring for linear (`:472-507`) | None significant. Solid CoH-style implementation. |
| Ghost rotation before placing | PARTIAL | Bridges only: Q/E 15° steps (`placement_controller.gd:268-277, 744-762`). Arc buildings (MG nest, mortar pit): two-click place-then-aim (`:599-628, 685-706`) | Standard buildings (bunker, TOC, hootch...) always place at rotation 0 (`:335`). A bunker's fire ports/entrance cannot be oriented. Need universal R or Q/E rotation. |
| Grid snap | MISSING | No snap logic anywhere in `placement_controller.gd`; only terrain-height snap (`:466-467`) | Free-form placement is arguably intentional (CoH/paint-perimeter style per Pillar 2). Recommend: optional soft-snap for wall/wire segment alignment only. Not a priority. |
| Drag-to-place linear structures | PRESENT | `placement_controller.gd:402-593` LINEAR_START/LINEAR_DRAGGING; `building_data.gd` `is_linear_placement` on Sandbag Wall, Wire, Concertina, Trench (`:1999`) | Works. Segment spacing 0.85× footprint (`:445-450`). Each segment becomes a separate job — acceptable. |
| Placement queueing (shift-place multiples) | MISSING | `_commit_single_placement()` always destroys ghost and resets (`placement_controller.gd:382-384`); zero shift handling in file (grep confirms) | Placing 4 bunkers = 4 full round-trips through the build menu. Standard RTS: hold shift to keep placing. |
| Cancel (ESC / right-click) | PRESENT | `placement_controller.gd:255-267` (right-click and KEY_ESCAPE both cancel) | None. |
| Cost preview + affordability gating | PARTIAL | Build menu shows cost and reads SupplyManager to gray unaffordable (`battle_system/ui/build_menu_popup.gd:115-124, 490-492`); JobSystem refuses + deducts at commit (`job_system.gd:321-336`) | Ghost itself shows no cost; no live "insufficient supply" state on the ghost during placement. Player learns of shortage only at commit. |
| Placement failure feedback | PARTIAL | `placement_failed` signal → `battle_hud.gd:435 _on_placement_failed`; validation message stream (`placement_controller.gd:665`) | **Anti-pattern:** any failed commit calls `cancel_placement()` (`placement_controller.gd:328-329, 358-359`) — one misclick kicks the player out of placement mode entirely and forces re-navigation of the build menu. CoH/AoE keep the ghost alive on invalid click. |

### B. Fortification Placement (click path traced)

| Aspect | Status | Evidence | Gap |
|---|---|---|---|
| Click path: build menu → ghost → commit → job → construction | PRESENT | BuildMenuPopup (`build_menu_popup.gd:89-93` Defenses tab) → `PlacementController.start_placement` → `JobSystem.create_build_job` (`job_system.gd:288`) → clear/flatten prereq jobs (`:342-344`) → engineer works stages → `ConstructionSiteNode` → `ConstructionManager.spawn_building_at` (`construction_manager.gd:452`) | Path functions end-to-end. **Click count: ~4 for a bunker** (open menu, tab, select building, place), 5 for arc buildings (extra aim click), 3-click drag for wire/sandbags. Competitive with genre norms. |
| Friction points | — | See gaps above | (1) Failed placement cancels the whole mode; (2) no shift-repeat; (3) no rotation for bunkers; (4) **the finished building is combat-inert** — see D. The placement UX is 80% there; what comes out the other end is the real problem. |

### C. Trenches

| Aspect | Status | Evidence | Gap |
|---|---|---|---|
| Trench as buildable type | PRESENT | `BuildingType.TRENCH` (`building_data.gd:190, 1988-2003`, linear placement, cover_value 0.7, 12 supply); in build menu Defenses tab (`build_menu_popup.gd:92, 221`) | Selectable and paintable today. |
| Trench construction/dig system | PARTIAL (disconnected) | `DIG_TRENCH` job type + `TrenchNode` (progressive dug visuals, dirt piles, Area3D) (`firebase_system/nodes/trench_node.gd`); `JobSystem.create_trench_job` (`job_system.gd:1308-1331`) | **`create_trench_job` has zero gameplay callers.** PlacementController commits TRENCH through generic `create_build_job` → BUILD_STRUCTURE → spawns static `trench_modular.glb` prop (`construction_zone.gd:196`, `construction_manager.gd:452-504`). No dig, no depression, no cover volume. |
| Units occupy + cover bonus | PARTIAL (dead code) | `TrenchNode._on_body_entered` auto-applies 0.7 cover via Area3D (`trench_node.gd:137-163`); second impl `fortification_system/trench.gd` (slot-based, test-scene only, `test_scenes/static_defenses/static_defenses_test.gd:117`) | Neither reachable in gameplay because TrenchNode never spawns from the build path. Three overlapping trench implementations exist (TrenchNode, fortification Trench, EngineeringSystem.DIG_TRENCH terrain profile `terrain/systems/engineering_system.gd:38`) — none connected. |
| Firing from trench / prone visual | MISSING | No prone/lowered stance in `squad.gd` tied to trench; squad has `is_in_cover` only (`squad.gd:90`) | See detail section 2. |
| Terrain deformation | MISSING (unwired) | `EngineeringSystem.DIG_TRENCH` carve profile exists (`engineering_system.gd:11, 38, 318`) but nothing in the build path calls it | TrenchNode fakes it with meshes — acceptable v1. |

### D. Garrison / Fire Ports

| Aspect | Status | Evidence | Gap |
|---|---|---|---|
| Garrison data | PRESENT | `building_data.gd:252` `garrison_capacity` (Bunker 8 `:360`, Sandbag 4 `:383`, CONEX 6 `:397`), `auto_attacks` `:274`, `requires_garrison_to_fire` `:279` | Data layer is complete and well-designed. |
| Garrison components | PARTIAL (orphaned) | `GarrisonableStructure` (enter/exit, firing positions, damage share, suppression immunity — `fortification_system/garrisonable_structure.gd`); `Bunker` (garrison + auto-fire volleys scaled by fill — `fortification_system/bunker.gd:274-317, 385-433`) | **Only instantiated by test scenes** (`test_scenes/static_defenses/static_defenses_test.gd:64`) **and the legacy ConstructionZone path** (`construction_zone.gd:478-503`). |
| Active build path attaches them | MISSING | `ConstructionManager.spawn_building_at` (`construction_manager.gd:452-504`) spawns raw GLB / placeholder box, attaches NO garrison, NO defense component; `initialize_from_building_data` check at `:497` never fires (GLB roots have no script) | **A bunker built by the player today is a static prop.** Cannot be entered, does not fire, per-building data ignored. |
| Scene-placed buildings | MISSING | `placed_building.gd` — no garrison; `take_damage()` is `pass` (`:183-186`) | Editor-placed bunkers are inert AND indestructible. |
| Enter/exit order UX | PARTIAL (broken for real use) | Right-click garrisonable → `_issue_garrison_orders` (`move_order_handler.gd:68-72, 540-606`); G key exits (`:44-45, 318-354`) | `can_enter`/`can_load` require squad within **5m at order time** (`garrisonable_structure.gd:117-118`, `bunker.gd:390-392`) — ordering a distant squad in fails immediately. The fallback is a blind 2.0s tween "arrival estimate" (`move_order_handler.gd:573-578`) that loads the squad whether or not it arrived. |
| Squad garrison state | MISSING | `squad.gd` has no `is_garrisoned` property (grep confirms — only `is_in_cover` `:90`); `unit.set("is_garrisoned", true)` from GarrisonableStructure is a silent no-op | Hidden garrisoned squads keep running their own movement/combat AI. Ungarrison-by-unit check (`move_order_handler.gd:345`) always fails. |
| Garrisoned units fire out | PARTIAL (dead code) | `Bunker._fire_at_target` fires as structure scaled by garrison fill (`bunker.gd:274-317`) — good design, unreachable. `GarrisonableStructure.can_fire_at` (`:264-283`) exists but nothing drives squad weapons from firing positions | No fire-out in the shipped path. |
| MG Nest auto-fire | MISSING (in active path) | Data says `auto_attacks=true` (`building_data.gd:414`); TWO auto-fire classes exist (`firebase_system/nodes/defensive_structure.gd` and `fortification_system/defensive_structure.gd` — duplicate classes) plus `MachineGunNest` (test-only) | Spawned MG nest gets no DefensiveStructure component → never fires. Pillar 5 "defenses auto-fire" is currently false. |

### E. Core RTS Controls

| Trope | Status | Evidence | Gap |
|---|---|---|---|
| Control groups (ctrl+1..9) | MISSING (orphaned impl) | Full implementation in `battle_system/systems/rts_controller.gd:96-296` — but RTSController is referenced by **no scene and no autoload** (grep confirms). Active `SelectionManager` autoload has none | Table-stakes control absent at 40-80 unit scale. Port, don't rewrite. |
| Double-click select-all-of-type | PRESENT | `selection_manager.gd:28, 182-183, 580` | None. |
| Attack-move | PRESENT | A key toggle + order (`move_order_handler.gd:29-32, 91-94, 139-148`) | None. |
| Stances (aggressive / hold fire) | MISSING | `Squad.StandingOrder { NONE, PATROL, GUARD, AUTO_REPAIR }` (`squad.gd:60`) — no HOLD_FIRE/AGGRESSIVE; BattleHUD "hold" is a TODO stub (`battle_hud.gd:737`) | Bible Phase 2 explicitly lists "Aggressive, Hold Fire" standing orders. Needed for ambushes and fire discipline. |
| Rally points | MISSING | Only morale "rally" exists (`squad_morale.gd:197` — unrelated) | Per Anti-Pillar "no rally points spitting units" — production rally is correctly excluded. But an **LZ/helipad arrival rally** ("new arrivals move to X") is doctrine-compliant and absent. Low priority. |
| Patrol | PRESENT | Cursor mode + waypoints (`battle_hud.gd:484-519, 788-815`; `squad.gd:237-284`) | Works via command panel. No hotkey shown; fine. |
| Stop / Hold | PARTIAL | Stop works (`battle_hud.gd:456-457, 712-723`); Hold is stop + `# TODO: Set hold position flag` (`:737`) | Hold-position doesn't prevent chase behavior. |
| Formation move | PRESENT | Line-spread formation positions (`move_order_handler.gd:281-295`) | Basic but adequate for squad-scale. |
| Box select | PRESENT | Drag select in `selection_manager.gd:119+` with shift/ctrl modifiers (`:192, 263`) | None. |
| Minimap click-to-move camera | PRESENT | `tactical_minimap.gd:77-82, 315` (click focuses camera, draws frustum, units, fog) ; instantiated by BattleHUD (`battle_hud.gd:10`) | None. |
| Minimap ping alerts | MISSING | No ping/flash code in `tactical_minimap.gd`; `firebase_under_attack` only reaches text log (`battle_log_panel.gd:99, 176`) | See F. |
| Edge scroll + camera rotate/zoom | PRESENT | `rts_camera.gd:2, 20-21, 53-67, 101-102` (WASD, edge scroll, wheel zoom 10-500m, middle-drag rotate/tilt) | None. |

### F. Feedback Tropes

| Trope | Status | Evidence | Gap |
|---|---|---|---|
| Health bars / unit labels | PRESENT | `FloatingLabelManager` autoload (project.godot UI section) + `FloatingUnitLabel`; auto-attach on `unit_spawned` (`floating_label_manager.gd:37-99`) | Duplicate orphaned system (`health_bar_manager.gd`, `floating_health_bar.gd`) should be deleted — unification issue. |
| Selection circles | PRESENT | `squad.gd:189` `_selection_ring`, plus outline + overhead marker (`:193-194`) | None. |
| Move markers | PRESENT | `MoveMarkerManager` created by MoveOrderHandler (`move_order_handler.gd:20-21, 310-311`) | None. |
| Under-attack alerts | PARTIAL | `BattleSignals.firebase_under_attack` emitted (`firebase.gd:478, 558`) → text-only battle log (`battle_log_panel.gd:176`) | No minimap ping, no audio sting, no screen-edge indicator. In a 45-90 min multi-firebase mission (Pillar 5: war continues off-screen) this is the difference between commanding and losing a firebase you never saw attacked. |
| Unit voice / audio cues | MISSING (orphaned) | `AudioManager` class exists (`battle_system/systems/audio_manager.gd`) but is **not autoloaded**; `veterancy_tracker.gd:379` checks `/root/AudioManager` which never exists; `CombatAudio` (`battle_system/audio/combat_audio.gd`) referenced by nothing | Zero acknowledgment/report audio in active path. |
| Kill feedback | PARTIAL | `unit_died` signal (`battle_signals.gd:9`), battle log entries, muzzle flash via ParticlePool (`bunker.gd:326`) | No kill confirmations, no veterancy pop surfaced (veterancy exists but its audio hook is dead). Acceptable for now. |

---

## 2. Detail C — Trench System: what exists, what to connect

**Verdict: PARTIAL, not MISSING — and that's good news.** Roughly 70% of a trench system already exists as three disconnected islands:

1. **Placement island (live):** `BuildingType.TRENCH` is linear-paintable in the build menu today. The player can already drag a trench line and get green/red segment validation.
2. **Job island (dead):** `JobSystem.create_trench_job` → `DIG_TRENCH` → `TrenchNode` with progressive dig visuals, dirt piles, engineer-only work rules (`job_system.gd:927-928`), and an Area3D that auto-applies 0.7 cover to any unit standing in it (`trench_node.gd:137-163`). Nothing calls it.
3. **Terrain island (dead):** `EngineeringSystem.DIG_TRENCH` carve profile for real terrain deformation.

The active commit path bypasses all of it: TRENCH goes through `create_build_job` like a hootch and spawns a static `trench_modular.glb` prop.

### Implementation sketch (reuse-first)

**Step 1 — Route the commit (1 file).** In `placement_controller.gd:_commit_linear_placement` (`:548`), branch: if `_current_building_type == BuildingData.BuildingType.TRENCH`, call `_job_system.create_trench_job(pos, segment_length, width, _linear_rotation_y)` per segment instead of `create_build_job`. Supply deduction must be added to `create_trench_job` (mirror `create_build_job:321-336`).

**Step 2 — Keep TrenchNode alive post-completion (2 files).** `_on_trench_complete` (`job_system.gd:1176`) currently just completes the job; the TrenchNode already persists in `_node_container`. Add: register completed trench with nearest Firebase (`firebase.buildings`, like `placed_building.gd:169-174`) and with `CoverSystem` autoload so combat resolution sees it, not just the Area3D property-set.

**Step 3 — Occupancy + firing (2 files).** Units already receive `cover_bonus`/`set_cover_bonus` on entry (`trench_node.gd:155-163`) and `squad.gd` already folds `is_in_cover` into combat and morale (`squad.gd:1263, 1331, 2194`). Missing piece is *visual*: when `is_in_cover` from a trench, lower squad soldier meshes ~0.6m (prone-in-trench read). Firing out requires nothing new — units in a trench are not hidden; existing squad combat continues with the cover bonus. This matches the Summoner's ask (occupy + shoot from) at minimal cost.

**Step 4 (later) — Real carve.** Swap TrenchNode's fake depression mesh for an `EngineeringSystem.DIG_TRENCH` call on completion. Purely visual upgrade; defer.

**Cleanup:** retire `fortification_system/trench.gd` (slot-based duplicate, test-only) or fold its slot-spacing idea into TrenchNode later. Two trench classes must not both survive.

**Files touched:** `placement_controller.gd`, `job_system.gd`, `trench_node.gd`, `cover_system.gd`, (delete/archive `fortification_system/trench.gd`).

---

## 3. Detail D — Garrison & Fire Ports: the last-mile disconnect

**Verdict: PARTIAL — all the parts exist, none are installed in the car.**

The trace, end to end:

1. Player right-clicks a bunker with a squad selected → `move_order_handler.gd:69` finds it (bunkers group / `can_enter` / `load_squad` duck-typing — this part is fine).
2. `_issue_garrison_orders` (`:540`) calls `can_enter`/`can_load` **before the squad has moved** — both require the squad within 5m (`garrisonable_structure.gd:117`, `bunker.gd:391`). A squad 50m away fails instantly with "full or too far". **Garrison ordering only works if you park the squad next to the bunker first.**
3. If it passes, the actual load fires on a blind `2.0s` tween (`:573-578`) regardless of arrival.
4. But none of this matters for **built** bunkers, because `ConstructionManager.spawn_building_at` (`construction_manager.gd:452-504`) never attaches `GarrisonableStructure` or any `DefensiveStructure`. Only the legacy `ConstructionZone._spawn_building` path does (`construction_zone.gd:478-503`) — and player placement doesn't go through it. The player's bunker is a GLB prop in the "buildings" group.
5. Squad-side: `squad.gd` has **no garrison state at all**. `unit.set("is_garrisoned", true)` is a silent no-op; a "garrisoned" (hidden) squad keeps pathing and fighting on its own.
6. Fire ports: `Bunker._fire_at_target` (`bunker.gd:274-317`) implements exactly the right model — the *structure* fires, damage/rate scaled by garrison fill and firing arc (`is_in_firing_arc:449-460`) — but `Bunker` is only ever constructed in `test_scenes/static_defenses_test.gd`. MG Nest auto-fire: same story; `auto_attacks=true` in data, no component attached at spawn, so nothing fires.

### Implementation sketch (reuse-first)

**Step 1 — One spawn path, components attached (fixes bunkers AND MG nests).** Port `construction_zone.gd:478-503` verbatim into `spawn_building_at` (`construction_manager.gd:~495`): if `data.garrison_capacity > 0` attach `GarrisonableStructure` (max_infantry from data); if `data.auto_attacks` attach ONE DefensiveStructure class (see below) configured from `defense_weapon` / `attack_range` / `requires_garrison_to_fire` / `fire_arc` + `initial_facing` (PlacementController already encodes arc facing into rotation — `placement_controller.gd:339-343`). Then delete the component-attach block from ConstructionZone to end the dual pipeline.

**Step 2 — Kill the duplicate.** Two DefensiveStructure classes exist: `firebase_system/nodes/defensive_structure.gd` (SpatialHashGrid-based, ammo, crew — the better one, already Pillar-5-documented) and `fortification_system/defensive_structure.gd` (`FortificationDefensiveStructure`). Keep the firebase_system one; migrate `requires_garrison` gating: it checks sibling `GarrisonableStructure.garrisoned_units.size() >= crew_required` before firing.

**Step 3 — Real garrison order flow.** In `move_order_handler.gd:_issue_garrison_orders`: drop the pre-move `can_enter` distance check (keep only capacity check); issue `move_to(structure position)` and connect to the squad's arrival (squad already has movement-complete state transitions) → then `enter()`. Replace both 2.0s tweens. Add to `squad.gd`: `is_garrisoned: bool`, `garrison_structure` ref, and an early-return in movement/AI processing while garrisoned (mirrors how `is_in_cover` already gates behavior at `:1263, 1331`). ~30 LOC in squad.gd.

**Step 4 — Fire out + UX.** `GarrisonableStructure` gains the volley logic from `Bunker._fire_at_target` (or simply: attach DefensiveStructure with `requires_garrison_to_fire=true` to garrisonable bunkers — data already flags this at `building_data.gd:368` — so "garrison in = bunker starts shooting" with zero new combat code). Surface capacity pips on `building_selection_card.gd` (it already looks up DefensiveStructure at `:386`).

**Files touched:** `construction_manager.gd`, `construction_zone.gd`, `move_order_handler.gd`, `squad.gd`, `garrisonable_structure.gd`, `firebase_system/nodes/defensive_structure.gd` (+ archive `fortification_system/defensive_structure.gd`, `fortification_system/bunker.gd` after harvesting volley/arc logic), `building_selection_card.gd`, `placed_building.gd` (real `take_damage`).

---

## 4. Top 5 Gaps by Gameplay Impact (logistics / firebase-defense RTS)

1. **Built defenses are inert props (D).** Bunkers can't be garrisoned, MG nests never fire, in the path the player actually uses. This nullifies Pillar 2 (the firebase is decoration) and Pillar 5 (defenses do not auto-fire). Every defense playtest ran on a fake firebase. Highest-value fix in the codebase, and it's mostly a 25-line port from ConstructionZone.
2. **Garrison order flow is unusable at range + squads have no garrison state (D).** Even with components attached, the 5m pre-check and 2s-tween load make garrisoning feel broken; hidden squads keep fighting ghosts. Required for "same for bunkers" in the Summoner's decree.
3. **Trench pipeline disconnect (C).** Summoner explicitly demands trenches units occupy and shoot from. 70% built across three islands; one routing change in `_commit_linear_placement` + firebase/cover registration delivers a playable v1.
4. **Control groups missing / stances missing (E).** At 40-80 units across two firebases, no ctrl+1-9 and no hold-fire means the player physically cannot execute doctrine. Full control-group impl already exists orphaned in `rts_controller.gd` — port to SelectionManager.
5. **No under-attack pings/audio (F).** 45-90 min missions where "the game runs whether you're watching or not" (Pillar 5) require the game to tell you when it needs you. Text log only = silent firebase losses. Minimap ping + audio sting on `firebase_under_attack` / player `unit_died`.

Honorable mention (UX polish, cheap): failed placement cancels the whole placement mode; no shift-place; no bunker rotation — together these make fortification-building feel far clumsier than the underlying system deserves.

---

## Proposed Workstreams

1. **WS-1: Unify building completion pipeline** — Make `ConstructionManager.spawn_building_at` attach `GarrisonableStructure` + `DefensiveStructure` from BuildingData (port `construction_zone.gd:478-503`); remove ConstructionZone's spawn duplication; merge the two DefensiveStructure classes (keep `firebase_system/nodes/`); give `PlacedBuilding.take_damage` a real body. *Unblocks WS-2 and MG-nest auto-fire in one stroke.*
2. **WS-2: Garrison order flow + squad garrison state** — Arrival-triggered enter (no 2s tween, no 5m pre-check), `is_garrisoned` state in `squad.gd` that suspends squad AI, fire-out via `requires_garrison_to_fire` DefensiveStructure, G-to-exit polish, capacity pips on selection card. Depends on WS-1.
3. **WS-3: Trench v1 (occupy + shoot)** — Route TRENCH commits in `placement_controller.gd:_commit_linear_placement` to `JobSystem.create_trench_job` (add supply deduction); register completed TrenchNode with Firebase + CoverSystem; lowered/prone squad visual while in trench cover; archive `fortification_system/trench.gd`. Terrain carve via EngineeringSystem deferred.
4. **WS-4: Control groups + combat stances** — Port ctrl/shift+1-9 from orphaned `rts_controller.gd` into the `SelectionManager` autoload (then delete rts_controller); add HOLD_FIRE and AGGRESSIVE to `Squad.StandingOrder` with command-panel buttons; finish the Hold-position TODO in `battle_hud.gd:737`.
5. **WS-5: Placement QoL pass** — Keep placement mode alive on failed commit (retry instead of cancel); shift-click to place multiples; universal ghost rotation (Q/E or R) for non-linear buildings; supply-cost label + affordability tint on the ghost.
6. **WS-6: Alert & audio layer** — Minimap ping + screen-edge flash + audio sting on `firebase_under_attack` and friendly `unit_died` clusters; register `AudioManager` as autoload (its consumers already null-check `/root/AudioManager`); wire `CombatAudio` or delete it.
7. **WS-7: Feedback dead-code sweep** — Delete orphaned `health_bar_manager.gd` / `floating_health_bar.gd` (superseded by FloatingLabelManager), `fortification_system/machine_gun_nest.gd` after WS-1 harvests anything useful. Prevents future "random systems" regressions.

*Sequencing: WS-1 → WS-2/WS-3 in parallel → WS-4/WS-5/WS-6 independent → WS-7 last. WS-1 through WS-4 are the decree-critical set.*
