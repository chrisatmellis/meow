# Building the base mesh and its UVs

Step-by-step for the two longest items in `ASSETS.md`. Assumes you have never
opened Blender.

Do the cube spike first (`ASSETS.md` §7, step 1). Everything here is wasted if
Blender's USD export turns out to mangle your skeleton, and you want to find that
out in an afternoon rather than in month three.

---

## 0. Get something to retopologise over

The source USDZ is not in this repository — only the derived `cat.catmesh`. Look
for your original purchase first; it will have better normals and possibly a
higher-density variant.

Failing that, unpack the shipped mesh:

```sh
python3 Tools/usd/catmesh-to-obj.py MeowRoom/Resources/cat.catmesh /tmp/cat
```

That writes `/tmp/cat.obj` (1,976 verts, 2,804 tris, with the generated UVs),
`/tmp/cat-skel.obj` (one line per bone, so you can eyeball the joints) and
`/tmp/cat-skel.json` (parents, rest positions, role names).

It is low-poly and triangulated, which is the whole problem — but as a *shape
reference* to build over it is exactly as good as the original. Retopology only
needs a surface to snap to.

### Blender setup

1. **File ▸ Import ▸ Wavefront (.obj)**. In the import panel set **Up Axis: Y**,
   **Forward Axis: -Z**. The data is Y-up (height runs 0 → 0.30 in Y) and Blender
   is Z-up; get this wrong and your cat is on its side for the next two months.
2. Confirm the scale. **N** for the sidebar, Item tab: dimensions should read
   about **0.61 × 0.30 × 0.11 m**. Scene units are metres by default, so no unit
   change is needed.
3. Rename the import `cat_source`. In the Outliner, click the filter funnel and
   enable the cursor-arrow column, then switch it off for `cat_source` — this
   makes it unselectable so you stop grabbing it by accident.
4. Give it a flat mid-grey material and turn its viewport display down. You want
   to see your new topology against it, not admire it.

---

## 1. Retopology

### Which tool

| Option | Cost | Verdict |
|---|---|---|
| Poly Build + Shrinkwrap | free, built in | Works. Fiddly. |
| **RetopoFlow** | free (GPL, GitHub) | **Use this.** PolyStrips and Contours are built for exactly this job. |
| QuadRemesher | ~$60 | Automatic — and it will *not* give you the loops you need. |

On QuadRemesher specifically: auto-retopology produces beautifully uniform quads
that know nothing about where the animal bends. For a mesh that deforms, the loop
placement *is* the work. It is a reasonable way to spend an hour seeing what good
topology looks like; it is not a way to get one.

### Scene setup for retopo

Create a new empty mesh object, name it `cat_base`, and add two modifiers:

- **Shrinkwrap** → Target `cat_source`, Mode **Nearest Surface Point**, Offset
  `0.0005`. This keeps every vertex you draw pinned to the old surface, just
  outside it.
- **Mirror** → Axis X, **Clipping on**. You build the left half only. Do not
  apply this until the very end.

Then, in Object Properties ▸ Viewport Display, tick **In Front** so your new mesh
draws over the reference instead of z-fighting with it.

Finally, in the snapping dropdown (magnet icon): **Snap to Face**, with **Project
Individual Elements** on.

### Budget

Aim for **~7,000 quads**. Roughly:

| Region | Quads | Notes |
|---|---:|---|
| Head and face | 2,200 | Where the detail belongs |
| Mouth bag, tongue, teeth | 600 | |
| Ears ×2 | 400 | |
| Neck | 200 | |
| Torso | 1,200 | |
| Legs ×4 | 1,600 | |
| Paws and toes | 800 | |
| Tail | 400 | |

That is ~14k triangles against your 60,000 budget, leaving room for fur cards and
the mouth interior.

### Order of construction

**Torso → face → limbs → extremities.** The face has the tightest constraints and
is where beginners stall; do the torso first on easy geometry to learn the tools,
then slow right down for the head.

