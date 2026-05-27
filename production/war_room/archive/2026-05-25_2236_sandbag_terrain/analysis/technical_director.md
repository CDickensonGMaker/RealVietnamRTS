# Technical Director Analysis: VegetationManager Synchronous Loading

**Author:** Technical Director
**Date:** 2026-05-25
**Query:** VegetationManager freezes game during chunk loading

---

## Executive Summary

The freeze is caused by `VegetationManager.generate_for_chunk()` executing heavy work synchronously on the main thread for all 144 chunks in a tight loop. The solution requires spreading this work across frames using Godot 4.6's async patterns. I recommend a **hybrid coroutine + time-budgeted approach** that integrates with TerrainManager's existing streaming architecture.

---

## Root Cause Analysis

### The Call Chain

```
TerrainManager.load_all_chunks()           # Line 418-424: Tight loop, no yield
  -> _load_chunk(coord)                    # Line 248-296: Sync call
    -> vegetation_manager.generate_for_chunk()  # Line 265: THE BOTTLENECK
      -> _build_terrain_from_grid()        # O(n^2) bundle iteration
      -> _build_placement_cache()          # 5000 RNG calls per chunk
      -> _materialize_vegetation()         # Transform buffer construction
      -> _materialize_grass()              # More buffer construction
```

### Quantified Impact

For a 3000m map with 256m chunks:
- **144 chunks** (12x12 grid)
- **~800 trees per chunk** average
- **~1200 grass patches per chunk** average
- **5000 RNG calls** per chunk for placement cache
- **12 floats per transform** = ~480KB of transform buffers per chunk

**Total synchronous work per chunk:** ~15-25ms on typical hardware
**Total freeze duration:** 144 chunks x 20ms = **~2.9 seconds**

---

## Godot 4.6 Async Patterns Available

### Option A: Coroutines with await + Callable.call_deferred()

```gdscript
# Pattern: Yield control back to main loop after each chunk
func generate_for_chunk_async(chunk_coord: Vector2i, heightmap: Object, chunk_size: float) -> void:
    clear_chunk_visuals(chunk_coord)
    if _meshes.is_empty():
        return

    _bundles_per_chunk = int(chunk_size / bundle_meters)
    _build_terrain_from_grid(chunk_coord, chunk_size)

    # Yield after heavy work
    await get_tree().process_frame

    if not _chunk_placements.has(chunk_coord):
        _build_placement_cache(chunk_coord, heightmap, chunk_size)
        await get_tree().process_frame

    _materialize_vegetation(chunk_coord, heightmap)
    await get_tree().process_frame

    _materialize_grass(chunk_coord, heightmap)
```

**Pros:**
- Simple to implement
- Preserves execution order
- No threading complexity

**Cons:**
- Still blocks for each sub-operation (up to 8-10ms each)
- Must change all callers to handle async
- No parallelism - 144 sequential awaits

### Option B: WorkerThreadPool (Godot 4.x Threading)

```gdscript
# Pattern: Offload placement cache generation to worker threads
func _build_placement_cache_threaded(chunk_coord: Vector2i, chunk_size: float) -> int:
    var task_id := WorkerThreadPool.add_task(
        _build_placement_cache_work.bind(chunk_coord, chunk_size)
    )
    return task_id

func _build_placement_cache_work(chunk_coord: Vector2i, chunk_size: float) -> void:
    # CRITICAL: Only compute data - NO NODE CREATION
    var placements: Array = []
    # ... RNG and math work ...
    # Store result in thread-safe structure
    _pending_placements_mutex.lock()
    _pending_placements[chunk_coord] = placements
    _pending_placements_mutex.unlock()
```

**Pros:**
- True parallelism for CPU-bound RNG work
- Can process multiple chunks simultaneously

**Cons:**
- Cannot create Nodes or Meshes from worker threads (Godot limitation)
- Requires mutex protection for shared state
- Complex error handling
- Placement cache generation is not the slowest part (materialization is)

### Option C: Time-Budgeted Processing (TerrainManager Pattern)

The existing `TerrainManager._process_rebuild_queue()` demonstrates the correct pattern:

```gdscript
# Pattern: Process work in _process() with time budget
const VEGETATION_BUDGET_MS := 8.0
var _pending_vegetation_chunks: Array[Dictionary] = []

func _process(_delta: float) -> void:
    _process_vegetation_queue()

func _process_vegetation_queue() -> void:
    if _pending_vegetation_chunks.is_empty():
        return

    var start_time := Time.get_ticks_msec()
    while not _pending_vegetation_chunks.is_empty():
        if Time.get_ticks_msec() - start_time > VEGETATION_BUDGET_MS:
            break  # Continue next frame

        var task: Dictionary = _pending_vegetation_chunks.pop_front()
        _process_vegetation_step(task)
```

**Pros:**
- Maintains 60 FPS guarantee (8ms budget leaves headroom)
- No threading complexity
- Integrates with existing TerrainManager architecture
- Predictable memory behavior

