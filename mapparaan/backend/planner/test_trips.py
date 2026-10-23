#!/usr/bin/env python3
"""Batch test: runs ~20 real Manila trips through the planner and checks the answers.

Two ways to run (from the project root, the folder that contains backend/ and data/):

  python backend\\planner\\test_trips.py                       # loads the planner directly
  python backend\\planner\\test_trips.py --url http://localhost:8080   # asks the running API

Options:
  --data-dir PATH   data folder (default: ./data). Needed for station coordinates too.
  --verbose         print every option of every trip, not just problems

Each trip ends as one of:
  PASS  everything checked out
  WARN  worth a look, but not necessarily wrong (e.g. no route found, slow, estimated rail fare)
  FAIL  something is wrong (bad fare, PNR/unknown mode, missing fields, crash, expected value missed)
The script exits with code 1 if any trip FAILs.
"""
import argparse
import csv
import datetime
import json
import os
import sys
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

KNOWN_MODES = {"jeepney", "bus", "lrt1", "lrt2", "uv_express"}
RAIL = {"lrt1", "lrt2"}
FARE_KEYS = ("fare", "fare_max", "fare_discounted", "fare_discounted_max")
WHEN = datetime.datetime(2026, 10, 23, 9, 0, tzinfo=datetime.timezone(datetime.timedelta(hours=8)))

# Landmarks (approximate lat, lon). A few hundred metres of error is fine: the planner
# walks up to 1.5 km to a stop.
PLACES = {
    "City Hall": (14.5896, 120.9815),
    "UST": (14.6097, 120.9894),
    "Quiapo Church": (14.5991, 120.9838),
    "Divisoria": (14.6014, 120.9726),
    "Tutuban": (14.6115, 120.9730),
    "SM San Lazaro": (14.6192, 120.9833),
    "Luneta": (14.5831, 120.9794),
    "De La Salle Univ": (14.5648, 120.9932),
    "Fort Santiago": (14.5951, 120.9663),
    "Robinsons Manila": (14.5783, 120.9850),
    "PUP Sta. Mesa": (14.5978, 121.0112),
    "Paco Park": (14.5805, 120.9930),
    "Pandacan": (14.5864, 121.0042),
    "Binondo": (14.5997, 120.9742),
    "Malate Church": (14.5693, 120.9918),
    "Moriones Tondo": (14.6212, 120.9690),
    "Post Office": (14.5933, 120.9798),
    "Manila Bay (sea)": (14.5800, 120.9400),
    "Ayala Makati": (14.5547, 121.0244),
    "NAIA": (14.5086, 121.0194),
}


def load_stations(data_dir):
    """name -> (lat, lon) from gtfs/stops.txt, for exact rail station coordinates."""
    out = {}
    with open(os.path.join(data_dir, "gtfs", "stops.txt"), encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f):
            out[r["stop_name"].strip()] = (float(r["stop_lat"]), float(r["stop_lon"]))
    return out


def build_trips(stations):
    def st(name):
        if name not in stations:
            raise SystemExit(f"Station '{name}' not found in stops.txt - check the data folder.")
        return stations[name]

    P = PLACES
    return [
        # ── LRT-1, answers read from the LRT-1 station table ──
        dict(name="LRT-1 Vito Cruz > Blumentritt", a=st("Vito Cruz LRT"), b=st("Blumentritt LRT"),
             modes_any={"lrt1"}, fare=26.0),
        dict(name="LRT-1 Central > Carriedo (adjacent)", a=st("Central Terminal LRT"), b=st("Carriedo LRT"),
             modes_any={"lrt1"}, fare=17.0),
        dict(name="LRT-1 Pedro Gil > Abad Santos", a=st("Pedro Gil LRT"), b=st("Abad Santos LRT"),
             modes_any={"lrt1"}, fare=25.0),
        # ── LRT-2, answers read from the LRT-2 station table ──
        dict(name="LRT-2 Recto > V. Mapa", a=st("Recto LRT"), b=st("V. Mapa LRT"),
             modes_any={"lrt2"}, fare=18.0),
        dict(name="LRT-2 Legarda > Pureza (adjacent)", a=st("Legarda LRT"), b=st("Pureza LRT"),
             modes_any={"lrt2"}, fare=15.0),
        # ── transfer between the two lines ──
        dict(name="Transfer LRT-1 > LRT-2 (Vito Cruz > V. Mapa)", a=st("Vito Cruz LRT"), b=st("V. Mapa LRT"),
             modes_any={"lrt1", "lrt2"}, want_transfer=True),
        # ── road trips: no exact fare, just sanity checks ──
        dict(name="City Hall > UST", a=P["City Hall"], b=P["UST"]),
        dict(name="Quiapo > Divisoria", a=P["Quiapo Church"], b=P["Divisoria"]),
        dict(name="Tutuban > SM San Lazaro", a=P["Tutuban"], b=P["SM San Lazaro"]),
        dict(name="Luneta > De La Salle", a=P["Luneta"], b=P["De La Salle Univ"]),
        dict(name="Fort Santiago > Robinsons Manila", a=P["Fort Santiago"], b=P["Robinsons Manila"]),
        dict(name="PUP Sta. Mesa > Quiapo", a=P["PUP Sta. Mesa"], b=P["Quiapo Church"]),
        dict(name="Paco Park > Pandacan", a=P["Paco Park"], b=P["Pandacan"]),
        dict(name="Divisoria > PUP Sta. Mesa (cross-town)", a=P["Divisoria"], b=P["PUP Sta. Mesa"]),
        dict(name="Binondo > Malate Church", a=P["Binondo"], b=P["Malate Church"]),
        dict(name="UST > Moriones Tondo", a=P["UST"], b=P["Moriones Tondo"]),
        # ── special cases ──
        dict(name="Walk only (City Hall > Post Office)", a=P["City Hall"], b=P["Post Office"],
             walk_only=True),
        dict(name="Same point both ends", a=P["City Hall"], b=P["City Hall"], same_point=True),
        dict(name="Origin in Manila Bay (no stops nearby)", a=P["Manila Bay (sea)"], b=P["City Hall"],
             expect_none=True),
        dict(name="Avoid jeepney+bus (Vito Cruz > Blumentritt)", a=st("Vito Cruz LRT"), b=st("Blumentritt LRT"),
             avoid={"jeepney", "bus"}, forbid_modes={"jeepney", "bus"}, modes_any={"lrt1"}),
        dict(name="Outside Manila (Ayala > NAIA)", a=P["Ayala Makati"], b=P["NAIA"],
             outside=True),
    ]


