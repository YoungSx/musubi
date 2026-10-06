class_name PassageChoice
extends RefCounted
## Bounded, time-based evidence for simultaneous hypotheses. A tied or missing
## route never locks; a stable winner must earn fresh evidence after switching.
var tracks: Array[Dictionary] = []
var ambiguous := false
var confidence := 0.0
var _winner := {}
var _dwell := 0.0
var _travel := 0.0

func clear() -> void:
	tracks.clear()
	_winner.clear()
	_dwell = 0
	_travel = 0
	confidence = 0
	ambiguous = false

func update(candidates: Array[Dictionary], continuity: float, movement: float,
		dt: float, segments: int, radius: float) -> Dictionary:
	dt = clampf(dt,0,0.04)
	for track in tracks: track.missing += dt
	for candidate in candidates:
		var matched := -1
		for i in tracks.size():
			if _same(tracks[i].candidate,candidate,segments):
				matched = i
				break
		var score: float = candidate.alignment * 0.45 + continuity * 0.2 + clampf(1.0-candidate.distance/0.18,0,1)*0.25 + 0.1
		if matched < 0:
			if tracks.size() >= 16: continue
			tracks.append({"candidate":candidate,"score":score,"missing":0.0})
		else:
			tracks[matched].score = lerpf(tracks[matched].score,score,1.0-exp(-dt/0.04))
			tracks[matched].candidate = candidate
			tracks[matched].missing = 0.0
	tracks = tracks.filter(func(t: Dictionary): return t.missing < 0.12)
	var current := tracks.filter(func(t: Dictionary): return t.missing == 0)
	current.sort_custom(func(a: Dictionary,b: Dictionary): return a.score > b.score)
	ambiguous = current.size() > 1 and current[0].score-current[1].score < 0.1
	if current.is_empty() or current[0].score < 0.7 or ambiguous:
		_dwell = maxf(0,_dwell-dt*2)
		confidence = clampf(_dwell/0.12,0,1)
		return {}
	var winner: Dictionary = current[0].candidate
	if _winner.is_empty() or not _same(_winner,winner,segments):
		_dwell = 0
		_travel = 0
	_winner = winner
	_dwell += dt
	_travel += movement
	confidence = clampf(_dwell/0.12,0,1)
	return winner if confidence >= 1 and _travel > radius else {}

func _same(a: Dictionary,b: Dictionary,segments: int) -> bool:
	return a.loop.id == b.loop.id and absf(float(a.u)-float(b.u))*segments <= 3
