extends Control

# Vue depuis le cockpit : tunnel d'hyperespace (shader), champ d'etoiles en perspective,
# planete (shader), sol neon a l'atterrissage, armature et tableau de bord vectoriels.
# Le pilotage (fleches) est purement visuel : le pilote auto recentre des qu'on lache.
# Mini-jeu d'evitement d'asteroides activable avec G.

const Journey = preload("res://scripts/journey.gd")
const Biomes = preload("res://scripts/biomes.gd")

signal best_score_changed(score: int)

const VIEW := Vector2(900.0, 600.0)
const VP_BASE := Vector2(450.0, 232.0)   # point de fuite, au centre de la verriere
const FOCAL := 360.0
const STAR_COUNT := 240
const STAR_SPREAD := 3.0
const FAR_Z := 22.0
const NEAR_Z := 0.2

const HYPER_SPEED := 26.0
const SUBLIGHT_SPEED := 1.5
const BOOST_FACTOR := 2.4
const TUNNEL_TRAVEL_SCALE := 0.06

const STEER_ACCEL := 6.0
const STEER_DAMP := 2.6
const AUTOPILOT_PULL := 4.0
const STEER_LIMIT := Vector2(1.5, 0.85)

const SHIELDS_MAX := 3
const SHIP_RADIUS := 0.18
const HIT_Z := 0.6

# Poses de la planete a l'ecran (centre, rayon) selon la phase de vol.
const APPROACH_END := {"c": Vector2(380, 300), "r": 170.0}
const ORBIT_POSE := {"c": Vector2(450, 1120), "r": 830.0}
const DEPART_END := {"c": Vector2(450, 1900), "r": 900.0}
const LANDING_POSE := {"c": Vector2(450, 1450), "r": 1300.0}

var cockpit_theme: CockpitTheme
var state: Dictionary = {}

var ship_off: Vector2 = Vector2.ZERO
var ship_vel: Vector2 = Vector2.ZERO
var vp: Vector2 = VP_BASE
var roll: float = 0.0
var boost: float = 0.0
var speed: float = 0.0
var travel: float = 0.0
var time: float = 0.0
var flash: float = 0.0
var shake: float = 0.0
var prev_hyper: float = -1.0
var planet_spin: float = 0.0
var ground_scroll: float = 0.0
var stars := PackedVector3Array()

var game_on: bool = false
var game_over: bool = false
var game_time: float = 0.0
var spawn_timer: float = 0.0
var shields: int = SHIELDS_MAX
var dodged: int = 0
var best: int = 0
var asteroids: Array[Dictionary] = []
var debris: Array[Dictionary] = []
var hit_flash: float = 0.0

var bg_mat: ShaderMaterial
var planet_rect: ColorRect
var planet_mat: ShaderMaterial
var stars_layer: Node2D
var fg_layer: Node2D
var frame_layer: Node2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = VIEW

	var bg := ColorRect.new()
	bg.size = VIEW
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_mat = ShaderMaterial.new()
	bg_mat.shader = load("res://shaders/hyperspace.gdshader")
	bg.material = bg_mat
	add_child(bg)

	stars_layer = Node2D.new()
	add_child(stars_layer)
	stars_layer.draw.connect(_draw_stars)

	planet_rect = ColorRect.new()
	planet_rect.size = VIEW
	planet_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	planet_mat = ShaderMaterial.new()
	planet_mat.shader = load("res://shaders/planet.gdshader")
	planet_rect.material = planet_mat
	add_child(planet_rect)

	fg_layer = Node2D.new()
	add_child(fg_layer)
	fg_layer.draw.connect(_draw_fg)

	frame_layer = Node2D.new()
	add_child(frame_layer)
	frame_layer.draw.connect(_draw_frame)

	for i in STAR_COUNT:
		stars.append(_new_star(randf_range(NEAR_Z, FAR_Z)))


func set_cockpit_theme(t: CockpitTheme) -> void:
	cockpit_theme = t


func update_state(s: Dictionary) -> void:
	state = s


func toggle_game() -> void:
	if game_on and not game_over:
		game_on = false
		asteroids.clear()
		return
	game_on = true
	game_over = false
	game_time = 0.0
	spawn_timer = 1.0
	shields = SHIELDS_MAX
	dodged = 0
	asteroids.clear()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.pressed or event.echo:
		return
	if event.keycode == KEY_G:
		toggle_game()
		get_viewport().set_input_as_handled()


