# ADR-0014: Reinforcement System

## Status
Proposed

## Context

RealVietnamRTS uses "Doctrine Over Spam" (Pillar 4) as a core design pillar. Unlike Age of Empires-style RTS games where units are produced at buildings, reinforcements arrive from off-map via helicopter or convoy. This creates meaningful force preservation - losing a squad means waiting minutes for replacement.

### Requirements to Address
| TR-ID | Requirement |
|-------|-------------|
| TR-SYS-050 | No Age of Empires-style unit production at firebases |
| TR-SYS-051 | Reinforcements arrive via helicopter or convoy from off-map supply chain |
| TR-SYS-052 | Reinforcement timing: infantry 3-5 min, armor 10-15 min, specialists 5-7 min |
| TR-SYS-053 | Lose a unit and wait minutes for replacement - force preservation matters |
| TR-SYS-054 | Deck cards determine available unit types and required buildings |
| TR-SYS-055 | Unit card auto-includes required buildings (tank card -> tank revetment) |
| TR-SYS-056 | 4-6 flexible building slots from doctrine-determined pool |

## Decision

### Reinforcement Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                      ReinforcementManager                           │
│                      (Autoload Singleton)                           │
├─────────────────────────────────────────────────────────────────────┤
│  + request_reinforcement(unit_type, delivery_mode) -> ReinforcementRequest │
│  + get_pending_requests() -> Array[ReinforcementRequest]            │
│  + cancel_request(request_id) -> bool                               │
│  + get_available_units(faction) -> Array[UnitCardData]              │
├─────────────────────────────────────────────────────────────────────┤
│  Signals: reinforcement_requested, reinforcement_arriving,          │
│           reinforcement_delivered, reinforcement_intercepted        │
└─────────────────────────────────────────────────────────────────────┘
          ▲
          │ manages
          │
┌─────────────────────────────────────────────────────────────────────┐
│                      ReinforcementRequest                           │
├─────────────────────────────────────────────────────────────────────┤
│  + id: int                                                          │
│  + unit_card: UnitCardData                                          │
│  + delivery_mode: DeliveryMode (HELICOPTER, CONVOY)                 │
│  + destination: Node3D (firebase or LZ)                             │
│  + eta_seconds: float                                               │
│  + state: RequestState (PENDING, EN_ROUTE, DELIVERED, INTERCEPTED)  │
└─────────────────────────────────────────────────────────────────────┘
```

### No In-Firebase Production (TR-SYS-050)

```gdscript
## ReinforcementManager.gd - Autoload singleton

class_name ReinforcementManager extends Node

## Reinforcement cannot be spawned locally at firebases
## All units come from off-map sources via physical delivery

enum DeliveryMode {
    HELICOPTER,  # Fast, requires LZ, vulnerable to AAA
    CONVOY,      # Slow, requires road, high capacity, ambush-vulnerable
}

enum RequestState {
    PENDING,     # Queued, waiting for transport
    EN_ROUTE,    # Transport dispatched, traveling to destination
    DELIVERED,   # Successfully arrived
    INTERCEPTED, # Destroyed en route (ambush, shot down)
    CANCELLED,   # Player cancelled request
}

## Active reinforcement requests
var _active_requests: Dictionary = {}  # request_id -> ReinforcementRequest
var _next_request_id: int = 1

## Faction delivery assets
var _available_helicopters: Dictionary = {}  # faction -> count
var _available_convoys: Dictionary = {}       # faction -> count

func _ready() -> void:
    BattleSignals.unit_died.connect(_on_unit_died)
    BattleSignals.transport_destroyed.connect(_on_transport_destroyed)
