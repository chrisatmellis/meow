# Headless verification

The game only builds and runs for real in Xcode. But most of what can actually be
*wrong* in it isn't UIKit or SceneKit — it's the solar clock, the cat's decision
making, the procedural mesh maths, the leg IK, the needs economy and the offline
catch-up. All of that is plain Swift.

`verify.sh` compiles the entire project against hand-written stand-ins for the
Apple frameworks and then runs it, so those parts can be exercised on any machine
with a Swift toolchain — including a Linux CI box with no Apple SDKs at all.

```sh
./verify.sh              # ~13M assertions across 15 areas
./verify.sh --profile    # simulate whole days, print how the cat spends them
```

## What it checks

`Harness/main.swift` asserts, among other things:

- **maths** — clamp/lerp/smoothstep/angle wrapping, vector algebra, RNG determinism and range, noise bounds
- **world clock** — sun elevation and azimuth are finite and in range across four seasons and 24 hours; the direction vector stays unit length; noon is brighter than midnight; the lantern wants to be on at night and off at noon
- **mesh builder** — degenerate triangles are rejected, vertex normals are unit length, and **lofted side faces point outward** (this is the check that would have caught the inside-out winding bug)
- **cat builder** — every breed × life stage produces four legs, a tail, positive bone lengths and a sane body height; parameter extremes (all sliders at 0, then all at 1, across every tail and ear shape) produce no NaN or zero-size geometry
- **animator** — 20 poses × 240 frames each, asserting every joint stays finite and within bounds, and that the look-at solver **settles instead of drifting** (this is the check that caught the neck-space feedback loop)
- **cat brain** — every personality archetype simulated for four hours at 20 Hz, asserting needs stay in 0…1, the cat stays inside the room, no NaN reaches the transform, behaviour actually varies, and events are emitted
- **interaction** — a lap cat comes when called; belly rubs build to overstimulation, produce a hiss or yowl, block further petting and then wear off; a swinging wand never wedges the cat and does satisfy the play need; a dropped treat gets eaten and cleaned up
- **consumables** — an empty feeder or fountain is never chosen, and refilling makes the cat use it again
- **offline catch-up** — 0 to 200 hours away leaves every need in range, caps at 72 hours, and produces a log
- **save file** — full round trip through JSON, and garbage is rejected rather than crashing
- **room layout** — thousands of random and out-of-bounds points clamp inside the room; every activity's target spot is reachable and captioned; the sun patch never leaves the floor
- **textures / room** — every breed, coat pattern and hour of the day is rendered, and lighting is applied across a whole day, to catch crashes and hangs

`Harness/profile.swift` is the design tool rather than a test. It simulates whole
days and prints where the time went, which is how the balance was tuned. A healthy
profile looks roughly like:

```
── Chill ──────────────────────────────
  sleepFuton      15.9%  ███████
  sleepSunPatch   11.2%  █████
  perchTree        9.8%  ████
  …
  asleep 53% · 25 distinct activities · 125 vocalisations · mood 0.77
```

Three things it is watched for: a cat asleep 40–55% of the day (not 5%, not 90%),
at least ~20 distinct activities in play, and roughly 100–200 vocalisations a day
— about one every ten minutes, rather than one a second.

## Looking at the cat

```sh
./verify.sh --render ./renders
```

`Harness/render.swift` is a small software rasteriser: it walks the node tree,
applies the transforms, projects the triangles and writes PNGs. It renders the
cat in six poses from two angles, six breeds side by side for silhouette
comparison, and the room from exactly where the player sits.

This is how the shim ended up with real 4×4 matrix maths — `convertPosition`
being an identity function meant the leg IK wasn't actually being exercised.
Making the transforms real both fixed that and made these pictures possible.

Things it caught: tail rings that bulged out like a caterpillar's segments,
16 cm whiskers, legs sized to be exactly straight when standing (so they could
not reach the floor when the cat sat up), a tail that curled far enough to loop
over the cat's own back, a single `tuck` value that folded the front legs of a
sitting cat, and a head welded to the shoulders with no neck to lift it.

`reference/` holds two of these renders — the cat standing, and the room from the
player's seat — to diff against after changing the rig or the layout.

The images are flat-shaded and untextured: no fur, no lighting, no materials, and
no near-plane clipping (which is why the top of the room shot is black rather than
ceiling). They are for checking proportion, pose and framing, not for judging how
the game will look.

## What it does not prove

The stand-ins in `Shims/` are written from the documented Apple API surface. They
make the project **typecheck and run**, which catches every error in our own code:
wrong types, bad argument labels, non-exhaustive switches, view-builder arity,
undefined symbols, NaN, out-of-range values, infinite loops.

They cannot verify that our *use of Apple's frameworks* is correct, because they
encode our belief about those frameworks rather than the frameworks themselves. A
wrong assumption baked identically into both the shim and the app would pass here
and fail in Xcode. Rendering, layout, audio output and touch handling are all
no-ops.

So: a green run means the logic is sound and the code compiles. It does not
replace building the app in Xcode once.

To narrow that gap, every non-obvious Apple API the game uses was checked against
Apple's published declarations rather than memory — `SCNCamera`'s post-processing
properties, `SCNLight`'s shadow and attenuation types (`zNear`/`zFar` are `CGFloat`
on lights but `Double` on cameras), `SCNMaterial.transparencyMode` and its
`rgbZero` case, `SCNParticleSystem`'s property names and the `SCNParticleBlendMode`
/ `SCNParticleBirthLocation` cases, `SCNNode.look(at:up:localFront:)` and
`convertPosition(_:from:)`, `SCNGeometrySource(textureCoordinates:)` taking
`[CGPoint]`, `AVAudioPlayerNode.scheduleBuffer(_:at:options:completionHandler:)`,
`UIImpactFeedbackGenerator.impactOccurred(intensity:)`, and the SwiftUI modifiers
with tighter availability windows (`statusBarHidden`, `presentationDetents`,
`PresentationDetent.height(_:)`, `LabeledContent(_:value:)`). The shims match
those declarations.

## Layout

```
Shims/     one Swift file per framework: CoreGraphics, QuartzCore, UIKit,
           SceneKit, AVFoundation, UserNotifications, SwiftUI
Harness/   main.swift (assertions), profile.swift (behavioural report),
           render.swift (software rasteriser)
reference/ flat-shaded reference renders to diff against after rig changes
verify.sh  builds the shims, stages the sources, compiles, runs
```

Staging copies the project to a scratch directory and rewrites the two
Objective-C-only constructs it uses (`@objc` and `#selector`, needed for the
gesture recognisers) before compiling. The repository itself is never modified.
