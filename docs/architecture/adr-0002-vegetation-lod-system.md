# ADR-0002: Vegetation LOD System

## Status

Accepted

## Date

2026-05-21

## Last Verified

2026-05-21

## Decision Makers

- Technical Director
- Systems Designer

## Summary

Dense jungle rendering with thousands of trees per chunk causes severe performance degradation at 60 FPS target. This ADR defines a two-tier LOD system using hard swap with hysteresis between 3D tree nodes (near) and MultiMesh billboards (far), coordinated by VegetationLODManager autoload to prevent flickering and maintain visual consistency.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Rendering / Core |
| **Knowledge Risk** | LOW - MultiMesh and instancing are stable APIs in training data |
| **References Consulted** | Godot 4.x MultiMesh documentation, existing terrain chunk system |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Verify MultiMesh transform buffer format unchanged in 4.6 |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (terrain chunks own vegetation) - assumed foundational |
| **Enables** | Terrain clearing visual feedback, firebase LZ visibility |
| **Blocks** | None |
| **Ordering Note** | Must be implemented before large map testing |

## Context

### Problem Statement

The game requires rendering dense jungle with 4,500+ billboards per 256m chunk and dozens of clearable 3D tree nodes within clearing zones. Without LOD management:
- Rendering all trees as 3D models destroys framerate
- Rendering all trees as billboards loses close-up fidelity
- Hard distance thresholds cause visible popping at transition boundaries
- Two independent systems (VegetationManager for 3D, BillboardVegetation for billboards) can conflict

### Current State

Two vegetation systems exist:
1. **BillboardVegetation** (`terrain/vegetation/billboard_vegetation.gd`) - 5-plane cross billboards via MultiMesh, 4,500 per chunk, visible 60m-800m
2. **TreeNodeManager** (`terrain/vegetation/tree_node_manager.gd`) - Individual Node3D trees for clearing operations, spawned within clearing zones

Without coordination, both systems render independently causing overdraw and visual inconsistency.

### Constraints

- **Performance**: Must maintain 60 FPS with 300-500 units + vegetation
- **Visual quality**: No visible popping at LOD transitions
- **Clearability**: 3D trees must be individually removable for clearing operations
- **Memory**: MultiMesh buffer format uses 12 floats per transform (48 bytes)

### Requirements

- Smooth visual transitions between LOD tiers
- 3D trees visible and interactive within ~70m of camera
- Billboards take over at medium distance (60m+)
- Trees cleared via ClearingSystem must disappear from both systems
- 10Hz update rate to minimize CPU overhead

## Decision

Implement a **hard swap with hysteresis** LOD system using a coordinating autoload singleton.

### Distance Thresholds

| LOD Tier | Show Distance | Hide Distance | Hysteresis Buffer |
|----------|---------------|---------------|-------------------|
| **3D Trees** | < 70m | > 90m | 20m |
| **Billboards** | > 60m | < 50m | 10m |

### Overlap Zone

Between 60m and 90m, both 3D trees and billboards can be simultaneously visible. This overlap:
- Prevents pop-in during fast camera movement
- Allows gradual visual blending
- Costs additional draw calls in this zone (acceptable trade-off)

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    VegetationLODManager                         │
│                    (Autoload Singleton)                         │
├─────────────────────────────────────────────────────────────────┤
│  - _camera: Camera3D                                            │
│  - _tracked_trees: Array[Node3D]                                │
│  - _tree_visibility: Dictionary  # Node3D -> bool               │
│  - UPDATE_INTERVAL: 0.1 (10Hz)                                  │
├─────────────────────────────────────────────────────────────────┤
│  + register_tree(tree: Node3D)                                  │
│  + unregister_tree(tree: Node3D)                                │
│  + register_tree_container(container: Node3D)                   │
│  + set_camera(camera: Camera3D)                                 │
└───────────────────────┬─────────────────────────────────────────┘
                        │ coordinates
         ┌──────────────┴──────────────┐
         │                             │
         ▼                             ▼