**Cons:**
- Total load time increases (spread across many frames)
- Requires state machine for multi-step operations
- Player sees progressive loading (may need visual feedback)

---

## Recommended Architecture: Hybrid Approach

I recommend **Option C (Time-Budgeted) as the foundation** with **selective threading for RNG-heavy work**.

### Phase 1: Time-Budgeted Queue (Immediate Fix)

Split `generate_for_chunk()` into discrete steps that fit within frame budget:

```gdscript
enum VegetationStep {
    TERRAIN_GRID,      # ~2ms - Build terrain type array
    PLACEMENT_CACHE,   # ~8ms - RNG for 5000 candidates (can be threaded)
    MATERIALIZE_TREES, # ~10ms - Build tree MultiMesh buffers
    MATERIALIZE_GRASS, # ~5ms - Build grass MultiMesh buffers
    COMPLETE
}

class VegetationTask:
    var chunk_coord: Vector2i
    var heightmap: Object
    var chunk_size: float
    var step: VegetationStep = VegetationStep.TERRAIN_GRID

var _vegetation_queue: Array[VegetationTask] = []
const STEP_BUDGET_MS := 6.0  # Conservative - leaves 10ms for rendering

func queue_vegetation(coord: Vector2i, heightmap: Object, size: float) -> void:
    var task := VegetationTask.new()
    task.chunk_coord = coord
    task.heightmap = heightmap
    task.chunk_size = size
    _vegetation_queue.append(task)

func _process(_delta: float) -> void:
    _process_vegetation_queue()

func _process_vegetation_queue() -> void:
    if _vegetation_queue.is_empty():
        return

    var start := Time.get_ticks_msec()
    while not _vegetation_queue.is_empty():
        if Time.get_ticks_msec() - start > STEP_BUDGET_MS:
            break

        var task: VegetationTask = _vegetation_queue[0]
        _execute_step(task)

        if task.step == VegetationStep.COMPLETE:
            _vegetation_queue.pop_front()
```

### Phase 2: Priority Queue by Distance

Chunks near camera should load first:

```gdscript
func queue_vegetation_prioritized(coord: Vector2i, heightmap: Object, size: float, camera_pos: Vector3) -> void:
    var task := VegetationTask.new()
    task.chunk_coord = coord
    task.heightmap = heightmap
    task.chunk_size = size

    # Calculate priority (lower = higher priority)
    var chunk_center := Vector3(
        (coord.x + 0.5) * size,
        0,
        (coord.y + 0.5) * size
    )
    task.priority = camera_pos.distance_to(chunk_center)

    # Insert sorted
    var insert_idx := 0
    for i in _vegetation_queue.size():
        if task.priority < _vegetation_queue[i].priority:
            break
        insert_idx = i + 1
    _vegetation_queue.insert(insert_idx, task)
```

### Phase 3: Background Thread for RNG (Optional Optimization)

The placement cache step is pure math - safe for threading:

```gdscript
func _execute_placement_cache_step(task: VegetationTask) -> void:
    if _use_threaded_placement:
        var task_id := WorkerThreadPool.add_task(
            _build_placement_cache_threaded.bind(task.chunk_coord, task.chunk_size)
        )
        task.thread_task_id = task_id
        task.step = VegetationStep.WAIT_PLACEMENT
    else:
        _build_placement_cache(task.chunk_coord, task.heightmap, task.chunk_size)
        task.step = VegetationStep.MATERIALIZE_TREES

func _execute_wait_placement_step(task: VegetationTask) -> void:
    if WorkerThreadPool.is_task_completed(task.thread_task_id):
        WorkerThreadPool.wait_for_task_completion(task.thread_task_id)  # Clears result
        task.step = VegetationStep.MATERIALIZE_TREES
    # Else: stay in WAIT_PLACEMENT, check next frame
```

---

## Integration with TerrainManager

The TerrainManager already has the correct streaming architecture:

```gdscript
# terrain_manager.gd line 23-24
@export var load_distance: int = 3     # Chunks to load around camera
@export var unload_distance: int = 5   # Chunks to unload beyond this
```

**Key Integration Points:**

1. **Decouple terrain mesh from vegetation:**
   - `_load_chunk()` creates terrain mesh immediately (fast - already async via streaming)
   - Vegetation queued separately, loads progressively

2. **Use existing rebuild queue pattern:**
   - TerrainManager already has `_rebuild_queue` and `_process_rebuild_queue()`
   - VegetationManager should mirror this pattern

3. **Signal-based coordination:**
   - Add `vegetation_chunk_ready(coord: Vector2i)` signal
   - Systems that depend on vegetation (LOS, pathfinding) wait for signal

---

## Memory Implications

### Current Memory Profile (per chunk)
| Data Structure | Size | Notes |
|----------------|------|-------|
| `_chunk_terrain` | ~1KB | PackedByteArray, bundles per chunk |
| `_chunk_placements` | ~400KB | 5000 Dictionaries with floats |
| `_chunk_instances` | ~60KB | MultiMesh transform buffers |
| `_chunk_grass` | ~36KB | MultiMesh transform buffers |

