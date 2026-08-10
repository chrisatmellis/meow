# Cat asset work — task list

Working list for the cat asset overhaul described in `ASSETS.md` and `RETOPO.md`.
Unlike the CLI's own TodoWrite, this file is not session-scoped — it survives
restarts, teleports and new sessions because it's a tracked file. Check items
off in place and commit as you go, so a fresh session can `git log` this file
and see what changed.

Status as of 2026-08-10.

## BLOCKER: the re-exported mesh's skin weights point at the wrong joints

`MeowRoom/Resources/cat.catmesh` as re-exported in 33cfcdd does not render. The
cat draws as a fan of flat shards with the head roughly intact — the signature
of vertices being dragged toward bones they do not belong to. It is not a scale
problem (fixed separately, see below) and not the influence count.

Measured, per joint, as the distance from a joint to the weighted centroid of
the vertices bound to it:

| mesh | median | max | joints >0.10 m off |
| --- | --- | --- | --- |
| pre-re-export (36 joints, renders correctly) | 0.031 m | 0.085 m | 0 of 36 |
| re-export (55 joints) | 0.142 m | 0.409 m | 26 of 36 |

A cluster 0.41 m from its own joint on a cat 0.6 m long is not a near miss. The
skeleton itself is fine — one root, no bad parents, all 38 roles resolved, no
role claimed twice, L/R positions symmetric — so what is wrong is the mapping
from per-vertex joint indices into the new 55-joint ordering, not the ordering
itself.

Confirmed against the offline rasteriser (`verify.sh --render`, which draws the
same buffers the phone does):

- old mesh + current code -> a correct cat. So the loader, `CatShape` and
  `CatSkin` are not implicated; the asset is.
- new mesh + 12 influences, scale fixed, no pruning -> still shredded. So the
  influence cap is not implicated either.

Reverting the mesh is a real fallback but not a free one: the old skeleton fails
exactly nine assertions, all of them `the skeleton has a <role>` for the roles
e30a43e added (`foreToeL/R`, `hindToeL/R`, `tongueBase/Tip`, `clavicleL/R`,
`shoulder`), and `cat-walk.catanim` is baked against the 55-joint skeleton.

Fixing it properly needs the source `.blend`, which is not in the repository —
re-export with the joint indices remapped into the same ordering the bind
matrices are written in, and check this table before committing the result.

## Environment

- [x] Local session running on the user's own Windows machine (not the cloud
      sandbox), so there's no network-policy proxy to fight.
- [x] Blender MCP server wired up and connected. It's the **official** Blender
      Lab server (`projects.blender.org/lab/blender_mcp`), not the community
      `ahujasid/blender-mcp` package — those are different projects that happen
      to share a default port (9876). Setup:
      - cloned to `C:\Users\oru20\blender_mcp`
      - hit a real upstream bug: the repo's committed `mcp/uv.lock` pins
        `mcp==2.0.0`, and the real MCP SDK's 2.0 release removed
        `mcp.server.fastmcp`, which `blmcp/__init__.py` imports. Fixed locally
        with `uv add "mcp[cli]<2"` inside `C:\Users\oru20\blender_mcp\mcp`.
        This is an upstream problem, not something specific to this machine —
        if the clone is ever redone from scratch, redo this pin too.
      - registered with `claude mcp add blender -- <uv.exe> --directory
        C:\Users\oru20\blender_mcp\mcp run blender-mcp` (local scope, this
        machine only, not committed to the repo).
      - **MCP servers only load at session start.** After registering or
        changing the server, restart the session before expecting its tools
        to show up in `ToolSearch`.
      - **Hit a second bug (2026-08-10): drive-letter casing splits the
        project identity.** `~/.claude.json`'s `projects` map keys entries by
        the *literal* cwd string, and `C:/Users/oru20/Documents/meow/meow` vs
        `c:/Users/oru20/Documents/meow/meow` are tracked as two unrelated
        projects with independent `mcpServers`. The VS Code native extension
        session ran with a lowercase-`c:` cwd, whose project entry had *no*
        `mcpServers` at all — so `blender`'s tools never appeared in
        `ToolSearch`, even after a full extension reload — while a terminal
        `claude mcp list`/`claude mcp add` (git-bash, which normalizes to
        lowercase `c:` too but apparently still resolved differently) reported
        it "Connected" the whole time. Fixed by copying the working `blender`
        entry from the uppercase-`C:` project into the lowercase-`c:` one
        directly in `~/.claude.json`. **If Blender MCP tools go missing again
        after this**, suspect the same drive-letter split before re-debugging
        from scratch — check `~/.claude.json`'s `projects` keys for duplicate
        casing variants of this repo's path and diff their `mcpServers`.
