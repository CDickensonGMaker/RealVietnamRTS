# Devil's Advocate Analysis: Depot Resource System

## Problems I See

### 1. Breaking Change: Firebase Auto-Resupply

**Current behavior**: Squad within firebase radius gets free water regen.
**New behavior**: Squad must be near Water Tank depot specifically.

**Impact**:
- Existing test scenes break
- Players who built firebases without Water Tanks lose infantry sustainability
- Must communicate this change clearly in UI

**Mitigation**: Add a basic water source to TOC building? Or require Water Tank for all firebase operations?

### 2. Vehicle Fuel - Scope Creep Risk

User said: "maybe we do need to add fuel as a trackable supply chain"

The word "maybe" signals uncertainty. We could:
- **Option A**: Implement full fuel system now
- **Option B**: Only implement water depot, defer fuel
- **Option C**: Implement both but make fuel optional (game setting)

**My recommendation**: Start with water only. Fuel adds:
- New building type
- Vehicle code changes
- More balance testing
- More UI elements

That's 2x the scope. Do water first, prove it works, then fuel.

### 3. Maintenance Drain - Death Spiral

**Scenario**:
1. Player loses supply convoy
2. Global supply hits zero
3. All depots fail maintenance
4. Infantry dehydrate, vehicles immobilize
5. Player can't recover because units can't move to capture more supply

**Mitigation options**:
- Emergency reserve: First depot maintenance is free
- Graceful degradation: Depot works at 50% efficiency when broke
- Grace period: 1-2 minutes warning before shutdown

### 4. Depot Destruction - Cascade Failure

If Water Tank is destroyed mid-battle:
- 40+ infantry suddenly have no water source
- They're in combat, can't retreat
- Dehydration timer starts ticking
- Squad becomes ineffective before they can build replacement

**This might be intentional** - attacking supply is valid strategy.

But test: Is it fun to lose because your depot got sniped?

### 5. Overlapping Depot Radii

What if two Water Tanks are within 40m of each other?
- Do units drain from both? (double speed?)
- Do units drain from nearest? (one is wasted)
- Do units drain from fullest? (smart but complex)

**Need rule**: Units always resupply from nearest depot only.

### 6. Depot Queue System?

**Scenario**: 10 squads all at 0% water, one depot.

At 5 units/sec refill rate, fully resupplying 10 squads (1000 water total) takes 200 seconds = 3+ minutes.

Is that okay? Or do we need:
- Higher refill rate for multiple units
- Queue priority (more critical units first)
- Parallel refill (depot serves N units at once, splitting rate)

### 7. UI Complexity

Current HUD shows: supply, selected unit info
New HUD needs: depot reservoir, unit water, unit fuel, warnings

**Risk**: Information overload. RTS players manage armies, not resource bars.

**Mitigation**: Hide details unless relevant (unit selected, depot selected, warning state).

## Questions for the Council

1. Do we implement water only, or water + fuel together?
2. What happens when maintenance fails - hard shutdown or graceful degradation?
3. Should TOC provide emergency water (fallback)?
4. Multiple units at one depot - parallel refill or sequential?
5. Is depot sniping intended counterplay or frustrating?
