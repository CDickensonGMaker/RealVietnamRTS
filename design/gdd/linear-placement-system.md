# Linear Placement System Design Document

> **Status**: `[DRAFT]`
> **Last Updated**: 2026-05-22
> **Source Documents**: GAME_BIBLE.md Section 3 (Pillar 2), construction-system.md, coh_mow_construction.md
> **Pillar**: 2 (Network of Firebases) - "Paint/drag perimeter tools"
> **Reference Games**: Company of Heroes 3, Men of War 2

---

## 1. Overview

The Linear Placement System enables Company of Heroes-style click-and-drag placement for linear defensive structures: wire obstacles, trenches, sandbag walls, and foxhole lines. Players click to set a start point, drag to extend the line, and release to confirm placement. The preview updates in real-time showing cost, segment count, and validity.

This replaces the current segment-by-segment approach in PlacementController with a true continuous-drag experience that matches CoH3's wire/sandbag placement feel.

---

## 2. Player Fantasy

You're an engineer commander designing your firebase perimeter. Click on the northwest corner of your position, drag a sweeping arc of concertina wire around the approach, see the cost update in real-time, and release to have your engineers start working. No clicking individual segments. No micro-managing placement. One fluid gesture defines your defensive line.

---

## 3. Current System Analysis

### 3.1 Existing Files

| File | Purpose | LOC | Assessment |
|------|---------|-----|------------|
| `firebase_system/placement_controller.gd` | Main placement coordinator | 503 | Has LINEAR_START/LINEAR_DRAGGING states but segment-based |
| `battle_system/ui/blueprint_ghost.gd` | Visual preview (LINE type) | 667 | Good foundation, supports LINE ghost type |
| `firebase_system/building_data.gd` | Building definitions | 1200+ | Has `is_linear_placement` flag |
| `firebase_system/nodes/wire_obstacle_node.gd` | Wire obstacle entity | 449 | Individual segment, not continuous |
| `firebase_system/nodes/trench_node.gd` | Trench entity | 379 | Individual segment, path-based |
| `fortification_system/trench.gd` | Trench path manager | 174 | Slot-based occupancy, takes path points |
| `firebase_system/job_system/unified_job.gd` | Job data structure | 600+ | Has DIG_TRENCH, LAY_WIRE, BUILD_ROAD types |
| `firebase_system/job_system/job_system.gd` | Job creation/management | 1200+ | Creates jobs for linear structures |

### 3.2 Current PlacementController Flow

```
State: IDLE
   |
   v [start_placement(wire_type)]
State: LINEAR_START  -- Click --> State: LINEAR_DRAGGING
   |                                       |
   | Ghost follows cursor                  | _calculate_linear_segments() every frame
   | _validate_current_position()          | Ghost shows line preview
   |                                       | _validate_linear_segments()
   v [Click again]                         v [Click to commit]
                           _commit_linear_placement()
                           Creates N separate build jobs
                           Back to IDLE
```

### 3.3 Current Limitations

1. **Segment-Based, Not Continuous**: `_calculate_linear_segments()` breaks the line into fixed-length chunks
2. **No Real-Time Cost Feedback**: Player doesn't see total cost until after placement
3. **No Length/Angle Display**: No visual indication of total length being placed
4. **Fixed Segment Length**: Uses `_current_building_data.footprint_size.x` as segment length
5. **No Curve Support**: Only straight lines between start and end
6. **Ghost Switches Type**: Creates new ghost when transitioning from START to DRAGGING
7. **No Snap/Grid Options**: Free-form only, no angle snapping

### 3.4 BlueprintGhost LINE Support

The `BlueprintGhost` class already supports LINE type:
- `create_line(width)` factory method
- `set_line_points(PackedVector3Array)` to update path
- `_create_line_fill()`, `_create_line_outline()`, `_create_line_grid()` mesh builders
- Handles multi-point paths with proper edge normals

---

## 4. Proposed Design: Company of Heroes-Style Drag Placement

### 4.1 Reference: Company of Heroes 3 Wire Placement

