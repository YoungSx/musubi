# Windows creation prototype

## Controls

- Rope menu: New 1.4 m / 2.2 m / 3.0 m; Fix A/B here or Release A/B.
- Gold marker: actual grabbed rope point. Blue marker and tether: requested
  target, including behind an obstacle. A/B labels identify the endpoints.
- Drag visible rope to shape it; wheel moves the target nearer/farther.
  Release holds the entire shape. Continue/Hold or Space resumes/pauses physics.
- Other side or B turns the view around; F restores the default view.
- Ctrl+Z / Undo reverses one complete drag, endpoint action, new rope or Reset.
  Ctrl+Shift+Z or Ctrl+Y / Redo restores it. During a drag, Undo cancels the
  current gesture first. Esc also cancels it without adding history.
- Save/Open or Ctrl+S/Ctrl+O persists the creation, including rope configuration,
  endpoints, held state, velocities, mannequin transform and camera.

New rope replaces the current rope but is undoable. Reset keeps the selected
rope length and returns the original attachments/view. Undo restores rope state,
including whether physics was running and the matching mannequin pose; it does
not rewind the camera. Successful
Open establishes a fresh history boundary. Invalid files leave the scene and
history intact. History is limited to 32 edits and 4 MiB of encoded snapshots;
this bounds retained data, not an exact Godot heap allocation measurement.

## Configuration and performance

| Rope | Segments | Simulation Hz | Substeps | Iterations |
| --- | ---: | ---: | ---: | ---: |
| 1.4 m | 48 | 120 | 6 | 2 |
| 2.2 m | 72 | 60 | 10 | 2 |
| 3.0 m | 96 | 60 | 8 | 2 |

Local segment spacing stays around 3 cm. Scene import validates numeric ranges
and bounds the product of segments, substeps, solver and obstacle iterations to
8,192 before replacing the live simulation. The snapshot supplies the scheduler
and renderer configuration; it no longer needs to match the currently open rope.

Self-contact broad phase reuses the previous ordering but sorts with a stable
segment-index tie break. Cached order therefore improves cost without introducing
hidden simulation state that changes snapshot continuation.

Same-host CPU simulation plus mesh-submission benchmark (360 frames per length,
after 120 warmup frames; includes drag/release):

| Rope | Before median ms | After median ms | After p95 ms | Maximum segment stretch |
| --- | ---: | ---: | ---: | ---: |
| 1.4 m | 11.67 | 8.90 | 10.73 | 6.18% |
| 2.2 m | 18.15 | 11.64 | 16.40 | 3.46% |
| 3.0 m | 26.37 | 13.03 | 17.39 | 7.10% |

These are Godot 4.7.2 Windows development measurements, not GPU completion time
or a guarantee on other hardware. Frame reports now use monotonic wall-clock
differences between frames rather than the engine's supplied simulation delta.

## Acceptance evidence

- 90 unit/integration tests pass: configuration restoration, invalid-load
  rejection, legacy loading, edit boundaries, history trimming, undo/redo
  branches, attachment restoration and keyboard mapping, alongside physics tests.
- `verify_creation_workflow.gd` starts from the default scene, selects a long
  rope through the menu handler and moves its endpoint exclusively through
  dispatched mouse/wheel input. The rope passes behind and around the mannequin,
  releases into held mode, saves and restores exactly over a short rope. It then
  re-grabs the saved endpoint and moves it from in front to behind beside a leg.
  No prebuilt knot or direct particle-coordinate edits are used.
- This is synthetic input through Godot's real input dispatch, not a human
  usability study. The loose wrap slides toward the legs under gravity; the
  test does not establish arbitrary knot recognition or topological correctness.
- `verify_interaction.gd` checks menu/button opening, Continue, Other side,
  keyboard undo/redo and save/load dialogs. File/menu selections use their
  selection signals. `verify_tightening.gd` separately covers a tight knot fixture.
- `benchmark_creation.gd` also runs 50 new/reset/undo/redo cycles after warming
  history. Observed live object growth: 0; static memory did not grow; history
  stayed at 32 entries and below the encoded-byte budget.
- `verify_desktop_stability.gd` renders 1,200 measured frames per length, with
  fullscreen toggles and 960×640 / 1280×800 resize transitions. Measured means:
  **59.55 / 59.42 / 59.51 FPS** for short/medium/long; wall-clock p95 frame intervals
  **18.15 / 18.79 / 18.25 ms**.
  Across this one-minute run: live object growth **2**, static memory growth
  **279,652 bytes** (includes the longer rope meshes and additional history).
- Default and 960×640 layouts were rendered and inspected. On short desktop
  canvases the vertical field of view widens to keep the mannequin clear of UI.

## Remaining limits

Synthetic paths cannot establish that a first-time user finds depth controls easy.
Dense knots and arbitrary-speed movement still have the bounded solver limitations
described in `rope-self-collision.md`. Strong input targets can lag behind the
blue marker under gravity/tension. Long-rope p95 CPU time can exceed a 60 FPS
budget even though the measured authoring run averaged 60 FPS. Mobile deployment
and prolonged multi-hour leak/thermal testing are not part of this acceptance.
