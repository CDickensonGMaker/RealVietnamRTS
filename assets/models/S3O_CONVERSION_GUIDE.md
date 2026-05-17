# S3O to Godot Conversion Guide

## Source Models (from Spring 1944)

### US Forces (use French infantry as stand-ins)
| S3O File | Use For | Vietnam Equivalent |
|----------|---------|-------------------|
| FRARifle.s3o | Rifle Platoon | M16 infantry |
| FRAEngineer.s3o | Engineers | Combat engineers |
| FRAMortar.s3o | Weapons Squad | 81mm mortar team |
| FRAHotchkissMle1914.s3o | Weapons Squad | M60 MG team |

### VC Forces (use Finnish infantry as stand-ins)
| S3O File | Use For | Vietnam Equivalent |
|----------|---------|-------------------|
| FINRifle.s3o | VC Infantry | AK-47 guerrillas |
| FINEngineer.s3o | VC Sappers | Tunnel diggers/demo |
| FINMortar.s3o | VC Mortar | 82mm mortar team |
| FINLMG.s3o | VC Infantry | RPD gunner |

### US Vehicles
| S3O File | Use For | Vietnam Equivalent |
|----------|---------|-------------------|
| USJeep.s3o | Light Transport | Jeep/Scout |
| USM3A1Halftrack.s3o | APC | M113 stand-in |
| USM24.s3o | Light Tank | M48 Patton stand-in |

### Structures
| S3O File | Use For |
|----------|---------|
| FRABarracks.s3o | Barracks / HQ building |
| FRABarracksBunker.s3o | Firebase bunker |
| FRAHQ.s3o | Command center / TOC |

## Conversion Pipeline

### Requirements
1. Blender 3.x or 4.x
2. S3O Blender Plugin: https://github.com/FluidPlay/s3o-Blender-plugins-2022

### Steps
1. Install the S3O plugin in Blender (Edit > Preferences > Add-ons > Install)
2. File > Import > Spring S3O
3. Select the .s3o file and corresponding .dds texture
4. Clean up the model:
   - Remove S3O-specific empties/attribute nodes
   - Apply transforms (Ctrl+A > All Transforms)
   - Verify UV mapping
5. Export as GLTF 2.0:
   - File > Export > glTF 2.0 (.glb/.gltf)
   - Format: GLB (binary, single file)
   - Include: Selected Objects, Apply Modifiers
   - Geometry: UVs, Normals, Tangents
6. Import .glb into Godot assets/models/ folder

### Texture Notes
- Spring 1944 uses .dds textures
- May need to convert to .png for Godot compatibility
- Use GIMP or ImageMagick for DDS conversion

## Current Status

### CONVERTED MODELS (GLB format, Ready to Use)

#### US Infantry (from French S3O)
| Model | File | Size | Source |
|-------|------|------|--------|
| Rifle Infantry | `us/infantry/us_rifle_infantry.glb` | 287 KB | FRARifle.s3o |
| Engineer | `us/infantry/us_engineer.glb` | 239 KB | FRAEngineer.s3o |
| Mortar Team | `us/infantry/us_mortar.glb` | 249 KB | FRAMortar.s3o |
| MG Team | `us/infantry/us_mg_team.glb` | 305 KB | FRAHotchkissMle1914.s3o |

#### VC Infantry (from Finnish S3O)
| Model | File | Size | Source |
|-------|------|------|--------|
| Rifle Infantry | `vc/infantry/vc_rifle_infantry.glb` | 242 KB | FINRifle.s3o |
| Sapper | `vc/infantry/vc_sapper.glb` | 231 KB | FINEngineer.s3o |
| Mortar Team | `vc/infantry/vc_mortar.glb` | 244 KB | FINMortar.s3o |
| LMG Gunner | `vc/infantry/vc_lmg.glb` | 242 KB | FINLMG.s3o |

#### US Vehicles (from S3O)
| Model | File | Size | Source |
|-------|------|------|--------|
| Jeep | `vehicles/us_jeep_s3o.glb` | 454 KB | USJeep.s3o |
| Halftrack (APC) | `vehicles/us_halftrack.glb` | 1.1 MB | USM3A1Halftrack.s3o |
| M24 Light Tank | `vehicles/us_m24_tank.glb` | 1.0 MB | USM24.s3o |

#### Structures (from S3O)
| Model | File | Size | Source |
|-------|------|------|--------|
| Barracks | `structures/barracks.glb` | 199 KB | FRABarracks.s3o |
| Fortified Bunker | `structures/barracks_bunker.glb` | 167 KB | FRABarracksBunker.s3o |
| HQ Building | `structures/hq_building.glb` | 165 KB | FRAHQ.s3o |

#### Previously Converted
| Model | File | Size |
|-------|------|------|
| M113 APC | `vehicles/m113_apc.glb` | 1.2 MB |
| UH-1 Huey | `vehicles/uh1_huey.glb` | 39 KB |
| Huey Variant | `huey_helicopter.glb` | 71 KB |

#### Procedural Placeholders (OBJ converted to GLB)
| Model | File | Size |
|-------|------|------|
| US Jeep (OBJ) | `us/vehicles/us_jeep.glb` | 20 KB |
| Sherman Tank (OBJ) | `us/vehicles/us_m4_sherman.glb` | 45 KB |
| US Infantry | `us/infantry/us_infantry.glb` | 5 KB |
| VC Infantry | `vc/infantry/vc_infantry.glb` | 6 KB |
| Bunker | `structures/bunker.glb` | 8 KB |
| Sandbag Wall | `structures/sandbag_wall.glb` | 3 KB |
| MG Nest | `structures/mg_nest.glb` | 4 KB |

### Model Scale Reference
All models scaled for Godot (1 unit = 1 meter):
- Infantry: 1.8m tall
- Jeep: 3.4m long
- Halftrack: 6.0m long
- M24 Tank: 5.5m long
- Barracks: 10m wide
- HQ Building: 12m wide

## S3O Source Files
Location: `assets/models/s3o_source/`

All S3O files have been converted. Source files retained for reference:
- FRAInfantry/ (French infantry - US stand-ins)
- FINInfantry/ (Finnish infantry - VC stand-ins)
- USJeep/, USM24/, USM3A1Halftrack/ (US vehicles)
- FRABunkers/ (Structures)

## Next Steps
1. [x] ~~Convert S3O infantry models to GLB using Blender~~
2. [ ] Apply converted models to squad.gd rendering
3. [x] ~~Convert vehicle S3O models for higher quality than OBJ~~
4. [ ] Create material system to apply DDS-converted textures
5. [ ] Wire up models to unit data resources

## Conversion Complete: May 2026
- 8 infantry models (4 US, 4 VC)
- 3 vehicle models
- 3 structure models
- Total: 14 S3O models converted to GLB
