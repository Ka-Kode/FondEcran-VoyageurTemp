extends Node2D

const AppTheme = preload("res://scripts/app_theme.gd")
const Journey = preload("res://scripts/journey.gd")
const Biomes = preload("res://scripts/biomes.gd")

enum Phase { TIME_INPUT, ROUTE_EDIT, FLIGHT, ARRIVED }
enum View { MAP, COCKPIT }

const KIND_START := 0
const KIND_STOP := 1
const KIND_DEST := 2

const CANDIDATE_STOP_COUNT := 10
const MIN_STOP_OFFSET_RATIO := 0.04  # ecart lateral des planetes, en fraction de la longueur du trajet
const MAX_STOP_OFFSET_RATIO := 0.18
const MAX_STOPS := 6

# La carte est bien plus grande que l'ecran : la longueur du trajet suit la duree du voyage.
const ROUTE_LENGTH_PER_MINUTE := 12.0
const MIN_ROUTE_LENGTH := 4000.0
const MAX_ROUTE_LENGTH := 14000.0
const FLIGHT_ZOOM := 0.7          # zoom camera en vol (< 1 : on voit plus loin)
const CAMERA_SMOOTHING := 2.2
const USER_CAMERA_SMOOTHING := 12.0
const MIN_ZOOM := 0.03
const MAX_ZOOM := 3.0
const ZOOM_STEP := 1.18           # facteur par cran de molette
const DRAG_THRESHOLD := 6.0       # px avant qu'un appui devienne un glissement

const HOVER_NONE := -1
const PLANET_NAMES := [
	"Kepler", "Aldera", "Vesper", "Hyperion", "Solace", "Meridian", "Talos", "Nyx",
	"Orpheus", "Cassiel", "Lumen", "Zephyr", "Ossian", "Calypso", "Eos", "Thalassa",
]
const PLANET_CLICK_RADIUS := 26.0 # tolerance de clic (px ecran) pour choisir une planete-etape
const ORBIT_RADIUS_PX := 26.0
const FAST_FORWARD := 60.0        # F8 maintenu : le temps du voyage passe 60x plus vite (test)

const THEME_PATHS := [
	"res://themes/default.tres",
	"res://themes/cyberpunk.tres",
	"res://themes/dystopian.tres",
]
const COCKPIT_THEME_PATHS := [
	"res://cockpit_themes/neon_cyan.tres",
	"res://cockpit_themes/synthwave.tres",
	"res://cockpit_themes/terminal.tres",
]
const SETTINGS_PATH := "user://settings.cfg"

var themes: Array[AppTheme] = []
var current_theme: AppTheme
var cockpit_themes: Array[CockpitTheme] = []
var cockpit_theme_index: int = 0
var view_zoom: float = 1.0
var pan_detached: bool = false    # la camera ne suit plus la vue automatique
var zoom_custom: bool = false
var user_pos: Vector2 = Vector2.ZERO
var user_zoom: float = 1.0
var press_active: bool = false
var press_pos: Vector2 = Vector2.ZERO
var dragging: bool = false
var pan_button_held: bool = false
var hover_id: int = HOVER_NONE
var local_offset: float = 0.0
var route_length: float = 0.0
var time_skip: float = 0.0

var phase: Phase = Phase.TIME_INPUT
var view: View = View.MAP

var planets: Array[Dictionary] = []
var selected: Array[bool] = []
var start_id: int = 0
var dest_id: int = 0

var journey := Journey.new()
var jstate: Dictionary = {}
var ship_pos: Vector2
var ship_draw_pos: Vector2
var heading: Vector2 = Vector2.RIGHT
var trail := PackedVector2Array()

var journey_start_unix: float = 0.0
var target_arrival_unix: float = 0.0

@onready var camera: Camera2D = $Camera
@onready var sky: Node2D = $Background/Sky
@onready var cockpit_layer: CanvasLayer = $CockpitLayer
@onready var cockpit: Control = $CockpitLayer/Cockpit
@onready var view_button: Button = $UI/ViewButton
@onready var cockpit_button: Button = $UI/CockpitButton
@onready var controls_label: Label = $UI/ControlsLabel
@onready var hint_label: Label = $UI/HintLabel
@onready var stats_label: Label = $UI/StatsLabel
@onready var time_panel: PanelContainer = $UI/TimePanel
@onready var hour_spin: SpinBox = $UI/TimePanel/VBox/TimeRow/HourSpin
@onready var minute_spin: SpinBox = $UI/TimePanel/VBox/TimeRow/MinuteSpin
@onready var validate_button: Button = $UI/TimePanel/VBox/ValidateButton
@onready var start_button: Button = $UI/StartButton
@onready var arrival_panel: PanelContainer = $UI/ArrivalPanel
@onready var summary_label: Label = $UI/ArrivalPanel/VBox/SummaryLabel
@onready var new_trip_button: Button = $UI/ArrivalPanel/VBox/NewTripButton
@onready var theme_option: OptionButton = $UI/ThemeOption
@onready var cockpit_theme_option: OptionButton = $UI/CockpitThemeOption


