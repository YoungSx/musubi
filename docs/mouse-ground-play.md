# Single-mouse ground play (0.8.0)

## Player contract

The full mannequin remains the default scene and collision obstacle. Menu →
Lay rope on ground supplies an ordinary open rope in front of it. After this
setup, the core action uses only left press, drag and release. The ground camera
stays fixed; no wheel depth, second hand, pass button or hole selection is needed.
The shoulder scene and Advanced workbench keep their existing controls.

## Design basis

Nintendo's [Switch Sports interview](https://www.nintendo.com/au/news-and-articles/ask-the-developer-vol-5-nintendo-switch-sports/)
describes recognizing intended swings and balancing responsiveness with accuracy.
[Ocarina's contextual jumps](https://iwataasks.nintendo.com/interviews/3ds/zelda-ocarina-of-time/4/4/)
illustrate letting terrain choose motion details without another button.
[3D Land's shadow discussion](https://www.nintendo.com/en-gb/Iwata-Asks/Iwata-Asks-SUPER-MARIO-3D-LAND/Vol-1-SUPER-MARIO-3D-LAND/4-It-s-So-High-I-m-Scared-/4-It-s-So-High-I-m-Scared--216999.html)
informs the small ground contact shadows. These are design influences, not claims
that Nintendo uses Musubi's algorithms.

A 2D trajectory cannot uniquely reveal every possible 3D intention. The response
is a predictable local grammar with reversible assistance, rather than requiring
another input axis or pretending to know the player's mind. Ordinary crossings
travel over low strands. Sustained endpoint movement into a visible loop can
open a low passage. Equal hypotheses stay uncommitted. This first implementation
covers local floor loops, not arbitrary knot topology or universal intent inference.

## Implementation

- `GroundLoopTopology` observes material-coordinate crossings, simple projected
  loops and possible entrance edges; it rejects dense/degenerate observations.
- `GroundPassIntent` scores approach direction, speed continuity, distance and
  candidate persistence. A candidate needs 120 ms of sustained evidence and a
  score margin. Switching loop identity resets confidence.
- `GroundHand` supplies bounded vertical clearance. It never edits particles.
- For a confirmed approach, the assist layer temporarily supports a local strand
  using the same soft XPBD constraint mathematics as the primary grip. Support
  grows only with input, remains subject to collisions/length, and disappears on
  release, retreat, cancellation, focus loss or invalidated geometry. There is
  no player-controlled second hand and no persistent pin.
- The input target waits outside a closed gap. A pass is recorded only when the
  actual endpoint crosses the finite supported edge below it with clearance,
  entering the loop. A stationary cursor cannot advance the requested target.
- A remembered recent passage can reopen for reverse movement. General multi-pass
  unwind and knot recognition remain future work; the local reverse case has a
  controlled geometry test, not a broad human-play acceptance claim.
- Completed scene saves reject transient support; simulation snapshot version 4
  preserves active support for deterministic testing. Versions 1–3 still load.
- The entire assisted grab is one undo transaction. Physics continues after Set;
  no global freeze is used to manufacture persistence.

## Verification

`godot --headless --path . -s res://tests/run_tests.gd`

Tests cover temporal convergence, equal candidates, changed candidate identity,
stationary input, finite-edge/height crossing evidence, local reverse passage,
invalidated loops, support release, focus loss, fractional snapshot continuation,
one history transaction and unchanged primary grip behavior.

`godot --path . -s res://tools/verify_mouse_ground.gd -- <existing-output-dir>`

The rendered replay starts from the ordinary open rope, hides all HUD, and uses
fixed screen-coordinate left-mouse events. It forms a loop, approaches and passes
under an automatically supported strand, pulls and releases. It asserts real
crossing evidence, three separated crossings after settling, bounded stretch,
no leftover helper constraint and an unchanged camera. It records crossing order
and screenshots. It does not steer from hidden world coordinates, preload a knot,
change physical parameters mid-gesture or directly modify rope positions.

This is regression evidence for one complete gesture sequence, not proof that
first-time players can effortlessly tie arbitrary knots. Three crossings alone
are not a general knot classification. Next acceptance should vary approach speed,
route and loop shape, test multi-pass unwind and include novice observation.

Verified on Windows / Godot 4.7.2: 116 unit tests passed. The normal and 0.85x
motion-duration rendered replays both preserved crossing order
`[-1, 2, -3, 1, -2, 3]` after release. Pull-time maximum segment stretch was
approximately 0.35% and 0.37%, respectively. Existing full-mannequin play and
controlled spatial pass replays also passed. This does not establish mobile
performance or first-time-player usability.

0.7 extends this with bounded planar face discovery, persistent candidate scores,
physical-entrance deduplication and time-based velocity filtering. The same
screen-space sequence with `1 --jitter` adds two-pixel motion perturbations and
also preserves the alternating crossing order. See the [complex-case report](complex-case-feasibility.md)
for the historical failures and the remaining full-mannequin lattice gates.
Nintendo NERD's [gesture-filtering report](https://www.nerd.nintendo.com/2022/04/29/Switch_Sports.html)
is a design reference for input robustness, not a claim that Musubi uses
Nintendo's sensor fusion implementation.

0.8 adds [input-driven material transport](rope-transport.md), passing the full
single-knot unwind without changing rope length, using Undo or disabling contact.
