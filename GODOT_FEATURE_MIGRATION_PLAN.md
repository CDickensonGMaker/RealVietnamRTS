# Godot Feature Migration Plan - 10 Steps

## Overview
Migrate script-based implementations to Godot native features for better performance, maintainability, and engine integration.

**Estimated Total Effort:** 30-40 hours
**Performance Improvement:** 25-40% in combat scenarios

---

## Step 1: Create Detection Area Base Class
**Goal:** Replace manual `get_nodes_in_group()` target scanning with Area3D signals

**Files to create:**
- `battle_system/components/detection_area.gd`

**What it does:**
```gdscript
class_name DetectionArea extends Area3D
## Reusable detection component for emplacements

signal target_entered(target: Node3D)
signal target_exited(target: Node3D)

@export var detection_radius: float = 250.0
@export var target_groups: Array[String] = ["enemy_units"]
@export var exclude_groups: Array[String] = ["aircraft"]  # For ground-only

var targets_in_range: Array[Node3D] = []

func _ready() -> void:
    _setup_collision()
    body_entered.connect(_on_body_entered)
    body_exited.connect(_on_body_exited)
```

**Benefits:**
- 20-40% faster target acquisition
- Eliminates repeated group iteration
- Reusable across all emplacements

**Effort:** 3-4 hours

---

## Step 2: Migrate Emplacements to DetectionArea
**Goal:** Wire MG Nest, Mortar Pit, Bunker, AA to use new detection system

**Files to modify:**
- `fortification_system/machine_gun_nest.gd`
- `fortification_system/mortar_pit.gd`
- `fortification_system/bunker.gd`
- `battle_system/ai/aa_emplacement.gd`

**Changes per file:**
```gdscript
# Remove:
func _scan_for_targets() -> void:
    for group_name in target_groups:
        var units = get_tree().get_nodes_in_group(group_name)
        for unit in units:
            # distance check...

# Add:
@onready var _detection: DetectionArea = $DetectionArea

func _ready() -> void:
    _detection.target_entered.connect(_on_target_entered)
    _detection.target_exited.connect(_on_target_exited)

func _find_best_target() -> Node3D:
    # Only iterate targets already in range
    for target in _detection.targets_in_range:
        if is_in_firing_arc(target.global_position):
            return target
    return null
```

**Effort:** 4-5 hours

---

## Step 3: Replace Manual Fire Timers with Tween
**Goal:** Eliminate `_fire_timer += delta` patterns

**Files to modify:**
- `fortification_system/machine_gun_nest.gd` (3 timers)
- `fortification_system/mortar_pit.gd` (3 timers)
- `fortification_system/bunker.gd` (2 timers)
- `battle_system/ai/aa_emplacement.gd` (2 timers)

**Pattern replacement:**
```gdscript
# BEFORE (in _process):
_fire_timer += delta
if _fire_timer >= fire_interval:
    _fire_timer = 0.0
    _fire_burst()

# AFTER:
var _fire_tween: Tween

func _start_firing() -> void:
    if _fire_tween:
        _fire_tween.kill()
    _fire_tween = create_tween().set_loops()
    _fire_tween.tween_callback(_fire_burst).set_delay(fire_interval)

func _stop_firing() -> void:
    if _fire_tween:
        _fire_tween.kill()
        _fire_tween = null
```

**Benefits:**
- Frame-rate independent timing
- Automatic cleanup on node free
- Cleaner state management

**Effort:** 3-4 hours

---

## Step 4: Replace Pending Impacts with SceneTreeTimer
**Goal:** Eliminate manual array tracking for projectiles in flight

**Files to modify:**
- `fortification_system/mortar_pit.gd`
- `battle_system/units/artillery.gd`

**Pattern replacement:**
```gdscript
# BEFORE:
var _pending_impacts: Array = []

func _fire_round(target_pos: Vector3) -> void:
    _pending_impacts.append({
        "position": impact_pos,
        "time_remaining": flight_time,
        "damage": damage
    })

func _process(delta: float) -> void:
    for impact in _pending_impacts:
        impact.time_remaining -= delta
        if impact.time_remaining <= 0:
            _apply_impact(impact)
            # Remove from array...

# AFTER:
func _fire_round(target_pos: Vector3) -> void:
    var timer := get_tree().create_timer(flight_time)
    timer.timeout.connect(_apply_impact.bind(impact_pos, damage))
    # No array management needed!
```

**Benefits:**
- Eliminates ~15 lines of array management
- Self-cleaning (timers auto-free)
- More predictable timing

**Effort:** 2-3 hours

---

## Step 5: Create Emplacement State Machine Resource
**Goal:** Define reusable AnimationTree StateMachine for emplacements