### Deferred Loading Implications

With progressive loading:
- Peak memory unchanged (all chunks eventually loaded)
- Memory allocation spreads over time (less GC pressure)
- Can add **memory budget** to limit loaded vegetation chunks

### Optional: LRU Vegetation Cache

For very large maps, add vegetation unloading:

```gdscript
const MAX_VEGETATION_CHUNKS := 64  # ~32MB vegetation data

func _ensure_vegetation_budget() -> void:
    while _chunk_instances.size() > MAX_VEGETATION_CHUNKS:
        var oldest: Vector2i = _get_furthest_chunk_from_camera()
        clear_chunk_visuals(oldest)  # Keep placement cache
```

---

## Fallback Visuals

During progressive loading, chunks without vegetation look bare. Options:

### A. Low-Poly Placeholder (Recommended)

```gdscript
func _create_placeholder_for_chunk(coord: Vector2i) -> void:
    # Single green quad covering chunk
    var placeholder := MeshInstance3D.new()
    var quad := QuadMesh.new()
    quad.size = Vector2(chunk_size, chunk_size)
    placeholder.mesh = quad
    placeholder.position = Vector3(
        coord.x * chunk_size + chunk_size / 2,
        50.0,  # Approximate ground level
        coord.y * chunk_size + chunk_size / 2
    )
    placeholder.rotation_degrees.x = -90
    # Green tint material
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.2, 0.35, 0.15, 0.5)
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    placeholder.material_override = mat
    add_child(placeholder)
    _placeholders[coord] = placeholder
```

### B. Loading Indicator UI

Show progress bar or "Loading terrain..." in HUD while vegetation populates.

### C. Camera Restriction

Lock camera zoom-out until initial vegetation loads (prevents seeing bare terrain).

---

## Performance Budget Allocation

With 16.67ms frame budget at 60 FPS:

| System | Budget | Notes |
|--------|--------|-------|
| Rendering | ~8ms | GPU bound |
| Physics/Collision | ~2ms | Jolt |
| AI/Gameplay | ~2ms | Combat, pathfinding |
| **Vegetation Loading** | **4ms** | Conservative |
| Headroom | ~0.67ms | Spikes, GC |

**Vegetation budget of 4ms allows:**
- ~1 placement cache build (8ms / 2 frames)
- ~1 tree materialization (10ms / 3 frames)
- ~1 grass materialization (5ms / 2 frames)

**Effective loading rate:** ~0.15 chunks/frame = ~9 chunks/second
**Full map load time:** 144 chunks / 9 cps = **~16 seconds of progressive loading**

This is acceptable for RTS (player can start playing immediately while far terrain loads).

---

## Concrete Implementation Steps

### Step 1: Add Async Infrastructure to VegetationManager (Day 1)

1. Add `VegetationTask` class and `_vegetation_queue`
2. Add `_process()` function with `_process_vegetation_queue()`
3. Split `generate_for_chunk()` into `queue_vegetation()` + steps
4. Add `vegetation_chunk_ready` signal

### Step 2: Decouple TerrainManager Calls (Day 1)

1. In `_load_chunk()`: Replace direct call with `vegetation_manager.queue_vegetation()`
2. Terrain mesh builds immediately, vegetation follows asynchronously
3. Test that terrain is playable without vegetation

### Step 3: Add Priority Sorting (Day 2)

1. Implement distance-based priority in queue insertion
2. Expose camera reference to VegetationManager
3. Verify camera-near chunks load first

### Step 4: Add Placeholder Visuals (Day 2)

1. Create simple green overlay for loading chunks
2. Remove placeholder when vegetation completes
3. Optional: Add UI loading indicator

### Step 5: Profile and Tune (Day 3)

1. Run Godot profiler with new system
2. Adjust `STEP_BUDGET_MS` based on actual frame times
3. Consider threading for placement cache if CPU-bound

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Gameplay depends on vegetation before loaded | Medium | High | Signal-based readiness checks |
| Visual pop-in noticeable | High | Medium | Placeholder + priority loading |
| Threading complexity | Low | Medium | Start with coroutines only |
| Memory pressure from queue | Low | Low | Limit queue size |

---

## Questions for Other Architects

1. **Systems Designer:** Does LOS/pathfinding need immediate vegetation data, or can it use simplified fallback during load?

2. **Gameplay Programmer:** What's the minimum viable vegetation for "playable" state? (Trees for cover only? Full grass too?)

3. **Devil's Advocate:** Are there edge cases where async vegetation breaks gameplay invariants?

---

## Final Recommendation

**Implement Time-Budgeted Queue (Option C) as Phase 1.**

This approach:
- Solves the freeze immediately
- Integrates with existing TerrainManager architecture
- Requires minimal code changes
- Maintains 60 FPS guarantee
- Can be extended with threading later if needed

The 16-second progressive load is acceptable for an RTS where players typically spend time in pre-mission menus. Camera-near priority ensures the immediate play area is ready first.

**Do not implement threading in Phase 1.** The complexity is not justified until profiling proves the coroutine approach is insufficient.
