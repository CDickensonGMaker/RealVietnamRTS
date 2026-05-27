# ADR-0004: Signal Bus Pattern

## Status
Accepted

## Context
- Multiple systems need to communicate (combat, morale, supply, UI)
- Direct references create tight coupling
- Events need multiple listeners (UI, AI, sound)
- Want to avoid spaghetti dependencies

## Decision
- BattleSignals autoload as central signal bus
- All combat/game events go through BattleSignals
- Signal naming: past tense for events (unit_died), present for requests (request_reinforcements)
- Systems emit signals, don't call each other directly
- Listeners connect in _ready()

## Consequences
### Positive
- Loose coupling between systems
- Easy to add new listeners
- Clear event flow
- Testable in isolation

### Negative
- Indirection can obscure flow
- Must manage connection lifecycle
- Signal explosion if not curated

## ADR Dependencies
None (foundational)

## Engine Compatibility
Godot 4.6 - Native signal system, autoload pattern

## GDD Requirements Addressed
- All systems use signals for cross-system communication
- combat-system.md: unit_died, unit_suppressed events
- morale-routing.md: squad_routing, squad_rallied events
