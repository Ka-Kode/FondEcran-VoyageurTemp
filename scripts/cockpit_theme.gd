extends Resource
class_name CockpitTheme

@export var display_name: String = "Neon cyan"
# canopee : verriere ronde a nervures / chasseur : verriere effilee / passerelle : grande baie vitree
@export_enum("canopee", "chasseur", "passerelle") var frame_style: String = "canopee"

@export var frame_fill: Color = Color(0.02, 0.03, 0.06)
@export var frame_line: Color = Color(0.2, 0.95, 1.0)
@export var dash_fill: Color = Color(0.015, 0.02, 0.045)
@export var hud_text: Color = Color(0.7, 0.97, 1.0)
@export var hud_accent: Color = Color(1.0, 0.3, 0.8)
@export var hud_dim: Color = Color(0.3, 0.55, 0.65)

@export var space_color: Color = Color(0.01, 0.01, 0.03)
@export var star_color: Color = Color(0.85, 0.95, 1.0)
@export var tunnel_a: Color = Color(0.3, 0.6, 1.0)
@export var tunnel_b: Color = Color(0.8, 0.95, 1.0)

@export var asteroid_line: Color = Color(1.0, 0.55, 0.2)
@export var asteroid_fill: Color = Color(0.05, 0.03, 0.03)
@export var grid_color: Color = Color(0.2, 0.95, 1.0)
