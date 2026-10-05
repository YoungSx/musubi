# Musubi

An interactive study of rope, form and connection.

Godot 4.7.2 / GDScript prototype, validating Windows locally first while keeping
the simulation and touch input portable. Open `project.godot`
in Godot and run the main scene (F6 from `scenes/main/main.tscn`, or F5).
No third-party dependencies are required.

## Current milestone: Windows creation prototype (0.3.0)

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
  Release holds the current shape; grabbing again resumes simulation.
- Grab marker and contextual hints. A developer-only Debug toggle reveals
  rope particles, constraints, collision outlines, selection, FPS and timings.
- Versioned JSON simulation snapshots preserve configuration, particles,
  velocity history, pins and active grab state for future local save/replay.

Touch: drag the rope to shape it, drag empty space to orbit; two fingers pan
and pinch to zoom. Mouse: left-drag has the same behavior, right/middle-drag
pans, wheel zooms. Grab either dark endpoint to release that attachment;
release keeps it free and holds the shape. The wheel moves the grabbed rope
toward/away from the camera during a drag. Esc restores the complete pre-grab
shape and attachments; Reset restores both original attachments.

Desktop: the rope highlights on hover. R resets the scene, F restores the view,
Space pauses/resumes, Esc cancels a grab and restores its starting shape, and
F11 toggles full screen. Mouse picking uses a tighter tolerance than touch.
Gold marks the grabbed rope; blue marks its requested target, including when
occluded. Continue/Hold controls physics explicitly; B or Other side turns the
camera around. The Rope menu creates 1.4/2.2/3.0 m ropes and fixes/releases A or B.
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

The default rope uses 48 segments, a 1.4 m rest length, 120 Hz simulation,
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
godot --path . -s res://tools/verify_creation_workflow.gd -- <output-directory>
godot --headless --path . -s res://tools/benchmark_creation.gd
godot --path . -s res://tools/verify_desktop_stability.gd
```

The screenshot command requires a graphics driver and an existing output
directory. Unit tests cover camera/gestures, mannequin construction, rope
length, settling, repeatability, pins, mesh geometry and simulation reset.

Windows verification used Godot 4.7.2 with Vulkan Forward Mobile on RTX 3070.
All 89 tests passed. A rendered scene smoke check exercised camera orbit,
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
Simulation format v2 includes self-contact settings. Existing v1 creations load
with self-contact disabled to preserve their behavior; Reset starts a new rope
with the current default (enabled). Debug shows the active setting and last-pass
contact count. See [self-contact implementation and verification](docs/rope-self-collision.md).
See [Windows creation controls and acceptance](docs/windows-creation.md) for
the complete authoring workflow, history behavior and measured limitations.

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
- iOS export/signing and physical touch remain unverified. Windows recognizes
  the USB-connected iPad, but this environment has no detected `xcrun` or
  libimobiledevice tools. Standard export uses macOS/Xcode; Windows can also
  use WSL cross-compilation and tools such as xtool. This project's full
  build/sign/install integration has not been verified. See the researched
  [Windows iOS build routes and prerequisites](docs/windows-ios.md).
