"""Builds the real-history maps in data/maps/ from real geography.

    python3 tools/make_real_maps.py [map_id ...]

The coastlines come from Natural Earth (public domain), cut out by
tools/extract_coastlines.py into tools/coastlines/<map>.json. The towns and
their approximate latitude/longitude are in tools/real_maps_data.py. Nothing
is traced from another game's maps.

How a map is made:
  1. The coastline is projected (orthographic, centred on the map) and painted
     onto a grid of small square cells: land, sea or lake.
  2. Each region grows over the land from its town, cell by cell, slightly
     faster or slower on a smooth random noise so the borders wander like real
     ones. Regions can't cross the sea, so islands keep their own regions; land
     that no town reaches (other countries, far deserts) becomes scenery: drawn
     as land but not playable.
  3. Small fixes: lone cells are smoothed away, every region is one connected
     piece without holes, and no two cells of a region touch only at a corner.
  4. The cell borders are traced into chains between the points where three
     areas meet, smoothed and simplified. Each chain is used by both areas on
     either side, so neighbouring regions share exactly the same vertices.
The script checks that every region is reachable by land or a sea link, that
sea links join ports, and that region names don't crowd each other.
"""

import heapq
import json
import math
import os
import random
import re
import sys
import unicodedata
from collections import deque

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from real_maps_data import MAPS  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WATER, OUT, DECOR = -1, -2, -3
POPULATION = {5: 6500, 10: 10500, 15: 14500}


def to_id(name):
    plain = unicodedata.normalize("NFKD", name.replace("ø", "o").replace("ł", "l").replace("æ", "ae"))
    plain = plain.encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z]+", "_", plain.lower()).strip("_")


class Projection:
    """Orthographic projection around the map centre, in pixels."""

    def __init__(self, spec):
        self.lon0, self.lat0 = math.radians(spec["center"][0]), math.radians(spec["center"][1])
        self.scale = spec["scale"]
        self.grid = spec.get("grid", 6)
        w, h = spec["span"]
        self.nx = int(round(w * self.scale / self.grid))
        self.ny = int(round(h * self.scale / self.grid))
        self.width, self.height = self.nx * self.grid, self.ny * self.grid

    def __call__(self, lon, lat):
        lam, phi = math.radians(lon), math.radians(lat)
        x = math.cos(phi) * math.sin(lam - self.lon0)
        y = math.cos(self.lat0) * math.sin(phi) - math.sin(self.lat0) * math.cos(phi) * math.cos(lam - self.lon0)
        return (self.width / 2 + math.degrees(x) * self.scale, self.height / 2 - math.degrees(y) * self.scale)


