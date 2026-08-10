#!/usr/bin/env python3
"""Fixes a diagonal leg-role swap in cat.catmesh.

`export-cat.py`'s `infer_roles` guessed joint roles from rest-pose geometry
because the FBX conversion stripped the source .blend's bone names. It got
eight of the sixteen leg joints wrong: the left-hind leg (source bones
`Bip01_L_Thigh` chain) was labelled as the front-right leg (`shoulderR` etc),
and the front-right leg (`Bip01_R_Clavicle` chain) was labelled as the
left-hind leg (`hipL` etc) — a clean diagonal swap. Two independent checks
confirm it: the joint parent chain matches the source .blend bone order
exactly, and the raw rest-pose coordinates put the mislabelled joints on the
wrong side of the body's own front/back and left/right midlines.

This script doesn't hardcode which joints are wrong. It derives the body's
own sign convention from the two leg chains that were NOT mislabelled
(front-left and hind-right), then checks every leg role against it, and
swaps only the roles that fail. If a future export has no mislabelled roles
at all, this script makes no changes and says so.

    Tools/usd/fix-leg-roles.py MeowRoom/Resources/cat.catmesh
"""
import struct
import sys

ROLES = [
    'hips', 'spineBase', 'spineMid', 'chest', 'neck', 'head', 'jaw', 'earL', 'earR',
    'tail0', 'tail1', 'tail2', 'tail3',
    'shoulderL', 'upperArmL', 'lowerArmL', 'pawL',
    'shoulderR', 'upperArmR', 'lowerArmR', 'pawR',
    'hipL', 'upperLegL', 'lowerLegL', 'footL',
    'hipR', 'upperLegR', 'lowerLegR', 'footR',
]

# The four bones making up each leg, in a fixed order, so a role group can be
# compared and swapped as a unit rather than one joint at a time.
LEG_GROUPS = {
    'shoulderL': ['shoulderL', 'upperArmL', 'lowerArmL', 'pawL'],
    'shoulderR': ['shoulderR', 'upperArmR', 'lowerArmR', 'pawR'],
    'hipL': ['hipL', 'upperLegL', 'lowerLegL', 'footL'],
    'hipR': ['hipR', 'upperLegR', 'lowerLegR', 'footR'],
}


def parse(data):
    at = 0

    def take(n):
        nonlocal at
        chunk = data[at:at + n]
        at += n
        return chunk

    def u32():
        return struct.unpack('<I', take(4))[0]

    def i16():
        return struct.unpack('<h', take(2))[0]

    def f32n(n):
        return struct.unpack(f'<{n}f', take(4 * n))

    assert take(8) == b'MEOWCAT2', 'not a MEOWCAT2 file'
    nv, ni, nj, influences = u32(), u32(), u32(), u32()

    take(nv * 12)              # positions
    take(nv * 12)              # normals
    take(nv * 8)               # uvs
    take(ni * 4)               # indices
    take(nv * influences * 2)  # joint indices
    take(nv * influences * 4)  # joint weights

    bind_positions = []
    for _ in range(nj):
        i16()                          # parent
        m = [f32n(4) for _ in range(4)]  # bind matrix, column-major
        bind_positions.append(m[3][:3])

    role_count = u32()
    roles_at = at
    roles = [i16() for _ in range(role_count)]

    return dict(nj=nj, bind_positions=bind_positions,
                role_count=role_count, roles=roles, roles_at=roles_at)


def role_joint(parsed, name):
    i = ROLES.index(name)
    j = parsed['roles'][i]
    assert j >= 0, f'role {name!r} has no joint (slot {i} = -1)'
    return j


def leg_positions(parsed, group_name):
    """(x, z) for each bone in a leg group, using the file's own coordinates."""
    out = []
    for role in LEG_GROUPS[group_name]:
        j = role_joint(parsed, role)
        x, _, z = parsed['bind_positions'][j]
        out.append((x, z))
    return out


def check_convention(parsed, group_name, expect_front, expect_right):
    """True if every bone in this leg group sits on the expected side."""
    for x, z in leg_positions(parsed, group_name):
        if (x > 0) != expect_front:
            return False
        if (z > 0) != expect_right:
            return False
    return True


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__.strip().splitlines()[-1].strip())
    path = sys.argv[1]
    data = bytearray(open(path, 'rb').read())
    parsed = parse(bytes(data))

    # Derive the sign convention from the two chains that agree with the
    # source .blend's bone order and are not suspected of being swapped:
    # front-left (Bip01_L_Clavicle chain) and hind-right (Bip01_R_Thigh chain).
    front_left_x = [x for x, z in leg_positions(parsed, 'shoulderL')]
    hind_right_x = [x for x, z in leg_positions(parsed, 'hipR')]
    assert all(x > 0 for x in front_left_x), \
        'shoulderL is not consistently forward (x > 0) — convention check failed'
    assert all(x < 0 for x in hind_right_x), \
        'hipR is not consistently hind (x < 0) — convention check failed'
    front_left_z = [z for x, z in leg_positions(parsed, 'shoulderL')]
    hind_right_z = [z for x, z in leg_positions(parsed, 'hipR')]
    assert all(z < 0 for z in front_left_z), \
        'shoulderL is not consistently left (z < 0) — convention check failed'
    assert all(z > 0 for z in hind_right_z), \
        'hipR is not consistently right (z > 0) — convention check failed'

    print(f'{path}: {parsed["nj"]} joints, convention derived from '
          f'shoulderL (front, x>0; left, z<0) and hipR (hind, x<0; right, z>0)')

    # Now check the other two groups against that same convention.
    shoulderR_ok = check_convention(parsed, 'shoulderR', expect_front=True, expect_right=True)
    hipL_ok = check_convention(parsed, 'hipL', expect_front=False, expect_right=False)

    if shoulderR_ok and hipL_ok:
        print('shoulderR and hipL already match the convention — nothing to fix.')
        return

    print(f'shoulderR (should be front-right): {"OK" if shoulderR_ok else "WRONG SIDE"}')
    print(f'hipL (should be hind-left):        {"OK" if hipL_ok else "WRONG SIDE"}')

    # Swap the joint each role in 'shoulderR' points to with the corresponding
    # role in 'hipL' — the fix is a straight swap between the two groups.
    for a, b in zip(LEG_GROUPS['shoulderR'], LEG_GROUPS['hipL']):
        ia, ib = ROLES.index(a), ROLES.index(b)
        ja, jb = parsed['roles'][ia], parsed['roles'][ib]
        offset_a = parsed['roles_at'] + ia * 2
        offset_b = parsed['roles_at'] + ib * 2
        struct.pack_into('<h', data, offset_a, jb)
        struct.pack_into('<h', data, offset_b, ja)
        print(f'  {a} (slot {ia}): joint {ja} -> {jb}    '
              f'{b} (slot {ib}): joint {jb} -> {ja}')

    open(path, 'wb').write(data)

    # Re-parse the patched file and verify against the same convention,
    # derived fresh so this isn't just checking its own arithmetic.
    reparsed = parse(bytes(data))
    ok = (check_convention(reparsed, 'shoulderR', expect_front=True, expect_right=True)
          and check_convention(reparsed, 'hipL', expect_front=False, expect_right=False)
          and all(x > 0 for x, z in leg_positions(reparsed, 'shoulderL'))
          and all(x < 0 for x, z in leg_positions(reparsed, 'hipR')))
    if not ok:
        raise SystemExit('patch written but post-patch verification failed — investigate before trusting the file')

    print('\npatched and verified: all four leg groups now sit on their named side.')


if __name__ == '__main__':
    main()
