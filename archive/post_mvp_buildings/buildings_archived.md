# Post-MVP Building Reference

## Date: 2026-05-13

## MVP Buildings (14 total)

### US Player-Buildable (10):
1. SANDBAG_WALL - Basic defensive cover
2. BUNKER - Hardened fighting position
3. MACHINE_GUN_NEST - M60 emplacement
4. MORTAR_PIT - 81mm indirect fire
5. WIRE_OBSTACLE - Concertina wire barrier
6. WATCHTOWER - Elevated observation
7. HELIPAD - Landing zone
8. AMMO_BUNKER - Resupply point
9. TOC - Command center (Tactical Operations Center)
10. OBSERVATION_TOWER - Elevated lookout

### VC Map Features (4):
1. TUNNEL_ENTRANCE_HIDDEN - Camouflaged tunnel access
2. SPIDER_HOLE - One-man fighting position
3. WEAPONS_CACHE - Hidden supplies
4. PUNJI_PIT - Concealed spike trap

## Current Build Menu
The build_menu.gd currently exposes 13 buildings which is acceptable for MVP:
- Perimeter: SANDBAG_WALL, BUNKER, MACHINE_GUN_NEST, MORTAR_PIT, WIRE_OBSTACLE, WATCHTOWER
- Support: HELIPAD, AMMO_BUNKER, MEDICAL_STATION, TOC, COMMO_BUNKER
- Heavy: ARTILLERY_PIT, TANK_REVETMENT

## Post-MVP Buildings (100+)
The following building types exist in BuildingData.gd but are not exposed in MVP:

### Firebase Living (7):
HOOTCH, MESS_HALL, LATRINE, SHOWER_POINT, GUARD_TOWER, POWDER_BUNKER

### Additional Firebase (10):
SANDBAG_BUNKER, CONEX_BUNKER, TRIPLE_CONCERTINA, CLAYMORE_LINE, PSP_HELIPAD, VIP_HELIPAD, HELICOPTER_REVETMENT, FUEL_DEPOT, FUEL_POINT, HOWITZER_PIT_105MM, HOWITZER_PIT_155MM, FIRE_DIRECTION_CENTER, OPEN_REVETMENT

### Vietnamese Village (15):
THATCHED_HUT, CLAY_WALL_COTTAGE, STILT_HOUSE, THREE_ROOM_HOUSE, COMMUNAL_HOUSE, VILLAGE_WELL, RICE_STORAGE_SHED, WATER_BUFFALO_SHED, BAMBOO_FENCE, VILLAGE_GATE, VILLAGE_PAGODA, TAM_QUAN_GATE, BELL_TOWER, MONK_QUARTERS, STONE_BUDDHA

### Airfield (19):
All runway, taxiway, hangar, and support structures

### French Colonial (9):
COLONIAL_VILLA, PLANTATION_HOUSE, GOVERNMENT_BUILDING, etc.

### Infrastructure (11):
Bridges, roads, docks, cranes

### VC/NVA (8):
TUNNEL_ENTRANCE_EXPOSED, UNDERGROUND_HOSPITAL, STOCKADE_COMPOUND, PRISONER_TENT

### Ruins (12):
All destruction variants

### Cham Ruins (3):
Ancient temple structures

### Commercial (4):
Marketplace buildings

## Integration Plan
When expanding beyond MVP, add buildings to build_menu.gd by category as needed.
