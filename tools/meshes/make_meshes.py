"""Writes the Game Night OBJ meshes (see docs/Meshes.md).

    python3 tools/meshes/make_meshes.py <out_dir>

Every mesh is Y up, centered on its bounding box, in studs at the size the code uses,
with smooth normals and simple UVs. Import each into Studio (3D Importer), name the
MeshPart as listed in docs/Meshes.md and put it in ReplicatedStorage.Assets.Meshes.
Pure standard library, no dependencies.
"""

import math
import os
import sys


class Mesh:
    def __init__(self, name):
        self.name = name
        self.v = []  # (x, y, z)
        self.uv = []  # (u, v), one per vertex
        self.f = []  # triangles of vertex indices

    def add(self, p, uv=(0.0, 0.0)):
        self.v.append(p)
        self.uv.append(uv)
        return len(self.v) - 1

    def quad(self, a, b, c, d):
        self.f.append((a, b, c))
        self.f.append((a, c, d))

    def center(self):
        xs, ys, zs = zip(*self.v)
        cx, cy, cz = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, (max(zs) + min(zs)) / 2
        self.v = [(x - cx, y - cy, z - cz) for x, y, z in self.v]
        return self

    def size(self):
        xs, ys, zs = zip(*self.v)
        return (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))

    def normals(self):
        n = [[0.0, 0.0, 0.0] for _ in self.v]
        # Vertices at the same spot (lathe seams, caps) share a normal.
        key = {}
        for i, p in enumerate(self.v):
            key.setdefault(tuple(round(c, 5) for c in p), []).append(i)
        for a, b, c in self.f:
            pa, pb, pc = self.v[a], self.v[b], self.v[c]
            u = [pb[i] - pa[i] for i in range(3)]
            w = [pc[i] - pa[i] for i in range(3)]
            fn = (u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0])
            for idx in (a, b, c):
                for k in range(3):
                    n[idx][k] += fn[k]
        out = list(n)
        for group in key.values():
            if len(group) > 1:
                s = [sum(n[i][k] for i in group) for k in range(3)]
                # Only merge when the faces agree (keeps hard rims hard).
                for i in group:
                    dot = sum(n[i][k] * s[k] for k in range(3))
                    if dot > 0:
                        out[i] = s
        res = []
        for x, y, z in out:
            l = math.sqrt(x * x + y * y + z * z) or 1.0
            res.append((x / l, y / l, z / l))
        return res

    def write(self, folder):
        self.center()
        norms = self.normals()
        path = os.path.join(folder, f"{self.name}.obj")
        with open(path, "w") as fh:
            sx, sy, sz = self.size()
            fh.write(f"# Game Night mesh {self.name}: {sx:.3f} x {sy:.3f} x {sz:.3f} studs, Y up\n")
            fh.write(f"o {self.name}\n")
            for x, y, z in self.v:
                fh.write(f"v {x:.5f} {y:.5f} {z:.5f}\n")
            for u, v in self.uv:
                fh.write(f"vt {u:.5f} {v:.5f}\n")
            for x, y, z in norms:
                fh.write(f"vn {x:.5f} {y:.5f} {z:.5f}\n")
            for a, b, c in self.f:
                fh.write(f"f {a+1}/{a+1}/{a+1} {b+1}/{b+1}/{b+1} {c+1}/{c+1}/{c+1}\n")
        return path, len(self.f)


def lathe(name, profile, segments=48, radius_fn=None):
    """Spins `profile` [(r, y), ...] (bottom center to top center) around Y.
    radius_fn(r, angle) can wobble the radius (ridges)."""
    m = Mesh(name)
    rows = []
    total = sum(math.dist(profile[i], profile[i + 1]) for i in range(len(profile) - 1)) or 1
    t = 0.0
    for j, (r, y) in enumerate(profile):
        if j > 0:
            t += math.dist(profile[j - 1], profile[j])
        row = []
        for i in range(segments + 1):
            a = i / segments * math.pi * 2
            rr = radius_fn(r, a) if radius_fn and r > 0 else r
            row.append(m.add((math.sin(a) * rr, y, math.cos(a) * rr), (i / segments, t / total)))
        rows.append(row)
    for j in range(len(rows) - 1):
        for i in range(segments):
            a, b, c, d = rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i]
            m.quad(a, b, c, d)
    return m


