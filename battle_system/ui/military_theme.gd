class_name MilitaryTheme extends RefCounted
## Centralized military-style UI theme for RealVietnamRTS.
## Provides color palettes, style factories, and theme building.

# =============================================================================
# PANEL COLORS
# =============================================================================
const COL_PANEL_BG := Color(0.12, 0.14, 0.10, 0.95)
const COL_PANEL_BORDER := Color(0.3, 0.35, 0.25)
const COL_PANEL_HEADER := Color(0.18, 0.20, 0.15, 0.98)

# =============================================================================
# TEXT COLORS
# =============================================================================
const COL_TEXT_PRIMARY := Color(0.9, 0.9, 0.85)
const COL_TEXT_SECONDARY := Color(0.6, 0.6, 0.55)
const COL_TEXT_DISABLED := Color(0.4, 0.4, 0.38)
const COL_TEXT_HIGHLIGHT := Color(1.0, 0.95, 0.7)

# =============================================================================
# HEALTH / STATUS COLORS (matches existing FloatingHealthBar)
# =============================================================================
const COL_HEALTH_FULL := Color(0.2, 0.8, 0.2)
const COL_HEALTH_MID := Color(0.9, 0.9, 0.2)
const COL_HEALTH_LOW := Color(0.9, 0.2, 0.2)
const COL_SUPPRESSION := Color(0.9, 0.5, 0.1, 0.7)
const COL_AMMO_FULL := Color(0.7, 0.7, 0.6)
const COL_AMMO_LOW := Color(0.9, 0.6, 0.2)
const COL_AMMO_EMPTY := Color(0.9, 0.2, 0.2)

# =============================================================================
# FACTION COLORS (for NATO symbols and UI accents)
# =============================================================================
const COL_FACTION_US := Color(0.3, 0.5, 0.9)       # Blue
const COL_FACTION_ARVN := Color(0.3, 0.7, 0.5)     # Teal
const COL_FACTION_VC := Color(0.9, 0.3, 0.3)       # Red
const COL_FACTION_NVA := Color(0.8, 0.2, 0.2)      # Dark red
const COL_FACTION_NEUTRAL := Color(0.5, 0.5, 0.5)  # Gray

# =============================================================================
# TARGETING OVERLAY COLORS
# =============================================================================
const COL_MOVE_PATH := Color(0.3, 0.8, 0.3, 0.7)
const COL_ATTACK_MOVE_PATH := Color(0.9, 0.5, 0.2, 0.7)
const COL_FIRE_MISSION_VALID := Color(0.9, 0.6, 0.1, 0.5)
const COL_FIRE_MISSION_INVALID := Color(0.9, 0.2, 0.2, 0.5)
const COL_FIRE_MISSION_MIN_RANGE := Color(0.9, 0.2, 0.2, 0.3)
const COL_GHOST := Color(0.5, 0.5, 0.5, 0.4)
const COL_GHOST_INVALID := Color(0.9, 0.2, 0.2, 0.4)
const COL_GARRISON_VALID := Color(0.4, 0.7, 0.9, 0.6)  # Light blue for valid garrison targets

# =============================================================================
# VETERANCY CHEVRON COLORS
# =============================================================================
const COL_VET: Array[Color] = [
	Color(0.5, 0.5, 0.5),    # 0: Conscript (gray)
	Color(0.6, 0.5, 0.3),    # 1: Regular (tan)
	Color(0.7, 0.55, 0.25),  # 2: Veteran (bronze)
	Color(0.75, 0.75, 0.8),  # 3: Elite (silver)
	Color(0.95, 0.8, 0.2),   # 4: Legend (gold)
]

# =============================================================================
# BUTTON COLORS
# =============================================================================
const COL_BUTTON_NORMAL := Color(0.2, 0.22, 0.18, 0.9)
const COL_BUTTON_HOVER := Color(0.28, 0.30, 0.24, 0.95)
const COL_BUTTON_PRESSED := Color(0.35, 0.38, 0.30, 1.0)
const COL_BUTTON_DISABLED := Color(0.15, 0.16, 0.14, 0.7)

# =============================================================================
# STATE BADGE COLORS
# =============================================================================
const COL_STATE_IDLE := Color(0.5, 0.5, 0.5)
const COL_STATE_MOVING := Color(0.3, 0.6, 0.9)
const COL_STATE_COMBAT := Color(0.9, 0.3, 0.2)
const COL_STATE_SUPPRESSED := Color(0.9, 0.6, 0.1)
const COL_STATE_CLEARING := Color(0.6, 0.4, 0.2)
const COL_STATE_DEPLOYED := Color(0.4, 0.7, 0.4)

# =============================================================================
# STATIC HELPER METHODS
# =============================================================================

