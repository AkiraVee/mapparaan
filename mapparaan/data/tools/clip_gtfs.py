#!/usr/bin/env python3
"""Clip a GTFS feed to a polygon (e.g. the City of Manila boundary).

Usage:
  python3 clip_gtfs.py <gtfs_in_dir> <boundary.geojson> <gtfs_out_dir>
                       [--tolerance-m 50] [--review-csv stops_to_review.csv]
                       [--exclude-routes ROUTE_ID[,ROUTE_ID...]]

Rules
  * A stop is kept if it lies inside the polygon, or within --tolerance-m
    metres of its edge (default 50). Source coordinates are rounded to ~3
    decimals (up to ~55 m error), so a stop on the city line can land just
    outside the polygon. Use --tolerance-m 0 for a strict polygon test.
    A stop in that edge band is skipped if its name names another city
    (e.g. "..., Quezon City"): outside the polygon that label is real evidence.
    Names are never used to ADD a stop, and never to drop one inside the
    polygon (LTFRB labels many Manila stops "Quezon City" / "Caloocan").
  * Each trip is cut into runs of consecutive inside-stops. Every run with
    2+ stops becomes its own trip (suffix _a, _b ...), so the planner never
    sees a fake direct ride across a gap outside the city.
  * Stop times are re-based so each run starts at 00:00:00.
  * Shapes are cut to the part inside the polygon.
  * --exclude-routes drops whole routes first (e.g. a line that has no service in
    the city). Their stops, services, agencies and shapes go too if nothing else uses them.
  * Routes/services/agencies/stops/shapes that end up unused are removed.
"""
import argparse, csv, json, math, sys, os, collections

def load(d, n):
    p = os.path.join(d, n + ".txt")
    if not os.path.exists(p): return [], []
    with open(p, encoding="utf-8-sig", newline="") as f:
        r = csv.DictReader(f)
        return r.fieldnames, list(r)

def save(d, n, fields, rows):
    with open(os.path.join(d, n + ".txt"), "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        w.writeheader(); w.writerows(rows)

def rings_of(geom):
    polys = [geom["coordinates"]] if geom["type"] == "Polygon" else geom["coordinates"]
    return polys  # list of polygons; each = [outer, hole1, ...]

def in_ring(x, y, ring):
    ins = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i][0], ring[i][1]; xj, yj = ring[j][0], ring[j][1]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            ins = not ins
        j = i
    return ins

OTHER_CITIES = ("quezon city", "caloocan", "pasay", "makati", "mandaluyong", "san juan",
                "pasig", "taguig", "navotas", "malabon", "parañaque", "paranaque",
                "marikina", "las piñas", "las pinas", "valenzuela", "muntinlupa", "pateros")

def names_other_city(name):
    n = name.lower()
    return any(c in n for c in OTHER_CITIES)

def make_inside(geoj):
    polys = []
    for f in geoj["features"]:
        polys += rings_of(f["geometry"])
    def inside(lat, lon):
        for p in polys:
            if in_ring(lon, lat, p[0]) and not any(in_ring(lon, lat, h) for h in p[1:]):
                return True
        return False
    return inside

def make_near(geoj):
    """dist_to_edge_m(lat, lon): metres from the point to the nearest outer-ring edge."""
    rings = []
    for f in geoj["features"]:
        rings += [p[0] for p in rings_of(f["geometry"])]
    def dist(lat, lon):
        best = 1e12
        kx = 111320.0 * math.cos(math.radians(lat)); ky = 111320.0
        for ring in rings:
            for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
                ax, ay = (x1 - lon) * kx, (y1 - lat) * ky
                bx, by = (x2 - lon) * kx, (y2 - lat) * ky
                dx, dy = bx - ax, by - ay
                L = dx * dx + dy * dy
                t = 0.0 if L == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / L))
                best = min(best, math.hypot(ax + t * dx, ay + t * dy))
        return best
    return dist

def secs(t):
    h, m, s = (int(v) for v in t.split(":")); return h * 3600 + m * 60 + s

