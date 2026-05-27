# Game Designer Analysis: Depot Resource System

## Player Experience Goals

### What This Adds to Gameplay

1. **Forward Operating Pressure** - Units can't stay in the field forever
2. **Depot as Strategic Target** - Enemy can attack your water/fuel to cripple operations
3. **Logistics Decisions** - Build depots close to action vs. safe behind lines
4. **Tactical Retreats** - Units at low resources must fall back to resupply

### Risk: Micromanagement Hell

**Concern**: Player constantly watching water/fuel bars instead of fighting

**Mitigation**:
- Auto-resupply when in range (already exists for water)
- Warning UI only when critically low (<20%)
- Units seek nearest depot automatically when critically low
- Generous depletion rates - minutes of operation, not seconds

## Naming Recommendation

| Current Name | Proposed Name | Why |
|--------------|---------------|-----|
| Fuel Depot | **Water Tank** | Infantry hydration |
| (new) | **Fuel Point** | Vehicle refueling |

"Water Tank" is clearer than "Water Depot" - tanks hold water.
"Fuel Point" is military terminology for vehicle refueling stations.

## Gameplay Loop Integration

### Firebase Building Order (Typical)

1. TOC (HQ)
2. Bunkers, MG Nests (defense)
3. **Water Tank** (sustain infantry)
4. Helipad (resupply, medevac)
5. **Fuel Point** (if vehicles present)

### Edge Case: No Depot Built

If player never builds Water Tank:
- Infantry water depletes in the field
- Firebase influence zone should NOT provide water (change from current)
- Forces player to build logistics infrastructure

**This is a breaking change** - current auto-resupply happens just from being near firebase.

## Suggested Depot Stats

| Stat | Water Tank | Fuel Point |
|------|------------|------------|
| Supply Cost | 40 | 50 |
| Reservoir | 10,000 | 10,000 |
| Refill Radius | 40m | 50m |
| Maintenance | 100/2min | 100/2min |
| Build Time | Medium | Medium |

## UI Requirements

1. **Depot HUD** - Show reservoir level when depot selected
2. **Unit Icons** - Small water/fuel indicator in selection panel
3. **Warning Toasts** - "Water Tank running low" at 20%
4. **Minimap** - Optional: depot coverage circles
