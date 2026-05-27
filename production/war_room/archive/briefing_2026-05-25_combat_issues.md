# ⛧ THE COUNCIL IS SUMMONED ⛧

## The Mortal's Query
> Eight interconnected issues plague the combat loop and construction systems. Units exhaust ammunition rapidly, tracers are invisible, damage fails to register, workers pathfind poorly to jobs, sandbag placement spawns terrain spikes, segment rotation fails at odd angles, gates remain sealed to friendlies, and an MG nest materializes within the gate itself. The game loop approaches functionality but these demons must be exorcised.

## Victory Shall Be Known By
- ▸ Units sustain combat for realistic engagement durations (1-3 minutes of firefight before resupply needed)
- ▸ Tracer rounds visibly streak through the jungle, revealing fire patterns
- ▸ Damage registers and units die when struck by projectiles
- ▸ Workers navigate to job positions accurately without offset
- ▸ Sandbag placement flattens terrain smoothly without spikes
- ▸ Linear segments rotate to face correct perpendicular direction at all angles
- ▸ Gates detect approaching friendly units and open bidirectionally
- ▸ Test arena HQ structures spawn without overlapping

## The Chains That Bind Us
- ▸ D-101: No AOE-style unit production - ammo must MATTER (Pillar 4)
- ▸ D-102: Engineers auto-build inside zones - pathfinding must work reliably
- ▸ Pillar 3: Physical Supply Chains - supply is spatial, visible, attackable
- ▸ Pillar 5: The War Continues - automation must work without babysitting
- ▸ Performance: 60 FPS with 300-500 units (can't add expensive per-frame checks)

## Those Who Must Be Awakened
- **systems-designer:** Combat math, ammo economy, suppression balance
- **gameplay-programmer:** Projectile systems, hit detection, damage flow
- **ai-programmer:** Pathfinding, worker AI, proximity detection
- **technical-artist:** Tracer visuals, terrain modification, model rotation

## Decrees Already Carved
- D-101: Units cannot be built - reinforcements arrive via supply chain
- D-102: Engineers auto-build in zones, manual outside
- D-103: Bulldozers fast/large clearing, engineers det-cord slower/tactical

## The Context of This Summoning

### Issue 1: Rapid Ammo Depletion
- M16: 20 round magazine, BURST (3 rounds), 7 magazines = 140 total rounds
- Suppression burns 10 rounds/second (SUPPRESS_AMMO_PER_SECOND)
- A 5-second suppression consumes 50 rounds (36% of combat load)
- Auto weapons (M60 at 550 RPM) consume ~9 rounds/second

### Issue 2: Invisible Tracers
- Tracer mesh radius = 0.03m (3 centimeters - barely visible)
- Tracer ratio = 1 in 5 rounds (20%)
- Trail particles may not emit (visibility state may not reset on pool reuse)
- Spawn position uses source.global_position + Vector3(0, 1.0, 0)

### Issue 3: Damage Not Registering
- Projectile Area3D collision_mask = layers 2, 4, 8 (US, VC, NVA)
- Ammo depleted = no projectile fired = no damage
- If consume_ammo() returns false, fire_weapon() returns false
- Units may run dry before combat even begins visually

### Issue 4: Worker Pathfinding Offset
- Work positions calculated 1m OUTSIDE job bounds (unified_job.gd:228-252)
- Arrival threshold = 3.0m (worker_controller.gd:32)
- Combined offset = 4-6m from actual job center
- Workers may stop at perimeter, not reach actual work area

### Issue 5: Sandbag Terrain Spikes
- terrain_flattening.gd uses lerp modifier without height clamping
- progress * falloff can overshoot on curved terrain
- No safety check prevents terrain going higher than original
- Multi-cell gradients create compound peaks

### Issue 6: Sandbag Rotation
- placement_controller.gd:395 uses atan2(x,z) + PI/2
- Godot forward axis is -Z, not +Z
- Certain angles (west-facing drags) compute wrong rotation
- No angle normalization or sanity check

### Issue 7: Gate Opening
- NO gate opening mechanics exist in codebase
- Gates are static decorative structures only
- No Area3D proximity triggers
- No faction detection or animation

### Issue 8: MG Nest in Gate
- test_arena.gd spawns gate at hq_pos + Vector3(0, 0, -25)
- MG nest spawns at hq_pos + Vector3(0, 0, -28) - only 3m apart
- _spawn_structure() bypasses JobSystem validation entirely
- No group membership = no overlap detection

*Let the deliberation begin.*
