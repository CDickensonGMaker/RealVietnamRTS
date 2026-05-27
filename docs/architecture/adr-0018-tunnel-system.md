# ADR-0018: Tunnel System

## Status
Proposed

## Context

The VC faction uses tunnel networks as their primary force generation mechanism, contrasting with the US helicopter/convoy reinforcement system. Tunnel entrances spawn VC units until found and destroyed, creating asymmetric gameplay where the US must hunt hidden infrastructure while defending against unpredictable attacks.

### Requirements to Address
| TR-ID | Requirement |
|-------|-------------|
| TR-SYS-090 | Tunnel entrances spawn VC units until found and destroyed |
| TR-SYS-091 | Tunnel entrances are hidden until spotted |

## Decision

### Tunnel System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                      TunnelNetworkManager                           │
│                      (Autoload Singleton)                           │
├─────────────────────────────────────────────────────────────────────┤
│  + register_tunnel(entrance: TunnelEntrance) -> void                │
│  + get_active_tunnels() -> Array[TunnelEntrance]                    │
│  + spawn_from_tunnel(entrance, unit_type) -> Node3D                 │
│  + reveal_tunnel(entrance) -> void                                  │
│  + destroy_tunnel(entrance, method) -> void                         │
├─────────────────────────────────────────────────────────────────────┤
│  Signals: tunnel_revealed, tunnel_destroyed, tunnel_spawn,          │
│           tunnel_network_updated                                    │
└─────────────────────────────────────────────────────────────────────┘
          ▲
          │ manages
          │
┌─────────────────────────────────────────────────────────────────────┐
│                      TunnelEntrance (Node3D)                        │
├─────────────────────────────────────────────────────────────────────┤
│  + tunnel_id: String                                                │
│  + is_revealed: bool = false                                        │
│  + is_destroyed: bool = false                                       │
│  + spawn_capacity: int                                              │
│  + units_spawned: int                                               │
│  + spawn_cooldown: float                                            │
│  + connected_tunnels: Array[TunnelEntrance]                         │
├─────────────────────────────────────────────────────────────────────┤
│  Components: detection_area, spawn_point, destruction_particles     │
└─────────────────────────────────────────────────────────────────────┘
```

### Tunnel Entrance (TR-SYS-090)

```gdscript
## tunnel_entrance.gd - Hidden spawn point for VC units

class_name TunnelEntrance extends Node3D

@export var tunnel_id: String
@export var spawn_capacity: int = 20          # Max units that can spawn
@export var spawn_cooldown: float = 30.0      # Seconds between spawns
@export var units_per_spawn: int = 4          # Squad size per spawn
@export var connected_tunnels: Array[NodePath] = []

## Visibility state (TR-SYS-091)
var is_revealed: bool = false
var is_destroyed: bool = false

## Spawn tracking
var units_spawned: int = 0
var _spawn_timer: float = 0.0
var _spawned_units: Array[Node3D] = []

## Detection
@export var detection_radius: float = 15.0    # How close US must be to spot
@export var detection_time: float = 3.0       # Seconds of proximity to reveal
var _detection_progress: float = 0.0

@onready var _spawn_point: Marker3D = $SpawnPoint
@onready var _detection_area: Area3D = $DetectionArea
@onready var _visual_mesh: MeshInstance3D = $TunnelMesh
@onready var _hidden_effect: GPUParticles3D = $HiddenEffect

func _ready() -> void:
    TunnelNetworkManager.register_tunnel(self)

    _detection_area.body_entered.connect(_on_body_entered_detection)
    _detection_area.body_exited.connect(_on_body_exited_detection)

    # Start hidden (TR-SYS-091)
    _set_visible(false)

    # Connect to AI Director for spawn requests
    BattleSignals.ai_director_spawn_request.connect(_on_spawn_request)
```

### Hidden Until Spotted (TR-SYS-091)

```gdscript
## tunnel_entrance.gd - Detection mechanics

var _detecting_units: Array[Node3D] = []

func _on_body_entered_detection(body: Node3D) -> void:
    if is_revealed or is_destroyed:
        return

    if not body.has_method("get_faction"):
        return

    # Only US/ARVN can detect
    var faction: GameEnums.Faction = body.get_faction()
    if faction not in [GameEnums.Faction.US_ARMY, GameEnums.Faction.ARVN]:
        return

    _detecting_units.append(body)

func _on_body_exited_detection(body: Node3D) -> void:
    _detecting_units.erase(body)

func _process(delta: float) -> void:
    if not is_revealed and not is_destroyed:
        _process_detection(delta)

    if not is_destroyed:
        _process_spawn(delta)

