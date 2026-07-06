# PERFORMANCE FIX PLAN
## Epic: RealVietnamRTS-zuf
## Date: 2026-05-29

---

## EXECUTIVE SUMMARY

The game lags with 10 units because **40 files call `get_nodes_in_group()` inside `_process()`**, causing 100+ O(n) scene tree walks per second. Additionally, a **27:1 signal connect/disconnect ratio** causes memory leaks over time.

**Good news**: `SpatialHashGrid` autoload already exists with all needed methods. It's just not being used.

---

## PHASE 1: CRITICAL - Squad Auto-Engage (Biggest Impact)

**Task**: RealVietnamRTS-n3w
**Impact**: Eliminates 20+ scene walks per second with 10 units

### Current Code (squad.gd:629)
```gdscript
func _scan_for_auto_engage_targets() -> void:
    # Called every 0.75s per squad
    var enemies: Array[Node]
    if is_player_controlled:
        enemies = get_tree().get_nodes_in_group("enemy_units")  # O(n) walk!
    else:
        enemies = get_tree().get_nodes_in_group("player_units")  # Another O(n) walk!

    for enemy in enemies:
        var dist = global_position.distance_to(enemy.global_position)
        # ... find nearest
```

### Fixed Code
```gdscript
func _scan_for_auto_engage_targets() -> void:
    # O(1) spatial lookup via SpatialHashGrid autoload
    var weapon_range: float = 300.0
    if data:
        weapon_range = data.attack_range

    # Get faction from data
    var my_faction: int = GameEnums.Faction.US_ARMY
    if data and data.faction != null:
        my_faction = data.faction

    # Single O(1) call instead of O(n) + O(n) distance loop
    var nearest: Node3D = SpatialHashGrid.get_nearest_enemy(
        global_position,
        my_faction,
        weapon_range
    )

    if nearest and is_instance_valid(nearest):
        # Check if enemy is alive
        if nearest.has_method("get") and nearest.get("state") != null:
            if nearest.state != State.DEAD:
                current_target = nearest
                _enter_combat_state()
```

### Also Fix in squad.gd
- Line 577: `_find_target()` - same pattern
- Line 1933: `_find_nearest_supply_depot()` - use cached lookup (Phase 2)
- Line 2079: `_find_nearest_firebase()` - use cached lookup (Phase 2)

---

## PHASE 2: Cache Static Entity Lookups

**Task**: RealVietnamRTS-894
**Impact**: Eliminates repeated firebase/depot lookups

### Create: battle_system/systems/entity_cache.gd
```gdscript
extends Node
class_name EntityCache

## Cached arrays - invalidated by signals
var _firebases: Array[Node] = []
var _firebases_dirty: bool = true

var _supply_depots: Array[Node] = []
var _supply_depots_dirty: bool = true

var _landing_zones: Array[Node] = []
var _landing_zones_dirty: bool = true

func _ready() -> void:
    # Connect to invalidation signals
    BattleSignals.firebase_constructed.connect(func(_fb): _firebases_dirty = true)
    BattleSignals.firebase_destroyed.connect(func(_fb): _firebases_dirty = true)
    BattleSignals.building_constructed.connect(_on_building_constructed)
    BattleSignals.building_destroyed.connect(_on_building_destroyed)

func _on_building_constructed(building: Node, type: int) -> void:
    if type == GameEnums.BuildingType.SUPPLY_DEPOT:
        _supply_depots_dirty = true
    elif type == GameEnums.BuildingType.HELIPAD:
        _landing_zones_dirty = true

func _on_building_destroyed(building: Node, type: int) -> void:
    _on_building_constructed(building, type)  # Same invalidation

func get_firebases() -> Array[Node]:
    if _firebases_dirty:
        _firebases = get_tree().get_nodes_in_group("firebases")
        _firebases_dirty = false
    return _firebases

func get_supply_depots() -> Array[Node]:
    if _supply_depots_dirty:
        _supply_depots = get_tree().get_nodes_in_group("supply_depots")
        _supply_depots_dirty = false
    return _supply_depots

func get_landing_zones() -> Array[Node]:
    if _landing_zones_dirty:
        _landing_zones = get_tree().get_nodes_in_group("landing_zones")
        _landing_zones_dirty = false
    return _landing_zones

func get_nearest_firebase(position: Vector3) -> Node:
    var firebases := get_firebases()
    var nearest: Node = null
    var nearest_dist: float = INF
    for fb in firebases:
        if not is_instance_valid(fb):
            continue
        var dist := position.distance_to(fb.global_position)
        if dist < nearest_dist:
            nearest_dist = dist
            nearest = fb
    return nearest

func get_nearest_supply_depot(position: Vector3, faction: int = -1) -> Node:
    var depots := get_supply_depots()
    var nearest: Node = null
    var nearest_dist: float = INF
    for depot in depots:
        if not is_instance_valid(depot):
            continue
        if faction >= 0 and "faction" in depot and depot.faction != faction:
            continue
        var dist := position.distance_to(depot.global_position)
        if dist < nearest_dist:
            nearest_dist = dist
            nearest = depot
    return nearest
```

### Add to project.godot autoloads
```
EntityCache="*res://battle_system/systems/entity_cache.gd"
```

