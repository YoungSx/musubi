class_name CameraConfig
extends Resource
## Tunable parameters for CameraRig. Screen-space amounts are expressed per
## screen height so behaviour is independent of device resolution.

@export var focus: Vector3 = Vector3(0.0, 0.92, 0.0)
@export_range(0.1, 20.0, 0.01, "suffix:m") var distance: float = 3.6
@export_range(0.1, 20.0, 0.01, "suffix:m") var min_distance: float = 1.2
@export_range(0.1, 20.0, 0.01, "suffix:m") var max_distance: float = 6.0
@export_range(-180.0, 180.0, 0.1, "degrees") var yaw_degrees: float = -25.0
## Positive pitch places the camera above the focus, looking down.
@export_range(-89.0, 89.0, 0.1, "degrees") var pitch_degrees: float = 8.0
@export_range(-89.0, 89.0, 0.1, "degrees") var min_pitch_degrees: float = -30.0
@export_range(-89.0, 89.0, 0.1, "degrees") var max_pitch_degrees: float = 75.0
## Rotation applied for a drag spanning one full screen height.
@export var orbit_degrees_per_screen: float = 220.0
## Focus travel per screen height, multiplied by the current distance.
## ~0.73 keeps content under the finger at a 40 degree vertical FOV.
@export var pan_per_screen: float = 0.73
## Maximum distance the focus may drift from its default position.
@export_range(0.0, 10.0, 0.01, "suffix:m") var max_focus_offset: float = 1.2
## Exponential easing rate toward the requested view. Higher is snappier.
@export_range(1.0, 60.0, 0.1) var smoothing: float = 14.0
@export_range(10.0, 120.0, 0.1, "degrees") var fov: float = 40.0