In CoH3:
1. **Select Build**: Click wire icon, enter placement mode
2. **Click Start**: First click sets anchor point
3. **Drag**: Mouse movement extends wire from anchor, preview shows length
4. **Real-Time Preview**: Wire preview bends with mouse, shows as green (valid) or red (blocked)
5. **Cost Display**: UI shows supply cost updating as length changes
6. **Release/Click End**: Second click confirms, engineers begin construction
7. **Continuous Result**: Wire is one continuous obstacle, not discrete segments

### 4.2 Key Behaviors to Implement

| Behavior | CoH3 Reference | Implementation |
|----------|----------------|----------------|
| **Anchor on Click** | First click sets start | Store `_drag_start_pos` on mouse_down |
| **Live Preview** | Wire follows cursor | Update ghost every frame with `[start, cursor]` |
| **Length Calculation** | Per-meter cost | `length * cost_per_meter` |
| **Angle Snapping** | Hold Shift for 45 deg | Optional snap to 45/90 degree angles |
| **Terrain Following** | Wire conforms to ground | Sample terrain height along path |
| **Validity Check** | Red = blocked | Check for obstacles, slope, cleared terrain |
| **Release to Confirm** | Second click confirms | Create single linear job or segmented jobs |
| **Cancel on RMB** | Right-click cancels | Return to IDLE state |

### 4.3 State Machine Enhancement

```
State: IDLE
   |
   v [start_placement(linear_type)]
State: LINEAR_PREVIEW  -- Shows single-segment ghost at cursor
   |
   v [mouse_down (LMB)]
State: LINEAR_DRAGGING -- Anchor set, line extends
   |                     Ghost updates: [anchor, cursor]
   |                     Cost updates in real-time
   |                     Validation per-frame
   v [mouse_up (LMB)]
_commit_drag_placement()
   |
   v [success]
State: IDLE (or continue placing if shift held)
```

### 4.4 New Properties for Linear Building Data

```gdscript
# In BuildingData
@export var cost_per_meter: float = 0.0      # Cost scales with length (0 = fixed cost)
@export var min_length: float = 2.0           # Minimum drag distance
@export var max_length: float = 50.0          # Maximum single placement
@export var supports_curves: bool = false     # Future: Bezier curves
@export var angle_snap_degrees: float = 0.0   # 0 = free, 45 = 45-degree snap
```

---

## 5. Detailed Rules

### 5.1 Placement Mode Entry

When player selects a linear structure from the build menu:
1. Check: Player has engineer selected OR is in firebase auto-build radius
2. Check: Sufficient supply for minimum length
3. Enter `LINEAR_PREVIEW` state
4. Show ghost at cursor position (single segment preview)
5. Show cursor hint: "Click and drag to place"

### 5.2 Drag Start (Mouse Down)

On left mouse button press in LINEAR_PREVIEW state:
1. Record `_drag_start_pos = cursor_world_position`
2. Record `_drag_start_time = Time.get_ticks_msec()`
3. Transition to `LINEAR_DRAGGING` state
4. Create line ghost with points `[start, start]`

### 5.3 Drag Update (Every Frame)

In LINEAR_DRAGGING state, every frame:
1. Get current cursor world position
2. Apply angle snapping if shift held
3. Clamp length to `[min_length, max_length]`
4. Sample terrain heights along path
5. Update ghost: `set_line_points([start, end])`
6. Calculate cost: `base_cost + (length * cost_per_meter)`
7. Validate placement (terrain state, obstacles, slope)
8. Update HUD: length, cost, validity

### 5.4 Placement Validation

A linear placement is valid if:
- [ ] Start point is on cleared terrain (or partially cleared for wire)
- [ ] End point is on cleared terrain
- [ ] Path does not cross water
- [ ] Path does not cross enemy structures
- [ ] Slope along path < 45 degrees
- [ ] Total cost <= available supply
- [ ] Length >= min_length

### 5.5 Drag End (Mouse Up)

On left mouse button release in LINEAR_DRAGGING state:
1. If length < min_length: cancel, show warning
2. If invalid: cancel, show error message
3. If valid: create job(s) for construction
4. Deduct supply cost
5. If shift held: remain in LINEAR_PREVIEW for chained placement
6. Else: return to IDLE

### 5.6 Cancellation

On right-click or Escape:
1. Destroy ghost
2. Return to IDLE
3. No supply deducted

---

## 6. Formulas

### 6.1 Length Calculation