### Update Callers
Replace all:
```gdscript
var firebases = get_tree().get_nodes_in_group("firebases")
```
With:
```gdscript
var firebases = EntityCache.get_firebases()
```

---

## PHASE 3: Ensure Units Register with SpatialHashGrid

**Task**: RealVietnamRTS-1a8

### Check: Does squad.gd emit unit_spawned?

Search for `BattleSignals.unit_spawned.emit` - if not found, add:

```gdscript
# In squad.gd _ready()
func _ready() -> void:
    # ... existing setup ...

    # Register with SpatialHashGrid
    var faction: int = GameEnums.Faction.US_ARMY
    if data and data.faction != null:
        faction = data.faction
    BattleSignals.unit_spawned.emit(self, faction)

# In squad.gd when dying
func _die() -> void:
    BattleSignals.unit_died.emit(self, _last_attacker)
    # ... existing death logic ...
```

---

## PHASE 4: Signal Lifecycle Cleanup

**Task**: RealVietnamRTS-dv3

### Pattern for All High-Churn Nodes

```gdscript
# Track connections for cleanup
var _signal_connections: Array[Dictionary] = []

func _connect_tracked(sig: Signal, callable: Callable) -> void:
    sig.connect(callable)
    _signal_connections.append({"signal": sig, "callable": callable})

func _exit_tree() -> void:
    for conn in _signal_connections:
        if conn.signal.is_connected(conn.callable):
            conn.signal.disconnect(conn.callable)
    _signal_connections.clear()
```

### Priority Files (by connection count)
1. `projectile.gd` - 41 connections
2. `infantry_squad.gd` - 20 connections
3. `apc.gd` - 19 connections
4. `tank.gd` - 18 connections
5. `helicopter.gd` - 12 connections
6. `soldier.gd` - 11 connections

---

## PHASE 5: Audit Remaining 40 Files

**Task**: RealVietnamRTS-h4d

### Full List of Files with get_nodes_in_group in _process

```
battle_system/ai/ai_director.gd
battle_system/ai/ai_tick_manager.gd
battle_system/ai/ambush_manager.gd
battle_system/ai/auto_cover_behavior.gd
battle_system/ai/enemy_ai_controller.gd
battle_system/ai/nva_controller.gd
battle_system/ai/sapper_team.gd
battle_system/ai/siege_manager.gd
battle_system/ai/vc_controller.gd
battle_system/nodes/squad.gd
battle_system/systems/selection_manager.gd
battle_system/ui/battle_hud.gd
battle_system/ui/floating_label_manager.gd
battle_system/ui/tactical_minimap.gd
battle_system/ui/targeting_overlay.gd
battle_system/units/gunship_behavior.gd
battle_system/units/transport_truck.gd
core/save_manager.gd
firebase_system/construction_manager.gd
firebase_system/deployable_fob.gd
firebase_system/job_system/job_system.gd
firebase_system/job_system/worker_controller.gd
firebase_system/nodes/water_tank.gd
firebase_system/placement_controller.gd
firebase_system/test/building_test_scene.gd
fortification_system/machine_gun_nest.gd
fortification_system/mortar_pit.gd
helicopter_system/gunship.gd
helicopter_system/insertion_manager.gd
helicopter_system/landing_zone.gd
helicopter_system/medevac.gd
reinforcement_system/convoy_manager.gd
reinforcement_system/reinforcement_manager.gd
reinforcement_system/supply_manager.gd
reinforcement_system/supply_truck.gd
test_daemon/daemon_autoload.gd
test_scenes/_archive/supply_loop_test.gd
tunnel_system/tunnel_network.gd
village_system/civilian.gd
village_system/village_manager.gd
```

### Fix Strategy Per File Type

| Pattern | Fix |
|---------|-----|
| Unit proximity queries | Use `SpatialHashGrid.get_*` |
| Firebase/depot lookups | Use `EntityCache.get_*` |
| UI unit lists | Use `SpatialHashGrid.get_units_in_radius()` or cache |
| AI target finding | Use `SpatialHashGrid.get_nearest_enemy()` |
| One-time lookups | Move to `_ready()` or signal handlers |

---

## IMPLEMENTATION ORDER

1. **Day 1**: Phase 1 - Fix squad.gd auto-engage (biggest impact)
2. **Day 1**: Phase 3 - Ensure units register with SpatialHashGrid
3. **Day 2**: Phase 2 - Create EntityCache autoload
4. **Day 2**: Update squad.gd to use EntityCache for firebase/depot
5. **Day 3**: Phase 5 - Audit and fix remaining 40 files (batch by system)
6. **Day 4**: Phase 4 - Add _exit_tree cleanup to high-churn nodes
7. **Day 5**: Performance testing and profiling

---

## EXPECTED RESULTS

| Metric | Before | After |
|--------|--------|-------|
| Scene walks/second | 100+ | <5 |
| Frame time (10 units) | Laggy | Smooth |
| Memory growth (1 hour) | Unbounded | Stable |
| Target capacity | ~10 units | 300+ units |

---

## VALIDATION

After each phase, run:
1. Spawn 10 squads
2. Check Godot profiler for `get_nodes_in_group` calls
3. Monitor frame time in debugger
4. Play for 10 minutes, check memory growth

---

*Plan approved by War Room. Implementation begins immediately.*
