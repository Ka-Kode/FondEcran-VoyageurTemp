extends RefCounted

# Types de planetes : couleurs de surface (a, b), atmosphere, motif du shader
# (0 = bandes, 1 = continents, 2 = dunes). La couleur d'atmosphere teinte aussi
# le tunnel d'hyperespace et la nebuleuse de la region traversee.
const LIST := [
	{"name": "Volcanique", "a": Color(0.22, 0.04, 0.03), "b": Color(1.0, 0.38, 0.06), "atmo": Color(1.0, 0.4, 0.12), "style": 1, "rings": false},
	{"name": "Glaciaire", "a": Color(0.78, 0.9, 1.0), "b": Color(0.32, 0.52, 0.8), "atmo": Color(0.55, 0.85, 1.0), "style": 1, "rings": false},
	{"name": "Géante gazeuse", "a": Color(0.5, 0.32, 0.72), "b": Color(0.95, 0.68, 0.5), "atmo": Color(0.8, 0.5, 1.0), "style": 0, "rings": true},
	{"name": "Océanique", "a": Color(0.04, 0.18, 0.5), "b": Color(0.15, 0.62, 0.42), "atmo": Color(0.3, 0.7, 1.0), "style": 1, "rings": false},
	{"name": "Jungle", "a": Color(0.06, 0.32, 0.1), "b": Color(0.5, 0.85, 0.25), "atmo": Color(0.5, 1.0, 0.6), "style": 1, "rings": false},
	{"name": "Désertique", "a": Color(0.7, 0.45, 0.22), "b": Color(0.96, 0.8, 0.5), "atmo": Color(1.0, 0.78, 0.5), "style": 2, "rings": false},
	{"name": "Cristalline", "a": Color(0.08, 0.75, 0.7), "b": Color(0.85, 0.2, 0.85), "atmo": Color(0.45, 1.0, 0.92), "style": 1, "rings": true},
]


static func get_biome(i: int) -> Dictionary:
	return LIST[clampi(i, 0, LIST.size() - 1)]


static func map_color(i: int) -> Color:
	var b: Dictionary = get_biome(i)
	return (b["b"] as Color).lerp(b["atmo"], 0.4)