- [x] Swift toolchain installed locally via `winget install --id
      Swift.Toolchain` (6.3.3, official, downloaded straight from
      download.swift.org — no proxy issue on the user's own network). Needs
      **both** dirs on `PATH` to run, not just the toolchain bin — the
      runtime DLLs are in a separate directory and `swift.exe`/`swiftc.exe`
      fail with an opaque "cannot open shared object file" error without it:
      ```
      C:\Users\oru20\AppData\Local\Programs\Swift\Toolchains\6.3.3+Asserts\usr\bin
      C:\Users\oru20\AppData\Local\Programs\Swift\Runtimes\6.3.3\usr\bin
      ```
      Neither is on PATH by default in a shell that was already open when
      winget installed it — export explicitly per session, or open a fresh
      shell after install.
- [ ] `Tools/linux-verify/verify.sh` does **not** run on native Windows Swift
      — confirmed, not just untested. It fails at the first `emit-module`
      with "unable to load standard library for target
      'x86_64-unknown-windows-msvc'", and even past that, the framework
      stand-ins are linked as `.so` shared libraries, which is a Unix ABI
      convention with no Windows equivalent — this isn't a flag or path fix,
      it's a different linking model. `python3` is also not on PATH by
      default on Windows (only `python`); worked around locally with a
      `python3 -> python` shim at `C:\Users\oru20\bin`, since editing the
      tracked script would diverge from what Linux CI runs.
      **Decision: install WSL2** rather than porting the harness to native
      Windows. Requires an elevated terminal (`wsl --install`, admin
      approval, likely a reboot) — has to be run by the user, not from here.
      Once WSL is up: install a Linux Swift toolchain inside it and run
      `verify.sh` there unmodified, matching what the harness was actually
      written for.
      **Status (2026-08-10): still blocked, one step further than before.**
      The user ran `wsl --install` and rebooted, which enabled the "Windows
      Subsystem for Linux" feature — but installing an actual Linux distro
      (`wsl --install -d Ubuntu`) now fails with
      `HCS_E_HYPERV_NOT_INSTALLED`, because **virtualization is disabled in
      this machine's BIOS/UEFI firmware** (confirmed via `systeminfo`:
      "Virtualization Enabled In Firmware: No"). This is a hardware/firmware
      setting — nothing an agent can flip; it needs the user to reboot into
      BIOS/UEFI setup (key varies by manufacturer: Del, F2, F10, F12...) and
      enable "Intel VT-x" / "AMD-V" / "SVM Mode" / "Virtualization", save,
      reboot. **User decision (2026-08-10): skipped for now** — not worth
      interrupting other work for. Once firmware virtualization is on, the
      remaining steps are just `wsl --install -d Ubuntu` (no longer blocked)
      then a Linux Swift toolchain install inside it.

      A native-Windows alternative was also tried and independently
      dead-ended (see the `pip install usd-core` entry below for the
      unrelated fix that *did* work that day) — `swiftc` on native Windows
      needs the VS Build Tools' C++ headers, and this machine's install is
      missing `stdnoreturn.h` (only 60 of the normal 100+ UCRT headers are
      present under `Windows Kits\10\include\10.0.19041.0\ucrt` — a
      partial/broken SDK component, fixable via "Visual Studio Installer" →
      Build Tools 2019 → Modify → ensure "Windows 10 SDK" is checked → Repair
      — also needs the user, also not done). Either path fixes the same
      underlying gap: no working Swift compiler on this machine yet.
      **Net effect: two Swift-touching commits this session
      (`33cfcdd`-era joint-role work and the tongue/toe/clavicle role
      additions) have not been compiled or run against `verify.sh`.** They're
      small, additive, and structurally similar to already-tested changes,
      but treat them as unverified until one of the two paths above is
      finished.
