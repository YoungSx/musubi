# Mannequin play — first interaction correction

The default remains the complete abstract mannequin. Complex limb, torso and
neck contacts are retained; a simple column or tabletop does not substitute for
the main interaction environment. The rope starts draped over the shoulders with
both ends free, supported by actual contacts rather than invisible attachments.

## Changes

- A grip uses a normalized material coordinate along the rope. The solver
  constrains the interpolated contact point and distributes correction to both
  neighboring particles by interpolation weights and inverse mass. Pins remain
  immovable. Input sets constraint intent, not particle positions.
- In play mode, release removes the grip and leaves simulation running. The
  local neighborhood receives a 120 ms fading damping pulse; its release speed
  is capped at 0.8 m/s. Distant particles retain motion. These are prototype
  feel parameters, not calibrated material properties.
- The default UI has one secondary Menu. Advanced exposes the workbench tools.
  Blue targets, tethers and A/B labels appear only in developer diagnostics;
  normal play uses the actual gripped location for the local highlight.
  If that location is occluded by the mannequin, only its small, faded highlight
  remains visible through the body until the view clears or the grip releases.
- A second touch or right mouse drag can inspect while maintaining the grip.
  Camera changes rebuild the pointer reference around the existing world target,
  preventing camera easing from being interpreted as hand movement.
- Snapshot version 3 saves fractional grips and the local release pulse. Versions
  1/2 remain readable. Scene snapshots preserve release behavior and initial
  layout. Old workbench creations reopen with their original held-release policy.

## Verification

95 tests cover the previous physics/creation behavior plus fractional grabs,
natural release and deterministic continuation, legacy migration, complete
mannequin presence, minimal default UI and retained grips during inspection.

`tools/verify_play_mannequin.gd` uses fixed screen-space pointer trajectories
calibrated from the visible scene. It does not read world positions to steer,
use a depth wheel, pause the world or edit particles. It drags a visible end
out past the arm and toward the torso, releases and saves/restores the result.
Observed particle clearance: 0.01205 m for a 0.012 m radius; final segment stretch
about 1.5%. These values describe this fixture, not all possible interactions.

Run with a graphics driver:

```text
godot --path . -s res://tools/verify_play_mannequin.gd -- <existing-output-directory>
```

## Not yet demonstrated

This verifies the direct-grip/release foundation on complex geometry. It does
not establish that a player can form Loop, Overhand or Half Hitch naturally.
The depth plane and optional desktop wheel remain a fallback. Local pass-corridor
candidates and intent scoring were added in 0.5.0; see `pass-assistance.md` for
their deliberately limited acceptance. Surface-following assistance and automatic
camera attention still require implementation and gameplay acceptance.
Synthetic replay is not a first-time-player usability study.