func _new_star(z: float) -> Vector3:
	return Vector3(
		ship_off.x + randf_range(-STAR_SPREAD, STAR_SPREAD),
		ship_off.y + randf_range(-STAR_SPREAD, STAR_SPREAD),
		z)


func _process(delta: float) -> void:
	if not is_visible_in_tree() or cockpit_theme == null or state.is_empty():
		return
	time += delta
	_update_steering(delta)

	var mode: int = state["mode"]
	var u: float = state["u"]
	var arrived: bool = state["arrived"]
	var hyper: float = state["hyper"]
	boost = move_toward(boost, 1.0 if Input.is_key_pressed(KEY_SHIFT) else 0.0, delta * 2.0)
	speed = lerpf(SUBLIGHT_SPEED, HYPER_SPEED, hyper) * (1.0 + boost * (BOOST_FACTOR - 1.0))
	if arrived:
		speed = 0.0
	travel += speed * delta * TUNNEL_TRAVEL_SCALE

	if prev_hyper >= 0.0 and (prev_hyper < 0.5) != (hyper < 0.5):
		flash = 1.0
	prev_hyper = hyper
	flash = maxf(0.0, flash - delta * 2.2)
	shake = maxf(0.0, shake - delta * 1.5)
	hit_flash = maxf(0.0, hit_flash - delta * 1.8)
	planet_spin += delta * (0.05 if mode == Journey.Mode.ORBIT else 0.015)

	if mode == Journey.Mode.LANDING and not arrived:
		var land_t: float = clampf((u - 0.6) / 0.4, 0.0, 1.0)
		ground_scroll += 5.0 * pow(1.0 - land_t, 2.0) * delta

	_update_stars(delta)
	_update_game(delta)
	_update_shaders()

	position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 8.0
	stars_layer.queue_redraw()
	fg_layer.queue_redraw()
	frame_layer.queue_redraw()


func _update_steering(delta: float) -> void:
	var inp := Vector2(
		float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP)))
	ship_vel += inp * STEER_ACCEL * delta
	ship_vel *= exp(-STEER_DAMP * delta)
	# Pilote automatique : ramene le vaisseau au centre du couloir des qu'on lache les
	# commandes. Desactive pendant le mini-jeu, sinon impossible d'esquiver.
	if inp == Vector2.ZERO and not (game_on and not game_over):
		ship_vel += -ship_off * AUTOPILOT_PULL * delta
		ship_vel *= exp(-1.5 * delta)
	ship_off += ship_vel * delta
	for axis in 2:
		if absf(ship_off[axis]) > STEER_LIMIT[axis]:
			ship_off[axis] = signf(ship_off[axis]) * STEER_LIMIT[axis]
			ship_vel[axis] = 0.0
	roll = -ship_vel.x * 0.12
	vp = VP_BASE - ship_vel * Vector2(24.0, 18.0)


func _proj(p: Vector3) -> Vector2:
	var q := Vector2(p.x - ship_off.x, p.y - ship_off.y) * (FOCAL / p.z)
	return vp + q.rotated(roll)


func _update_stars(delta: float) -> void:
	for i in stars.size():
		var s: Vector3 = stars[i]
		s.z -= speed * delta
		if s.z < NEAR_Z or absf(s.x - ship_off.x) > STAR_SPREAD * 1.4 or absf(s.y - ship_off.y) > STAR_SPREAD * 1.4:
			s = _new_star(FAR_Z + randf() * 2.0)
		stars[i] = s


func _region_tint() -> Color:
	var a: Color = Biomes.get_biome(state["region_from"])["atmo"]
	var b: Color = Biomes.get_biome(state["region_to"])["atmo"]
	return a.lerp(b, state["region_u"])


