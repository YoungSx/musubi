# Rope self-contact

`RopeSelfCollision` is pure simulation code. It treats each centerline segment
as a capsule, excludes nearby material on the same tube, and applies unilateral
separation constraints to the four endpoints using inverse mass and interpolation
weights. Pins remain exact. Relative normal motion is removed on impact; bounded
tangential friction reduces sliding without damping free flight.

The approach follows [position-based contact constraints](https://matthias-research.github.io/pages/publications/posBasedDyn.pdf).
Closest segment points use `RopeGeometry` with a relative determinant threshold.
[Godot 4.7.2's built-in implementation](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/math/geometry_3d.cpp)
uses an absolute determinant threshold, which misclassifies centimeter-scale
perpendicular segments as parallel. Analytical multi-scale regression tests
cover the replacement independently of the simulation's clearance checks.

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

- 82 tests pass, including segment-interior crossings, exact pins, equal-mass
  response, fast crossings with separated final states, degenerate contacts,
  neighbor exclusion, friction, JSON continuation with active contact, and
  legacy full-scene load/Reset.
- `tools/verify_self_collision.gd` simulates a 48-segment open figure-eight,
  drags and releases it, checks clearance/length and writes rendered screenshots.
  Over 360 steps: minimum separation after settling **0.040852 m** for a **0.04 m**
  diameter; maximum segment stretch **0.59%**.
- Same-process default mannequin benchmark, 60 warmup and 240 measured steps:
  self-contact off median **3.522 ms**, on median **5.457 ms** per 120 Hz step.
  On p95 **6.137 ms**. Windows/Godot 4.7.2; desktop results, not mobile acceptance.
- Rendered normal-scene input checks cover drag, endpoint/depth controls,
  cancellation, Reset, Save/Open and performance export.
- `tools/verify_tightening.gd`: 72-segment open trefoil, one fixed end and one
  dragged through a 2.6 m target displacement, then released; 600 steps.
  Minimum centerline separation **0.023530 m** for **0.024 m** diameter, maximum
  segment stretch **2.05%**. Rendered checkpoint separation exceeds **0.02405 m**.
- `tools/verify_wrap.gd`: 48-segment wrap around the actual mannequin, dragging
  and release under gravity for 600 steps. Minimum sampled obstacle clearance
  **0.012050 m** for **0.012 m** radius; self separation **0.024020 m**;
  maximum stretch **0.089%**. Obstacle clearance samples five points per segment,
  so this is a regression scenario rather than an exact continuous-space proof.

These measurements supersede the earlier builtin-Geometry3D clearance results.
Run either tool with an existing output directory after `--` to capture images.
The stress tools are development fixtures, not user-facing knot presets.

## Limits

This is a bounded prototype contact solver, not a proof of topology preservation.
Dense contacts, impossible fixed attachments, initial overlaps and sufficiently
large deformations can leave penetration. Newly created contact pairs outside
cached bounds are handled on the next iteration; obstacle and self-contact
constraints can compete. Broad-phase worst case remains quadratic for dense coils.
Rendered cubic smoothing is limited to 2.5% of rope radius from the piecewise-linear
collision centerline to prevent smoothing from cutting across a tight contact.
No knot recognition, twisting model or calibrated static
knot friction is included. Mobile performance remains unverified.
