#!/usr/bin/env python3
"""Clip a GTFS feed to a polygon (e.g. the City of Manila boundary).

Usage:
  python3 clip_gtfs.py <gtfs_in_dir> <boundary.geojson> <gtfs_out_dir>

Rules
  * A stop is kept only if it lies inside the polygon.
  * Each trip is cut into runs of consecutive inside-stops. Every run with
    2+ stops becomes its own trip (suffix _a, _b ...), so the planner never
    sees a fake direct ride across a gap outside the city.
  * Stop times are re-based so each run starts at 00:00:00.
  * Shapes are cut to the part inside the polygon.
  * Routes/services/agencies/stops/shapes that end up unused are removed.
"""
import csv, json, sys, os, collections

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

def main(src, boundary, dst):
    inside = make_inside(json.load(open(boundary)))
    os.makedirs(dst, exist_ok=True)
    sf, stops = load(src, "stops")
    sin = {s["stop_id"] for s in stops if inside(float(s["stop_lat"]), float(s["stop_lon"]))}
    ff, trips = load(src, "trips"); stf, st = load(src, "stop_times")
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
    print(f"stops {len(stops)} -> {len(new_stops)} (inside polygon: {len(sin)})")
    print(f"routes {len(routes)} -> {len(new_routes)}; trips {len(trips)} -> {len(new_trips)}")
    print(f"stop_times {len(st)} -> {len(new_st)}; shapes kept {len(shape_ok)}/{len(sh)}")
    print(dict(stats))

if __name__ == "__main__":
    if len(sys.argv) != 4: sys.exit(__doc__)
    main(*sys.argv[1:])