1. **Torso.** A tube. Draw one ring of ~24 quads around the ribcage, then extrude
   it forward to the neck and back to the hips — about 16 rings total. Keep the
   rings perpendicular to the spine.
2. **Face.** Build a ring of ~12 quads around the eye opening and a ring of ~12
   around the mouth opening, then connect them. This figure-of-eight is the
   standard basis of every animal face and everything else grows from it. Add two
   more concentric rings around each.
3. **Skull.** Join the face to the torso across the cheek and jaw, keeping loops
   running around the muzzle rather than across it.
4. **Legs.** Cylinders of 12 around, extruded down from the shoulder and hip.
5. **Paws, toes, ears, tail.**

### Loop rules that matter for a cat

- **Three concentric loops at every joint that bends** — shoulder, elbow, carpus,
  hip, stifle, hock. The middle loop sits exactly on the joint pivot. This is the
  single thing that stops the elbow collapsing when posed, and `CatSkin` uses
  plain linear-blend skinning with no corrective, so nothing downstream will save
  a bad loop.
- **Loops perpendicular to the bone**, not to the world.
- **Poles** — vertices with three or five edges — go where the surface does not
  deform: the top of the skull, the base of the ear, inside the mouth. Never on a
  joint.
- **Edge flow follows muscle**: around the shoulder, along the spine, radiating
  from the eye and mouth.
- The **scapula** needs its own loop running around the shoulder blade, because
  that joint is being added to the rig and it slides across the ribcage.

### The parts that don't exist yet

**Mouth bag.** From the lip loop, extrude *inward*. It needs to be a closed bag,
not a hole — 2–3 cm deep is plenty. Add a flattened tube for the tongue (skinned
to `tongue1`/`tongue2`) and four canines, eight quads each. Without this, opening
the jaw stretches skin, which is what happens today.

**Eye sockets.** Build the lid rings, then extrude inward and back to form an
actual recess. The eyeball stays a **separate sphere object** sitting inside the
socket — do not weld it to the head. The lids become part of the head surface,
skinned to the four lid joints, replacing the `cap(74°)` cones.

**Toes.** Four on the hind paws, five on the fore. Cheap, and very visible when
the cat kneads or stretches.

### Checks before you move on

Run all of these. In Edit mode:

| Check | How |
|---|---|
| Zero triangles and ngons | Select ▸ Select All by Trait ▸ Faces by Sides, set to 4, **Not Equal** |
| No doubled vertices | **M ▸ By Distance**, threshold `0.0001` |
| No non-manifold edges | Select ▸ Select All by Trait ▸ Non Manifold |
| Normals consistent | **Shift+N** (Recalculate Outside) |
| Quad count | Overlays ▸ Statistics |
| No pinching | Add a Subdivision modifier at level 1 and orbit |

Symmetry: apply the Mirror modifier **last**, and only once you are done.

---

## 2. UVs — two sets, and only one of them is yours

### Why two

`unwrap.py` does not produce an atlas. It produces a **coordinate system**:

- `u` = angle around whichever bone owns the vertex, wrapping 0–1. `u = 0.25` is
  the spine, `u = 0.75` the belly.
- `v` = distance along the bone chain × `v_per_metre`. **Unbounded.** Not
  normalised.
- **Parts overlap deliberately.** Both front legs land in the same UV region. The
  texture tiles.

That is not a mistake, it is the point: it is why a mackerel tabby's rings are
bands of constant `v` and run unbroken from shoulder to hip and on down the legs.
All 17 pattern generators in `TextureFactory` are written against it.

But it means **you cannot bake into it** — all four legs would bake into the same
texels — and it means hand-authoring it in Blender is fighting every tool Blender
has to reproduce something the algorithm already does correctly.

So:

