# Input-driven material transport (0.8)

The ground replay can now make a knot, tighten it, release it, grab its end and
unthread it with one continuous mouse gesture. No Reset, Undo, camera movement,
depth wheel, restored geometry or disabled collision is used during the sequence.

## Interaction and boundaries

An endpoint on a free, ground-level rope becomes eligible only when its current
projection has a nontrivial crossing sequence. Obvious adjacent crossing pairs
are reduced; this is an eligibility heuristic, not a general knot classifier.
Moving inward along the tail for 120 ms expresses retraction. Interior grabs,
ordinary open ropes and attached endpoints keep their normal behavior.

`RopeTransport` samples the **current** centerline by arc length. Mouse movement
along the established screen direction advances material distance; opposite input
reduces it. The screen direction stays stable while the system handles the bends
inside the knot. Sideways input exits the assistance; releasing or cancelling the
grab removes it. Holding the pointer still does not advance material distance.

The interaction proposes distributed soft position constraints at `p(s_i + shift)`.
The opposite end supplies material along an incrementally planned floor path;
it can turn away from existing strands and the mannequin, so no material is
deleted or requested below the floor. `RopeSimulation` solves these targets before its regular length and
contact constraints. Particles remain movable; there are no new persistent pins.
Progress stops when the physical rope lags too far behind the proposed guide.
This is deliberate game assistance, not a claim of unassisted physical realism.

Snapshot format 5 preserves active solver targets and deterministic continuation.
Versions 1–4 still load. Completed creation files continue to reject active grabs.
Cancellation restores the pre-grab scene, including removal of transport targets.

## Evidence

- Full normal ground sequence: original three alternating crossings reduce to
  zero and remain absent after release. Peak segment length error about 0.64%,
  sampled nonlocal strand clearance about 0.02388 m (rope diameter 0.024 m).
- Full sequence at 0.85 duration with two-pixel jitter: zero final crossings,
  peak length error about 0.81%, sampled clearance about 0.02382 m.
- The previously failing 0.7 retreat route, starting from its saved mouse-created
  knot: zero final crossings, peak length error about 2.07%, sampled clearance
  about 0.02387 m. This does not require a recorded creation history.
- The opposite endpoint also unthreads the saved knot: zero final crossings,
  about 0.92% peak length error and 0.02393 m sampled clearance.
- 132 unit tests pass. Coverage includes delayed activation, stationary input, reverse progress,
  lateral exit, snapshot continuation, malformed data, cancellation and real
  focus-loss cleanup.
- A controlled 6.216 m, 192-segment two-knot fixture reduces six crossings to
  zero and stays clear after release: peak length error about 0.55%, sampled
  clearance about 0.02388 m. Straight passive-end extrusion initially stalled
  against the second knot; collision-aware payout corrected that failure.
  This fixture is prearranged and is NOT evidence that a player created two knots.

Replays use elapsed seconds for gestures, so monitor refresh rate no longer
silently changes their speed. Synthetic windows ignore unrelated host focus
changes; real application windows still cancel input on focus loss. The latter
is separately tested with the production policy enabled.

```text
godot --path . -s res://tools/verify_mouse_ground.gd -- <output> 1 --unwind
godot --path . -s res://tools/verify_mouse_ground.gd -- <output> 0.85 --jitter --unwind
godot --path . -s res://tools/verify_mouse_ground.gd -- <output> 1 --legacy-unwind --resume=<mouse-knot.musubi>
godot --path . -s res://tools/verify_transport_compound.gd -- <output>
```

Clearance is sampled; bounded sweep tests and this replay are not a proof against
every possible tunneling case. Player-created compound knots, model-wrapped ropes and first-time
player usability remain separate acceptance gates. The full torso lattice has
not been achieved by this ground-only feature.
