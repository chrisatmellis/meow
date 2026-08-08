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

Or from the command line:

```sh
./Tools/xcode-build.sh            # simulator build, no signing needed
./Tools/xcode-build.sh device     # device build, needs a signing team
```

It prints a compact diagnostic report rather than the usual wall of xcodebuild
output, and keeps the full log for when you need it.

For a device build, set your team once: select the Meow target → Signing &
Capabilities → Team. The bundle identifier is `com.drinkmellis.meowroom`; if you
are building under a different account, change it to your own namespace here and
in `Tools/xcode-screenshot.sh`, which installs and launches the app by that ID.

Notifications need a real device to be useful. The simulator will show the
permission prompt but background delivery is unreliable there.

Debug builds have a time-of-day slider in Settings, so you can see dawn, noon,
golden hour and night without waiting for them.

## Shipping a build

Run the `testflight` workflow from the Actions tab. It is manual-only on purpose:
it pushes a build to real testers, which should not follow from an ordinary
commit. It asks Apple what the last build number was, archives, signs, uploads,
and takes about ten minutes; Apple then takes another five to fifteen to process
the build before it appears in TestFlight.

Run `preflight` first if anything about the credentials has changed. It checks
the whole set on a free runner in about ten seconds and names whatever is wrong —
a mangled `.p8`, the key's own id pasted where the issuer id belongs, a p12 in an
encoding macOS cannot import, a missing app record. Each of those otherwise
appears twenty minutes into an archive as an error mentioning none of them.

`Tools/testflight.sh` does the same thing from a Mac, if you want a build without
waiting on a runner.

### Credentials

Five repository secrets, and nothing in the repository:

| Secret | What it is |
| --- | --- |
| `APP_STORE_CONNECT_KEY_P8` | The `.p8` file's contents, pasted whole, `BEGIN`/`END` lines included |
| `APP_STORE_CONNECT_KEY_ID` | The 10-character Key ID shown beside the key |
| `APP_STORE_CONNECT_ISSUER_ID` | The UUID at the top of the Integrations page — one per account, not per key |
| `APPLE_SIGNING_P12_BASE64` | The signing certificate and its private key, base64 |
| `APPLE_SIGNING_P12_PASSWORD` | The password that `.p12` was exported with |

The team id and bundle id are in the workflow rather than here. Neither is
secret: a team id is embedded in every app Apple ships.

`Tools/asc-rotate.py` mints the certificate, and does it without a Mac — the
private key is generated locally and Apple only ever sees a signing request, so
the Mac's usual job of running Keychain Access to produce a CSR falls to openssl.
The provisioning profile is fetched from App Store Connect at build time rather
than stored, so rotating the certificate needs nothing else changed.

These were committed in a `ci/` directory for a while, which was a deliberate
trade: the repository was private, and it removed the need for a Mac at a point
where that was the whole blocker. Going public ended the trade — a public
repository has a public history, so a committed key is a published key whatever
the current tree looks like — and the certificate and key that lived there have
been revoked.

### Two things that are not obvious

**The archive is unsigned, and the export step signs it.** Signing during the
archive fails outright on an account with no registered devices: `xcodebuild`
asks for an *iOS App Development* profile, and development profiles are built
from a device list. This account has none and needs none — the build is going to
TestFlight, not to a cable. App Store distribution profiles carry no device list
at all, so the export step can use one with nothing else set up.

**Signing is manual, from a committed `.p12`, and `-allowProvisioningUpdates` is
deliberately absent.** Automatic signing asks Apple's cloud signing service to
produce an identity, and this key is not permitted to use it — that is the
"Cloud signing permission error", and the "no profiles were found" that follows
is a symptom rather than a second problem. The certificate was minted from a
locally generated CSR so we hold its private key, and it is supplied directly.

One step genuinely cannot be automated: the App Store Connect app record.
Apple's API can create bundle ids but not app records, so that one is made in
the UI (Apps → ＋ → New App). `preflight` says so, and lists the records that do
exist, if it is missing.

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

### Surfaces have shape, not just colour

Every surface also carries a normal, roughness and occlusion map, generated from
a height field in `SurfaceMaps.swift` that is built alongside the colour texture
rather than derived from it. Deriving from the albedo would emboss the tabby
stripes, which are dark and completely flat.

