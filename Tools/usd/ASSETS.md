# Making the cat look good: an asset production plan

## Context

The cat is the only art asset in Meow, and it is the weakest thing in the game. Everything
else — the room, the coat patterns, the material maps, the lighting — is generated in Swift
and has been tuned hard. The cat is a bought FBX→USDZ conversion pushed through
`Tools/usd/export-cat.py` once, by hand, and it has never been improved.

What ships today, measured from `MeowRoom/Resources/cat.catmesh`:

| | Current | Notes |
|---|---|---|
| Triangles (body mesh) | **2,804** | Budget assertion allows **60,000** (`Harness/main.swift:2378`) |
| Vertices | 1,976 | |
| Joints | 36 (29 named roles) | Of which 2 are dead whisker cards |
| Topology | Triangulated | Fan-triangulated at import (`unwrap.py:99`) |
| UVs | Generated, per-bone cylindrical | Not authored; stretch measured but never gated |
| Blendshapes | **None** | Pipeline has no support anywhere |
| Baked maps | **None** | All relief comes from procedural fur-stroke height fields |
| Mouth | **None** | Head is a closed surface; opening the jaw stretches skin |

The assembled cat clears the harness's `tris > 3_000` floor once the generated eyes, lids,
whiskers, collar and fur shells are added — but the body itself, the thing every pattern is
painted on and every joint deforms, is 2,804 triangles against an allowance of 60,000. The
lantern's seven wire ribs alone once cost 16,128 (`Tessellation.swift:12`). That imbalance is
the headline.

This document is the production plan: what assets to make, how many cat variants are
actually needed, what software to learn, and what code has to change to receive it.

---

## 1. Why it doesn't look good — five causes, ranked by payoff per hour

**1. Density and topology.** 2,804 triangles for a character that fills the screen in the
character creator. Worse than the count: it is *triangle soup*, so it can't be cleanly
subdivided (Catmull–Clark on triangles pinches), can't be edge-loop-selected, and morph
targets on it produce shading artifacts. There are no deformation loops at the shoulder,
elbow, hip, stifle or hock, and `CatSkin` does plain linear-blend skinning with no
corrective — so those joints collapse when posed.

**2. Every breed is the same skull.** `CatShape.boneScales` (`:341-342`) scales the head
joint uniformly and the jaw by muzzle length; `inflate` (`:522-523`) swells the head
radially. That is the whole of breed head variation. A Persian's face is *concave* — the
nose sits between the eyes and there is no muzzle projection. A Siamese is a straight
profile wedge. Neither is reachable by inflating a moggy skull. **This is why 18 breeds
read as one cat with different fur colours,** and it is the highest-value new asset.

**3. The face is primitives stuck on a closed head.** Eyes are `sphere(segments: 16)`
intersecting the skull; lids are `cap(74°)` and `cap(66°)` cones (`CatBuilder.swift:233-252`).
No socket, no brow, no inner canthus, no nose bridge, no lip line, no mouth interior. The
eyes are the first thing anyone looks at.

**4. No baked anatomy.** Every normal/roughness/occlusion map comes from a height field of
*fur strokes* (`SurfaceMaps.catCoat:404`). Nothing in the pipeline knows where the
cheekbone, scapula, brow or ear cartilage is. One baked normal + AO + curvature set from a
high-poly sculpt adds more perceived detail than doubling the poly count — and it composites
under the runtime-painted albedo, so "everything is generated" stays true for colour.

**5. Fur is two offset shells.** `offsetAlongNormals` at 4–13 mm, capped at 2 layers
(`RenderQuality.maxFurShells`). A Maine Coon's ruff, britches and tail plume are *silhouette*,
and silhouette is geometry. Today `tailFluff` is radial inflation, so a plumed tail is a fat
cylinder.

Secondary but cheap: the rig has one `spine` entity (`CatRig.swift:45`), 4 tail joints, and
no scapula — a sliding shoulder blade is most of why a cat's walk looks like a cat's.

