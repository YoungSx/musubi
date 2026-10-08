class_name AimIndicator
extends Control
## Screen-space aim feedback for the grab stick: a ray from the body and a ring
## on the material a grab would take.
##
## It is told where to draw, in canvas coordinates, and knows nothing about the
## camera, the octopus or the rope. Drawing on the canvas rather than placing a
## marker in the world is deliberate: the material being aimed at is often behind
## the figure being climbed, and feedback the figure can hide is feedback the
## player cannot rely on.

enum State {
	## Nothing drawn: the stick is centred, or an aim preview would mislead.
	IDLE,
	## The stick is pushed but no material qualifies, so only the bearing is drawn.
	SEARCHING,
	## Material is in reach; the ring marks exactly what a release would take.
	LOCKED,
}

## Warm off-white, matching the theme's label colour.
@export var locked_color: Color = Color(0.95, 0.93, 0.89, 0.9)
@export var searching_color: Color = Color(0.92, 0.9, 0.86, 0.3)
@export_range(1.0, 8.0, 0.5) var line_width: float = 2.0
@export_range(4.0, 40.0, 1.0) var ring_radius: float = 11.0
## Length of the bearing ray drawn when nothing is in reach.
@export_range(20.0, 200.0, 1.0) var search_length: float = 64.0

var _state := State.IDLE
var _origin := Vector2.ZERO
var _toward := Vector2.ZERO


func _ready() -> void:
	# An indicator that swallowed touches would block the sticks underneath it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Draws the ray and the ring on the material a release would take.
func show_target(origin: Vector2, target: Vector2) -> void:
	_set_state(State.LOCKED, origin, target)


## Draws the bearing alone: the stick is pushed, nothing qualifies along it.
func show_search(origin: Vector2, direction: Vector2) -> void:
	if direction.is_zero_approx():
		clear()
		return
	_set_state(State.SEARCHING, origin, origin + direction.normalized() * search_length)


func clear() -> void:
	_set_state(State.IDLE, Vector2.ZERO, Vector2.ZERO)


func get_state() -> State:
	return _state


## End of what is drawn: the ring's centre when locked, the bearing's tip when
## searching. Zero while idle.
func get_endpoint() -> Vector2:
	return _toward if _state != State.IDLE else Vector2.ZERO


func _set_state(state: State, origin: Vector2, toward: Vector2) -> void:
	if state == _state and origin.is_equal_approx(_origin) and toward.is_equal_approx(_toward):
		return
	_state = state
	_origin = origin
	_toward = toward
	queue_redraw()


func _draw() -> void:
	if _state == State.IDLE:
		return
	var color := locked_color if _state == State.LOCKED else searching_color
	var span := _toward - _origin
	if _state == State.LOCKED:
		# Stop the ray at the ring rather than through it, so the ring reads as the
		# thing being pointed at instead of a bead on a line.
		var gap := minf(ring_radius, span.length())
		draw_line(_origin, _toward - span.normalized() * gap, color, line_width, true)
		draw_arc(_toward, ring_radius, 0.0, TAU, 32, color, line_width, true)
	else:
		draw_line(_origin, _toward, color, line_width, true)