- [x] `pip install usd-core` run locally (2026-08-10) — `Tools/usd`'s scripts
      import `pxr` and it wasn't installed on this machine yet, per the note
      in `ASSETS.md`. User-site install (`pip install --user`, since the
      system site-packages isn't writeable); nothing else needed.

## Done: the leg-role bug (no Swift needed)

`cat.catmesh`'s role table had 8 of 16 leg-joint roles swapped between the
left-hind and right-front leg — a diagonal pair, from `infer_roles` guessing
wrong on two of the eight leg chains.

- [x] `Tools/usd/fix-leg-roles.py` written and applied. It doesn't hardcode
      which joints are wrong — it derives the body's own front/hind and
      left/right sign convention from the two leg chains that were *not*
      mislabelled (`shoulderL`, `hipR`), then checks the other two
      (`shoulderR`, `hipL`) against that convention and swaps only what fails.
      If a future export has no swap at all, it makes no changes.
- [x] Verified: dry-run on a copy first, then applied to the real file
      (`git diff --stat` confirms same byte count, i.e. only the 8 role
      entries changed), then re-parsed the patched file fresh and confirmed
      all four leg groups satisfy the convention. Second run is a no-op
      ("already match the convention"), confirming idempotence.
- [x] Commit the patched `cat.catmesh` alongside the script (done in
      `ba0221c`, same commit as the script).

## Next: re-export with joint names, via Blender MCP

Goal: stop `export-cat.py` guessing roles from rest-pose geometry
(`infer_roles`, ~109 lines) and read the 55 real bone names from the source
`.blend` instead. This also recovers geometry that already exists in the
mesh but previously had no role: the tongue, the toe joints, the clavicles,
and the shoulder-girdle spine joint. **Done** — see the checked-off items
below.

- [x] Use Blender MCP to open/inspect the source `.blend` (path on this
      machine: `C:\Users\oru20\Downloads\cat.blend`, already open in the
      connected Blender instance) and confirm the bone names and hierarchy
      match what `blend-inspect.py` reported: 55 bones, same names/parents
      (`Hips` root, `BN_Tail_01..04`, `Bip01_*` limbs/spine/clavicles,
      `BN_Thouge_01/02` tongue, `BN_Beard_L/R`, `BN_Ear_L/R`, toe `*_Finger0`).
- [x] Export USD from Blender with the armature and bone names intact (not via
      the FBX path that stripped them originally). Done via
      `bpy.ops.wm.usd_export` through the Blender MCP `execute_blender_code`
      tool, selecting only `Armature` + `U3DMesh` (`export_armatures=True,
      only_deform_bones=False` — all 55 bones are deform bones anyway —
      `export_uvmaps=True, export_animation=False, export_materials=False`).
      Wrote to the session scratchpad as `cat-blender-export.usdc` (not
      committed — it's a build input, `export-cat.py`'s job is to consume it,
      not to carry it). Verified with `pxr` (had to `pip install usd-core`
      locally first, per `ASSETS.md`'s note — not yet installed on this
      machine): joint paths are full real names
      (`Hips/Bip01_Pelvis/BN_Tail_01/...`), 55 joints, 1518 points,
      `skel:jointIndices`/`skel:jointWeights` primvars present (element size
      12), and a `st` UV primvar already exists (the source `uvset1`
      survived — a bonus, though `export-cat.py` still generates its own via
      `unwrap.py` for the per-bone cylindrical convention).
- [x] Update `Tools/usd/unwrap.py`'s `build()` to also return the joint
      **names** (it now returns `joint_names`, the last path segment of each
      USD skeleton joint). `Tools/usd/export-cat.py` maps role names directly
      from those via a new `NAME_TO_ROLE` table + `roles_from_names()`,
      falling back to `infer_roles` when fewer than `NAME_MATCH_THRESHOLD`
      (80%) of `ROLES` resolve by name — keeps the tool working for other
      users' unnamed exports.
- [x] Added roles for the tongue, toes, clavicles, and the shoulder-girdle
      spine joint (`BN_Thouge_01/02` -> `tongueBase/tongueTip`,
      `*_Finger0Nub`/`*_Toe0` -> `foreToe*`/`hindToe*`, `Bip01_*_Clavicle` ->
      `clavicle*`, `Bip01_Neck` -> `shoulder`) to `CatMeshAsset.Role` (Swift,
      appended after the existing 29 cases — append-only, per the enum's own
      doc comment) and the matching `ROLES`/`NAME_TO_ROLE` entries in
      `export-cat.py`, **in the same order** (the file format is positional:
      role index *i* in the binary is `Role(rawValue: i)`, so the Python list
      and the Swift enum must list new cases in lockstep). Re-ran the export;
      all 38/38 roles now resolve by name, all at plausible, left/right- and
      fore/hind-symmetric positions.

      Wired into `CatShape.region(of:)`: toes join `.paw` (same swelling/IK
      treatment as the paw they extend), tongue joins `.jaw`. Clavicles and
      `shoulder` fall through to the `.torso` default deliberately — nothing
      in `CatShape`/`CatAnimator` currently treats the shoulder girdle
      differently from the chest it sits on, and grepping confirmed neither
      `CatRig.swift` nor `CatSkin.swift` reference `CatMeshAsset.Role` at
      all (both are already joint-index-generic), so there was nothing
      further to "wire in" there for this step — extending `region()` was
      the only per-role logic that existed to extend. No exhaustive `switch`
      over `Role` exists anywhere, so appending cases can't break a build by
      making a switch non-exhaustive.

      **Not verified by compiling** — see the WSL2/native-Windows entries
      under Environment. This is a data-only, append-only, well-precedented
      change (same shape as the roles added in the previous step, which
      *did* get end-to-end tested through the Python pipeline), and
      `roles[i] = -1` for any role a skeleton lacks was already exercised
      by the pre-existing 29-role table, but flag it for extra scrutiny the
      first time a Swift toolchain is available here.
      **New environment finding (2026-08-10):** tried to unblock verification
      by pointing native Windows `swiftc` at the installed VS 2019
      BuildTools (`vswhere.exe` -> `VsDevCmd.bat` -> `INCLUDE`/`LIB`) instead
      of waiting on WSL2. Got past the earlier "unable to load standard
      library for target x86_64-unknown-windows-msvc" error, but hit a
      different, more fundamental one: `stdnoreturn.h` (a C11 header
      `ucrt.modulemap` needs to build `SwiftOverlayShims`) does not exist
      anywhere under either the MSVC toolset's `include` dir or the Windows
      10 SDK's — confirmed by `find`, not just a bad `INCLUDE` path. This
      looks like a genuinely incomplete/minimal BuildTools install, not
      something fixable by env vars alone. Doesn't change the WSL2 decision;
      recorded so a future session doesn't re-spend the time reaching the
      same dead end.
- [x] Re-ran `export-cat.py` and `unwrap.py` against the new Blender export
      (`cat-blender-export.usdc` in the session scratchpad — not committed,
      see above), diffed against the current `cat.catmesh`, sanity-checked
      with `Tools/usd/preview.py`, and **replaced the shipped
      `MeowRoom/Resources/cat.catmesh`** with the result. Header comparison
      (`MEOWCAT2`, same 29-entry role table, same struct layout — a
      data-only change, no format change):
      | | old (FBX path) | new (named Blender export) |
      |---|---|---|
      | vertices (pre/post seam-split) | ? / 1976 | 1518 / 1694 |
      | triangles | 2804 | 2798 |
      | joints | 36 | 55 |
      | influences/vertex | 4 | 12 |

      Notes on the diffs, so a future session doesn't mistake either for a
      regression:
      - **Triangle count (2804 -> 2798):** the new count exactly matches the
        source `.blend` mesh's own polygon count (checked directly in
        Blender: 2798 triangles, no ngons/quads). The old FBX-path number was
        the one that didn't match the source — likely a triangulation
        artifact of that conversion, not a Blender-export bug.
      - **Influences per vertex (4 -> 12):** also matches the source directly
        — Blender's vertex groups genuinely go up to 12 per vertex (checked:
        343 verts have 1, tapering up to 4 verts with 12), and the old
        4-influence cap was the FBX path silently discarding real weight
        data, not a size optimisation worth keeping. `CatMeshAsset.swift`
        reads `influencesPerVertex` from the file header rather than
        assuming 4, so nothing downstream needed to change. File size grew
        (~296 KB vs the doc comment's stale "141 KB" figure) accordingly;
        worth revisiting only if load time or memory actually becomes a
        problem, not preemptively.
      - Texel density (p10/median/p90 0.02/0.04/0.06) and the `uv-tabby.png`
        / `uv-checker.png` previews both look right: stripes ring the body
        cleanly, checker squares stay roughly square, no seam collapse.

## Prototype tradeoff: real coat texture instead of procedural, while retopo is pending

Decision (2026-08-10): rather than wait for retopology, use the source
`.blend`'s own hand-painted coat for a prototype — same low-poly mesh, but
real painted fur instead of `TextureFactory`'s procedural approximation.
Traded away deliberately: per-cat recoloring/breed patterns (every cat looks
like this one cat) until the mesh work catches up and a second UV set can
carry both. Baked animation clips were considered too and initially set aside
as new infrastructure rather than a shortcut — **revisited below** once the
user confirmed the procedural walk specifically was the thing that looked
rushed, which is exactly the condition under which this was worth doing.

- [x] Found the mesh's two UV sets in the `.blend`: `uvset1` (active/render,
      mapped to a real painted image, `cat texture.jpg`, 1024², packed into
      the file) and an unused `uvset2` (presumably meant for a future bake
      pass, matching the `MEOWCAT3` "second UV array" plan). Also found
      leftover, *unused* image references to a commercial rig library
      ("Truebone Z-OO" lion rig/textures) — not part of our cat's material,
      just orphaned data — that explain why the source animation looks
      smoother than the procedural one: this skeleton was likely built by
      retargeting onto a professional animal-rig template.