---

## 2. Tier 0 — visible wins with no new assets

Do these first; they're days, not months, and they raise the floor while the modelling
work is underway.

- **Drive pupil dilation from `WorldClock`.** `TextureFactory.iris` takes a `dilation`
  parameter that is hard-coded to `0.5` at both call sites (`Materials.swift:115`,
  `Harness/main.swift:800`). The machinery, including the cache key, already exists. A cat
  whose pupils blow open at dusk in a game built entirely around real solar time is the
  single best "alive" signal available for near-zero cost.
- **Wire up the four dead sliders.** `shoulderHeight`, `tailRingCount`, `earTufts` and
  `pawPadColor` have UI controls and breed presets but no consumer. `tailRingCount` even has
  a Bengal preset (`BreedPresets.swift:87`) and a slider (`CharacterCreatorView.swift:210`)
  and `TextureFactory` never reads it.
- **Honour `EarShape.curled` and `TailShape.bobbed`/`.kinked` properly** — currently partial.
- **Gate UV stretch.** `unwrap.py:254-275` computes texels/metre p10/median/p90 and prints
  it. Make it a hard failure above, say, p90/p10 > 2.5.
- **Split spine into a chain in `CatRig`.** The file already carries `spineBase`, `spineMid`
  and `chest` as distinct roles; `CatRig` collapses them into one `spine` Entity. Exposing
  all three lets the cat arch and curl with no asset change at all.

---

## 3. The asset list

### A. `cat_base.blend` — the retopologised base mesh

- **6,000–9,000 quads** (12–18k tris) at subdiv 0. Well inside the existing 60k budget.
- Concentric deformation loops: ×3 at shoulder, elbow, carpus, hip, stifle, hock; ×2 per
  tail segment; full loops at neck base, mid-neck, jaw hinge; radial loops ×3 around the
  eye, ×3 around the mouth, ×2 at the nostril, ×2 at the ear base.
- Poles kept out of deforming areas.
- **Symmetric across X** — morphs mirror, and the seam-split logic stays predictable.
- **A mouth bag**: inner lips, gums, tongue, four canines. Transforms yawning, meowing,
  hissing and grooming, none of which currently work.
- **Real eye sockets**, with lids as part of the same surface skinned to lid joints —
  replacing the cone caps.
- **Separated toes** (4 hind, 5 fore). Cheap in polys, very readable when the cat kneads.

### B. `cat_high.blend` — high-poly sculpt, for baking only

Skeletal landmarks: scapula, olecranon, iliac crest, faint ribs, cheekbone, brow, nose
bridge, ear cartilage ridges, pad separation, nose leather, claw sheaths. Two bake
variants minimum: **furred** and **hairless** (Sphynx wrinkles — better than the 900
procedural wrinkle strokes at `SurfaceMaps.swift:408-426`).

### C. UV layout — authored, honouring the existing convention

**Critical constraint:** all 17 coat-pattern generators in `TextureFactory.drawPattern` are
written against `unwrap.py`'s contract — *u runs once around the part, u=0.25 is the spine,
u=0.75 is the belly; v runs along the body, one repeat per torso length*
(`unwrap.py:12-19`). Do **not** author a conventional game UV layout and rewrite the
generators. Author a manual unwrap that *honours the same convention*: torso+neck as one
cylinder seamed on the belly midline, legs as cylinders seamed on the inner leg, tail
seamed underneath.

The one place the convention must break: **the face gets its own flat island**, placed in
the v-range the head occupies. A cat's face is a disc, not a tube, and forcing it round a
cylinder is why the muzzle textures badly today.

Payoff: far less stretch, a paintable face, and every existing Core Graphics generator
keeps working unchanged.

### D. The skeleton — ~60 joints, **named**

