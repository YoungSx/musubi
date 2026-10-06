# Control authority audit — complex lacing as a stress scenario

## Frame and success criteria

The problem is whether one mouse lets players express, revise and cancel spatial
rope intentions predictably. Completing a particular net is diagnostic context,
not the success metric. Prototype contracts: immediate free motion while a
candidate is uncertain; no capture from a one-frame brush; no new waypoints after
input stops; deliberate departure releases assistance; free-space reversal changes
the requested direction immediately; release removes all temporary control.

## Axioms

A1. Perspective projection is many-to-one: a screen point alone cannot identify
one intended 3D depth (front/back points can share a projection).
A2. Identical final geometry can be reached with different player effort and
amounts of automation; geometry alone cannot measure control quality.
A3. Once a grab ends, subsequent input no longer authorizes that grab's transient
constraints; this boundary is directly observable through the input lifecycle.

## Assumptions challenged

| Assumption | Challenge | Basis | Decision |
| --- | --- | --- | --- |
| A completed knot proves good controls | Assistance can produce the same result while overriding choices | A2 | Discard |
| Lower stretch means better UX | A frozen/sticky target can have excellent numerical stability | A2 | Keep stretch only as a physics gate |
| Pointer/body overlap means attachment | A passing stroke can overlap the same pixels | A1 | Require sustained evidence; preserve free response first |
| A reversal always means going behind | Correction and continuation can look similar | A1 | Hysteresis plus silhouette evidence; test false positives |
| Finish the planned route after the pointer stops | Continuous manipulation is not a committed discrete jump | A2, A3 | Remove autonomous waypoint advance |
| More assistance is always easier | Strong guidance can increase effort needed to change one's mind | A2 | Test escape/reversal alongside capture |
| A synthetic expert replay represents beginners | Expected intentions have not been labelled by real newcomers | A1, A2 | Keep novice acceptance open |

## Current ground truths

G1. The full lacing sweep produced crossings but no verified complete net; the
baseline maximum segment error was 11.01%, versus approximately 3.88% in a revised
run. Neither number establishes that the intended route was selected.
G2. Surface following originally captured immediately and never left its active
state during a grab, even after dragging far away from the figure.
G3. An intermediate implementation advanced new surface waypoints in tick()
without fresh pointer movement. This could continue moving the requested hand,
not just allow physics to catch up to the last requested target.
G4. Surface-following mode originally bypassed spatial passage evaluation.

## Reasoning and changes

G2 + A1 -> free response during candidate accumulation, then soft surface capture;
leaving the projection by a small deliberate stroke releases it.
G3 + A3 -> no autonomous routing on idle ticks; physics may still settle.
G4 + A1 -> passage interpretation can take priority over surface following.
G1 + A2 -> retain lacing as a stress trace, but add expected-intent microcases:
brush, front-side correction, stop, departure, reversal and release. Record both
requested-target and actual-grip motion, so solver lag is not confused with a
recognizer choosing the wrong action.

## Primary design references

- Nintendo's [Super Mario Galaxy developers](https://iwataasks.nintendo.com/interviews/wii/super_mario_galaxy/1/0/)
  describe responsive, pleasant control as central, and connect readable form to
  function. Our implication: assess the basic grab/move loop before knot output.