func _update_shaders() -> void:
	var t := cockpit_theme
	var tint := _region_tint()
	bg_mat.set_shader_parameter("vp", vp)
	bg_mat.set_shader_parameter("travel", travel)
	bg_mat.set_shader_parameter("intensity", 0.0 if state["arrived"] else float(state["hyper"]))
	bg_mat.set_shader_parameter("roll", roll)
	bg_mat.set_shader_parameter("flash", flash * 0.8)
	bg_mat.set_shader_parameter("color_a", t.tunnel_a.lerp(tint, 0.35))
	bg_mat.set_shader_parameter("color_b", t.tunnel_b.lerp(tint, 0.2))
	bg_mat.set_shader_parameter("space_color", t.space_color)
	bg_mat.set_shader_parameter("nebula_color", tint)
	bg_mat.set_shader_parameter("nebula_amount", 0.5)
	bg_mat.set_shader_parameter("nebula_drift", time * 0.004 + ship_off.x * 0.03)

	var pv: Dictionary = _planet_view()
	planet_rect.visible = not pv.is_empty()
	if pv.is_empty():
		return
	var pl: Dictionary = state["planet"]
	var biome: Dictionary = Biomes.get_biome(pl["biome"])
	planet_mat.set_shader_parameter("center", pv["c"])
	planet_mat.set_shader_parameter("radius", pv["r"])
	planet_mat.set_shader_parameter("alpha", pv["alpha"])
	planet_mat.set_shader_parameter("color_a", biome["a"])
	planet_mat.set_shader_parameter("color_b", biome["b"])
	planet_mat.set_shader_parameter("atmo", biome["atmo"])
	planet_mat.set_shader_parameter("line_color", t.frame_line)
	planet_mat.set_shader_parameter("style", biome["style"])
	planet_mat.set_shader_parameter("spin", planet_spin + float(pl["seed"]))
	planet_mat.set_shader_parameter("seed", float(pl["seed"]) * 10.0)


# Position et taille de la planete a l'ecran selon la phase ; vide si aucune n'est visible.
func _planet_view() -> Dictionary:
	if state["arrived"] or state["planet"].is_empty():
		return {}
	var mode: int = state["mode"]
	var u: float = state["u"]
	var c: Vector2
	var r: float
	var alpha: float = 1.0
	match mode:
		Journey.Mode.DEPART:
			if u > 0.7:
				return {}
			var k: float = smoothstep(0.0, 0.7, u)
			k *= k
			c = (ORBIT_POSE["c"] as Vector2).lerp(DEPART_END["c"], k)
			r = lerpf(ORBIT_POSE["r"], DEPART_END["r"], k)
		Journey.Mode.APPROACH:
			r = 2.5 * pow(float(APPROACH_END["r"]) / 2.5, pow(u, 1.4))
			c = VP_BASE.lerp(APPROACH_END["c"], smoothstep(0.35, 1.0, u))
			alpha = smoothstep(0.05, 0.2, u)
		Journey.Mode.ORBIT:
			var k: float = smoothstep(0.0, 0.25, u)
			c = (APPROACH_END["c"] as Vector2).lerp(ORBIT_POSE["c"], k)
			r = lerpf(APPROACH_END["r"], ORBIT_POSE["r"], k)
		Journey.Mode.LANDING:
			if u > 0.56:
				return {}
			var k: float = smoothstep(0.0, 0.5, u)
			c = (APPROACH_END["c"] as Vector2).lerp(LANDING_POSE["c"], k)
			r = lerpf(APPROACH_END["r"], LANDING_POSE["r"], k)
			alpha = 1.0 - smoothstep(0.42, 0.56, u)
		_:
			return {}
	# Legere parallaxe quand on pilote.
	c += (vp - VP_BASE) * 0.5
	return {"c": c, "r": r, "alpha": alpha}


# --- Mini-jeu -----------------------------------------------------------------

func _update_game(delta: float) -> void:
	var running: bool = game_on and not game_over
	if running:
		game_time += delta
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			spawn_timer = maxf(0.28, 1.0 - game_time * 0.012)
			_spawn_asteroid()
	var gspeed: float = minf(10.0 + game_time * 0.12, 24.0)
	var i: int = asteroids.size() - 1
	while i >= 0:
		var a: Dictionary = asteroids[i]
		var p: Vector3 = a["pos"]
		var prev_z: float = p.z
		p.z -= gspeed * delta
		a["pos"] = p
		a["rot"] = float(a["rot"]) + float(a["rot_speed"]) * delta
		if prev_z >= HIT_Z and p.z < HIT_Z and running:
			if Vector2(p.x, p.y).distance_to(ship_off) < float(a["radius"]) + SHIP_RADIUS:
				_on_hit(a)
				asteroids.remove_at(i)
				i -= 1
				continue
			dodged += 1
		if p.z < NEAR_Z:
			asteroids.remove_at(i)
		i -= 1
	var j: int = debris.size() - 1
	while j >= 0:
		var d: Dictionary = debris[j]
		d["pos"] = (d["pos"] as Vector2) + (d["vel"] as Vector2) * delta
		d["life"] = float(d["life"]) - delta
		if d["life"] <= 0.0:
			debris.remove_at(j)
		j -= 1