func _process_detection(delta: float) -> void:
    if _detecting_units.is_empty():
        # Decay detection progress when no one nearby
        _detection_progress = maxf(0.0, _detection_progress - delta * 0.5)
        return

    # Check for recon units (faster detection)
    var detection_speed := 1.0
    for unit in _detecting_units:
        if unit.has_method("is_recon") and unit.is_recon():
            detection_speed = 2.0
            break

    _detection_progress += delta * detection_speed

    if _detection_progress >= detection_time:
        _reveal()

func _reveal() -> void:
    if is_revealed:
        return

    is_revealed = true
    _set_visible(true)

    BattleSignals.tunnel_revealed.emit(self)

    # Play reveal audio
    AudioManager.play_sfx(global_position, "tunnel_discovered")

    # Notify AI Director
    AIDirector.on_tunnel_revealed(self)

func _set_visible(visible: bool) -> void:
    _visual_mesh.visible = visible

    if visible:
        _hidden_effect.emitting = false
    else:
        # Subtle visual hint for observant players
        _hidden_effect.emitting = true
```

### Spawn Mechanics (TR-SYS-090)

```gdscript
## tunnel_entrance.gd - Unit spawning

func _process_spawn(delta: float) -> void:
    if is_destroyed:
        return

    if units_spawned >= spawn_capacity:
        return

    _spawn_timer += delta

func can_spawn() -> bool:
    if is_destroyed:
        return false
    if units_spawned >= spawn_capacity:
        return false
    if _spawn_timer < spawn_cooldown:
        return false
    return true

## Called by AI Director or TunnelNetworkManager
func spawn_unit(unit_type: String) -> Node3D:
    if not can_spawn():
        return null

    _spawn_timer = 0.0
    units_spawned += 1

    # Spawn unit at tunnel exit
    var spawn_pos := _spawn_point.global_position
    var unit := UnitFactory.spawn_vc_unit(unit_type, spawn_pos)

    if unit:
        _spawned_units.append(unit)

        # Play spawn effect
        _play_spawn_effect()

        # If revealed, spawn is visible to US
        if is_revealed:
            BattleSignals.tunnel_spawn_observed.emit(self, unit)
        else:
            # Hidden spawn - unit appears from jungle
            unit.set_stealth_mode(true)

        BattleSignals.tunnel_spawn.emit(self, unit)

    return unit

func _play_spawn_effect() -> void:
    # Dust/dirt particles emerging from ground
    var effect := preload("res://effects/tunnel_spawn.tscn").instantiate()
    effect.global_position = _spawn_point.global_position
    get_tree().current_scene.add_child(effect)

## Spawn multiple units (squad spawn)
func spawn_squad(unit_type: String, count: int = -1) -> Array[Node3D]:
    if count < 0:
        count = units_per_spawn

    var spawned: Array[Node3D] = []

    for i in range(count):
        if not can_spawn():
            break

        var unit := spawn_unit(unit_type)
        if unit:
            spawned.append(unit)

            # Stagger spawn positions slightly
            unit.global_position += Vector3(
                randf_range(-2.0, 2.0),
                0,
                randf_range(-2.0, 2.0)
            )

    return spawned
```

### Tunnel Destruction (TR-SYS-090)

```gdscript
## tunnel_entrance.gd - Destruction methods

enum DestructionMethod {
    EXPLOSIVE,     # C4, grenades, demo charges
    ENGINEER,      # Engineer squad sealing
    TUNNEL_RAT,    # Tunnel rat clearing (detailed clear)
    COLLAPSE,      # Artillery/airstrike cave-in
}

func destroy(method: DestructionMethod, source: Node3D = null) -> void:
    if is_destroyed:
        return

    is_destroyed = true

    # Play destruction effect based on method
    match method:
        DestructionMethod.EXPLOSIVE:
            _play_explosion_effect()
            AudioManager.play_sfx(global_position, "tunnel_explode")
        DestructionMethod.ENGINEER:
            _play_sealing_effect()
            AudioManager.play_sfx(global_position, "tunnel_sealed")
        DestructionMethod.TUNNEL_RAT:
            _play_clearing_effect()
            # Tunnel rat may find intel
            _generate_intel(source)
        DestructionMethod.COLLAPSE:
            _play_collapse_effect()
            AudioManager.play_sfx(global_position, "tunnel_collapse")

    # Disable spawning
    spawn_capacity = 0

    # Notify connected tunnels
    _notify_network_destruction()

    BattleSignals.tunnel_destroyed.emit(self, method)

func _notify_network_destruction() -> void:
    for path in connected_tunnels:
        var connected: TunnelEntrance = get_node_or_null(path)
        if connected and not connected.is_destroyed:
            # Connected tunnels may become less effective
            connected.spawn_cooldown *= 1.5

func _generate_intel(source: Node3D) -> void:
    # Tunnel rat clearing generates intel about other tunnels
    if randf() < 0.3:  # 30% chance
        var nearby := TunnelNetworkManager.get_nearest_unrevealed(global_position)
        if nearby:
            # Partial reveal - shows approximate area
            BattleSignals.tunnel_intel_found.emit(nearby.global_position, 50.0)

