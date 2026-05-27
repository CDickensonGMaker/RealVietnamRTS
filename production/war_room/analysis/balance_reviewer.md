# Balance Reviewer Analysis: Depot Resource System

## Numbers Audit

### Current Infantry Water System

| Stat | Value | Time to Deplete |
|------|-------|-----------------|
| max_water | 100 | - |
| depletion_rate | 0.05/sec | 33 minutes |

**Assessment**: 33 minutes is generous. Infantry can operate long missions.

### Proposed Depot Numbers

| Stat | User Request | Recommendation |
|------|--------------|----------------|
| Reservoir | 10,000 | 10,000 (good) |
| Maintenance Cost | 100 supply | 100 supply |
| Maintenance Interval | "couple minutes" | 120 sec (2 min) |
| Refill Rate | (not specified) | 5 units/sec |

### Math Check: Reservoir Sustainability

**Scenario**: 4 squads (48 soldiers) at depot

- Each squad refilling from 0 to 100 = 100 water
- 4 squads × 100 = 400 water per full resupply cycle
- At 5 units/sec, each squad takes 20 seconds to refill
- Reservoir supports 100 full resupply cycles (10,000 / 100)

**Assessment**: 10,000 is plenty for normal operations.

### Maintenance Drain Analysis

| Supply Income | Depots Sustainable |
|---------------|-------------------|
| 0 (isolated) | 0 (will drain) |
| 200/min | 4 depots |
| 500/min | 10 depots |

**User's "100 every couple minutes"** = 50 supply/min per depot

If player has 3 Water Tanks + 2 Fuel Points = 250 supply/min just for depot maintenance.

**Risk**: May strain supply chain if player over-builds depots. **This is good** - it creates meaningful choices.

## Vehicle Fuel Balance

### Proposed Values

| Vehicle Type | Max Fuel | Depletion Rate | Range |
|--------------|----------|----------------|-------|
| Jeep | 100 | 0.1/sec idle, 0.3/sec moving | ~17 min driving |
| APC | 150 | 0.15/sec idle, 0.5/sec moving | ~15 min driving |
| Tank | 200 | 0.2/sec idle, 0.8/sec moving | ~12 min driving |

**Formula**: `fuel_depletion = base_rate * (1.0 if idle else speed_multiplier)`

Heavier vehicles burn more fuel but have larger tanks.

## Edge Cases to Test

1. **Zero Supply** - Depot runs dry, units stranded
2. **Depot Destroyed** - Nearby units immediately at risk
3. **Mass Resupply** - 20 squads at one depot (queue system?)
4. **Long Patrol** - Squad 500m from firebase, water hits zero

## Recommended Test Scenarios

1. Infantry patrol circuit: firebase → 1km out → return (water budget)
2. Vehicle convoy: firebase A → firebase B (fuel budget)
3. Siege scenario: firebase cut off from supply, depots drain
4. Combat stress: depot under attack while units resupplying
