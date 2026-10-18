# Octopus Play Mode

Twin-stick locomotion and grapple mode for Musubi. The player navigates an
octopus mascot over signed-distance sculpture surfaces and grabs, reels, carries,
and releases dynamic rope constraints.

## Locomotion, Jump Mechanics, and Game Feel Polish

### 1. Dual-Stick & Jump Integration
- **Left Stick**: Drives surface walking along tangent frames and steers airborne trajectories.
- **Right Stick Center Tap / Space Bar**: Triggers jump (`jump_speed = 2.2 m/s`, `jump_horizontal_boost = 0.8`).
- **Right Stick Drag & Release**: Aims and grapples visible rope material.

### 2. Aim Cancel Safeguard
- Dragging the aim stick and releasing outside the deadzone initiates a rope grab.
- Returning the aim stick to center before releasing cancels the aim gesture without triggering an unintended jump.

### 3. Wall Jump & Upward Bias
- When leaping off vertical or steep sculpture slopes, the launch direction blends the local surface normal with world up (`jump_upward_bias = 0.4`), producing an athletic parabolic arc instead of pitching horizontally away from the wall.

### 4. Forgiveness & Buffer Windows
- **Coyote Time (0.12 s)**: Walking off ledges or sculpture contours preserves the ability to jump for a brief window after detachment.
- **Jump Input Buffering (0.15 s)**: Pressing jump slightly before landing queues the impulse, executing seamlessly on the very first contact frame.
- **Air Control (0.35)**: Left-stick horizontal input steers airborne velocity (`air_control = 0.35`), giving subtle mid-air corrective agency.

### 5. Physical Juice & Weight Presentation
- **Carrying Drag (`carry_drag_factor = 0.85`)**: Walking while holding heavy rope introduces tangible physical tension.
- **Landing Impact & Squash/Stretch**: Landing from airborne falls feeds vertical impact momentum into volume-preserving procedural deformation (`OctopusLocomotion.trigger_landing_impact`), settling back via damped harmonic spring curves.

## Aim feedback

The grab resolves on release, so without feedback during the gesture the player
aims blind and learns the result only once the gesture is spent. Two surfaces
answer that, both driven from the same place the grab is:

- While the stick is held, `AimIndicator` draws a ray from the body and a ring
  on the material a release would take. The preview calls `Octopus.aim_material`,
  which runs the same `pick` with the same cone and the same visibility test the
  grab runs, so the ring cannot promise material the grab would refuse. Nothing
  in reach draws the bearing alone, dimmed.
- A grab that found nothing says so in the hint line for 1.6 s. The cone and the
  line of sight both fail silently, and a silent failure is indistinguishable
  from a stick that does nothing — which is how the working-but-unread aim stick
  in `5108cbe` read as broken.

The ring is drawn on the canvas rather than placed in the world because the
aimed material is often behind the figure being climbed, and feedback the figure
can hide is feedback the player cannot rely on. A target off the edge of the
screen keeps its true position rather than being clamped onto it: clamping would
put the ring where the material is not, and `_draw` is not clipped to the
control's rect, so the ray's visible part still carries the bearing.

Two engine facts shape this. `Camera3D.unproject_position` does not report that
a point is behind the camera — it returns a plausible-looking position — so
`is_position_behind` is checked separately for both the eye and the target.
And the mode owns `_aim_locked` itself rather than reading the state back out of
the indicator, so the ring is drawn only when the indicator is actually locked.

## Visual presentation

- All eight arms are one `MultiMesh` bead chain: a single draw call, and no
  second tube-mesh builder beside the rope's.
- Continuous swept tentacle skin extends from the mascot model's base, tapering
  to a hemispherical tip with two-tone shading.
- Procedural locomotion animates volume-preserving squash and stretch, walking
  waddle roll, forward pitch, and idle breathing.

No performance or physical-touch acceptance is inferred from the desktop
replay.

Replay command (create the output directory first):

```text
godot --path . -s res://tools/verify_octopus.gd -- <output-directory>
```
