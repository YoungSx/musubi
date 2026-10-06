# Torso sequence acceptance — 2026-10-06

**Overall result: not accepted.** This checks the existing 0.9.1 implementation;
the researched body-gap preparation mechanism has not been implemented. No
application interaction or physics code was changed by this acceptance pass.

## Separate the two acceptance lanes

| Lane | Result | What it establishes |
| --- | --- | --- |
| Controlled open torso passage: forward and reverse | Pass | Actual endpoint crosses inside the opening in both directions |
| Controlled passage: release, regrab and reverse | Pass | One mouse can resume the existing route with fixed camera |
| Controlled passage: withdraw before crossing | Pass | Guidance was acquired, but reversal produced no crossing |
| Controlled passage: sideways bypass | Pass | No passage capture and no crossing |
| Original side-aperture replay | Pass | Existing passage behavior remains operational |
| Free 6 m rope: form and retain a torso loop | Fail | No near-closed torso loop observed at stroke boundaries or after release |
| Prepare a closed body-backed gap | Not implemented | Spatial assist has FREE/APPROACH/PASSING, but no opening-deformation plan |
| Free-rope pass, unwind and regrab sequence | Blocked by formation prerequisite | Controlled fixture results do not satisfy this gate |
| Complete torso lattice | Not accepted | No player-created interlocking net was demonstrated |

The fixed-aperture lane keeps a known ring supported to isolate interpretation
and passage execution. It cannot establish loop creation, release retention or
novice usability. Maximum segment error in the corrected torso fixture was 1.05%.
All segment/body checks passed with a 0.5 mm runtime numerical tolerance, as did
stationary-target, fixed-camera and release-cleanup checks.

## Fixture audit

The earlier circular torso fixture had fixed side segments intersecting the upper
arms. Replacing it with an ellipse then exposed incompatible pinned lengths at
the incoming/outgoing corners. The corrected fixture:

- fits between torso and arms;
- fixes ring-interior samples and the far end during setup, leaving the corners
  free to relax with mannequin collision enabled;
- verifies the entire relaxed rope against body geometry before interaction;
- checks body clearance during the replay, including pinned segments;
- uses actual pointer deltas and direction-aware crossing evidence;
- records `running` before setup, so a failed setup cannot leave an old passing
  JSON result looking current.

Previous controlled-circle results should not be used as whole-fixture collision
acceptance. They have been superseded by fixture revision 2. These changes repair
the test setup; they do not add a playable loop-making feature.

## Free-rope gate

`probe_torso_lattice.gd -- <output> 2 --single-loop` starts the normal 6 m
shoulder-draped rope on the complete mannequin. It uses only left-button screen
trajectories, with three seconds per stroke. It does not write particle positions,
load a ring or move the camera during the measurement. After eight wrap/closure
strokes, the pointer is released and the rope runs for three seconds.

`TorsoLoopEvidence` is a read-only observer for this default mannequin. It requires
a material arc at torso height, endpoint-segment proximity within 2.2 rope radii
and an XZ winding around the torso. Its tests reject open arcs, height-separated
projection overlap and a loop beside the body. This is geometric near-closure,
not knot recognition. Stroke-boundary sampling cannot rule out a fleeting loop
between samples; the post-release check directly establishes failure to retain it.

The gate returns exit code 2 when formation/retention fails. Later operations are
explicitly recorded as unevaluated. The nonzero exit is an intentional acceptance
failure, separate from the unit suite that verifies the observer and existing code.
Screenshots show strands slipping down rather than a retained torso ring. A single
recorded trajectory failing does not prove every possible trajectory must fail.

## Reproduce

Create an output directory first, then use the Godot console executable:

```text
godot --path . -s res://tools/verify_pass_assist.gd -- <output> --torso --reverse
godot --path . -s res://tools/verify_pass_assist.gd -- <output> --torso --regrab
godot --path . -s res://tools/verify_pass_assist.gd -- <output> --torso --withdraw
godot --path . -s res://tools/verify_pass_assist.gd -- <output> --torso --bypass
godot --path . -s res://tools/verify_pass_assist.gd -- <output>
godot --path . -s res://tools/probe_torso_lattice.gd -- <output> 2 --single-loop
```

Controlled cases write `pass-<fixture>-<scenario>.json` and screenshots. The free
case writes `lattice-input-report.json`, input/state CSV, screenshots and a final
`.musubi` snapshot. Its rear inspection is taken only after measurements finish.

## Next implementation gate

The next feature must demonstrate free loop formation and local retention, then
reversible preparation of a body-backed passage. Verify the same geometry with
intended pass, intended bypass and changed-mind inputs. Final retention must be
checked after temporary assistance is removed. Increasing the number of passing
fixture tests does not close the free-rope acceptance gap.
