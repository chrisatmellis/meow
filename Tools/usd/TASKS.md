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
