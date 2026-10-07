# Assisted follow camera (0.9.3)

New scenes default to **Assisted follow**. Menu → Camera selects Assisted follow
or Free camera without releasing grips or snapping the view. Existing creations
without a camera mode retain Free camera when loaded; new files store the mode.

## Behavior

- Fine manipulation inside the central 60% of the view does not reframe it.
- Explicit changes to grip targets activate tracking. Passive settling cannot
  start tracking. A short 0.45 s settling window permits the camera to finish
  its response after input stops, then its ordinary rig smoothing settles.
- Active grips and neighboring rope samples define the operation region. An
  oversized region causes bounded dolly-out, not a changing field of view.
- An edge excursion moves the focus at up to 0.9 m/s. Sustained horizontal
  intent can gently bias the view behind motion while the region is outside
  the safe area. Fine motions and opposing hand movements do not spin the view.
- Visibility is sampled at 10 Hz against the same mannequin/floor geometry used
  by the rope. Occlusion persisting for 0.25 s selects a nearby clearer yaw;
  rotation is capped at 35 degrees/s. Candidate camera positions inside
  collision geometry are rejected. If no candidate improves visibility, the
  camera holds instead of repeatedly switching sides.
- Manual orbit/pan/zoom takes priority. Automatic tracking waits for the manual
  gesture to finish, its 0.35 s cooldown, and fresh grip-target movement. Time
  alone never recenters the camera. Pointer membership changes also rebase intent.
- Free mode bypasses the policy completely. Releasing all hands clears tracking
  state; the view remains where it was rather than returning to the initial pose.

## Boundaries

`FollowCameraController` observes grip positions, requested targets, nearby
geometry and the requested camera pose; it never edits the rope or input.
`InteractionManager` supplies that context and manual-gesture ownership.
`CameraRig` owns the mode, pose limits, serialization and final smoothing.
`RopeInteraction.rebase()` keeps requested world targets stable as the camera
moves. Framing is evaluated against the requested camera pose so camera easing
does not repeatedly accumulate the same correction.

This is bounded assistance, not an unconditional chase camera. Existing camera
focus/distance limits still apply; the policy cannot guarantee visibility when
all candidate views are blocked or a grip is inside an obstacle. No performance
or physical-touch acceptance is inferred from the desktop replay.

## Verification

- `tests/run_tests.gd`: 170 tests pass, including safe-area stability, passive
  motion, edge follow, rate limits, manual override, multi-grip framing,
  occlusion delay/recovery, mode switching and JSON/legacy-file compatibility.
- `tools/verify_assisted_follow.gd`: 390×844 rendered replay with actual touch
  input dispatch; verifies extended edge drag, stationary-target stability,
  idle settling, mode changes retaining grips, menu display and saved modes.
- `tools/verify_multitouch.gd`: existing portrait multi-grip/camera replay passes
  with the new default mode enabled.

Replay command (create the output directory first):

```text
godot --path . -s res://tools/verify_assisted_follow.gd -- <output-directory>
```