```

### Reinforcement Request Flow (TR-SYS-051)

```gdscript
## Request reinforcement - returns request object for tracking
func request_reinforcement(
    unit_card: UnitCardData,
    delivery_mode: DeliveryMode,
    destination: Node3D,
    faction: GameEnums.Faction
) -> ReinforcementRequest:

    # Validate unit is available in deck
    if not _is_unit_available(unit_card, faction):
        push_warning("Unit not available in deck: %s" % unit_card.unit_name)
        return null

    # Check delivery mode is valid for this unit
    if not _can_deliver_via(unit_card, delivery_mode):
        push_warning("Cannot deliver %s via %s" % [unit_card.unit_name, delivery_mode])
        return null

    # Check delivery asset availability
    if delivery_mode == DeliveryMode.HELICOPTER:
        if _available_helicopters.get(faction, 0) <= 0:
            BattleSignals.reinforcement_blocked.emit("No helicopters available")
            return null

    # Create request
    var request := ReinforcementRequest.new()
    request.id = _next_request_id
    _next_request_id += 1
    request.unit_card = unit_card
    request.delivery_mode = delivery_mode
    request.destination = destination
    request.faction = faction
    request.state = RequestState.PENDING

    # Calculate ETA based on delivery mode and unit type (TR-SYS-052)
    request.eta_seconds = _calculate_eta(unit_card, delivery_mode, destination, faction)
    request.time_requested = Time.get_ticks_msec() / 1000.0

    _active_requests[request.id] = request

    # Start delivery timer
    _dispatch_delivery(request)

    BattleSignals.reinforcement_requested.emit(request)
    return request

## ETA calculation based on unit type (TR-SYS-052)
func _calculate_eta(
    unit_card: UnitCardData,
    delivery_mode: DeliveryMode,
    destination: Node3D,
    faction: GameEnums.Faction
) -> float:

    # Base times from TR-SYS-052
    var base_time: float
    match unit_card.unit_category:
        UnitCategory.INFANTRY:
            base_time = randf_range(180.0, 300.0)  # 3-5 minutes
        UnitCategory.SPECIALIST:
            base_time = randf_range(300.0, 420.0)  # 5-7 minutes
        UnitCategory.ARMOR:
            base_time = randf_range(600.0, 900.0)  # 10-15 minutes
        UnitCategory.VEHICLE:
            base_time = randf_range(360.0, 480.0)  # 6-8 minutes
        _:
            base_time = 300.0  # Default 5 min

    # Delivery mode modifiers
    match delivery_mode:
        DeliveryMode.HELICOPTER:
            base_time *= 0.7  # Faster delivery
        DeliveryMode.CONVOY:
            base_time *= 1.2  # Slower, road-dependent

    # Apply doctrine modifiers (from DoctrineManager)
    var doctrine_modifier := DoctrineManager.get_reinforcement_modifier(
        faction,
        delivery_mode
    )
    base_time *= doctrine_modifier

    return base_time
```

### Physical Delivery System (TR-SYS-051, TR-SYS-053)

```gdscript
## Spawn physical transport carrying reinforcement
func _dispatch_delivery(request: ReinforcementRequest) -> void:
    request.state = RequestState.EN_ROUTE

    match request.delivery_mode:
        DeliveryMode.HELICOPTER:
            _dispatch_helicopter(request)
        DeliveryMode.CONVOY:
            _dispatch_convoy(request)

func _dispatch_helicopter(request: ReinforcementRequest) -> void:
    # Reserve helicopter
    _available_helicopters[request.faction] -= 1

    # Spawn helicopter at off-map spawn point
    var spawn_point := _get_offmap_spawn(request.faction, "airbase")
    var heli := _spawn_transport_helicopter(request.unit_card, spawn_point)

    # Set destination to LZ
    var lz := _find_suitable_lz(request.destination, request.faction)
    if not lz:
        push_warning("No suitable LZ for reinforcement")
        request.state = RequestState.CANCELLED
        _available_helicopters[request.faction] += 1
        return

    heli.set_mission(HeliMission.TROOP_INSERTION, {
        "destination_lz": lz,
        "cargo": request.unit_card,
        "request_id": request.id,
    })

    request.transport = heli
    BattleSignals.reinforcement_en_route.emit(request, heli)

