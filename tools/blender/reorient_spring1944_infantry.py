# Blender Script: Reorient Spring 1944 Infantry Models for Godot
#
# This script fixes the axis orientation of S3O-converted infantry models
# so they work correctly with Spring 1944's procedural animation system.
#
# Usage:
# 1. Open the infantry .glb file in Blender
# 2. Run this script (Text Editor > Run Script)
# 3. Export as GLB with default settings
#
# Spring 1944 uses:
#   - Z-up coordinate system
#   - Pieces expect rotations around local axes
#   - Positive X rotation = pitch forward
#   - Positive Y rotation = yaw right
#   - Positive Z rotation = roll clockwise
#
# GLB/Godot uses:
#   - Y-up coordinate system
#   - Different rotation conventions

import bpy
import math
from mathutils import Matrix, Euler

# Spring 1944 piece names
PIECE_NAMES = [
    "pelvis", "torso", "head",
    "luparm", "lloarm", "ruparm", "rloarm",
    "lthigh", "lleg", "lfoot",
    "rthigh", "rleg", "rfoot",
    "gun", "flare", "ground"
]

def find_piece_objects():
    """Find all objects that match Spring 1944 piece names"""
    pieces = {}
    for obj in bpy.data.objects:
        name_lower = obj.name.lower()
        for piece_name in PIECE_NAMES:
            if name_lower == piece_name or name_lower.endswith("_" + piece_name) or name_lower.startswith(piece_name + "_"):
                pieces[piece_name] = obj
                print(f"Found piece: {piece_name} -> {obj.name}")
    return pieces

def reorient_for_spring1944():
    """
    Reorient pieces to match Spring 1944's axis expectations.

    Spring 1944 expects:
    - Pieces oriented so their "forward" is along local -Y in Spring coords
    - Which translates to -Z in Godot/Blender Y-up coords

    The S3O export may have pieces in different orientations.
    This applies a correction rotation to each piece.
    """
    pieces = find_piece_objects()

    if not pieces:
        print("ERROR: No Spring 1944 pieces found in scene!")
        print("Make sure you have objects named: pelvis, torso, head, etc.")
        return

    print(f"\nFound {len(pieces)} pieces")
    print("\nReorienting pieces for Spring 1944 animation compatibility...")

    # The correction needed depends on how the S3O was exported
    # Common fix: rotate 90 degrees around X to convert Z-up to Y-up
    # And possibly negate certain axes

    # Try: Apply a -90 degree X rotation to convert coordinate systems
    correction_matrix = Matrix.Rotation(math.radians(-90), 4, 'X')

    for piece_name, obj in pieces.items():
        # Store original parent and matrix
        original_parent = obj.parent
        original_matrix = obj.matrix_world.copy()

        # For the root piece (usually pelvis), apply coordinate system correction
        if piece_name == "pelvis":
            # Apply the correction to convert from S3O Z-up to Godot Y-up
            obj.rotation_euler.x += math.radians(-90)
            print(f"  Applied -90 X rotation to root: {obj.name}")

        # For child pieces, we may need to adjust their local orientations
        # This depends on how the hierarchy was set up in the original S3O

    print("\nReorientation complete!")
    print("\nNext steps:")
    print("1. Check the model looks correct in Blender viewport")
    print("2. If pieces look wrong, undo and try the alternative method below")
    print("3. Export as GLB: File > Export > glTF 2.0")
    print("   - Use default Y-up settings")
    print("   - Check 'Apply Modifiers' if needed")

def apply_transforms_to_pieces():
    """
    Alternative: Apply all transforms to pieces so they have identity rotation.
    This bakes the current rotation into the mesh vertices.
    """
    pieces = find_piece_objects()

    for piece_name, obj in pieces.items():
        # Select only this object
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj

        # Apply rotation (bakes it into mesh)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        print(f"  Applied transforms to: {obj.name}")

    print("\nTransforms applied! Pieces now have zero rotation as their rest pose.")

def reset_to_rest_pose():
    """Reset all pieces to zero rotation (their rest pose)"""
    pieces = find_piece_objects()

    for piece_name, obj in pieces.items():
        obj.rotation_euler = Euler((0, 0, 0))
        print(f"  Reset rotation: {obj.name}")

    print("\nAll pieces reset to rest pose (zero rotation)")

def print_piece_info():
    """Debug: Print information about all pieces"""
    pieces = find_piece_objects()

    print("\n=== Piece Information ===")
    for piece_name, obj in pieces.items():
        rot = obj.rotation_euler
        print(f"{piece_name}:")
        print(f"  Object: {obj.name}")
        print(f"  Rotation (deg): X={math.degrees(rot.x):.1f}, Y={math.degrees(rot.y):.1f}, Z={math.degrees(rot.z):.1f}")
        print(f"  Parent: {obj.parent.name if obj.parent else 'None'}")

# Menu for user to choose action
print("\n" + "="*50)
print("Spring 1944 Infantry Model Reorientation Tool")
print("="*50)
print("\nAvailable functions (run in Blender Python console):")
print("  reorient_for_spring1944()  - Apply coordinate system fix")
print("  apply_transforms_to_pieces() - Bake rotations into meshes")
print("  reset_to_rest_pose()       - Zero all rotations")
print("  print_piece_info()         - Show current piece rotations")
print("\nRunning print_piece_info() to show current state...")
print_piece_info()
