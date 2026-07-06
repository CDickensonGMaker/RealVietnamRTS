# War Room Briefing — 2026-07-06 (Session B: Unification + RTS Tropes)
**Summoner:** Caleb
**Prior session archived:** archive/2026-07-06_full_audit/

## The Query
1. **Unified systems**: Full audit of game systems — find loose, duplicated, or
   wrongly-placed code. Prior playtests suffered from "random systems" issues;
   the Summoner requires unified systems across the board.
2. **RTS tropes**: All standard RTS conventions must be present — easy-to-understand
   building placement, easy fortification placement, TRENCHES that units occupy
   and shoot from, same for bunkers (garrison + fire ports).

## Constraints
- Five Pillars (GAME_BIBLE.md) govern; fortifications/garrison serve Pillar 2
  (Network of Firebases) and Pillar 5 (The War Continues).
- Godot standards non-negotiable; 60 FPS @ 300-500 units; no per-frame group scans.

## Prior Intelligence (verify current state, do not re-derive)
- 2026-05-28: TerrainGrid/UnifiedTerrain duplicate (eiu), Squad.gd 3749-LOC god
  object (12x), supply depot tracking duplicated (mbp), orphaned files (8rc).
- 2026-07-06 AM: phantom singletons (sn0), test_combined.tscn 1740-LOC harness
  as main scene (hk7). Fix round 4614dc7 pushed, NOT playtested (6ba, deferred).

## Architects Summoned
- systems-auditor (technical-director lens) -> analysis/systems_auditor_2026-07-06b.md
- rts-tropes-analyst (game-designer + ux lens) -> analysis/rts_tropes_gap_2026-07-06.md