class Builder:
    def __init__(self, spec):
        self.spec = spec
        self.id = spec["id"]
        self.proj = Projection(spec)
        self.g = self.proj.grid
        self.nx, self.ny = self.proj.nx, self.proj.ny
        self.rng = random.Random(spec.get("seed", 7))
        self.towns = []
        for entry in spec["regions"]:
            name, lat, lon, owner, income, terrain = entry[:6]
            flags = entry[6].split() if len(entry) > 6 else []
            weight = 1.0
            for f in flags:
                if f.startswith("w="):
                    weight = float(f[2:])
            self.towns.append({"name": name, "id": to_id(name), "lat": lat, "lon": lon, "owner": owner,
                               "income": income, "terrain": terrain, "flags": set(flags), "weight": weight})
        ids = [t["id"] for t in self.towns]
        assert len(set(ids)) == len(ids), f"{self.id}: duplicate region ids"
        self.warnings = []

    def warn(self, text):
        self.warnings.append(text)
        print(f"  ! {text}")

    # ----- 1. land and water --------------------------------------------------------------

    def rasterize(self):
        with open(os.path.join(ROOT, "tools", "coastlines", self.id + ".json")) as f:
            coast = json.load(f)
        rings = []
        for ring in coast["land"] + coast["lakes"]:
            rings.append([self.proj(lon, lat) for lon, lat in ring])
        for strait in self.spec.get("straits", []):
            pass  # carved after filling
        nx, ny, g = self.nx, self.ny, self.g
        buckets = [[] for _ in range(ny)]
        for ring in rings:
            for i in range(len(ring)):
                (x0, y0), (x1, y1) = ring[i - 1], ring[i]
                if y0 == y1:
                    continue
                lo, hi = min(y0, y1), max(y0, y1)
                j0 = max(0, int(math.ceil(lo / g - 0.5)))
                j1 = min(ny - 1, int(math.floor(hi / g - 0.5)))
                for j in range(j0, j1 + 1):
                    buckets[j].append((x0, y0, x1, y1))
        land = [False] * (nx * ny)
        for j in range(ny):
            yc = (j + 0.5) * g
            xs = []
            for x0, y0, x1, y1 in buckets[j]:
                if (y0 <= yc < y1) or (y1 <= yc < y0):
                    xs.append(x0 + (yc - y0) * (x1 - x0) / (y1 - y0))
            xs.sort()
            for k in range(0, len(xs) - 1, 2):
                i0 = max(0, int(math.ceil(xs[k] / g - 0.5)))
                i1 = min(nx - 1, int(math.floor(xs[k + 1] / g - 0.5)))
                for i in range(i0, i1 + 1):
                    land[j * nx + i] = True
        # Straits that the grid would close up: carved out as water.
        for a, b in self.spec.get("straits", []):
            pa, pb = self.proj(a[1], a[0]), self.proj(b[1], b[0])
            steps = int(max(abs(pb[0] - pa[0]), abs(pb[1] - pa[1])) / (g / 3)) + 1
            for s in range(steps + 1):
                x = pa[0] + (pb[0] - pa[0]) * s / steps
                y = pa[1] + (pb[1] - pa[1]) * s / steps
                i, j = int(x / g), int(y / g)
                if 0 <= i < nx and 0 <= j < ny:
                    land[j * nx + i] = False
        self.land = land

    def neighbours4(self, c):
        nx = self.nx
        i, j = c % nx, c // nx
        if i > 0:
            yield c - 1
        if i < nx - 1:
            yield c + 1
        if j > 0:
            yield c - nx
        if j < self.ny - 1:
            yield c + nx

    def components(self, member):
        """4-connected components of the cells where member(c) is true."""
        seen = [False] * (self.nx * self.ny)
        out = []
        for start in range(self.nx * self.ny):
            if seen[start] or not member(start):
                continue
            comp = [start]
            seen[start] = True
            k = 0
            while k < len(comp):
                for n in self.neighbours4(comp[k]):
                    if not seen[n] and member(n):
                        seen[n] = True
                        comp.append(n)
                k += 1
            out.append(comp)
        return out

    def place_towns(self):
        land = self.land
        for t in self.towns:
            x, y = self.proj(t["lon"], t["lat"])
            t["xy"] = (x, y)
            i, j = int(x / self.g), int(y / self.g)
            assert 0 <= i < self.nx and 0 <= j < self.ny, f"{self.id}: {t['name']} is off the map"
            c = j * self.nx + i
            if not land[c]:
                # The town is on the coast: use the nearest land cell.
                best = None
                for dj in range(-5, 6):
                    for di in range(-5, 6):
                        ii, jj = i + di, j + dj
                        if 0 <= ii < self.nx and 0 <= jj < self.ny and land[jj * self.nx + ii]:
                            d = di * di + dj * dj
                            if best is None or d < best[0]:
                                best = (d, jj * self.nx + ii)
                assert best is not None, f"{self.id}: {t['name']} is at sea"
                c = best[1]
            t["cell"] = c
        cells = [t["cell"] for t in self.towns]
        assert len(set(cells)) == len(cells), f"{self.id}: two towns in one cell"

    def clean_land(self):
        """Tiny islets go under water, tiny ponds and inlets fill in."""
        town_cells = {t["cell"] for t in self.towns}
        min_island = self.spec.get("min_island", 40)
        for comp in self.components(lambda c: self.land[c]):
            if len(comp) < min_island and not town_cells.intersection(comp):
                for c in comp:
                    self.land[c] = False
        nx, ny = self.nx, self.ny
        for comp in self.components(lambda c: not self.land[c]):
            touches_edge = any(c % nx in (0, nx - 1) or c // nx in (0, ny - 1) for c in comp)
            if len(comp) < 12 and not touches_edge:
                for c in comp:
                    self.land[c] = True

    # ----- 2. regions grow from their towns ------------------------------------------------

    def noise_field(self, spacing, seed):
        rng = random.Random(seed)
        gx, gy = self.nx // spacing + 2, self.ny // spacing + 2
        lattice = [[rng.random() for _ in range(gx)] for _ in range(gy)]
        field = [0.0] * (self.nx * self.ny)
        for j in range(self.ny):
            fy = j / spacing
            y0 = int(fy)
            ty = fy - y0
            ty = ty * ty * (3 - 2 * ty)
            for i in range(self.nx):
                fx = i / spacing
                x0 = int(fx)
                tx = fx - x0
                tx = tx * tx * (3 - 2 * tx)
                a = lattice[y0][x0] + (lattice[y0][x0 + 1] - lattice[y0][x0]) * tx
                b = lattice[y0 + 1][x0] + (lattice[y0 + 1][x0 + 1] - lattice[y0 + 1][x0]) * tx
                field[j * self.nx + i] = a + (b - a) * ty
        return field

    def grow(self):
        n = self.nx * self.ny
        coarse = self.noise_field(9, self.rng.random())
        fine = self.noise_field(3, self.rng.random())
        cost = [self.g * (0.55 + 0.9 * coarse[c] + 0.3 * fine[c]) for c in range(n)]
        cutoff = self.spec.get("cutoff", 1e9) * self.spec["scale"]
        lab = [WATER if not self.land[c] else DECOR for c in range(n)]
        dist = [math.inf] * n
        heap = []
        for k, t in enumerate(self.towns):
            dist[t["cell"]] = 0.0
            heapq.heappush(heap, (0.0, t["cell"], k))
        done = [False] * n
        while heap:
            d, c, k = heapq.heappop(heap)
            if done[c]:
                continue
            done[c] = True
            lab[c] = k
            w = self.towns[k]["weight"]
            for m in self.neighbours4(c):
                if self.land[m] and not done[m]:
                    nd = d + (cost[c] + cost[m]) / 2 / w
                    if nd < dist[m] and nd * w <= cutoff:
                        dist[m] = nd
                        heapq.heappush(heap, (nd, m, k))
        self.lab = lab

    def smooth(self, passes=2):
        nx, ny, lab = self.nx, self.ny, self.lab
        towns = {t["cell"] for t in self.towns}
        for _ in range(passes):
            new = lab[:]
            for j in range(1, ny - 1):
                for i in range(1, nx - 1):
                    c = j * nx + i
                    if lab[c] < 0 or c in towns:
                        continue
                    counts = {}
                    for dj in (-1, 0, 1):
                        for di in (-1, 0, 1):
                            if di or dj:
                                l = lab[c + dj * nx + di]
                                if l >= 0:
                                    counts[l] = counts.get(l, 0) + 1
                    best = max(counts, key=counts.get) if counts else lab[c]
                    if best != lab[c] and counts[best] >= 5:
                        new[c] = best
            self.lab = lab = new

    def reconnect(self):
        """Each region keeps the piece holding its town; stray pieces join the area they touch most."""
        lab = self.lab
        changed = True
        while changed:
            changed = False
            keep = [False] * len(lab)
            for k, t in enumerate(self.towns):
                stack = [t["cell"]]
                keep[t["cell"]] = True
                while stack:
                    c = stack.pop()
                    for m in self.neighbours4(c):
                        if not keep[m] and lab[m] == k:
                            keep[m] = True
                            stack.append(m)
            stray = lambda c: lab[c] >= 0 and lab[c] < len(self.towns) and not keep[c]
            for comp in self.components(stray):
                counts = {}
                inside = set(comp)
                for c in comp:
                    for m in self.neighbours4(c):
                        if m not in inside and lab[m] != WATER:
                            counts[lab[m]] = counts.get(lab[m], 0) + 1
                target = max(counts, key=counts.get) if counts else DECOR
                for c in comp:
                    lab[c] = target
                changed = True

    def split_scenery(self):
        """Unclaimed land: one scenery area per connected piece; small slivers join a region."""
        lab = self.lab
        nreg = len(self.towns)
        self.scenery_labels = []
        for comp in self.components(lambda c: lab[c] == DECOR or lab[c] >= nreg):
            counts = {}
            inside = set(comp)
            for c in comp:
                for m in self.neighbours4(c):
                    if m not in inside and 0 <= lab[m] < nreg:
                        counts[lab[m]] = counts.get(lab[m], 0) + 1
            if counts and len(comp) < 30:
                target = max(counts, key=counts.get)
            else:
                target = nreg + len(self.scenery_labels)
                self.scenery_labels.append(target)
            for c in comp:
                lab[c] = target

    def unpinch(self):
        """No area may touch itself only at a corner: fill one of the two other cells."""
        nx, ny, lab = self.nx, self.ny, self.lab
        towns = {t["cell"] for t in self.towns}
        changed = 0
        for j in range(ny - 1):
            for i in range(nx - 1):
                a = j * nx + i
                b, c, d = a + 1, a + nx, a + nx + 1
                for p, q, r, s in ((a, d, b, c), (b, c, a, d)):
                    if lab[p] == lab[q] and lab[p] >= 0 and lab[r] != lab[p] and lab[s] != lab[p]:
                        target = r if r not in towns else s
                        if lab[target] == WATER:
                            self.land[target] = True
                        lab[target] = lab[p]
                        changed += 1
        return changed

    def fill_holes(self):
        """An area completely inside one other area (a lake, a scrap) is filled by it."""
        nx, ny, lab = self.nx, self.ny, self.lab
        nreg = len(self.towns)
        changed = 0
        seen = [False] * (nx * ny)
        for start in range(nx * ny):
            if seen[start]:
                continue
            l = lab[start]
            comp = [start]
            seen[start] = True
            k = 0
            border = set()
            on_edge = False
            while k < len(comp):
                c = comp[k]
                i, j = c % nx, c // nx
                if i in (0, nx - 1) or j in (0, ny - 1):
                    on_edge = True
                for m in self.neighbours4(c):
                    if lab[m] == l:
                        if not seen[m]:
                            seen[m] = True
                            comp.append(m)
                    else:
                        border.add(lab[m])
                k += 1
            if not on_edge and len(border) == 1:
                outer = border.pop()
                if outer >= 0:
                    if 0 <= l < nreg:
                        raise SystemExit(f"{self.id}: {self.towns[l]['name']} is an enclave inside {self.area_name(outer)}")
                    for c in comp:
                        lab[c] = outer
                        self.land[c] = True
                    changed += 1
        return changed

    def area_name(self, l):
        return self.towns[l]["name"] if 0 <= l < len(self.towns) else f"scenery {l}"

    def fix(self):
        for _ in range(30):
            changes = self.unpinch()
            self.reconnect()
            changes += self.fill_holes()
            if changes == 0:
                return
        raise SystemExit(f"{self.id}: shapes didn't settle")

    # ----- 3. trace borders ----------------------------------------------------------------

    def label(self, i, j):
        if 0 <= i < self.nx and 0 <= j < self.ny:
            return self.lab[j * self.nx + i]
        return OUT

    def trace(self):
        nx, ny = self.nx, self.ny
        adj = {}

        def add(p, q, pair):
            adj.setdefault(p, []).append((q, pair))
            adj.setdefault(q, []).append((p, pair))

        for cj in range(ny + 1):
            for ci in range(nx):
                a, b = self.label(ci, cj - 1), self.label(ci, cj)
                if a != b and max(a, b) >= 0:
                    add((ci, cj), (ci + 1, cj), (min(a, b), max(a, b)))
        for cj in range(ny):
            for ci in range(nx + 1):
                a, b = self.label(ci - 1, cj), self.label(ci, cj)
                if a != b and max(a, b) >= 0:
                    add((ci, cj), (ci, cj + 1), (min(a, b), max(a, b)))
        nodes = set()
        for p, edges in adj.items():
            ci, cj = p
            labels = {self.label(ci - 1, cj - 1), self.label(ci, cj - 1), self.label(ci - 1, cj), self.label(ci, cj)}
            if len(labels) >= 3 or len(edges) != 2:
                nodes.add(p)
        visited = set()
        chains = []

        def walk(start, first, pair):
            pts = [start, first]
            visited.add(frozenset((start, first)))
            prev, cur = start, first
            while cur not in nodes and cur != start:
                options = [(q, pr) for q, pr in adj[cur] if q != prev and frozenset((cur, q)) not in visited]
                assert len(options) == 1 and options[0][1] == pair, f"{self.id}: tracing broke at {cur}"
                q = options[0][0]
                visited.add(frozenset((cur, q)))
                pts.append(q)
                prev, cur = cur, q
            return pts

        for node in sorted(nodes):
            for q, pair in adj[node]:
                if frozenset((node, q)) not in visited:
                    chains.append({"pair": pair, "corners": walk(node, q, pair)})
        for p in sorted(adj):
            for q, pair in adj[p]:
                if frozenset((p, q)) not in visited:
                    nodes.add(p)
                    chains.append({"pair": pair, "corners": walk(p, q, pair), "loop": True})
        self.nodes = nodes
        self.chains = chains

    def shape_chains(self):
        g = self.g
        for chain in self.chains:
            pts = [(ci * g, cj * g) for ci, cj in chain["corners"]]
            if OUT in chain["pair"]:
                chain["points"] = simplify(pts, 0.5)
                continue
            for _ in range(3):
                pts = chaikin(pts)
            chain["points"] = simplify(pts, self.spec.get("tolerance", 1.3))

    # ----- 4. the map file -----------------------------------------------------------------

    def assemble(self):
        vertices = {}
        node_ids = {}
        counter = [0]

        def new_id(point):
            counter[0] += 1
            vid = f"p{counter[0]}"
            vertices[vid] = [round(point[0], 1), round(point[1], 1)]
            return vid

        for chain in self.chains:
            ids = []
            corners = chain["corners"]
            pts = chain["points"]
            for k, p in enumerate(pts):
                if k == 0 or k == len(pts) - 1:
                    corner = corners[0] if k == 0 else corners[-1]
                    if corner not in node_ids:
                        node_ids[corner] = new_id(p)
                    ids.append(node_ids[corner])
                else:
                    ids.append(new_id(p))
            chain["ids"] = ids
        self.vertices = vertices

        areas = {}
        for chain in self.chains:
            for l in chain["pair"]:
                if l >= 0:
                    areas.setdefault(l, []).append(chain)
        polygons = {}
        for l, chains in areas.items():
            loops = [c for c in chains if c.get("loop")]
            opens = [c for c in chains if not c.get("loop")]
            rings = []
            for c in loops:
                rings.append(c["ids"][:-1])
            by_end = {}
            for c in opens:
                by_end.setdefault(c["ids"][0], []).append(c)
                by_end.setdefault(c["ids"][-1], []).append(c)
            used = set()
            for c in opens:
                if id(c) in used:
                    continue
                ring = list(c["ids"])
                used.add(id(c))
                while ring[-1] != ring[0]:
                    nxt = [d for d in by_end[ring[-1]] if id(d) not in used]
                    assert len(nxt) == 1, f"{self.id}: {self.area_name(l)} has a broken outline"
                    d = nxt[0]
                    used.add(id(d))
                    ring.extend(d["ids"][1:] if d["ids"][0] == ring[-1] else list(reversed(d["ids"]))[1:])
                rings.append(ring[:-1])
            if len(rings) != 1:
                raise SystemExit(f"{self.id}: {self.area_name(l)} has {len(rings)} outlines (a hole?)")
            polygons[l] = rings[0]
        self.polygons = polygons

        nreg = len(self.towns)
        self.neigh = {k: set() for k in range(nreg)}
        self.coastal = set()
        for chain in self.chains:
            a, b = chain["pair"]
            if 0 <= a < nreg and 0 <= b < nreg:
                self.neigh[a].add(b)
                self.neigh[b].add(a)
            if a == WATER and 0 <= b < nreg:
                self.coastal.add(b)

    def points_of(self, l):
        return [self.vertices[v] for v in self.polygons[l]]

    def port_spots(self):
        """For each coastal region, a spot in the water off its coast for the boat."""
        nx, lab = self.nx, self.lab
        nreg = len(self.towns)
        owner = {}
        dist = {}
        queue = deque()
        for c in range(nx * self.ny):
            if lab[c] == WATER:
                for m in self.neighbours4(c):
                    if 0 <= lab[m] < nreg:
                        owner[c] = lab[m]
                        dist[c] = 1
                        queue.append(c)
                        break
        while queue:
            c = queue.popleft()
            for m in self.neighbours4(c):
                if lab[m] == WATER and m not in dist:
                    dist[m] = dist[c] + 1
                    owner[m] = owner[c]
                    queue.append(m)
        self.water_owner, self.water_dist = owner, dist
        partners = {}
        for a, b in self.spec.get("sea_links", []):
            partners.setdefault(to_id(a), []).append(to_id(b))
            partners.setdefault(to_id(b), []).append(to_id(a))
        index = {t["id"]: k for k, t in enumerate(self.towns)}
        g = self.g
        want = max(3, round(30 / g))
        spots = {}
        for k, t in enumerate(self.towns):
            if k not in self.coastal or not ({"port"} & t["flags"] or t["id"] in partners):
                continue
            if t["id"] in partners:
                tx = sum(self.towns[index[p]]["xy"][0] for p in partners[t["id"]]) / len(partners[t["id"]])
                ty = sum(self.towns[index[p]]["xy"][1] for p in partners[t["id"]]) / len(partners[t["id"]])
                # Aim at the partner but stay near home: the spot nearest a point a little way out.
                hx, hy = t["xy"]
                tx, ty = hx + (tx - hx) * 0.35, hy + (ty - hy) * 0.35
            else:
                tx, ty = t["xy"]
            best = None
            for c, o in owner.items():
                if o != k or not (want - 1 <= dist[c] <= want + 1):
                    continue
                x, y = (c % nx + 0.5) * g, (c // nx + 0.5) * g
                if x < 24 or y < 24 or x > self.proj.width - 24 or y > self.proj.height - 24:
                    continue
                d = (x - tx) ** 2 + (y - ty) ** 2
                if best is None or d < best[0]:
                    best = (d, x, y)
            if best is None:
                self.warn(f"no room for a boat off {t['name']}")
                continue
            spots[k] = [round(best[1]), round(best[2])]
        self.ports = spots
        # Second look for ports with links: the spot whose lines to the partners' boats cross the least land.
        for k, t in enumerate(self.towns):
            if k not in spots or t["id"] not in partners:
                continue
            others = [spots[index[p]] for p in partners[t["id"]] if index[p] in spots]
            best = None
            for c, o in owner.items():
                if o != k or not (want - 1 <= dist[c] <= want + 2):
                    continue
                x, y = (c % nx + 0.5) * g, (c // nx + 0.5) * g
                if x < 24 or y < 24 or x > self.proj.width - 24 or y > self.proj.height - 24:
                    continue
                crossing = sum(self.land_on_line((x, y), other) for other in others)
                score = crossing * 10000 + math.hypot(x - t["xy"][0], y - t["xy"][1])
                if best is None or score < best[0]:
                    best = (score, x, y)
            spots[k] = [round(best[1]), round(best[2])]

    def land_on_line(self, a, b):
        (x0, y0), (x1, y1) = a, b
        steps = int(math.hypot(x1 - x0, y1 - y0) / self.g) + 1
        on_land = 0
        for s in range(steps + 1):
            x = x0 + (x1 - x0) * s / steps
            y = y0 + (y1 - y0) * s / steps
            if self.lab[int(y / self.g) * self.nx + int(x / self.g)] != WATER:
                on_land += 1
        return on_land

    def check_links(self):
        index = {t["id"]: k for k, t in enumerate(self.towns)}
        links = []
        for a, b in self.spec.get("sea_links", []):
            ka, kb = index[to_id(a)], index[to_id(b)]
            assert ka in self.ports and kb in self.ports, f"{self.id}: sea link {a}-{b} needs two ports"
            links.append((ka, kb))
            on_land = self.land_on_line(self.ports[ka], self.ports[kb])
            if on_land > 2:
                self.warn(f"sea link {a}-{b} crosses {on_land} land cells")
        # Everything reachable by land or sea.
        graph = {k: set(v) for k, v in self.neigh.items()}
        for a, b in links:
            graph[a].add(b)
            graph[b].add(a)
        seen = {0}
        queue = deque([0])
        while queue:
            c = queue.popleft()
            for m in graph[c]:
                if m not in seen:
                    seen.add(m)
                    queue.append(m)
        cut_off = [self.towns[k]["name"] for k in range(len(self.towns)) if k not in seen]
        if cut_off:
            raise SystemExit(f"{self.id}: can't reach {cut_off}")
        self.links = links

    def check_labels(self):
        rects = []
        self.centroids = {}
        for k, t in enumerate(self.towns):
            pts = self.points_of(k)
            cx, cy = centroid(pts)
            self.centroids[k] = (cx, cy)
            if not point_in_polygon(cx, cy, pts):
                self.warn(f"{t['name']}: centre lies outside the region")
            margin = distance_to_outline(cx, cy, pts)
            if margin < 22:
                self.warn(f"{t['name']}: centre only {margin:.0f}px from the border")
            half = max(62, len(t["name"]) * 4.6 + 8)
            rects.append((cx - half, cy - 62, cx + half, cy + 54))
        for a in range(len(rects)):
            for b in range(a + 1, len(rects)):
                ra, rb = rects[a], rects[b]
                if ra[0] < rb[2] and rb[0] < ra[2] and ra[1] < rb[3] and rb[1] < ra[3]:
                    ox = min(ra[2], rb[2]) - max(ra[0], rb[0])
                    oy = min(ra[3], rb[3]) - max(ra[1], rb[1])
                    self.warn(f"crowded: {self.towns[a]['name']} / {self.towns[b]['name']} ({ox:.0f}x{oy:.0f}px)")
        for k, t in enumerate(self.towns):
            area = polygon_area(self.points_of(k))
            if area < 9000:
                self.warn(f"{t['name']}: small region ({area:.0f}px²)")

    def write(self):
        spec = self.spec
        regions = []
        for k, t in enumerate(self.towns):
            region = {
                "id": t["id"], "name": t["name"], "terrain": t["terrain"],
                "population": POPULATION[t["income"]] + self.rng.randrange(-5, 6) * 100,
                "income": t["income"], "coastal": k in self.coastal,
            }
            for site in ("town", "camp"):
                if site in t["flags"]:
                    region["site"] = site
            if "fortress" in t["flags"]:
                region["fortress"] = True
            if k in self.ports:
                region["port"] = True
                region["port_at"] = self.ports[k]
            region["town_at"] = [round(t["xy"][0]), round(t["xy"][1])]
            region["vertices"] = self.polygons[k]
            region["neighbours"] = sorted(self.towns[m]["id"] for m in self.neigh[k])
            regions.append(region)
        labels = []
        for entry in spec.get("sea_labels", []):
            text, lat, lon = entry[:3]
            size = entry[3] if len(entry) > 3 else 30
            angle = entry[4] if len(entry) > 4 else 0
            x, y = self.proj(lon, lat)
            label = {"text": text, "at": [round(x), round(y)], "size": size, "angle": angle}
            if len(entry) > 5 and entry[5] == "land":
                label["land"] = True
            else:
                c = int(y / self.g) * self.nx + int(x / self.g)
                if self.lab[c] != WATER:
                    self.warn(f"sea label {text} sits on land")
            labels.append(label)
        history = spec["history"]
        owners = {t["id"]: t["owner"] for t in self.towns}
        capitals = {}
        for t in self.towns:
            if "capital" in t["flags"]:
                assert t["owner"] not in capitals, f"{self.id}: two capitals for {t['owner']}"
                capitals[t["owner"]] = t["id"]
        factions = [dict(f) for f in history["factions"]]
        for f in factions:
            assert f["id"] in capitals, f"{self.id}: {f['id']} has no capital"
        buildings = {t["id"]: {"walls": 1} for t in self.towns if "fortress" in t["flags"]}
        # Skirmish starts: each faction's capital, or (on an island) its region with the most land
        # neighbours, since a skirmish player also takes two neighbouring regions.
        index = {t["id"]: k for k, t in enumerate(self.towns)}
        starts = []
        for f in factions[:4]:
            start = capitals[f["id"]]
            if len(self.neigh[index[start]]) < 2:
                own = [k for k, t in enumerate(self.towns) if t["owner"] == f["id"]]
                start = self.towns[max(own, key=lambda k: len(self.neigh[k]))]["id"]
            starts.append(start)
        data = {
            "id": self.id, "name": spec["name"], "size": [self.proj.width, self.proj.height], "coast": [],
            "starts": starts,
            "source": "Coastlines: Natural Earth 1:10m (public domain). Towns and borders: drawn for this game.",
            "history": {"year": history["year"], "title": history["title"], "factions": factions,
                        "owners": owners, "capitals": capitals, "buildings": buildings},
            "sea_links": [[self.towns[a]["id"], self.towns[b]["id"]] for a, b in self.links],
            "sea_labels": labels,
            "vertices": self.vertices,
            "regions": regions,
            "scenery": [{"vertices": self.polygons[l]} for l in self.scenery_labels if l in self.polygons],
            "borders": [],
        }
        text = json.dumps(data, indent=1, ensure_ascii=False)
        text = re.sub(r"\[\s+([^\[\]\{\}]*?)\s+\]", lambda m: "[" + re.sub(r"\s*\n\s*", " ", m.group(1)) + "]", text)
        with open(os.path.join(ROOT, "data", "maps", self.id + ".json"), "w") as f:
            f.write(text + "\n")
        print(f"{self.id}: {len(regions)} regions, {self.proj.width}x{self.proj.height}px, "
              f"{len(self.vertices)} vertices, {len(data['scenery'])} scenery areas, {len(self.links)} sea links, "
              f"starts {starts}")

    def build(self):
        print(f"{self.id} ...")
        self.rasterize()
        self.place_towns()
        self.clean_land()
        self.grow()
        self.smooth()
        self.reconnect()
        self.split_scenery()
        self.fix()
        self.trace()
        self.shape_chains()
        self.assemble()
        self.port_spots()
        self.check_links()
        self.check_labels()
        self.write()


def chaikin(pts):
    if len(pts) < 3:
        return pts
    out = [pts[0]]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        out.append((0.75 * x0 + 0.25 * x1, 0.75 * y0 + 0.25 * y1))
        out.append((0.25 * x0 + 0.75 * x1, 0.25 * y0 + 0.75 * y1))
    out.append(pts[-1])
    return out


def simplify(pts, tolerance):
    """Douglas-Peucker with fixed ends (a closed chain has the same point at both ends)."""
    if len(pts) < 3:
        return pts
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    if pts[0] == pts[-1]:
        far = max(range(len(pts)), key=lambda i: (pts[i][0] - pts[0][0]) ** 2 + (pts[i][1] - pts[0][1]) ** 2)
        keep[far] = True
        stack = [(0, far), (far, len(pts) - 1)]
    else:
        stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        if b - a < 2:
            continue
        ax, ay = pts[a]
        bx, by = pts[b]
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy)
        worst, at = -1.0, -1
        for i in range(a + 1, b):
            px, py = pts[i]
            if length < 1e-9:
                d = math.hypot(px - ax, py - ay)
            else:
                d = abs(dy * (px - ax) - dx * (py - ay)) / length
            if d > worst:
                worst, at = d, i
        if worst > tolerance:
            keep[at] = True
            stack.append((a, at))
            stack.append((at, b))
    return [p for p, k in zip(pts, keep) if k]


def polygon_area(pts):
    return abs(sum(pts[i - 1][0] * p[1] - p[0] * pts[i - 1][1] for i, p in enumerate(pts))) / 2


def centroid(pts):
    a = cx = cy = 0.0
    for i, (x1, y1) in enumerate(pts):
        x0, y0 = pts[i - 1]
        cross = x0 * y1 - x1 * y0
        a += cross
        cx += (x0 + x1) * cross
        cy += (y0 + y1) * cross
    return cx / (3 * a), cy / (3 * a)


def point_in_polygon(x, y, pts):
    inside = False
    for i, (x1, y1) in enumerate(pts):
        x0, y0 = pts[i - 1]
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            inside = not inside
    return inside


def distance_to_outline(x, y, pts):
    best = math.inf
    for i, (x1, y1) in enumerate(pts):
        x0, y0 = pts[i - 1]
        dx, dy = x1 - x0, y1 - y0
        t = 0.0 if dx == dy == 0 else max(0.0, min(1.0, ((x - x0) * dx + (y - y0) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(x - x0 - t * dx, y - y0 - t * dy))
    return best


if __name__ == "__main__":
    wanted = sys.argv[1:]
    for spec in MAPS:
        if not wanted or spec["id"] in wanted:
            Builder(spec).build()
