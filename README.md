# Musubi

An interactive study of rope, form and connection.

Godot 4.7.2 / GDScript prototype, targeting iOS first. Open `project.godot`
in Godot and run the main scene (F6 from `scenes/main/main.tscn`, or F5).
No third-party dependencies are required.

## Current milestone: rope rendering and basic simulation

- Abstract mannequin and studio lighting.
- One procedural tube mesh with rounded ends, suspended between two anchors.
- Particle-based Verlet integration and XPBD distance constraints, gravity,
  damping and fixed simulation steps.
- Camera orbit, zoom and pan; Reset restores the camera, mannequin pose and
  rope simulation for the fixed-anchor scene.

Touch: one finger orbits; two fingers pan and pinch to zoom.
Mouse: left-drag orbits, right/middle-drag pans, wheel zooms.
Rope dragging and mannequin collision are upcoming milestones.

## Module boundaries

| Location | Responsibility |
| --- | --- |
| `scripts/rope/rope_config.gd`, `data/rope/` | Physical parameters and preset |
| `scripts/rope/rope_layout.gd` | Initial centerline geometry |
| `scripts/rope/rope_simulation.gd` | Particles, pins and constraint solving; no nodes or input |
| `scripts/rope/rope_renderer.gd` | Centerline to a single tube mesh |
| `scripts/rope/rope.gd` | Fixed-step scheduling, anchors and renderer wiring |
| `scripts/core/app_controller.gd` | Scene wiring and Reset |
| `scripts/interaction/`, `scripts/camera/` | Input gestures and camera intent |
| `scripts/mannequin/`, `data/mannequin/` | Figure geometry and matching primitive collision shapes |

The default rope uses 48 segments, a 1.4 m rest length, 120 Hz simulation,
6 substeps and 2 constraint iterations per substep. Catch-up is bounded after
frame hitches. The default camera preset frames both endpoints in portrait.

## Verification

Run from the project directory, substituting your Godot executable:

```text
godot --headless --path . --import
godot --headless --path . -s res://tests/run_tests.gd
godot --path . -s res://tools/capture_screenshot.gd -- <absolute-output.png> 180
```

The screenshot command requires a graphics driver and an existing output
directory. Unit tests cover camera/gestures, mannequin construction, rope
length, settling, repeatability, pins, mesh geometry and simulation reset.

Windows verification used Godot 4.7.2 with Vulkan Forward Mobile on RTX 3070.
All 26 tests passed. A rendered scene smoke check exercised camera orbit,
zoom and pan, a temporary rope pin and release, and the HUD Reset signal.
This checks scene integration, not physical touchscreen input.

## Remaining validation and next milestone

- Add a separate `RopeCollision` module using mannequin sphere/capsule data,
  then test penetration, contact stability and length under collision.
- Add segment picking and temporary drag constraints in `RopeInteraction`.
  Define anchor removal and anchor Reset semantics at that stage: currently
  removing an anchor reference alone does not release its pin, and Reset
  rebuilds from current anchor positions.
- Profile both solver and renderer on iPad. The renderer currently recreates
  its mesh surface each display frame; array reuse does not eliminate engine
  or GPU allocations. Mobile performance and memory acceptance remain open.
- iOS export/signing and physical touch remain unverified. Windows recognizes
  the USB-connected iPad, but this environment has no detected `xcrun` or
  libimobiledevice tools. A macOS/Xcode signing/build environment and matching
  Godot export templates are needed for native iOS deployment.
