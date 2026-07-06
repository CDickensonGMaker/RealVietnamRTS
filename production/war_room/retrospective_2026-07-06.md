# Retrospective — 2026-07-06: How We Improve This Game
**Architect:** retrospective-architect
**Sources:** synthesis.md (Session B), analysis/systems_auditor_2026-07-06b.md, analysis/rts_tropes_gap_2026-07-06.md (incl. Arbiter Correction), archive/2026-07-06_full_audit/ (briefing, discussion, synthesis), git log, Beads closed issues + memories.
**Purpose:** Not what we fixed — HOW we keep producing the same classes of defect, and the checkable rules that prevent each. Distilled cross-project version: `~/.claude/architect_knowledge/rts_project_lessons.md`.

---

## Pattern 1 — Written ≠ Wired (code "done" is not feature done)

**Evidence**
- 16 phantom `/root/` lookups targeting 11 unregistered names (systems_auditor_2026-07-06b.md, Phantom Singleton Inventory; bead sn0). AIDirector (613 LOC), SaveManager, ReinforcementManager, MissionManager, DoctrineManager, AudioManager all exist and are never instanced — "there is no live enemy strategic AI" (F-03).
- `JobSystem.create_trench_job` has **zero gameplay callers** (rts_tropes_gap §C; job_system.gd:1308-1331); TRENCH commits route to the generic build job and spawn a static prop.
- `ConstructionManager.spawn_building_at` (construction_manager.gd:452-504) never attaches GarrisonableStructure/DefensiveStructure — every player-built bunker is an inert prop (rts_tropes_gap §D, gap #1). Pillar 5 "defenses auto-fire" was false in the shipped path while the feature existed in code.
- Pillar 4 (Doctrine) judged "spec-only, dead at runtime" (archive synthesis, Pillar Health).

**Root cause**
Definition of done stopped at "the class exists and compiles." Godot's forgiving lookup style (`get_node_or_null` + null-check) converts a missing wire into a permanent silent no-op, so nothing ever screamed. Agents built the engine and never turned the key.

**PREVENTION RULES**
- R1.1: A feature is done only when its code executes on a path reachable from the main scene, a registered autoload, or a .tscn referenced by them. Before closing any bead, trace one concrete call chain from player input (or boot) to the new code and record it in the close note.
- R1.2: Never commit a `/root/Name` (or equivalent global) lookup unless `Name` appears in `project.godot [autoload]` in the same commit — or the lookup is deleted.
- R1.3: After writing any new public function/system, run a project-wide grep for its name. Zero callers at commit time = wire it or file a bead titled "UNWIRED: <name>" in the same session.

---

## Pattern 2 — Parallel/duplicate implementations instead of one canonical system

**Evidence**
- 3 autoloaded terrain engines + a 4th hand-synced instance in test_combined; **three files each claim "single source of truth"** (unified_terrain_engine.gd:3, terrain_grid.gd:4, terrain_integration.gd:7; bead eiu — first flagged 2026-05-28, MUTATED WORSE by 2026-07-06).
- 2 `DefensiveStructure` classes with colliding names (F-05); 3 trench implementations, none connected (rts_tropes_gap §C); 3 truck implementations, 2 squad implementations (F-06); 2 health-bar systems (rts_tropes_gap §F); supply depots quadruple-tracked (F-03/Known Issue #3).
- Duplication *grew* between audits: map_maker/ was removed, but the terrain count went from 2 systems to 4 (Known Issue #1: "MUTATED, WORSE").

**Root cause**
Agents write fresh instead of searching; each new session/agent rediscovers the domain and builds its own copy. "Single source of truth" was asserted in comments instead of enforced by deleting rivals. Nothing in the workflow forced the loser to die.

**PREVENTION RULES**
- R2.1: Before creating any new manager/system/component class, grep for existing classes owning that noun (e.g., `class_name.*Terrain`, `class_name.*Supply`). If one exists: extend it, or explicitly archive it to `_archive/` in the same PR. Creating a sibling is forbidden.
- R2.2: A "single source of truth" claim is only permitted in the commit that archives or deletes every rival. Comments asserting canonicity without a corpse are lies.
- R2.3: When an audit finds N implementations of one concern, the decree must name the canonical one AND schedule the deaths of the others in the same workstream (as Session B's F1/U1/D1 now do).

---

## Pattern 3 — Test harness logic shipping as the game

**Evidence**
- `scenes/test_combined.tscn` is the registered main scene (project.godot:19); its 1740-LOC script owns the convoy FSM, Chinook FSM, depot creation, and squad supply via `set_meta("supply_current")` (F-01). "The game currently ships as its own test scaffold."
- TestDaemon autoload did main-thread file I/O every 1-2s in production (archive synthesis, freeze secondary cause; bead ezj).
- Depot stock stored in node metadata that `SupplyManager.get_supply_at()` cannot read (F-03) — the harness's private data model broke the real system, and the "supply loop PROVEN WORKING" memory was proven only on the harness path.

**Root cause**
Features were built where they could be *seen* fastest — the harness — and the promotion step never happened. Metadata side-channels let the harness fake state without touching the owning classes, so the divergence was invisible.

**PREVENTION RULES**
- R3.1: Never add game logic (FSMs, economy state, spawning rules) to any scene/script whose name contains `test`. Harnesses call systems; they never own behavior.
- R3.2: State lives in typed fields on the owning class. `set_meta`/dictionary side-channels for gameplay state are forbidden — if a system can't read it, it doesn't exist.
- R3.3: If the project's main scene is a test scene, extracting it (bead hk7 / U2) outranks new features in every prioritization.

---

## Pattern 4 — Audit verdicts asserted without direct code verification

**Evidence**
- **Today:** rts_tropes_gap declared control groups "MISSING (orphaned impl)" — WRONG. Arbiter Correction (bottom of rts_tropes_gap_2026-07-06.md): `selection_manager.gd:140-167` already implements Ctrl+0-9 save / recall / Shift-add / Ctrl+G / Space focus. The analyst found the orphan (rts_controller.gd) and stopped searching. Required a correction commit (14e1111) and a bead rescope (1z5).
- **Precedent:** bd memory `session-continued-audit-work-fixed-false-positives-in` — a prior CODE_AUDIT_REPORT falsely claimed BTCondition/Task classes were undefined. Same failure mode, second occurrence.
- **Counter-example that worked:** in the morning session, two architects disagreed on whether `apply_clearing_damage` fired in production; the Arbiter resolved it by reading bulldozer.gd:586/618 and test_combined.gd:609 inline (discussion.md C1) — verdict changed from both positions to a third, correct one.

**Root cause**
Verdicts formed from one grep at one expected location, or from memory of file structure. Absence-of-evidence at a single site was reported as evidence-of-absence project-wide.

**PREVENTION RULES**
- R4.1: Any MISSING/dead/unwired verdict requires: (a) project-wide grep for at least 2 naming variants of the capability (not the class you expect — the *behavior*, e.g. `control_group|group_\d|KEY_1`), and (b) a direct read of the file that would consume it. Cite file:line for the negative search scope, not just positives.
- R4.2: Conflicting architect claims are resolved only by reading the disputed code inline during synthesis, never by argument strength. (This worked in C1; make it law.)
- R4.3: Before a decree schedules "implement X", the Arbiter spot-verifies the underlying MISSING claim in code. Every false MISSING costs a wasted workstream or a duplicate system (Pattern 2 feeder).

---

## Pattern 5 — Doc rot actively generating phantom code

**Evidence**
- CLAUDE.md's autoload table lists `AirSupportManager`, `WeatherSystem`, `ReinforcementManager`, `InsertionManager` — none in project.godot (F-03: "Doc rot is generating new phantom code"). Agents reading CLAUDE.md write new `/root/InsertionManager` lookups in good faith (reinforcement_manager.gd:166).
- CLAUDE.md's directory table still describes `map_maker/` (deleted) and `scenes/main.tscn` (broken — references nonexistent main.gd, F-07).
- `terrain-clearing.md` described `update_road_cutting()` which was never written (archive discussion, Agreement #2) — the Summoner's own bug hypotheses were shaped by a doc describing imaginary code.
- PRD vs GAME_BIBLE authority conflict: Chinook implemented despite explicit exclusion (archive synthesis #16).

**Root cause**
Docs are edited at design time and never re-verified against project.godot / the filesystem. Because agents treat CLAUDE.md as ground truth (it says so), every stale row becomes a code generator for phantoms.

**PREVENTION RULES**
- R5.1: Any commit that changes `[autoload]`, the main scene, or top-level directories must update the corresponding CLAUDE.md/doc tables in the same commit (U4 already encodes this once; make it standing law).
- R5.2: Treat doc tables as claims, not truth: before writing code against a documented autoload/API, verify it exists in project.godot or the source file. One `Select-String` costs seconds; a phantom subsystem costs an audit.
- R5.3: When two authority documents conflict (PRD vs Bible), stop and escalate to the Summoner; never implement the excluded thing because one doc permits it.

---

## Pattern 6 — Playtest deferral: headless-boot gating lets integration bugs pool

**Evidence**
- Session B tradeoffs: "each workstream gates on headless-boot only. Risk acknowledged: regressions surface late" (synthesis.md).
- The cost is already demonstrated: "Every defense playtest ran on a fake firebase" (rts_tropes_gap gap #1) — inert player-built bunkers survived undetected because nobody clicked the player path. The 5m garrison pre-check + blind 2s tween (§D trace) are bugs only a hands-on order-a-distant-squad test reveals.
- The freeze itself shipped through many sessions ("major slowdowns during every playtest" — archive briefing) before a session was spent diagnosing it.

**Root cause**
Headless boot proves the game *starts*; it proves nothing about interaction. With playtests deferred by decree, the only integration signal was the Summoner's frustration, arriving in batches.

**PREVENTION RULES**
- R6.1: A feature may only be reported as working if exercised on the player's actual input path (menu → click → result), not a test scene or direct function call. "PROVEN WORKING" claims must name the scene and path used.
- R6.2: When playtesting is deferred by decree, each closing workstream still runs one scripted in-game smoke of its click path (spawn, order, observe result via daemon or screenshot) — headless boot alone never gates a close.
- R6.3: Any Summoner report of "random systems" behavior triggers a wiring audit (Patterns 1-3) before feature work — randomness is the smell of half-wired parallel systems, and today proved it.

---

## Pattern 7 — Work hoarding: uncommitted trees and silent failure paths

**Evidence**
- 279 files / ~6 weeks of fixes existed only in the working tree — "single point of total loss" (archive synthesis Phase 0; bead 9vo). Recovery required two duplicate checkpoint commits (964f517, 856be11) and sacrificed clean history (discussion.md, Devil's Advocate).
- Silent failures compounding invisibly: `supply_chain_manager.gd:216-218` returns without logging → first road never tasked and nobody knew why (H1); `get_height_at()` 0.0 sentinel accepted silently → below-map spawns → which *caused* the idle-worker bug via 3D distance scoring (H2, "the spawn bug causes the idle-worker bug").
- Root clutter accumulating (nul, freezing big time.zip, 3 more zips) — same hoarding instinct at file level.

**Root cause**
No session-end discipline (now automated in CLAUDE.md — keep it), and defensive code written without telemetry: every guarded early-return converted a wiring bug into an invisible no-op that later audits had to excavate.

**PREVENTION RULES**
- R7.1: Commit and push at every session end; a working tree older than one session is an incident, not a style choice. (Already law in CLAUDE.md — this retrospective records WHY.)
- R7.2: Every fallback/early-return that skips intended work must `push_warning` at least once per session (guard with a static flag if spammy). Silent no-ops are how dead systems pass for alive.
- R7.3: Never accept a sentinel value (0.0 height, null lookup, empty group) as valid input; gate on the readiness signal or defer. When two bugs co-occur, hunt the shared datum (a coordinate, a sentinel, an init order) before patching either separately.

---

## What Worked — Keep Doing

1. **Hypothesis-driven diagnosis.** The morning briefing stated H1/H2/H3 as falsifiable claims; the audit CONFIRMED/REFUTED each with file:line. H1 was refuted-as-stated but confirmed-as-topology — a shape of answer that only appears when you diagnose before fixing. Keep "diagnose first, no code changes until findings reviewed."
2. **Arbiter inline verification.** Both the C1 adjudication and the control-groups correction were caught by reading code during synthesis. The Arbiter reading disputed code is the single highest-value quality gate this project has.
3. **Reuse-first sketches.** The tropes report's implementation sketches ("port construction_zone.gd:478-503", "route one commit call", "70% of trench exists") turned MISSING-looking features into 25-line ports. Inventory orphans before scoping anything as new work.
4. **Beads + memories continuity.** Bead eiu carrying the terrain-duplication finding from May to July is the only reason "MUTATED, WORSE" could be measured. Keep encoding audit deltas against prior bead IDs.

---

## Standing Instruction for Future Sessions

Before any implementation session on this project, agents must load
`~/.claude/architect_knowledge/rts_project_lessons.md` alongside godot_standards.md.
Rules R1.1-R7.3 above are checkable; auditors should spot-check compliance
(phantom-lookup count, duplicate-class count, test-scene LOC) as regression metrics
each War Room session. Current baselines to beat: 16 phantom lookups, 4 terrain
systems, test_combined.gd 1740 LOC.