```gdscript
func calculate_drag_length(start: Vector3, end: Vector3) -> float:
    # Horizontal distance only (ignore height for cost)
    var horizontal := Vector3(end.x - start.x, 0, end.z - start.z)
    return horizontal.length()
```

### 6.2 Cost Calculation

```gdscript
func calculate_linear_cost(building_data: BuildingData, length: float) -> int:
    if building_data.cost_per_meter > 0:
        return int(ceil(building_data.supply_cost + length * building_data.cost_per_meter))
    else:
        # Fixed cost regardless of length (e.g., single foxhole)
        return building_data.supply_cost
```

**Example Values:**
| Structure | Base Cost | Per-Meter | 10m Total | 30m Total |
|-----------|-----------|-----------|-----------|-----------|
| Wire Obstacle | 5 | 0.5 | 10 | 20 |
| Triple Concertina | 8 | 0.8 | 16 | 32 |
| Sandbag Wall | 3 | 0.4 | 7 | 15 |
| Trench | 0 | 1.0 | 10 | 30 |

### 6.3 Angle Snapping

```gdscript
const SNAP_ANGLES: PackedFloat64Array = [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]

func snap_to_angle(start: Vector3, end: Vector3) -> Vector3:
    var dir := (end - start)
    dir.y = 0
    var length := dir.length()
    if length < 0.1:
        return end

    var current_angle := rad_to_deg(atan2(dir.z, dir.x))
    var best_snap := 0.0
    var best_diff := 360.0

    for snap in SNAP_ANGLES:
        var diff := absf(angle_difference(current_angle, snap))
        if diff < best_diff:
            best_diff = diff
            best_snap = snap

    var snapped_dir := Vector3(
        cos(deg_to_rad(best_snap)),
        0,
        sin(deg_to_rad(best_snap))
    ) * length

    return start + snapped_dir
```

### 6.4 Terrain Height Sampling

```gdscript
func sample_path_heights(start: Vector3, end: Vector3, sample_count: int = 10) -> PackedVector3Array:
    var points: PackedVector3Array = []
    var terrain: Node = get_node_or_null("/root/TerrainIntegration")

    for i in range(sample_count + 1):
        var t := float(i) / float(sample_count)
        var pos := start.lerp(end, t)
        if terrain and terrain.has_method("get_height_at"):
            pos.y = terrain.get_height_at(pos)
        points.append(pos)

    return points
```

---

## 7. Edge Cases

### 7.1 Very Short Drags (< min_length)

- **What happens**: Placement is cancelled
- **Feedback**: Toast message "Wire too short (minimum 2m)"
- **No supply deducted**

### 7.2 Maximum Length Exceeded

- **What happens**: Line is clamped to max_length
- **Feedback**: Ghost endpoint stops at max distance, UI shows "Max length reached"
- **Reason**: Prevents single massive placements that would take forever to build

### 7.3 Drag Crosses Invalid Terrain

- **What happens**: Ghost turns red, segments over invalid terrain highlighted
- **On release**: Only valid portion is placed (if continuous from start)
- **Alternative**: Entire placement rejected with specific error

### 7.4 Insufficient Supply Mid-Drag

- **What happens**: Ghost changes color at the point where supply runs out
- **Feedback**: UI shows "Insufficient supply" beyond X meters
- **On release**: Placement limited to affordable length

### 7.5 Shift-Chaining Multiple Lines

- **What happens**: After first line placed, new drag starts from old endpoint
- **End point becomes start point** for next line
- **Creates connected defensive perimeter**

### 7.6 Drag Start in Invalid Location

- **What happens**: Drag is rejected, cannot anchor on invalid terrain
- **Feedback**: Cursor shows "Cannot place here"
- **State remains**: LINEAR_PREVIEW (no transition to DRAGGING)

### 7.7 Mouse Leaves Game Window While Dragging

- **What happens**: Drag continues with last known position
- **When mouse returns**: Resume tracking
- **Cancel on focus lost**: Optional behavior

---

## 8. Dependencies