func _spawn_asteroid() -> void:
	var aimed: bool = randf() < 0.35
	var pos := Vector3(
		ship_off.x + (randf_range(-0.12, 0.12) if aimed else randf_range(-1.4, 1.4)),
		ship_off.y + (randf_range(-0.1, 0.1) if aimed else randf_range(-0.8, 0.8)),
		FAR_Z)
	pos.x = clampf(pos.x, -STEER_LIMIT.x * 1.1, STEER_LIMIT.x * 1.1)
	pos.y = clampf(pos.y, -STEER_LIMIT.y * 1.1, STEER_LIMIT.y * 1.1)
	var verts := PackedVector2Array()
	var n: int = randi_range(7, 10)
	for k in n:
		verts.append(Vector2.from_angle(TAU * float(k) / float(n)) * randf_range(0.7, 1.1))
	asteroids.append({
		"pos": pos, "radius": randf_range(0.16, 0.38), "verts": verts,
		"rot": randf() * TAU, "rot_speed": randf_range(-1.5, 1.5),
	})


func _on_hit(a: Dictionary) -> void:
	shields -= 1
	hit_flash = 1.0
	shake = 0.6
	var center: Vector2 = _proj(a["pos"])
	for k in 14:
		debris.append({"pos": center, "vel": Vector2.from_angle(randf() * TAU) * randf_range(120, 420), "life": randf_range(0.4, 0.9)})
	if shields <= 0:
		game_over = true
		if dodged > best:
			best = dodged
			best_score_changed.emit(best)


# --- Dessin -------------------------------------------------------------------

func _draw_stars() -> void:
	if state.is_empty() or cockpit_theme == null:
		return
	var ci := stars_layer
	var hyper: float = state["hyper"]
	var tint := _region_tint()
	var trail: float = 0.04 + hyper * 2.2 * (1.0 + boost) + (0.0 if state["arrived"] else 0.0)
	var col_base: Color = cockpit_theme.star_color.lerp(tint, hyper * 0.5)
	for s in stars:
		if s.z < NEAR_Z:
			continue
		var p1: Vector2 = _proj(s)
		var p0: Vector2 = _proj(Vector3(s.x, s.y, s.z + trail))
		var a: float = clampf((1.0 - s.z / FAR_Z) * 1.4, 0.0, 1.0)
		var w: float = clampf(1.3 / s.z, 0.6, 3.0)
		var col := Color(col_base, a)
		if p0.distance_to(p1) < 1.5:
			ci.draw_circle(p1, w * 0.6, col)
		else:
			ci.draw_line(p0, p1, col, w)
	# Moitie arriere des anneaux : derriere la planete.
	var pv: Dictionary = _planet_view()
	if not pv.is_empty() and Biomes.get_biome(state["planet"]["biome"])["rings"]:
		_draw_rings(ci, pv, true)


func _draw_rings(ci: CanvasItem, pv: Dictionary, back: bool) -> void:
	var c: Vector2 = pv["c"]
	var r: float = pv["r"]
	var col: Color = Biomes.get_biome(state["planet"]["biome"])["atmo"]
	for band in 3:
		var rx: float = r * (1.55 + 0.18 * float(band))
		var ry: float = rx * 0.22
		var pts := PackedVector2Array()
		var from_a: float = PI if back else 0.0
		for k in 49:
			var ang: float = from_a + PI * float(k) / 48.0
			pts.append(c + Vector2(cos(ang) * rx, sin(ang) * ry).rotated(-0.25))
		ci.draw_polyline(pts, Color(col, (0.35 - 0.08 * float(band)) * float(pv["alpha"])), 2.0 + float(band), true)


