# UI Vision — North Star Concept
**Date:** 2026-07-06
**Reference image:** `ui-concept-2026-07-06.png` (AI concept shot provided by Caleb)
**Status:** Directional vibe target, not a literal spec. Elements below are what the concept communicates; each needs its own UX spec before implementation.

## Overall Read
Warno / Broken Arrow-class presentation: dark translucent panels with thin light borders, military-stencil typography, muted olive/khaki accent palette, dense but organized information. The world view stays dominant — UI hugs the edges, center screen is battlefield.

## Elements Shown in the Concept

### Top Bar
- **Mission panel (top-left):** mission name, day counter ("Day 2 of 3"), clock + weather icon. Primary/secondary objectives checklist with completion diamonds.
- **Resource strip (top-center):** four resources with icons, current stock, and **rate per minute** (+48/min style). Concept implies: supply, ammo(?), fuel(?), manpower (42/60 cap).
- **Game controls + morale (top-right):** pause/speed, menu, and a global **MORALE %** readout.

### Right Panel — Selected Firebase
- Firebase name + level, rendered portrait/thumbnail of the base.
- HP bar (2,450/3,000 style).
- **Structures grid** with upgrade-available arrows and an empty "+" slot (maps to firebase level slot caps: 4/8/12).
- **Support Requests list** with per-ability cooldown timers: Mortar Strike (Ready), Artillery Barrage (2:30), Napalm Strike (4:15), Helicopter Gunship (6:00).

### Bottom-Left — Force Roster
- Category tabs: INFANTRY / VEHICLES / SUPPORT / STRUCTURES / AIR SUPPORT / INTEL.
- Unit cards with portrait, name, and strength fraction (10/12, 6/6, 2/2…). Selected card highlighted.

### Bottom-Center — Selected Unit Detail
- Unit name, strength, **veterancy tier label + stars** (VETERAN).
- Weapons readout with icons and ammo count.
- **Orders grid** of icon buttons (move, attack, hold, formations, special orders).

### Bottom-Right — Campaign Map
- Node-graph strategic map (friendly blue / enemy red nodes, connecting lines) with the current AO framed.
- View-mode toggle row beneath (grid, terrain, POI, layers, etc.).

### Bottom Strip
- **Battle log** with timestamps ("14:28 – Enemy mortar team spotted").
- Conditions readout: WEATHER / TERRAIN / VISIBILITY / WIND.
- **Terrain effects** callouts: "Jungle — Cover Bonus 25%", "Elevation — High Ground +10% Range".

### In-World
- Floating nameplates on units/structures (RIFLE SQUAD 10/12, M60 MG NEST, SUPPLY CONVOY, 81MM MORTAR, UH-1H HUEY) with faction/status icons.
- Firebase label pinned to the base with level.

## Pillar Mapping
| Concept element | Pillar served |
|---|---|
| Supply convoy label, resource rates/min | 3 — Physical Supply Chains |
| Firebase panel, structures grid, HP | 2 — Network of Firebases |
| Terrain effects strip (jungle cover, elevation) | 1 — Carve the Map |
| Support request cooldowns, roster with fixed strength fractions | 4 — Doctrine Over Spam |
| Battle log, auto-firing MG nest labels, standing patrol readouts | 5 — The War Continues |

## Notes / Constraints
- Style target only — final HUD must obey performance budget (Control nodes, no per-frame group scans for label updates; see performance audit 2026-07-06).
- Run `/ux-design` per screen (HUD, firebase panel, campaign map) before implementing; this doc is the mood anchor those specs should reference.
