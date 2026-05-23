class_name PrintThrottle
extends RefCounted
## PrintThrottle - Limits print spam by category
## Prevents console flooding from high-frequency debug messages
##
## Usage:
##   PrintThrottle.log("worker", "[WorkerController] %s moving to job" % worker.name)
##   PrintThrottle.log("job_progress", "[JobSystem] Progress: %.1f%%" % progress, 5)  # 5 per second max
##
## Categories are automatically tracked. Default limit is 3 messages per second per category.

## Message counts per category per second
## Structure: {category: {count: int, last_reset_time: float}}
static var _category_data: Dictionary = {}

## Default max messages per category per second
const DEFAULT_LIMIT: int = 3

## Suppression summary interval (report suppressed count every N seconds)
const SUMMARY_INTERVAL: float = 5.0

## Suppressed message counts (for summary reporting)
## Structure: {category: int}
static var _suppressed_counts: Dictionary = {}
static var _last_summary_time: float = 0.0


## Log a message with throttling
## Returns true if the message was printed, false if suppressed
static func log(category: String, message: String, limit: int = DEFAULT_LIMIT) -> bool:
	var current_time: float = Time.get_ticks_msec() / 1000.0

	# Initialize category data if needed
	if not _category_data.has(category):
		_category_data[category] = {"count": 0, "last_reset_time": current_time}

	var data: Dictionary = _category_data[category]

	# Reset count if a second has passed
	if current_time - data["last_reset_time"] >= 1.0:
		data["count"] = 0
		data["last_reset_time"] = current_time

	# Check if we're under the limit
	if data["count"] < limit:
		data["count"] += 1
		print(message)
		return true
	else:
		# Track suppression
		if not _suppressed_counts.has(category):
			_suppressed_counts[category] = 0
		_suppressed_counts[category] += 1

		# Print summary periodically
		_maybe_print_summary(current_time)
		return false


## Print suppression summary if interval has passed
static func _maybe_print_summary(current_time: float) -> void:
	if current_time - _last_summary_time < SUMMARY_INTERVAL:
		return

	# Count total suppressed
	var total: int = 0
	var categories_with_suppression: PackedStringArray = PackedStringArray()

	for cat: String in _suppressed_counts:
		var count: int = _suppressed_counts[cat]
		if count > 0:
			total += count
			categories_with_suppression.append("%s:%d" % [cat, count])

	if total > 0:
		print("[PrintThrottle] Suppressed %d messages in last %.0fs [%s]" % [
			total, SUMMARY_INTERVAL, ", ".join(categories_with_suppression)
		])

	# Reset suppression counts
	_suppressed_counts.clear()
	_last_summary_time = current_time


## Log with warning prefix (always printed, but still tracked for throttling)
static func warn(category: String, message: String) -> void:
	push_warning(message)


## Log with error prefix (always printed)
static func error(category: String, message: String) -> void:
	push_error(message)


## Reset all throttle data (useful for testing)
static func reset() -> void:
	_category_data.clear()
	_suppressed_counts.clear()
	_last_summary_time = 0.0


## Check if a category would be throttled (without printing)
static func would_throttle(category: String, limit: int = DEFAULT_LIMIT) -> bool:
	var current_time: float = Time.get_ticks_msec() / 1000.0

	if not _category_data.has(category):
		return false

	var data: Dictionary = _category_data[category]

	# Would reset?
	if current_time - data["last_reset_time"] >= 1.0:
		return false

	return data["count"] >= limit


## Get current count for a category (for debugging)
static func get_count(category: String) -> int:
	if not _category_data.has(category):
		return 0
	return _category_data[category]["count"]
