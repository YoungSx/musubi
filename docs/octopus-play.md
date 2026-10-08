# Octopus play (0.9.4)

`res://scenes/main/octopus_play.tscn` is the default scene. A third-person
octopus is driven by two virtual sticks: the left one walks it over the floor
and up the mannequin, the right one aims an elastic arm at the rope and grabs
on release. Carrying the rope is just walking while holding it.

This replaces direct rope touching as the play scheme. `play.tscn` and
`main.tscn` are untouched, so the touch-drag mode, its HUD and its tests still
run as before.

## Controls

| Input | Effect |
| --- | --- |
| Left stick | Walk. The stick is read in the view's frame on level ground and in the surface's fall line while climbing, so pushing up always means "away from the camera, up the wall". |
| Right stick, held | Aim. A ring marks the material a release would take; a dim ray alone means nothing is in reach that way. |
| Right stick, released off centre | Grab the marked material. |
| Right stick, released at centre | Let go. |
| Keyboard `WASD` | Same locomotion, for desktop checks. |

Both sticks are the engine's own `VirtualJoystick`, which presses input actions
with analog strength, so both are read with `Input.get_vector()` and the mode
keeps no touch bookkeeping. The sticks are `JOYSTICK_FIXED` about their own
centre.

The grab and the let-go are both driven by `released` alone, not by
`flicked`/`tapped`. Those two leave gestures unanswered: `VirtualJoystick`
flicks on *any* lift outside the deadzone, so speed is irrelevant and a
30-frame hold still flicks, while `tapped` fires only when the finger never
moved at all — a lift that drifted a few pixels inside the deadzone fires
neither. Both gestures ask one question, where the stick was when the finger
left, and answering it from the single release event leaves no lift unanswered.

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
- A grab picks the nearest draggable, visible rope point inside a 35° cone,
  measured on the view plane. A two-axis stick spans that plane and carries no
  depth, so the cone flattens both the aim and the candidate offset by the
  camera's view normal before comparing them; only the distance ranking stays in
  world space. Comparing a plane-bound aim against a full 3D offset instead caps
  the achievable cosine at the offset's planar fraction, which rejects material
  the aim points straight at — at any cone width. That was the shipped defect
  in `5108cbe`: from the figure the measured cosine was 0.619 against a 0.819
  threshold, and no material anywhere in view cleared it.
- A release at the centre takes the nearest visible point instead, the usual
  twin-stick fallback. Visibility uses the same `RopeVisibility` sampling the
  touch scheme uses.
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

## Aim feedback

The grab resolves on release, so without feedback during the gesture the player
aims blind and learns the result only once the gesture is spent. Two surfaces
answer that, both driven from the same place the grab is:

- While the stick is held, `AimIndicator` draws a ray from the body and a ring
  on the material a release would take. The preview calls `Octopus.aim_material`,
  which runs the same `pick` with the same cone and the same visibility test the
  grab runs, so the ring cannot promise material the grab would refuse. Nothing
  in reach draws the bearing alone, dimmed.
- A grab that found nothing says so in the hint line for 1.6 s. The cone and the
  line of sight both fail silently, and a silent failure is indistinguishable
  from a stick that does nothing — which is how the working-but-unread aim stick
  in `5108cbe` read as broken.

The ring is drawn on the canvas rather than placed in the world because the
aimed material is often behind the figure being climbed, and feedback the figure
can hide is feedback the player cannot rely on. A target off the edge of the
screen keeps its true position rather than being clamped onto it: clamping would
put the ring where the material is not, and `_draw` is not clipped to the
control's rect, so the ray's visible part still carries the bearing.

Two engine facts shape this. `Camera3D.unproject_position` does not report that
a point is behind the camera — it returns a plausible-looking position — so
`is_position_behind` is checked separately for both the eye and the target.
And the mode owns `_aim_locked` itself rather than reading the state back out of
the indicator, which presents that state and does not define it.

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