func _draw_fg() -> void:
	if state.is_empty() or cockpit_theme == null:
		return
	var ci := fg_layer
	var pv: Dictionary = _planet_view()
	if not pv.is_empty() and Biomes.get_biome(state["planet"]["biome"])["rings"]:
		_draw_rings(ci, pv, false)

	var mode: int = state["mode"]
	var u: float = state["u"]
	var arrived: bool = state["arrived"]
	if mode == Journey.Mode.LANDING or arrived:
		var entry: float = 0.0 if arrived else smoothstep(0.4, 0.52, u) * (1.0 - smoothstep(0.56, 0.7, u))
		var ground_a: float = 1.0 if arrived else smoothstep(0.55, 0.66, u)
		if ground_a > 0.0:
			_draw_ground(ci, ground_a, 1.0 if arrived else clampf((u - 0.6) / 0.4, 0.0, 1.0))
		if entry > 0.0:
			var atmo: Color = Biomes.get_biome(state["planet"]["biome"])["atmo"]
			ci.draw_rect(Rect2(Vector2.ZERO, VIEW), Color(atmo.lightened(0.3), entry * 0.85), true)

	_draw_asteroids(ci)
	for d in debris:
		var p: Vector2 = d["pos"]
		var v: Vector2 = d["vel"]
		ci.draw_line(p, p - v * 0.04, Color(cockpit_theme.asteroid_line, clampf(float(d["life"]) * 1.6, 0.0, 1.0)), 2.0)
	if hit_flash > 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, VIEW), Color(1.0, 0.1, 0.15, hit_flash * 0.3), true)


func _draw_ground(ci: CanvasItem, alpha: float, land_t: float) -> void:
	var t := cockpit_theme
	var biome: Dictionary = Biomes.get_biome(state["planet"]["biome"])
	var atmo: Color = biome["atmo"]
	var horizon: float = VP_BASE.y + 30.0
	var cx: float = vp.x

	# Ciel : degrade de l'espace vers l'atmosphere a l'horizon.
	var bands := 24
	for i in bands:
		var k: float = float(i) / float(bands - 1)
		var col: Color = t.space_color.lerp(atmo * 0.55, k * k)
		var h: float = horizon / float(bands)
		ci.draw_rect(Rect2(0, h * float(i), VIEW.x, h + 1.0), Color(col, alpha), true)

	# Soleil retro a bandes.
	var sun_c := Vector2(cx, horizon - 8.0)
	var sun_r := 95.0
	var sun_col: Color = (biome["b"] as Color).lerp(atmo, 0.5)
	ci.draw_circle(sun_c, sun_r * 1.35, Color(sun_col, 0.12 * alpha))
	ci.draw_circle(sun_c, sun_r, Color(sun_col, alpha))
	for k in 6:
		var y: float = sun_c.y - sun_r * 0.55 + float(k) * 13.0
		ci.draw_rect(Rect2(sun_c.x - sun_r, y, sun_r * 2.0, 2.0 + float(k) * 1.2), Color(t.space_color.lerp(atmo * 0.55, 0.8), alpha), true)

	# Montagnes vectorielles, generees a partir de la graine de la planete.
	var seed_v: float = float(state["planet"]["seed"]) * 17.0
	var ridge := PackedVector2Array()
	var x: float = -20.0
	while x <= VIEW.x + 20.0:
		var n: float = 0.5 + 0.5 * sin(x * 0.013 + seed_v) * cos(x * 0.031 + seed_v * 2.0)
		n += 0.25 * sin(x * 0.07 + seed_v * 3.0)
		ridge.append(Vector2(x, horizon - 12.0 - maxf(n, 0.0) * 70.0))
		x += 18.0
	var fill := ridge.duplicate()
	fill.append(Vector2(VIEW.x + 20.0, horizon + 1.0))
	fill.append(Vector2(-20.0, horizon + 1.0))
	ci.draw_colored_polygon(fill, Color(t.space_color.darkened(0.3), alpha))
	ci.draw_polyline(ridge, Color(atmo, 0.9 * alpha), 2.0, true)

	# Sol : grille neon qui defile de moins en moins vite jusqu'a l'arret.
	ci.draw_rect(Rect2(0, horizon, VIEW.x, VIEW.y - horizon), Color(t.space_color.darkened(0.2).lerp(atmo, 0.04), alpha), true)
	var gcol: Color = t.grid_color.lerp(atmo, 0.35)
	var cam_h: float = lerpf(2.6, 0.7, 1.0 - pow(1.0 - land_t, 2.0))
	var scroll: float = fposmod(ground_scroll, 1.0)
	for i in 30:
		var z: float = (float(i) + 1.0 - scroll) * 0.8
		var y: float = horizon + cam_h * FOCAL / z
		if y > VIEW.y:
			continue
		var fade: float = clampf(1.0 - z / 24.0, 0.0, 1.0)
		ci.draw_line(Vector2(0, y), Vector2(VIEW.x, y), Color(gcol, 0.7 * fade * alpha), 1.5)
	for i in range(-18, 19):
		var wx: float = float(i) * 1.2 - ship_off.x
		var near := Vector2(cx + wx * FOCAL / 0.35, horizon + cam_h * FOCAL / 0.35)
		var far := Vector2(cx + wx * FOCAL / 30.0, horizon + cam_h * FOCAL / 30.0)
		ci.draw_line(far, near, Color(gcol, 0.55 * alpha), 1.5)
	ci.draw_line(Vector2(0, horizon), Vector2(VIEW.x, horizon), Color(atmo.lightened(0.3), alpha), 2.0)


