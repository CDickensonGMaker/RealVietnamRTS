# Research Priority Synthesis
**Date:** 2026-05-26
**Purpose:** Prioritize existing RTS research patterns for implementation

---

## PATTERN INVENTORY

### From spring1944_analysis.md

| Pattern | Pillar Alignment | Implementation Effort | Priority |
|---------|-----------------|----------------------|----------|
| **Fear/Suppression System** | P5 (automation) | Medium | HIGH |
| Fear IDs (smallarm=2, mortar=4, artillery=8, napalm=16) | | | |
| NCO Fear Shields | P5 | Low | MEDIUM |
| Squad Composition Arrays | P4 (doctrine) | Low | Already done |
| Prone State When Suppressed | P5 | Low | HIGH |

### From broken_arrow_analysis.md

| Pattern | Pillar Alignment | Implementation Effort | Priority |
|---------|-----------------|----------------------|----------|
| **Physical Supply System** | P3 (supply chains) | High | CRITICAL |
| Ammo/Fuel/Medical tracking | | | |
| FOB as Spawn/Supply Point | P2 (firebases) | Medium | HIGH |
| Deck Building (pre-battle) | P4 (doctrine) | High | Medium |
| Supply Convoy Vulnerability | P3 | Low | HIGH |

### From coh_mow_construction.md

| Pattern | Pillar Alignment | Implementation Effort | Priority |
|---------|-----------------|----------------------|----------|
| **Interactive Placement** | P2 (firebases) | Medium | DONE ✅ |
| Click-drag linear structures | | | |
| Garrison Mechanics | P2 | Medium | HIGH |
| Bunker Upgrade Paths | P2 | Low | MEDIUM |
| Any Infantry Builds Foxholes | P2 | Low | MEDIUM |

### From warno_wargame_terrain.md

| Pattern | Pillar Alignment | Implementation Effort | Priority |
|---------|-----------------|----------------------|----------|
| **Cover Damage Reduction** | P1 (terrain) | Medium | HIGH |
| Forest/Hedgerow = 40%, Urban = 70% | | | |
| LOS System | P1 | High | HIGH |
| Smoke Breaks LOS | P1 | Low | MEDIUM |
| Training Levels (suppression recovery) | P5 | Low | LOW |

### From rts_toolbox_research.md

| Pattern | Pillar Alignment | Implementation Effort | Priority |
|---------|-----------------|----------------------|----------|
| **Spatial Hash Grid (16m)** | All | Medium | HIGH |
| Replace scattered queries | | | |
| Priority Update Scheduler | P5 (automation) | Medium | MEDIUM |
| Flow Fields (convoys) | P3 | High | MEDIUM |
| MultiMesh Rendering | Performance | High | LOW (future) |

---

## PRIORITY TIERS

### TIER 1: Critical Path to MVP Loop (Do Now)

These complete the core gameplay loop: Build → Defend → Survive

| Pattern | Source | Why Critical |
|---------|--------|--------------|
| **Garrison Mechanics** | CoH/MoW | Bunkers must have purpose - units inside firing out |
| **Cover Damage Reduction** | Warno | Combat feels wrong without cover mattering |
| **Suppression/Fear System** | Spring1944 | Defines combat pacing, pins units down |

**Test Milestone:** Place bunker → garrison squad → VC attacks → squad fires from bunker → cover reduces damage → suppression pins VC

### TIER 2: Supply Chain Reality (Next Sprint)

These make supply physical and attackable (Pillar 3)

| Pattern | Source | Why Important |
|---------|--------|---------------|
| **Ammo Consumption Tracking** | Broken Arrow | Running out of ammo creates tension |
| **Supply Truck Resupply** | Broken Arrow | Physical supply chain, not magic |
| **FOB Supply Radius** | Broken Arrow | Units near depot auto-resupply |

**Test Milestone:** Patrol runs out of ammo → truck convoy delivers → patrol resupplied → convoy ambushed → supply cut

### TIER 3: Performance Foundation (Parallel)

These don't change gameplay but enable scale

| Pattern | Source | Why Now |
|---------|--------|---------|
| **Spatial Hash Grid** | RTS Toolbox | Every "units in range" query uses this |
| **Priority Update Scheduler** | RTS Toolbox | Off-screen units update less often |

---

## RECOMMENDED IMPLEMENTATION ORDER

```
Phase 1: Combat Feel (Garrison + Cover + Suppression)
├── 1.1 Garrison mechanics for bunkers
├── 1.2 Cover damage reduction system
├── 1.3 Fear/suppression system
└── TEST: Bunker defense scenario

Phase 2: Supply Reality (Ammo + Resupply)
├── 2.1 Ammo consumption per weapon
├── 2.2 Supply depot radius auto-resupply
├── 2.3 Supply truck delivery mechanics
└── TEST: Patrol sustain scenario

Phase 3: Performance (Spatial + Scheduler)
├── 3.1 Spatial hash grid (16m cells)
├── 3.2 Replace all range queries
├── 3.3 Priority update scheduler
└── TEST: 100+ units without lag

Phase 4: Automation Polish (Standing Orders)
├── 4.1 NCO fear shields
├── 4.2 Smoke/concealment
├── 4.3 Training level effects
└── TEST: Auto-defense scenario
```

---

## WHAT WE'RE NOT DOING YET

Per GAME_BIBLE.md scope discipline:

| Pattern | Why Defer |
|---------|-----------|
| Flow Fields | Only needed for 20+ units same destination |
| MultiMesh Rendering | Premature optimization |
| Deck Building UI | Functional before pretty |
| ORCA Local Avoidance | Current pathfinding works |
| HPA* Hierarchical | Small maps first |

---

## COUNCIL QUESTIONS

1. **Does Tier 1 order make sense?** (Garrison → Cover → Suppression)
2. **Should we test current build BEFORE Phase 1?**
3. **Is Spatial Hash Grid actually blocking anything?**

---

*Synthesis complete. Awaiting Council deliberation.*
