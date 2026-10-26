#!/usr/bin/env python3
"""One command to check everything before you deploy.

From the project root (the folder that contains backend/ and data/):
    python backend/planner/check_all.py

It checks, in order:
  1. your fare_config.json is the real one (not the placeholder)
  2. the Manila data is in place, with the Sunday LRT-1 fix and no PNR
  3. your four test files
  4. a live POST /plan against the real API code (no server needs to be running)
and prints PASS / FAIL for each, then a summary. Exit code 1 if anything failed.
"""
import datetime
import json
import os
import subprocess
import sys
import threading
import urllib.request
from http.server import HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
DATA = os.path.join(ROOT, "data")
sys.path.insert(0, HERE)
sys.path.insert(0, ROOT)

results = []


def record(name, ok, detail=""):
    results.append(ok)
    print(("PASS  " if ok else "FAIL  ") + name + ("" if ok or not detail else "\n        " + detail))


def read(path):
    with open(path, encoding="utf-8-sig") as f:
        return f.read()


# 1. fare config -------------------------------------------------------------
try:
    cfg = json.load(open(os.path.join(DATA, "reference", "fare_config.json"), encoding="utf-8"))
    modes = cfg.get("modes", {})
    placeholder = str(cfg.get("_note", "")).strip().upper().startswith("PLACEHOLDER")
    record("fare_config.json is not the placeholder", not placeholder,
           "It still says PLACEHOLDER. Restore your real file (VS Code Timeline / git / backup).")
    need = ("jeepney", "modern_jeepney", "bus", "aircon_bus")
    bad = [k for k in need if modes.get(k, {}).get("verified") is not True]
    record("road fares are verified (jeepney, modern jeepney, bus, aircon bus)", not bad,
           "not verified or missing: " + ", ".join(bad))
    for rail in ("lrt1", "lrt2"):
        record(f"{rail} has a station fare table", modes.get(rail, {}).get("type") == "station_matrix",
               f"{rail} has no station_matrix in fare_config.json")
except (OSError, ValueError) as e:
    record("fare_config.json can be read", False, str(e))

# 2. data ---------------------------------------------------------------------
try:
    trips = read(os.path.join(DATA, "gtfs", "trips.txt"))
    record("Sunday LRT-1 fix is in the data (trip id ends _sun)", "_sun" in trips,
           "Unzip mapparaan_data_manila.zip into data/ and replace files.")
    modes_csv = read(os.path.join(DATA, "reference", "route_modes.csv"))
    record("no PNR routes in the data", "pnr" not in modes_csv.lower(),
           "route_modes.csv still lists pnr. Use the newest data zip.")
    for name in ("manila_boundary.geojson", "manifest.json"):
        record(f"reference/{name} exists", os.path.isfile(os.path.join(DATA, "reference", name)))
except OSError as e:
    record("data/gtfs and data/reference are in place", False, str(e))

# 3. test files ---------------------------------------------------------------
suites = [
    ("test_trips.py (21 trips)", [sys.executable, os.path.join(HERE, "test_trips.py")]),
    ("test_fares", [sys.executable, "-m", "unittest", "backend.planner.test_fares"]),
    ("test_service_days", [sys.executable, "-m", "unittest", "backend.planner.test_service_days"]),
    ("test_api_security", [sys.executable, "-m", "unittest", "backend.planner.test_api_security"]),
]
for label, cmd in suites:
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    tail = (proc.stdout + proc.stderr).strip().splitlines()[-6:]
    record(label, proc.returncode == 0, "\n        ".join(tail))

# 4. live request against the real API code -----------------------------------
try:
    from backend.planner import api
    api._PLANNER = api.Planner(api.resolve_data_dir(DATA))
    api._AREA = api.load_service_area(DATA)
    server = HTTPServer(("127.0.0.1", 0), api.TransitApiHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_port}"

    def post(body):
        req = urllib.request.Request(base + "/plan", data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read().decode())

    with urllib.request.urlopen(base + "/health", timeout=10) as r:
        health = json.loads(r.read().decode())
    record(f"/health ({health['stops']} stops, {health['trips']} trips)", health["stops"] > 0 and health["trips"] > 0)
    route_time = datetime.datetime.now().replace(
        hour=10, minute=0, second=0, microsecond=0
    )
    d = post({
        "from": "14.6042,120.9822",
        "to": "14.5636,120.9950",
        "passenger": "student",
        "when": route_time.isoformat(),
    })
    record("POST /plan inside Manila returns routes", bool(d.get("options")), str(d)[:200])
    if d.get("options"):
        o = d["options"][0]
        record("route has fares and a fare note",
               all(k in o for k in ("fare", "fare_max", "fare_discounted", "fare_source")), str(o.keys()))
    d = post({"from": "14.5547,121.0244", "to": "14.5086,121.0194"})
    record("POST /plan outside Manila says outside_service_area",
           d.get("reason") == "outside_service_area", str(d)[:200])
    server.shutdown()
except Exception as e:  # keep going so the summary still prints
    record("live API request", False, f"{type(e).__name__}: {e}")

passed = sum(results)
print(f"\nSUMMARY: {passed} passed, {len(results) - passed} failed")
if len(results) == passed:
    print("All good. Safe to deploy.")
sys.exit(0 if len(results) == passed else 1)