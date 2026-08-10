#!/usr/bin/env python3
"""Turns a baked USD skeletal animation into the binary clip the game plays back.

Sampled per frame rather than stored as keyframe curves: the source is already a
dense per-frame bake (Blender's USD exporter samples every frame of the action),
so there is no sparse curve to preserve, and a flat per-frame array of local
joint transforms is exactly what playback needs to do anyway — look up frame i
and frame i+1, slerp/lerp between them.

Joints the clip does not cover are left out of the file entirely rather than
padded with a guessed rest value. `CatMeshAsset`'s roles work the same way
("anything not named here is still carried... it simply follows its parent") —
here it means a joint the clip is silent on keeps whatever pose the rest of the
animator already gave it that frame, procedural or bind.

## Rotations are exported relative to *this file's* rest pose, not the source's

`CatShape`/`CatBuilder` deliberately discard every joint's rest *rotation* when
building the rig — a joint entity starts at identity orientation, and the
animator writes pure deltas onto that (see `CatShape.swift`'s doc comment on
why: applying a file's raw bind-relative rotations "folded the skeleton into a
heap", because each bone's rest orientation sits on a different, exporter-
chosen axis). A `SkelAnimation`'s rotations are local-to-parent *in the file's
own bind pose*, which is exactly that same trap: writing them straight onto a
`CatMeshAsset` joint would mean "pitch" on one bone and some unrelated axis on
the next.

So each rotation is re-expressed here as a delta from *this skeleton's own*
bind-local rotation before it's written — `delta = restLocal.inverse() *
frameLocal`, both computed the same "row-vector, USD-native" way (verified
against a round-trip: `restLocal * delta` reproduces `frameLocal` exactly).
That delta is a small, physically sensible rotation on its own (checked
directly: a walking thigh's delta swings 5-36 degrees, smoothly, frame to
frame — not some huge or discontinuous number, which is what a wrong
composition order would have produced), and is safe to apply directly as a
`CatMeshAsset` joint's orientation, because both start from the same "identity
means rest" convention.

## Which joints, by default

Blender bakes every joint in the skeleton whether it moved or not, but the game
should not blindly apply all of them: the clip is one specific walk cycle, and
handing its baked spine/tail/ear motion to `CatAnimator` would fight the
procedural systems already driving those (attention look-at, idle tail sway,
ear twitch) for no benefit, since only the *legs* are what read as stiff today.
So by default this keeps only the hips (the root the legs hang off) and the
four legs' hip/knee/ankle/paw chains, and drops the rest — meaning the Swift
side never has to make that judgment call itself; it can just apply whatever
the clip contains. Pass `--joints=all` to keep everything instead (e.g. for a
future clip that's meant to drive the whole body).

    Tools/usd/export-anim.py [--joints=all] <in.usdz|in.usdc> <out.catanim>
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from unwrap import load_stage, first_of_type  # noqa: E402
from pxr import UsdSkel  # noqa: E402

MAGIC = b'MEOWANM1'

# Below this fraction of the animation's own joints resolving onto the skeleton
# by name, the two do not belong together — refuse rather than silently drive
# most of the skeleton from mismatched channels (same principle as
# export-cat.py's NAME_MATCH_THRESHOLD).
NAME_MATCH_THRESHOLD = 0.8

# The default joint filter: hips, plus each leg's hip/knee/ankle/paw chain, by
# their real bone names (same naming export-cat.py's NAME_TO_ROLE maps from).
LEGS_AND_HIPS = {'Hips'}
for side in ('L', 'R'):
    LEGS_AND_HIPS.update(f'Bip01_{side}_{bone}' for bone in
                         ('UpperArm', 'Forearm', 'Hand', 'Finger0'))
    LEGS_AND_HIPS.update(f'Bip01_{side}_{bone}' for bone in
                         ('Thigh', 'Calf', 'HorseLink', 'Foot'))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    keep_all = '--joints=all' in sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        return 1
    src, dst = args[0], args[1]
    stage = load_stage(src)

    skel_prim = first_of_type(stage, 'Skeleton')
    if skel_prim is None:
        raise SystemExit('no Skeleton in the stage')
    skel = UsdSkel.Skeleton(skel_prim)
    skel_paths = [str(j) for j in (skel.GetJointsAttr().Get() or [])]
    skel_names = [p.rsplit('/', 1)[-1] for p in skel_paths]
    joint_count = len(skel_names)
    name_to_index = {n: i for i, n in enumerate(skel_names)}
    path_to_index = {p: i for i, p in enumerate(skel_paths)}
    joint_parent = []
    for p in skel_paths:
        cut = p.rfind('/')
        joint_parent.append(path_to_index.get(p[:cut], -1) if cut >= 0 else -1)

    anim_prim = first_of_type(stage, 'SkelAnimation')
    if anim_prim is None:
        raise SystemExit('no SkelAnimation in the stage')
    anim = UsdSkel.Animation(anim_prim)
    anim_names = [str(j).rsplit('/', 1)[-1] for j in (anim.GetJointsAttr().Get() or [])]
    if not anim_names:
        raise SystemExit('SkelAnimation has no joints')

    remap = [name_to_index.get(n, -1) for n in anim_names]
    unresolved = sum(1 for i in remap if i < 0)
    if unresolved > len(anim_names) * (1 - NAME_MATCH_THRESHOLD):
        raise SystemExit(f'{unresolved}/{len(anim_names)} animated joints do not '
                          'match this skeleton by name -- refusing to export a '
                          'clip that would misdrive most of the skeleton')

    from pxr import UsdGeom, Gf  # noqa: E402
    scale = UsdGeom.GetStageMetersPerUnit(stage) or 1.0

    # This skeleton's own rest-local rotation per joint, so each frame's
    # rotation can be re-expressed as a delta from it (see module docstring).
    binds = skel.GetBindTransformsAttr().Get() or []

    def rest_local_quat(j):
        mj = binds[j]
        p = joint_parent[j]
        local = mj if p < 0 else mj * binds[p].GetInverse()
        return local.ExtractRotationQuat()

    rest_quats = {j: rest_local_quat(j) for j in range(joint_count)}

    rot_attr = anim.GetRotationsAttr()
    trans_attr = anim.GetTranslationsAttr()
    times = sorted(rot_attr.GetTimeSamples())
    if not times:
        raise SystemExit('SkelAnimation has no time samples')
    fps = stage.GetTimeCodesPerSecond() or 24.0

    # Which skeleton joints this clip actually drives, in the order we'll write
    # their per-frame data. A channel with no time-varying value at all (e.g. a
    # leaf bone Blender baked out of habit) is still included — cheap, and
    # simpler than trying to detect "did this ever actually move".
    driven = sorted(i for i in remap if i >= 0)
    if not keep_all:
        driven = [i for i in driven if skel_names[i] in LEGS_AND_HIPS]
        missing_filter = LEGS_AND_HIPS - {skel_names[i] for i in driven}
        if missing_filter:
            raise SystemExit(f'--joints filter expected these bones and did not '
                              f'find them animated: {sorted(missing_filter)}')
    anim_index_of_joint = {}
    for anim_i, skel_i in enumerate(remap):
        if skel_i >= 0:
            anim_index_of_joint[skel_i] = anim_i

    frames = []
    for t in times:
        rots = rot_attr.Get(t)
        trans = trans_attr.Get(t)
        frame = []
        for j in driven:
            ai = anim_index_of_joint[j]
            qf = rots[ai]
            frame_q = Gf.Quatd(qf.GetReal(), Gf.Vec3d(*qf.GetImaginary()))
            delta = rest_quats[j].GetInverse() * frame_q
            im = delta.GetImaginary()
            p = trans[ai]
            # Scaled into metres, same convention as export-cat.py's bind
            # matrices — joint entities in the game are built and posed in
            # metres throughout.
            frame.append((im[0], im[1], im[2], delta.GetReal(),
                          p[0] * scale, p[1] * scale, p[2] * scale))
        frames.append(frame)

    blob = bytearray()
    blob += MAGIC
    blob += struct.pack('<IIfI', joint_count, len(frames), fps, len(driven))
    for j in driven:
        blob += struct.pack('<H', j)
    for frame in frames:
        for qx, qy, qz, qw, tx, ty, tz in frame:
            blob += struct.pack('<7f', qx, qy, qz, qw, tx, ty, tz)

    with open(dst, 'wb') as f:
        f.write(blob)

    print(f'  wrote {dst}  ({len(blob)} bytes)')
    print(f'  {len(frames)} frames at {fps} fps ({len(frames) / fps:.2f}s), '
          f'{len(driven)}/{joint_count} joints driven')
    missing = [skel_names[i] for i in range(joint_count) if i not in anim_index_of_joint]
    if missing:
        print(f'  not driven by this clip: {", ".join(missing)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