func _draw_asteroids(ci: CanvasItem) -> void:
	if asteroids.is_empty():
		return
	var sorted: Array[Dictionary] = asteroids.duplicate()
	sorted.sort_custom(func(a, b): return a["pos"].z > b["pos"].z)
	for a in sorted:
		var p: Vector3 = a["pos"]
		if p.z < NEAR_Z:
			continue
		var c: Vector2 = _proj(p)
		var rs: float = float(a["radius"]) * FOCAL / p.z
		var fade: float = clampf((FAR_Z - p.z) / 4.0, 0.0, 1.0)
		var pts := PackedVector2Array()
		for v in a["verts"]:
			pts.append(c + (v * rs).rotated(float(a["rot"]) + roll))
		ci.draw_colored_polygon(pts, Color(cockpit_theme.asteroid_fill, fade))
		pts.append(pts[0])
		ci.draw_polyline(pts, Color(cockpit_theme.asteroid_line, 0.25 * fade), 6.0, true)
		ci.draw_polyline(pts, Color(cockpit_theme.asteroid_line, fade), 2.0, true)


func _window_poly() -> PackedVector2Array:
	match cockpit_theme.frame_style:
		"chasseur":
			return PackedVector2Array([Vector2(150, 28), Vector2(750, 28), Vector2(880, 250),
				Vector2(850, 445), Vector2(50, 445), Vector2(20, 250)])
		"passerelle":
			return PackedVector2Array([Vector2(30, 45), Vector2(870, 45), Vector2(870, 440), Vector2(30, 440)])
	var pts := PackedVector2Array()
	for k in 24:
		var ang: float = TAU * float(k) / 24.0
		pts.append(VP_BASE + Vector2(cos(ang) * 440.0, sin(ang) * 262.0))
	return pts


func _draw_frame() -> void:
	if state.is_empty() or cockpit_theme == null:
		return
	var ci := frame_layer
	var t := cockpit_theme
	var win: PackedVector2Array = _window_poly()
	var c: Vector2 = VP_BASE
	var n: int = win.size()
	# Masque : tout ce qui est hors de la verriere (convexe) est rempli par la carlingue.
	for i in n:
		var a: Vector2 = win[i]
		var b: Vector2 = win[(i + 1) % n]
		ci.draw_colored_polygon(PackedVector2Array([a, b, c + (b - c) * 8.0, c + (a - c) * 8.0]), t.frame_fill)
	var inner := PackedVector2Array()
	for p in win:
		inner.append(c + (p - c) * 1.05)
	inner.append(inner[0])
	ci.draw_polyline(inner, Color(t.frame_line, 0.18), 1.0, true)

	match t.frame_style:
		"canopee":
			for deg in [-90.0, -138.0, -42.0, -172.0, -8.0]:
				var d := Vector2.from_angle(deg_to_rad(deg))
				var e := Vector2(d.x * 440.0, d.y * 262.0)
				_strut(ci, c + e * 0.72, c + e * 1.05, 12.0, 40.0)
		"chasseur":
			_strut(ci, Vector2(450, 20), Vector2(450, 70), 16.0, 5.0)
			_strut(ci, Vector2(255, 20), Vector2(30, 330), 12.0, 18.0)
			_strut(ci, Vector2(645, 20), Vector2(870, 330), 12.0, 18.0)
		"passerelle":
			_strut(ci, Vector2(310, 36), Vector2(310, 450), 16.0, 16.0)
			_strut(ci, Vector2(590, 36), Vector2(590, 450), 16.0, 16.0)
	var closed := win.duplicate()
	closed.append(win[0])
	_neon(ci, closed, t.frame_line, 2.0)

	_draw_dashboard(ci)
	_draw_banner(ci)
	_draw_game_hud(ci)


