# Meow — a cat, a room, and the actual time of day

A first-person iOS game set in one small Japanese-style bedroom. You don't move.
You sit on a zabuton with your back to the wall and you live with a cat.

The cat is yours: you build it in detail before you ever see the room — breed,
coat pattern, fur length, eye colour and pupil shape, ear length and fold, muzzle,
build, tail, whiskers, temperament. Then it gets on with its life. It sleeps,
eats from the automatic feeder, drinks from the fountain, uses the litter box,
scratches the post, watches the garden, chirps at birds, knocks the teacup off
the table at 3am, and occasionally comes over to sit with you.

## Running it

Open `Meow.xcodeproj` in Xcode 16 or newer and run the `Meow` scheme on an
iOS 17+ device or simulator. There is nothing to install and no package
dependencies — every mesh, texture and sound in the game is generated at
runtime in Swift.

Notifications need a real device to be useful. The simulator will show the
permission prompt but background delivery is unreliable there.

## What's in the box

```
MeowRoom/
  App/            @main entry point, top-level app state, save lifecycle
  Core/           Vector maths, seeded RNG, value noise, codable colour
  Model/          Cat appearance (≈70 parameters), personality, needs, save file
  Simulation/     Solar clock, utility-AI cat brain, offline catch-up
  Scene/          Procedural meshes, textures, materials, the room, the cat rig,
                  the animator, lighting, and the SceneKit controller
  Audio/          Runtime synthesis: meow, trill, chirp, purr, hiss, yowl, …
                  plus the haptics that go with them
  Notifications/  Local notification scheduling
  UI/             SwiftUI character creator, live 3D preview, in-game HUD

Tools/
  linux-verify/   Framework stand-ins and the headless verification harness
```

### Time of day is real

`WorldClock` computes solar declination and hour angle from the device's clock
and time zone, so the sun's elevation and azimuth are genuinely correct for the
moment you open the app. Everything downstream follows: the colour and intensity
of the light raking through the shoji, how strongly the paper glows, the sky and
garden seen through the open half of the window, the sun patch sliding across the
tatami, whether the paper lantern comes on, and the ambient bounce off the floor.
Night gets a soft moon so the room is never black.

The cat notices too — it's crepuscular, so it's liveliest around dawn and dusk
and sleeps through the middle of the day and the small hours.

### The cat decides for itself

`CatBrain` scores every activity it could be doing against eight needs (food,
water, rest, bladder, company, play, grooming, curiosity), the time of day, its
personality, and what it did recently, then picks a winner with a little noise so
no two days are the same. It walks there — a real navigation step with a
lateral-sequence walk, a trot, and a bound — jumps onto the window sill or the
cat tree, and performs the activity. Opening the app at a random moment should
show you something different each time.

### Everything is generated

There are no art assets. The cat's body is a lofted mesh whose cross-sections are
driven by the appearance parameters; the coat is drawn with Core Graphics
(tabby stripes that thin over the belly, rosettes, colourpoint gradients, calico
patches, per-hair ticking); the eyes are radial-fibre iris textures with a slit,
oval or round pupil; the legs are solved with two-bone IK so the paws stay
planted. The room — tatami, shoji, futon, tansu, cat tree, feeder, fountain,
litter box, paper lantern — is built the same way.

### Petting is a negotiation, and it is felt

Swipe on the cat when it is within reach. Head, cheek and chin are welcome; the
back is fine; the belly and tail are a gamble. Contentment builds a purr — both a
synthesised one and a matching haptic pulse under your fingers — while
overstimulation builds a tail flick, then pinned ears, then a hiss, a yowl, a
sharp haptic warning, and a cat that leaves. How long that takes depends on the
Patience and Cuddliness sliders you set when you made it.

### Notifications

When the app goes to the background it projects each need forward at its current
drain rate and schedules the moments worth interrupting you for: the cat is
lonely, wants to play, is eating, is at the fountain, found a sun patch, or has
left you something in the litter box. Plus a few for flavour. The schedule is
rebuilt from scratch every time, capped at twelve, and spaced at least 45 minutes
apart.

### While you were away

Closing the app doesn't pause the cat. `OfflineSimulator` replays up to 72 hours
in fifteen-minute slices, letting the cat feed itself, drink, use the litter box
and sleep, then tells you what happened when you come back. This runs both on a
cold launch and when the app returns from the background, so an afternoon away is
an afternoon away either way.

## Verifying it

Xcode is the only way to build the real app, but most of what can actually be
wrong in it is plain Swift. `Tools/linux-verify/verify.sh` compiles the whole
project against hand-written stand-ins for the Apple frameworks and runs it,
on any machine with a Swift toolchain:

```sh
./Tools/linux-verify/verify.sh              # ~13M assertions across 15 areas
./Tools/linux-verify/verify.sh --profile    # simulate whole days, report the results
```

The assertions cover the solar clock, mesh winding and normals, every breed and
every slider extreme through the rig builder, twenty poses through the animator
(including that the look-at solver settles rather than drifts), every personality
archetype through four simulated hours of the brain, the petting and
overstimulation cycle, the wand, treats, consumables, offline catch-up, resuming
from the background, the save file, and the whole room and lighting across a day.

The profile is the tuning tool. A healthy cat spends 40–55% of the day asleep,
touches around 25 distinct activities, vocalises roughly every ten minutes, and
gets through most of a week on one hopper of food. That is what the numbers in
`CatNeeds`, `CatActivity` and `CatBrain.score` were tuned against.

What this does not prove: the stand-ins encode our belief about Apple's APIs
rather than the APIs themselves, and rendering, audio and touch are all no-ops.
A green run means the logic is sound and the code compiles; it does not replace
building in Xcode once. See `Tools/linux-verify/README.md`.