The maps are authored by **angle**, not by depth. Depth on its own does not
predict how a surface looks — it only means something read against the width of
the features carrying it, and authoring millimetres directly produced wood at
0.5° of tilt and rope at 30° in the same pass, one invisible and one a cliff.
Each surface declares the RMS tilt it should read at; `HeightField` solves for
the slope that achieves it, and the physical depth that implies is derived and
bounded per material. When the two disagree it means the field's features are
the wrong size, which is a more useful thing to be told than a number being off.

Everything wraps. The height fields are periodic by construction, and the Core
Graphics generators draw anything near an edge again on the opposite side, so
the floor and walls have no repeat grid in them.

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

## A note on SceneKit

Apple soft-deprecated SceneKit at WWDC25 in favour of RealityKit. It is in
maintenance mode, not removed — existing apps keep working, and no removal date
has been announced. Because this project's deployment target is iOS 17.0, well
below the 26.0 deprecation, the build stays warning-free; you would only start
seeing deprecation warnings if you raised the target to 26.

SceneKit is still the right choice here: the entire game is procedural geometry
generated at runtime, which is exactly what `SCNGeometry` from raw vertex sources
is for. If you ever want to port, `CatAnimator` drives named joints and would
move across; `CatBuilder` and `RoomBuilder` are where the SceneKit-specific work
lives.

## Verifying it

Xcode is the only way to build the real app, but most of what can actually be
wrong in it is plain Swift. `Tools/linux-verify/verify.sh` compiles the whole
project against hand-written stand-ins for the Apple frameworks and runs it,
on any machine with a Swift toolchain:

```sh
./Tools/linux-verify/verify.sh              # ~13M assertions across 19 areas
./Tools/linux-verify/verify.sh --profile    # simulate whole days, report the results
./Tools/linux-verify/verify.sh --render ./r # software-rasterise the cat and the room
./Tools/linux-verify/verify.sh --maps ./m   # write every surface's material maps as PNGs
./Tools/linux-verify/verify.sh --budget     # print triangle counts against the budget
```

The assertions cover the solar clock, mesh winding and normals, every breed and
every slider extreme through the rig builder, twenty poses through the animator
(including that the look-at solver settles rather than drifts), every personality
archetype through four simulated hours of the brain, the petting and
overstimulation cycle, the wand, treats, consumables, offline catch-up, resuming
from the background, the save file, and the whole room and lighting across a day.

They also cover the material pipeline, which is deliberately pure Foundation so
that it can be checked without a graphics framework: that a surface rising along
+u tilts its normal toward −u (an inverted normal map does not look broken, it
looks like the light is on the wrong side); that every baked normal is unit
length and no steeper than 78°; that each surface hits the tilt it asked for and
implies a depth a real version of that material could have; that the noise tiles
exactly and the seam is no steeper than the middle of the tile; that meshes are
watertight; that the texture cache stays inside its byte budget and its pinned
room textures survive a 48-hour sky sweep; and that the room and every breed of
cat fit a triangle budget.

`--maps` is how the material work is looked at while CI is unavailable. It writes
each surface's height, normal, roughness and occlusion map tiled 2×2, so a map
that fails to tile announces itself as a cross through the middle of the image.

The profile is the tuning tool. A healthy cat spends 40–55% of the day asleep,
touches around 25 distinct activities, vocalises roughly every ten minutes, and
gets through most of a week on one hopper of food. That is what the numbers in
`CatNeeds`, `CatActivity` and `CatBrain.score` were tuned against.

### Looking at the real thing

`Tools/xcode-screenshot.sh` runs the app in a simulator and captures the room at
dawn, midday, golden hour and night, pinning the clock with a debug-only hook so
you don't have to wait for them. CI does the same on every push and uploads the
result.

Judging those by eye is unreliable — a window at luma 230 next to a dark wall
reads as pure white when nothing is clipping at all — so `Tools/shot-stats.py`
measures them instead:

```sh
./Tools/shot-stats.py stats screenshots/*.png   # mean luma, clipped/bright/dark %
./Tools/shot-stats.py map screenshots/05-night.png   # where the bright region is
```

Comparing `stats` across two commits is how the exposure work was checked, and
`map` is what identified the open half of the window — rather than the shoji
beside it — as the thing glowing at 10pm.

What this does not prove: the stand-ins encode our belief about Apple's APIs
rather than the APIs themselves, and rendering, audio and touch are all no-ops.
A green run means the logic is sound and the code compiles; it does not replace
building in Xcode once. See `Tools/linux-verify/README.md`.