def arc(cx, cy, r, a0, a1, steps):
    """Points on a circle in the (radius, y) plane, angles in degrees."""
    return [(cx + math.cos(math.radians(a0 + (a1 - a0) * i / steps)) * r, cy + math.sin(math.radians(a0 + (a1 - a0) * i / steps)) * r) for i in range(steps + 1)]


def merge(name, meshes):
    out = Mesh(name)
    for m in meshes:
        base = len(out.v)
        out.v += m.v
        out.uv += m.uv
        out.f += [(a + base, b + base, c + base) for a, b, c in m.f]
    return out


def box(name, cx, cy, cz, sx, sy, sz):
    m = Mesh(name)
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    faces = [
        ((1, 0, 0), (0, 0, -1), (0, 1, 0)),
        ((-1, 0, 0), (0, 0, 1), (0, 1, 0)),
        ((0, 1, 0), (1, 0, 0), (0, 0, -1)),
        ((0, -1, 0), (1, 0, 0), (0, 0, 1)),
        ((0, 0, 1), (1, 0, 0), (0, 1, 0)),
        ((0, 0, -1), (-1, 0, 0), (0, 1, 0)),
    ]
    for n, u, v in faces:
        idx = []
        for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            p = [n[k] * (hx, hy, hz)[k] + su * u[k] * (hx, hy, hz)[k] + sv * v[k] * (hx, hy, hz)[k] for k in range(3)]
            idx.append(m.add((cx + p[0], cy + p[1], cz + p[2]), ((su + 1) / 2, (sv + 1) / 2)))
        m.quad(*idx)
    return m


def extrude(name, outline, depth, bevel=0.0):
    """Extrudes a closed 2D outline [(x, y)] (counter-clockwise) along Z, centered.
    Caps are fanned from the outline's centroid, so keep outlines star-shaped."""
    m = Mesh(name)
    cx = sum(p[0] for p in outline) / len(outline)
    cy = sum(p[1] for p in outline) / len(outline)
    layers = [(-depth / 2, 1.0 - bevel), (-depth / 2 + bevel, 1.0), (depth / 2 - bevel, 1.0), (depth / 2, 1.0 - bevel)] if bevel > 0 else [(-depth / 2, 1.0), (depth / 2, 1.0)]
    rings = []
    for z, k in layers:
        ring = [m.add((cx + (x - cx) * k, cy + (y - cy) * k, z), (x, y)) for x, y in outline]
        rings.append(ring)
    n = len(outline)
    for j in range(len(rings) - 1):
        for i in range(n):
            m.quad(rings[j][i], rings[j][(i + 1) % n], rings[j + 1][(i + 1) % n], rings[j + 1][i])
    for ring, z, flip in ((rings[0], layers[0][0], True), (rings[-1], layers[-1][0], False)):
        c = m.add((cx, cy, z))
        for i in range(n):
            a, b = ring[i], ring[(i + 1) % n]
            m.f.append((c, b, a) if flip else (c, a, b))
    return m


def rounded_rect(w, h, r, steps=6):
    pts = []
    for cx, cy, a0 in ((w / 2 - r, -h / 2 + r, -90), (w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180)):
        for i in range(steps + 1):
            a = math.radians(a0 + 90 * i / steps)
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def rotate_x(m, degrees):
    a = math.radians(degrees)
    m.v = [(x, y * math.cos(a) - z * math.sin(a), y * math.sin(a) + z * math.cos(a)) for x, y, z in m.v]
    return m


# ---- Furniture -------------------------------------------------------------------------

def table_top_round():
    # 13 across, 0.4 thick, a bullnose (rounded) edge.
    R, H, e = 6.5, 0.4, 0.2
    prof = [(0, 0)] + arc(R - e, e, e, -90, 90, 10) + [(0, H)]
    return lathe("TableTopRound", prof, 96)


