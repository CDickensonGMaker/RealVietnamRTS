# RealVietnamRts — Game Bible

**Status:** `[LOCKED]` for foundational decisions, `[LIVING]` for production details
**Last updated:** 2026-05-13
**Working title:** RealVietnamRts (final title TBD)

> Read this before every Claude Code session. Read it before adding any feature. Read it before making any design decision. If a proposal does not serve a pillar, or violates an anti-pillar, it does not go in.

---

## Table of Contents

1. [Vision](#1-vision)
2. [The Player Fantasy](#2-the-player-fantasy)
3. [The Five Pillars](#3-the-five-pillars)
4. [Reference Games](#4-reference-games)
5. [Anti-Pillars — What the Game Is NOT](#5-anti-pillars--what-the-game-is-not)
6. [Asymmetry: US vs. VC/NVA](#6-asymmetry-us-vs-vcnva)
7. [Tone & Period](#7-tone--period)
8. [Win Conditions](#8-win-conditions)
9. [Design Decisions Log](#9-design-decisions-log)
10. [MVP Vertical Slice](#10-mvp-vertical-slice)
11. [MVP Rosters](#11-mvp-rosters)
12. [Explicit MVP Exclusions](#12-explicit-mvp-exclusions)
13. [Production Phases](#13-production-phases)
14. [Post-MVP Roadmap](#14-post-mvp-roadmap)
15. [Scope Discipline Rules](#15-scope-discipline-rules)
16. [Documents To Be Written](#16-documents-to-be-written)
17. [Status Tag Reference](#17-status-tag-reference)

---

# PART I — VISION

## 1. Vision

### Logline

*RealVietnamRts is a logistics-first Vietnam War RTS where you carve a battlespace out of jungle — clearing roads, building interlocking firebase networks, and running physical supply chains under constant threat — while a doctrine-based force composition system forces every unit and every supply line to matter.*

---

## 2. The Player Fantasy

You are a US Army battalion commander in a fictional unit operating in real Vietnamese geography during the period 1965-1972. Your AO is opaque jungle, broken terrain, and contested villages. Your job is to carve out a defensible position, push supply lines forward, send patrols to find and destroy the enemy, and hold what you build against an enemy who decides when and where to fight.

You are not a tactical squad leader. You are not babysitting individual soldiers. You command an operation. You decide the *shape* of the fight — where firebases go, where roads get cut, what your reinforcement schedule looks like. The fight itself is automated in the small and decided by you in the large.

---

## 3. The Five Pillars

### Pillar 1: Carve the Map
The battlespace is opaque until you make it legible. Bulldozers cut roads through hills, engineers use det-cord to clear jungle pockets and LZs. Every cleared meter is vision, mobility, and supply. The map is a first-class entity — terrain matters, height matters, every river crossing and every ridgeline shapes the campaign.

### Pillar 2: Network of Firebases
Build interlocking forward positions, each with its own LZ and road link back to the supply network. Place every sandbag and bunker yourself with paint/drag perimeter tools. Engineers auto-construct inside established zones; you direct them manually for forward bunker complexes outside the wire. No two firebases look the same. The firebase is your design.

### Pillar 3: Physical Supply Chains
Trucks on roads, helicopters between LZs, fixed-wing from captured airstrips. Supply is spatial, not abstract. Cut a road, crater a runway, ambush a convoy — supply chains exist in the world and they can be attacked. A firebase isolated from supply is a firebase that dies slowly.

### Pillar 4: Doctrine Over Spam
Pre-mission deck commits you to a force composition (Air Cavalry, Mechanized Infantry, Marine Force, etc.). Cards unlock both unit types AND the buildings required to field them. Reinforcements arrive by helicopter or convoy in real time — minutes, not seconds. Lose a tank and you wait for the next convoy. Lose your supply line and you starve. Force preservation matters more than force production.

### Pillar 5: The War Continues
Patrols run on standing orders. Defenses fire automatically. Convoys run schedules. Engineers auto-build in zones. You command the operation; you don't babysit individuals. Long missions (45-90+ min) reward planning over reflexes. The game runs whether you're watching that sector or not.

---

## 4. Reference Games

| Game | What we borrow |
|------|----------------|
| **C&C Generals** | Faction doctrines, base-building feel, persistent map control |
| **Steel Division / Wargame** | Pre-mission deck, period authenticity, combat lethality, phased availability |
| **Company of Heroes** | Sector/territory logic, cover system, suppression, squad-level combat |
| **Supreme Commander** | Automation philosophy, strategic zoom, "commander not babysitter" |
| **Foxhole** | Logistics as physical reality — supply chains you can see and cut |
| **Men of War: Vietnam** | Period detail, vehicle/weapon realism, mixed-arms combat |
| **R.U.S.E.** | Strategic zoom for managing wide AOs without losing tactical detail |
| **Battlefield Vietnam (2004)** | Visual reference for the early-2000s aesthetic target |
| **Joint Operations: Typhoon Rising (2004)** | Helicopter/jungle/firebase visual and tonal reference |
| **Warno** | Reinforcement timing, deck building, combined arms |
| **Broken Arrow** | Modern combined arms, realistic lethality, supply vulnerability |

---

## 5. Anti-Pillars — What the Game Is NOT

- **Not Age of Empires.** No rapid unit production. No rally points spitting units. No instant-buy reinforcements. If you want a tank, you wait for the convoy that's bringing it.
- **Not WARNO pure.** This is not a deployment-then-fight game. You carve, build, reinforce, and adapt throughout the mission.
- **Not Foxhole.** Single-player and co-op campaign. Not a persistent MMO war.
- **Not Spec Ops: The Line.** Villages, civilians, and morally complex situations exist and are handled with care, but the primary tone is *strategy in a difficult setting*, not a moral-weight piece. We are not making a war crimes simulator.
- **Not a sandbox.** Missions have objectives, escalation curves, time pressure. Skirmish is open-ended; campaign missions are not.
- **Not retro.** Early-2000s RTS aesthetic (Generals, Rome: Total War, Battlefield Vietnam '04) — mid-poly, hand-painted, real lighting. Not PS1, not voxel, not pixel art.
- **Not symmetric.** US and VC play fundamentally different games. We are not making a "VC with re-skinned tanks" faction.

---

## 6. Asymmetry: US vs. VC/NVA

This game is *about* the asymmetry of the Vietnam War. The two sides do not play the same game.

| Aspect | US | VC / NVA |
|--------|-----|----------|
| **Logistics** | Trucks on roads, helicopters to LZs, fixed-wing from airstrips. High capacity, visible, vulnerable to interdiction. | Cached supplies (pre-placed by player or via Ho Chi Minh Trail), porter teams, tunnel storage. Low capacity, hard to spot. |
| **Force generation** | Reinforcements arrive at firebase LZs over minutes | Spawn from tunnel networks and infiltrate from map edges |
| **Buildings** | Bunkers, wire, sandbags, helipads, airstrips, mortar pits | Tunnel entrances, spider holes, weapon caches, punji traps, sapper staging |
| **Win condition (skirmish)** | Hold firebases, clear the AO | Destroy firebases, sustain attrition, survive |
| **Tempo** | Deliberate buildup, then sustained pressure | Strike-and-fade, harassment, occasional all-out offensive |

In MVP: US is the campaign faction. VC is playable in skirmish only. Post-MVP: VC gets campaign missions.

---

## 7. Tone & Period

**Setting:** Fictional US Army battalion (1st Battalion, 7th Cavalry analogue) operating in II Corps Tactical Zone, 1965-1972.

**Tone:** Filmic. Period-authentic. Respectful of the war's weight without sanitizing or wallowing. The game is about *operating* in this conflict, not about morally judging it. Villages, civilians, and ambiguous combat situations exist as mechanics because they were the reality of Vietnam ground operations — they are handled with care, not as the central theme.

**Visual style:** Early-2000s RTS aesthetic. Mid-poly models with hand-painted textures, real lighting and shadows, readable at strategic zoom. Specific references: C&C Generals (2003), Rome: Total War (2004), Battlefield Vietnam (2004), Joint Operations: Typhoon Rising (2004). Ages well. Achievable as a small team. Not retro slop, not photorealistic.

**Audio:** Era-appropriate radio chatter, M16/AK-47 distinct soundscapes, Huey rotor wash as a recurring motif. Music: period-influenced where appropriate, original score for the strategic layer.

---

## 8. Win Conditions

- **Campaign mission win:** Specific objectives complete (varies per mission — clear AO, hold for duration, destroy specific position, etc.)
- **Campaign mission loss:** Designated command post / main firebase destroyed, OR all player forces eliminated, OR total supply collapse for extended duration
- **Skirmish (US):** Hold all firebases against escalating waves for duration, OR achieve specified destruction objectives
- **Skirmish (VC):** Destroy US firebases, OR sustain attrition victory by depleting US supply over time

---

# PART II — DESIGN DECISIONS

## 9. Design Decisions Log

> Every non-obvious design decision, why it was made, and what was considered as alternative. When you forget in three months why something is the way it is, look here. When Claude Code proposes changing something, check here first. New decisions get appended chronologically (newest at bottom of each section). If a `[LOCKED]` decision is revisited, log the change with a new date — don't delete history.

### VISION-LEVEL DECISIONS

#### D-001: Game scale is multi-firebase strategic, not single-firebase tactical
**Status:** `[LOCKED]` 2026-05-13
**Decision:** The full game is multi-firebase: build an interlocking network of forward positions across an AO with road links between them, supplied from rear depots.
**Alternative considered:** Single-firebase CoH-scale gameplay (one base, ~60 min, ~20 units).
**Rationale:** Single-firebase doesn't deliver the "logistics-first" pillar — you can't have interesting logistics if there's only one position to supply. Multi-firebase is also where the Vietnam-period authenticity lives (Khe Sanh, the I Corps firebase belt, the Central Highlands network of forward positions).
**Consequence:** Missions are 45-90+ min. Map sizes are 2-9 km². Player manages 40-80+ units across multiple positions. Strategic zoom is mandatory, not optional.

#### D-002: MVP vertical slice uses only two firebases
**Status:** `[LOCKED]` 2026-05-13
**Decision:** MVP scope is one main firebase + one forward outpost, linked by one cleared road, supplied from one rear depot with one airstrip. ~2 km² map.
**Alternative considered:** Full network-scale (4-6 firebases) as MVP.
**Rationale:** Two-firebase scale proves the *network* aspect (multiple positions, supply links, interlocking defense) without requiring 3-hour missions before we know the loop is fun. Validates pillars 1-5 at a cost we can ship in weeks, not months.
**Consequence:** All systems must be designed to scale UP from 2 to N firebases without architectural changes. No hardcoding "the firebase" — always treat firebases as a collection.

#### D-003: VC is a fully asymmetric faction, not a re-skin
**Status:** `[LOCKED]` 2026-05-13
**Decision:** US and VC have fundamentally different mechanics for force generation, logistics, and win conditions. VC playable in skirmish from MVP. VC campaign missions post-MVP.
**Alternative considered:** US-only at MVP, VC bolted on later; or symmetric VC with re-skinned units.
**Rationale:** Asymmetric warfare is the thematic core of Vietnam. A symmetric Vietnam RTS misses the obvious hook. Building asymmetry into the architecture from MVP costs ~15-20% extra scope but prevents a major refactor later.
**Consequence:** All faction-touching systems must be parameterized by faction. No hardcoded references to "trucks" or "helipads" in faction-agnostic code. Buildings, units, doctrines, and win conditions all carry a faction tag.

#### D-004: Hybrid historical/fictional campaign approach
**Status:** `[LOCKED]` 2026-05-13
**Decision:** Player commands a fictional unit (e.g. 1/7 Cavalry analogue) operating in real geographic AOs during real historical periods. Missions are inspired by real operations but not docu-drama recreations.
**Alternative considered:** Fully historical (recreate specific battles), fully fictional (made-up AOs).
**Rationale:** Hybrid gives creative freedom for mission design without losing period weight. Wargame and Steel Division both use this approach successfully. Matches existing tone in the user's Vietnam comic project.
**Consequence:** AO names are real (Ia Drang Valley, A Shau Valley, etc.), units and callsigns are fictional. Period equipment must match the date (no Cobras pre-1967, etc.).

#### D-005: Early-2000s RTS aesthetic
**Status:** `[LOCKED]` 2026-05-13
**Decision:** Mid-poly models, hand-painted textures, real lighting and shadows. Visual targets: C&C Generals (2003), Rome: Total War (2004), Battlefield Vietnam (2004), Joint Operations: Typhoon Rising (2004).
**Alternative considered:** PS1 low-poly with vertex snapping (reusing Catacombs shaders), realistic modern Steel Division-like fidelity, stylized 1960s filmic.
**Rationale:** PS1 carries personality but conflicts with strategic-scale readability — units become blobs at zoom. Modern realistic is unachievable for a solo/small team competing with Eugen on their own ground. Early-2000s is achievable, ages well, distinctive without being divisive, and is the natural home for the genre.
**Consequence:** Visual style guide must be written (see future Volume 7). Asset pipeline targets ~1500-3000 tris per unit, ~512px hand-painted diffuse textures, standard PBR is overkill — diffuse + spec/gloss is enough. PS1 shaders from Catacombs are NOT reused here.

### CORE LOOP DECISIONS

#### D-101: No Age of Empires-style unit production
**Status:** `[LOCKED]` 2026-05-13
**Decision:** Units cannot be "built" at firebases. Reinforcements arrive only via helicopter or convoy from supply chain. Lose a unit and you wait — minutes, not seconds — for replacement.
**Rationale:** This IS pillar 4. The whole game's tension lives here. AOE-style unit-vending undermines every other system — supply doesn't matter if you can spam units, doctrine decks are meaningless if you have infinite access, force preservation is moot if death is free.
**Consequence:** Reinforcement timing is the single most important balance variable. Probably 3-7 minutes for light infantry resupply, 10-15 minutes for armor, longer for specialized assets. Long missions (45+ min) are required for this to feel right.

#### D-102: Engineers auto-build inside zones, manual outside
**Status:** `[LOCKED]` 2026-05-13
**Decision:** "Established zones" (firebase perimeters, cleared areas) allow paint/drag perimeter tools and engineer auto-construction. Outside those zones — forward bunker complexes, ambush positions, etc. — engineers are directly commanded.
**Rationale:** Auto-build inside zones avoids tedious sandbag-by-sandbag micro. Manual outside zones preserves tactical decisions for high-stakes construction.
**Consequence:** Engineers under fire while building must have defined behavior: pause construction, seek cover, resume when safe. Engineer combat capability is mediocre by default; flamethrower-equipped engineer variant exists as combat option.

#### D-103: Det-cord engineers vs. bulldozers for terrain clearing
**Status:** `[LOCKED]` 2026-05-13
**Decision:** Two distinct terrain-clearing tools.
- **Bulldozers:** Fast, large-area, road-grade clearing. Required for road construction and big-footprint buildings (airstrips, large firebases).
- **Engineer det-cord:** Slower, smaller, more tactical. Clears jungle pockets, prepares LZs, opens fire lanes.

**Rationale:** Single tool was too one-note. Two tools give the player real choices ("rush a road through" vs. "carefully clear LOS for an ambush").
**Consequence:** Need terrain types that respond differently to each tool. Bulldozers can't easily push up steep hills (engineers more flexible there). Det-cord doesn't make a road. Both vulnerable while working.

#### D-104: Airstrips are map features, not buildings
**Status:** `[LOCKED]` 2026-05-13
**Decision:** Airstrips exist on the map as static features. Player either starts controlling one, or must capture one. Lost airstrip = no fixed-wing supply or air strikes from that base. VC sappers can crater runways, grounding aircraft until engineers repair.
**Alternative considered:** Buildable airstrips at rear-area safe zones with long build times.
**Rationale:** Historically accurate (Bien Hoa, Da Nang, Pleiku were existing French-built airbases the US occupied and defended). Mechanically interesting — runway becomes a high-value target you must defend. Engineering: building airstrips during missions adds complexity for marginal gameplay value.
**Consequence:** Map design must include airstrip locations as significant terrain features. Runway crater repair is an engineer task with specific build time. Sapper attacks on runways are a scripted enemy threat.

#### D-105: Deck cards include unit cards AND auto-include required buildings, plus 4-6 flexible building slots
**Status:** `[LOCKED]` 2026-05-13
**Decision:** Pre-mission deck selection works as follows:
1. Player picks a doctrine (e.g., "Air Cavalry")
2. Doctrine determines which unit cards are available
3. Picking a unit card auto-includes its required buildings (tank card → tank revetment building card)
4. Player additionally picks 4-6 *flexible* building cards from a doctrine-determined pool

**Rationale:** Auto-included buildings prevent "I brought tanks but forgot the revetment" frustration. Flexible slots preserve interesting strategic choices ("do I bring an extra ammo bunker or a watchtower?").
**Consequence:** Card system has three knobs to balance: doctrine selection, unit slots, flexible building slots. Each doctrine needs ~10-15 unit cards and ~10-15 building cards in its pool. MVP scope: 1 doctrine per side, fully fleshed out.

#### D-106: Save system parked until post-MVP, architect for it anyway
**Status:** `[LOCKED]` 2026-05-13
**Decision:** Mid-mission save/load is post-MVP. However, all systems must be written with serialization-friendly patterns from day one (state held in data, not in scene graph; signals over direct refs; deterministic state machines).
**Rationale:** Saves are hard to bolt on, but committing engineering bandwidth to implementation pre-MVP delays the vertical slice. Hygiene now = cheap saves later.
**Consequence:** Code review checklist must flag non-serializable patterns. No raw `Node` references stored across frames — use IDs or paths. No state stored in `@onready` lookups that can't be recomputed on load.

### SCOPE DECISIONS

#### D-201: SOG long-range recon teams parked indefinitely
**Status:** `[LOCKED]` 2026-05-13
**Decision:** The existing 1471-line `sog_team.gd` does NOT get integrated into the MVP. It's archived for post-MVP consideration.
**Rationale:** SOG ops are a whole separate gameplay layer (small team behind enemy lines, mission types, compromise mechanic, extraction). It's cool, but it doesn't prove any of the five pillars in MVP. Ship without it, add later as content update.
**Consequence:** SOG code moves to `archive/sog_system/` (don't delete — it's substantial work). Not referenced by any active code. Not in the MVP entity catalogue.

#### D-202: Villages stay, tunnels stay, weather parked
**Status:** `[LOCKED]` 2026-05-13
**Decision:**
- **Villages:** IN for MVP at minimal scope. Pre-placed on map, allegiance affects whether VC can stage from them. Civic action mechanics post-MVP.
- **Tunnels:** IN for MVP as VC spawn mechanic. Find them and destroy them, or they keep spitting infiltrators.
- **Weather:** Parked. Full system exists in code (Clear/Overcast/Monsoon/Fog/Night) but not wired in for MVP. Re-introduce post-MVP.

**Rationale:** Villages and tunnels are core to Vietnam's gameplay identity and support the "seek and destroy" pillar. Weather is atmosphere — nice but not pillar-load-bearing for MVP.
**Consequence:** Village system code stays active but trimmed to allegiance + spawning. Tunnel system stays active. Weather system code archived to `archive/weather_system/` for post-MVP re-integration.

#### D-203: Strategic air support parked for MVP
**Status:** `[LOCKED]` 2026-05-13
**Decision:** Napalm runs, Arc Light B-52 strikes, AC-47 Spooky, A-1 Skyraider CAS are all post-MVP.
**Rationale:** MVP air support is limited to helicopter assets (Huey transport, Huey gunship). Adds fast iteration cycle for the core loop without strategic air being a balance complication.
**Consequence:** `air_support_manager.gd` stays in code but only Huey gunship calls are wired. Strategic air strike cards exist in the deck-system design but are flagged "post-MVP."

#### D-204: MVP roster is locked at 6 US units + 4 VC units + 14 buildings
**Status:** `[LOCKED]` 2026-05-13
**Decision:** See [MVP Rosters](#11-mvp-rosters) for full roster.
**Rationale:** Smallest roster that proves all five pillars with both factions playable. Anything past this risks scope creep before the loop is validated.
**Consequence:** Hard line — no additional units or buildings in MVP without explicit scope amendment in this doc.

### TECHNICAL DECISIONS

#### D-301: The codebase will be cleaned up before any new feature work
**Status:** `[LOCKED]` 2026-05-13
**Decision:** Before writing any new code, resolve the dual-project mess: archive `game/`, create `project.godot` at root, register autoloads, resolve class-name collisions, normalize line endings to LF.
**Rationale:** Continuing to work on a project Godot can't open is impossible. Every Claude Code session burns time on phantom issues otherwise.
**Consequence:** See Phase 0 in production plan.

#### D-302: Building inheritance uses `BaseStructure` extending `StaticBody3D`
**Status:** `[LOCKED]` 2026-05-13
**Decision:** The "old" architecture pattern wins for building inheritance: `Bunker extends BaseStructure extends StaticBody3D`. The "new" `BuildingBase extends Node3D` (which manually creates a StaticBody3D child) pattern is rejected.
**Rationale:** More Godot-idiomatic, simpler signal/collision routing, less code, fewer node lookups at runtime.
**Consequence:** Merge new building behaviors (firebase tier system, GameEnums.BuildingType, garrison mechanics) into the StaticBody3D-extending hierarchy from old code. Migration plan in Phase 0.

#### D-303: Faction-parameterized everything
**Status:** `[LOCKED]` 2026-05-13
**Decision:** All units, buildings, systems carry a `faction` enum. No hardcoded references to "trucks" or "helipads" in code that should work for either side.
**Rationale:** D-003 (asymmetric VC) requires this. Cheap if done from day one, expensive to retrofit.
**Consequence:** Code review checklist must flag "this assumes US" code paths.

#### D-304: TerrainEngine integration for terrain generation
**Status:** `[LOCKED]` 2026-05-13
**Decision:** Use the TerrainEngine project (3km x 3km chunked streaming, domain warping, hydraulic erosion) as the terrain foundation.
**Components:**
- `TerrainManager` - Chunk streaming
- `ClearingSystem` - Progressive jungle clearing (JUNGLE → PARTIALLY_CLEARED → CLEARED → FORTIFIED)
- `DamageSystem` - Craters and terrain deformation
- `VegetationManager` - Terrain types and density
**Consequence:** Terrain clearing is now a visual and gameplay system. Craters from explosives persist. Firebase construction requires cleared terrain.

#### D-305: Persistent Expanding Map Campaign
**Status:** `[LOCKED]` 2026-05-13
**Decision:** The campaign uses a **single persistent map** that expands with each mission:
1. **Mission 1** starts with a small playable area (~500m x 500m)
2. Each subsequent mission **reveals and unlocks** a new larger section of the same map
3. **All terrain modifications persist:** roads, cleared jungle, craters, firebase fortifications
4. **All constructed bases persist:** player investments carry forward
5. **Final mission** reveals the complete 3km x 3km map with all prior work visible
6. **10 missions total**, ranging from 50 minutes to 1.5 hours each

**Rationale:**
- Creates genuine investment in terrain control — every road matters across the whole campaign
- Teaches mechanics progressively (small scale → full combined arms)
- Final mission becomes a capstone test of everything player has built
- Unique design — no other RTS does persistent expanding maps
- Aligns perfectly with "Carve the Map" pillar

**Implementation:**
- TerrainEngine chunks unlock progressively (start with inner chunks, expand outward)
- Save system must serialize: terrain clearing state, crater positions, building positions, road network
- Mission N's starting area = union of all previous mission areas
- New fog of war covers unexplored regions until mission objective triggers expansion

**Consequence:**
- Campaign progression becomes spatially legible — player can see their progress on the map itself
- Tutorial integrated into campaign — each mission introduces new mechanics in expanded terrain
- Save system becomes critical infrastructure (must implement before campaign)
- Map design must work at all zoom levels (small early maps feel intimate, full map feels epic)

### DEFERRED DECISIONS

These need answers before they become blocking, but they're not blocking right now.

#### D-901: Specific reinforcement timing values
**Status:** `[REVISIT after first playtest]`
**Question:** How long does it take for a Rifle squad to arrive? An M48? A specialist team?
**Current placeholder:** 3-5 min infantry, 10-15 min armor, 5-7 min specialists. Tune via playtest.

#### D-902: Map size for MVP
**Status:** `[REVISIT after Week 1]`
**Question:** Exactly 2 km², or smaller for first playable?
**Current placeholder:** 2 km² target, smaller acceptable for proof-of-concept.

#### D-903: Co-op multiplayer architecture
**Status:** `[PARKING LOT]`
**Question:** When/if we add co-op, does player 2 share commander view or run a separate firebase?
**Decision:** Defer until MVP ships. Mention nothing about co-op in MVP marketing.

#### D-904: Civilian representation rules
**Status:** `[REVISIT before village system goes in]`
**Question:** When villages contain civilians and a player attacks: what happens visually, mechanically, narratively?
**Decision:** Defer until village system integration starts. Hold a focused design session on tone at that point. For MVP, villages are abstracted (just "allegiance," no individual civilian agents).

#### D-905: Audio direction and source
**Status:** `[REVISIT in Volume 7 of bible]`
**Question:** Original score or licensed? Period radio chatter recreated or stylized? Who's writing/sourcing audio?
**Decision:** Out of scope until visual/audio direction doc is written.

#### D-906: Final game title
**Status:** `[REVISIT before public-facing materials]`
**Question:** "RealVietnamRts" is a working title. Final title TBD.
**Current placeholder:** RealVietnamRts.

---

# PART III — SCOPE & PRODUCTION

## 10. MVP Vertical Slice

### Purpose
Prove that all five pillars deliver a fun core loop in one playable mission. If the slice is fun, we expand. If it's not, we cut and re-scope before doing any more work.

### Definition of Done for MVP
A playable mission you can boot, finish in 60-90 minutes, and which delivers:
1. **Carve the Map** — at least one bulldozer-cut road and one engineer-cleared LZ
2. **Network of Firebases** — two firebases, one main + one forward outpost
3. **Physical Supply Chains** — truck convoys on roads, helicopter resupply, captured airstrip
4. **Doctrine Over Spam** — pre-mission deck choice, in-mission reinforcements over time
5. **The War Continues** — auto-defending firebases, auto-patrolling squads, scheduled convoys

### The Mission: "Establish Firebase Alpha"

**Setting:** Pleiku Province, II Corps Tactical Zone, late 1965.
**Player force:** 1st Battalion, 7th Cavalry (fictional). Air Cavalry doctrine pre-selected for first-play; player can switch to Mechanized.
**Map:** ~2 km² of mixed terrain — jungle, rolling hills, one river with a single ford, one existing road, one captured airstrip (Camp Holloway analogue) at the rear, one fictional village (allegiance: neutral, non-interactive in MVP), no tunnels visible at start.

**Objectives:**
1. Establish Firebase Alpha at a designated hilltop clearing (10 min build window before first contact)
2. Clear and grade a road from Camp Holloway to Firebase Alpha (player chooses route)
3. Establish forward outpost Firebase Bravo at a secondary location of player's choosing
4. Hold both firebases against escalating VC/NVA assaults for 45 minutes after Bravo is established

**Win condition:** Both firebases standing at mission timer. Supply chain intact.
**Loss condition:** Firebase Alpha destroyed, OR total supply collapse for 5+ minutes, OR all forces destroyed.

---

## 11. MVP Rosters

### US Player Units (6)

| Unit | Role | Reinforcement Time | Notes |
|------|------|----|----|
| Rifle Squad | General infantry, can garrison | 3 min | 10 soldiers, M16+M60+M79 |
| Engineer Squad | Construction, terrain clearing | 4 min | 8 soldiers, det-cord, mediocre combat |
| Weapons Squad | Fire support | 5 min | 8 soldiers, M2 .50cal or 81mm mortar |
| Recon Team | Stealth scouting, extended sight | 3 min | 4 soldiers, stealth-focused |
| M48 Patton | Heavy armor | 12 min | Tank, requires tank revetment building |
| Huey Transport (UH-1D) | Air mobility | 6 min | Transports 1 squad, also delivers supplies |

### US "Called-In" Air Assets (deck-locked, on cooldown)
- Huey Gunship (UH-1B) — fire support pass, 90s cooldown, 4 uses per mission

### VC AI Units (4)

| Unit | Role | Spawn Source | Notes |
|------|------|----|----|
| VC Infantry | Light infantry | Tunnel entrances, map edges | AK-47, basic |
| VC Sappers | Infiltrators | Tunnel entrances | Bypass wire/mines, target structures |
| VC Mortar Team | Indirect fire | Tunnel entrances | 60mm mortar, hit-and-run |
| VC Porter | Supply carriers | Map edges | Non-combat, target for player |

### US Buildings (10)

| Building | Cost | Build Time | Function |
|----------|------|------|----------|
| Command Post | Starting | — | HQ. Destroy = game over |
| Sandbag Wall | Free | Fast | Basic cover, drag-paint perimeter |
| Wire Obstacle | Cheap | Fast | Slows enemy, channels attacks |
| Foxhole | Free | Fast | Infantry fighting position |
| Bunker | Medium | Moderate | Heavy cover, garrison 1 squad |
| MG Nest | Medium | Moderate | Auto-fires arc, suppresses |
| Mortar Pit | Heavy | Slow | Indirect fire, player or auto |
| Supply Depot | Medium | Moderate | Stores supplies, resupplies nearby squads |
| Helipad | Heavy | Slow | LZ for incoming helicopters |
| Observation Tower | Medium | Moderate | Extended sight, spots for mortars |

### VC Buildings (4)

| Building | Function |
|----------|----------|
| Tunnel Entrance | Spawn point for VC units, hidden until spotted |
| Spider Hole | Single-soldier ambush position, very hard to see |
| Weapon Cache | Resupply point for VC squads, finite |
| Punji Trap | Cheap damage trap, one-use |

### Vehicles (non-combat, support)
- M35 "Deuce-and-a-half" truck — convoy supply
- D7 bulldozer — road grading, large clearing

### Doctrine Decks (MVP)

- **US "Air Cavalry":** Bias toward helicopters, light infantry, mobility. Bonus: faster Huey reinforcement timing. Required buildings: Helipad x2. Flexible slots: 4.
- **US "Mechanized" (alt for MVP):** Bias toward armor, slower but heavier. Bonus: 1 free M48 at mission start. Required buildings: Tank revetment. Flexible slots: 4. *Not required for first vertical slice — can be added Week 4-5.*
- **VC "Local Force":** Bias toward attrition, tunnels, sappers. Bonus: extra tunnel entrance at start. Required buildings: Tunnel entrance x3. Flexible slots: 4.

---

## 12. Explicit MVP Exclusions

These exist in code (some fully built) but are NOT in MVP:

- Weather system (archived for post-MVP)
- Strategic air strikes — Napalm, Arc Light, Spooky, Skyraider (parked)
- Village civic action / allegiance shifts (allegiance stays static at "neutral" in MVP)
- Civilian representation
- SOG long-range recon (archived)
- Mid-mission saves (architect for serialization, don't implement load)
- Multi-mission campaign chain
- Multiplayer / co-op
- Map editor / mod support
- Cobra gunships, Chinooks, additional helicopter types
- ARVN allied units
- NVA conventional armor (PT-76, T-54)
- AAA emplacements
- Tank-on-tank combat (M48 vs nothing in MVP; armor exists to wreck infantry)

---

## 13. Production Phases

### Phase 0: Codebase Cleanup (Week 0)
**Goal:** Get to a state where Godot can open and run the project.

- Archive `game/` directory → `archive/game_old/` (don't delete)
- Archive currently-parked systems → `archive/sog_system/`, `archive/weather_system/`
- Create `project.godot` at repo root with:
  - Main scene = `scenes/main.tscn`
  - Autoloads: `GameEnums`, `BattleSignals`, `CombatManager`, `CoverSystem`, `ReinforcementManager`, `AirSupportManager`, `WeatherSystem` (stub for MVP)
  - Physics layers: terrain, infantry, vehicles, structures, projectiles, cover, jungle
  - Input map: WASD + arrows, mouse select, mouse command, Q/E rotate, scroll zoom, hotkeys 1-9 for groups, F1-F4 debug
- Resolve class-name collisions: `Bunker`, `MGNest`, `Helicopter`, `LandingZone` (new versions win, merge old combat behavior in)
- Migrate new `BuildingBase extends Node3D` hierarchy to `BaseStructure extends StaticBody3D` (per D-302)
- Normalize all `.gd` files to LF line endings
- Add faction parameter to all unit/building base classes (per D-303)
- Boot project, verify main scene loads with no errors

**Exit criteria:** Godot opens project. Main scene runs. No parse errors. No missing-class errors. Empty world but rendering.

### Phase 1: Terrain & Camera (Week 1)
**Goal:** Walkable world with strategic-zoom camera.

- One playable map (~2 km², heightmap-based terrain, manually placed jungle, hills, river, road, airstrip, village)
- RTS camera with WASD pan, edge scroll, scroll zoom (smooth from ~10m to ~500m), Q/E rotate, focus-on-selection
- Strategic zoom rendering — units at distance render as NATO-style markers (post-process effect at low zoom)
- Time of day baked into map (no day/night cycle for MVP — fixed at late afternoon for atmosphere)
- Skybox, terrain materials, basic foliage instancing (LOD-ed)
- Fog/draw distance for performance and atmosphere

### Phase 2: Units & Combat Foundation (Week 2)
**Goal:** Squads exist, move, fight.

- 4 US infantry types operational (Rifle, Engineer, Weapons, Recon) — no vehicles yet
- 2 VC infantry types (VC infantry, VC sappers)
- NavigationServer3D pathfinding with terrain-cost modifiers (jungle slow, road fast, water impassable)
- Selection: click, box-drag, control groups (1-9)
- Movement: right-click to move, queue with shift-click
- Combat: range-based, hit chance, damage, cover bonus (full / partial / none), suppression
- Squad casualty tracking (squad has N soldiers, takes damage, dies when N=0)
- Standing orders: Guard, Patrol, Aggressive, Hold Fire

### Phase 3: Construction & Logistics (Week 3)
**Goal:** Build firebases, supply them physically.

- Build menu UI with all 10 US buildings
- Paint/drag perimeter tools for sandbag/wire (inside established zones)
- Engineer auto-build inside zones, manual outside
- Bulldozer road-cutting mechanic with terrain modification (road becomes traversable)
- Engineer det-cord jungle clearing
- Truck convoy logic: spawns at depot, follows roads to firebase, delivers supplies, returns
- Helicopter logic: spawns at airstrip/rear LZ, flies to firebase LZ, delivers/loads, returns
- Supply consumption: ammo (units shoot), construction (building costs), reinforcements (unit arrivals)
- Captured airstrip mechanic: starts as "controlled by player," can be lost, runway cratering by sappers

### Phase 4: Reinforcement & Deck System (Week 4)
**Goal:** Doctrine-driven force composition with real reinforcement cadence.

- Pre-mission deck-builder UI (1 doctrine choice + flexible slots)
- Reinforcement queue: deck cards become available in-mission, costs supply, arrives via convoy/heli with real timer
- M48 Patton tank operational (vehicle physics, treads, main gun, MG)
- Huey transport (load/unload squads, supply delivery)
- Huey gunship called-in air asset (cooldown-based)
- Reinforcement "next arrival" UI clock on HUD

### Phase 5: AI & Mission Logic (Week 5)
**Goal:** Enemy waves, mission objectives, win/loss conditions.

- VC mortar team operational
- VC porter supply carriers operational
- AI Director: wave timing, escalating composition, attack-direction variation
- Tunnel entrance system: spawns VC units until found and destroyed
- Mission scripting: objective tracking, win/loss triggers
- Save-as-architecture review (no save implementation, but verify systems are serialization-friendly)

### Phase 6: Polish & Vertical Slice Validation (Week 6)
**Goal:** Make the slice presentable. Playtest. Decide if loop is fun.

- HUD polish: minimap with fog of war, supply ticker, reinforcement clock, mission objectives panel
- Combat VFX: muzzle flashes, tracer rounds, dust kicks, explosions, smoke
- Audio: weapon sounds, vehicle sounds, radio chatter on events, minimal ambient
- VC Local Force doctrine for skirmish
- Skirmish mode menu (US vs VC selectable)
- **Playtest the vertical slice. If fun: green-light Phase 7. If not: re-scope.**

---

## 14. Post-MVP Roadmap

> Sketched, not locked. Subject to revision after MVP playtest.

### Phase 7: Scale Up (Weeks 7-9)
- Expand to 4-6 firebases per mission
- Weather system re-integration
- Village allegiance and civic action
- Strategic air support (Napalm, CAS, Spooky)
- Additional US doctrines (Marine, Mechanized full)
- Additional VC/NVA doctrines (Main Force, NVA Conventional)

### Phase 8: Campaign Mode (Weeks 10-13)
- **10-mission persistent expanding map campaign** for US side (see D-305)
- Same map expands each mission; all terrain work persists
- Mission-to-mission persistence (terrain, buildings, unit veterancy, supply state)
- Cutscenes / briefing screens / debrief screens
- Mid-mission and between-mission save/load implementation
- Progressive unlock of mechanics (each mission introduces 1-2 new systems)

### Phase 9: VC Campaign (Weeks 14-17)
- 4-6 mission VC/NVA campaign
- Full asymmetric VC mechanics polish (Ho Chi Minh trail caches, infiltration routes)

### Phase 10: Polish & Launch Prep (Weeks 18-20)
- Audio direction overhaul
- Visual style sweep
- Performance optimization
- Achievements / progression
- Localization prep

### Parking Lot (No timeline)
- SOG missions (re-integrate archived code)
- Multiplayer / co-op
- Map editor
- Procedural mission generation
- Mod support
- Console ports

---

## 15. Scope Discipline Rules

1. **No additions to MVP roster.** If it's not in this doc's MVP section, it's not going in MVP. Want to add a Cobra gunship? Wait for Phase 7.
2. **Cuts are OK.** If a feature in this doc proves harder than expected, we cut from MVP and move to post-MVP rather than missing scope deadlines.
3. **Every Claude Code session starts with reading this document.** Drift comes from not knowing where you are.
4. **Scope changes require a Decisions Log entry.** No "I just added a system because Claude Code was already there." Log it or back it out.
5. **The vertical slice is sacred.** Phase 6 must conclude with a playtest decision. If the loop isn't fun, we don't bulldoze forward — we re-design.

---

# PART IV — DOCUMENT MANAGEMENT

## 16. Documents To Be Written

These will be added as needed in production phases:

- **Volume 3 — Rules:** Combat resolution, suppression, morale, supply economy formulas
- **Volume 4 — Entities:** Every unit, building, weapon, terrain with stats
- **Volume 5 — Missions:** Mission archetypes, campaign structure, mission designs
- **Volume 6 — UI/UX:** HUD spec, camera spec, command interface, info display
- **Volume 7 — Art:** Style guide, color palette, asset standards, VFX scope
- **Volume 8 — Tech:** Project structure, naming conventions, autoloads, signal bus
- **Volume 10 — Historical:** Period accuracy targets, source list, sensitivity notes
- **Glossary:** Vietnam-era military terminology
- **Pillars Quick Reference:** One-page printable reminder for the wall

---

## 17. Status Tag Reference

- `[LOCKED]` — Decided. Don't change without explicit re-decision logged in the Decisions section.
- `[LIVING]` — Designed to evolve. Add entries, don't delete history.
- `[DRAFT]` — Written but not signed off. May still change significantly.
- `[PROPOSAL]` — Idea, not committed yet.
- `[REVISIT]` — Decided to defer until a specific trigger.
- `[PARKING LOT]` — Cut for now. May come back later.

---

*End of document. Working title: RealVietnamRts. Document version: 1.0. Last updated: 2026-05-13.*
