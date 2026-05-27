# ⛧ THE COUNCIL HAS DELIBERATED ⛧

## Summary of Architect Findings

### Systems-Designer (Ammo Economy)
- M16 combat load = 140 rounds (7 x 20-round mags)
- Suppression burns 10 rounds/sec uniformly (regardless of weapon type)
- 14 seconds of suppression = completely dry
- **Root cause**: Flat SUPPRESS_AMMO_PER_SECOND doesn't scale by weapon category
- **Fix**: Scale suppress cost (rifles 2 rps, MGs 6 rps), increase M16 to 30-round mags

### Gameplay-Programmer (Projectiles/Damage)
- Tracer mesh = 0.03m radius (3cm - nearly invisible at 50m+)
- Trail particles = 20 count, 0.3s lifetime, 2-5cm scale
- Tracer ratio uses GLOBAL counter (cross-weapon contamination)
- Pool reuse doesn't reset trail color/scale
- **Damage not registering**: If ammo depleted, `consume_ammo()` returns false → no projectile spawns → no damage
- **Fix**: Increase tracer mesh to 0.08-0.1m, brighter emission, per-weapon tracer counters, pool reset

### AI-Programmer (Pathfinding/Gates)
- Work positions = 1m OUTSIDE job bounds (intentional)
- arrival_threshold = 3.0m (too generous)
- Combined offset = 4m from actual job
- Gate opening = NOT IMPLEMENTED (gates are static)
- MG Nest spawns 3m behind gate (overlap)
- **Fix**: Reduce arrival_threshold to 1.5m, create GateController with Area3D detection, move MG nest

### Technical-Artist (Visuals/Terrain/Rotation)
- Terrain modifier lerps from `current_h` not `original_h`
- Multi-frame modifications compound into spikes
- Sandbag rotation uses `atan2(x,z) + PI/2` - fails for certain quadrants
- West-facing drags compute wrong rotation (0° instead of 90°)
- **Fix**: Clamp terrain modifier to prevent opposite-direction changes, fix rotation math with perpendicular vector

## Points of Agreement
- Tracer mesh size must increase 3-5x for visibility
- Ammo depletion causing silent fire failure needs visual feedback
- Arrival threshold is too loose for precision work
- Gate mechanics need to be implemented from scratch
- Terrain spikes caused by modifier not referencing original heights
- Sandbag rotation math is incorrect for certain drag angles

## ⛧ THE ARBITER'S JUDGMENT ⛧

All eight issues have clear root causes and fixes. No conflicts between architects. Proceeding to decree.
