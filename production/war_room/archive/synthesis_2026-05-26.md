# War Room Synthesis: Clearing Test Scene Issues

**Session:** 2026-05-26
**Status:** DECREE ISSUED

---

## ROOT CAUSES IDENTIFIED

### 1. CRITICAL: Scene Freeze - Missing Await
**File:** test_scenes/clearing_test.gd:282
**Cause:** Synchronous terrain generation blocks main thread

```gdscript
# BUG: Missing await causes entire terrain to generate in one frame
local_terrain.generate_terrain(42)

# FIX: Add await for async generation
await local_terrain.generate_terrain(42)
```

### 2. HIGH: Billboard System Loading Unnecessarily
**File:** test_scenes/clearing_test.gd:441-463
**Cause:** BillboardVegetation instantiated even though disabled

The node's _ready() still:
- Loads 13 texture files
- Creates billboard meshes
- Allocates MultiMesh instances

**FIX:** Remove billboard instantiation entirely from test scene.

### 3. MEDIUM: TOC Influence Radius Not Visible
**Cause:** No visualization of 150m firebase building zone

**FIX:** Add influence radius circle to ghost during HQ building placement.

### 4. LOW: MG Nest Rotation UX
**Cause:** Two-step rotation (right-click anchor, then aim) is not intuitive

**FIX:** Add hint text explaining rotation mechanic.

---

## THE DECREE

### Immediate Actions (Fixes 1 & 2)

Fix 1: Add await to clearing_test.gd terrain generation
Fix 2: Remove BillboardVegetation instantiation from clearing_test.gd

### Follow-up Actions (Fixes 3 & 4)

Fix 3: TOC influence radius visualization - investigate existing code first
Fix 4: Rotation hint - low priority, document the UX

---

## TRADEOFFS NAMED

- Removing billboards from test scene reduces visual fidelity at distance
- Async terrain adds loading screen time (but prevents freeze)
- Influence radius circle adds visual clutter (but improves UX)

---

## NEXT STEPS

1. Implement Fix 1 and Fix 2 immediately
2. Test scene for stability
3. Investigate TOC circle rendering approach
4. Document MG nest rotation in player guide
