# War Room Synthesis: Depot Resource Management System

**Date:** 2026-05-27
**Arbiter's Decree**

---

## THE MATTER

Design a resource system where Water Tanks and Fuel Points sustain units, drawing from reservoirs that consume global supply for maintenance.

---

## COUNCIL CONSENSUS

### Points of Agreement

| Topic | Consensus |
|-------|-----------|
| Reservoir size | 10,000 units (sufficient for extended ops) |
| Maintenance cost | 100 supply every 2 minutes |
| Refill radius | 40-50m (distinct from firebase 168m) |
| Smart consumption | Units at 100% don't drain depot |
| Depot naming | "Water Tank" and "Fuel Point" |

### Points of Debate

| Topic | Options | Trade-off |
|-------|---------|-----------|
| **Scope** | Water only vs. Water + Fuel | Complexity vs. completeness |
| **Maintenance failure** | Hard shutdown vs. graceful degradation | Punishing vs. forgiving |
| **TOC fallback** | TOC provides emergency water vs. depot required | Safety net vs. pure logistics |
| **Multi-unit refill** | Sequential vs. parallel | Simple vs. fast |

---

## THE DECREE

### Phase 1: Water Tank System (Recommended First)

1. **Rename** `FUEL_DEPOT` → `WATER_TANK` in `BuildingType` enum
2. **Add** depot properties to PlacedBuilding or create DepotBuilding subclass
3. **Modify** `Squad._auto_resupply()` to consume from Water Tank instead of free firebase regen
4. **Add** maintenance tick system to SupplyManager
5. **Add** depot signals to BattleSignals

### Phase 2: Vehicle Fuel System (Deferred)

Implement after water system is tested and stable. Adds:
- Vehicle fuel tracking
- FUEL_POINT building type
- Immobilization when empty

### Key Design Decisions (Pending User Input)

**Decision 1: Breaking Change Handling**
Current: Infantry auto-resupply just from firebase proximity.
New: Infantry must be near Water Tank specifically.

Options:
- A) **Hard break** - Require Water Tank, no fallback
- B) **TOC fallback** - TOC provides emergency water at 50% rate
- C) **Firebase fallback** - Firebase still works, depot is just faster

**Decision 2: Maintenance Failure Mode**

When depot can't pay supply maintenance:
- A) **Hard shutdown** - Depot stops working entirely
- B) **Graceful degradation** - Depot works at 50% efficiency
- C) **Grace period** - Warning toast, 2 minutes before shutdown

**Decision 3: Multi-Unit Resupply**

When 10 squads crowd one depot:
- A) **First-come sequential** - Each unit takes turn, others wait
- B) **Parallel split** - Depot divides rate among all units
- C) **Priority queue** - Most critical units first

---

## QUESTIONS FOR THE SUMMONER

1. **Water only first, or both systems together?**
   - Recommendation: Water only, prove it works

2. **Break existing auto-resupply or provide fallback?**
   - Recommendation: Hard break - forces logistics play

3. **Hard shutdown or graceful degradation on maintenance failure?**
   - Recommendation: Grace period with warning

4. **Sequential or parallel multi-unit resupply?**
   - Recommendation: Parallel split (simpler math, feels fairer)

---

## IMPLEMENTATION ESTIMATE

| Phase | Components | Files |
|-------|------------|-------|
| Water Tank | Enum rename, depot class, squad changes, maintenance | 6 files |
| Vehicle Fuel | Vehicle tracking, new building, immobilization | 4 files |
| UI | Depot selection, warnings, unit indicators | 2 files |

---

*The Council awaits the Summoner's decisions on the four questions above.*