| Region | Joints | Current | Why |
|---|---|---|---|
| Spine | `hips, spine1–3, chest` (5) | 3 | Arch, curl, loaf, stretch |
| Neck | `neck1, neck2` (2) | 1 | |
| Head | `head, jaw, tongue1, tongue2` (4) | 2 | |
| Eyes | `eyeL/R` (2) | 0 | Skinned, not parented spheres |
| Lids | 4 | 0 | Blinking deforms the surface |
| Ears | `base/mid/tip` ×2 (6) | 2 | Flick, and a real fold crease |
| Whisker pads | 2 | 0 | Clearest emotional tell a cat has |
| Tail | 9 | **4** | 4 can't make an S-curve or a question-mark hook |
| Legs | `scapula, upper, lower, ankle, paw, toe` ×4 (24) | 16 | **Scapula is the big one** |

**Name them.** `export-cat.py:46-155` is 109 lines of heuristics inferring roles from rest-pose
geometry, with hard `SystemExit`s (`no spine leaving the root`, `never found a skull walking
forward from the pelvis`), because the FBX conversion stripped names to `n8`…`n49`. Named
joints demote all of that to a fallback path. Keep `CatShape`'s discarding of bind rotations
(`:285-296`) — the README explains at length why that must stay.

### E. Shape targets — **this is the answer to "how many cats"**

**One mesh. One skeleton. ~33 morphs. 4 coat layers.** The 18 breeds are *mixes*, exactly
as `BreedPresets` already mixes 73 scalars.

**Breed shape (18):**
`skull_brachy` (Persian/Exotic), `skull_wedge` (Siamese/Oriental), `skull_broad`
(British/Bombay), `skull_square` (Maine Coon/Norwegian), `jowls`, `muzzle_short`,
`muzzle_long`, `brow_heavy`, `eye_round`, `eye_oriental`, `eye_large`, `ear_large_wide`
(Sphynx/Oriental), `ear_small`, `ear_fold` (a crease, not the current rotation),
`ear_curl` (the enum case that currently does nothing), `body_cobby`, `body_oriental`,
`body_substantial`. `semiCobby` stays the base.

**Age and condition (4):** `kitten`, `senior`, `chonk`, `skinny`.

> `lifeStage` feeds exactly one thing in the whole codebase: `overallScale`, a uniform
> multiplier of 0.62 (`CatAppearance.swift:255` → `CatShape.swift:415-420`). Grep it — there
> are no other consumers. A kitten is the adult cat at 62%.
>
> The comment at `CatShape.swift:339-340` says *"A kitten's skull is nearly adult-sized on a
> small body, which is most of why kittens read as kittens"* — but the head scale term
> immediately below it takes `a.headRadius` only, and `headRadius` has no `lifeStage` input.
> The code states the right intent and then doesn't implement it.
>
> A kitten has a proportionally huge head and eyes, a short muzzle, stubby legs, a thin tail
> and oversized paws. A uniform scale reads as a doll. One morph fixes it — and this is
> probably the single most visible morph on the list.

**Expression (11)**, driven by `CatAnimator` rather than the creator: `blink_L`, `blink_R`,
`squint` (the slow-blink affection signal), `ears_back`, `ears_flat` (the pinned-ear stage of
overstimulation you already simulate), `mouth_open`, `hiss`, `flehmen`, `whiskers_forward`,
`whiskers_back`, `pant`.

**Coat geometry variants (4 mesh layers, not morphs):** `shorthair` (base only),
`longhair` (ruff + britches + tail plume + ear furnishings as alpha cards), `rex` (curl lives
entirely in the normal bake), `hairless` (wrinkle bake + exaggerated ears).

### F. Baked map set

Normal, AO, curvature, cavity, **thickness** (feeds the fake-SSS in `Translucency.swift` —
real SSS is iOS 26 and the app targets 18), and a **hair-flow map** so `drawFurDetail`'s comb
follows anatomy instead of value noise. 1024² to match the coat; 2048² for the face island.

---

## 4. Why morph targets are nearly free here

RealityKit's `BlendShapeWeightsComponent` is **irrelevant to this project**, because
`CatSkin` already does linear-blend skinning on the CPU (`CatSkin.swift:71`). A morph target
is therefore just a sparse `[(index, dPos, dNormal)]` array and a lerp.

