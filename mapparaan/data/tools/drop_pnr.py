#!/usr/bin/env python3
"""Remove the PNR route from data/gtfs, in place. Standard library only.

Why: the planner has no PNR mode or fare table, so a PNR ride would be priced
like a bus. The README already says PNR was removed; this makes it true.

Run from the project root:
    python data/tools/drop_pnr.py            # uses ./data
    python data/tools/drop_pnr.py path/to/data

It removes every route of the PNR agency (or route id ROUTE_880872) together with
its trips, stop_times and frequencies, then deletes whatever is left unused:
stops, calendar rows, shapes and the PNR agency. It never touches clip rules,
fare_config.json or anything in reference/ except the row counts in manifest.json.
Safe to run twice (the second run changes nothing). A backup of every changed
file is kept in data/gtfs_backup_before_drop_pnr/.
"""
import csv
import json
import os
import shutil
import sys

DROP_AGENCIES = {"PNR"}
DROP_ROUTE_IDS = {"ROUTE_880872"}
FILES = ("agency", "routes", "trips", "stop_times", "frequencies", "stops", "calendar", "shapes")


def read(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        r = csv.DictReader(f)
        return r.fieldnames, list(r)


def write(path, fields, rows):
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)


def main():
    data = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "data")
    gtfs = os.path.join(data, "gtfs")
    if not os.path.isfile(os.path.join(gtfs, "routes.txt")):
        sys.exit(f"No gtfs/routes.txt in {data}. Run from the project root or pass the data folder.")

    t = {n: read(os.path.join(gtfs, n + ".txt")) for n in FILES}
    fields = {n: v[0] for n, v in t.items()}
    rows = {n: v[1] for n, v in t.items()}
    before = {n: len(r) for n, r in rows.items()}

    drop = {r["route_id"] for r in rows["routes"]
            if r.get("agency_id") in DROP_AGENCIES or r["route_id"] in DROP_ROUTE_IDS}
    if not drop:
        print("No PNR routes found. Nothing to do.")
        return

    backup = os.path.join(data, "gtfs_backup_before_drop_pnr")
    if not os.path.exists(backup):
        os.makedirs(backup)
        for n in FILES:
            shutil.copy(os.path.join(gtfs, n + ".txt"), backup)

    rows["routes"] = [r for r in rows["routes"] if r["route_id"] not in drop]
    keep_routes = {r["route_id"] for r in rows["routes"]}
    rows["trips"] = [x for x in rows["trips"] if x["route_id"] in keep_routes]
    keep_trips = {x["trip_id"] for x in rows["trips"]}
    rows["stop_times"] = [x for x in rows["stop_times"] if x["trip_id"] in keep_trips]
    rows["frequencies"] = [x for x in rows["frequencies"] if x["trip_id"] in keep_trips]
    used_stops = {x["stop_id"] for x in rows["stop_times"]}
    rows["stops"] = [x for x in rows["stops"] if x["stop_id"] in used_stops]
    used_services = {x["service_id"] for x in rows["trips"]}
    rows["calendar"] = [x for x in rows["calendar"] if x["service_id"] in used_services]
    used_shapes = {x["shape_id"] for x in rows["trips"] if x.get("shape_id")}
    rows["shapes"] = [x for x in rows["shapes"] if x["shape_id"] in used_shapes]
    used_agencies = {x["agency_id"] for x in rows["routes"]}
    rows["agency"] = [x for x in rows["agency"] if x["agency_id"] in used_agencies] or rows["agency"]

    for n in FILES:
        write(os.path.join(gtfs, n + ".txt"), fields[n], rows[n])

    modes_path = os.path.join(data, "reference", "route_modes.csv")
    if os.path.isfile(modes_path):
        mf, mrows = read(modes_path)
        write(modes_path, mf, [r for r in mrows if r["route_id"] not in drop])

    manifest_path = os.path.join(data, "reference", "manifest.json")
    if os.path.isfile(manifest_path):
        with open(manifest_path, encoding="utf-8") as f:
            m = json.load(f)
        m["rows"] = {f"{n}.txt": len(rows[n]) for n in FILES} | {"feed_info.txt": m.get("rows", {}).get("feed_info.txt", 1)}
        m.get("routes_by_mode", {}).pop("pnr", None)
        m["excluded_modes"] = sorted(set(m.get("excluded_modes", [])) | {"pnr"})
        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(m, f, indent=2)

    print(f"Removed {len(drop)} PNR route(s): {', '.join(sorted(drop))}")
    for n in FILES:
        if before[n] != len(rows[n]):
            print(f"  {n}.txt: {before[n]} -> {len(rows[n])}")
    print(f"Backup of the old files: {backup}")


if __name__ == "__main__":
    main()