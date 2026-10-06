# Complex-case acceptance (in progress)

The target is a continuous long-rope lattice on the complete mannequin, created
through ordinary mouse input, with crossings and tension surviving release.
A prearranged lattice is a solver diagnostic, not evidence that the interaction
can tie the requested structure. No real-person restraint is tested.

## Long rope

The Advanced rope menu now includes 6 m / 192 segments. Excess shoulder-drape
length is laid on the ground instead of being spawned below the floor.
Snapshot/reset/renderer validation covers the longer preset.

`tools/probe_long_rope.gd -- <output-directory>` supplies a deliberately
prearranged counterwound lattice around the full torso and arms. Its measured
length is 7.774 m; this is a custom stress fixture, not the 6 m menu preset and
not a classified hexagonal knot. After five simulated seconds it slides down
to the feet. Therefore this fixture FAILS structure retention. It demonstrates
why visual arrangement alone is insufficient without stable interlocking.

Observed Windows / Godot 4.7.2 values: peak segment stretch 4.84%, final stretch
0.18%, minimum sampled mannequin/floor clearance 0.012029 m for radius 0.012 m.
Simulation cost was approximately 40 ms per 60 Hz step in this diagnostic.
The dense long-rope case is not accepted for 60 FPS or for user-constructed
torso lacing. Screenshots and JSON are emitted to the requested output directory.

## Remaining acceptance gates

- Multiple possible passages: retain hypotheses, reject ties, converge with
  deliberate trajectory changes; test actual adjacent loops as well as scoring.
- Continuous unwind: remove a player-created tightened structure using mouse
  gestures. Reversing recorded screen coordinates currently buckles the tail and
  can recreate the same knot. An endpoint crossing counter alone is insufficient.
- Novice usability: test jitter, speed, pickup tolerance and clear in-world
  feedback, then observe real first-time players. Automated scripts cannot certify
  that an unfamiliar person understands the gesture.
- Full mannequin: mouse-only front-to-back wraps, local passes between rope and
  body, interlocking cells, pull/release retention, and measured frame budget.

Failure reports must remain visible until these gates actually pass. Do not
count restoring a prebuilt creation or freezing physics as completion.

## Historical 0.7 findings

- `GroundFaces` splits projected edges at crossings and walks bounded faces.
  Free-tail bridge edges are removed from face boundaries. `PassageChoice`
  maintains several hypotheses and merges physically identical entrances before
  applying the confidence margin; duplicate descriptions must not cause false
  ambiguity. Unit tests cover mixed-arc cells, ties, jitter and genuine exits.
- The two-pixel jitter replay initially failed the underpass and ended without
  the intended knot. Filtering velocity in elapsed time, including retreat
  detection, corrected this case: it retained `[-1,2,-3,1,-2,3]` after release.
  This is input robustness evidence, not a novice-user study.
- `SurfaceIntent` adds bounded surface targets using the same collider geometry
  as the solver. A 6 m rope's endpoint reached torso height through screen-space
  mouse input, without wheel/depth/camera controls. The attempt reached 6.74%
  peak segment stretch. It did not retain a torso lattice after release. A rear
  intent flag is not proof that a physical rear wrap completed.
- Tightened-knot unthreading still FAILS. Both reversing the old pointer path
  and directing the end through the visible region can buckle the tail and leave
  the same knot or extra crossings. A tested endpoint-feed experiment did not
  fix it and was removed from production code. Do not treat an individual
  crossing or a remembered entrance as evidence of complete untying.

The original negative acceptance was recorded with
`godot --path . -s res://tools/verify_mouse_ground.gd -- <output> 1 --unwind`.
Version 0.8 now passes this single-knot gate with material transport (see below).
It writes `mouse-knot.musubi`, so later work can use
`--resume=<path-to-mouse-knot.musubi>` to reproduce from a real mouse-created knot.
`tools/probe_long_mouse.gd -- <output>` separately records the long-rope mouse
attempt. Neither probe counts the geometric stress fixture as player success.

The next architectural work is a verified material-through-passage transport
constraint with current crossing adjacency, bidirectional progress and contact
order invariants; its acceptance must show complete unthreading without changing
rope length, disabling collisions or moving particles outside the solver.
For the torso target, continuous rear-surface routing and interlocking cell
retention must pass before attempting a full hexagonal pattern. The current
implementation does not establish that the requested complete pattern is playable.

## 0.8 update

[Material transport](rope-transport.md) now passes the full single ground-knot
sequence, including jitter and the previously failing retreat route from a saved
mouse-created knot. The implementation uses current geometry, not history undo.
Length and self/body contacts remain active. This closes that specific failure;
player-created compound knots, torso-lattice construction and novice observation
are still open. A separate controlled 6.216 m two-knot transport fixture now also
passes after adding collision-aware passive-end payout. The 0.7 observations
above are retained as the failure baseline.