- `tests/run_tests.gd`: 210 tests pass. The 40 new ones cover floor and body
  adhesion, climbing a convex edge while holding clearance, falling and
  landing, ledge departure keeping momentum, the floor/limb crease being
  crossable, the control frame on level ground and on a climbed face, aim
  mapping through the camera frame including pitch, an aim reaching material
  above the body, cone accept/reject, the cone being measured on the view plane
  rather than against depth, material centred on screen being reachable by any
  aim, grip claim/release/re-take, grip-id independence from finger grips,
  rate-limited carry, unbounded reach, bow behaviour, camera framing, turn rate,
  the origin-clearance dolly and the deliberate absence of a line-of-sight
  dolly.
- The eight aim-feedback tests cover every lift being answered as a grab or a
  let-go including the drifted lift `flicked`/`tapped` miss; the held stick
  marking material, the ring landing on the rope as projected, and a release
  there taking the material that was marked; an aim at nothing showing its
  bearing and saying so; a missed grab reporting it and the notice outliving the
  next frame's steady hint; nothing being marked while already holding; the
  overlay passing touches through to the sticks; an off-screen target keeping
  its true position; and `get_material_position` sampling the same point a grip
  taken at that coordinate reports.
- `tools/verify_octopus.gd`: 390×844 portrait rendered replay, 0 failures in ten
  consecutive runs. Ten rather than one because the grab happens wherever the
  aim lands — material 0.48 m to 0.80 m out across those runs — and a single
  clean run cannot tell a sound bound from a lucky sample. Every
  movement, grab and release comes from synthetic touch events on the on-screen
  sticks through Godot's input dispatch, not from calling the octopus directly.
  It checks floor adhesion; an aim-stick release from the floor grabbing
  material overhead 0.80 m out, past twice its own mantle width, with the arm
  starting short of it and reaching full extension over later frames to draw the
  material inward; stick-driven walking; climbing until rope is in sight with a
  tilted frame and positive clearance; a grab from the figure claiming exactly
  one grip with the extended tip holding its material; carrying — the grip
  surviving, the reel still asking the material inward, the material riding at
  what it asks, ground gained on the body, and the rope not tearing; a centred
  release with the rope still simulating; and camera framing and clearance.
  Captures `octopus-start`, `octopus-reach`, `octopus-climb`, `octopus-grab`,
  `octopus-carry`, `octopus-release`.
- The figure stage holds the aim stick out and inspects it before the lift, which
  is the only window a preview can help in: the marker reads `LOCKED` while
  nothing is yet grabbed, the ring sits on the rope as projected, the lift then
  claims the material the ring was on, and the marker clears. The lift is checked
  in material coordinates, not world position — the rope keeps falling between
  the preview and the grab, so the material keeps its identity while its position
  does not. Within one segment, because the pick is per particle. This stage has
  three clean runs, not the ten behind the older claims above — enough to watch
  the ring gap and its bound move together (0.23 px against 0.40 px, 6.19 against
  7.36, 6.72 against 7.45) rather than to settle a bound.
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
  depends on what the rope drags over. The ring check is bounded the same way, by
  how far the marked material itself moves on screen in a frame: the mode draws
  the ring from its own `_process` while the rope keeps its fixed-step schedule,
  so the mark is a frame stale by construction and that motion is the floor on
  any pixel figure. It is measured at the marked material rather than over the
  whole rope, so a whipping free end cannot buy slack for a misplaced ring, and
  after the ring and material readings so all three stay in one frame. Four
  earlier attempts to bound these by a fitted figure — a fraction of the hold
  span, a flat 0.5 m, a reach clamp that `octopus_play.tscn` pins nothing to
  trigger, and a flat 1.0 px on the ring — each passed once and then failed,
  which is why the assertion messages print their own measurements. The ring
  bound is the clearest case: the gap read 1.13 px against the fitted 1.0 px,
  then 6.72 px on the next run while its self-measured bound moved with it to
  7.45 px. The figure was frame phase all along, which no constant can track.

No performance or physical-touch acceptance is inferred from the desktop
replay.

Replay command (create the output directory first):

```text
godot --path . -s res://tools/verify_octopus.gd -- <output-directory>
```
