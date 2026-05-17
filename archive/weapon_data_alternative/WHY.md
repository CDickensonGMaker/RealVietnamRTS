# Why This Folder Was Archived

## Date: 2026-05-13

## Reason
This contains an alternative weapon data implementation. The main game uses `battle_system/data/vietnam_weapon_data.gd` instead.

## What Was Here
- `weapon_data.gd` - Weapon stats using @export and GameEnums references

## Differences
- weapon_data.gd uses @export for properties and GameEnums.WeaponClass
- vietnam_weapon_data.gd defines its own enums and has more comprehensive weapon definitions

## Decision
VietnamWeaponData has 40+ weapon definitions with detailed Vietnam-era specifics, making it the better choice for this project.
