# War Room Briefing: Linear Placement Orientation Bug

**Date**: 2026-05-26
**Severity**: HIGH - Core building mechanic broken
**Pillar Affected**: Network of Firebases (Pillar 2)

---

## The Problem

Sandbag walls and barbed wire placed via linear (paint) placement are oriented incorrectly:
- Models should span ALONG the painted line (Company of Heroes style)
- Currently models are oriented at seemingly random angles
- Both preview rectangles AND final placed models are wrong
- Bug is most visible when painting North/South (up/down)

---

## Root Cause Analysis

### The Critical Bug: Double-Application of model_offset

**Found the smoking gun at two locations:**

#### Location 1: `placement_controller.gd:396`
```gdscript
var model_offset := deg_to_rad(_current_building_data.model_rotation_y)
_linear_rotation_y = atan2(direction.x, direction.z) - model_offset
```
The placement controller SUBTRACTS model_offset from the direction angle.

#### Location 2: `construction_manager.gd:430-431`
```gdscript
var model_offset: float = deg_to_rad(data.model_rotation_y) if data else 0.0
building.rotation.y = rotation_y + model_offset
```
The construction manager ADDS model_offset back.

### The Math
```
Job rotation = atan2(dir.x, dir.z) - model_offset
Building rotation = job_rotation + model_offset
Building rotation = atan2(dir.x, dir.z) - model_offset + model_offset
Building rotation = atan2(dir.x, dir.z)  // model_offset cancels out!
```

**The model correction is being applied twice (subtract then add), completely canceling out!**

### Preview Bug

The preview has a similar issue:
```gdscript
// blueprint_ghost.gd:501
marker.rotation.y = _segment_rotation + _model_rotation_offset
```

Where `_segment_rotation = _linear_rotation_y` (which already had model_offset subtracted).

Result: Preview = `atan2(dir.x, dir.z) - model_offset + model_offset = atan2(dir.x, dir.z)`

Both preview and final model get the raw direction angle with no model correction.

---

## Why This Matters

### Sandbag Example
- Sandbag model has length along X axis (at rotation.y = 0)
- `model_rotation_y = 90°` should rotate it to align with paint direction
- But correction cancels out, so sandbag stays at raw direction angle
- When painting East: model length points perpendicular to drag instead of along it

### CoH Reference Behavior
In Company of Heroes, when you paint a wall from point A to point B:
- The wall's LENGTH spans from A to B
- Wall segments are arranged along the line
- The wall COVERS the line, not crosses it

---

## Files Involved

| File | Line | Issue |
|------|------|-------|
| `placement_controller.gd` | 396 | Subtracts model_offset |
| `construction_manager.gd` | 431 | Adds model_offset back |
| `blueprint_ghost.gd` | 501 | Adds model_offset to preview |
| `building_data.gd` | 340, 360 | Defines model_rotation_y values |

---

## Proposed Fix Options

### Option A: Remove from placement_controller
- Change line 396 to: `_linear_rotation_y = atan2(direction.x, direction.z)`
- Let construction_manager handle all model rotation
- Preview would need: `marker.rotation.y = _segment_rotation + _model_rotation_offset` (keep as-is)

### Option B: Remove from construction_manager
- Change line 431 to: `building.rotation.y = rotation_y`
- placement_controller provides fully-corrected rotation
- Preview would need: `marker.rotation.y = _segment_rotation` (remove offset addition)

### Option C: Fix both locations properly
- placement_controller: Store raw direction in job, not corrected
- construction_manager: Apply correction once
- blueprint_ghost: Apply correction for preview

---

## Impact Assessment

- **Firebase construction**: Broken - walls don't form defensive perimeters
- **Cover mechanics**: Potentially broken - soldiers may not get cover from misaligned walls
- **Player experience**: Confusing - preview doesn't match placed structures
- **Pillar 2 violation**: Can't build proper firebase networks with misaligned defenses

---

## Test Cases After Fix

1. Paint East (+X): Wall length should span East-West
2. Paint North (-Z): Wall length should span North-South
3. Paint diagonal: Wall length should follow diagonal
4. Preview should match final placement exactly
5. All linear building types: SANDBAG_LIGHT, SANDBAG_HEAVY, WIRE_OBSTACLE, TRIPLE_CONCERTINA