- [x] Extracted `cat texture.jpg` (`bpy.data.images[...].save()` via Blender
      MCP) to `MeowRoom/Resources/cat-coat.jpg`. It's a real painted/projected
      atlas (visible face, eye, mouth interior, paw pads, ears, whiskers), not
      a procedural material — confirmed by inspecting the image directly.
- [x] Taught the export pipeline to carry a mesh's own UV seams through
      instead of always generating `unwrap.py`'s cylindrical ones:
      - `unwrap.py`'s `build()` now also reads the `st` primvar (the
        USD/Blender convention for a mesh's active UV set) as flattened
        per-face-corner values, plus a new `corners` list running parallel to
        `tris` (the flat face-corner index for each triangle vertex — the only
        way to look up a per-corner, not per-vertex, attribute).
      - New `split_by_source_uv()`, a generalization of the existing
        `split_seam()`: instead of guessing a seam from where a cylindrical
        `u` wraps past 1.0, it splits a vertex wherever the mesh's *own*
        authored UVs actually differ face-to-face — correct for any UV
        layout, not just one cylindrical wrap.
      - `export-cat.py --uvs=source` uses this path instead of
        `unwrap()`/`split_seam()`; default behaviour (no flag) is unchanged,
        so nothing about the previous two commits' output changed.
      - Result: 1518 -> 1785 vertices (more than the cylindrical unwrap's 1694
        — a hand-authored atlas has more islands/seams), still 2798 triangles,
        still 38/38 roles. `git diff --stat` on `cat.catmesh` shows only the
        vertex/UV/skin-weight arrays changed size accordingly.