| System | Dependency Type | Integration Point |
|--------|-----------------|-------------------|
| **PlacementController** | Modify | Add LINEAR_DRAGGING state, mouse up/down handlers |
| **BlueprintGhost** | Extend | Already supports LINE type, add cost display |
| **BuildingData** | Extend | Add cost_per_meter, min/max length fields |
| **JobSystem** | Use | create_linear_job() for path-based construction |
| **TerrainIntegration** | Use | Height sampling, clearance checking |
| **SupplyManager** | Use | Cost checking and deduction |
| **BattleHUD** | Extend | Show length, cost during drag |
| **InputHandling** | Modify | mouse_up event triggers commit |

---

## 9. Tuning Knobs

| Parameter | Default | Range | Effect |
|-----------|---------|-------|--------|
| `min_drag_length` | 2.0m | 1.0-5.0 | Minimum to prevent accidental taps |
| `max_drag_length` | 50.0m | 20.0-100.0 | Maximum single placement |
| `angle_snap_tolerance` | 15.0 deg | 5.0-30.0 | How close to snap angle before snapping |
| `height_sample_count` | 10 | 5-20 | Points sampled along path for terrain |
| `drag_update_rate` | 60 Hz | 30-120 | Ghost update frequency |
| `cost_update_debounce` | 100ms | 50-200ms | Debounce for HUD cost updates |

---

## 10. Implementation Plan

### Phase 1: PlacementController State Machine (2-3 hours)

**File: `firebase_system/placement_controller.gd`**

1. Add new state `LINEAR_DRAGGING_ACTIVE` (distinguish from current segment approach)
2. Track `_drag_is_active: bool` flag
3. Handle `InputEventMouseButton` for button_up, not just button_down
4. Add `_handle_mouse_release()` method
5. Remove segment calculation from drag (continuous line instead)

```gdscript
# New state handling
func _handle_left_click(position: Vector3) -> bool:
    match state:
        State.LINEAR_START:
            _begin_drag(position)
            return true
        State.LINEAR_DRAGGING:
            # In new design, commit happens on mouse_up, not click
            return false
    return false

func _handle_mouse_release(position: Vector3) -> bool:
    if state == State.LINEAR_DRAGGING:
        return _commit_drag_placement()
    return false
```

### Phase 2: Continuous Ghost Update (1-2 hours)

**File: `battle_system/ui/blueprint_ghost.gd`**

1. Add method `update_line_continuous(start: Vector3, end: Vector3)`
2. Terrain-conform the line path
3. Add cost display element (Label3D or billboard)
4. Add length display

### Phase 3: BuildingData Extensions (1 hour)

**File: `firebase_system/building_data.gd`**

1. Add exports: `cost_per_meter`, `min_length`, `max_length`, `angle_snap_degrees`
2. Update `SANDBAG_LIGHT`, `WIRE_OBSTACLE`, `TRIPLE_CONCERTINA` with values
3. Add validation methods

### Phase 4: Input Handling Refinement (1 hour)

**File: `firebase_system/placement_controller.gd`**

1. Modify `handle_input()` to detect mouse release events
2. Add shift-to-chain functionality
3. Add shift-to-snap angle functionality

### Phase 5: HUD Integration (1-2 hours)

**File: `battle_system/ui/battle_hud.gd` or new widget**

1. Create `LinearPlacementHUD` widget showing:
   - Current length (meters)
   - Total cost (supply)
   - Validity status
   - Angle (if snapping)
2. Position near cursor during drag

### Phase 6: Job Creation for Linear Structures (2 hours)

**File: `firebase_system/job_system/job_system.gd`**

1. Add `create_linear_job(path: PackedVector3Array, type: Type)` method
2. Linear job stores full path, not just center/size
3. Workers progress along path as they build
4. Visual node extends as construction progresses

---

## 11. File Changes Summary

| File | Change Type | Scope |
|------|-------------|-------|
| `firebase_system/placement_controller.gd` | **MODIFY** | Major - add drag tracking, mouse release handling |
| `battle_system/ui/blueprint_ghost.gd` | **MODIFY** | Minor - add continuous update, cost display |
| `firebase_system/building_data.gd` | **MODIFY** | Minor - add linear placement properties |
| `battle_system/ui/linear_placement_hud.gd` | **NEW** | Small - drag info display widget |
| `firebase_system/job_system/job_system.gd` | **MODIFY** | Minor - linear job path support |

---

## 12. Acceptance Criteria