func _dispatch_convoy(request: ReinforcementRequest) -> void:
    # Reserve convoy slot
    _available_convoys[request.faction] -= 1

    # Spawn convoy at off-map road entry
    var spawn_point := _get_offmap_spawn(request.faction, "road_entry")
    var convoy := _spawn_convoy(request.unit_card, spawn_point)

    # Calculate route to destination firebase
    var route := RoadNetwork.get_route_to(
        spawn_point.global_position,
        request.destination.global_position
    )

    if route.is_empty():
        push_warning("No road route to destination")
        request.state = RequestState.CANCELLED
        _available_convoys[request.faction] += 1
        return

    convoy.set_route(route)
    convoy.set_cargo(request.unit_card, request.id)

    request.transport = convoy
    BattleSignals.reinforcement_en_route.emit(request, convoy)
```

### Transport Vulnerability (TR-SYS-053)

```gdscript
## When transport is destroyed, reinforcement is lost
func _on_transport_destroyed(transport: Node3D) -> void:
    # Find associated request
    for request in _active_requests.values():
        if request.transport == transport:
            request.state = RequestState.INTERCEPTED

            # Return transport slot
            match request.delivery_mode:
                DeliveryMode.HELICOPTER:
                    # Helicopter lost - doesn't return to pool
                    pass
                DeliveryMode.CONVOY:
                    # Convoy destroyed
                    pass

            # Emit intercepted signal for UI/audio
            BattleSignals.reinforcement_intercepted.emit(
                request,
                transport.global_position
            )

            # Play audio callout
            AudioManager.play_voice(
                request.faction,
                "reinforcement_lost"
            )

            # Remove from active requests
            _active_requests.erase(request.id)
            return

## When transport arrives successfully
func _on_transport_arrived(transport: Node3D, request_id: int) -> void:
    var request: ReinforcementRequest = _active_requests.get(request_id)
    if not request:
        return

    request.state = RequestState.DELIVERED

    # Spawn the actual unit at destination
    var unit := UnitFactory.spawn_unit(
        request.unit_card,
        transport.global_position,
        request.faction
    )

    # Return transport asset
    match request.delivery_mode:
        DeliveryMode.HELICOPTER:
            # Helicopter returns to base (handled by HeliMission system)
            _available_helicopters[request.faction] += 1
        DeliveryMode.CONVOY:
            # Convoy returns empty
            _available_convoys[request.faction] += 1

    BattleSignals.reinforcement_delivered.emit(request, unit)

    # Audio callout
    AudioManager.play_voice(request.faction, "reinforcement_arrived")

    _active_requests.erase(request_id)
```

### Deck Card System (TR-SYS-054, TR-SYS-055, TR-SYS-056)

```gdscript
## UnitCardData.gd - Resource defining what units can be requested

class_name UnitCardData extends Resource

@export var unit_id: String
@export var unit_name: String
@export var unit_scene: PackedScene
@export var unit_category: UnitCategory

## Deck management
@export var max_in_deck: int = 3              # How many copies allowed
@export var reinforcement_cost: int = 100     # Supply cost to request
@export var deployment_count: int = 1         # Units spawned per request

## Required buildings (TR-SYS-055)
## If this card is in deck, these buildings are auto-unlocked
@export var required_buildings: Array[BuildingData] = []

## Delivery restrictions
@export var can_deliver_helicopter: bool = true
@export var can_deliver_convoy: bool = true

## Faction restrictions
@export var allowed_factions: Array[GameEnums.Faction] = [GameEnums.Faction.US_ARMY]
```

```gdscript
## DeckManager.gd - Manages player's force composition deck

class_name DeckManager extends Node

## Player's selected cards for this mission
var _player_deck: Dictionary = {}  # unit_id -> {card: UnitCardData, available: int}

## Buildings unlocked by deck cards
var _unlocked_buildings: Array[BuildingData] = []

## Flexible building slots (TR-SYS-056)
var _flexible_slots: Array[BuildingData] = []
const MAX_FLEXIBLE_SLOTS := 6

