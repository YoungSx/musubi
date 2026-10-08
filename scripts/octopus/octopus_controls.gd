class_name OctopusControls
extends CanvasLayer
## Twin-stick touch layer. Emits intents only; it never touches the octopus,
## the camera or the rope.
##
## Both sticks are the engine's own VirtualJoystick, which presses the input
## actions with an analog strength. Movement is therefore read with
## Input.get_vector() and needs no touch bookkeeping here; the aim stick's
## flicked/tapped signals carry the grab and release intents.

signal grab_requested(aim: Vector2)
signal release_requested

@onready var _safe_area: MarginContainer = %SafeArea
@onready var _hint: Label = %Hint

var _base_margins: Dictionary[StringName, int] = {}


func _ready() -> void:
	%AimStick.flicked.connect(func(aim: Vector2): grab_requested.emit(aim))
	%AimStick.tapped.connect(func(): release_requested.emit())
	_base_margins = MusubiSafeArea.capture(_safe_area)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


## Stick vector of the move joystick, in screen axes (y grows downward).
static func read_move() -> Vector2:
	return Input.get_vector(&"octopus_left", &"octopus_right", &"octopus_forward", &"octopus_back")


## Screen origin of a stick, which is its centre: both are JOYSTICK_FIXED with a
## centred initial offset. Replays touch the sticks here so the vector they
## report is the offset dragged from this point, and a tap lifts at zero.
func get_stick_origin(side: StringName) -> Vector2:
	var stick: Control = %MoveStick if side == &"move" else %AimStick
	return stick.get_global_rect().get_center()


func set_hint(text: String) -> void:
	_hint.text = text


func _apply_safe_area() -> void:
	MusubiSafeArea.apply(_safe_area, _base_margins)
