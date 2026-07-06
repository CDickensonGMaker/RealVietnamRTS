# Systems Index

> **Status**: `[LIVING]`
> **Last Updated**: 2026-05-21
> **Source Documents**: GAME_BIBLE.md, PRD.md, Codebase Analysis

---

## Overview

Master index of all game systems with their design status, implementation status, and dependencies. Use this document to understand system relationships and prioritization.

---

## System Categories

### Core Layer (Engine-Level)
Systems that provide foundational services to all other systems.

| System | GDD | Priority | Design Status | Implementation Status | Owner |
|--------|-----|----------|---------------|----------------------|-------|
| Terrain Generation | `terrain-clearing.md` | P0 | Complete | In Progress | TerrainEngine |
| Cell Streaming | — | P0 | Complete | Complete | map_maker/ |
| Spatial Hash Grid | — | P0 | Complete | Complete | SpatialHashGrid autoload |
| Signal Bus | — | P0 | Complete | Complete | BattleSignals autoload |
| Camera System | — | P0 | Partial | In Progress | battle_system/camera/ |

### Gameplay Layer (Player-Facing Systems)
Systems the player directly interacts with.

| System | GDD | Priority | Design Status | Implementation Status | Pillar |
|--------|-----|----------|---------------|----------------------|--------|
| Combat System | `combat-system.md` | P0 | Complete | In Progress | 5 |
| Firebase System | `firebase-system.md` | P0 | Complete | In Progress | 2 |
| Supply & Logistics | `supply-logistics.md` | P0 | Complete | Partial | 3 |
| Construction System | `construction-system.md` | P0 | Complete | In Progress | 2 |
| Terrain Clearing | `terrain-clearing.md` | P0 | Complete | In Progress | 1 |
| Doctrine System | `doctrine-system.md` | P1 | Complete | Not Started | 4 |
| Morale & Routing | `morale-routing.md` | P1 | Complete | Not Started | 5 |
| Reinforcement System | `reinforcement-system.md` | P1 | Partial | In Progress | 4 |
| Helicopter System | `helicopter-system.md` | P1 | Partial | In Progress | 3 |
| Unit Resource System | `unit-resources.md` | P1 | Complete | Not Started | 3 |

### AI Layer
Enemy behavior and dynamic difficulty.

| System | GDD | Priority | Design Status | Implementation Status |
|--------|-----|----------|---------------|----------------------|
| AI Director | `ai-director.md` | P1 | Complete | Partial |
| VC Controller | — | P1 | Partial | In Progress |
| NVA Controller | — | P2 | Partial | In Progress |

### Meta Layer
Campaign and progression systems.

| System | GDD | Priority | Design Status | Implementation Status | Pillar |
|--------|-----|----------|---------------|----------------------|--------|
| Campaign Structure | `campaign-structure.md` | P2 | Complete | Not Started | 6 |
| Save System | `save-system.md` | P2 | Complete | Not Started | 6 |
| Skirmish Mode | — | P2 | Partial | Not Started | — |

### Environment Layer
Weather and time-of-day systems.

| System | GDD | Priority | Design Status | Implementation Status | MVP Status |
|--------|-----|----------|---------------|----------------------|------------|
| Day/Night Cycle | `day-night-weather.md` | P3 | Complete | Not Started | Parked |
| Weather System | `day-night-weather.md` | P3 | Complete | Not Started | Parked |

### UI Layer
Player interface systems.

| System | GDD | Priority | Design Status | Implementation Status |
|--------|-----|----------|---------------|----------------------|
| Selection System | — | P0 | Partial | In Progress |
| Build Menu | — | P1 | Partial | Not Started |
| HUD | — | P1 | Partial | Not Started |
| Minimap | — | P1 | Partial | Not Started |

### Parked Systems (Post-MVP)
Systems designed but not scheduled for MVP.

| System | GDD | Design Status | Notes |
|--------|-----|---------------|-------|
| SOG Operations | — | Complete | Archived at archive/sog_system/ |
| Strategic Air Strikes | — | Partial | Napalm, Arc Light, CAS |
| Village Civic Action | — | Partial | Allegiance shifts |
| Multiplayer/Co-op | — | Not Started | D-903 deferred |

---

## Priority Definitions

| Priority | Definition | MVP Status |
|----------|------------|------------|
| **P0** | Core - Game doesn't function without it | Required |
| **P1** | Important - Core loop incomplete without it | Required |
| **P2** | Enhancing - Improves experience significantly | Optional |
| **P3** | Polish - Nice to have | Post-MVP |

---

## System Dependencies

```
                    ┌─────────────────┐
                    │  Game Concept   │
                    │   (6 Pillars)   │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│    Terrain    │   │    Combat     │   │   Doctrine    │
│   Clearing    │   │    System     │   │    System     │
│  (Pillar 1)   │   │  (Pillar 5)   │   │  (Pillar 4)   │
└───────┬───────┘   └───────┬───────┘   └───────┬───────┘
        │                   │                   │
        │           ┌───────┴───────┐           │
        │           ▼               ▼           │
        │   ┌─────────────┐ ┌─────────────┐     │
        │   │   Morale    │ │    Unit     │     │
        │   │  & Routing  │ │  Resources  │     │
        │   └─────────────┘ └──────┬──────┘     │
        │                          │            │
        ▼                          ▼            ▼
┌───────────────┐          ┌───────────────┐    │
│  Construction │          │    Supply     │◄───┘
│    System     │          │   Logistics   │
└───────┬───────┘          │  (Pillar 3)   │
        │                  └───────┬───────┘
        ▼                          │
┌───────────────┐                  │
│   Firebase    │◄─────────────────┘
│    System     │
│  (Pillar 2)   │
└───────┬───────┘
        │
        │   ┌─────────────┐   ┌─────────────┐
        ├───►  Helicopter │   │Reinforcement│
        │   │   System    │   │   System    │
        │   └─────────────┘   └─────────────┘
        │
        ▼
┌───────────────┐
│  AI Director  │
└───────┬───────┘
        │
        ▼
┌───────────────┐
│   Campaign    │
│  (Pillar 6)   │
└───────────────┘
```