### Core Functionality
- [ ] Left-click and hold initiates drag from anchor point
- [ ] Drag shows continuous line preview from anchor to cursor
- [ ] Release (mouse up) confirms placement
- [ ] Right-click cancels at any point
- [ ] ESC cancels at any point

### Visual Feedback
- [ ] Ghost line follows terrain height
- [ ] Ghost is green when valid, red when invalid
- [ ] Length displayed in meters during drag
- [ ] Cost displayed and updates as length changes
- [ ] Invalid portions of line highlighted differently

### Cost System
- [ ] Cost calculated as base + (length * per_meter)
- [ ] Insufficient supply prevents placement
- [ ] Supply deducted on successful placement

### Quality of Life
- [ ] Shift+drag snaps to 45-degree angles
- [ ] Shift after placement starts new line from endpoint (chaining)
- [ ] Minimum length requirement prevents accidental taps

### Edge Cases
- [ ] Drag across water marks that section invalid
- [ ] Drag across obstacles marks that section invalid
- [ ] Very short drag shows warning and cancels
- [ ] Maximum length enforced with visual feedback

---

## 13. Test Scenarios

### T1: Basic Wire Placement
1. Select Engineer, click Wire Obstacle
2. Click and hold at position A
3. Drag to position B (20 meters)
4. Release
5. **Expected**: Wire job created, supply deducted, engineers move to build

### T2: Cancel Mid-Drag
1. Select Engineer, click Trench
2. Click and hold at position A
3. Drag 10 meters
4. Press Right-click
5. **Expected**: Ghost disappears, no job created, no supply deducted

### T3: Shift-Chain Placement
1. Select Engineer, click Sandbag Wall
2. Place first wall A->B
3. Hold Shift before releasing
4. Drag from B to C
5. Release
6. **Expected**: Two connected walls, B is shared endpoint

### T4: Insufficient Supply
1. Reduce supply to 5
2. Select Wire Obstacle (base 5 + 0.5/m)
3. Try to drag 20m (would cost 15)
4. **Expected**: Ghost shows affordable length, rest is red

### T5: Snap to Angle
1. Select Wire Obstacle
2. Hold Shift before clicking
3. Drag at ~40 degree angle
4. **Expected**: Line snaps to 45 degrees

---

## Appendix A: CoH3 Wire Placement Frame-by-Frame

Based on gameplay analysis:

1. **Frame 0**: Click Build Wire
2. **Frame 1-60**: Cursor shows wire icon, follows mouse
3. **Frame 61 (Click)**: Anchor appears at click point (small marker)
4. **Frame 62+**: Wire extends from anchor to cursor
5. **During Drag**: Wire bends over terrain, cost number floats near cursor
6. **On Release**: Wire "settles", engineers dispatch
7. **Construction**: Engineers work along wire from one end to other

---

## Appendix B: Existing Code Snippets

### Current _update_linear_dragging (to be replaced)

```gdscript
func _update_linear_dragging() -> void:
    """Update ghost while dragging to extend line"""
    if not is_instance_valid(_ghost) or _linear_start_pos == Vector3.INF:
        return

    # Calculate segments along the line  <-- THIS IS WHAT WE'RE REMOVING
    _calculate_linear_segments(_linear_start_pos, _cursor_world_pos)

    # Update ghost line
    var points: PackedVector3Array = [_linear_start_pos, _cursor_world_pos]
    _ghost.set_line_points(points)

    # Validate all segments and update ghost state
    _validate_linear_segments()
```

### BlueprintGhost LINE creation (already exists)

```gdscript
static func create_line(width: float) -> BlueprintGhost:
    var ghost := BlueprintGhost.new()
    ghost.ghost_type = GhostType.LINE
    ghost.line_width = width
    return ghost
```

---

## Appendix C: Related Bible Entries

**D-102: Engineers auto-build inside zones, manual outside**
> "paint/drag perimeter tools and engineer auto-construction"

**Construction System GDD Section 3.1:**
> "Perimeter Structures (Paint/Drag): Sandbag Wall, Wire Obstacle, Triple Concertina, Foxhole"

**Construction System Acceptance Criteria:**
> "Sandbags can be painted as continuous perimeter"
> "Wire obstacles can be dragged to define defensive lines"

---

*End of Document*
