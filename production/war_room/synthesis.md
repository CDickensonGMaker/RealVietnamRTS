# Decree — 2026-07-06 Session B: Unified Systems + RTS Tropes
**Arbiter synthesis of:** analysis/systems_auditor_2026-07-06b.md + analysis/rts_tropes_gap_2026-07-06.md

## Root Judgment
The game does not lack systems; it runs on the WRONG copies of them. test_combined.gd
(main scene) hand-rolls convoy/depot/terrain logic while the real managers are never
instanced (16 phantom /root/ lookups, 11 unregistered names). Fortification code
(garrison, fire-ports, trench dig+cover) exists but only the LEGACY construction path
attaches it — every player-built bunker/MG nest/trench is an inert prop. This is the
mechanical cause of the Summoner's "random systems" pain.

## Unified Workstreams (dependency order)

### Phase F — Fortification tropes (player-facing, decree-critical)
- **F1 Building completion pipeline** [bead zwq]: ConstructionManager.spawn_building_at
  must attach GarrisonableStructure/DefensiveStructure per BuildingData (port
  construction_zone.gd:480-500); merge duplicate DefensiveStructure classes; real
  PlacedBuilding.take_damage. Exit: built bunker can be garrisoned, MG nest auto-fires.
- **F2 Garrison flow** [bead 4f8, blocked by F1]: arrival-triggered enter (kill 5m
  pre-check + blind 2s tween), is_garrisoned suspends squad AI, fire-out scaled by
  fill, G-exit polish, capacity pips.
- **F3 Trench v1** [bead d0q, blocked by F1]: route TRENCH commits to
  create_trench_job (has zero callers today), register TrenchNode with Firebase +
  cover, lowered squad visual, archive fortification_system/trench.gd.

### Phase U — System unification (foundation; existing beads updated)
- **U1 Terrain** [eiu]: UnifiedTerrain sole authority; 3 autoloaded engines + a 4th
  hand-synced instance in test_combined today.
- **U2 Harness extraction** [hk7]: convoy FSM/Chinook/depot creation/terrain bootstrap
  out of test_combined.gd into real managers; exit <300 LOC scene setup.
- **U3 Supply** [mbp]: one depot registry (EntityCache) + one pool owner
  (SupplyManager); kill set_meta("supply_current") storage.
- **U4 Phantom purge** [sn0]: register/rename/delete all 11 phantom autoload names;
  sync CLAUDE.md table to project.godot.
- **U5 Squad decomposition** [12x]: unchanged scope.

### Phase C — Controls & QoL
- **C1 Control groups + stances** [bead 1z5]: port orphaned rts_controller.gd impl
  into SelectionManager; HOLD_FIRE/AGGRESSIVE standing orders; finish Hold TODO.
- **C2 Placement QoL** [bead aqz]: failed commit retries instead of cancels;
  shift-place multiples; universal ghost rotation; cost on ghost.
- **C3 Alerts + audio** [bead jtl]: minimap ping + edge flash + sting on
  firebase_under_attack / friendly losses; register AudioManager autoload.

### Phase D — Cleanup
- **D1 Orphan sweep** [8rc updated]: archive fortification monoliths after F-phase
  harvest, orphaned health bar duo, rts_controller after C1 port, fix/delete
  scenes/main.tscn, standardize take_damage contract.

## Tradeoffs Named (Devil's Advocate)
- Executing F before U ships visible tropes sooner but builds on the harness main
  scene; U2/U1 rewire ground under F later. Accepted: F-phase touches construction
  pipeline only, low overlap with terrain/supply seams.
- Trench v1 fakes terrain deformation with meshes (EngineeringSystem carve deferred).
- Playtest (6ba) remains deferred by Summoner order; each workstream gates on
  headless-boot only. Risk acknowledged: regressions surface late.

## Execution Order
F1 -> F2+F3 parallel -> C1/C2/C3 independent -> U1-U4 -> U5 -> D1.
