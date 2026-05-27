# War Room Briefing: Depot Resource Management System

**Date:** 2026-05-27
**Query:** Design water and fuel depot system for unit sustainability
**Type:** Core Systems Design

---

## The Problem

Design a resource management system for unit sustainability:

1. **Rename "Fuel Depot" → "Water Tank"** - Tied to infantry water/hydration meter
2. **Add Vehicle Fuel System** - Vehicles need fuel to operate, cannot drive unlimited
3. **Depot Reservoir System** - Both depot types have ~10,000 unit capacity
4. **Smart Consumption** - Units only consume depot resources when below 100%
5. **Depot Maintenance** - Depots consume global supply (~100 every few minutes) to function
6. **Regeneration** - Depots regenerate their reservoir while supplies available

---

## Current State (Codebase Exploration)

### Infantry Water System (EXISTS in `Squad.gd`)
```gdscript
var current_water: float = 100.0
var max_water: float = 100.0
var water_depletion_rate: float = 0.05  # per second
```
- Auto-resupply works within firebase `influence_radius`
- `_auto_resupply()` in `_process()` restores water if within firebase range
- **Problem**: Consumes no depot resource, unlimited free water

### Vehicle Fuel System (PARTIAL in `VehicleComponent`)
```gdscript
enum ComponentType { ENGINE, TRACKS, TURRET, GUN, FUEL_TANK, AMMO_RACK }
```
- `FUEL_TANK` only tracks damage state
- **No fuel consumption**, no fuel level tracking
- Vehicles have unlimited operational range

### Firebase/Supply System
- `SupplyManager` handles global supply pool
- `Firebase.influence_radius = 168.0` meters
- Firebase has `supply_level` for construction costs
- No per-depot resource tracking

---

## User Requirements (Direct Quotes)

> "fuel depot should be known as Water Tank and thats tied into the water meter units have to stay hydrated"

> "vehicles cant just be driving around unlimited so maybe we do need to add fuel as a trackable supply chain"

> "make a rule that units that are low of these things will refil but when a unit at 100 percent they will not just keep using a bit and consuming the supply"

> "the fuel and water only works if theres supply to maintain their levels... would consume 100 supplies every couple of minutes"

> "depots will have a reservoir of 10,000 or something that gets eaten up as units replenish but will regenerate at a decent rate too"

---

## Constraints (From Game Bible)

- **Pillar 3**: Physical Supply Chains - "Supply is spatial and attackable"
- Depot buildings are destructible
- No infinite resources - everything has logistics cost
- Firebase system handles influence zones (168m radius)

---

## Architects Summoned

| Architect | Domain |
|-----------|--------|
| systems-designer | Resource flow, depot mechanics |
| game-designer | Player experience, tactical depth |
| balance-reviewer | Numbers, rates, edge cases |
| programmer | Technical implementation |
| devil's-advocate | Problems, exploits, edge cases |