def table_rail_round():
    # A padded leather tube around the felt: torus, ring radius 5.95, tube 0.42.
    R, r = 5.95, 0.21
    prof = arc(R, r, r, -90, 270, 16)
    return lathe("TableRailRound", prof, 96)


def stool_cushion():
    # 1.95 across, 0.36 tall: a domed cushion with a piped edge.
    prof = [(0, 0), (0.9, 0), (0.95, 0.04)] + arc(0.9, 0.16, 0.075, -60, 90, 6) + [(0.75, 0.28), (0.45, 0.34), (0, 0.36)]
    return lathe("StoolCushion", prof, 48)


# ---- Pieces ----------------------------------------------------------------------------

def die():
    # A 1-stud die with rounded edges (a rounded cube from a subdivided, pushed-out cube).
    m = Mesh("Die")
    n, r = 8, 0.14
    inner = 0.5 - r
    faces = [((1, 0, 0), (0, 0, -1), (0, 1, 0)), ((-1, 0, 0), (0, 0, 1), (0, 1, 0)), ((0, 1, 0), (1, 0, 0), (0, 0, -1)), ((0, -1, 0), (1, 0, 0), (0, 0, 1)), ((0, 0, 1), (1, 0, 0), (0, 1, 0)), ((0, 0, -1), (-1, 0, 0), (0, 1, 0))]
    for nrm, u, v in faces:
        grid = []
        for j in range(n + 1):
            row = []
            for i in range(n + 1):
                su, sv = -1 + 2 * i / n, -1 + 2 * j / n
                p = [0.5 * (nrm[k] + su * u[k] + sv * v[k]) for k in range(3)]
                q = [max(-inner, min(inner, c)) for c in p]
                d = [p[k] - q[k] for k in range(3)]
                l = math.sqrt(sum(c * c for c in d)) or 1
                pt = tuple(q[k] + d[k] / l * r for k in range(3))
                row.append(m.add(pt, (i / n, j / n)))
            grid.append(row)
        for j in range(n):
            for i in range(n):
                m.quad(grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])
    return m


def pawn():
    # A plain game pawn, 1 stud tall (Models.pawn proportions).
    prof = [(0, 0), (0.31, 0), (0.31, 0.06)] + arc(0.29, 0.08, 0.03, 0, 90, 3) + [(0.25, 0.12), (0.22, 0.16), (0.17, 0.3), (0.12, 0.5), (0.1, 0.6), (0.18, 0.62), (0.18, 0.66), (0.09, 0.68)] + arc(0, 0.82, 0.18, -60, 90, 10)
    return lathe("Pawn", prof, 40)


def card():
    m = extrude("Card", rounded_rect(0.9, 1.26, 0.08), 0.03, 0.006)
    return rotate_x(m, 90)  # lie flat: 0.9 wide (X), 1.26 long (Z), 0.03 thick (Y)


def checker():
    # A checker with a ridged rim, 1 across, 0.28 tall.
    prof = [(0, 0), (0.48, 0), (0.5, 0.03), (0.5, 0.25), (0.48, 0.28), (0.36, 0.28), (0.34, 0.25), (0.3, 0.24), (0, 0.24)]
    return lathe("Checker", prof, 72, lambda r, a: r * (1 + 0.012 * math.cos(a * 36)) if r >= 0.49 else r)


def hex_tile():
    # A Hexlands land tile: pointy-top hexagon (points at +-Z), 1 stud corner to corner,
    # beveled edges, 0.2 thick.
    pts = [(math.cos(math.radians(60 * i + 30)) * 0.5, math.sin(math.radians(60 * i + 30)) * 0.5) for i in range(6)]
    m = extrude("HexTile", pts, 0.2, 0.03)
    return rotate_x(m, -90)


# ---- Chess (an alternative smooth set; Assets.Chess is used today) ---------------------

def chess_base(h):
    return [(0, 0), (0.42 * h, 0), (0.42 * h, 0.04 * h)] + arc(0.38 * h, 0.07 * h, 0.04 * h, 0, 90, 3) + [(0.3 * h, 0.13 * h), (0.32 * h, 0.15 * h), (0.24 * h, 0.18 * h)]