# ── ways to get an answer ────────────────────────────────────────────────────
def make_runner(args):
    if args.url:
        base = args.url.rstrip("/")

        def run(trip):
            q = {"from": "%s,%s" % trip["a"], "to": "%s,%s" % trip["b"], "passenger": "general"}
            if trip.get("avoid"):
                q["avoid"] = ",".join(sorted(trip["avoid"]))
            with urllib.request.urlopen(base + "/plan?" + urllib.parse.urlencode(q), timeout=30) as r:
                body = json.loads(r.read().decode("utf-8"))
            return body.get("options", []), body.get("reason")
        return run

    from gtfs_planner import Planner
    planner = Planner(args.data_dir)

    def run(trip):
        opts = planner.plan(trip["a"], trip["b"], passenger="general", when=WHEN,
                            avoid_modes=trip.get("avoid") or set())
        return opts, None
    return run


# ── checks ───────────────────────────────────────────────────────────────────
def quarter(x):
    return abs(x / 0.25 - round(x / 0.25)) < 1e-6


def check_option(o, issues, warns):
    for k in FARE_KEYS + ("fare_estimated", "fare_source", "eta_minutes", "legs", "modes", "preference"):
        if k not in o:
            issues.append(f"option missing '{k}'")
            return
    if not (o["fare"] <= o["fare_max"] + 1e-9):
        issues.append(f"fare {o['fare']} > fare_max {o['fare_max']}")
    if not (o["fare_discounted"] <= o["fare"] + 1e-9):
        issues.append(f"student fare {o['fare_discounted']} > regular {o['fare']}")
    for k in FARE_KEYS:
        if not quarter(o[k]):
            issues.append(f"{k}={o[k]} is not a multiple of 0.25")
    rides = [l for l in o["legs"] if l["type"] == "ride"]
    for k in FARE_KEYS:
        s = sum(l[k] for l in rides)
        if abs(s - o[k]) > 0.01:
            issues.append(f"{k} total {o[k]} != sum of legs {s}")
    if o["transfers"] != max(0, len(rides) - 1):
        issues.append(f"transfers={o['transfers']} but {len(rides)} ride legs")
    for l in o["legs"]:
        if l["type"] == "ride":
            m = l["mode"]
            if m not in KNOWN_MODES:
                issues.append(f"unknown mode '{m}' on route {l.get('route_code')}")
            if l["km"] <= 0:
                warns.append(f"ride leg with km={l['km']} ({l.get('route_code')})")
            if not l.get("path") or len(l["path"]) < 2:
                issues.append("ride leg without a path")
            if m == "jeepney" and l["fare"] < 14:
                issues.append(f"jeepney fare {l['fare']} below the P14 minimum")
            if m == "bus" and l["fare"] < 15:
                issues.append(f"bus fare {l['fare']} below the P15 minimum")
            if m in RAIL and l["fare_estimated"]:
                warns.append(f"{m} leg {l['from']} > {l['to']} priced as an ESTIMATE (station name not in fare table)")
            if m in RAIL and l["fare"] != l["fare_max"]:
                issues.append(f"{m} fare should be a single value, got {l['fare']}-{l['fare_max']}")
        elif l["type"] == "walk":
            if l.get("meters", 0) > 2500:
                warns.append(f"long walk: {l['meters']} m")
    if o["eta_minutes"] > 240:
        warns.append(f"ETA {o['eta_minutes']} min looks too long")
    if o["eta_minutes"] <= 0 and rides:
        warns.append("ETA is 0 for a ride")