┌─────────────────────┐    ┌───────────────────────────┐
│   TreeNodeManager   │    │   BillboardVegetation     │
│   (3D Trees)        │    │   (MultiMesh Billboards)  │
├─────────────────────┤    ├───────────────────────────┤
│ Near: <70m visible  │    │ Far: >60m visible         │
│ Far:  >90m hidden   │    │ Near: <50m hidden         │
│ Clearable nodes     │    │ 5-plane cross quads       │
│ ~50 trees/zone      │    │ ~4500 per chunk           │
└─────────────────────┘    └───────────────────────────┘
         │                             │
         └──────────────┬──────────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │   ClearingSystem    │
              │   (TerrainGrid)     │
              ├─────────────────────┤
              │ Marking cleared     │
              │ areas removes both  │
              │ 3D trees & billboards│
              └─────────────────────┘
```

### Key Interfaces

```gdscript
# VegetationLODManager (autoload)
class_name VegetationLODManager extends Node

const TREE_SHOW_DISTANCE := 70.0   # 3D trees visible below this
const TREE_HIDE_DISTANCE := 90.0   # 3D trees hide above this (20m buffer)
const BILLBOARD_SHOW_DISTANCE := 60.0  # Billboards show above this
const BILLBOARD_HIDE_DISTANCE := 50.0  # Billboards hide below this
const UPDATE_INTERVAL := 0.1  # 10Hz

func register_tree(tree: Node3D) -> void
func unregister_tree(tree: Node3D) -> void
func register_tree_container(container: Node3D) -> void
func set_camera(camera: Camera3D) -> void
func get_stats() -> Dictionary  # For debugging

# Hysteresis logic in _update_lod()
func _update_lod() -> void:
    for tree in _tracked_trees:
        var dist := cam_pos.distance_to(tree.global_position)
        var currently_visible: bool = _tree_visibility.get(tree, true)

        if currently_visible:
            # Stay visible until exceeding hide distance
            should_show = dist < TREE_HIDE_DISTANCE
        else:
            # Become visible when below show distance
            should_show = dist < TREE_SHOW_DISTANCE
```

```gdscript
# BillboardVegetation visibility check
func _update_billboard_visibility() -> void:
    for coord in _chunk_billboards:
        var dist := cam_pos.distance_to(chunk_center)
        # Show in mid-distance range only
        container.visible = dist >= BILLBOARD_RANGE_MIN and dist < BILLBOARD_RANGE_MAX
