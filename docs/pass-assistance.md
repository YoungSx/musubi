# Local pass assistance (0.5.0)

The full mannequin remains the default scene. Play mode can now stabilize a
clear local passage when the player grabs a rope end and moves consistently
toward it. No candidate names, path list or extra tool is shown to the player.

## Contract

- A near-contact closure must bound a sufficiently large, simple, nearly planar
  polygon in 3D. Screen overlap alone is not evidence of an opening.
- Candidate centerlines must clear the actual mannequin/floor and other rope
  segments. If the center is blocked, eight bounded side samples search for
  alternatives such as space beside the torso. The moving tip alone is excluded
  from rope blocking checks; ordinary collision remains enabled in the solver.
- More than four distinct candidates causes assistance to decline, rather than
  silently favoring the first segments encountered. Equal scores likewise do
  not select a path. Direction, approach trajectory, proximity and recent motion
  determine the score, followed by a 100 ms confidence dwell.
- Guidance only updates a soft grip target. Input controls longitudinal motion;
  bounded lateral correction reduces alignment error. No input means no target
  advance. Reverse input backs out, sideways intent exits and excessive physical
  lag blocks further forward assistance.
- Boundary/obstacle validity is refreshed during movement and polled at 20 Hz
  while holding still. Invalid geometry drops guidance and rebases the pointer
  without jumping the world target. Camera inspection, explicit depth-wheel use,
  cancellation and release also clear or override guidance.
- A path nearly aligned with the viewing ray is declined, because screen motion
  cannot reliably express its direction. Automatic camera attention is not yet
  implemented; manual inspection remains available without releasing the grip.

`PassAssistConfig` owns tuning parameters. `RopePassCandidates` provides geometry
and clearance; `RopePassAssist` ranks candidates and maintains transient guidance;
`RopeInteraction` submits only the resulting target to the existing simulation.
Active guidance is not saved as player intent. Completed scene geometry and the
normal simulation snapshot continue to use the existing format.

## Verification scope

103 tests cover the existing project and aperture validity, torso occlusion,
clear side portals, minimum opening size, nonplanarity, sampling duplicates,
ambiguity, stationary input, reversal, invalidation and crossing evidence.

`tools/verify_pass_assist.gd` places a **controlled, fixed aperture beside the
full mannequin**, with a free incoming strand. The fixture is relaxed before
fixing it so sampled corners do not impose incompatible segment lengths. Mouse
events travel through the application input layer; the physical solver moves
the endpoint. Assertions require an actual crossing inside the aperture with
rope-radius clearance and arrival beyond its plane, not just a changed Z value.
This proves the assistance/solver integration. It does **not** prove that an
untrained player can create an Overhand or Half Hitch from the default rope.

`verify_play_mannequin.gd` retains the ordinary mannequin drag/release/inspection
regression. Replay windows isolate synthetic events from native mouse movement
and avoid taking focus; they are functional tests, not foreground FPS acceptance.
The test-only unfocusable window uses the standard
[Godot Window property](https://docs.godotengine.org/en/4.5/classes/class_window.html).

In a same-host headless query probe, medians were 0.18 ms for the initial
73-point drape, 1.46 ms for a 97-point clear aperture, and 3.32 ms for a small
torso-occluded aperture. These are bounded local-query examples, not worst-case
mobile or dense-knot performance guarantees.

## Remaining limits

The detector approximates local openings and samples only a small number of side
portals. It can miss concave, highly twisted, fast-changing or densely nested
passages. Conservative rejection is preferable to moving the hand through a
wrong path. Global topology recognition, automatic camera assistance and
first-time-player Loop/Overhand/Half Hitch acceptance remain separate work.