---

## Dependency Matrix

| System | Depends On | Blocks |
|--------|------------|--------|
| **Terrain Clearing** | Cell Streaming, Spatial Hash | Construction, Firebase |
| **Combat System** | Spatial Hash, Signal Bus | Morale, AI Director |
| **Firebase System** | Construction, Terrain Clearing | Supply, Reinforcement |
| **Supply Logistics** | Firebase, Roads | Unit Resources, Reinforcement |
| **Construction System** | Terrain Clearing | Firebase |
| **Doctrine System** | — | Reinforcement, Unit Roster |
| **Morale & Routing** | Combat System | — |
| **Unit Resources** | Supply Logistics | Combat (ammo), Morale (water) |
| **Reinforcement System** | Doctrine, Supply, Helicopter | — |
| **Helicopter System** | Firebase (LZs), Supply | Reinforcement |
| **AI Director** | Combat, Firebase, Supply | Campaign pacing |
| **Campaign Structure** | All gameplay systems | — |
| **Save System** | All systems (serialization) | — |

---

## Implementation Order (Recommended)

Based on dependencies and pillar coverage:

### Phase 1: Foundation (Weeks 1-2)
1. Terrain Clearing (Pillar 1) - *In Progress*
2. Camera System - *In Progress*
3. Selection System - *In Progress*

### Phase 2: Combat (Weeks 2-3)
4. Combat System (Pillar 5)
5. Morale & Routing

### Phase 3: Base Building (Weeks 3-4)
6. Construction System
7. Firebase System (Pillar 2)

### Phase 4: Logistics (Weeks 4-5)
8. Supply Logistics (Pillar 3)
9. Unit Resources
10. Helicopter System

### Phase 5: Force Structure (Weeks 5-6)
11. Doctrine System (Pillar 4)
12. Reinforcement System

### Phase 6: AI & Mission (Weeks 6-7)
13. AI Director
14. Mission scripting

### Phase 7: Campaign (Post-MVP)
15. Campaign Structure (Pillar 6)
16. Save System

---

## GDD Status Summary

| GDD | Status | Last Updated |
|-----|--------|--------------|
| `game-concept.md` | Complete | 2026-05-21 |
| `game-pillars.md` | Complete | 2026-05-21 |
| `systems-index.md` | Complete | 2026-05-21 |
| `combat-system.md` | Complete | 2026-05-21 |
| `firebase-system.md` | Complete | 2026-05-21 |
| `supply-logistics.md` | Complete | 2026-05-21 |
| `construction-system.md` | Complete | 2026-05-21 |
| `terrain-clearing.md` | Complete | 2026-05-21 |
| `doctrine-system.md` | Complete | 2026-05-21 |
| `ai-director.md` | Complete | 2026-05-21 |
| `morale-routing.md` | Complete | 2026-05-21 |
| `campaign-structure.md` | Complete | 2026-05-21 |
| `helicopter-system.md` | Complete | 2026-05-21 |
| `reinforcement-system.md` | Complete | 2026-05-21 |
| `unit-resources.md` | Complete | 2026-05-21 |
| `day-night-weather.md` | Complete | 2026-05-21 |
| `save-system.md` | Complete | 2026-05-21 |

---

## Codebase Mapping

| System | Primary Files | Autoload |
|--------|---------------|----------|
| Terrain Clearing | `firebase_system/terrain_clearing.gd` | TerrainClearingSystem |
| Combat | `battle_system/systems/combat_manager.gd` | CombatManager |
| Firebase | `firebase_system/firebase.gd`, `construction_zone.gd` | — |
| Supply | `reinforcement_system/convoy_manager.gd` | — |
| Construction | `firebase_system/construction_manager.gd` | ConstructionManager |
| Helicopter | `helicopter_system/insertion_manager.gd` | InsertionManager |
| Reinforcement | `reinforcement_system/reinforcement_manager.gd` | ReinforcementManager |
| AI Director | `battle_system/ai/` | — |
| Spatial Hash | `battle_system/ai/spatial_hash_grid.gd` | SpatialHashGrid |
| Signal Bus | `battle_system/signals/battle_signals.gd` | BattleSignals |
| Camera | `battle_system/camera/` | — |
| Map/Terrain | `map_maker/vietnam_terrain.gd`, `cell_streamer.gd` | — |
| Weather | `battle_system/systems/weather_system.gd` | WeatherSystem |

---

## Quick Reference: MVP Systems

**Must Have for MVP (P0-P1):**
- Terrain Clearing
- Combat System
- Morale & Routing
- Construction System
- Firebase System
- Supply Logistics
- Unit Resources
- Doctrine System
- Reinforcement System
- Helicopter System
- AI Director
- Selection/Camera/HUD

**Parked for Post-MVP:**
- Weather System
- Day/Night Cycle
- Campaign Structure (full)
- Save System (full)
- SOG Operations
- Strategic Air Strikes
- Village Civic Action
