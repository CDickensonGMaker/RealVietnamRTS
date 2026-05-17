class_name BuildingPadDecal
extends Decal
## BuildingPadDecal - Simple decal for dirt foundation blending
##
## Uses Godot's built-in Decal node to project a dirt/foundation texture
## onto terrain around building pads. Much simpler than procedural mesh.

## Default dirt color for albedo modulation
const DIRT_COLOR := Color(0.55, 0.45, 0.30, 0.85)

## Padding around footprint for decal extent
const DECAL_PADDING := 2.0


func _init() -> void:
	# Configure decal properties
	cull_mask = 1  # Only affect terrain layer
	upper_fade = 0.1
	lower_fade = 0.5
	normal_fade = 0.3

	# Set modulate to dirt color (texture will be multiplied by this)
	modulate = DIRT_COLOR


## Setup the decal with building footprint data
func setup(footprint_size: Vector2, _corners: Array[Vector3], _pad_height: float, _terrain: Node, _rotation_y: float) -> void:
	# Set decal size to cover footprint plus padding
	var padded_x: float = footprint_size.x + DECAL_PADDING * 2.0
	var padded_z: float = footprint_size.y + DECAL_PADDING * 2.0

	size = Vector3(padded_x, 4.0, padded_z)  # 4m vertical extent

	# Try to load a dirt texture, fall back to procedural
	_setup_texture()


func _setup_texture() -> void:
	# Try to load dirt foundation texture
	var texture_path := "res://assets/textures/terrain/dirt_foundation.png"
	if ResourceLoader.exists(texture_path):
		texture_albedo = load(texture_path)
	else:
		# Create simple procedural gradient texture
		texture_albedo = _create_fallback_texture()


func _create_fallback_texture() -> Texture2D:
	# Create a simple radial gradient texture for blending
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var center := Vector2(32, 32)

	for y in range(64):
		for x in range(64):
			var dist: float = Vector2(x, y).distance_to(center) / 32.0
			var alpha: float = clampf(1.0 - dist, 0.0, 1.0)
			# Soft falloff at edges
			alpha = alpha * alpha
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	return ImageTexture.create_from_image(img)


## Rebuild is a no-op for decal approach (kept for API compatibility)
func rebuild_mesh() -> void:
	pass