**Files to create:**
- `fortification_system/resources/emplacement_state_machine.tres`
- `fortification_system/emplacement_base.gd`

**State Machine Layout:**
```
[IDLE] ─────────────────┐
   │                    │
   ▼ (target detected)  │
[TRACKING] ◄────────────┤
   │                    │
   ▼ (in range + arc)   │
[FIRING] ───────────────┤
   │                    │
   ▼ (ammo depleted)    │
[RELOADING] ────────────┤
   │                    │
   │  ┌── (suppressed) ─┘
   ▼  ▼
[SUPPRESSED] ───────────┘
   │
   ▼ (health <= 0)
[DESTROYED]
```

**Base class:**
```gdscript
class_name EmplacementBase extends Node3D

@onready var _anim_tree: AnimationTree = $AnimationTree
@onready var _state_machine: AnimationNodeStateMachinePlayback

func _ready() -> void:
    _state_machine = _anim_tree.get("parameters/playback")

func transition_to(state_name: String) -> void:
    _state_machine.travel(state_name)

func get_current_state() -> String:
    return _state_machine.get_current_node()
```

**Effort:** 4-5 hours

---

## Step 6: Add Smooth Rotation via Tween
**Goal:** Replace instant/lerp rotation with smooth Tween animation

**Files to modify:**
- `fortification_system/machine_gun_nest.gd`
- `fortification_system/mortar_pit.gd`
- `fortification_system/bunker.gd`
- `battle_system/nodes/squad.gd`

**Pattern replacement:**
```gdscript
# BEFORE (instant):
_gun_mesh.rotation.y = target_angle

# BEFORE (lerp in _process):
rotation.y = lerp_angle(rotation.y, target, delta * speed)

# AFTER:
var _rotation_tween: Tween

func _rotate_to_target(target_pos: Vector3) -> void:
    var direction := (target_pos - global_position).normalized()
    var target_angle := atan2(direction.x, direction.z)

    if _rotation_tween:
        _rotation_tween.kill()

    _rotation_tween = create_tween()
    _rotation_tween.set_trans(Tween.TRANS_SINE)
    _rotation_tween.set_ease(Tween.EASE_OUT)
    _rotation_tween.tween_property(_gun_mesh, "rotation:y", target_angle, 0.3)
```

**Benefits:**
- Frame-rate independent
- Customizable easing curves
- Better visual feedback

**Effort:** 2-3 hours

---

## Step 7: Create GPUParticles3D for Effects
**Goal:** Replace mesh-spawning effects with particle systems

**Files to create:**
- `effects/particles/muzzle_flash.tscn`
- `effects/particles/mortar_impact.tscn`
- `effects/particles/dust_cloud.tscn`

**Files to modify:**
- `fortification_system/machine_gun_nest.gd`
- `fortification_system/mortar_pit.gd`
- `fortification_system/bunker.gd`

**Pattern replacement:**
```gdscript
# BEFORE (mesh-based):
func _spawn_muzzle_flash() -> void:
    var flash := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.2
    flash.mesh = sphere
    # Material setup...
    var tween := create_tween()
    tween.tween_property(mat, "albedo_color:a", 0.0, 0.1)
    tween.tween_callback(flash.queue_free)

# AFTER (particles):
@onready var _muzzle_particles: GPUParticles3D = $MuzzleFlash

func _spawn_muzzle_flash() -> void:
    _muzzle_particles.restart()
```

**Benefits:**
- GPU-accelerated rendering
- Better visual quality
- Less garbage collection
- Configurable in editor

**Effort:** 4-5 hours

---

## Step 8: Migrate Blast Damage to Area3D Overlap
**Goal:** Replace distance loop with physics overlap query

**Files to modify:**
- `fortification_system/mortar_pit.gd`
- `battle_system/units/artillery.gd`
- `battle_system/systems/combat_manager.gd` (if applicable)

**Pattern replacement:**
```gdscript
# BEFORE:
func _apply_impact(pos: Vector3, damage: float) -> void:
    var all_units := get_tree().get_nodes_in_group("all_units")
    for unit in all_units:
        var dist := unit.global_position.distance_to(pos)
        if dist <= blast_radius:
            var falloff := 1.0 - (dist / blast_radius)
            unit.take_damage(damage * falloff, self)

# AFTER:
func _apply_impact(pos: Vector3, damage: float) -> void:
    var space := get_world_3d().direct_space_state
    var params := PhysicsShapeQueryParameters3D.new()
    params.shape = SphereShape3D.new()
    params.shape.radius = blast_radius
    params.transform.origin = pos
    params.collision_mask = 0b1110  # Units layers

    var results := space.intersect_shape(params)
    for result in results:
        var unit := result.collider.get_parent()
        if unit and unit.has_method("take_damage"):
            var dist := unit.global_position.distance_to(pos)
            var falloff := 1.0 - clampf(dist / blast_radius, 0.0, 1.0)
            unit.take_damage(damage * falloff, self)
```