func _ready() -> void:
	validate_button.pressed.connect(_on_time_validated)
	start_button.pressed.connect(_on_start_pressed)
	new_trip_button.pressed.connect(_on_new_trip)
	view_button.pressed.connect(_on_view_button_pressed)
	cockpit_button.pressed.connect(_toggle_view)
	cockpit.best_score_changed.connect(_on_best_score)
	# Les boutons ne prennent pas le focus clavier : les fleches et Espace servent au pilotage.
	for b in [view_button, cockpit_button, start_button, new_trip_button, theme_option, cockpit_theme_option]:
		b.focus_mode = Control.FOCUS_NONE

	for path in THEME_PATHS:
		themes.append(load(path) as AppTheme)
	for t in themes:
		theme_option.add_item("Galaxie : " + t.display_name)
	theme_option.item_selected.connect(_on_theme_selected)
	for path in COCKPIT_THEME_PATHS:
		cockpit_themes.append(load(path) as CockpitTheme)
	for t in cockpit_themes:
		cockpit_theme_option.add_item("Cockpit : " + t.display_name)
	cockpit_theme_option.item_selected.connect(_on_cockpit_theme_selected)

	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	_on_theme_selected(clampi(int(cfg.get_value("app", "theme_index", 0)), 0, themes.size() - 1))
	_on_cockpit_theme_selected(clampi(int(cfg.get_value("app", "cockpit_theme_index", 0)), 0, cockpit_themes.size() - 1))
	cockpit.best = int(cfg.get_value("app", "asteroid_best", 0))
	_set_view(View.MAP)


