extends Node2D

const AppTheme = preload("res://scripts/app_theme.gd")

# Couches d'etoiles, de la plus lointaine a la plus proche.
# cam  : parallaxe liee au deplacement de la camera (px d'ecran par unite monde)
# flow : defilement ambiant (px/s) quand le vaisseau vole, pour sentir la vitesse
const LAYERS := [
	{"cam": 0.003, "flow": 3.0, "count": 150, "radius": 0.6, "alpha": 0.35, "glow": false},
	{"cam": 0.008, "flow": 7.0, "count": 90, "radius": 0.9, "alpha": 0.55, "glow": false},
	{"cam": 0.018, "flow": 14.0, "count": 45, "radius": 1.3, "alpha": 0.75, "glow": false},
	{"cam": 0.040, "flow": 26.0, "count": 16, "radius": 1.9, "alpha": 0.95, "glow": true},
]
const NEBULA_COUNT := 4
const NEBULA_CAM := 0.0015
const VIGNETTE_BANDS := 14

var current_theme: AppTheme

var cam_pos: Vector2 = Vector2.ZERO
var cam_zoom: float = 1.0
var flow: Vector2 = Vector2.ZERO   # defilement cumule (px)
var flow_dir: Vector2 = Vector2.RIGHT
var flow_amount: float = 0.0       # 0 = a l'arret, 1 = en vol (lisse)
var flow_target: float = 0.0
var time: float = 0.0

var star_pos: Array[PackedVector2Array] = []
var star_phase: Array[PackedFloat32Array] = []
var star_tint: Array[PackedColorArray] = []
var nebulae: Array[Dictionary] = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260923
	for layer in LAYERS:
		var pos := PackedVector2Array()
		var phase := PackedFloat32Array()
		var tint := PackedColorArray()
		for i in int(layer["count"]):
			pos.append(Vector2(rng.randf(), rng.randf()))
			phase.append(rng.randf() * TAU)
			var roll: float = rng.randf()
			if roll < 0.15:
				tint.append(Color(1.0, 0.86, 0.72))
			elif roll < 0.35:
				tint.append(Color(0.75, 0.85, 1.0))
			else:
				tint.append(Color(1, 1, 1))
		star_pos.append(pos)
		star_phase.append(phase)
		star_tint.append(tint)
	for i in NEBULA_COUNT:
		nebulae.append({
			"pos": Vector2(rng.randf(), rng.randf()),
			"radius": rng.randf_range(220.0, 380.0),
			"alt": i % 2 == 1,
		})


func set_app_theme(t: AppTheme) -> void:
	current_theme = t
	queue_redraw()


func update_view(pos: Vector2, zoom: float, heading: Vector2, flying: bool) -> void:
	cam_pos = pos
	cam_zoom = zoom
	if heading != Vector2.ZERO:
		flow_dir = heading
	flow_target = 1.0 if flying else 0.0


func _process(delta: float) -> void:
	time += delta
	flow_amount = lerpf(flow_amount, flow_target, 1.0 - exp(-delta * 1.5))
	flow -= flow_dir * flow_amount * delta
	queue_redraw()


func _draw() -> void:
	if current_theme == null:
		return
	var size: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), current_theme.background, true)
	if current_theme.background_style == "grid":
		_draw_grid(size)
	_draw_nebulae(size)
	_draw_stars(size)
	_draw_vignette(size)


func _draw_grid(size: Vector2) -> void:
	var step: float = 160.0
	while step * cam_zoom < 28.0:
		step *= 4.0
	var s: float = step * cam_zoom
	var x: float = fposmod(size.x * 0.5 - cam_pos.x * cam_zoom, s)
	while x <= size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), current_theme.grid_color, 1.0)
		x += s
	var y: float = fposmod(size.y * 0.5 - cam_pos.y * cam_zoom, s)
	while y <= size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), current_theme.grid_color, 1.0)
		y += s


func _draw_nebulae(size: Vector2) -> void:
	for n in nebulae:
		var p: Vector2 = n["pos"]
		var off: Vector2 = cam_pos * NEBULA_CAM + flow * 1.5
		var margin: float = float(n["radius"])
		var wrap: Vector2 = size + Vector2(margin, margin) * 2.0
		var c := Vector2(
			fposmod(p.x * wrap.x - off.x, wrap.x) - margin,
			fposmod(p.y * wrap.y - off.y, wrap.y) - margin)
		var base: Color = current_theme.planet_dest if n["alt"] else current_theme.planet_selected
		for i in 8:
			var k: float = float(i) / 7.0
			draw_circle(c, margin * (1.0 - k * 0.85), Color(base.r, base.g, base.b, 0.012))


func _draw_stars(size: Vector2) -> void:
	var base: Color = current_theme.star_color
	for li in LAYERS.size():
		var layer: Dictionary = LAYERS[li]
		var off: Vector2 = cam_pos * float(layer["cam"]) + flow * float(layer["flow"])
		var r: float = layer["radius"]
		var a: float = layer["alpha"]
		var glow: bool = layer["glow"]
		var pos: PackedVector2Array = star_pos[li]
		var phase: PackedFloat32Array = star_phase[li]
		var tint: PackedColorArray = star_tint[li]
		for i in pos.size():
			var p := Vector2(
				fposmod(pos[i].x * size.x - off.x, size.x),
				fposmod(pos[i].y * size.y - off.y, size.y))
			var tw: float = 0.78 + 0.22 * sin(time * (0.6 + float(li) * 0.35) + phase[i])
			var t: Color = tint[i]
			var col := Color(base.r * t.r, base.g * t.g, base.b * t.b, a * tw)
			draw_circle(p, r, col)
			if glow:
				draw_circle(p, r * 3.2, Color(col.r, col.g, col.b, 0.08 * tw))


func _draw_vignette(size: Vector2) -> void:
	var strength: float = 0.5 if current_theme.background_style == "vignette" else 0.35
	var band: float = 14.0
	for i in VIGNETTE_BANDS:
		var k: float = 1.0 - float(i) / float(VIGNETTE_BANDS)
		var col := Color(0, 0, 0, strength * k * k / 3.0)
		var o: float = float(i) * band
		draw_rect(Rect2(0, o, size.x, band), col, true)
		draw_rect(Rect2(0, size.y - o - band, size.x, band), col, true)
		draw_rect(Rect2(o, 0, band, size.y), col, true)
		draw_rect(Rect2(size.x - o - band, 0, band, size.y), col, true)
