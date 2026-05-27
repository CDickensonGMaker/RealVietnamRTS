# Active Session State

## Session Extract — Architecture Review Update 2026-05-26
- Verdict: PARTIAL (upgraded from FAIL)
- Requirements: 134 total — 51 covered (38%), 12 partial (9%), 71 gaps (53%)
- ADRs Created This Session: 6 new ADRs (ADR-0010 through ADR-0015)
- Total ADRs: 15 (ADR-0001 through ADR-0015)
- Report: docs/architecture/architecture-review-2026-05-26.md (v2)

## ADRs Created This Session
1. **ADR-0010: Combat System** — Covers TR-COR-001-007 (cover, suppression, lethality, damage types)
2. **ADR-0011: Morale and Routing** — Covers TR-COR-010-017 (morale states, routing, rally)
3. **ADR-0012: Unit Resource System** — Covers TR-COR-020-025 (ammo, water, resupply)
4. **ADR-0013: AI Director** — Covers TR-COR-040-043 (dynamic difficulty, attack scheduling)
5. **ADR-0014: Reinforcement System** — Covers TR-SYS-050-056 (deck cards, delivery modes, timing)
6. **ADR-0015: Doctrine System** — Covers TR-SYS-060-064 (Air Cav, Mech Infantry, VC Local Force)
7. **ADR-0016: Terrain Clearing System** — Covers TR-SYS-001-011 (bulldozer, det-cord, craters)
8. **ADR-0017: Airstrip System** — Covers TR-SYS-080-083 (capture, cratering, repair)
9. **ADR-0018: Tunnel System** — Covers TR-SYS-090-091 (hidden spawn, detection, destruction)

## Bug Fixes Applied This Session
1. **Scene Freeze**: Added `await` to terrain generation in clearing_test.gd
2. **Billboard Loading**: Added early return in billboard_vegetation._ready() when disabled
3. **TOC Influence Radius**: Added dashed circle visualization to BlueprintGhost (150m radius)
4. **MG Nest Rotation**: Changed to left-click anchor pattern (first click anchors, second confirms)

## Remaining ADR Gaps
- Systems: Firebase (TR-SYS-020-026) - partially covered by ADR-0009
- Systems: Construction (TR-SYS-030-036) - partially covered by ADR-0005
- Systems: Supply/Logistics (TR-SYS-040-047) - partially covered by ADR-0006
- Content: Faction Architecture (TR-CNT-001-004)
- Content: Unit Roster (TR-CNT-010-024)
- Content: Building Roster (TR-CNT-030-043)
- Content: Map Requirements (TR-CNT-050-055)

## Coverage Summary
- Total ADRs: 18 (ADR-0001 through ADR-0018)
- Foundation Layer: Mostly covered by ADR-0001, 0002, 0003, 0008
- Core Layer: Fully covered by ADR-0010-0013
- Systems Layer: Mostly covered by ADR-0005-0009, 0014-0018
- Content Layer: Requires data schema ADRs (lower priority - implementation over documentation)