func take_damage(amount: float, damage_type: DamageType, source: Node3D) -> void:
    # Only explosives can damage tunnels
    if damage_type != DamageType.EXPLOSIVE:
        return

    # Large explosions can collapse tunnels
    if amount >= 100.0:
        destroy(DestructionMethod.COLLAPSE, source)
```

### Tunnel Network Manager

```gdscript
## tunnel_network_manager.gd - Autoload singleton

class_name TunnelNetworkManager extends Node

var _tunnels: Dictionary = {}  # tunnel_id -> TunnelEntrance

func _ready() -> void:
    BattleSignals.ai_director_spawn_request.connect(_on_ai_spawn_request)

func register_tunnel(entrance: TunnelEntrance) -> void:
    _tunnels[entrance.tunnel_id] = entrance

func get_active_tunnels() -> Array[TunnelEntrance]:
    var active: Array[TunnelEntrance] = []
    for tunnel in _tunnels.values():
        if not tunnel.is_destroyed:
            active.append(tunnel)
    return active

func get_hidden_tunnels() -> Array[TunnelEntrance]:
    var hidden: Array[TunnelEntrance] = []
    for tunnel in _tunnels.values():
        if not tunnel.is_revealed and not tunnel.is_destroyed:
            hidden.append(tunnel)
    return hidden

func get_nearest_unrevealed(position: Vector3) -> TunnelEntrance:
    var nearest: TunnelEntrance = null
    var nearest_dist := INF

    for tunnel in get_hidden_tunnels():
        var dist := position.distance_to(tunnel.global_position)
        if dist < nearest_dist:
            nearest_dist = dist
            nearest = tunnel

    return nearest

## Called by AI Director to spawn units
func request_spawn(unit_type: String, count: int, preferred_position: Vector3 = Vector3.ZERO) -> Array[Node3D]:
    var spawned: Array[Node3D] = []

    # Find best tunnel to spawn from
    var tunnel := _select_spawn_tunnel(preferred_position)
    if not tunnel:
        return spawned

    # Spawn units
    spawned = tunnel.spawn_squad(unit_type, count)

    return spawned

func _select_spawn_tunnel(preferred_position: Vector3) -> TunnelEntrance:
    var active := get_active_tunnels()
    if active.is_empty():
        return null

    # If no preferred position, pick random
    if preferred_position == Vector3.ZERO:
        var valid := active.filter(func(t): return t.can_spawn())
        if valid.is_empty():
            return null
        return valid[randi() % valid.size()]

    # Find tunnel nearest to preferred position that can spawn
    var best: TunnelEntrance = null
    var best_score := -INF

    for tunnel in active:
        if not tunnel.can_spawn():
            continue

        var dist := tunnel.global_position.distance_to(preferred_position)

        # Score: closer is better, hidden is better
        var score := -dist
        if not tunnel.is_revealed:
            score += 100.0  # Prefer hidden tunnels

        if score > best_score:
            best_score = score
            best = tunnel

    return best

## Reveal tunnel via area scan (recon sweep)
func scan_area(center: Vector3, radius: float) -> Array[TunnelEntrance]:
    var found: Array[TunnelEntrance] = []

    for tunnel in get_hidden_tunnels():
        var dist := tunnel.global_position.distance_to(center)
        if dist <= radius:
            tunnel._reveal()
            found.append(tunnel)

    return found
```

### Integration with AI Director

```gdscript
## ai_director.gd - Tunnel spawning integration

func _select_attack_spawn_method() -> void:
    # Prefer tunnels for VC attacks
    var active_tunnels := TunnelNetworkManager.get_active_tunnels()

    if active_tunnels.is_empty():
        # No tunnels - spawn from map edge
        _spawn_from_map_edge()
        return

    # Select tunnel based on attack direction
    var target_firebase := _select_attack_target()
    var best_tunnel := _select_best_tunnel_for_attack(active_tunnels, target_firebase)

    if best_tunnel:
        _spawn_from_tunnel(best_tunnel)
    else:
        _spawn_from_map_edge()

func _select_best_tunnel_for_attack(
    tunnels: Array[TunnelEntrance],
    target: Node3D
) -> TunnelEntrance:

    var best: TunnelEntrance = null
    var best_score := -INF

    for tunnel in tunnels:
        if not tunnel.can_spawn():
            continue

        var dist := tunnel.global_position.distance_to(target.global_position)

        # Score: moderate distance is ideal (100-300m from target)
        var ideal_dist := 200.0
        var dist_score := -absf(dist - ideal_dist)

        # Hidden tunnels preferred
        var hidden_bonus := 50.0 if not tunnel.is_revealed else 0.0

        # Remaining capacity matters
        var capacity_score := (tunnel.spawn_capacity - tunnel.units_spawned) * 2.0

        var total_score := dist_score + hidden_bonus + capacity_score

        if total_score > best_score:
            best_score = total_score
            best = tunnel

    return best