```

### Implementation Guidelines

1. **VegetationLODManager is authoritative** for 3D tree visibility
2. **BillboardVegetation manages itself** but respects overlapping ranges
3. **TreeNodeManager registers trees** with VegetationLODManager on spawn
4. **ClearingSystem checks** affect both systems via TerrainGrid clearing_stage
5. **10Hz update rate** shared between both systems to stay synchronized

## Alternatives Considered

### Alternative 1: Continuous Alpha Fade

- **Description**: Fade tree alpha from 1.0 to 0.0 as distance increases
- **Pros**: Smoothest visual transition
- **Cons**: Requires shader modification, transparent sorting issues, performance cost
- **Estimated Effort**: 2x chosen approach
- **Rejection Reason**: Transparent sorting with thousands of trees is prohibitively expensive

### Alternative 2: Single LOD System with Impostors

- **Description**: Replace 3D trees with camera-facing impostor billboards at distance
- **Pros**: Single unified system
- **Cons**: Requires pre-baked impostor textures per tree type, less flexibility for clearing
- **Estimated Effort**: 1.5x chosen approach
- **Rejection Reason**: Clearing system needs actual Node3D trees for gameplay interaction

### Alternative 3: Visibility Range on Nodes

- **Description**: Use Godot's built-in visibility_range_begin/end on each tree
- **Pros**: Engine-managed, zero custom code
- **Cons**: No hysteresis built-in, would still pop; cannot coordinate across systems
- **Estimated Effort**: 0.5x chosen approach
- **Rejection Reason**: Built-in visibility ranges cause popping without hysteresis

## Consequences

### Positive

- **No flickering at thresholds** due to hysteresis buffer (20m for trees, 10m for billboards)
- **Smooth visual transitions** via overlap zone (60-90m)
- **Performance maintained** with distant billboards using efficient MultiMesh
- **Clearable trees preserved** as Node3D for gameplay interaction
- **10Hz update rate** reduces CPU overhead while remaining responsive
- **Clean separation** between near-field gameplay (3D) and far-field visuals (billboards)

### Negative

- **Overlap zone uses more draw calls** when camera is 60-90m from vegetation
- **Requires coordination** between VegetationLODManager, TreeNodeManager, and BillboardVegetation
- **Billboard quality affects visual consistency** - must match 3D tree silhouettes
- **Two render paths** means two places to fix bugs

### Neutral

- System complexity matches existing terrain chunk streaming pattern
- Billboard placement uses same RNG seed pattern as would-be 3D trees for consistency

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Billboard/3D mismatch in overlap zone | Medium | Low | Use same placement RNG seeds, match scale factors |
| Performance regression if hysteresis tuning wrong | Low | Medium | Expose constants as tuning knobs, profile on target hardware |
| Clearing desync between systems | Medium | Medium | ClearingSystem clearing_stage check in both systems |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|----------------|--------|
| Draw calls (max visible vegetation) | 4500+ | <500 (3D) + batched MultiMesh | 1000 |
| Frame time (vegetation) | 8ms+ | <2ms | 3ms |
| Memory (per chunk) | N/A | ~200KB (MultiMesh buffers) | 512KB |
| LOD update CPU | N/A | <0.1ms (10Hz amortized) | 0.5ms |

## Migration Plan

1. VegetationLODManager already exists at `terrain/vegetation/vegetation_lod_manager.gd`
2. TreeNodeManager already registers trees with LOD manager
3. BillboardVegetation already manages its own visibility
4. **No migration required** - systems are already implemented per this design

**Rollback plan**: Set `VegetationLODManager._enabled = false` to show all trees, disable billboard visibility in BillboardVegetation

## Validation Criteria

- [ ] Camera at 50m shows only 3D trees, no billboards
- [ ] Camera at 75m shows both 3D trees and billboards (overlap zone)
- [ ] Camera at 100m shows only billboards, 3D trees hidden
- [ ] Moving camera back and forth across thresholds produces no visible pop
- [ ] Cleared terrain shows no vegetation in either system
- [ ] 60 FPS maintained with full jungle chunk visible
- [ ] `VegetationLODManager.get_stats()` reports expected visible/hidden counts

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|--------------|--------|-------------|---------------------------|
| `design/gdd/terrain-clearing.md` | Terrain Clearing | "Vegetation LOD respects clearing state" (Section 8 - Acceptance Criteria) | Both systems check ClearingSystem.clearing_stage, skip vegetation in CLEARED/FORTIFIED areas |
| `design/gdd/game-concept.md` | Core Vision | Pillar 1: "Carve the Map - battlespace is opaque until you make it legible" | Dense billboard vegetation renders opaque jungle at distance; 3D trees provide interactive clearing targets |
| `design/gdd/terrain-clearing.md` | Vegetation & Cover | "Clearing affects more than just pathability" (Section 3.6) | 3D trees removed during clearing provide visual feedback; billboards regenerate based on terrain state |

## Related

- `terrain/vegetation/vegetation_lod_manager.gd` - VegetationLODManager implementation
- `terrain/vegetation/billboard_vegetation.gd` - Billboard system with MultiMesh
- `terrain/vegetation/tree_node_manager.gd` - 3D tree spawning for clearing zones
- `terrain/systems/clearing_system.gd` - Terrain clearing state management
- ADR-0003: Spatial Hash Grid - may be used for tree position queries in future optimization
- ADR-0004: Signal Bus Pattern - TreeNodeManager uses signals for tree registration
