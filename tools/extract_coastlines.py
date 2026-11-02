"""Cuts the coastlines for the real-history maps out of Natural Earth.

Natural Earth (https://www.naturalearthdata.com) is public domain. Download
ne_10m_land.geojson and ne_10m_lakes.geojson (for example from
https://github.com/nvkelso/natural-earth-vector/tree/master/geojson), then:

    python3 tools/extract_coastlines.py <ne_10m_land.geojson> <ne_10m_lakes.geojson>

For each map in BOXES this writes tools/coastlines/<map>.json: the land and
the named lakes inside the map's longitude/latitude box, simplified to about
1 km and rounded to 0.001 degrees. tools/make_real_maps.py builds the maps
from these files, so the large downloads aren't needed after this step.
"""

import json
import sys

# lon_min, lon_max, lat_min, lat_max (with room to spare), and the lakes kept as water.
BOXES = {
    "british_isles": ((-11.5, 3.5, 49.0, 60.0), ["Lough Neagh"]),
    "france": ((-6.5, 9.0, 41.5, 53.0), ["Lake Geneva", "IJsselmeer"]),
    "scandinavia": ((3.0, 24.5, 52.5, 65.5), ["Vänern", "Vättern", "Mälaren", "Hjälmaren", "Mjøsa"]),
    "levant": ((28.5, 41.5, 29.8, 39.2), ["Dead Sea", "Sea of Galilee", "Lake Tuz", "Beyşehir", "Eğirdir"]),
    "holy_roman_empire": ((3.5, 19.0, 46.0, 55.8), ["Bodensee", "Lake Geneva", "IJsselmeer", "Müritz"]),
    "livonia": ((19.5, 37.5, 53.5, 61.5), ["Lake Peipus", "Lake Pskov", "Lake Il'Men'", "Lake Ladoga"]),
}
TOLERANCE = 0.008  # degrees


def rings_of(geometry):
    if geometry["type"] == "Polygon":
        return geometry["coordinates"]
    return [ring for polygon in geometry["coordinates"] for ring in polygon]


def clip(ring, box):
    """Sutherland-Hodgman against the box. Zero-width slivers along the box
    edge can remain; they don't matter for an even-odd fill."""
    lon0, lon1, lat0, lat1 = box
    sides = [
        (lambda p: p[0] >= lon0, lambda p, q: (lon0, p[1] + (q[1] - p[1]) * (lon0 - p[0]) / (q[0] - p[0]))),
        (lambda p: p[0] <= lon1, lambda p, q: (lon1, p[1] + (q[1] - p[1]) * (lon1 - p[0]) / (q[0] - p[0]))),
        (lambda p: p[1] >= lat0, lambda p, q: (p[0] + (q[0] - p[0]) * (lat0 - p[1]) / (q[1] - p[1]), lat0)),
        (lambda p: p[1] <= lat1, lambda p, q: (p[0] + (q[0] - p[0]) * (lat1 - p[1]) / (q[1] - p[1]), lat1)),
    ]
    points = [tuple(p[:2]) for p in ring]
    for inside, cross in sides:
        if not points:
            break
        result = []
        for i, q in enumerate(points):
            p = points[i - 1]
            if inside(q):
                if not inside(p):
                    result.append(cross(p, q))
                result.append(q)
            elif inside(p):
                result.append(cross(p, q))
        points = result
    return points


def simplify(points, tolerance):
    """Douglas-Peucker on a closed ring (iterative)."""
    if len(points) < 8:
        return points
    keep = [False] * len(points)
    half = len(points) // 2
    keep[0] = keep[half] = keep[-1] = True
    stack = [(0, half), (half, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = points[a]
        bx, by = points[b]
        dx, dy = bx - ax, by - ay
        length = (dx * dx + dy * dy) ** 0.5 or 1e-12
        worst, at = 0.0, -1
        for i in range(a + 1, b):
            px, py = points[i]
            d = abs(dy * (px - ax) - dx * (py - ay)) / length
            if d > worst:
                worst, at = d, i
        if worst > tolerance:
            keep[at] = True
            stack.append((a, at))
            stack.append((at, b))
    return [p for p, k in zip(points, keep) if k]


def area(points):
    return abs(sum(points[i - 1][0] * p[1] - p[0] * points[i - 1][1] for i, p in enumerate(points))) / 2.0


def main(land_path, lakes_path):
    with open(land_path) as f:
        land = json.load(f)["features"]
    with open(lakes_path) as f:
        lakes = json.load(f)["features"]
    for map_id, (box, lake_names) in BOXES.items():
        out = {"source": "Natural Earth 1:10m land and lakes, public domain (naturalearthdata.com)",
               "box": box, "land": [], "lakes": []}
        named_lakes = [f for f in lakes if f["properties"].get("name") in lake_names]
        for key, features in (("land", land), ("lakes", named_lakes)):
            for feature in features:
                for ring in rings_of(feature["geometry"]):
                    xs = [p[0] for p in ring]
                    ys = [p[1] for p in ring]
                    if max(xs) < box[0] or min(xs) > box[1] or max(ys) < box[2] or min(ys) > box[3]:
                        continue
                    clipped = clip(ring, box)
                    if len(clipped) < 3 or area(clipped) < 0.002:
                        continue
                    simple = simplify(clipped, TOLERANCE)
                    out[key].append([[round(x, 3), round(y, 3)] for x, y in simple])
        with open(f"tools/coastlines/{map_id}.json", "w") as f:
            json.dump(out, f, separators=(",", ":"))
        print(map_id, len(out["land"]), "land rings,", sum(len(r) for r in out["land"]), "points,",
              len(out["lakes"]), "lakes")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
