# Musubi

An interactive study of rope, form and connection.

Godot 4.7.2 / GDScript prototype, validating Windows locally first while keeping
the simulation and touch input portable. Open `project.godot`
in Godot and press F5 for the default play scene (`scenes/main/play.tscn`).
The previous workbench remains available at `scenes/main/main.tscn` (F6).
No third-party dependencies are required.

## Current milestone: independent touch grips (0.9.2)

Each finger that starts on visible rope owns an independent soft grip. Other
fingers control the camera: two drag to orbit and pinch to zoom, three drag to
pan. A single finger on empty space stays idle. Ownership is fixed until release,
so camera gestures cannot accidentally grab rope mid-drag. These camera gestures
also work in the floor session. Releasing one grip preserves the others; camera
motion preserves each hand's world target. Multi-hand gestures suspend shared
single-hand assistance until those grips are released.

Portrait input-dispatch replay verifies multiple grips, camera transitions,
release over UI and stable targets during camera smoothing. This automated
coverage does not replace physical touchscreen feel/performance acceptance.

Complex torso lacing is now a stress test of control quality, not a net-completion
target. Surface capture needs sustained evidence, front-side corrections do not
imply rear wrapping, deliberate departure releases assistance, and stopping the
mouse does not advance route waypoints. Local body routing preserves the chosen
entry side and spatial passages take priority over ordinary surface following.
See the [control-authority audit](docs/control-authority.md) for design sources,
rendered negative tests and the remaining need for first-time-player observation.

Rim return strokes now preserve their wrap evidence, and a loaded grip can turn
or retreat without increasing its lead distance. Torso-side passages search a
bounded radial strip rather than a single point; the incoming tail can follow
through without being mistaken for a nonlocal obstacle. A controlled ring around
the full torso passes rendered mouse-driven crossing checks. The unseeded full
lattice remains incomplete: preparing closed gaps and retaining successive
interlocking cells are still open.

The default scene retains the full mannequin and its limb/torso collisions.
An unpinned rope rests naturally across its shoulders. Grab any visible portion
of the rope, move it and release: physics continues, with a brief local damping
pulse rather than a frozen scene. Grabs address a continuous location between
particles. During a grab, two additional fingers on empty space or right mouse
drag can inspect the scene without dropping the rope or moving its world target.

The default UI has one Menu entry. Rope settings, snapshots, undo/redo and pause
controls remain available through Advanced; developer targets and endpoint labels
are hidden in normal play. Saved workbench creations retain their old held-release
behavior. Play mode now offers conservative local pass-corridor assistance,
including intent scoring and clear side passages around mannequin occlusion.
Verified first-time-player Overhand/Half Hitch play is not implemented yet.
See [pass assistance and its acceptance limits](docs/pass-assistance.md).

Menu → **Lay rope on ground** starts a floor session (fixed camera for mouse input) in front of the
full mannequin. Left-drag forms loops; a sustained approach into a loop can
gently lift a local strand and guide the tip underneath. Release removes the
temporary support and lets the rope settle. No second mouse button or depth
control is required in this session. See [single-mouse design and verification](docs/mouse-ground-play.md).

Passage discovery now includes cells bounded by several material arcs, with
persistent candidate evidence and time-based velocity filtering. A replay with
two-pixel pointer jitter passes the complete ground knot sequence. Endpoint
drags can transition from the ground to the mannequin surface. A knotted ground
rope can now be retracted along its current path by moving its end inward; this
uses reversible soft transport constraints, with length and collisions active.
[Transport design and replay evidence](docs/rope-transport.md) covers the verified
single-knot unwind. Compound knots and a mouse-tied torso lattice remain open in
the [complex-case report](docs/complex-case-feasibility.md).

The capabilities below describe the shared core and advanced workbench:

- Abstract mannequin and studio lighting.
- One procedural tube mesh with rounded ends, suspended between two anchors.
- Particle-based Verlet integration and XPBD distance constraints, gravity,
  damping and fixed simulation steps.
- Sphere, capsule and oriented-box contacts derived from mannequin data,
  including rope segment interiors, floor contact and friction.
- Rope self-contact between nonlocal segments, with mass-weighted separation,
  relative sliding friction and bounded swept crossing checks.
- Camera orbit, zoom and pan; Reset restores the camera, mannequin pose and
  rope simulation and original anchor positions.