- **Breed morphs apply once, at build time**, inside `CatShape.shape` before `reskin` —
  zero per-frame cost.
- **Expression morphs apply per frame** as a pre-pass in `CatSkin.apply`. At ~8k vertices
  that stays well under a millisecond against the 8 ms budget.

No new framework surface, no iOS 26 gate, and it remains fully checkable on Linux by the
existing harness.

---

## 5. Format and code changes: `MEOWCAT2` → `MEOWCAT3`

`CatMeshAsset.swift:99-197` is the only parser. Bump the magic, keep a v2 read path so
nothing breaks mid-migration, and append:

```
  jointNames    : u32 count, then per joint (u32 len, utf8 bytes)
  submeshes     : u32 count, then per submesh (u32 firstIndex, u32 indexCount, u16 materialId)
  morphs        : u32 count, then per morph
                    u32 nameLen, utf8 name
                    u32 deltaCount
                    deltaCount × (u32 vertexIndex, 3×f32 dPos, 3×f32 dNormal)
```

Sparse deltas because a skull morph touches maybe 800 of 8,000 vertices.

Files that change:

- `Tools/usd/export-cat.py` — read `UsdSkelBlendShape`, emit names/submeshes/morphs;
  demote `infer_roles` to a fallback; fix `_origin_of` (`:247`), which is an O(n²) linear
  search on exact tuple equality and can copy the wrong skin weights when two vertices share
  a position.
- `Tools/usd/unwrap.py` — accept an authored `st` primvar and skip generation; turn the
  stretch report into a gate.
- `MeowRoom/Scene/CatMeshAsset.swift` — v3 parse, `morphs`, `jointNames`, `submeshes`.
- `MeowRoom/Scene/CatShape.swift` — map appearance scalars onto morph weights; apply breed
  morphs before `reskin`.
- `MeowRoom/Scene/CatSkin.swift` — per-frame expression morph pre-pass.
- `MeowRoom/Scene/CatRig.swift` / `CatAnimator.swift` — spine chain, scapula, 9-joint tail
  with spring follow-through, lid joints, whisker pads.
- `MeowRoom/Scene/CatBuilder.swift` — retire the primitive eyes/lids/mouth once the base
  mesh carries them; keep whiskers and collar generated.
- `Tools/linux-verify/Harness/main.swift` — assert every breed's morph mix is in range, that
  morph deltas don't tear the surface, and raise the density floor from 1,000 vertices.

---

## 6. Software — what to learn

**Blender 5.2 LTS (free) does about 90% of this job**, and it is the only tool that is
genuinely required. You need these parts of it, in this order:

| Task | Blender feature |
|---|---|
| Retopology over the bought mesh | Poly Build + Shrinkwrap (free addon: RetopoFlow) |
| High-poly sculpt | Sculpt mode, multires + dyntopo |
| UV layout | Mark Seams / Unwrap, with the UV stretch overlay on |
| Rigging | **Rigify** ships a quadruped metarig |
| Weight painting | Longest to learn, matters most |
| Shape keys | These *are* the morph targets |
| Baking | Cycles bake, high→low, normal + AO |
| Export | `File ▸ Export ▸ USD`, with Armatures and Shape Keys enabled |

**Worth paying for:**

- **Auto-Rig Pro (~$40)** — proper 3-bone IK for digitigrade quadrupeds. Rigify's quadruped
  metarig works, but ARP's is built for exactly this and will save you real pain as a
  first-timer. Best value on the list.
- **Nomad Sculpt (~$20, iPad)** — sculpting with a mouse is miserable. Cheapest way to get a
  stylus in the loop. Exports OBJ straight into Blender.
- **Marmoset Toolbag (~$300)** — cleaner, faster bakes than Cycles and the best real-time
  look-dev viewport available. Optional; Blender's baker is fine.

**Deliberately not on the list:**

