"""
Blender S3O to GLB Batch Converter for Vietnam RTS
Run this script in Blender with the S3O plugin installed:
  blender --background --python convert_s3o_to_glb.py
"""

import bpy
import os
import sys

# Source files to convert (S3O path -> output name)
CONVERSIONS = {
    # Mortar Pit
    r"C:\Users\caleb\spring1944-models\FRAInfantry\s3o\FRAMortar.s3o": "mortar_pit.glb",
    r"C:\Users\caleb\spring1944-models\FRAInfantry\s3o\FRASandbagMG.s3o": "sandbag_mg_alt.glb",

    # Supply/Storage structures
    r"C:\Users\caleb\spring1944-game\objects3d\GEN\SupplyDepot.S3O": "fuel_depot.glb",
    r"C:\Users\caleb\spring1944-game\objects3d\GEN\Storage.S3O": "storage_small.glb",
    r"C:\Users\caleb\spring1944-game\objects3d\HUN\HUNFortifiedStorage.s3o": "fortified_storage.glb",
    r"C:\Users\caleb\spring1944-game\objects3d\HUN\HUNStorage.s3o": "storage_large.glb",

    # Tank shelter
    r"C:\Users\caleb\spring1944-game\objects3d\GEN\SmallTankShelter.s3o": "tank_revetment.glb",

    # Tent for medical station
    r"C:\Users\caleb\spring1944-game\objects3d\JPN\JPNTent.s3o": "medical_tent.glb",

    # Landing zone
    r"C:\Users\caleb\spring1944-game\objects3d\GBR\GBRLZ.S3O": "helipad.glb",

    # Mines for claymore
    r"C:\Users\caleb\spring1944-game\objects3d\GEN\APMine.S3O": "ap_mine.glb",
    r"C:\Users\caleb\spring1944-game\objects3d\GEN\ATMine.S3O": "at_mine.glb",

    # Radar/tower
    r"C:\Users\caleb\spring1944-game\objects3d\GBR\GBRRadar.S3O": "radar_tower.glb",
    r"C:\Users\caleb\spring1944-game\objects3d\US\USRadar.S3O": "us_radar.glb",

    # Tank obstacle
    r"C:\Users\caleb\spring1944-game\objects3d\GEN\TankObstacle.S3O": "tank_obstacle.glb",

    # Additional barracks/HQ variants
    r"C:\Users\caleb\spring1944-game\objects3d\GBR\GBRBarracks.S3O": "barracks_gbr.glb",
    r"C:\Users\caleb\spring1944-game\objects3d\GBR\GBRHQ.S3O": "hq_gbr.glb",
    r"C:\Users\caleb\spring1944-game\objects3d\GER\GERStorageBunker.S3O": "storage_bunker.glb",

    # Gun emplacements (for artillery pit reference)
    r"C:\Users\caleb\spring1944-models\USM1_45InGun\s3o\USM1_45inGun_stationary.s3o": "us_gun_emplacement.glb",
    r"C:\Users\caleb\spring1944-game\objects3d\GBR\GBR45inGun_stationary.s3o": "gbr_gun_emplacement.glb",
}

OUTPUT_DIR = r"C:\Users\caleb\RealVietnamRTS\assets\models\structures\converted"


def clear_scene():
    """Remove all objects from scene"""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

    # Also clear orphan data
    for block in bpy.data.meshes:
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in bpy.data.materials:
        if block.users == 0:
            bpy.data.materials.remove(block)


def import_s3o(filepath):
    """Import S3O file using the S3O plugin"""
    try:
        # The S3O importer operator name may vary based on plugin version
        # Common names: import_scene.s3o, import_mesh.s3o
        if hasattr(bpy.ops.import_scene, 's3o'):
            bpy.ops.import_scene.s3o(filepath=filepath)
            return True
        elif hasattr(bpy.ops.import_mesh, 's3o'):
            bpy.ops.import_mesh.s3o(filepath=filepath)
            return True
        else:
            print(f"ERROR: S3O import operator not found. Is the S3O plugin installed?")
            return False
    except Exception as e:
        print(f"ERROR importing {filepath}: {e}")
        return False


def export_glb(filepath):
    """Export scene as GLB"""
    try:
        bpy.ops.export_scene.gltf(
            filepath=filepath,
            export_format='GLB',
            use_selection=False,
            export_apply=True,
            export_texcoords=True,
            export_normals=True,
            export_materials='EXPORT',
        )
        return True
    except Exception as e:
        print(f"ERROR exporting {filepath}: {e}")
        return False


def convert_file(s3o_path, output_name):
    """Convert a single S3O file to GLB"""
    if not os.path.exists(s3o_path):
        print(f"SKIP: File not found: {s3o_path}")
        return False

    print(f"Converting: {os.path.basename(s3o_path)} -> {output_name}")

    # Clear scene
    clear_scene()

    # Import S3O
    if not import_s3o(s3o_path):
        return False

    # Center and normalize
    bpy.ops.object.select_all(action='SELECT')
    if bpy.context.selected_objects:
        bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')

        # Move to origin
        for obj in bpy.context.selected_objects:
            obj.location = (0, 0, 0)

    # Export GLB
    output_path = os.path.join(OUTPUT_DIR, output_name)
    return export_glb(output_path)


def main():
    # Create output directory
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("=" * 60)
    print("S3O to GLB Batch Converter")
    print("=" * 60)

    success_count = 0
    fail_count = 0

    for s3o_path, output_name in CONVERSIONS.items():
        if convert_file(s3o_path, output_name):
            success_count += 1
        else:
            fail_count += 1

    print("=" * 60)
    print(f"Conversion complete: {success_count} success, {fail_count} failed")
    print(f"Output directory: {OUTPUT_DIR}")
    print("=" * 60)


if __name__ == "__main__":
    main()