- Grab visible rope segments with a finger or mouse. A soft positional
  constraint responds to the pointer while respecting attachments and contacts.
  Workbench release holds the shape; Play release continues simulation.
- Grab marker and contextual hints. A developer-only Debug toggle reveals
  rope particles, constraints, collision outlines, selection, FPS and timings.
- Versioned JSON simulation snapshots preserve configuration, particles,
  velocity history, pins and active grab state for future local save/replay.

Touch: each finger on rope grabs independently; two fingers on empty space orbit
and pinch to zoom, three pan. Mouse: left-drag grabs rope or orbits empty space, right/middle-drag
pans, wheel zooms. Grab either dark endpoint to release that attachment;
release keeps it free, with natural motion in Play and a held shape in Workbench. The wheel moves the grabbed rope
toward/away from the camera during a drag. Esc restores the complete pre-grab
shape and attachments; Reset restores both original attachments.

Desktop: the rope highlights on hover. R resets the scene, F restores the view,
Space pauses/resumes, Esc cancels a grab and restores its starting shape, and
F11 toggles full screen. Mouse picking uses a tighter tolerance than touch.
In Workbench, gold marks the grabbed rope; blue marks its requested target, including when
occluded. Continue/Hold controls physics explicitly; B or Other side turns the
camera around. The Rope menu creates 1.4/2.2/3.0/6.0 m ropes and fixes/releases A or B.
Ctrl+Z undoes a rope edit, Ctrl+Shift+Z/Ctrl+Y redoes it. History includes grabs,
endpoint changes, new ropes and Reset; camera movement is not undone. It is
bounded to 32 entries and 4 MiB of encoded snapshots. Loading clears history.
Save/Open (Ctrl+S/Ctrl+O) writes and restores `.musubi` creations, including
rope shape and velocity, free endpoints, held state, camera and mannequin pose.
F9 exports rolling CPU/frame measurements as JSON and CSV, with a scene snapshot,
to `%APPDATA%/Godot/app_userdata/Musubi/reports`.

Build a standalone Windows package with
`powershell -ExecutionPolicy Bypass -File tools/build_windows.ps1 -Configuration Release -RenderSmoke`.
See [Windows builds and logs](docs/windows-build.md). Extract the resulting ZIP
and double-click `Musubi.exe`, keeping `Musubi.pck` alongside it.

## Module boundaries

| Location | Responsibility |
| --- | --- |
| `scripts/rope/rope_config.gd`, `data/rope/` | Physical parameters and preset |
| `scripts/rope/rope_layout.gd` | Initial centerline geometry |
| `scripts/rope/rope_simulation.gd` | Particles, pins and constraint solving; no nodes or input |
| `scripts/rope/rope_collision.gd` | Primitive contacts, segment projection and bounded motion sweeps |
| `scripts/rope/rope_self_collision.gd` | Swept segment bounds, rope/rope contacts and relative friction |
| `scripts/rope/rope_renderer.gd` | Centerline to a single tube mesh |
| `scripts/rope/rope.gd` | Fixed-step scheduling, anchors and renderer wiring |
| `scripts/interaction/rope_interaction.gd` | Visible-segment picking, grab plane and solver intent |
| `scripts/core/app_controller.gd` | Scene wiring and Reset |
| `scripts/interaction/`, `scripts/camera/` | Input gestures and camera intent |
| `scripts/mannequin/`, `data/mannequin/` | Figure geometry and matching primitive collision shapes |

The legacy workbench rope uses 48 segments, a 1.4 m rest length, 120 Hz simulation,
6 substeps and 2 constraint iterations per substep. Catch-up is bounded after
frame hitches. The desktop window starts at 1280×800, resizes down to 960×640
and adapts UI scale to display DPI. Mobile retains its portrait viewport.
New 2.2 m and 3.0 m ropes use 72/96 segments at 60 Hz with 10/8 substeps.
Imported creations restore their own validated configuration and simulation
frequency; the renderer rebuilds topology accordingly.

## Verification

Run from the project directory, substituting your Godot executable:

```text
godot --headless --path . --import
godot --headless --path . -s res://tests/run_tests.gd
godot --path . -s res://tools/capture_screenshot.gd -- <absolute-output.png> 180
godot --path . -s res://tools/verify_interaction.gd -- <output-directory>
godot --path . -s res://tools/verify_self_collision.gd -- <output-directory>
godot --path . -s res://tools/verify_tightening.gd -- <output-directory>
godot --path . -s res://tools/verify_wrap.gd -- <output-directory>
godot --path . -s res://tools/verify_pass_assist.gd -- <output-directory>
godot --path . -s res://tools/verify_play_mannequin.gd -- <output-directory>
godot --path . -s res://tools/verify_multitouch.gd -- <output-directory>
godot --path . -s res://tools/verify_mouse_ground.gd -- <output-directory>
godot --path . -s res://tools/verify_control_authority.gd -- <output-directory>
godot --path . -s res://tools/probe_torso_lattice.gd -- <output-directory>
godot --path . -s res://tools/verify_creation_workflow.gd -- <output-directory>
godot --headless --path . -s res://tools/benchmark_creation.gd
godot --path . -s res://tools/verify_desktop_stability.gd
```

The screenshot command requires a graphics driver and an existing output
directory. Unit tests cover camera/gestures, mannequin construction, rope
length, settling, repeatability, pins, mesh geometry and simulation reset.

Windows verification used Godot 4.7.2 with Vulkan Forward Mobile on RTX 3070.
All 161 tests passed. A rendered scene smoke check exercised camera orbit,
zoom and pan, a temporary rope pin and release, and the HUD Reset signal.
The rendered interaction smoke additionally sends mouse input through Godot's
input dispatch, drags the rope, releases over the HUD and clicks Reset.
It also clicks Debug, captures the diagnostic overlay and verifies Space/F keys.
It checks endpoint release, depth control, cancellation, F9 reports, Save/Open
button dialogs and full scene restoration via their file-selection signals.
This checks scene integration, not physical touchscreen input. Tests cover
two-finger transitions, cancellation, focus loss and occluded picking.

`RopeSimulation.capture_state()` returns detached JSON-compatible data;
`RopeSimulation.restore_state(data)` returns a new simulation, or `null` for
invalid data. Use `JSON.stringify(state, "", true, true)` for full precision.
Round-trip continuation is tested. Collision geometry, scene transforms and
the Rope node's held/catch-up state are application data and are not included
in this simulation snapshot. `MusubiSceneState` adds these fields for full
creation files, validates before changing the live scene and replaces files
only after a successful temporary-file write. Invalid files leave the scene intact.
Simulation format v7 records independent touch grips and transport ownership; v6 records independent length sweeps; v1–v5 retain their original
single-sweep schedule. Version 5 added distributed transport targets to the support,
fractional-grip and release state. New 6 m shoulder ropes use four length sweeps
and a firmer soft grip; contacts remain enabled. Existing v1 creations load
with self-contact disabled to preserve their behavior; Reset starts a new rope
with the current default (enabled). Debug shows the active setting and last-pass
contact count. See [self-contact implementation and verification](docs/rope-self-collision.md).
See [Windows creation controls and acceptance](docs/windows-creation.md) for
the complete authoring workflow, history behavior and measured limitations.
For current play-mode behavior and evidence, see [mannequin interaction](docs/mannequin-play.md).
The [torso sequence acceptance](docs/acceptance-torso-sequence.md) separates
passing controlled passage/reversal cases from the failing free-loop prerequisite.

## Remaining validation and next milestone

- Collision supports rigid transforms and positive uniform scale. Motion
  sweeps are bounded; arbitrary-speed continuous collision detection and
  guaranteed knot topology are not implemented. Default mannequin contact tests
  check segment clearance, length, settling and friction.
- Profile both solver and renderer on iPad. Cached segment bounds and radial
  trigonometry reduced Windows headless solver time about 15% and mesh work
  about 21% in a same-process comparison. Held frames skip mesh updates.
  The renderer recreates its mesh surface when simulation advances; array reuse does not eliminate engine
  or GPU allocations. Mobile performance and memory acceptance remain open.
- Native iPhone IPA compilation now passes on GitHub's macOS runner with
  Godot 4.7.2 and Xcode 26.3. Local WSL xtool connects to the USB iPhone through
  Windows Apple device services. Local signing and installation on iPhone 15 Pro
  / iOS 27.2 are verified. Device logs confirm the app runs and receives touch
  events; full interaction and mobile performance acceptance remain pending.
  See [Windows iOS build and installation](docs/windows-ios.md).