def evaluate(trip, options, reason, secs):
    issues, warns = [], []
    if trip.get("outside"):
        if reason == "outside_service_area":
            return issues, warns, "blocked as outside the service area (API)"
        if options:
            warns.append("outside Manila but the planner still returned routes "
                         "(the service-area block lives in the API; use --url to test it)")
        return issues, warns, f"{len(options)} option(s)"
    if trip.get("expect_none"):
        if options:
            warns.append(f"expected no route, got {len(options)} option(s)")
        return issues, warns, "no route (expected)" if not options else f"{len(options)} option(s)"
    if not options:
        warns.append("no route found")
        return issues, warns, "no options"
    for o in options:
        check_option(o, issues, warns)
    walk = next((o for o in options if o["preference"] == "walk"), None)
    if walk:
        for o in options:
            if o is not walk and o["fare"] > 0 and o["eta_minutes"] >= walk["eta_minutes"]:
                issues.append(f"'{o['preference']}' ride ({o['eta_minutes']} min, P{o['fare']:g}) is not faster than "
                              f"the free walk ({walk['eta_minutes']} min)")
    if trip.get("same_point") and any(o["modes"] for o in options):
        issues.append("origin and destination are the same point, but a paid ride is offered")
    all_modes = {m for o in options for m in o["modes"]}
    if trip.get("modes_any") and not (all_modes & trip["modes_any"]):
        issues.append(f"expected one of {sorted(trip['modes_any'])}, got {sorted(all_modes) or 'walk only'}")
    if trip.get("forbid_modes") and (all_modes & trip["forbid_modes"]):
        issues.append(f"forbidden mode used: {sorted(all_modes & trip['forbid_modes'])}")
    if "fare" in trip and not any(abs(o["fare"] - trip["fare"]) < 0.01 for o in options if o["modes"]):
        got = sorted({o["fare"] for o in options if o["modes"]})
        issues.append(f"expected fare {trip['fare']:g}, got {got}")
    if trip.get("walk_only") and not any(o["preference"] == "walk" for o in options):
        issues.append("expected a walk-only option")
    if trip.get("want_transfer") and not any(o["transfers"] >= 1 for o in options):
        warns.append("expected a transfer option between the two lines, none offered")
    if secs > 2.0:
        warns.append(f"slow: {secs:.1f}s")
    best = next((o for o in options if o["preference"] == "fastest"), options[0])
    fare = (f"P{best['fare']:g}" if best["fare"] == best["fare_max"]
            else f"P{best['fare']:g}-{best['fare_max']:g}")
    summary = f"{len(options)} opt | fastest {best['eta_minutes']} min, {fare} | {'+'.join(best['modes']) or 'walk'}"
    return issues, warns, summary


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", default=None)
    ap.add_argument("--data-dir", default=os.path.join(os.getcwd(), "data"))
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    if not os.path.isdir(os.path.join(args.data_dir, "gtfs")):
        sys.exit(f"No gtfs folder in {args.data_dir}. Run from the project root or pass --data-dir.")

    run = make_runner(args)
    trips = build_trips(load_stations(args.data_dir))
    counts = {"PASS": 0, "WARN": 0, "FAIL": 0}
    details = []
    print(f"Running {len(trips)} trips ({'API ' + args.url if args.url else 'direct planner'})\n")
    for i, trip in enumerate(trips, 1):
        t0 = time.time()
        try:
            options, reason = run(trip)
            issues, warns, summary = evaluate(trip, options, reason, time.time() - t0)
        except Exception as e:  # a crash is a failure, not a reason to stop the batch
            options, issues, warns, summary = [], [f"crashed: {type(e).__name__}: {e}"], [], "CRASH"
        status = "FAIL" if issues else ("WARN" if warns else "PASS")
        counts[status] += 1
        print(f"{i:2}. [{status}] {trip['name']}\n      {summary}")
        for m in issues:
            print(f"      FAIL: {m}")
        for m in warns:
            print(f"      warn: {m}")
        if args.verbose:
            for o in options:
                print(f"      - {o['preference']:<16} {o['eta_minutes']:>3} min  P{o['fare']:g}"
                      f"{'' if o['fare'] == o['fare_max'] else '-' + format(o['fare_max'], 'g')}"
                      f" (student P{o['fare_discounted']:g})  {o['summary']}")
        details.append((trip["name"], status))
    print(f"\nSUMMARY: {counts['PASS']} pass, {counts['WARN']} warn, {counts['FAIL']} fail "
          f"out of {len(trips)}")
    sys.exit(1 if counts["FAIL"] else 0)


if __name__ == "__main__":
    main()