def hms(s):
    return "%02d:%02d:%02d" % (s // 3600, s % 3600 // 60, s % 60)

def runs(flags):
    out, cur = [], []
    for i, f in enumerate(flags):
        if f: cur.append(i)
        elif cur: out.append(cur); cur = []
    if cur: out.append(cur)
    return out

def main(src, boundary, dst, tolerance_m=50.0, review_csv=None, exclude_routes=()):
    geoj = json.load(open(boundary))
    inside = make_inside(geoj)
    dist_to_edge = make_near(geoj)
    os.makedirs(dst, exist_ok=True)
    sf, stops = load(src, "stops")
    sin, strict, near_kept, review = set(), 0, [], []
    for s in stops:
        lat, lon = float(s["stop_lat"]), float(s["stop_lon"])
        if inside(lat, lon):
            sin.add(s["stop_id"]); strict += 1
            continue
        d = dist_to_edge(lat, lon)
        if d <= tolerance_m and not names_other_city(s["stop_name"]):
            sin.add(s["stop_id"]); near_kept.append((s, d))
        elif d <= 250:
            review.append((s, d, "names another city" if d <= tolerance_m else f"more than {tolerance_m:g} m outside"))
    ff, trips = load(src, "trips"); stf, st = load(src, "stop_times")
    trips = [t for t in trips if t["route_id"] not in set(exclude_routes)]
    ffr, freq = load(src, "frequencies")
    by = collections.defaultdict(list)
    for x in st: by[x["trip_id"]].append(x)
    fby = collections.defaultdict(list)
    for x in freq: fby[x["trip_id"]].append(x)

    new_trips, new_st, new_freq = [], [], []
    stats = collections.Counter()
    for t in trips:
        rows = sorted(by.get(t["trip_id"], []), key=lambda r: int(r["stop_sequence"]))
        rs = runs([r["stop_id"] in sin for r in rows])
        rs = [r for r in rs if len(r) >= 2]
        if not rs: stats["trips_dropped"] += 1; continue
        if len(rs) > 1: stats["trips_split"] += 1
        for k, idx in enumerate(rs):
            tid = t["trip_id"] if len(rs) == 1 else f'{t["trip_id"]}_{chr(97 + k)}'
            nt = dict(t); nt["trip_id"] = tid; new_trips.append(nt)
            base = secs(rows[idx[0]]["arrival_time"])
            for n, i in enumerate(idx, 1):
                r = dict(rows[i]); r["trip_id"] = tid; r["stop_sequence"] = str(n)
                r["arrival_time"] = hms(secs(r["arrival_time"]) - base)
                r["departure_time"] = hms(secs(r["departure_time"]) - base)
                new_st.append(r)
            for fr in fby.get(t["trip_id"], []):
                nf = dict(fr); nf["trip_id"] = tid; new_freq.append(nf)
    stats["trips_kept"] = len(new_trips)

    # shapes
    shf, shapes = load(src, "shapes")
    sh = collections.defaultdict(list)
    for r in shapes: sh[r["shape_id"]].append(r)
    new_shapes = []; shape_ok = set()
    for sid, pts in sh.items():
        pts.sort(key=lambda r: int(r["shape_pt_sequence"]))
        rr = runs([inside(float(p["shape_pt_lat"]), float(p["shape_pt_lon"])) for p in pts])
        if not rr: continue
        best = max(rr, key=len)
        if len(best) < 2: continue
        shape_ok.add(sid)
        for n, i in enumerate(best, 1):
            p = dict(pts[i]); p["shape_pt_sequence"] = str(n); new_shapes.append(p)
    for t in new_trips:
        if t.get("shape_id") and t["shape_id"] not in shape_ok: t["shape_id"] = ""
    used_shapes = {t["shape_id"] for t in new_trips if t.get("shape_id")}
    new_shapes = [p for p in new_shapes if p["shape_id"] in used_shapes]   # drop shapes no kept trip uses

    used_stops = {r["stop_id"] for r in new_st}
    new_stops = [s for s in stops if s["stop_id"] in used_stops]
    rf, routes = load(src, "routes")
    used_routes = {t["route_id"] for t in new_trips}
    new_routes = [r for r in routes if r["route_id"] in used_routes]
    af, agencies = load(src, "agency")
    used_ag = {r["agency_id"] for r in new_routes}
    new_ag = [a for a in agencies if a["agency_id"] in used_ag] or agencies
    cf, cal = load(src, "calendar")
    used_sv = {t["service_id"] for t in new_trips}
    new_cal = [c for c in cal if c["service_id"] in used_sv]

    save(dst, "agency", af, new_ag); save(dst, "routes", rf, new_routes)
    save(dst, "trips", ff, new_trips); save(dst, "stops", sf, new_stops)
    save(dst, "stop_times", stf, new_st); save(dst, "frequencies", ffr, new_freq)
    save(dst, "calendar", cf, new_cal)
    if shf: save(dst, "shapes", shf, new_shapes)
    for n in ("feed_info", "LICENSE", "README"):
        for ext in (".txt", ".md"):
            p = os.path.join(src, n + ext)
            if os.path.exists(p):
                open(os.path.join(dst, n + ext), "wb").write(open(p, "rb").read())
    print(f"stops {len(stops)} -> {len(new_stops)} (inside polygon: {strict}, "
          f"kept by {tolerance_m:g} m edge tolerance: {len(near_kept)})")
    for s_, d in sorted(near_kept, key=lambda x: x[1]):
        print(f"  + {d:3.0f} m outside  {s_['stop_id']:12} {s_['stop_name']}")
    if review_csv:
        with open(review_csv, "w", encoding="utf-8", newline="") as f:
            w = csv.writer(f); w.writerow(["stop_id", "stop_name", "lat", "lon", "meters_outside", "excluded_because"])
            for s_, d, why in sorted(review, key=lambda x: x[1]):
                w.writerow([s_["stop_id"], s_["stop_name"], s_["stop_lat"], s_["stop_lon"], round(d), why])
        print(f"stops 'within 250 m outside, not kept' written to {review_csv} ({len(review)})")
    print(f"routes {len(routes)} -> {len(new_routes)}; trips {len(trips)} -> {len(new_trips)}")
    print(f"stop_times {len(st)} -> {len(new_st)}; shapes kept {len(shape_ok)}/{len(sh)}")
    print(dict(stats))

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("gtfs_in"); ap.add_argument("boundary"); ap.add_argument("gtfs_out")
    ap.add_argument("--tolerance-m", type=float, default=50.0)
    ap.add_argument("--review-csv", default=None)
    ap.add_argument("--exclude-routes", default="", help="comma-separated route_ids to drop entirely")
    a = ap.parse_args()
    main(a.gtfs_in, a.boundary, a.gtfs_out, a.tolerance_m, a.review_csv, [r for r in a.exclude_routes.split(",") if r])