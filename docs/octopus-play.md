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
- A flick picks the nearest draggable, visible rope point inside a 35° cone,
  measured on the view plane. A two-axis stick spans that plane and carries no
  depth, so the cone flattens both the aim and the candidate offset by the
  camera's view normal before comparing them; only the distance ranking stays in
  world space. Comparing a plane-bound aim against a full 3D offset instead caps
  the achievable cosine at the offset's planar fraction, which rejects material
  the flick points straight at — at any cone width. That was the shipped defect
  in `5108cbe`: from the figure the measured cosine was 0.619 against a 0.819
  threshold, and no material anywhere in view cleared it.
- An aimless tap takes the nearest visible point instead, the usual twin-stick
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
- The camera does **not** react to a blocked line of sight, so a body clinging
  to the far side of a limb can be partly hidden. This is deliberate. A clinging
  body is always within its own radius of the thing occluding it, so no distance
  along the same view ray is clear: dollying in runs to the rig's minimum and
  crops the figure and rope out of frame, which costs the player more than the
  partial occlusion. Swinging the yaw instead, as the rope's
  `FollowCameraController` does for grips in open space, would spin the view
  while climbing between limbs. Resolving this properly needs a camera that
  offsets laterally off the ray, which is not implemented.
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

- `tests/run_tests.gd`: 202 tests pass. The 32 new ones cover floor and body
  adhesion, climbing a convex edge while holding clearance, falling and
  landing, ledge departure keeping momentum, the floor/limb crease being
  crossable, the control frame on level ground and on a climbed face, aim
  mapping through the camera frame including pitch, a flick reaching material
  above the body, cone accept/reject, the cone being measured on the view plane
  rather than against depth, material centred on screen being reachable by any
  flick, grip claim/release/re-take, grip-id independence from finger grips,
  rate-limited carry, unbounded reach, bow behaviour, camera framing, turn rate,
  the origin-clearance dolly and the deliberate absence of a line-of-sight
  dolly.
- `tools/verify_octopus.gd`: 390×844 portrait rendered replay, 0 failures in ten
  consecutive runs. Ten rather than one because the grab happens wherever the
  flick lands — material 0.48 m to 0.80 m out across those runs — and a single
  clean run cannot tell a sound bound from a lucky sample. Every
  movement, grab and release comes from synthetic touch events on the on-screen
  sticks through Godot's input dispatch, not from calling the octopus directly.
  It checks floor adhesion; a flick from the floor grabbing material overhead
  0.80 m out, past twice its own mantle width, with the arm starting short of it
  and reaching full extension over later frames to draw the material inward;
  stick-driven walking; climbing until rope is in sight with a tilted frame and
  positive clearance; a flick grab from the figure claiming exactly one grip
  with the extended tip holding its material; carrying — the grip surviving, the
  reel still asking the material inward, the material riding at what it asks,
  ground gained on the body, and the rope not tearing; tap
  release with the rope still simulating; and camera framing and clearance.
  Captures `octopus-start`, `octopus-reach`, `octopus-climb`, `octopus-grab`,
  `octopus-carry`, `octopus-release`.
- The replay asserts the order of the stretch, not mid-stretch magnitudes: a
  step advances extension by `delta / reach_time`, so at the replay's frame rate
  the arm saturates within a few frames and any specific partial value is the
  host's business. It likewise checks the tip holding its material only on the
  figure. From the floor the grip is still reeling in at `reel_speed` under the
  solver's soft constraint, so the tip legitimately lags its target there; what
  is true at that range is that the extended arm has drawn the material inward.
- Every replay bound is measured against something the same frame window also
  measures, never against a fitted constant. The tip-holding check bounds the
  gap by how far the grip itself travelled that frame, because `Octopus.advance`
  anchors the arm on the grip as it was before the solver ran and the solver
  then reels that grip onward — the residual is one frame of grip motion, so a
  fixed length would be a coincidence. Carrying is asserted by sign only: the
  reel pulls at `reel_speed` 0.7 m/s while the carry point retreats at no more
  than `move_speed` 0.55 m/s, so the gap can only shrink, but how far it shrinks
  depends on what the rope drags over. Three earlier attempts to bound these by
  a fitted figure — a fraction of the hold span, a flat 0.5 m, and a reach
  clamp that `octopus_play.tscn` pins nothing to trigger — each passed once and
  then failed, which is why the assertion messages print their own measurements.

No performance or physical-touch acceptance is inferred from the desktop
replay.

Replay command (create the output directory first):

```text
godot --path . -s res://tools/verify_octopus.gd -- <output-directory>
```
