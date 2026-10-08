# Octopus play (0.9.4)

`res://scenes/main/octopus_play.tscn` is the default scene. A third-person
octopus is driven by two virtual sticks: the left one walks it over the floor
and up the mannequin, the right one flicks an elastic arm out to grab the rope
and taps to let go. Carrying the rope is just walking while holding it.

This replaces direct rope touching as the play scheme. `play.tscn` and
`main.tscn` are untouched, so the touch-drag mode, its HUD and its tests still
run as before.

## Controls

| Input | Effect |
| --- | --- |
| Left stick | Walk. The stick is read in the view's frame on level ground and in the surface's fall line while climbing, so pushing up always means "away from the camera, up the wall". |
| Right stick flick | Reach for rope along the flicked direction. |
| Right stick tap | Let go. |
| Keyboard `WASD` | Same locomotion, for desktop checks. |

Both sticks are the engine's own `VirtualJoystick`, which presses input actions
with analog strength. Locomotion is therefore read with `Input.get_vector()`
and the mode keeps no touch bookkeeping. The sticks are `JOYSTICK_FIXED` about
their own centre, and `flicked`/`tapped` are what separate a grab from a
release: a lift with a non-zero vector flicks, a lift at rest taps.

## Behavior

- The body clings to whatever it touches. Position plus the surface normal as
  local up, movement projected onto the tangent plane, re-snapped to the
  surface every stride, so convex edges are crawled around instead of launched
  off. This is the Mario-Galaxy surface-walker shape, not a physics character.
- Adhesion is evaluated against the rope's own signed-distance geometry, so the
  walkable surface is the drawn figure by construction and cannot drift from
  it. There is no `CharacterBody3D`, no physics server use and no second copy
  of the collision shapes.
- Across the crease where a limb meets the floor, the surface normal is blended
  over a band one body width wide. Picking either the floor or the limb makes
  the two corrections fight in the wedge and the body stops dead.
- Walking off a ledge keeps the forward speed, falls under gravity and re-clings
  on landing.
- The aim is mapped through the camera's own frame: screen right is the camera's
  right, screen up its up. It deliberately ignores the climbing surface, which
  may be any wall, but it keeps the camera's pitch — rope hangs above a body on
  the floor, and a horizon-locked aim can never reach it.
- A flick picks the nearest draggable, visible rope point inside a 35° cone. An
  aimless tap takes the nearest visible point instead, the usual twin-stick
  fallback. Visibility uses the same `RopeVisibility` sampling the touch scheme
  uses.
- The arm has no length limit. Extension is an animation parameter only: the
  published tip travels from shoulder to anchor over `reach_time`, so the arm
  reads as stretching rather than snapping, and once extended the tip is the
  anchor exactly so the drawn arm stays attached.
- The grip goes through the same `begin_grip` / `update_drag_target` /
  `end_drag` seam a finger uses, at a grip id outside the touch-index range.
  The solver applies the identical soft constraint, length limits and contacts;
  carrying reels the material toward the body at a bounded rate rather than
  teleporting it.
- The camera follows without any gesture. It frames the body along its current
  surface normal, eases its yaw behind sustained movement under a rate limit
  with a dead zone, and dollies in when its own origin would sit inside
  geometry.
- All eight arms are one `MultiMesh` bead chain: a single draw call, and no
  second tube-mesh builder beside the rope's.

## Boundaries

`SurfaceWalker` is pure geometry over an SDF: no nodes, no input, no rope.
`OctopusArm` is pure geometry too. `OctopusGrab` owns exactly one rope grip and
never reaches into the simulation. `Octopus` composes those three and owns no
input and no camera. `OctopusSkin` is presentation only. `OctopusCamera` writes
only through `CameraRig.apply_assisted_view()`, following
`FollowCameraController`'s precedent, so the rig keeps its pose limits and
smoothing. `OctopusControls` emits intents and touches nothing else.
`OctopusMode` is the only place that wires them together and the only place the
frame order lives: read input, advance the octopus, then move the camera. The
rope keeps its own fixed-step schedule.

Every tunable is on `OctopusConfig`, so a variant is a new resource rather than
new code.

`octopus_play.tscn` has no `InteractionManager` and no `Hud`: the touch-drag
scheme and the gesture camera are absent rather than suppressed.

Industry-practice claims above (Mario-Galaxy surface walking, twin-stick aim
fallbacks) are stated from model knowledge; web search was unavailable in this
environment. The engine facts — `VirtualJoystick`'s signal semantics, its fixed
centre, and analog action strength — were established by headless probe against
this exact build, 4.7.2-stable `ed1daf0bf`.

## Verification

- `tests/run_tests.gd`: 199 tests pass. The 29 new ones cover floor and body
  adhesion, climbing a convex edge while holding clearance, falling and
  landing, ledge departure keeping momentum, the floor/limb crease being
  crossable, the control frame on level ground and on a climbed face, aim
  mapping through the camera frame including pitch, a flick reaching material
  above the body, cone accept/reject, grip claim/release/re-take, grip-id
  independence from finger grips, rate-limited carry, unbounded reach, bow
  behaviour, and camera framing/turn-rate/occlusion.
- `tools/verify_octopus.gd`: 390×844 portrait rendered replay. Every movement,
  grab and release comes from synthetic touch events on the on-screen sticks
  through Godot's input dispatch, not from calling the octopus directly. It
  checks floor adhesion, stick-driven walking, climbing until rope is in sight
  with a tilted frame and positive clearance, a flick grab claiming exactly one
  grip, the arm stretching and then holding the material past its own body
  width, carrying without tearing, tap release with the rope still simulating,
  and camera framing and clearance. Captures `octopus-start`, `octopus-climb`,
  `octopus-grab`, `octopus-carry`, `octopus-release`.

No performance or physical-touch acceptance is inferred from the desktop
replay.

Replay command (create the output directory first):

```text
godot --path . -s res://tools/verify_octopus.gd -- <output-directory>
```