def chess_pawn():
    h = 1.0
    prof = chess_base(0.8) + [(0.14, 0.3), (0.1, 0.45), (0.2, 0.47), (0.2, 0.5), (0.09, 0.52)] + arc(0, 0.64, 0.14, -50, 90, 8)
    return lathe("ChessPawn", prof, 40)


def chess_rook():
    prof = chess_base(1) + [(0.2, 0.3), (0.18, 0.62), (0.26, 0.66), (0.26, 0.86), (0.18, 0.86), (0.18, 0.8), (0, 0.8)]
    body = lathe("b", prof, 40)
    teeth = []
    for i in range(6):
        a = i / 6 * math.pi * 2
        t = box("t", math.sin(a) * 0.22, 0.9, math.cos(a) * 0.22, 0.09, 0.08, 0.09)
        teeth.append(t)
    return merge("ChessRook", [body] + teeth)


def chess_bishop():
    prof = chess_base(1) + [(0.15, 0.35), (0.1, 0.6), (0.22, 0.62), (0.22, 0.65), (0.1, 0.67), (0.15, 0.75), (0.15, 0.86), (0.08, 0.98), (0.04, 1.0)] + arc(0, 1.04, 0.05, -60, 90, 5)
    return lathe("ChessBishop", prof, 40)


def chess_queen():
    prof = chess_base(1.1) + [(0.16, 0.4), (0.1, 0.72), (0.24, 0.74), (0.24, 0.77), (0.12, 0.8), (0.2, 1.0), (0.22, 1.04), (0.12, 1.06)] + arc(0, 1.12, 0.07, -60, 90, 5)
    body = lathe("b", prof, 40)
    crown = []
    for i in range(8):
        a = i / 8 * math.pi * 2
        crown.append(lathe("c", arc(0, 1.06, 0.035, -90, 90, 5), 12))
        crown[-1].v = [(x + math.sin(a) * 0.21, y, z + math.cos(a) * 0.21) for x, y, z in crown[-1].v]
    return merge("ChessQueen", [body] + crown)


def chess_king():
    prof = chess_base(1.1) + [(0.17, 0.4), (0.11, 0.74), (0.25, 0.76), (0.25, 0.79), (0.13, 0.82), (0.21, 1.02), (0.21, 1.06), (0, 1.08)]
    body = lathe("b", prof, 40)
    return merge("ChessKing", [body, box("x", 0, 1.2, 0, 0.06, 0.24, 0.06), box("y", 0, 1.22, 0, 0.18, 0.06, 0.06)])


def chess_knight():
    base = lathe("b", chess_base(1) + [(0, 0.18)], 40)
    # Side silhouette of a horse head (x forward, y up), extruded 0.26 thick.
    head = [(-0.22, 0.18), (0.2, 0.18), (0.16, 0.34), (0.12, 0.48), (0.26, 0.6), (0.32, 0.7), (0.3, 0.78), (0.18, 0.82), (0.1, 0.9), (0.04, 0.98), (-0.02, 0.92), (-0.12, 0.86), (-0.2, 0.74), (-0.24, 0.56), (-0.26, 0.36)]
    neck = extrude("h", head, 0.26, 0.04)
    # Face -Z like the rest of the set (White faces -Z): turn the head's +X forward to -Z.
    neck.v = [(z, y, -x) for x, y, z in neck.v]
    return merge("ChessKnight", [base, neck])


MESHES = [
    table_top_round, table_rail_round, stool_cushion,
    die, pawn, card, checker, hex_tile,
    chess_pawn, chess_rook, chess_knight, chess_bishop, chess_queen, chess_king,
]


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "meshes"
    os.makedirs(out, exist_ok=True)
    for make in MESHES:
        m = make()
        path, tris = m.write(out)
        sx, sy, sz = m.size()
        print(f"{m.name:16s} {tris:6d} tris  {sx:.2f} x {sy:.2f} x {sz:.2f}  {path}")


if __name__ == "__main__":
    main()