**Benefits:**
- Uses physics broadphase (faster)
- Respects collision layers
- Future-proof for visibility checks

**Effort:** 3-4 hours

---

## Step 9: Add AudioStreamPlayer3D Pooling
**Goal:** Replace ad-hoc sound playing with pooled 3D audio

**Files to create:**
- `audio/audio_pool.gd`
- `audio/audio_pool_3d.tscn`

**Implementation:**
```gdscript
class_name AudioPool3D extends Node3D
## Pool of AudioStreamPlayer3D for efficient spatial sound

const POOL_SIZE := 32

var _players: Array[AudioStreamPlayer3D] = []
var _next_index: int = 0

func _ready() -> void:
    for i in POOL_SIZE:
        var player := AudioStreamPlayer3D.new()
        player.bus = "SFX"
        add_child(player)
        _players.append(player)

func play_at(stream: AudioStream, position: Vector3, volume_db: float = 0.0) -> void:
    var player := _players[_next_index]
    _next_index = (_next_index + 1) % POOL_SIZE

    player.stream = stream
    player.global_position = position
    player.volume_db = volume_db
    player.play()
```

**Usage in emplacements:**
```gdscript
func _fire_burst() -> void:
    AudioPool3D.play_at(fire_sound, global_position + muzzle_offset)
```

**Benefits:**
- No node creation/destruction overhead
- Proper 3D audio positioning
- Consistent volume/bus management

**Effort:** 3-4 hours

---

## Step 10: Create Resource-Based Weapon Data
**Goal:** Replace weapon dictionaries with typed Resources

**Files to create:**
- `battle_system/data/weapon_resource.gd`
- `battle_system/data/weapons/*.tres` (individual weapon files)

**Implementation:**
```gdscript
class_name WeaponResource extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var damage: float = 15.0
@export var range_meters: float = 300.0
@export var rate_of_fire: float = 600.0  # RPM
@export var magazine_size: int = 30
@export var reload_time: float = 2.5
@export var suppression_per_hit: float = 5.0
@export var accuracy_base: float = 0.8
@export var fire_sound: AudioStream
@export var muzzle_flash_scene: PackedScene
@export var projectile_type: String = "bullet"  # bullet, shell, rocket

func get_damage_at_range(distance: float) -> float:
    var falloff := clampf(distance / range_meters, 0.0, 1.0)
    return damage * (1.0 - falloff * 0.3)  # 30% falloff at max range
```

**Benefits:**
- Editor-editable weapon stats
- Type safety (no dictionary key typos)
- Easy balancing without code changes
- Inheritance for weapon variants

**Effort:** 4-5 hours (including migration of existing weapons)

---

## Implementation Schedule

| Week | Steps | Focus Area |
|------|-------|------------|
| **1** | 1-2 | Detection system (biggest perf win) |
| **2** | 3-4 | Timer migration (cleanup) |
| **3** | 5-6 | State machines + rotation |
| **4** | 7-8 | Effects + blast damage |
| **5** | 9-10 | Audio + weapon resources |

---

## Verification Checklist

After each step:
- [ ] Run `static_defenses_test.tscn` - emplacements engage targets
- [ ] Spawn 20+ enemies - no performance degradation
- [ ] Check console - no errors or warnings from changed code
- [ ] Profile with `--profile` flag - verify improvements

---

## Files Summary

**New files to create:**
```
battle_system/components/detection_area.gd
fortification_system/emplacement_base.gd
fortification_system/resources/emplacement_state_machine.tres
effects/particles/muzzle_flash.tscn
effects/particles/mortar_impact.tscn
effects/particles/dust_cloud.tscn
audio/audio_pool.gd
audio/audio_pool_3d.tscn
battle_system/data/weapon_resource.gd
battle_system/data/weapons/*.tres
```

**Files to modify:**
```
fortification_system/machine_gun_nest.gd
fortification_system/mortar_pit.gd
fortification_system/bunker.gd
battle_system/ai/aa_emplacement.gd
battle_system/nodes/squad.gd
battle_system/units/artillery.gd
```

---

## Expected Outcomes

| Metric | Before | After |
|--------|--------|-------|
| Target scanning (per frame) | 455 checks | ~50 checks |
| Timer variables | 10+ manual | 0 (Tween-based) |
| State machine LOC | ~40 lines/class | ~10 lines/class |
| Effect nodes created | ~20/sec combat | 0 (particles) |
| Audio nodes created | ~30/sec combat | 0 (pooled) |

**Total estimated performance improvement: 25-40% in heavy combat**