func _strut(ci: CanvasItem, p0: Vector2, p1: Vector2, w0: float, w1: float) -> void:
	var nrm: Vector2 = (p1 - p0).normalized().orthogonal()
	var a := p0 + nrm * w0 * 0.5
	var b := p1 + nrm * w1 * 0.5
	var c := p1 - nrm * w1 * 0.5
	var d := p0 - nrm * w0 * 0.5
	ci.draw_colored_polygon(PackedVector2Array([a, b, c, d]), cockpit_theme.frame_fill)
	ci.draw_line(a, b, Color(cockpit_theme.frame_line, 0.8), 1.5, true)
	ci.draw_line(d, c, Color(cockpit_theme.frame_line, 0.8), 1.5, true)


func _neon(ci: CanvasItem, pts: PackedVector2Array, col: Color, width: float) -> void:
	ci.draw_polyline(pts, Color(col, 0.07), width * 5.0, true)
	ci.draw_polyline(pts, Color(col, 0.2), width * 2.4, true)
	ci.draw_polyline(pts, col, width, true)


func _text(ci: CanvasItem, pos: Vector2, s: String, fs: int, col: Color, center: bool = false) -> void:
	var font: Font = ThemeDB.fallback_font
	var x: float = pos.x
	if center:
		x -= font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5
	ci.draw_string(font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _panel(ci: CanvasItem, r: Rect2, title: String) -> void:
	var t := cockpit_theme
	var k := 10.0
	var pts := PackedVector2Array([
		r.position + Vector2(k, 0), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y - k),
		r.end - Vector2(k, 0), Vector2(r.position.x, r.end.y), r.position + Vector2(0, k), r.position + Vector2(k, 0)])
	ci.draw_colored_polygon(pts, Color(t.frame_line, 0.04))
	ci.draw_polyline(pts, Color(t.frame_line, 0.45), 1.0, true)
	_text(ci, r.position + Vector2(14, 16), title, 10, t.hud_dim)