## Returns faction color for the given GameEnums.Faction value
static func faction_color(faction: int) -> Color:
	match faction:
		0:  # US_ARMY
			return COL_FACTION_US
		1:  # ARVN
			return COL_FACTION_ARVN
		2:  # VC
			return COL_FACTION_VC
		3:  # NVA
			return COL_FACTION_NVA
		_:
			return COL_FACTION_NEUTRAL


## Returns interpolated health color based on fraction (0.0 to 1.0)
static func health_color(fraction: float) -> Color:
	fraction = clampf(fraction, 0.0, 1.0)
	if fraction > 0.6:
		return COL_HEALTH_FULL.lerp(COL_HEALTH_MID, (1.0 - fraction) / 0.4)
	elif fraction > 0.3:
		return COL_HEALTH_MID.lerp(COL_HEALTH_LOW, (0.6 - fraction) / 0.3)
	else:
		return COL_HEALTH_LOW


## Returns ammo color based on fraction (0.0 to 1.0)
static func ammo_color(fraction: float) -> Color:
	fraction = clampf(fraction, 0.0, 1.0)
	if fraction > 0.5:
		return COL_AMMO_FULL
	elif fraction > 0.2:
		return COL_AMMO_LOW
	else:
		return COL_AMMO_EMPTY


## Returns veterancy chevron color for level (0-4)
static func veterancy_color(level: int) -> Color:
	level = clampi(level, 0, COL_VET.size() - 1)
	return COL_VET[level]


## Returns state badge color for unit state string
static func state_color(state_name: String) -> Color:
	match state_name.to_upper():
		"IDLE":
			return COL_STATE_IDLE
		"MOVING":
			return COL_STATE_MOVING
		"COMBAT", "ATTACKING":
			return COL_STATE_COMBAT
		"SUPPRESSED", "PINNED":
			return COL_STATE_SUPPRESSED
		"CLEARING":
			return COL_STATE_CLEARING
		"DEPLOYED":
			return COL_STATE_DEPLOYED
		_:
			return COL_STATE_IDLE


# =============================================================================
# STYLEBOX FACTORIES
# =============================================================================

## Creates a panel stylebox with military theme
static func create_panel_stylebox() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL_BG
	style.border_color = COL_PANEL_BORDER
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_top = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	return style


## Creates a header panel stylebox (slightly lighter)
static func create_header_stylebox() -> StyleBoxFlat:
	var style := create_panel_stylebox()
	style.bg_color = COL_PANEL_HEADER
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	return style


## Creates a button stylebox
static func create_button_stylebox(state: String = "normal") -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 6
	style.content_margin_top = 4
	style.content_margin_right = 6
	style.content_margin_bottom = 4

	match state:
		"normal":
			style.bg_color = COL_BUTTON_NORMAL
			style.border_color = COL_PANEL_BORDER
		"hover":
			style.bg_color = COL_BUTTON_HOVER
			style.border_color = COL_TEXT_SECONDARY
		"pressed":
			style.bg_color = COL_BUTTON_PRESSED
			style.border_color = COL_TEXT_PRIMARY
		"disabled":
			style.bg_color = COL_BUTTON_DISABLED
			style.border_color = COL_TEXT_DISABLED

	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	return style


## Creates a progress bar stylebox (for health/XP bars)
static func create_progress_bg_stylebox() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style


static func create_progress_fill_stylebox(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style


# =============================================================================
# THEME BUILDER
# =============================================================================

## Builds and returns a complete Theme resource with military styling
static func build() -> Theme:
	var theme := Theme.new()

	# Panel styles
	theme.set_stylebox("panel", "PanelContainer", create_panel_stylebox())

	# Button styles
	theme.set_stylebox("normal", "Button", create_button_stylebox("normal"))
	theme.set_stylebox("hover", "Button", create_button_stylebox("hover"))
	theme.set_stylebox("pressed", "Button", create_button_stylebox("pressed"))
	theme.set_stylebox("disabled", "Button", create_button_stylebox("disabled"))

	# Button colors
	theme.set_color("font_color", "Button", COL_TEXT_PRIMARY)
	theme.set_color("font_hover_color", "Button", COL_TEXT_HIGHLIGHT)
	theme.set_color("font_pressed_color", "Button", COL_TEXT_HIGHLIGHT)
	theme.set_color("font_disabled_color", "Button", COL_TEXT_DISABLED)

	# Label colors
	theme.set_color("font_color", "Label", COL_TEXT_PRIMARY)

	# ProgressBar styles
	theme.set_stylebox("background", "ProgressBar", create_progress_bg_stylebox())
	theme.set_stylebox("fill", "ProgressBar", create_progress_fill_stylebox(COL_HEALTH_FULL))

	# Default font size
	theme.set_font_size("font_size", "Label", 14)
	theme.set_font_size("font_size", "Button", 12)

	return theme
