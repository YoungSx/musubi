class_name OctopusArm
extends RefCounted
## Elastic reach for one arm. Pure geometry: no nodes, no input, no rope.
##
## Reach is not limited by a length. The shoulder is wherever the body is and
## the anchor is wherever the grabbed material is; extension only decides how
## far along that span the published tip has travelled, so the arm reads as
## stretching out rather than snapping to its target. Once extended the tip is
## the anchor exactly, which keeps the drawn arm attached to the rope.

enum State { IDLE, REACHING, HOLDING, RETRACTING }

var _config: OctopusConfig
var _state := State.IDLE
var _extension := 0.0
var _shoulder := Vector3.ZERO
var _anchor := Vector3.ZERO


func configure(config: OctopusConfig) -> void:
	_config = config


func reach(shoulder: Vector3, anchor: Vector3) -> void:
	_shoulder = shoulder
	_anchor = anchor
	_extension = 0.0
	_state = State.REACHING


## Keeps both ends current while the arm holds material.
func hold(shoulder: Vector3, anchor: Vector3) -> void:
	_shoulder = shoulder
	_anchor = anchor
	if _state == State.IDLE or _state == State.RETRACTING:
		_state = State.REACHING


func release(shoulder: Vector3) -> void:
	if _state == State.IDLE:
		return
	_shoulder = shoulder
	_state = State.RETRACTING


func step(delta: float) -> void:
	if _config == null or delta <= 0.0:
		return
	match _state:
		State.REACHING:
			_extension = minf(1.0, _extension + delta / maxf(_config.reach_time, 0.001))
			if _extension >= 1.0:
				_state = State.HOLDING
		State.RETRACTING:
			_extension = maxf(0.0, _extension - delta / maxf(_config.retract_time, 0.001))
			if _extension <= 0.0:
				_state = State.IDLE
		_:
			pass


func is_active() -> bool:
	return _state != State.IDLE


func is_extended() -> bool:
	return _state == State.HOLDING


func get_state() -> State:
	return _state


func get_extension() -> float:
	return _extension


## Smoothstep keeps the stretch soft at both ends instead of linear and rubbery.
func get_tip() -> Vector3:
	return _shoulder.lerp(_anchor, smoothstep(0.0, 1.0, _extension))


## Quadratic Bezier from shoulder to tip. The bow relaxes while the arm is
## stretching and tightens as it takes load, so a carried rope looks pulled.
func get_curve(up: Vector3, samples: int) -> PackedVector3Array:
	var count := maxi(2, samples)
	var tip := get_tip()
	var span := _shoulder.distance_to(tip)
	var bow := up * (span * _config.arm_bow * (1.0 - 0.6 * _extension)) if _config != null else Vector3.ZERO
	var control := (_shoulder + tip) * 0.5 + bow
	var points := PackedVector3Array()
	points.resize(count)
	for i in count:
		var t := float(i) / float(count - 1)
		var inverse := 1.0 - t
		points[i] = _shoulder * (inverse * inverse) + control * (2.0 * inverse * t) + tip * (t * t)
	return points