func _draw_dashboard(ci: CanvasItem) -> void:
	var t := cockpit_theme
	var dash := PackedVector2Array([Vector2(0, 454), Vector2(170, 438), Vector2(730, 438), Vector2(900, 454),
		Vector2(900, 600), Vector2(0, 600)])
	ci.draw_colored_polygon(dash, t.dash_fill)
	_neon(ci, PackedVector2Array([Vector2(0, 454), Vector2(170, 438), Vector2(730, 438), Vector2(900, 454)]), t.frame_line, 1.5)
	if t.frame_style == "chasseur":
		var nose := PackedVector2Array([Vector2(385, 439), Vector2(450, 408), Vector2(515, 439)])
		ci.draw_colored_polygon(nose, t.dash_fill)
		_neon(ci, nose, t.frame_line, 1.5)

	var left := Rect2(22, 462, 250, 112)
	var mid := Rect2(288, 462, 324, 112)
	var right := Rect2(628, 462, 250, 112)
	_panel(ci, left, "NAVIGATION")
	_panel(ci, mid, "PROGRESSION")
	_panel(ci, right, "CHRONO")

	var hl: PackedStringArray = state.get("hud_left", PackedStringArray())
	for i in hl.size():
		_text(ci, left.position + Vector2(14, 42 + 22 * i), hl[i], 14 if i == 0 else 13, t.hud_accent if i == 0 else t.hud_text)
	var hr: PackedStringArray = state.get("hud_right", PackedStringArray())
	for i in hr.size():
		_text(ci, right.position + Vector2(14, 42 + 22 * i), hr[i], 13, t.hud_text)

	# Barre de progression du voyage, avec les planetes-etapes.
	var x0: float = mid.position.x + 22.0
	var x1: float = mid.end.x - 22.0
	var y: float = mid.position.y + 60.0
	var prog: float = clampf(state.get("progress", 0.0), 0.0, 1.0)
	ci.draw_line(Vector2(x0, y), Vector2(x1, y), Color(t.hud_dim, 0.8), 2.0)
	ci.draw_line(Vector2(x0, y), Vector2(lerpf(x0, x1, prog), y), t.hud_accent, 3.0)
	var markers: Array = state.get("markers", [])
	for m in markers:
		var mx: float = lerpf(x0, x1, float(m))
		var passed: bool = float(m) <= prog
		ci.draw_circle(Vector2(mx, y), 5.0, t.hud_accent if passed else t.dash_fill)
		ci.draw_arc(Vector2(mx, y), 5.0, 0.0, TAU, 16, t.hud_accent if passed else t.hud_text, 1.5, true)
	ci.draw_circle(Vector2(x0, y), 4.0, t.hud_text)
	var sx: float = lerpf(x0, x1, prog)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(sx + 8, y - 12), Vector2(sx - 5, y - 18), Vector2(sx - 5, y - 6)]), t.hud_text)
	_text(ci, Vector2((x0 + x1) * 0.5, y + 30.0), String(state.get("hud_mid", "")), 13, t.hud_text, true)

	var hint := "Flèches : piloter  ·  Maj : boost  ·  G : astéroïdes  ·  T : thème cockpit  ·  Tab : carte"
	_text(ci, Vector2(450, 593), hint, 10, Color(t.hud_dim, 0.9), true)


func _draw_banner(ci: CanvasItem) -> void:
	var s: String = state.get("banner", "")
	if s == "":
		return
	var t := cockpit_theme
	var a: float = 0.75 + 0.25 * sin(time * 2.0)
	_text(ci, Vector2(450, 78), s, 17, Color(t.hud_text, a), true)
	var w: float = ThemeDB.fallback_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x * 0.5 + 20.0
	ci.draw_line(Vector2(450 - w, 88), Vector2(450 + w, 88), Color(t.frame_line, 0.5 * a), 1.0)


func _draw_game_hud(ci: CanvasItem) -> void:
	if not game_on:
		return
	var t := cockpit_theme
	var base := Vector2(90, 118)
	var box := Rect2(base + Vector2(-14, -20), Vector2(150, 88))
	ci.draw_rect(box, Color(t.dash_fill, 0.8), true)
	ci.draw_rect(box, Color(t.frame_line, 0.4), false, 1.0)
	_text(ci, base, "ASTÉROÏDES", 12, t.hud_accent)
	_text(ci, base + Vector2(0, 20), "BOUCLIERS", 11, t.hud_dim)
	for k in SHIELDS_MAX:
		var col: Color = t.hud_accent if k < shields else Color(t.hud_dim, 0.4)
		ci.draw_rect(Rect2(base + Vector2(72 + 16 * k, 10), Vector2(11, 12)), col, true)
	_text(ci, base + Vector2(0, 40), "ESQUIVÉS  %d" % dodged, 12, t.hud_text)
	_text(ci, base + Vector2(0, 58), "RECORD  %d" % best, 11, t.hud_dim)
	if not game_over:
		# Reticule : zone d'impact du vaisseau.
		var rr: float = SHIP_RADIUS * FOCAL / HIT_Z
		ci.draw_arc(vp, rr, 0.0, TAU, 48, Color(t.frame_line, 0.18), 1.0, true)
		for q in 4:
			var ang: float = TAU * float(q) / 4.0 + PI * 0.25
			ci.draw_arc(vp, rr, ang - 0.25, ang + 0.25, 8, Color(t.frame_line, 0.6), 2.0, true)
	else:
		_text(ci, Vector2(450, 200), "VAISSEAU TOUCHÉ", 22, t.hud_accent, true)
		_text(ci, Vector2(450, 228), "%d astéroïdes esquivés  —  G pour rejouer" % dodged, 14, t.hud_text, true)
