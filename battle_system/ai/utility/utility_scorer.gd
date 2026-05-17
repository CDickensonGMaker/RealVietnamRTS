extends RefCounted
class_name UtilityScorer
## Utility Scorer - Base class for utility-based AI decision making.
##
## Evaluates options using weighted considerations that return 0.0-1.0 scores.
## Scores are combined multiplicatively (Geometric Mean) for nuanced decisions.
##
## Usage:
##   var scorer := UtilityScorer.new()
##   scorer.add_consideration("enemy_distance", func(ctx): return 1.0 - ctx.distance / 100.0)
##   scorer.add_consideration("health_ratio", func(ctx): return ctx.health / ctx.max_health, 0.5)
##   var score := scorer.evaluate_option({"distance": 50.0, "health": 80.0, "max_health": 100.0})


## A single consideration that contributes to an option's utility score.
class Consideration:
	var name: String
	var weight: float
	var evaluate: Callable  # func(context: Dictionary) -> float (0.0-1.0)
	var response_curve: Curve = null  # Optional curve to transform raw value

	func _init(p_name: String, p_evaluate: Callable, p_weight: float = 1.0, p_curve: Curve = null) -> void:
		name = p_name
		evaluate = p_evaluate
		weight = p_weight
		response_curve = p_curve

	## Evaluate this consideration for a given context
	func get_score(context: Dictionary) -> float:
		var raw_value: float = clampf(evaluate.call(context), 0.0, 1.0)

		# Apply response curve if provided
		if response_curve:
			raw_value = response_curve.sample(raw_value)

		return raw_value


## All considerations for this scorer
var considerations: Array[Consideration] = []

## Minimum threshold - options below this score are rejected
var min_threshold: float = 0.0

## Bonus multiplier - applied to score as additive bonus (for priority boosting)
var bonus_multiplier: float = 0.0


## Add a consideration to this scorer.
## [param p_name]: Descriptive name for debugging
## [param p_evaluate]: Callable that takes context Dictionary and returns 0.0-1.0
## [param p_weight]: Weight multiplier (default 1.0)
## [param p_curve]: Optional Curve to transform raw value
func add_consideration(
	p_name: String,
	p_evaluate: Callable,
	p_weight: float = 1.0,
	p_curve: Curve = null
) -> UtilityScorer:
	var consideration := Consideration.new(p_name, p_evaluate, p_weight, p_curve)
	considerations.append(consideration)
	return self  # Allow chaining


## Remove a consideration by name
func remove_consideration(p_name: String) -> bool:
	for i in range(considerations.size() - 1, -1, -1):
		if considerations[i].name == p_name:
			considerations.remove_at(i)
			return true
	return false


## Clear all considerations
func clear_considerations() -> void:
	considerations.clear()


## Evaluate an option using all considerations.
## Returns a score between 0.0 and 1.0 (plus any bonus).
## Uses compensatory averaging - all considerations matter but can compensate.
func evaluate_option(context: Dictionary) -> float:
	if considerations.is_empty():
		return 0.0

	var total_score: float = 0.0
	var total_weight: float = 0.0
	var any_zero: bool = false

	for consideration in considerations:
		var score: float = consideration.get_score(context)
		var weight: float = consideration.weight

		# Track if any score is zero (could make entire evaluation zero)
		if score <= 0.001:
			any_zero = true

		total_score += score * weight
		total_weight += weight

	if total_weight <= 0.0:
		return 0.0

	var final_score: float = total_score / total_weight

	# Apply bonus multiplier
	final_score += bonus_multiplier

	return clampf(final_score, 0.0, 1.0)


## Evaluate using geometric mean (multiplicative).
## More punishing - a single zero consideration results in zero score.
func evaluate_option_geometric(context: Dictionary) -> float:
	if considerations.is_empty():
		return 0.0

	var product: float = 1.0
	var total_weight: float = 0.0

	for consideration in considerations:
		var score: float = consideration.get_score(context)
		var weight: float = consideration.weight

		# Weighted geometric mean: multiply scores raised to weight power
		if score > 0.0:
			product *= pow(score, weight)
		else:
			return 0.0  # Any zero kills the entire score

		total_weight += weight

	if total_weight <= 0.0:
		return 0.0

	# Take the weighted root
	var final_score: float = pow(product, 1.0 / total_weight)

	# Apply bonus
	final_score += bonus_multiplier

	return clampf(final_score, 0.0, 1.0)


## Find the best option from an array of options.
## Each option should be a Dictionary with context data.
## Returns the option with highest score, or null if none pass threshold.
func get_best_option(options: Array, use_geometric: bool = false) -> Dictionary:
	var best_option: Dictionary = {}
	var best_score: float = min_threshold

	for option in options:
		var score: float
		if use_geometric:
			score = evaluate_option_geometric(option)
		else:
			score = evaluate_option(option)

		if score > best_score:
			best_score = score
			best_option = option

	return best_option


## Rank all options by score (highest first).
## Returns array of {option: Dictionary, score: float}
func rank_options(options: Array, use_geometric: bool = false) -> Array:
	var ranked: Array = []

	for option in options:
		var score: float
		if use_geometric:
			score = evaluate_option_geometric(option)
		else:
			score = evaluate_option(option)

		ranked.append({"option": option, "score": score})

	# Sort by score descending
	ranked.sort_custom(func(a, b): return a.score > b.score)

	return ranked


## Get debug info about last evaluation
func get_debug_breakdown(context: Dictionary) -> Array[Dictionary]:
	var breakdown: Array[Dictionary] = []

	for consideration in considerations:
		var score: float = consideration.get_score(context)
		breakdown.append({
			"name": consideration.name,
			"score": score,
			"weight": consideration.weight,
			"weighted_score": score * consideration.weight,
		})

	return breakdown


## Create common response curves
static func curve_linear() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(1.0, 1.0))
	return curve


static func curve_quadratic() -> Curve:
	# Slow start, fast finish (good for "closer is much better")
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.5, 0.25))
	curve.add_point(Vector2(1.0, 1.0))
	return curve


static func curve_inverse_quadratic() -> Curve:
	# Fast start, slow finish (good for diminishing returns)
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.5, 0.75))
	curve.add_point(Vector2(1.0, 1.0))
	return curve


static func curve_logistic() -> Curve:
	# S-curve: slow start, fast middle, slow finish
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.25, 0.05))
	curve.add_point(Vector2(0.5, 0.5))
	curve.add_point(Vector2(0.75, 0.95))
	curve.add_point(Vector2(1.0, 1.0))
	return curve


static func curve_threshold(threshold: float = 0.5) -> Curve:
	# Binary: below threshold = 0, above = 1
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(threshold - 0.01, 0.0))
	curve.add_point(Vector2(threshold, 1.0))
	curve.add_point(Vector2(1.0, 1.0))
	return curve
