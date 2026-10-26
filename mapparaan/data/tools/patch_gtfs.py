#!/usr/bin/env python3
"""
Build Mapparaan's transit data folder from the original Sakay.ph GTFS feed.

Usage
  python3 patch_gtfs.py <original_gtfs_folder> <data_root> [boundary.geojson]
Example
  python3 patch_gtfs.py gtfs-master data data/reference/manila_boundary.geojson

If a boundary is given, the feed is first clipped to it with clip_gtfs.py
(stops outside are dropped, trips are cut at the boundary). raw/ always keeps
the full untouched feed.

Resulting layout (original files are never modified):

  data/
  ├── raw/sakay_gtfs/          untouched copy of the source feed (+ LICENSE.md)
  ├── gtfs/                    patched, standard GTFS files only
  ├── reference/
  │   ├── route_modes.csv      route_id -> jeepney / bus / lrt1 / ...
  │   ├── fare_config.json     fare rules + discounts (PLACEHOLDER values)
  │   └── manifest.json        counts + build info, for sanity checks
  └── build/
      └── mapparaan_gtfs.zip   what OpenTripPlanner loads

Patches applied to gtfs/
  1. calendar.txt  start/end dates extended (source expired 2020-06-30)
  2. routes.txt    empty route_short_name filled from the LTFRB code (PUJ1094)
                   route_type is left unchanged so OTP keeps working

Standard library only.
"""
import csv
import datetime
import subprocess
import json
import os
import shutil
import sys
import zipfile

# Modes the planner does not support (PNR has no fare table and is not in the
# planner's mode list), so their routes are removed from gtfs/.
EXCLUDE_MODES = {"pnr"}

# Files in reference/ that this script regenerates. Other reference data,
# including the hand-maintained fare configuration, is preserved.
GENERATED_REFERENCE = {"route_modes.csv", "manifest.json", "manila_boundary.geojson"}

NEW_START = "20200101"
NEW_END = "20351231"

GTFS_FILES = [
    "agency.txt", "calendar.txt", "feed_info.txt", "frequencies.txt",
    "routes.txt", "shapes.txt", "stop_times.txt", "stops.txt", "trips.txt",
]

# Non-LTFRB routes. LTFRB routes are classified by route-code prefix instead:
# LTFRB_PUJ... = public utility jeepney, LTFRB_PUB... = public utility bus.
ROUTE_ID_MODES = {
    "ROUTE_880747": "lrt1",
    "ROUTE_880801": "lrt2",
}
AGENCY_MODES = {"MRTC": "mrt3", "PNR": "pnr", "FORT": "fort_bus"}

FARE_CONFIG = {
    "_note": (
        "PLACEHOLDER VALUES - NOT OFFICIAL. Replace with the current "
        "LTFRB / DOTr fare orders before showing fares as real."
    ),
    "currency": "PHP",
    "discount": {
        "eligible_groups": ["student", "senior_citizen", "pwd"],
        "multiplier": 0.8,
        "stackable": False,
        "legal_basis": ["RA 11314", "RA 9994", "RA 10754"],
    },
    "modes": {
        "jeepney": {"verified": "provisional", "base_fare": 14.0, "base_km": 4, "per_km": 2.00,
                    "note": "Traditional jeepney, LTFRB provisional fare eff. 2026-03-19 (Philstar 2026-03-18). base_km is an assumption. Modern jeepney: 17.00 + 2.40/km."},
        "bus": {"verified": "provisional", "base_fare": 15.0, "base_km": 5, "per_km": 2.49,
                "note": "Ordinary bus, LTFRB provisional fare eff. 2026-03-19. Aircon: 18.00 + 2.98/km. Feed cannot tell ordinary from aircon. base_km is an assumption."},
        "uv_express": {"verified": False, "base_fare": 15.0, "base_km": 5, "per_km": 2.50},
        "lrt1": {"verified": False, "type": "stored_value_by_distance", "table": None},
        "lrt2": {"verified": False, "type": "stored_value_by_distance", "table": None},
        "mrt3": {"verified": False, "type": "stored_value_by_distance", "table": None},
        "pnr": {"verified": False, "type": "stored_value_by_distance", "table": None},
        "fort_bus": {"verified": False, "base_fare": None, "base_km": None, "per_km": None},
    },
}