func build_deck(doctrine: DoctrineData, selected_cards: Array[UnitCardData]) -> void:
    _player_deck.clear()
    _unlocked_buildings.clear()

    # Add doctrine's base units
    for card in doctrine.base_units:
        _add_card_to_deck(card)

    # Add player-selected cards
    for card in selected_cards:
        if _can_add_card(card, doctrine):
            _add_card_to_deck(card)

    # Collect all required buildings from cards (TR-SYS-055)
    for entry in _player_deck.values():
        var card: UnitCardData = entry.card
        for building in card.required_buildings:
            if building not in _unlocked_buildings:
                _unlocked_buildings.append(building)

    # Add flexible building slots from doctrine
    _flexible_slots = doctrine.flexible_buildings.duplicate()

func _add_card_to_deck(card: UnitCardData) -> void:
    if card.unit_id in _player_deck:
        # Add more copies
        _player_deck[card.unit_id].available += card.max_in_deck
    else:
        _player_deck[card.unit_id] = {
            "card": card,
            "available": card.max_in_deck,
            "deployed": 0,
        }

func get_available_units() -> Array[UnitCardData]:
    """Get all units that can currently be requested"""
    var available: Array[UnitCardData] = []
    for entry in _player_deck.values():
        if entry.available > 0:
            available.append(entry.card)
    return available

func consume_unit_card(unit_id: String) -> bool:
    """Called when reinforcement is requested - decrements available count"""
    if unit_id not in _player_deck:
        return false
    if _player_deck[unit_id].available <= 0:
        return false

    _player_deck[unit_id].available -= 1
    _player_deck[unit_id].deployed += 1
    return true

func return_unit_card(unit_id: String) -> void:
    """Called when unit dies - card returns to deck after cooldown"""
    if unit_id in _player_deck:
        # Card returns after reinforcement cooldown (handled by ReinforcementManager)
        _player_deck[unit_id].deployed -= 1
```

### Reinforcement UI Integration

```gdscript
## ReinforcementPanel.gd - UI for requesting reinforcements

class_name ReinforcementPanel extends Control

@onready var _unit_list: ItemList = $UnitList
@onready var _eta_label: Label = $ETALabel
@onready var _delivery_options: OptionButton = $DeliveryOptions
@onready var _request_button: Button = $RequestButton
@onready var _pending_list: VBoxContainer = $PendingList

var _selected_card: UnitCardData

func _ready() -> void:
    ReinforcementManager.reinforcement_requested.connect(_on_reinforcement_requested)
    ReinforcementManager.reinforcement_delivered.connect(_on_reinforcement_delivered)
    _refresh_available_units()

func _refresh_available_units() -> void:
    _unit_list.clear()
    var available := DeckManager.get_available_units()
    for card in available:
        var item_idx := _unit_list.add_item(card.unit_name)
        _unit_list.set_item_metadata(item_idx, card)

func _on_unit_selected(index: int) -> void:
    _selected_card = _unit_list.get_item_metadata(index)
    _update_delivery_options()
    _update_eta_preview()

func _update_eta_preview() -> void:
    if not _selected_card:
        return

    var delivery_mode := _get_selected_delivery_mode()
    var eta := ReinforcementManager.estimate_eta(
        _selected_card,
        delivery_mode,
        PlayerController.get_active_firebase()
    )

    var minutes := int(eta / 60.0)
    var seconds := int(eta) % 60
    _eta_label.text = "ETA: %d:%02d" % [minutes, seconds]

func _on_request_pressed() -> void:
    if not _selected_card:
        return

    var destination := PlayerController.get_active_firebase()
    var delivery_mode := _get_selected_delivery_mode()

    var request := ReinforcementManager.request_reinforcement(
        _selected_card,
        delivery_mode,
        destination,
        PlayerController.get_faction()
    )

    if request:
        _refresh_available_units()
        _add_pending_request_ui(request)
```

### Serialization Support

```gdscript
## ReinforcementManager serialization
func serialize() -> Dictionary:
    var requests_data: Array = []
    for request in _active_requests.values():
        requests_data.append(request.serialize())

    return {
        "_version": 1,
        "_system": "ReinforcementManager",
        "next_request_id": _next_request_id,
        "active_requests": requests_data,
        "available_helicopters": _available_helicopters.duplicate(),
        "available_convoys": _available_convoys.duplicate(),
    }

