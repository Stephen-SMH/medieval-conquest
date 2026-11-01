"""Generates the campaign maps in data/maps/ (PRD CP-1: 12-20 regions each).

Regions start as cells of a jittered brick layout (each cell touches up to 6
others), then some neighbouring cells are merged so regions differ in size.
Vertices are shared between neighbouring regions, so borders never have gaps.

    python3 tools/make_maps.py
"""

import json
import random
import re
import unicodedata
from collections import deque

WIDTH, HEIGHT = 1200, 700
TERRAINS = ["plains", "plains", "plains", "forest", "forest", "hills", "hills", "mountains", "marsh"]


def make_map(map_id, name, cols, rows, target, seed, coast, names, rivers=2, roads=4):
    rng = random.Random(seed)
    step_x = WIDTH / (2 * cols)
    step_y = HEIGHT / rows

    # Vertices on each row boundary r at every half-cell step k.
    vertices = {}
    for r in range(rows + 1):
        for k in range(2 * cols + 1):
            x = k * step_x
            y = r * step_y
            if 0 < k < 2 * cols:
                x += rng.uniform(-0.22, 0.22) * step_x
            if 0 < r < rows:
                y += rng.uniform(-0.18, 0.18) * step_y
            vertices[f"v{r}_{k}"] = [round(x), round(y)]

    # Cells: even rows have `cols` cells, odd rows `cols - 1` (wider at the ends).
    cells = []
    for r in range(rows):
        if r % 2 == 0:
            bounds = list(range(0, 2 * cols + 1, 2))
        else:
            bounds = [0] + list(range(3, 2 * cols - 2, 2)) + [2 * cols]
        for a, b in zip(bounds, bounds[1:]):
            top = [f"v{r}_{k}" for k in range(a, b + 1)]
            bottom = [f"v{r + 1}_{k}" for k in range(b, a - 1, -1)]
            cells.append({"row": r, "span": (a, b), "polygon": top + bottom})

    def edges(polygon):
        return [(polygon[i], polygon[(i + 1) % len(polygon)]) for i in range(len(polygon))]

    def cell_neighbours():
        owner = {}
        for i, cell in enumerate(cells):
            for u, v in edges(cell["polygon"]):
                owner.setdefault(frozenset((u, v)), []).append(i)
        pairs = set()
        for shared in owner.values():
            if len(shared) == 2:
                pairs.add(tuple(sorted(shared)))
        return pairs

    # Merge random neighbouring pairs of single cells until we reach the target count.
    groups = [[i] for i in range(len(cells))]
    group_of = list(range(len(cells)))
    pairs = sorted(cell_neighbours())
    rng.shuffle(pairs)
    for a, b in pairs:
        if len(groups) - sum(1 for g in groups if not g) <= target:
            break
        ga, gb = group_of[a], group_of[b]
        if ga == gb or len(groups[ga]) > 1 or len(groups[gb]) > 1:
            continue
        groups[ga].extend(groups[gb])
        for c in groups[gb]:
            group_of[c] = ga
        groups[gb] = []
    groups = [g for g in groups if g]

    # Each region's outline: the directed cell edges that aren't shared inside the region.
    regions = []
    for g in groups:
        directed = []
        for c in g:
            directed.extend(edges(cells[c]["polygon"]))
        inner = set(directed)
        outline = [(u, v) for u, v in directed if (v, u) not in inner]
        after = {u: v for u, v in outline}
        start = outline[0][0]
        polygon = [start]
        while after[polygon[-1]] != start:
            polygon.append(after[polygon[-1]])
        regions.append({"cells": g, "vertices": polygon})

    # Neighbours share at least one edge.
    edge_regions = {}
    for i, region in enumerate(regions):
        for u, v in edges(region["vertices"]):
            edge_regions.setdefault(frozenset((u, v)), set()).add(i)
    neighbours = {i: set() for i in range(len(regions))}
    for shared in edge_regions.values():
        if len(shared) == 2:
            a, b = sorted(shared)
            neighbours[a].add(b)
            neighbours[b].add(a)

    def on_side(vertex, side):
        x, y = vertices[vertex]
        return {"top": y == 0, "bottom": y == HEIGHT, "left": x == 0, "right": x == WIDTH}[side]

    def to_id(region_name):
        plain = unicodedata.normalize("NFKD", region_name.replace("ø", "o")).encode("ascii", "ignore").decode()
        return re.sub(r"[^a-z]+", "_", plain.lower()).strip("_")

    ids = [to_id(n) for n in names[: len(regions)]]
    assert len(ids) == len(regions), f"{map_id}: need {len(regions)} names, have {len(names)}"
    out_regions = []
    for i, region in enumerate(regions):
        coastal = any(
            on_side(u, side) and on_side(v, side) for u, v in edges(region["vertices"]) for side in coast
        )
        out_regions.append({
            "id": ids[i], "name": names[i], "terrain": rng.choice(TERRAINS),
            "population": rng.randrange(5000, 16001, 100), "coastal": coastal,
            "vertices": region["vertices"], "neighbours": sorted(ids[j] for j in neighbours[i]),
        })

    # Start slots: spread out by graph distance (farthest-point sampling).
    def distances(start):
        dist = {start: 0}
        queue = deque([start])
        while queue:
            current = queue.popleft()
            for nxt in neighbours[current]:
                if nxt not in dist:
                    dist[nxt] = dist[current] + 1
                    queue.append(nxt)
        return dist

    starts = [0]
    while len(starts) < 4:
        best = max(range(len(regions)), key=lambda i: min(distances(s)[i] for s in starts))
        starts.append(best)
    # Towns and camps, where mercenaries can be hired: about one region in four.
    for i, region in enumerate(out_regions):
        if i not in starts and rng.random() < 0.28:
            region["site"] = "town" if rng.random() < 0.5 else "camp"
    # At least three, so every map has somewhere to hire mercenaries.
    by_people = sorted((i for i in range(len(out_regions)) if i not in starts), key=lambda i: -out_regions[i]["population"])
    for n, i in enumerate(by_people):
        if sum(1 for r in out_regions if r.get("site")) >= 3:
            break
        out_regions[i].setdefault("site", "town" if n % 2 == 0 else "camp")
    for s in starts:
        out_regions[s]["terrain"] = "plains"
        out_regions[s]["population"] = max(out_regions[s]["population"], 13000)

    # Rivers along a few connected borders, roads out of each start.
    borders = []
    used = set()
    for _ in range(rivers):
        a = rng.randrange(len(regions))
        for _ in range(rng.randint(2, 3)):
            options = [b for b in neighbours[a] if frozenset((a, b)) not in used]
            if not options:
                break
            b = rng.choice(options)
            used.add(frozenset((a, b)))
            borders.append({"between": [ids[a], ids[b]], "type": "river"})
            a = b
    for s in starts[:roads]:
        options = [b for b in neighbours[s] if frozenset((s, b)) not in used]
        if options:
            b = rng.choice(options)
            used.add(frozenset((s, b)))
            borders.append({"between": [ids[s], ids[b]], "type": "road"})

    data = {
        "id": map_id, "name": name, "size": [WIDTH, HEIGHT], "coast": coast,
        "starts": [ids[s] for s in starts], "vertices": vertices, "regions": out_regions, "borders": borders,
    }
    text = json.dumps(data, indent=1, ensure_ascii=False)
    text = re.sub(r"\[\s+([^\[\]\{\}]*?)\s+\]", lambda m: "[" + re.sub(r"\s*\n\s*", " ", m.group(1)) + "]", text)
    with open(f"data/maps/{map_id}.json", "w") as f:
        f.write(text + "\n")
    print(f"{map_id}: {len(regions)} regions, starts {[ids[s] for s in starts]}")


