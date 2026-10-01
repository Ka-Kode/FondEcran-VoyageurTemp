extends Resource
class_name AppTheme

@export var display_name: String = "Defaut"

@export var background: Color = Color(0.06, 0.06, 0.09)
@export_enum("flat", "grid", "vignette") var background_style: String = "flat"
@export var grid_color: Color = Color(1, 1, 1, 0.05)

@export var star_color: Color = Color(0.9, 0.93, 1.0)

@export var text_color: Color = Color(1, 1, 1, 0.85)

@export var ship_color: Color = Color(0.85, 0.87, 0.9)
@export var ship_adrift_color: Color = Color(0.95, 0.3, 0.35)

@export var planet_start: Color = Color(0.6, 0.6, 0.65)
@export var planet_dest: Color = Color(0.9, 0.75, 0.3)
@export var planet_candidate: Color = Color(0.35, 0.4, 0.5)
@export var planet_candidate_dim: Color = Color(0.3, 0.32, 0.38, 0.4)
@export var planet_selected: Color = Color(0.4, 0.75, 0.9)

@export var route_line: Color = Color(0.5, 0.5, 0.55, 0.5)
@export var capture_ring: Color = Color(0.4, 0.85, 0.6, 0.5)
@export var emergency_marker: Color = Color(0.9, 0.4, 0.3)
@export var flash_color: Color = Color(1, 1, 1)

@export var planned_route_color: Color = Color(1.0, 0.15, 0.15, 0.95)
@export var drift_line_color: Color = Color(1.0, 0.65, 0.15, 0.85)
@export var correction_line_color: Color = Color(0.4, 0.85, 1.0, 0.85)