- [x] Verified visually **before touching any Swift**: wrote a throwaway
      script (session scratchpad, not committed) that runs the same
      `split_by_source_uv` path and rasterises the mesh sampling the real
      `cat-coat.jpg` by UV, same rasteriser as `preview.py`. Front and side
      renders both show correctly-placed markings, eye color, open mouth and
      paw pads, no seam smearing or flipped islands. (One gotcha worth
      remembering: USD/Blender's V=0 is the bottom of the image, an image
      library's row 0 is the top — the preview script flips V on sample;
      `Materials.swift`/RealityKit's own V convention should be checked the
      same way once this can actually be seen running, not assumed.)
      Replaced the shipped `cat.catmesh` with the `--uvs=source` export.
- [x] Wired into Swift: `TextureFactory.catCoatBaked` loads
      `cat-coat.jpg` from the bundle (nil if absent). `Materials.catFur`
      prefers it over `TextureFactory.catCoat`/`catCoatPreview` when present,
      and skips `catCoatMaps` (no baked normal/roughness/occlusion maps exist
      for this texture yet — that's the later high-poly bake pass) in favour
      of a flat roughness scalar. Falls back to the full procedural path
      automatically if `cat-coat.jpg` is ever removed from the bundle — no
      separate flag to keep in sync. `furShell`'s use of `catCoatPreview` for
      the long-hair silhouette alpha mask was deliberately left alone: a
      photo atlas doesn't tile and isn't the right thing there regardless.
      **Not verified by compiling** — same WSL2/firmware-virtualization
      blocker as the joint-role work above. This change is a larger, more
      structural diff than that one (new bundled binary asset, a new public
      `TextureFactory` entry point, a conditional in `catFur`), so give it
      real scrutiny — ideally an actual run in Xcode, not just a compile —
      the first time either becomes available. Specific things that can't be
      confirmed without seeing it rendered: whether RealityKit's V convention
      needs the same flip the preview script needed, and whether JPEG
      artifacting at 1024² reads as acceptable up close on-screen (it looked
      fine in a flat-shaded software rasterizer preview, which is not the
      same as the game's actual lit PBR material).

## Prototype tradeoff: baked walk-cycle playback for legs, procedural for everything else

Decision (2026-08-10): the user confirmed the procedural leg IK specifically
reads as rushed next to the source `.blend`'s own motion, so built playback
for real, is not a shortcut but is worth the cost. Scope was deliberately
narrowed twice, both to keep this reviewable without a working compiler on
this machine (see Environment) and because the source data itself only
supports a narrow scope cleanly:

- **Only one of the `.blend`'s five action entries is actually usable.** The
  three "SlowWalk" variants reference bone names (`BN_Eyebrow_L`, `BN_Fur_01`,
  `Saddle`, `Handle`, `C_ctrl`, ...) that don't exist anywhere in this
  skeleton — leftovers from a richer/different rig version, not something to
  retarget. A second "Walk" variant is a near-miss (31/32 bones match). The
  one clean fit — 44/44 bones match by name, and it's the action already
  assigned active on the Armature — is
  `Armature|Armature|Armature|Walk|Walk:BaseAnimation`, 90 frames at 30fps
  (3s), lateral-sequence gait. Its Hips motion is a small in-place bob
  (~0.02-0.1 units of oscillation), not a room-crossing drift, so it loops
  without needing separate root-motion handling.
- **Only legs + hips are clip-driven, not the whole 44-bone action.** Spine,
  tail and ear motion the clip also carries were deliberately dropped at
  export time (`export-anim.py`'s default `--joints` filter, *not* a Swift
  conditional) — driving those from the clip would fight the procedural
  systems already handling them well (look-at, idle tail sway, ear twitch)
  for no benefit, since legs were the specific complaint. This also means
  `CatWalkClip`'s Swift consumer never has to make that judgment call itself:
  it just applies whatever the file contains.

New tool: `Tools/usd/export-anim.py <in.usdz|usdc> <out.catanim>` (`--joints=all`
to keep everything instead of the legs+hips default).

- [x] Identified the one usable action (above) via Blender MCP — checked each
      action's animated bone names against the armature's real names directly
      (`arm.data.bones`), not by name pattern-matching alone.
- [x] Re-exported from Blender with `export_animation=True`, scene frame range
      set to 1-90 to match the action, same `Armature`+`U3DMesh` selection as
      the earlier joint-name export. Produces a `SkelAnimation` prim with 90
      time samples, one 55-entry rotation/translation/scale array per sample.
- [x] **Critical correctness issue caught before it reached Swift**: a
      `SkelAnimation`'s rotations are local-to-parent *in the source file's
      own bind pose* — but `CatShape`/`CatBuilder` deliberately discard rest
      *rotations* when building the rig (a joint entity starts at identity;
      see `CatShape.swift`'s own doc comment about a past bug where applying
      a file's raw bind-relative rotations "folded the skeleton into a heap"
      because every bone's rest orientation sits on a different,
      exporter-chosen axis). Writing the clip's raw rotations straight onto a
      `CatMeshAsset` joint would have been exactly that bug again. Fixed by
      re-expressing every frame's rotation as a delta from *this skeleton's
      own* bind-local rotation (`delta = restLocal.inverse() * frameLocal`,
      both computed with `pxr`'s own `Gf.Matrix4d`/`Gf.Quatd` operators to
      avoid hand-deriving row/column-convention matrix math a second time).
      Verified three independent ways before trusting it: (1) a round-trip
      check that `restLocal * delta` reproduces `frameLocal` exactly: passed;
      (2) delta rotation *angles* are small and physically sensible for a
      walking gait (thigh 5-36°, calf 0-27°, paw/toe up to ~100° through the
      swing phase) rather than huge or nonsensical: confirmed; (3) read back
      the actual written `.catanim` binary (not the intermediate Python
      values) and checked every quaternion is unit-length, no NaNs, and no
      frame-to-frame jump exceeds ~11° across all 90 frames at 30fps: passed,
      zero NaNs, max jump 10.7°.
      **This is the one part of this whole session most worth an actual human
      look once Xcode is available** — it's a derivation, not a transcription,
      and the verification above is numerical self-consistency, not a picture
      of a cat walking.
- [x] `export-anim.py`'s joint filter defaults to hips + each leg's
      hip/knee/ankle/paw chain (17 of 55 joints), verified to produce exactly
      the same 17 raw joint indices already established by `export-cat.py`'s
      independent role-resolution (`hips`=0, `hindHip/Knee/Ankle/PawL/R`,
      `foreHip/Knee/Ankle/PawL/R`) — two independently-computed paths agreeing
      on indices is good evidence neither has a joint-order bug.
      `MeowRoom/Resources/cat-walk.catanim`, 42.9 KB.
- [x] New `MeowRoom/Scene/CatWalkClip.swift`: loads the binary (same
      hand-rolled little-endian reader pattern as `CatMeshAsset`), samples at
      an arbitrary time with slerp/lerp between the two nearest baked frames
      and loops. Mirrors `TextureFactory.catCoatBaked`'s graceful-absence
      design — `try?` on load, nil is a valid, silent state.
- [x] Wired into `CatAnimator.solveLegs`: when `motion.pose == .walking` (the
      one gait the clip's lateral-sequence pattern actually matches — trot,
      run and pounce keep the existing IK, which already has the right foot
      pattern for each) and the cat is actually moving, sample the clip at
      `gait * clip.duration` — reusing the *existing* speed-scaled `gait`
      accumulator rather than wall-clock time, so clip playback speeds up and
      slows down with the cat exactly like the procedural stride already did
      — and write only `.orientation` per driven joint, then return early
      (skipping the procedural leg loop entirely for that frame). **Position
      is deliberately not applied even though the clip has it** — every other
      joint write in this file is rotation-only, joint *positions* are fixed
      once at build time (`CatShape.Shaped`'s "a joint is a point" contract),
      and the procedural fallback path never writes `.position` either — so a
      joint left at a clip-sampled translation would stay there, silently
      wrong, for as long as the cat then stood still or trotted afterward.
      The existing sine-wave body bob supplies vertical bounce on the same
      `gait` phase instead.
- [x] Known, accepted limitation, not fixed here: switching between
      clip-driven and IK-driven legs at the `moving`/`.walking` threshold is
      an instant swap, not a crossfade, so there may be a visible pop at that
      exact transition. Matches the existing code's own threshold-based
      gating style (`if moving { ... }` already works this way for the
      procedural stride), so not a new category of rough edge — but worth
      knowing about before spending time hunting for why a walk-start looks
      slightly off.
- [x] **Not verified by compiling** — same WSL2/firmware-virtualization
      blocker as the rest of this session's Swift work. Unlike the texture
      change, there is no way to sanity-check this one *without* running it
      (a rotation delta being "smooth and small" doesn't prove it's applied
      about the right axis in RealityKit's actual composition — see the
      correctness-issue note above). Treat this as the least-trusted change
      in this session until it has actually been seen animating a cat.

## Tier 0 fixes from ASSETS.md (small, independent, no modelling)

- [ ] Drive `dilation` in `Materials.swift:115` from `WorldClock`'s solar
      elevation instead of the hard-coded `0.5`.
- [ ] Wire up `shoulderHeight`, `tailRingCount`, `earTufts`, `pawPadColor` —
      sliders and breed presets exist, nothing consumes them.
- [ ] Make `unwrap.py`'s stretch report (`texels_per_metre_p90/p10`) a hard
      gate instead of just printed output.

## Longer-term (see ASSETS.md / RETOPO.md for full detail)

- [ ] Retopology in Blender via MCP — ~7,000 quads, mouth bag rebuilt at
      usable density, real eye sockets, separated toes. This is the long pole;
      budget weeks not days even with MCP assistance.
- [ ] Author the UV1 bake atlas (or confirm the source `.blend`'s `uvset1` can
      be reused/adapted — it already scores well on stretch).
- [ ] `MEOWCAT3` format: second UV array, joint names, submeshes, sparse morph
      deltas. Needs Swift changes in `CatMeshAsset.swift`.
- [ ] Breed/age/expression shape targets (~33 morphs total).
- [ ] High-poly sculpt and bake pass for normal/AO/curvature/thickness maps.

## Notes for picking this back up cold

- The bought `.blend` is the real source of the shipped mesh (100× scale
  match, identical vertex/triangle counts) — always retopologise/re-export
  from it, not from `cat.catmesh`.
- `Tools/usd/blend-inspect.py` reads `.blend` files without needing Blender
  installed — useful for quick checks from a plain Python shell.
- `Tools/usd/catmesh-to-obj.py` unpacks the shipped mesh back to OBJ, for
  when a shrinkwrap reference is needed and the `.blend` isn't handy.