| Set | Name | Made by | Used for |
|---|---|---|---|
| **UV0** | `pattern` | `unwrap.py`, at export | Runtime-painted coat, markings, material maps |
| **UV1** | `bake` | **You, in Blender** | Baked normal, AO, curvature, cavity, thickness |

### Authoring UV1 (the atlas)

This is ordinary game-art UV work, and it is the *only* unwrapping you do by hand.

1. In Edit mode, edge select. Mark seams with **Ctrl+E ▸ Mark Seam** along:
   - the belly midline, nose to tail base
   - a ring around each leg where it meets the body
   - the inner line of each leg, down to the paw
   - a ring around each ear base, and up the back of the ear
   - around the mouth opening, and around each eye socket
   - the underside of the tail
   - the back of the neck where it meets the skull
2. Select all (**A**), then **U ▸ Unwrap**, method **Angle Based**.
3. Open the UV Editor. Overlays ▸ **Display Stretch ▸ Area**. Anything strongly
   red or blue needs another seam. Iterate until it is mostly green.
4. **U ▸ Pack Islands**, margin `0.01`.
5. Give the face its own generous share of the space — it is what the player
   looks at. Scale the face island up before packing.
6. In Object Data Properties ▸ UV Maps, name it **`bake`**.

### UV0 (the generated set)

You do not author this. `unwrap.py` builds it from the skeleton after export, and
clean topology plus named joints will make its output far better than today
without touching the algorithm.

One exception. A cat's face is a **disc, not a tube**, and forcing it around a
cylinder is why the muzzle textures badly. The fix is a vertex group — call it
`face_flat` — painted over the face, which `unwrap.py` reads and handles with a
planar projection instead of the per-bone cylindrical one, blending back into the
cylindrical solution at the group's edge.

Creating the vertex group is your job and takes ten minutes. Teaching
`unwrap.py` to read it is a code change, listed below.

### Verifying UV0

The pipeline already measures this and then ignores it. `unwrap.py:254-275`
computes texels-per-metre p10 / median / p90 and prints them. Make it a hard gate
at **p90/p10 < 2.5** and you will catch a bad unwrap at export instead of on a
phone.

Then look at it:

```sh
python3 Tools/usd/preview.py
```

which renders the unwrap with a checker and a tabby. The checker squares should
be roughly square everywhere, and the tabby's rings should run unbroken from
shoulder to hip.

---

## 3. What has to change in the pipeline to accept this

Not your job before the modelling, but this is what the mesh is waiting on:

- **`MEOWCAT3`**: a second UV array, joint names, submeshes (mouth bag, teeth,
  claws need their own materials), and sparse morph deltas.
- **`unwrap.py`**: read the `face_flat` vertex group; accept an authored `st`
  primvar for UV1 and pass it through untouched; turn the stretch report into a
  gate.
- **`export-cat.py`**: read joint names instead of inferring roles from rest-pose
  geometry (`infer_roles`, 109 lines, currently required because the FBX
  conversion stripped the names). Fix `_origin_of` at line 247 while you are in
  there — it is an O(n²) search on exact tuple equality and can pick up the wrong
  skin weights when two vertices share a position.
- **`CatMeshAsset` / `CatShape` / `CatSkin`**: parse v3, apply breed morphs at
  build time, expression morphs per frame.
- **`Materials.swift`**: sample the baked maps through UV1 and the painted coat
  through UV0.
- **`CatBuilder`**: retire the primitive eyes, lids and cone eyelids once the base
  mesh carries real ones.

---

## 4. Order

1. Cube spike — prove USD export end to end.
2. Unpack `cat.catmesh` to OBJ, set up Blender.
3. Retopologise. **This is the long pole** — budget 6 weeks of evenings.
4. Mouth bag, eye sockets, toes.
5. Mesh checks (§1) — all of them.
6. UV1 atlas.
7. `face_flat` vertex group.
8. Hand off: rig, weight, sculpt, bake.

Steps 3–5 are where the work actually is. Steps 6–7 are about a day once the mesh
is clean.
