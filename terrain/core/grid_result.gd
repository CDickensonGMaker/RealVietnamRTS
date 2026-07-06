class_name GridResult
extends RefCounted
## GridResult - Result type for coordinate conversions
##
## Provides explicit error handling instead of silent clamping.
## Usage:
##   var result := GridCoords.world_to_gameplay(pos)
##   if result.valid:
##       process_cell(result.coords)
##   else:
##       push_warning(result.error)
##       # Can still use result.coords for clamped fallback

## Whether the conversion was valid (within bounds)
var valid: bool = false

## The resulting grid coordinates (clamped if invalid)
var coords: Vector2i = Vector2i.ZERO

## Error message if invalid
var error: String = ""


## Create a successful result
static func ok(c: Vector2i) -> RefCounted:
	var r := new()
	r.valid = true
	r.coords = c
	return r


## Create an error result (coords contains clamped fallback)
static func err(msg: String, clamped: Vector2i = Vector2i.ZERO) -> RefCounted:
	var r := new()
	r.valid = false
	r.coords = clamped
	r.error = msg
	return r


## Get coords, returning default if invalid
func unwrap_or(default: Vector2i) -> Vector2i:
	return coords if valid else default


## Assert valid and return coords (for development - triggers assertion failure)
func expect(msg: String) -> Vector2i:
	assert(valid, "%s: %s" % [msg, error])
	return coords


## Check validity and warn if invalid, returns validity
func warn_if_invalid(context: String = "") -> bool:
	if not valid:
		var prefix := "[%s] " % context if context else ""
		push_warning("%sGridResult invalid: %s" % [prefix, error])
	return valid


## String representation for debugging
func _to_string() -> String:
	if valid:
		return "GridResult.ok(%s)" % coords
	else:
		return "GridResult.err(\"%s\", %s)" % [error, coords]
