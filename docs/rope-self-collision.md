# Rope self-contact

`RopeSelfCollision` is pure simulation code. It treats each centerline segment
as a capsule, excludes nearby material on the same tube, and applies unilateral
separation constraints to the four endpoints using inverse mass and interpolation
weights. Pins remain exact. Relative normal motion is removed on impact; bounded
tangential friction reduces sliding without damping free flight.

The approach follows [position-based contact constraints](https://matthias-research.github.io/pages/publications/posBasedDyn.pdf).
Closest segment points use [Godot Geometry3D](https://docs.godotengine.org/en/4.4/classes/class_geometry3d.html).

Swept AABBs and an X-axis sweep-and-prune pass reject separated pairs. For motion
larger than a quarter diameter, up to 16 conservative-advancement steps search
for an earlier contact, retaining its incident normal when resolving the final
positions. Bounds rebuild every constraint iteration. Distance constraints run
before self-contact, then mannequin/floor contacts run afterward.

Configuration: `self_collision_enabled` (default true), `self_friction` (0–1,
default 0.18). Contact thickness uses the existing rope radius. Neighbor exclusion
scales with radius/rest length to avoid local straight-tube self-repulsion.

Simulation snapshots are version 2. Version 1 remains readable and preserves
the old behavior with self-contact off; Reset uses the current preset. No hidden
contact history is required for deterministic continuation. Scene files keep
their existing outer schema.

## Validation

- 78 tests pass, including segment-interior crossings, exact pins, equal-mass
  response, fast crossings with separated final states, degenerate contacts,
  neighbor exclusion, friction, JSON continuation with active contact, and
  legacy full-scene load/Reset.
- `tools/verify_self_collision.gd` simulates a 48-segment open figure-eight,
  drags and releases it, checks clearance/length and writes rendered screenshots.
  Over 360 steps: minimum separation after settling **0.040020 m** for a **0.04 m**
  diameter; maximum segment stretch **0.58%**.
- Same-process default mannequin benchmark, 60 warmup and 240 measured steps:
  self-contact off median **3.444 ms**, on median **5.062 ms** per 120 Hz step.
  On p95 **5.490 ms**. Windows/Godot 4.7.2; desktop results, not mobile acceptance.
- Rendered normal-scene input checks cover drag, endpoint/depth controls,
  cancellation, Reset, Save/Open and performance export.

## Limits

This is a bounded prototype contact solver, not a proof of topology preservation.
Dense contacts, impossible fixed attachments, initial overlaps and sufficiently
large deformations can leave penetration. Newly created contact pairs outside
cached bounds are handled on the next iteration; obstacle and self-contact
constraints can compete. Broad-phase worst case remains quadratic for dense coils.
The rendered Catmull-Rom tube can deviate slightly from the piecewise-linear
collision centerline. No knot recognition, twisting model or calibrated static
knot friction is included. Mobile performance remains unverified.
