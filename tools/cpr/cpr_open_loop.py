#!/usr/bin/env python3
"""Open-loop CPR voltages for the Nexus 5X, as the 3.10 cpr-regulator.c
computes them (cpr_pvs_per_corner_init, cpr_adjust_init_voltages,
cpr_get_open_loop_voltage, cpr_init_ceiling_floor_override_voltages,
cpr_limit_open_loop_voltage, cpr_reduce_ceiling_voltage).

usage: cpr_open_loop.py NODE.dtsi FUSE_ROWS   (rows: "ROW n lo hi" lines)
"""
import re
import sys

ANY = 0xFFFFFFFF


def prop(s, name, required=True):
    m = re.search(r'qcom,' + re.escape(name) + r'\s*=\s*([^;]*);', s)
    if not m:
        if required:
            sys.exit('missing qcom,' + name)
        return None
    vals = []
    for tok in re.findall(r'\(\s*-?\s*\w+\s*\)|-?0x[0-9a-fA-F]+|-?\d+', m.group(1)):
        tok = tok.strip('() ').replace(' ', '')
        vals.append(int(tok, 0) & 0xFFFFFFFF)
    return vals


def s32(v):
    return v - (1 << 32) if v & 0x80000000 else v


def flag(s, name):
    return re.search(r'qcom,' + re.escape(name) + r'\s*;', s) is not None


def main():
    s = open(sys.argv[1]).read()
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
    s = re.sub(r'//[^\n]*', '', s)
    rows = {}
    for line in open(sys.argv[2]):
        _, r, lo, hi = line.split()
        rows[int(r)] = int(lo, 16) | (int(hi, 16) << 32)

    def param(row, bit, width):
        row += bit >> 6
        bit &= 63
        v = rows[row] >> bit
        if bit + width > 64:
            v |= rows[row + 1] << (64 - bit)
        return v & ((1 << width) - 1)

    nfc = prop(s, 'cpr-fuse-corners')[0]
    redun = prop(s, 'cpr-fuse-redun-sel')
    if param(*redun[:3]) == redun[3]:
        sys.exit('redundant fuses selected: not modelled')
    rev = param(*prop(s, 'cpr-fuse-revision')[:3])
    sb = prop(s, 'speed-bin-fuse-sel')
    speed_bin = param(*sb[:3])
    pvs_version = 0
    frow = prop(s, 'cpr-fuse-row')[0]
    ro = [param(frow, b, 3) for b in prop(s, 'cpr-fuse-ro-sel')]
    print(f'speed bin {speed_bin}, fuse revision {rev}, ro_sel {ro}')

    vmap = prop(s, 'cpr-fuse-version-map')
    ts = nfc + 3
    match = None
    for i in range(len(vmap) // ts):
        t = vmap[i * ts:(i + 1) * ts]
        if t[0] not in (speed_bin, ANY) or t[1] not in (pvs_version, ANY) \
           or t[2] not in (rev, ANY):
            continue
        if all(t[3 + j] in (ro[j], ANY) for j in range(nfc)):
            match = i
            break
    print(f'fuse version map match: tuple {match}')
    allowed = prop(s, 'cpr-allowed', False)
    if allowed and match is not None:
        print(f'closed-loop CPR allowed by stock: {bool(allowed[match])}')

    step = prop(s, 'cpr-apc-volt-step')[0]
    ref = prop(s, 'cpr-init-voltage-ref')
    vstep = prop(s, 'cpr-init-voltage-step')[0]
    fsel = prop(s, 'cpr-fuse-init-voltage')
    fceil = prop(s, 'cpr-voltage-ceiling')
    ffloor = prop(s, 'cpr-voltage-floor')
    adj = prop(s, 'cpr-init-voltage-adjustment', False)
    pvs = []
    for i in range(nfc):
        r, b, w = fsel[i * 4:i * 4 + 3]
        bits = param(r, b, w)
        sign = -1 if bits & (1 << (w - 1)) else 1
        steps = bits & ((1 << (w - 1)) - 1)
        v = ref[i] + sign * steps * vstep
        v = -(-v // step) * step
        a = s32(adj[match * nfc + i]) if adj and match is not None else 0
        print(f'fuse corner {i + 1}: fuse {bits:#04x} -> {v} uV, adjust {a:+d}', end='')
        v += a
        v = min(max(v, ffloor[i]), fceil[i])
        print(f' -> {v} uV (floor {ffloor[i]}, ceiling {fceil[i]})')
        pvs.append(v)

    cmap = prop(s, 'cpr-corner-map')
    nc = len(cmap)
    ol = [None] + [pvs[cmap[i] - 1] for i in range(nc)]
    # corner_max per speed bin, frequency map
    sbm = prop(s, 'cpr-speed-bin-max-corners')
    corner_max = None
    for i in range(0, len(sbm), nfc + 2):
        t = sbm[i:i + nfc + 2]
        if t[0] in (speed_bin, ANY) and t[1] in (pvs_version, ANY):
            corner_max = [None] + t[2:]
            break
    fm = prop(s, 'cpr-corner-frequency-map')
    freq = [0] * (nc + 1)
    for i in range(0, len(fm), 2):
        freq[fm[i]] = fm[i + 1]
    maxf = prop(s, 'cpr-voltage-scaling-factor-max', False)
    if corner_max and maxf:
        for j in range(2, nfc + 1):
            fh, fl = freq[corner_max[j]], freq[corner_max[j - 1]]
            vh, vl = pvs[j - 1], pvs[j - 2]
            if fh <= fl or vh <= vl:
                continue
            for i in range(corner_max[j - 1] + 1, corner_max[j]):
                f = freq[i]
                if fh <= f:
                    continue
                t = (fh - f) * (vh - vl) // (fh - fl)
                lim = (fh - f) * maxf[j - 1] // 1000000
                v = vh - min(t, lim)
                ol[i] = -(-v // step) * step

    def override(name, fuse_limit):
        o = prop(s, name, False)
        if o:
            for i in range(0, len(o), nc + 2):
                t = o[i:i + nc + 2]
                if t[0] in (speed_bin, ANY) and t[1] in (pvs_version, ANY):
                    return [None] + t[2:]
        return [None] + [fuse_limit[cmap[i] - 1] for i in range(nc)]

    ceil = override('cpr-voltage-ceiling-override', fceil)
    floor = override('cpr-voltage-floor-override', ffloor)
    for i in range(1, nc + 1):
        ol[i] = min(max(ol[i], floor[i]), ceil[i])
    if flag(s, 'cpr-scaled-init-voltage-as-ceiling'):
        for i in range(1, nc + 1):
            ceil[i] = min(ceil[i], ol[i])
    last = corner_max[nfc] if corner_max else nc
    print('virtual corner  freq MHz  fuse corner  open-loop uV  floor  ceiling')
    for i in range(1, nc + 1):
        mark = '' if i <= last else '   (above this speed bin)'
        print(f'{i:>14}  {freq[i] / 1e6:>8.1f}  {cmap[i - 1]:>11}  {ol[i]:>12}  '
              f'{floor[i]:>6}  {ceil[i]:>7}{mark}')


main()
