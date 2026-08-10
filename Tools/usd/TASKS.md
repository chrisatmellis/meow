# Cat asset work — task list

Working list for the cat asset overhaul described in `ASSETS.md` and `RETOPO.md`.
Unlike the CLI's own TodoWrite, this file is not session-scoped — it survives
restarts, teleports and new sessions because it's a tracked file. Check items
off in place and commit as you go, so a fresh session can `git log` this file
and see what changed.

Status as of 2026-08-10.

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
- [ ] Swift toolchain installed locally. Still missing as of the last check
      (`where swiftc` empty). Windows installer is at swift.org — no proxy
      issue here since this is the user's own network, unlike the cloud
      sandbox this work started in.
- [ ] Confirm `Tools/linux-verify/verify.sh` runs end to end once Swift is
      installed, as a baseline before making any Swift changes.

## Immediate: the leg-role bug (no Swift needed)

`cat.catmesh`'s role table has 8 of 16 leg-joint roles swapped between the
left-hind and right-front leg — a diagonal pair. Confirmed independently two
ways: the joint parent chain matches the source `.blend`'s bone order, and the
raw coordinates put `shoulderR`/`upperArmR`/`lowerArmR`/`pawR` at `x < 0`
(behind the hips), which is anatomically the hind leg. See the chat history
for the full table.

- [ ] Write a small Python patch script (`Tools/usd/fix-leg-roles.py` or
      similar) that rewrites the 8 role-table entries in `cat.catmesh` in
      place, matching the corrected mapping already worked out.
- [ ] Verify the patch in Python: re-read the role table and assert every leg
      role's joint has `x` sign matching `front`/`hind` and `z` sign matching
      `L`/`R`. This is the check that would have caught the original bug.
- [ ] Commit the patched `cat.catmesh` with a clear message explaining the bug
      it fixes.

## Next: re-export with joint names, via Blender MCP

Goal: stop `export-cat.py` guessing roles from rest-pose geometry
(`infer_roles`, ~109 lines) and read the 55 real bone names from the source
`.blend` instead. This also recovers geometry that already exists in the
mesh but currently has no role: the tongue (`BN_Thouge_01/02`), the toe
joints (`Finger0` ×2), the clavicles, and `Bip01_Spine1`.

- [ ] Use Blender MCP to open/inspect the source `.blend` (find its current
      path on this machine — it was uploaded earlier in this conversation)
      and confirm the bone names and hierarchy match what `blend-inspect.py`
      reported.
- [ ] Export USD from Blender with the armature and bone names intact (not via
      the FBX path that stripped them originally).
- [ ] Update `Tools/usd/export-cat.py` to read joint names from the USD
      skeleton directly, falling back to `infer_roles` only when names are
      absent (keeps the tool working for other users' unnamed exports).
- [ ] Add roles for tongue, toes, clavicles, and the third spine joint to
      `CatMeshAsset.Role` (Swift) and wire them into `CatShape`/`CatRig`/
      `CatSkin` — this part needs the Swift toolchain to verify.
- [ ] Re-run `export-cat.py` and `unwrap.py` against the new export, diff the
      resulting `cat.catmesh` against the current one, and sanity-check with
      `Tools/usd/preview.py`.

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