make_map("fjordmark", "The Fjordmark", 5, 4, 16, 41, ["top", "left"], [
    "Skarholm", "Ravensfjord", "Ulvdal", "Kaldvik", "Hrafnsey", "Brimstad", "Sølvbekk", "Tornfjell",
    "Ashwick", "Morrow Fen", "Calder Abbey", "Hollin", "Wyrmsby", "Greyhaven", "Stonereach", "Elmsworth", "Ferrow",
])
make_map("wealdshire", "The Wealdshire", 4, 5, 15, 17, ["left", "bottom"], [
    "Kingsbarrow", "Oakhollow", "Fennick", "Wyndle", "Thornbury", "Coldmarsh", "Bramblegate", "Highwold",
    "Saltcombe", "Larkfield", "Bowmere", "Redstow", "Harrowdene", "Gullmouth", "Ashcombe", "Wexley",
])
make_map("valmont", "The Valmont", 6, 4, 18, 23, ["bottom"], [
    "Belcourt", "Rochemont", "Vaudrey", "Sainte-Aube", "Montclair", "Lorvane", "Castelroux", "Pierrefonde",
    "Auberive", "Grandval", "Marlenne", "Chaumière", "Vireux", "Port-Sable", "Brévine", "Ostrel",
    "Fontmarais", "Corlay", "Ravenne",
])