- [Nintendo Switch Sports](https://www.nintendo.com/au/news-and-articles/ask-the-developer-vol-5-nintendo-switch-sports/)
  discusses matching novice expectations, testing varied people and the trade-off
  between recognition accuracy and responsiveness. Our implication: labelled
  intent cases and human trials are necessary; a programmer's successful gesture
  is insufficient. Its ML implementation is not a claim about Musubi's algorithms.
- [Ocarina of Time autojump](https://iwataasks.nintendo.com/interviews/3ds/zelda-ocarina-of-time/4/4/)
  removes an extra button using terrain context. Our implication is contextual
  precision assistance after a clear action, not permission to choose a whole
  rope operation or to override a withdrawal.

## Validation and pre-mortem

All seven assumptions are tied to the axioms; G1–G4 each has an implementation or
test consequence. The principal failure risk is optimizing a beautiful completed
net while the controller quietly changes the player's intended action. The
countermeasure is to retain negative/control-authority cases even if capture or
knot completion rates fall. Numeric thresholds are prototype policy, not Nintendo
prescriptions. Human intent accuracy and perceived magnetism remain unverified
until first-time players provide expected-intent observations.

Phases 0–5: framing, essence, seven challenged assumptions, four code/runtime facts,
traceable changes and pre-mortem recorded. Runtime results are appended only after
execution; no claim of novice validation is made here.

## Implemented control contracts

- Surface capture needs sustained motion, not a brush, idle time or small tremor.
  Free dragging responds immediately while evidence accumulates.
- Rear wrapping needs an outward silhouette approach, actual silhouette exit and
  return travel. A front-side correction is insufficient. The route preserves the
  indicated entry side; a contradictory stroke brakes and then cancels it.
- Routes share the solver's body geometry and contact radius. An earlier larger
  routing margin rejected valid resting contacts and made the hand stick.
- Ordinary wrapping can clear a nearby strand outward from the body, but never
  through a neighboring arm. A spatial passage takes priority over this default.
- No pointer movement means no new route progress. Physics can still catch up to
  the last requested hand target. Release clears transient surface assistance.
- Deliberate departure releases attraction. The remaining grab-plane offset fades
  with further pointer travel, not elapsed time: no exit snap or lasting offset.
- Whole-rope unthreading needs sustained inward travel and a still-valid crossing
  structure. A tiny nudge or old pre-pause evidence cannot start it.

These are local prototype rules, not a general intent recognizer or a promise to
infer every front/back choice. The horizontal route planner can only resolve
local slices; complex passages and obstructed height changes remain limitations.

## Verification — Windows, 2026-10-06

149 unit/integration tests pass. `tools/verify_control_authority.gd` dispatches
mouse input to the real rendered scene: approach, stop, front correction, escape,
continued motion, reversal and release all pass. The CSV stores requested target
and actual grip separately. The script is a regression, not a human study.

The exit regression initially retained about 19 logical pixels of pointer/target
offset. With movement-driven hand-back, subsequent free forward/reverse motion
has zero offset in the measured replay. Unit cases separately cover contradictory
wrap motion, expressed entry side and stationary-target invariance.

The 6 m preset now runs at most one fixed simulation step per rendered update.
In the same scripted lift, recorded input/render samples increased from 102 over
9.72 s to 339 over 9.22 s; mean requested-target/cursor gap fell from 9.08 to 1.44
logical pixels. This is one desktop replay, not a 60 FPS guarantee or an input
latency benchmark. Under overload physics intentionally falls behind wall time;
saved creations retain their serialized step limit. This bounds catch-up work,
consistent with the overload trade-off described in
[Fix Your Timestep](https://gafferongames.com/post/fix_your_timestep/).

Rendered ground-knot formation/release/unthreading with two-pixel jitter also
passes (zero final projected crossings; peak segment error 0.93%). The mannequin
replay passes surface clearance, natural release, inspection and save/load checks.

The final 20-stroke mannequin lacing trace keeps the camera fixed and reaches
0.517 m of measured rear grip travel. Peak segment error is 4.02%, and minimum
sampled grip/body clearance is 0.012056 m for a 0.012 m rope radius. Screenshots
show slipping strands, not a retained interlocking net. Spatial Pass never
activates in this trace, and several broad upper-body returns stay on the front.
That is a usability warning: the conservative rim gesture may be too hard to
discover amid arms/torso overlap. Neither zero false captures in the small
regression set nor numerical stability establishes correct intended-side choice.
Do not simply lower capture thresholds to make this one script succeed; use
labelled wrap/correction pairs and test both errors together.

## Next acceptance work

### Follow-up: return motion and loaded steering

The detailed lacing trace exposed a recognition bug: outside travel accumulated
both outward and inward motion. A small rim excursion therefore lost its wrap
evidence on the way back, falsely interpreting the return as an escape. Escape
now uses displacement from the departure point. Clear outward departure still
releases assistance; front-only correction and tremor retain their negative tests.

A second bug spent the entire movement budget on existing hand lag, preventing
turning and retreat when the solver was under load. The lead envelope now limits
outward distance while allowing bounded steering inside it, with body-segment
clearance checked before accepting the new target. There is still no idle route
advance. The rendered control-authority replay passes after both changes.

The lacing probe now exports per-frame recognition state, requested route target,
actual grip and their gaps. Several upper-body returns now acquire rear intent,
but the grip still lags; the 20-stroke replay does not retain a net (4.62% peak
segment error, no spatial pass activation). A temporary stronger-grip experiment
improved following but reached 10.84% segment error and was rejected. These are
separate recognition, solver and usability findings, not a completed-case claim.

1. Observe first-time players making a front correction, wrapping a specified
   side, abandoning a route and releasing. Ask what they intended before showing
   diagnostic state. Report false captures and effort to escape, not just success.
2. Compare assisted/unassisted manipulation with the same scene and task. Label
   intended side/passage, wrong-choice rate, recovery strokes and perceived control.
3. Test backside readability and local passage selection amid multiple strands.
   Do not compensate for missing intent evidence by completing the net automatically.
4. Evaluate transport hand-back after the last crossing: guiding the entire rope
   may still feel too strong even when a complete unthreading replay passes.
