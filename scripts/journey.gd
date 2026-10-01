extends RefCounted

# Planning du voyage : une suite d'evenements dates (timestamps unix) que le vaisseau
# suit quoi qu'il arrive. La position, le mode de vol et le decor se deduisent de l'heure.
# Chaque troncon entre deux planetes : sortie en sublumiere -> hyperespace -> approche
# en sublumiere -> orbite (ou atterrissage sur la destination finale).

enum Mode { DEPART, HYPER, APPROACH, ORBIT, LANDING }

const DEPART_TIME := 40.0
const APPROACH_TIME := 45.0
const ORBIT_TIME := 150.0
const LANDING_TIME := 75.0
const MAX_FIXED_SHARE := 0.5       # les phases a duree fixe ne prennent jamais plus de la moitie du voyage
const SUBLIGHT_DIST_RATIO := 0.04  # distance parcourue en sublumiere, en fraction du troncon
const MAX_SUBLIGHT_DIST := 260.0
const ORBIT_TURNS := 1.25

var events: Array[Dictionary] = []


# Construit les evenements de `origin_pos` jusqu'au dernier element de `targets`
# (la destination, sur laquelle on atterrit). `origin_id` = -1 si on part du milieu
# de l'espace (replanification en plein vol) : pas de phase de sortie dans ce cas.
static func build(planets: Array[Dictionary], origin_pos: Vector2, origin_id: int,
		targets: Array[int], t_start: float, t_end: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n: int = targets.size()
	if n == 0:
		return out
	var with_depart: bool = origin_id >= 0

	var fixed: float = 0.0
	for i in n:
		if i > 0 or with_depart:
			fixed += DEPART_TIME
		fixed += APPROACH_TIME
		fixed += ORBIT_TIME if i < n - 1 else LANDING_TIME
	var total: float = maxf(t_end - t_start, 1.0)
	var scale: float = minf(1.0, MAX_FIXED_SHARE * total / maxf(fixed, 0.001))

	var froms: Array[Vector2] = [origin_pos]
	for i in range(n - 1):
		froms.append(planets[targets[i]]["pos"])
	var hyper_dists: Array[float] = []
	var sub_dists: Array[float] = []
	var hyper_sum: float = 0.0
	for i in n:
		var leg: float = froms[i].distance_to(planets[targets[i]]["pos"])
		var sd: float = minf(leg * SUBLIGHT_DIST_RATIO, MAX_SUBLIGHT_DIST)
		var departs: bool = i > 0 or with_depart
		var hd: float = maxf(leg - sd - (sd if departs else 0.0), 1.0)
		sub_dists.append(sd)
		hyper_dists.append(hd)
		hyper_sum += hd
	var hyper_time: float = total - fixed * scale

	var t: float = t_start
	var prev_id: int = origin_id
	for i in n:
		var to_id: int = targets[i]
		var a: Vector2 = froms[i]
		var b: Vector2 = planets[to_id]["pos"]
		var dir: Vector2 = (b - a).normalized()
		var sd: float = sub_dists[i]
		var cur: Vector2 = a
		if i > 0 or with_depart:
			var d_end: Vector2 = a + dir * sd
			out.append(_ev(Mode.DEPART, t, t + DEPART_TIME * scale, a, d_end, prev_id, prev_id, to_id))
			t += DEPART_TIME * scale
			cur = d_end
		var h_end: Vector2 = b - dir * sd
		var ht: float = hyper_time * hyper_dists[i] / hyper_sum
		out.append(_ev(Mode.HYPER, t, t + ht, cur, h_end, to_id, prev_id, to_id))
		t += ht
		out.append(_ev(Mode.APPROACH, t, t + APPROACH_TIME * scale, h_end, b, to_id, prev_id, to_id))
		t += APPROACH_TIME * scale
		if i < n - 1:
			out.append(_ev(Mode.ORBIT, t, t + ORBIT_TIME * scale, b, b, to_id, prev_id, to_id))
			t += ORBIT_TIME * scale
		else:
			# Le dernier evenement se termine exactement a l'heure d'arrivee choisie.
			out.append(_ev(Mode.LANDING, t, t_end, b, b, to_id, prev_id, to_id))
		prev_id = to_id
	return out


static func _ev(mode: Mode, t0: float, t1: float, a: Vector2, b: Vector2, planet: int, from: int, to: int) -> Dictionary:
	return {"mode": mode, "t0": t0, "t1": t1, "a": a, "b": b, "planet": planet, "from": from, "to": to}


func index_at(t: float) -> int:
	for i in events.size():
		if t < events[i]["t1"]:
			return i
	return -1


func end_time() -> float:
	return events[events.size() - 1]["t1"] if not events.is_empty() else 0.0


# Etat du vaisseau a l'instant `t`.
func sample(t: float) -> Dictionary:
	var idx: int = index_at(t)
	var done: bool = idx < 0
	if done:
		idx = events.size() - 1
	var ev: Dictionary = events[idx]
	var u: float = 1.0 if done else clampf((t - ev["t0"]) / maxf(ev["t1"] - ev["t0"], 0.001), 0.0, 1.0)
	var a: Vector2 = ev["a"]
	var b: Vector2 = ev["b"]
	var pos: Vector2 = b
	var hyper: float = 0.0
	var orbit_w: float = 0.0
	match ev["mode"]:
		Mode.DEPART:
			pos = a.lerp(b, u * u)
			hyper = smoothstep(0.75, 1.0, u)
		Mode.HYPER:
			pos = a.lerp(b, u)
			hyper = 1.0
		Mode.APPROACH:
			pos = a.lerp(b, 1.0 - (1.0 - u) * (1.0 - u))
			hyper = 1.0 - smoothstep(0.0, 0.15, u)
		Mode.ORBIT:
			orbit_w = smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.88, 1.0, u))
	return {
		"index": idx,
		"mode": ev["mode"],
		"u": u,
		"pos": pos,
		"dir": (b - a).normalized() if a != b else Vector2.ZERO,
		"hyper": hyper,
		"planet": ev["planet"],
		"from": ev["from"],
		"to": ev["to"],
		"orbit_w": orbit_w,
		"orbit_angle": u * TAU * ORBIT_TURNS,
		"done": done,
	}


# Heure de passage (debut d'orbite ou d'atterrissage) de chaque planete encore a venir.
func passage_times(from_t: float) -> Dictionary:
	var out: Dictionary = {}
	for ev in events:
		if (ev["mode"] == Mode.ORBIT or ev["mode"] == Mode.LANDING) and ev["t1"] > from_t:
			out[ev["planet"]] = ev["t0"]
	return out


# Prochaine planete ou le vaisseau s'arrete (orbite ou atterrissage), et l'heure de passage.
func next_stop(t: float) -> Dictionary:
	for ev in events:
		if (ev["mode"] == Mode.ORBIT or ev["mode"] == Mode.LANDING) and ev["t1"] > t:
			return {"planet": ev["planet"], "t": ev["t0"]}
	return {}
