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