def read_csv(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        return reader.fieldnames, list(reader)


def write_csv(path, fields, rows):
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def classify(route):
    rid, agency = route["route_id"], route["agency_id"]
    if rid in ROUTE_ID_MODES:
        return ROUTE_ID_MODES[rid]
    if agency in AGENCY_MODES:
        return AGENCY_MODES[agency]
    if agency == "LTFRB":
        if rid.startswith("LTFRB_PUJ"):
            return "jeepney"
        if rid.startswith("LTFRB_PUB"):
            return "bus"
    return "unknown"


def drop_routes(gtfs_dir, route_ids):
    """Remove routes (and their trips, stop_times, frequencies) and then anything
    left unused: stops, calendar rows, shapes, agencies."""
    if not route_ids:
        return 0
    tables = {n: read_csv(os.path.join(gtfs_dir, n + ".txt"))
              for n in ("routes", "trips", "stop_times", "frequencies", "stops",
                        "calendar", "shapes", "agency")}
    f = {n: t[0] for n, t in tables.items()}
    rows = {n: t[1] for n, t in tables.items()}
    rows["routes"] = [r for r in rows["routes"] if r["route_id"] not in route_ids]
    keep_routes = {r["route_id"] for r in rows["routes"]}
    rows["trips"] = [t for t in rows["trips"] if t["route_id"] in keep_routes]
    keep_trips = {t["trip_id"] for t in rows["trips"]}
    rows["stop_times"] = [r for r in rows["stop_times"] if r["trip_id"] in keep_trips]
    rows["frequencies"] = [r for r in rows["frequencies"] if r["trip_id"] in keep_trips]
    used_stops = {r["stop_id"] for r in rows["stop_times"]}
    rows["stops"] = [r for r in rows["stops"] if r["stop_id"] in used_stops]
    used_services = {t["service_id"] for t in rows["trips"]}
    rows["calendar"] = [r for r in rows["calendar"] if r["service_id"] in used_services]
    used_shapes = {t["shape_id"] for t in rows["trips"] if t.get("shape_id")}
    rows["shapes"] = [r for r in rows["shapes"] if r["shape_id"] in used_shapes]
    used_agencies = {r["agency_id"] for r in rows["routes"]}
    rows["agency"] = [r for r in rows["agency"] if r["agency_id"] in used_agencies] or rows["agency"]
    for n in tables:
        write_csv(os.path.join(gtfs_dir, n + ".txt"), f[n], rows[n])
    return len(route_ids)


def fill_rail_day_gaps(gtfs_dir, rail_route_ids):
    """The source feed has no Sunday service for LRT-1 toward Baclaran
    (Roosevelt -> Vito Cruz) although the other direction runs. Rail runs both
    directions every day, so for any rail direction with Saturday trips but no
    Sunday trips, copy the Saturday trip with the longest headway as a Sunday
    trip. Returns a list of what was added (goes into manifest.json)."""
    days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    cf, cal = read_csv(os.path.join(gtfs_dir, "calendar.txt"))
    tf, trips = read_csv(os.path.join(gtfs_dir, "trips.txt"))
    sf, st = read_csv(os.path.join(gtfs_dir, "stop_times.txt"))
    ff, fr = read_csv(os.path.join(gtfs_dir, "frequencies.txt"))
    cal_by = {c["service_id"]: c for c in cal}
    by_trip = {}
    for r in st:
        by_trip.setdefault(r["trip_id"], []).append(r)
    freq_by = {}
    for r in fr:
        freq_by.setdefault(r["trip_id"], []).append(r)

    patterns = {}
    for t in trips:
        if t["route_id"] not in rail_route_ids or t["trip_id"] not in by_trip:
            continue
        rows = sorted(by_trip[t["trip_id"]], key=lambda r: int(r["stop_sequence"]))
        key = (t["route_id"], rows[0]["stop_id"], rows[-1]["stop_id"])
        patterns.setdefault(key, []).append(t)

    added, new_service = [], None
    for key, ts in patterns.items():
        runs = lambda t, d: cal_by[t["service_id"]][d] == "1"
        if any(runs(t, "sunday") for t in ts):
            continue
        sat = [t for t in ts if runs(t, "saturday")]
        if not sat:
            continue
        pick = max(sat, key=lambda t: max(int(f["headway_secs"]) for f in freq_by.get(t["trip_id"], [{"headway_secs": 0}])))
        if new_service is None:
            new_service = {k: "0" for k in cf}
            new_service.update(service_id="FIX_SUNDAY", sunday="1",
                               start_date=NEW_START, end_date=NEW_END)
            cal.append(new_service)
        nid = pick["trip_id"] + "_sun"
        nt = dict(pick); nt["trip_id"] = nid; nt["service_id"] = "FIX_SUNDAY"
        trips.append(nt)
        for r in by_trip[pick["trip_id"]]:
            c = dict(r); c["trip_id"] = nid; st.append(c)
        for r in freq_by.get(pick["trip_id"], []):
            c = dict(r); c["trip_id"] = nid; fr.append(c)
        added.append({"route_id": key[0], "from_stop": key[1], "to_stop": key[2],
                      "copied_from_trip": pick["trip_id"], "new_trip": nid,
                      "reason": "no Sunday service in source feed"})
    if added:
        write_csv(os.path.join(gtfs_dir, "calendar.txt"), cf, cal)
        write_csv(os.path.join(gtfs_dir, "trips.txt"), tf, trips)
        write_csv(os.path.join(gtfs_dir, "stop_times.txt"), sf, st)
        write_csv(os.path.join(gtfs_dir, "frequencies.txt"), ff, fr)
    return added


def main():
    if len(sys.argv) not in (3, 4):
        print(__doc__)
        sys.exit(1)
    src, root = sys.argv[1], sys.argv[2]
    boundary = sys.argv[3] if len(sys.argv) == 4 else None
    if not os.path.isdir(src):
        sys.exit(f"Input folder not found: {src}")

    raw_dir = os.path.join(root, "raw", "sakay_gtfs")
    gtfs_dir = os.path.join(root, "gtfs")
    ref_dir = os.path.join(root, "reference")
    build_dir = os.path.join(root, "build")
    kept_reference = {}
    existing_ref = os.path.join(root, "reference")
    if os.path.isdir(existing_ref):
        for name in os.listdir(existing_ref):
            path = os.path.join(existing_ref, name)
            if name not in GENERATED_REFERENCE and os.path.isfile(path):
                with open(path, "rb") as fh:
                    kept_reference[name] = fh.read()
    keep_boundary = None
    if boundary:
        with open(boundary, "rb") as f:
            keep_boundary = f.read()
    for d in (gtfs_dir, ref_dir, build_dir):
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
    for name, data in kept_reference.items():
        with open(os.path.join(ref_dir, name), "wb") as fh:
            fh.write(data)
    if keep_boundary:
        with open(os.path.join(ref_dir, "manila_boundary.geojson"), "wb") as f:
            f.write(keep_boundary)
    if os.path.abspath(src) != os.path.abspath(raw_dir):
        shutil.rmtree(raw_dir, ignore_errors=True)
        shutil.copytree(src, raw_dir)

    # patched gtfs/ starts as a copy of the standard files only
    work_dir = raw_dir
    if boundary:
        work_dir = os.path.join(build_dir, "_clipped")
        clip = os.path.join(os.path.dirname(os.path.abspath(__file__)), "clip_gtfs.py")
        subprocess.run([sys.executable, "-I", clip, raw_dir,
                        os.path.join(ref_dir, "manila_boundary.geojson"), work_dir],
                       check=True)
    for name in GTFS_FILES:
        shutil.copy(os.path.join(work_dir, name), os.path.join(gtfs_dir, name))

    # 1. calendar
    fields, rows = read_csv(os.path.join(gtfs_dir, "calendar.txt"))
    for row in rows:
        row["start_date"], row["end_date"] = NEW_START, NEW_END
    write_csv(os.path.join(gtfs_dir, "calendar.txt"), fields, rows)
    n_services = len(rows)

    # 2. routes + modes
    fields, routes = read_csv(os.path.join(gtfs_dir, "routes.txt"))
    modes, counts = [], {}
    for route in routes:
        mode = classify(route)
        counts[mode] = counts.get(mode, 0) + 1
        modes.append({"route_id": route["route_id"], "mode": mode})
        if not route.get("route_short_name") and mode in ("jeepney", "bus"):
            route["route_short_name"] = route["route_id"].split("_", 1)[-1]
    write_csv(os.path.join(gtfs_dir, "routes.txt"), fields, routes)
    write_csv(os.path.join(ref_dir, "route_modes.csv"), ["route_id", "mode"], modes)

    excluded = {r["route_id"] for r, m in zip(routes, modes) if m["mode"] in EXCLUDE_MODES}
    n_dropped = drop_routes(gtfs_dir, excluded)
    if n_dropped:
        routes = [r for r in routes if r["route_id"] not in excluded]
        modes = [m for m in modes if m["route_id"] not in excluded]
        counts = {k: v for k, v in counts.items() if k not in EXCLUDE_MODES}
        write_csv(os.path.join(ref_dir, "route_modes.csv"), ["route_id", "mode"], modes)

    # 2b. fix known gaps in the source schedule
    rail_ids = {r["route_id"] for r, m in zip(routes, modes) if m["mode"] in ("lrt1", "lrt2", "mrt3", "pnr")}
    data_fixes = fill_rail_day_gaps(gtfs_dir, rail_ids)
    n_services = len(read_csv(os.path.join(gtfs_dir, "calendar.txt"))[1])

    # 3. fares + manifest
    fare_path = os.path.join(ref_dir, "fare_config.json")
    if not os.path.exists(fare_path):  # never overwrite your real fare tables
        with open(fare_path, "w", encoding="utf-8") as f:
            json.dump(FARE_CONFIG, f, indent=2)
        print("  WARNING: no fare_config.json found; wrote a PLACEHOLDER one. Copy your real one in.")
    else:
        print("  kept your existing reference/fare_config.json")

    def count_rows(name):
        with open(os.path.join(gtfs_dir, name), encoding="utf-8-sig") as f:
            return sum(1 for _ in f) - 1

    manifest = {
        "built_on": datetime.date.today().isoformat(),
        "source": "https://github.com/sakayph/gtfs (DOTC data, ~2013-15)",
        "clipped_to": "City of Manila (PSGC 1380600000), faeldon/philippines-json-maps 2023" if boundary else None,
        "calendar_patched_to": [NEW_START, NEW_END],
        "services": n_services,
        "routes_by_mode": counts,
        "rows": {n: count_rows(n) for n in GTFS_FILES},
        "data_fixes": data_fixes,
        "excluded_modes": sorted(EXCLUDE_MODES),
        "known_gaps": [
            "No road geometry for many jeepney/bus routes; most such legs are straight lines",
            "No UV Express routes",
            "No fares in GTFS; fare estimates and their verification status are maintained in fare_config.json",
            "Schedules are headway-based and approximate",
        ],
    }
    with open(os.path.join(ref_dir, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)

    # 4. zip for OTP
    zip_path = os.path.join(build_dir, "mapparaan_gtfs.zip")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for name in GTFS_FILES:
            z.write(os.path.join(gtfs_dir, name), name)

    if boundary:
        shutil.rmtree(work_dir, ignore_errors=True)
    print("Built:", root)
    print("  routes by mode:", counts)
    if counts.get("unknown"):
        print("  WARNING: some routes could not be classified")
    print("  OTP feed:", zip_path)


if __name__ == "__main__":
    main()