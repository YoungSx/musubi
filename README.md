# Musubi

An interactive study of rope, form and connection.

Godot 4.7.2 / GDScript prototype, validating Windows locally first while keeping
the simulation and touch input portable. Open `project.godot`
in Godot and run the main scene (F6 from `scenes/main/main.tscn`, or F5).
No third-party dependencies are required.

## Current milestone: interactive prototype with diagnostics

- Abstract mannequin and studio lighting.
- One procedural tube mesh with rounded ends, suspended between two anchors.
- Particle-based Verlet integration and XPBD distance constraints, gravity,
  damping and fixed simulation steps.
- Sphere, capsule and oriented-box contacts derived from mannequin data,
  including rope segment interiors, floor contact and friction.
- Camera orbit, zoom and pan; Reset restores the camera, mannequin pose and
  rope simulation for the fixed-anchor scene.
- Grab visible rope segments with a finger or mouse. A soft positional
  constraint responds to the pointer while respecting attachments and contacts.
  Release holds the current shape; grabbing again resumes simulation.
- Grab marker and contextual hints. A developer-only Debug toggle reveals
  rope particles, constraints, collision outlines, selection, FPS and timings.
- Versioned JSON simulation snapshots preserve configuration, particles,
  velocity history, pins and active grab state for future local save/replay.

Touch: drag the rope to shape it, drag empty space to orbit; two fingers pan
and pinch to zoom. Mouse: left-drag has the same behavior, right/middle-drag
pans, wheel zooms. The two dark attachment endpoints stay fixed.

## Module boundaries

| Location | Responsibility |
| --- | --- |
| `scripts/rope/rope_config.gd`, `data/rope/` | Physical parameters and preset |
| `scripts/rope/rope_layout.gd` | Initial centerline geometry |
| `scripts/rope/rope_simulation.gd` | Particles, pins and constraint solving; no nodes or input |
| `scripts/rope/rope_collision.gd` | Primitive contacts, segment projection and bounded motion sweeps |
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

## Verification

Run from the project directory, substituting your Godot executable:

```text
godot --headless --path . --import
godot --headless --path . -s res://tests/run_tests.gd
godot --path . -s res://tools/capture_screenshot.gd -- <absolute-output.png> 180
godot --path . -s res://tools/verify_interaction.gd -- <output-directory>
```

The screenshot command requires a graphics driver and an existing output
directory. Unit tests cover camera/gestures, mannequin construction, rope
length, settling, repeatability, pins, mesh geometry and simulation reset.

Windows verification used Godot 4.7.2 with Vulkan Forward Mobile on RTX 3070.
All 53 tests passed. A rendered scene smoke check exercised camera orbit,
zoom and pan, a temporary rope pin and release, and the HUD Reset signal.
The rendered interaction smoke additionally sends mouse input through Godot's
input dispatch, drags the rope, releases over the HUD and clicks Reset.
It also clicks Debug and captures the diagnostic overlay.
This checks scene integration, not physical touchscreen input. Tests cover
two-finger transitions, cancellation, focus loss and occluded picking.

`RopeSimulation.capture_state()` returns detached JSON-compatible data;
`RopeSimulation.restore_state(data)` returns a new simulation, or `null` for
invalid data. Use `JSON.stringify(state, "", true, true)` for full precision.
Round-trip continuation is tested. Collision geometry, scene transforms and
the Rope node's held/catch-up state are application data and are not included
in this simulation snapshot. No save UI or filesystem writes are added.

## Remaining validation and next milestone

- Collision supports rigid transforms and positive uniform scale. Motion
  sweeps are bounded; rope self-collision and arbitrary-speed continuous
  collision detection are not implemented. Default mannequin contact tests
  check segment clearance, length, settling and friction.
- The current attachments stay fixed. Before making them movable, define
  anchor removal and anchor Reset semantics: currently
  removing an anchor reference alone does not release its pin, and Reset
  rebuilds from current anchor positions.
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