func _spawn_from_tunnel(tunnel: TunnelEntrance) -> void:
    var attack_squad := tunnel.spawn_squad("vc_infantry", 4)

    if attack_squad.size() > 0:
        # Order attack
        var target := _current_attack_target
        for unit in attack_squad:
            unit.order_attack(target)

        BattleSignals.vc_attack_launched.emit(attack_squad, target)
```

### Serialization Support

```gdscript
## TunnelEntrance serialization
func serialize() -> Dictionary:
    return {
        "_version": 1,
        "tunnel_id": tunnel_id,
        "is_revealed": is_revealed,
        "is_destroyed": is_destroyed,
        "units_spawned": units_spawned,
        "spawn_timer": _spawn_timer,
        "detection_progress": _detection_progress,
        "spawn_cooldown": spawn_cooldown,
    }

func deserialize(data: Dictionary) -> bool:
    if data.get("_version", 0) != 1:
        return false

    is_revealed = data.get("is_revealed", false)
    is_destroyed = data.get("is_destroyed", false)
    units_spawned = data.get("units_spawned", 0)
    _spawn_timer = data.get("spawn_timer", 0.0)
    _detection_progress = data.get("detection_progress", 0.0)
    spawn_cooldown = data.get("spawn_cooldown", spawn_cooldown)

    # Update visibility
    _set_visible(is_revealed)

    return true

## TunnelNetworkManager serialization
func serialize() -> Dictionary:
    var tunnel_data: Array = []
    for tunnel in _tunnels.values():
        tunnel_data.append(tunnel.serialize())

    return {
        "_version": 1,
        "_system": "TunnelNetworkManager",
        "tunnels": tunnel_data,
    }
```

## Consequences

### Positive
- **Asymmetric gameplay**: VC spawning differs fundamentally from US (TR-SYS-090)
- **Hidden threat**: Creates recon gameplay and paranoia (TR-SYS-091)
- **Meaningful destruction**: Finding/destroying tunnels provides strategic value
- **Dynamic battlespace**: Tunnels can spawn attacks from unexpected directions

### Negative
- **Balance challenge**: Hidden spawning can feel unfair if not tuned
- **Map design requirement**: Maps must have tunnel placements
- **Detection clarity**: Players must understand when tunnels are revealed

### Mitigations
- Subtle visual hints for hidden tunnels
- Recon units provide faster detection
- Tunnel capacity limits total spawns
- Audio cues for nearby tunnel activity

## ADR Dependencies

- **ADR-0008 (Serialization)**: Tunnel state persistence
- **ADR-0013 (AI Director)**: Spawn integration
- **ADR-0015 (Doctrine)**: VC Local Force doctrine bonuses

## Engine Compatibility

**Godot 4.6** - Area3D for detection, standard node patterns.

## GDD Requirements Addressed

| Requirement | How Addressed |
|-------------|---------------|
| TR-SYS-090 | `spawn_unit()` and `spawn_squad()` spawn VC until `is_destroyed` |
| TR-SYS-091 | `is_revealed` starts false, `_process_detection()` reveals on proximity |

## Implementation Files

| File | Purpose |
|------|---------|
| `tunnel_system/tunnel_network_manager.gd` | Autoload singleton |
| `tunnel_system/tunnel_entrance.gd` | Individual tunnel entrance |
| `tunnel_system/tunnel_rat.gd` | Tunnel clearing specialist |
| `effects/tunnel_spawn.tscn` | Spawn visual effect |
| `effects/tunnel_revealed.tscn` | Reveal visual effect |

## Key Signals

```gdscript
## BattleSignals additions for tunnels
signal tunnel_revealed(tunnel: TunnelEntrance)
signal tunnel_destroyed(tunnel: TunnelEntrance, method: int)
signal tunnel_spawn(tunnel: TunnelEntrance, unit: Node3D)
signal tunnel_spawn_observed(tunnel: TunnelEntrance, unit: Node3D)
signal tunnel_intel_found(position: Vector3, radius: float)
signal tunnel_network_updated()
```

## Validation Criteria

- [ ] Tunnels start hidden from US player
- [ ] US units within detection radius reveal tunnel over time
- [ ] Recon units reveal tunnels faster
- [ ] VC units spawn from tunnels on AI Director request
- [ ] Destroyed tunnels stop spawning
- [ ] Explosives can collapse tunnels
- [ ] Engineers can seal tunnels
- [ ] Hidden tunnels provide spawn advantage
- [ ] Tunnel state persists in save/load