func deserialize(data: Dictionary) -> bool:
    if data.get("_version", 0) != 1:
        return false

    _next_request_id = data.get("next_request_id", 1)
    _available_helicopters = data.get("available_helicopters", {})
    _available_convoys = data.get("available_convoys", {})

    # Recreate active requests
    _active_requests.clear()
    for request_data in data.get("active_requests", []):
        var request := ReinforcementRequest.new()
        if request.deserialize(request_data):
            _active_requests[request.id] = request
            # Re-dispatch if was en route
            if request.state == RequestState.EN_ROUTE:
                _resume_delivery(request)

    return true
```

## Consequences

### Positive
- **Force preservation matters**: Losing units has real cost (TR-SYS-053)
- **No production spam**: Can't overwhelm with numbers (TR-SYS-050)
- **Physical logistics**: Reinforcements can be intercepted (TR-SYS-051)
- **Deck planning**: Pre-mission choices affect in-mission options (TR-SYS-054)
- **Building integration**: Unit cards unlock required buildings (TR-SYS-055)

### Negative
- **Player frustration**: Waiting minutes for replacements can feel punishing
- **Transport balance**: Helicopters vs convoys must feel meaningfully different
- **Deck complexity**: New players may not understand card limits

### Mitigations
- Clear ETA display in UI
- Multiple pending requests allowed
- Audio callouts for arrival/interception
- Tutorial explains deck building

## ADR Dependencies

- **ADR-0006 (Supply Chain)**: Supply costs for reinforcements
- **ADR-0008 (Serialization)**: Request state persistence
- **ADR-0009 (Firebase Placement)**: Destination validation
- **ADR-0015 (Doctrine System)**: Doctrine modifiers for timing

## Engine Compatibility

**Godot 4.6** - Pure GDScript, Resource-based card definitions.

## GDD Requirements Addressed

| Requirement | How Addressed |
|-------------|---------------|
| TR-SYS-050 | No spawn buildings, all via ReinforcementManager |
| TR-SYS-051 | `_dispatch_helicopter()` and `_dispatch_convoy()` physical delivery |
| TR-SYS-052 | `_calculate_eta()` with category-based timing ranges |
| TR-SYS-053 | `_on_transport_destroyed()` loses reinforcement, wait for next |
| TR-SYS-054 | `DeckManager.get_available_units()` filtered by deck |
| TR-SYS-055 | `UnitCardData.required_buildings` auto-unlocks |
| TR-SYS-056 | `DeckManager._flexible_slots` from doctrine |

## Implementation Files

| File | Purpose |
|------|---------|
| `reinforcement_system/reinforcement_manager.gd` | Main autoload singleton |
| `reinforcement_system/reinforcement_request.gd` | Request data class |
| `reinforcement_system/unit_card_data.gd` | Card resource definition |
| `reinforcement_system/deck_manager.gd` | Deck building and tracking |
| `ui/reinforcement_panel.gd` | Player UI for requesting |

## Key Signals

```gdscript
## BattleSignals additions for reinforcements
signal reinforcement_requested(request: ReinforcementRequest)
signal reinforcement_en_route(request: ReinforcementRequest, transport: Node3D)
signal reinforcement_delivered(request: ReinforcementRequest, unit: Node3D)
signal reinforcement_intercepted(request: ReinforcementRequest, position: Vector3)
signal reinforcement_blocked(reason: String)
signal deck_card_consumed(unit_id: String)
signal deck_card_returned(unit_id: String)
```

## Validation Criteria

- [ ] Cannot spawn units at firebase buildings
- [ ] Infantry reinforcement takes 3-5 minutes
- [ ] Armor reinforcement takes 10-15 minutes
- [ ] Helicopter delivery is faster than convoy
- [ ] Destroyed transport loses reinforcement
- [ ] Unit cards in deck unlock required buildings
- [ ] Flexible slots limited to 4-6 per doctrine
- [ ] ETA countdown displays in UI
