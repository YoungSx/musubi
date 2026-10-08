class_name OctopusControls
extends CanvasLayer
## Twin-stick touch layer. Emits intents only; it never touches the octopus,
## the camera or the rope.
##
## Both sticks are the engine's own VirtualJoystick, which presses the input
## actions with an analog strength. Both are therefore read with
## Input.get_vector() and need no touch bookkeeping here; the aim stick's
## release carries the grab and let-go intents.

signal grab_requested(aim: Vector2)
signal release_requested

## Seconds a notice holds the hint line before the steady text returns. Long
## enough to read a few words after a gesture, short enough that it never
## becomes the thing the player is reading while aiming.
const NOTICE_SECONDS := 1.6

@onready var _safe_area: MarginContainer = %SafeArea
@onready var _hint: Label = %Hint
@onready var _aim_indicator: AimIndicator = %AimIndicator

var _base_margins: Dictionary[StringName, int] = {}
var _hint_text := ""
var _notice_remaining := 0.0


func _ready() -> void:
	# Released rather than flicked/tapped: VirtualJoystick reports a flick on any
	# lift outside the deadzone and a tap only when the finger never moved at all,
	# so a lift that drifted a few pixels inside the deadzone fires neither. Both
	# gestures are one question -- where was the stick when the finger left -- and
	# answering it from the single release event leaves no gesture unanswered.
	%AimStick.released.connect(_aim_released)
	_base_margins = MusubiSafeArea.capture(_safe_area)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func _process(delta: float) -> void:
	if _notice_remaining <= 0.0:
		return
	_notice_remaining -= delta
	if _notice_remaining <= 0.0:
		_hint.text = _hint_text


## Stick vector of the move joystick, in screen axes (y grows downward).
static func read_move() -> Vector2:
	return Input.get_vector(&"octopus_left", &"octopus_right", &"octopus_forward", &"octopus_back")


## Stick vector of the aim joystick, in the same screen axes. Zero while the
## stick is centred, which is every frame the player is not aiming.
static func read_aim() -> Vector2:
	return Input.get_vector(&"octopus_aim_left", &"octopus_aim_right", &"octopus_aim_forward", &"octopus_aim_back")


## Screen origin of a stick, which is its centre: both are JOYSTICK_FIXED with a
## centred initial offset. Replays touch the sticks here so the vector they
## report is the offset dragged from this point, and a tap lifts at zero.
func get_stick_origin(side: StringName) -> Vector2:
	var stick: Control = %MoveStick if side == &"move" else %AimStick
	return stick.get_global_rect().get_center()


## Steady hint for the current state. A notice in flight keeps the line until it
## expires, so a gesture's answer is not overwritten by the next frame's state.
func set_hint(text: String) -> void:
	_hint_text = text
	if _notice_remaining <= 0.0:
		_hint.text = text


## Answer to a gesture, held for NOTICE_SECONDS. This is how a grab that found
## nothing becomes visible: without it a miss and an ignored stick read the same.
func notify(text: String) -> void:
	_hint.text = text
	_notice_remaining = NOTICE_SECONDS


## Marks the material a release would take, at a canvas position.
func show_aim_target(origin: Vector2, target: Vector2) -> void:
	_aim_indicator.show_target(origin, target)


## Marks the bearing alone, for an aim with nothing in reach.
func show_aim_search(origin: Vector2, direction: Vector2) -> void:
	_aim_indicator.show_search(origin, direction)


func clear_aim() -> void:
	_aim_indicator.clear()


func get_aim_indicator() -> AimIndicator:
	return _aim_indicator


## One release answers both gestures: outside the deadzone the stick was pointed
## somewhere, which is a grab; at the centre it was not, which is a let-go.
func _aim_released(stick: Vector2) -> void:
	if stick.is_zero_approx():
		release_requested.emit()
	else:
		grab_requested.emit(stick)


func _apply_safe_area() -> void:
	MusubiSafeArea.apply(_safe_area, _base_margins)
