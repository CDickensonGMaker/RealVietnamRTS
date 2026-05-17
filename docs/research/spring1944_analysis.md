# Spring 1944 Code Structure Analysis

## Overview
Spring 1944 is a WW2 RTS built on the Spring Engine using Lua. Its design provides excellent reference for infantry-focused combat systems.

## Key Architecture Patterns

### 1. Unit Inheritance System
Units use a class-based inheritance pattern:
```lua
local Infantry = Unit:New{ ... }
local RifleInf = Infantry:New{ ... }
local SMGInf = Infantry:New{ ... }
```

**Base Infantry properties:**
- `damageModifier = 0.265` - Reduces incoming damage
- `flankingBonusMax = 1.5` - 50% more damage when flanking
- `flankingBonusMin = 0.675` - Minimum damage multiplier from front
- `stealth = true` - Infantry can hide

### 2. Squad Composition System
Squads are defined as arrays of individual unit types:
```lua
["us_platoon_rifle"] = {
    members = {
        "usthompson", "usthompson",
        "usrifle", "usrifle", "usrifle", "usrifle",
        "usrifle", "usrifle", "usrifle", "usrifle",
        "usbar", "usbar",
    },
    name = "Rifle Platoon",
    description = "8 x Garand Rifle, 2 x Thompson SMG, 2 x BAR",
    buildCostMetal = 1675,
}
```

**Squad Types:**
- Rifle Platoon (12 men)
- Assault Platoon (12 men, SMG-heavy)
- MG Squad (3 MGs + 1 Scout)
- Mortar Team (3 mortars + 1 Scout)
- Sniper Team (1 sniper + 1 Scout)
- AT Squad (3 bazookas)
- Flamethrower Squad (4 flamethrowers)
- Pioneer Squad (mixed heavy weapons)

### 3. Weapon Data Structure
Weapons use inheritance with damage types:
```lua
local SmallArm = Weapon:New{
    accuracy = 100,
    weaponVelocity = 1500,
    customparams = {
        damagetype = "smallarm",
        onlytargetcategory = "INFANTRY SOFTVEH DEPLOYED",
    },
}

local RifleClass = SmallArm:New{
    accuracy = 210,
    range = 450,
    reloadtime = 1.3,
    damage = { default = 33 },
}
```

**Damage Types:**
- `smallarm` - Rifles, SMGs, pistols
- Custom types for explosives, cannons, etc.

### 4. Fear/Suppression System (game_fearHandler.lua)

**Fear IDs (suppression strength):**
- 301: Small arms (MGs, snipers, 20mm) - fear value 2
- 401: Small explosions (mortars, <=88mm) - fear value 4
- 501: Large explosions (bombs, 105-155mm) - fear value 8
- 601: Massive explosions (heavy bombs, 170mm+) - fear value 16

**Suppression Mechanics:**
1. Weapons have `fearaoe` (area of effect) and `fearid` (intensity)
2. Units in fear AOE receive suppression based on fear ID
3. Suppressed units go prone (hitbox adjusted lower)
4. Suppression decays over time (~1.5 seconds per check)
5. "Fear shields" - NCOs/commanders block fear for nearby friendlies
6. Smoke also blocks fear

**Collision Adjustment When Suppressed:**
```lua
-- When suppressed, lower the hitbox
local sphereMult = 0.4  -- 40% of normal height
Spring.SetUnitCollisionVolumeData(unitID, scaleX, scaleY, scaleZ,
    offsetX, offsetY + direction * scaleY * sphereMult, offsetZ, ...)
```

### 5. Engineer System
Engineers have special capabilities:
```lua
local EngineerInf = Infantry:New{
    builder = true,
    canRestore = true,
    canRepair = true,
    canReclaim = true,
    terraformSpeed = 300,
    workerTime = 15,
    customParams = { canclearmines = true },
}
```

### 6. Unit Categories
Units belong to categories for targeting:
- `INFANTRY` - Ground troops
- `MINETRIGGER` - Units that trigger mines
- `SOFTVEH` - Soft vehicles
- `OPENVEH` - Open-top vehicles
- `DEPLOYED` - Static deployed weapons
- `AIR` - Aircraft

## Applicability to RealVietnamRTS

### Immediately Applicable:
1. **Squad composition system** - Use arrays to define squad makeup
2. **Suppression/fear system** - Implement fear IDs and AOE
3. **Prone state when suppressed** - Lower hitbox
4. **Fear shields** - NCOs reduce suppression on nearby units

### Adaptation Needed:
1. **Weapon data** - Convert Lua tables to GDScript Resources
2. **Fear decay** - Implement in _physics_process
3. **Unit categories** - Already have faction groups, extend to role groups

## Implementation Recommendations

### Suppression System Enhancement
```gdscript
# In Squad class
const FEAR_IDS = {
    "smallarm": 2,
    "mortar": 4,
    "artillery": 8,
    "napalm": 16
}

func apply_suppression(amount: float, source_type: String) -> void:
    var fear_mult = FEAR_IDS.get(source_type, 2)
    suppression_level += amount * fear_mult * 0.01
    suppression_level = minf(suppression_level, 1.0)

    if suppression_level > 0.3 and not is_prone:
        _go_prone()
```

### NCO Fear Shield
```gdscript
# Officers/NCOs reduce fear for nearby units
var fear_shield_radius: float = 10.0
var fear_reduction: float = 0.5  # 50% fear reduction

func _process_morale_aura() -> void:
    var nearby = SpatialHashGrid.get_friendlies_in_radius(
        global_position, fear_shield_radius, faction
    )
    for unit in nearby:
        if unit.has_method("apply_morale_buff"):
            unit.apply_morale_buff(fear_reduction)
```

## Source Files Referenced
- `BaseClasses/Units/Infantry.lua` - Infantry base classes
- `LuaRules/Configs/side_squad_defs/us.lua` - US squad compositions
- `BaseClasses/Weapons/Infantry/SmallArms.lua` - Weapon definitions
- `LuaRules/Gadgets/game_fearHandler.lua` - Suppression system
