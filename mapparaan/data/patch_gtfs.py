#!/usr/bin/env python3
"""
Build Mapparaan's transit data folder from the original Sakay.ph GTFS feed.

Usage
  python3 patch_gtfs.py <original_gtfs_folder> <data_root>
Example
  python3 patch_gtfs.py gtfs-master data

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
import json
import os
import shutil
import sys
import zipfile

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
        "jeepney": {"verified": False, "base_fare": 13.0, "base_km": 4, "per_km": 1.80},
        "bus": {"verified": False, "base_fare": 13.0, "base_km": 5, "per_km": 2.25},
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


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    src, root = sys.argv[1], sys.argv[2]
    if not os.path.isdir(src):
        sys.exit(f"Input folder not found: {src}")

    raw_dir = os.path.join(root, "raw", "sakay_gtfs")
    gtfs_dir = os.path.join(root, "gtfs")
    ref_dir = os.path.join(root, "reference")
    build_dir = os.path.join(root, "build")
    for d in (gtfs_dir, ref_dir, build_dir):
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
    if os.path.abspath(src) != os.path.abspath(raw_dir):
        shutil.rmtree(raw_dir, ignore_errors=True)
        shutil.copytree(src, raw_dir)

    # patched gtfs/ starts as a copy of the standard files only
    for name in GTFS_FILES:
        shutil.copy(os.path.join(raw_dir, name), os.path.join(gtfs_dir, name))

    # 1. calendar
    fields, rows = read_csv(os.path.join(raw_dir, "calendar.txt"))
    for row in rows:
        row["start_date"], row["end_date"] = NEW_START, NEW_END
    write_csv(os.path.join(gtfs_dir, "calendar.txt"), fields, rows)
    n_services = len(rows)

    # 2. routes + modes
    fields, routes = read_csv(os.path.join(raw_dir, "routes.txt"))
    modes, counts = [], {}
    for route in routes:
        mode = classify(route)
        counts[mode] = counts.get(mode, 0) + 1
        modes.append({"route_id": route["route_id"], "mode": mode})
        if not route.get("route_short_name") and mode in ("jeepney", "bus"):
            route["route_short_name"] = route["route_id"].split("_", 1)[-1]
    write_csv(os.path.join(gtfs_dir, "routes.txt"), fields, routes)
    write_csv(os.path.join(ref_dir, "route_modes.csv"), ["route_id", "mode"], modes)

    # 3. fares + manifest
    with open(os.path.join(ref_dir, "fare_config.json"), "w", encoding="utf-8") as f:
        json.dump(FARE_CONFIG, f, indent=2)

    def count_rows(name):
        with open(os.path.join(gtfs_dir, name), encoding="utf-8-sig") as f:
            return sum(1 for _ in f) - 1

    manifest = {
        "built_on": datetime.date.today().isoformat(),
        "source": "https://github.com/sakayph/gtfs (DOTC data, ~2013-15)",
        "calendar_patched_to": [NEW_START, NEW_END],
        "services": n_services,
        "routes_by_mode": counts,
        "rows": {n: count_rows(n) for n in GTFS_FILES},
        "known_gaps": [
            "No road geometry for jeepney/bus routes (only 10 shapes)",
            "No UV Express routes",
            "No fares in GTFS; fare_config.json values are placeholders",
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

    print("Built:", root)
    print("  routes by mode:", counts)
    if counts.get("unknown"):
        print("  WARNING: some routes could not be classified")
    print("  OTP feed:", zip_path)


if __name__ == "__main__":
    main()