func _save_setting(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("app", key, value)
	cfg.save(SETTINGS_PATH)


func _on_theme_selected(index: int) -> void:
	current_theme = themes[index]
	theme_option.select(index)
	sky.set_app_theme(current_theme)
	for lbl in [hint_label, stats_label, summary_label, controls_label]:
		lbl.add_theme_color_override("font_color", current_theme.text_color)
	_save_setting("theme_index", index)
	queue_redraw()


func _on_cockpit_theme_selected(index: int) -> void:
	cockpit_theme_index = index
	cockpit_theme_option.select(index)
	cockpit.set_cockpit_theme(cockpit_themes[index])
	_save_setting("cockpit_theme_index", index)


func _on_best_score(score: int) -> void:
	_save_setting("asteroid_best", score)


func _now() -> float:
	return Time.get_unix_time_from_system() + time_skip


# --- Vues ---------------------------------------------------------------------

func _toggle_view() -> void:
	if phase != Phase.FLIGHT and phase != Phase.ARRIVED:
		return
	_set_view(View.MAP if view == View.COCKPIT else View.COCKPIT)


func _set_view(v: View) -> void:
	view = v
	var in_cockpit: bool = v == View.COCKPIT
	cockpit_layer.visible = in_cockpit
	cockpit.visible = in_cockpit
	for c in [hint_label, stats_label, controls_label, theme_option, cockpit_theme_option]:
		c.visible = not in_cockpit
	cockpit_button.text = "Carte (Tab)" if in_cockpit else "Cockpit (Tab)"
	cockpit_button.visible = phase == Phase.FLIGHT or phase == Phase.ARRIVED
	get_viewport().gui_release_focus()
	_update_view_button()


func _input(event: InputEvent) -> void:
	# Intercepte avant l'interface : Tab sert sinon a la navigation entre boutons.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB:
				_toggle_view()
				get_viewport().set_input_as_handled()
			KEY_T:
				if view == View.COCKPIT:
					_on_cockpit_theme_selected((cockpit_theme_index + 1) % cockpit_themes.size())
					get_viewport().set_input_as_handled()


# --- Preparation du voyage ----------------------------------------------------

func _on_time_validated() -> void:
	# Time.get_datetime_dict_from_system() renvoie l'heure locale,
	# mais Time.get_unix_time_from_datetime_dict() traite les champs comme de l'UTC.
	# On mesure donc le decalage local <-> UTC une fois, et on le reapplique pour
	# convertir l'heure locale choisie en un vrai timestamp unix (UTC).
	var now_unix: float = Time.get_unix_time_from_system()
	var local_now: Dictionary = Time.get_datetime_dict_from_system()
	local_offset = Time.get_unix_time_from_datetime_dict(local_now) - now_unix
	time_skip = 0.0

	var target_dict: Dictionary = {
		"year": local_now["year"],
		"month": local_now["month"],
		"day": local_now["day"],
		"hour": int(hour_spin.value),
		"minute": int(minute_spin.value),
		"second": 0,
	}
	var target_unix: float = Time.get_unix_time_from_datetime_dict(target_dict) - local_offset
	if target_unix <= now_unix:
		target_unix += 86400.0
	target_arrival_unix = target_unix

	var minutes: float = (target_unix - now_unix) / 60.0
	route_length = clampf(minutes * ROUTE_LENGTH_PER_MINUTE, MIN_ROUTE_LENGTH, MAX_ROUTE_LENGTH)
	_generate_planets()

	time_panel.visible = false
	start_button.visible = true
	hint_label.text = "Clique sur les planètes pour choisir tes étapes (0 à %d), puis démarre le voyage." % MAX_STOPS
	phase = Phase.ROUTE_EDIT
	_reset_view()
	queue_redraw()


func _generate_planets() -> void:
	planets.clear()
	selected.clear()
	var names: Array = PLANET_NAMES.duplicate()
	names.shuffle()
	var biome_count: int = Biomes.LIST.size()
	start_id = 0
	planets.append({"pos": Vector2.ZERO, "name": names[0], "kind": KIND_START, "biome": randi() % biome_count, "seed": randf()})
	for i in CANDIDATE_STOP_COUNT:
		var t: float = lerpf(0.08, 0.92, float(i) / float(CANDIDATE_STOP_COUNT - 1)) + randf_range(-0.03, 0.03)
		var side: float = 1.0 if (i % 2 == 0) == (randf() < 0.75) else -1.0
		var y: float = side * randf_range(MIN_STOP_OFFSET_RATIO, MAX_STOP_OFFSET_RATIO) * route_length
		planets.append({"pos": Vector2(t * route_length, y), "name": names[i + 1], "kind": KIND_STOP, "biome": randi() % biome_count, "seed": randf()})
	dest_id = planets.size()
	planets.append({"pos": Vector2(route_length, 0.0), "name": names[CANDIDATE_STOP_COUNT + 1], "kind": KIND_DEST, "biome": randi() % biome_count, "seed": randf()})
	for p in planets:
		selected.append(false)


func _selected_count() -> int:
	var n := 0
	for s in selected:
		if s:
			n += 1
	return n


# Etapes choisies, triees dans l'ordre du voyage (de gauche a droite), destination incluse.
func _route_ids(after_x: float = -INF, exclude: int = -1) -> Array[int]:
	var ids: Array[int] = []
	for i in planets.size():
		if selected[i] and i != exclude and planets[i]["pos"].x > after_x:
			ids.append(i)
	ids.sort_custom(func(a, b): return planets[a]["pos"].x < planets[b]["pos"].x)
	ids.append(dest_id)
	return ids


func _on_start_pressed() -> void:
	journey_start_unix = _now()
	journey.events = Journey.build(planets, planets[start_id]["pos"], start_id, _route_ids(),
		journey_start_unix, target_arrival_unix)
	ship_pos = planets[start_id]["pos"]
	ship_draw_pos = ship_pos
	trail = PackedVector2Array([ship_pos])
	start_button.visible = false
	hint_label.text = "En route ! Clique une planète devant le vaisseau pour ajouter ou retirer une étape."
	phase = Phase.FLIGHT
	_reset_view()
	_set_view(View.COCKPIT)


# Recalcule le planning apres un changement d'etapes en vol, sans toucher au passe.
func _replan() -> void:
	var now: float = _now()
	var idx: int = journey.index_at(now)
	if idx < 0:
		return
	var ev: Dictionary = journey.events[idx]
	# Le passe est conserve (trace, marqueurs d'etapes franchies).
	var keep: Array[Dictionary] = journey.events.slice(0, idx)
	var origin_id: int = -1
	var origin_pos: Vector2 = ship_pos
	var t0: float = now
	match ev["mode"]:
		Journey.Mode.LANDING:
			return
		Journey.Mode.APPROACH, Journey.Mode.ORBIT:
			# On termine l'approche et l'orbite en cours, puis on repart vers le nouvel itineraire.
			var j: int = idx
			while j < journey.events.size() and journey.events[j]["mode"] != Journey.Mode.ORBIT:
				if journey.events[j]["mode"] == Journey.Mode.LANDING:
					return
				j += 1
			keep.append_array(journey.events.slice(idx, j + 1))
			origin_id = journey.events[j]["planet"]
			origin_pos = planets[origin_id]["pos"]
			t0 = journey.events[j]["t1"]
		_:
			# En plein vol : le troncon en cours s'arrete ici, le nouveau part de la position actuelle.
			var cut: Dictionary = ev.duplicate()
			cut["t1"] = now
			cut["b"] = ship_pos
			keep.append(cut)
	var targets: Array[int] = _route_ids(origin_pos.x + 1.0, origin_id)
	var fresh: Array[Dictionary] = Journey.build(planets, origin_pos, origin_id, targets, t0, target_arrival_unix)
	journey.events = keep + fresh


# Planete verrouillee (approche ou orbite en cours) : on ne peut plus la retirer.
func _locked_planet() -> int:
	if jstate.is_empty():
		return -1
	if jstate["mode"] == Journey.Mode.APPROACH or jstate["mode"] == Journey.Mode.ORBIT:
		return jstate["planet"]
	return -1


func _can_toggle(i: int) -> bool:
	if planets[i]["kind"] != KIND_STOP:
		return false
	if phase == Phase.ROUTE_EDIT:
		return selected[i] or _selected_count() < MAX_STOPS
	if phase != Phase.FLIGHT or i == _locked_planet():
		return false
	if jstate.get("mode", -1) == Journey.Mode.LANDING:
		return false
	var margin: float = route_length * 0.01
	var ref_x: float = ship_pos.x
	if _locked_planet() >= 0:
		ref_x = planets[_locked_planet()]["pos"].x
	if planets[i]["pos"].x <= ref_x + margin:
		return false
	return selected[i] or _selected_count() < MAX_STOPS


func _try_toggle_stop(click_pos: Vector2) -> void:
	for i in planets.size():
		if click_pos.distance_to(planets[i]["pos"]) * view_zoom <= PLANET_CLICK_RADIUS:
			if not _can_toggle(i):
				return
			selected[i] = not selected[i]
			if phase == Phase.FLIGHT:
				_replan()
			queue_redraw()
			return


# --- Entrees carte ------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.TIME_INPUT or view == View.COCKPIT:
		return

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					press_active = true
					press_pos = event.position
					dragging = false
				else:
					# Le clic n'est valide qu'au relachement et sans glissement,
					# pour ne pas confondre "deplacer la carte" et "cliquer une planete".
					if press_active and not dragging:
						_try_toggle_stop(get_global_mouse_position())
					press_active = false
					dragging = false
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				pan_button_held = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_by(ZOOM_STEP, event.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_by(1.0 / ZOOM_STEP, event.position)
	elif event is InputEventMouseMotion:
		if press_active and not dragging and event.position.distance_to(press_pos) > DRAG_THRESHOLD:
			dragging = true
		if dragging or pan_button_held:
			_pan_by(event.relative)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R, KEY_HOME:
				_reset_view()
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				_zoom_by(ZOOM_STEP, get_viewport_rect().size * 0.5)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_zoom_by(1.0 / ZOOM_STEP, get_viewport_rect().size * 0.5)


func _reset_view() -> void:
	pan_detached = false
	zoom_custom = false


func _pan_by(rel: Vector2) -> void:
	if not pan_detached:
		user_pos = camera.position
		pan_detached = true
	user_pos -= rel / view_zoom
	var bounds: Rect2 = _overview_rect().grow(maxf(route_length * 0.15, 400.0))
	user_pos = user_pos.clamp(bounds.position, bounds.end)
	camera.position = user_pos


func _zoom_by(factor: float, screen_pos: Vector2) -> void:
	var cur_zoom: float = user_zoom if zoom_custom else view_zoom
	var new_zoom: float = clampf(cur_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	# En vol, tant que la vue suit le vaisseau, on zoome sur lui ; sinon on zoome sous le curseur.
	if pan_detached or phase != Phase.FLIGHT:
		var offset: Vector2 = screen_pos - get_viewport_rect().size * 0.5
		var cur_pos: Vector2 = user_pos if pan_detached else camera.position
		var world_pt: Vector2 = cur_pos + offset / cur_zoom
		user_pos = world_pt - offset / new_zoom
		pan_detached = true
	user_zoom = new_zoom
	zoom_custom = true


# --- Boucle -------------------------------------------------------------------

func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_F8) and phase == Phase.FLIGHT:
		time_skip += delta * (FAST_FORWARD - 1.0)
	# Economie de ressources : l'app tourne toute la journee en arriere-plan.
	var focused: bool = get_window().has_focus()
	Engine.max_fps = (60 if view == View.COCKPIT else 30) if focused else 20

	if phase == Phase.FLIGHT:
		_update_flight()
	if phase == Phase.FLIGHT or phase == Phase.ARRIVED:
		cockpit.update_state(_cockpit_state())
	_update_camera(delta)
	_update_hover()
	_update_view_button()
	queue_redraw()


func _update_flight() -> void:
	var now: float = _now()
	jstate = journey.sample(now)
	ship_pos = jstate["pos"]
	ship_draw_pos = ship_pos
	if jstate["dir"] != Vector2.ZERO:
		heading = jstate["dir"]
	if jstate["mode"] == Journey.Mode.ORBIT:
		var ang: float = jstate["orbit_angle"]
		ship_draw_pos = ship_pos + Vector2.from_angle(ang) * _px(ORBIT_RADIUS_PX) * float(jstate["orbit_w"])
		heading = Vector2.from_angle(ang + PI * 0.5)
	if trail.is_empty() or trail[trail.size() - 1].distance_to(ship_pos) > route_length / 600.0:
		trail.append(ship_pos)
	_update_stats_label(now)
	if jstate["done"]:
		_show_arrival()


func _update_stats_label(now: float) -> void:
	var elapsed: float = now - journey_start_unix
	var remaining: float = maxf(target_arrival_unix - now, 0.0)
	var total: float = maxf(target_arrival_unix - journey_start_unix, 0.001)
	var txt: String = "Temps : %s écoulé · %s restant (%d%%) · arrivée %s" % [
		_format_duration(elapsed), _format_duration(remaining),
		int(round(clampf(elapsed / total, 0.0, 1.0) * 100.0)), _clock(target_arrival_unix)]
	var ns: Dictionary = journey.next_stop(now)
	if not ns.is_empty():
		txt += "\n%s : %s — passage %s · %s" % [
			_mode_label(jstate["mode"], jstate["u"]).capitalize(), planets[ns["planet"]]["name"],
			_clock(ns["t"]), Biomes.get_biome(planets[ns["planet"]]["biome"])["name"]]
	if time_skip > 0.0:
		txt += "\n[avance rapide F8 : +%s]" % _format_duration(time_skip)
	stats_label.text = txt


func _mode_label(mode: int, u: float) -> String:
	match mode:
		Journey.Mode.DEPART:
			return "SAUT" if u > 0.75 else "SUBLUMIÈRE"
		Journey.Mode.HYPER:
			return "HYPERESPACE"
		Journey.Mode.APPROACH:
			return "SUBLUMIÈRE"
		Journey.Mode.ORBIT:
			return "ORBITE"
		Journey.Mode.LANDING:
			return "ATTERRISSAGE"
	return ""


# Donnees transmises a la vue cockpit : decor, planete visible, textes du tableau de bord.
func _cockpit_state() -> Dictionary:
	var now: float = _now()
	var arrived: bool = phase == Phase.ARRIVED
	var mode: int = jstate["mode"]
	var u: float = jstate["u"]
	var from_id: int = jstate["from"]
	var to_id: int = jstate["to"]
	var shown_id: int = jstate["planet"]
	if arrived:
		shown_id = dest_id
		from_id = dest_id
		to_id = dest_id
	if from_id < 0:
		from_id = to_id
	var region_u: float = 0.0
	match mode:
		Journey.Mode.HYPER:
			region_u = u
		Journey.Mode.APPROACH, Journey.Mode.ORBIT, Journey.Mode.LANDING:
			region_u = 1.0
	var target: Dictionary = planets[to_id]
	var shown: Dictionary = planets[shown_id]
	var biome_name: String = Biomes.get_biome(target["biome"])["name"]

	var banner := ""
	if arrived:
		banner = "Bienvenue sur %s" % shown["name"]
	else:
		match mode:
			Journey.Mode.DEPART:
				if u < 0.35:
					banner = "Départ de %s" % planets[shown_id]["name"]
				elif u > 0.65:
					banner = "Saut vers %s" % target["name"]
			Journey.Mode.APPROACH:
				if u < 0.5:
					banner = "Système %s — %s" % [target["name"], biome_name]
			Journey.Mode.ORBIT:
				if u < 0.6:
					banner = "Orbite autour de %s" % target["name"]
			Journey.Mode.LANDING:
				banner = "Atterrissage sur %s" % target["name"]

	var passages: Dictionary = journey.passage_times(journey_start_unix)
	var total: float = maxf(target_arrival_unix - journey_start_unix, 0.001)
	var markers: Array = []
	for pid in passages:
		markers.append(clampf((float(passages[pid]) - journey_start_unix) / total, 0.0, 1.0))
	var ns: Dictionary = journey.next_stop(now)
	var eta: String = _clock(ns["t"]) if not ns.is_empty() else "--:--"
	var hud_left := PackedStringArray()
	hud_left.append("POSÉ" if arrived else _mode_label(mode, u))
	hud_left.append("VERS  %s" % target["name"])
	hud_left.append(("RÉGION  %s" % biome_name) if arrived else ("PASSAGE  %s" % eta))
	var hud_right := PackedStringArray()
	hud_right.append("ARRIVÉE   %s" % _clock(target_arrival_unix))
	hud_right.append("RESTANT   %s" % _format_duration(maxf(target_arrival_unix - now, 0.0)))
	hud_right.append("HEURE     %s" % _clock(now))

	return {
		"mode": mode,
		"u": u,
		"hyper": 0.0 if arrived else float(jstate["hyper"]),
		"arrived": arrived,
		"region_from": planets[from_id]["biome"],
		"region_to": target["biome"],
		"region_u": region_u,
		"planet": {"biome": shown["biome"], "seed": shown["seed"], "name": shown["name"]},
		"banner": banner,
		"hud_left": hud_left,
		"hud_right": hud_right,
		"hud_mid": "Voyage terminé" if arrived else "%d %%  ·  prochaine : %s" % [int(round(clampf((now - journey_start_unix) / total, 0.0, 1.0) * 100.0)), target["name"]],
		"progress": clampf((now - journey_start_unix) / total, 0.0, 1.0),
		"markers": markers,
	}


func _show_arrival() -> void:
	phase = Phase.ARRIVED
	arrival_panel.visible = true
	summary_label.text = "Posé sur %s à %s.\nBelle journée de voyage !" % [planets[dest_id]["name"], _clock(_now())]
	hint_label.text = ""
	_update_stats_label(_now())


func _on_new_trip() -> void:
	arrival_panel.visible = false
	time_panel.visible = true
	hint_label.text = "Choisis l'heure à laquelle tu comptes finir ta journée."
	stats_label.text = ""
	phase = Phase.TIME_INPUT
	jstate = {}
	time_skip = 0.0
	_set_view(View.MAP)
	_reset_view()
	queue_redraw()


# --- Camera -------------------------------------------------------------------

func _update_view_button() -> void:
	var customized: bool = pan_detached or zoom_custom
	view_button.visible = view == View.MAP and ((phase == Phase.FLIGHT) or (customized and phase != Phase.TIME_INPUT))
	view_button.text = "Recentrer (R)" if customized else "Vue d'ensemble"
	cockpit_button.visible = phase == Phase.FLIGHT or phase == Phase.ARRIVED


func _on_view_button_pressed() -> void:
	if pan_detached or zoom_custom:
		_reset_view()
		return
	# Vue d'ensemble en vol : tout le trajet, sans suivre le vaisseau.
	var r: Rect2 = _overview_rect()
	user_pos = r.get_center()
	user_zoom = _overview_zoom(r)
	pan_detached = true
	zoom_custom = true


func _update_hover() -> void:
	hover_id = HOVER_NONE
	if phase == Phase.TIME_INPUT or view == View.COCKPIT or dragging or pan_button_held:
		Input.set_default_cursor_shape(Input.CURSOR_MOVE if (dragging or pan_button_held) else Input.CURSOR_ARROW)
		return
	var m: Vector2 = get_global_mouse_position()
	var best: float = PLANET_CLICK_RADIUS
	for i in planets.size():
		var d: float = m.distance_to(planets[i]["pos"]) * view_zoom
		if d <= best:
			hover_id = i
			best = d
	var clickable: bool = hover_id >= 0 and _can_toggle(hover_id)
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if clickable else Input.CURSOR_ARROW)


func _overview_rect() -> Rect2:
	var r := Rect2(planets[start_id]["pos"], Vector2.ZERO) if not planets.is_empty() else Rect2()
	for p in planets:
		r = r.expand(p["pos"])
	return r


func _overview_zoom(r: Rect2) -> float:
	var v: Vector2 = get_viewport_rect().size
	var z: float = minf(v.x * 0.82 / maxf(r.size.x, 1.0), v.y * 0.6 / maxf(r.size.y, 1.0))
	return minf(z, 1.0)


func _update_camera(delta: float) -> void:
	var goal_pos: Vector2 = Vector2.ZERO
	var goal_zoom: float = 1.0
	match phase:
		Phase.ROUTE_EDIT, Phase.ARRIVED:
			# Vue d'ensemble du trajet complet, comme une carte.
			var r: Rect2 = _overview_rect()
			goal_pos = r.get_center()
			goal_zoom = _overview_zoom(r)
		Phase.FLIGHT:
			goal_pos = ship_draw_pos
			goal_zoom = FLIGHT_ZOOM
	if pan_detached:
		goal_pos = user_pos
	if zoom_custom:
		goal_zoom = user_zoom
	# Reponse vive quand le joueur pilote la camera, transition douce pour les mouvements automatiques.
	var smoothing: float = USER_CAMERA_SMOOTHING if (pan_detached or zoom_custom) else CAMERA_SMOOTHING
	var k: float = 1.0 - exp(-delta * smoothing)
	camera.position = camera.position.lerp(goal_pos, k)
	view_zoom = exp(lerpf(log(view_zoom), log(goal_zoom), k))
	camera.zoom = Vector2(view_zoom, view_zoom)
	sky.update_view(camera.position, view_zoom, heading, phase == Phase.FLIGHT)


# Convertit une taille en pixels ecran en unites monde (pour garder une taille constante a l'ecran).
func _px(v: float) -> float:
	return v / view_zoom


func _format_duration(seconds: float) -> String:
	var s: int = int(max(seconds, 0.0))
	var h: int = s / 3600
	var m: int = (s % 3600) / 60
	var sec: int = s % 60
	return "%d:%02d:%02d" % [h, m, sec]


func _clock(unix: float) -> String:
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(int(unix + local_offset))
	return "%02d:%02d" % [d["hour"], d["minute"]]


# --- Dessin de la carte -------------------------------------------------------

func _draw() -> void:
	if phase == Phase.TIME_INPUT or view == View.COCKPIT:
		return

	# Regions : chaque planete colore l'espace autour d'elle (le "paysage" du trajet).
	var region_r: float = route_length * 0.09
	for p in planets:
		var col: Color = Biomes.map_color(p["biome"])
		for i in 6:
			var k: float = float(i) / 5.0
			draw_circle(p["pos"], region_r * (1.0 - k * 0.8), Color(col, 0.018))

	_draw_route()

	for i in planets.size():
		var p: Dictionary = planets[i]
		var col: Color = Biomes.map_color(p["biome"])
		var radius: float = 10.0
		if p["kind"] == KIND_DEST:
			radius = 17.0
		elif p["kind"] == KIND_START:
			radius = 13.0
		var is_stop: bool = selected[i]
		if p["kind"] == KIND_STOP and not is_stop and phase != Phase.ROUTE_EDIT:
			col = Color(col, 0.55)
		_draw_planet(p["pos"], radius, col, is_stop or p["kind"] == KIND_DEST)
		if is_stop:
			draw_arc(p["pos"], _px(radius + 5.0), 0.0, TAU, 40, current_theme.planet_selected, _px(2.0), true)
		if view_zoom >= 0.25 or p["kind"] != KIND_STOP or is_stop:
			_draw_label(p["pos"] + Vector2(0, _px(radius + 16.0)), p["name"], Color(current_theme.text_color, 0.7))

	if hover_id != HOVER_NONE:
		var hr: float = 20.0 if planets[hover_id]["kind"] == KIND_DEST else 15.0
		var ok: bool = _can_toggle(hover_id)
		draw_arc(planets[hover_id]["pos"], _px(hr), 0.0, TAU, 40, Color(current_theme.planet_selected, 0.8 if ok else 0.3), _px(1.5), true)

	if phase == Phase.FLIGHT:
		_draw_ship()

	if hover_id != HOVER_NONE:
		_draw_tooltip(planets[hover_id]["pos"], _tooltip_lines(hover_id))


func _draw_route() -> void:
	var col: Color = current_theme.planned_route_color
	if phase == Phase.ROUTE_EDIT:
		var prev: Vector2 = planets[start_id]["pos"]
		for id in _route_ids():
			_draw_dashed(prev, planets[id]["pos"], Color(col, 0.8))
			prev = planets[id]["pos"]
		return
	# Deja parcouru : trace pleine attenuee. A venir : planning actuel.
	if trail.size() >= 2:
		var pts := trail.duplicate()
		pts.append(ship_pos)
		draw_polyline(pts, Color(current_theme.ship_color, 0.35), _px(2.0), true)
	if phase == Phase.FLIGHT:
		var now: float = _now()
		var prev: Vector2 = ship_pos
		for ev in journey.events:
			if ev["t1"] <= now:
				continue
			var b: Vector2 = ev["b"]
			if b != prev:
				draw_line(prev, b, col, _px(2.0), true)
				prev = b


func _tooltip_lines(id: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var p: Dictionary = planets[id]
	lines.append(p["name"])
	lines.append("Planète %s" % Biomes.get_biome(p["biome"])["name"].to_lower())
	if p["kind"] == KIND_START:
		lines.append("Point de départ")
		return lines
	if p["kind"] == KIND_DEST:
		lines.append("Destination — atterrissage à %s" % _clock(target_arrival_unix))
		return lines
	if phase == Phase.FLIGHT:
		var passages: Dictionary = journey.passage_times(_now())
		if passages.has(id):
			lines.append("Étape — orbite à %s" % _clock(passages[id]))
	elif phase == Phase.ROUTE_EDIT and selected[id]:
		lines.append("Étape")
	if _can_toggle(id):
		lines.append("Clic pour retirer l'étape" if selected[id] else "Clic pour ajouter l'étape")
	elif phase != Phase.ARRIVED and not selected[id] and _selected_count() >= MAX_STOPS:
		lines.append("Maximum d'étapes atteint")
	elif phase == Phase.FLIGHT:
		lines.append("Hors de portée (derrière le vaisseau)")
	return lines


# Texte a taille ecran constante, centre horizontalement sur `pos`.
func _draw_label(pos: Vector2, text: String, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_set_transform(pos, 0.0, Vector2(_px(1.0), _px(1.0)))
	draw_string(font, Vector2(-w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_tooltip(anchor: Vector2, lines: PackedStringArray) -> void:
	var font: Font = ThemeDB.fallback_font
	var fs := 13
	var pad := 8.0
	var lh := 18.0
	var w := 0.0
	for l in lines:
		w = maxf(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var box := Vector2(w + pad * 2.0, lines.size() * lh + pad * 2.0)

	# Position ecran de l'ancre, pour garder l'infobulle dans la fenetre.
	var v: Vector2 = get_viewport_rect().size
	var screen: Vector2 = (anchor - camera.position) * view_zoom + v * 0.5
	var origin := Vector2(18.0, -box.y - 10.0)
	if screen.x + origin.x + box.x > v.x - 8.0:
		origin.x = -box.x - 18.0
	if screen.y + origin.y < 8.0:
		origin.y = 18.0

	draw_set_transform(anchor, 0.0, Vector2(_px(1.0), _px(1.0)))
	draw_rect(Rect2(origin, box), Color(0.04, 0.05, 0.09, 0.9), true)
	draw_rect(Rect2(origin, box), Color(current_theme.planet_selected, 0.6), false, 1.0)
	for i in lines.size():
		var col: Color = current_theme.planet_dest if i == 0 else Color(current_theme.text_color, 0.9)
		draw_string(font, origin + Vector2(pad, pad + lh * (float(i) + 0.75)), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_planet(pos: Vector2, radius_px: float, color: Color, glow: bool) -> void:
	var r: float = _px(radius_px)
	if glow:
		for i in 5:
			var k: float = float(i) / 4.0
			draw_circle(pos, r * (2.6 - k * 1.4), Color(color.r, color.g, color.b, color.a * 0.045))
	draw_circle(pos, r, color)
	# Reflet et liseré : donne du volume au disque.
	draw_circle(pos + Vector2(-0.3, -0.3) * r, r * 0.55, Color(1, 1, 1, 0.12 * color.a))
	draw_arc(pos, r, 0.0, TAU, 32, Color(color.lightened(0.5), 0.55 * color.a), _px(1.2), true)


func _draw_ship() -> void:
	var s: float = _px(1.0)
	var mode: int = jstate.get("mode", Journey.Mode.HYPER)
	if mode == Journey.Mode.LANDING:
		s *= 1.0 - 0.8 * float(jstate["u"])
	var fwd: Vector2 = heading
	var side: Vector2 = fwd.orthogonal()
	var col := current_theme.ship_color
	var p: Vector2 = ship_draw_pos
	draw_circle(p, 18.0 * s, Color(col, 0.08))
	var hyper: float = jstate.get("hyper", 0.0)
	if hyper > 0.0:
		draw_line(p - fwd * 8.0 * s, p - fwd * (8.0 + 60.0 * hyper) * s, Color(col, 0.35 * hyper), 3.0 * s, true)
	draw_circle(p - fwd * 9.0 * s, 5.0 * s, Color(col, 0.22))
	draw_circle(p - fwd * 8.0 * s, 2.5 * s, Color(col, 0.5))
	var hull := PackedVector2Array([
		p + fwd * 11.0 * s,
		p - fwd * 7.0 * s + side * 6.0 * s,
		p - fwd * 3.0 * s,
		p - fwd * 7.0 * s - side * 6.0 * s,
	])
	draw_colored_polygon(hull, col)


func _draw_dashed(a: Vector2, b: Vector2, color: Color) -> void:
	var dist: float = a.distance_to(b)
	var dir: Vector2 = (b - a).normalized()
	var dash: float = _px(10.0)
	var gap: float = _px(6.0)
	var t := 0.0
	while t < dist:
		var seg_end: float = min(t + dash, dist)
		draw_line(a + dir * t, a + dir * seg_end, color, _px(1.5), true)
		t += dash + gap