- **Substance 3D Painter** — everything is painted at runtime in Core Graphics, and that is
  the project's identity. Buying Painter would tempt you to abandon it. The one thing it's
  genuinely better at is the flow and thickness maps, and those can be painted in Blender's
  texture paint mode or derived from the sculpt.
- **ZBrush** — only if sculpting becomes the bottleneck. It won't be, at this scale.

**Validation tools (free):**

- **Reality Composer Pro** (ships with Xcode) — not for authoring. Drop the USDZ in and
  confirm the skeleton, joint names, blendshapes and materials survived export. Catches the
  "FBX conversion stripped the joint names" class of bug *before* it reaches `export-cat.py`.
- **`usdchecker` / `usdview`** from OpenUSD (`pip install usd-core` — `Tools/usd` already
  imports `pxr`).

---

## 7. Order of work

The classic failure mode is learning modelling for three months and discovering the topology
can't be rigged. So: **spike the pipeline first, with a garbage asset.**

1. **Prove the pipeline end to end (~1 week).** Make a cube in Blender. Rig it to three
   named bones. Add one shape key. Export USDZ. Run it through `export-cat.py`. Get it into
   the app. You will find out on day three — not month three — that Blender's USD export
   nests `SkelRoot` prims in a way that breaks binding, and that blendshapes need explicit
   enabling. This de-risks everything downstream.
2. **Re-rig the mesh you already own (~3 weeks).** Build the ~60-joint named skeleton and
   paint weights onto the *existing* bought geometry. Ship it. You get a visibly better cat
   with zero modelling, because the current rig has 4 tail joints and no scapula.
3. **Retopologise (~6 weeks).** The long pole, and the part with the least immediate reward —
   which is exactly why it comes after a shipped win.
4. **UVs, high-poly sculpt, bake (~3 weeks).**
5. **Shape targets (~5 weeks).** Where 18 breeds finally become 18 cats.
6. **Fur cards and expressions (ongoing).**

**Honest estimate for a complete beginner: 150–250 hours through step 5.** Steps 1 and 2
are about 40 of those and produce a real improvement on their own, so the early exit is a
good one if the appetite runs out.

Tier 0 (§2) and the format work (§5) run in parallel and don't block on any of this.

---

## 8. Verification

Everything below runs on Linux with no graphics framework, using the existing harness.

- `./Tools/linux-verify/verify.sh` — the ~13M assertions. Extend the modelled-cat section
  (`Harness/main.swift:1284-1700`) with: morph deltas finite and bounded, every breed's morph
  mix within range, skeleton has size and its bones have length (the `simd_quatf()` check
  that already exists), weights still sum to 1, no vertex left unweighted.
- `./Tools/linux-verify/verify.sh --render ./r` — software-rasterise the cat. This draws the
  *same buffers the phone draws*, so a picture here is a picture of what ships. Compare
  against `Tools/linux-verify/reference/cat-stand-side.png` before and after.
- `./Tools/linux-verify/verify.sh --budget` — triangle counts. The cat body will go from
  2,804 to ~15,000 against a 60,000 ceiling; confirm room + heaviest cat stays under 140,000.
- `./Tools/linux-verify/verify.sh --maps ./m` — every surface's material maps as tiled PNGs,
  to check the baked maps tile and don't seam.
- `python3 Tools/usd/preview.py` — renders the UV unwrap with a checker and a tabby, which is
  how you confirm an authored UV layout still honours the u=0.25-spine convention.
- `Tools/xcode-screenshot.sh` + `Tools/shot-stats.py stats` — on a Mac, to confirm the
  heavier mesh hasn't moved the exposure numbers (midday 94, golden hour 54, dawn 47,
  night 19.5).
- **Reality Composer Pro**, manually, on every export — skeleton, joint names, blendshapes.

## 9. Deliverable for this plan

Commit this document to the repo as `Tools/usd/ASSETS.md`, linked from the README's
"The cat" section, so the production plan lives next to the pipeline it describes.
