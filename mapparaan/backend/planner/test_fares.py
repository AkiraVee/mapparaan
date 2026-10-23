#!/usr/bin/env python3
"""Fare and planner tests on a small synthetic feed (no real GTFS needed).

Run from anywhere:
  MAPPARAAN_DATA_DIR=path/to/data python3 backend/planner/test_fares.py

MAPPARAAN_DATA_DIR must contain reference/fare_config.json (default: ../../data).
The synthetic feed is written to a temp folder; the real feed is never touched.
"""
import csv
import datetime
import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gtfs_planner import Planner, round_fare, to_manila  # noqa: E402

DATA_DIR = os.environ.get(
    "MAPPARAAN_DATA_DIR",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data"),
)
WHEN = datetime.datetime(2026, 10, 23, 9, 0, tzinfo=datetime.timezone(datetime.timedelta(hours=8)))


def write_csv(path, header, rows):
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


def hms(sec):
    return "%02d:%02d:%02d" % (sec // 3600, sec % 3600 // 60, sec % 60)


def build_feed(root):
    gtfs = os.path.join(root, "gtfs")
    ref = os.path.join(root, "reference")
    os.makedirs(gtfs)
    os.makedirs(ref)
    shutil.copy(os.path.join(DATA_DIR, "reference", "fare_config.json"), ref)

    stops, trips, routes, times, freqs, modes = [], [], [], [], [], []

    # Jeepney line: 6 stops 0.01 deg of latitude apart (about 1.44 km of road per hop)
    for i in range(6):
        stops.append((f"J{i}", f"Jeep Stop {i}", 14.600 + 0.01 * i, 120.980))
    # Bus line along the same road
    for i in range(6):
        stops.append((f"B{i}", f"Bus Stop {i}", 14.600 + 0.01 * i, 120.981))
    # LRT-1: four consecutive stations, well away from the road
    lrt1 = ["Central Terminal LRT", "Carriedo LRT", "Doroteo Jose LRT", "Bambang LRT"]
    for i, name in enumerate(lrt1):
        stops.append((f"L{i}", name, 14.660, 121.000 + 0.01 * i))
    # LRT-2: Recto to V. Mapa, further east
    lrt2 = ["Recto LRT", "Legarda LRT", "Pureza LRT", "V. Mapa LRT"]
    for i, name in enumerate(lrt2):
        stops.append((f"M{i}", name, 14.700, 121.000 + 0.01 * i))
    # A slow jeepney line (1 hour headway) with stops about 550 m apart: on a short
    # trip here walking beats waiting for the vehicle.
    for i in range(3):
        stops.append((f"K{i}", f"Slow Stop {i}", 14.800 + 0.005 * i, 120.980))
    # A rail stop that is not in the fare table
    stops.append(("X0", "Mystery LRT", 14.740, 121.000))
    stops.append(("X1", "Mystery 2 LRT", 14.740, 121.010))

    def add_route(route_id, mode, stop_ids, hop_s, headway=600):
        routes.append((route_id, route_id, f"Route {route_id}"))
        modes.append((route_id, mode))
        trips.append((f"{route_id}_t", route_id, "S1"))
        for seq, sid in enumerate(stop_ids, 1):
            t = hms((seq - 1) * hop_s)
            times.append((f"{route_id}_t", t, t, sid, seq))
        freqs.append((f"{route_id}_t", "00:00:00", "24:00:00", headway))

    add_route("PUJ1", "jeepney", [f"J{i}" for i in range(6)], 180)
    add_route("PUB1", "bus", [f"B{i}" for i in range(6)], 150)
    add_route("LRT1R", "lrt1", [f"L{i}" for i in range(4)], 120)
    add_route("LRT2R", "lrt2", [f"M{i}" for i in range(4)], 120)
    add_route("XRAIL", "lrt1", ["X0", "X1"], 120)
    add_route("PUJSLOW", "jeepney", [f"K{i}" for i in range(3)], 120, headway=3600)

    write_csv(os.path.join(gtfs, "stops.txt"),
              ["stop_id", "stop_name", "stop_lat", "stop_lon"], stops)
    write_csv(os.path.join(gtfs, "routes.txt"),
              ["route_id", "route_short_name", "route_long_name"], routes)
    write_csv(os.path.join(gtfs, "trips.txt"), ["trip_id", "route_id", "service_id"], trips)
    write_csv(os.path.join(gtfs, "stop_times.txt"),
              ["trip_id", "arrival_time", "departure_time", "stop_id", "stop_sequence"], times)
    write_csv(os.path.join(gtfs, "frequencies.txt"),
              ["trip_id", "start_time", "end_time", "headway_secs"], freqs)
    write_csv(os.path.join(gtfs, "calendar.txt"),
              ["service_id", "monday", "tuesday", "wednesday", "thursday", "friday",
               "saturday", "sunday", "start_date", "end_date"],
              [("S1", 1, 1, 1, 1, 1, 1, 1, "20200101", "20351231")])
    write_csv(os.path.join(ref, "route_modes.csv"), ["route_id", "mode"], modes)


class FareTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="mapparaan_test_")
        build_feed(cls.tmp)
        cls.p = Planner(cls.tmp)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    # ── rounding ────────────────────────────────────────────────────────────
    def test_round_half_up_to_quarter(self):
        self.assertEqual(round_fare(14.4), 14.5)
        self.assertEqual(round_fare(20.4), 20.5)
        self.assertEqual(round_fare(18.125), 18.25)   # half rounds up, not to even
        self.assertEqual(round_fare(18.1249), 18.0)
        self.assertEqual(round_fare(21.75), 21.75)

    # ── road fares: values worked out by hand from the LTFRB rates ──────────
    def test_jeepney_6km(self):
        f = self.p.leg_fares("jeepney", 6.0)
        self.assertEqual((f["fare"], f["fare_max"]), (18.0, 21.75))
        self.assertEqual((f["fare_discounted"], f["fare_discounted_max"]), (14.5, 17.5))

    def test_bus_8km(self):
        f = self.p.leg_fares("bus", 8.0)
        self.assertEqual((f["fare"], f["fare_max"]), (22.5, 27.0))
        self.assertEqual((f["fare_discounted"], f["fare_discounted_max"]), (18.0, 21.5))

    def test_inside_base_distance_uses_base_fare(self):
        f = self.p.leg_fares("jeepney", 2.0)
        self.assertEqual((f["fare"], f["fare_max"]), (14.0, 17.0))
        self.assertEqual((f["fare_discounted"], f["fare_discounted_max"]), (11.25, 13.5))
        b = self.p.leg_fares("bus", 3.0)
        self.assertEqual((b["fare"], b["fare_max"]), (15.0, 18.0))

    def test_range_is_never_inverted(self):
        for mode in ("jeepney", "bus"):
            for km in (0, 0.5, 4, 5, 7.3, 12, 40):
                f = self.p.leg_fares(mode, km)
                self.assertLessEqual(f["fare"], f["fare_max"])
                self.assertLessEqual(f["fare_discounted"], f["fare_discounted_max"])
                self.assertLess(f["fare_discounted"], f["fare"] + 0.001)
                for key in ("fare", "fare_max", "fare_discounted", "fare_discounted_max"):
                    self.assertAlmostEqual(f[key] / 0.25, round(f[key] / 0.25), places=6)

    def test_discount_is_not_08_times_regular(self):
        # The add-on method differs from 0.8 x fare on some distances (see config note).
        f = self.p.leg_fares("jeepney", 6.0)
        self.assertNotEqual(f["fare_discounted"], round(f["fare"] * 0.8))

    # ── rail fares: cells read straight from the station tables ─────────────
    def test_lrt1_table_lookup(self):
        f = self.p.leg_fares("lrt1", 3.0, "Central Terminal LRT", "Bambang LRT")
        self.assertEqual((f["fare"], f["fare_max"], f["fare_discounted"]), (19.0, 19.0, 9.5))
        self.assertFalse(f["estimated"])
        back = self.p.leg_fares("lrt1", 3.0, "Bambang LRT", "Central Terminal LRT")
        self.assertEqual(back["fare"], 19.0)

    def test_lrt1_name_matching_ignores_case_and_spacing(self):
        f = self.p.leg_fares("lrt1", 3.0, "  central terminal  lrt", "BAMBANG LRT")
        self.assertEqual(f["fare"], 19.0)

    def test_lrt2_table_lookup(self):
        f = self.p.leg_fares("lrt2", 3.0, "Recto LRT", "V. Mapa LRT")
        self.assertEqual((f["fare"], f["fare_discounted"]), (18.0, 9.0))
        self.assertFalse(f["estimated"])

    def test_rail_discount_is_half(self):
        r = self.p.rail["lrt1"]
        for i in range(12):
            for j in range(12):
                self.assertEqual(r["discounted"][i][j], r["regular"][i][j] / 2)

    def test_unknown_rail_stop_is_flagged_estimate(self):
        f = self.p.leg_fares("lrt1", 3.0, "Mystery LRT", "Mystery 2 LRT")
        self.assertTrue(f["estimated"])
        self.assertGreater(f["fare"], 0)

    # ── plan() ──────────────────────────────────────────────────────────────
    def test_plan_accepts_avoid_modes(self):
        # api.py calls plan(..., avoid_modes=...); this used to raise TypeError.
        origin, dest = (14.600, 120.980), (14.650, 120.980)
        both = self.p.plan(origin, dest, passenger="general", when=WHEN, avoid_modes=set())
        self.assertTrue(both)
        modes_used = {m for o in both for m in o["modes"]}
        self.assertTrue(modes_used & {"jeepney", "bus"})
        only_bus = self.p.plan(origin, dest, when=WHEN, avoid_modes={"jeepney"})
        self.assertTrue(only_bus)
        self.assertTrue(all("jeepney" not in o["modes"] for o in only_bus))
        none = self.p.plan(origin, dest, when=WHEN, avoid_modes={"JEEPNEY", "bus"})
        self.assertTrue(all(not o["modes"] for o in none))

    def test_plan_road_option_totals(self):
        origin, dest = (14.600, 120.980), (14.650, 120.980)
        options = self.p.plan(origin, dest, when=WHEN, avoid_modes={"bus"})
        opt = next(o for o in options if o["modes"] == ["jeepney"])
        ride = next(l for l in opt["legs"] if l["type"] == "ride")
        # 5 hops of 0.01 deg latitude, road factor 1.3
        self.assertAlmostEqual(ride["km"], 7.2, delta=0.1)
        self.assertEqual(opt["fare"], ride["fare"])
        self.assertEqual(opt["fare_max"], ride["fare_max"])
        self.assertEqual(opt["fare_discounted"], ride["fare_discounted"])
        self.assertTrue(opt["fare_estimated"])
        self.assertLess(opt["fare"], opt["fare_max"])
        self.assertLess(opt["fare_discounted"], opt["fare"])
        self.assertIn("estimated", opt["fare_source"].lower())

    def test_plan_rail_option_is_exact(self):
        origin, dest = (14.660, 121.000), (14.660, 121.030)
        options = self.p.plan(origin, dest, when=WHEN)
        opt = next(o for o in options if o["modes"] == ["lrt1"])
        self.assertEqual((opt["fare"], opt["fare_max"], opt["fare_discounted"]), (19.0, 19.0, 9.5))
        self.assertFalse(opt["fare_estimated"])
        self.assertIn("Beep", opt["fare_source"])

    def test_walk_only_option_is_free(self):
        options = self.p.plan((14.600, 120.980), (14.604, 120.980), when=WHEN)
        walk = next(o for o in options if o["preference"] == "walk")
        for key in ("fare", "fare_max", "fare_discounted", "fare_discounted_max"):
            self.assertEqual(walk[key], 0)
        self.assertFalse(walk["fare_estimated"])

    def test_same_point_offers_only_a_walk(self):
        options = self.p.plan((14.600, 120.980), (14.600, 120.980), when=WHEN)
        self.assertEqual([o["preference"] for o in options], ["walk"])
        self.assertEqual(options[0]["fare"], 0)

    def test_ride_slower_than_walking_is_not_offered(self):
        options = self.p.plan((14.600, 120.980), (14.604, 120.980), when=WHEN)
        walk = next(o for o in options if o["preference"] == "walk")
        for o in options:
            if o is not walk:
                self.assertLess(o["eta_minutes"], walk["eta_minutes"])

    def test_slow_ride_is_not_offered_when_walking_is_faster(self):
        # Slow Stop 0 > Slow Stop 1: a 10 min walk, but the only vehicle comes hourly.
        # Before the fix the planner still offered the ~30 min paid ride.
        options = self.p.plan((14.800, 120.980), (14.805, 120.980), when=WHEN)
        self.assertEqual([o["preference"] for o in options], ["walk"])
        # A longer trip on the same line: walking is 20 min, still faster than the wait.
        options = self.p.plan((14.800, 120.980), (14.810, 120.980), when=WHEN)
        self.assertEqual([o["preference"] for o in options], ["walk"])

    def test_same_point_on_a_slow_line_offers_only_a_walk(self):
        options = self.p.plan((14.800, 120.980), (14.800, 120.980), when=WHEN)
        self.assertEqual([o["preference"] for o in options], ["walk"])

    def test_fast_line_still_offered_when_it_beats_walking(self):
        # Guards against the fix being too aggressive: a long trip must keep its rides.
        options = self.p.plan((14.600, 120.980), (14.650, 120.980), when=WHEN)
        self.assertTrue(any(o["modes"] for o in options))

    # ── time zone ───────────────────────────────────────────────────────────
    def test_to_manila_converts_aware_times(self):
        utc = datetime.timezone.utc
        m = to_manila(datetime.datetime(2026, 10, 23, 1, 0, tzinfo=utc))
        self.assertEqual((m.day, m.hour), (23, 9))
        late = to_manila(datetime.datetime(2026, 10, 23, 20, 0, tzinfo=utc))
        self.assertEqual((late.day, late.hour), (24, 4))  # next day in Manila

    def test_to_manila_keeps_naive_times_and_defaults_to_now(self):
        naive = datetime.datetime(2026, 10, 23, 9, 0)
        self.assertEqual(to_manila(naive), naive)
        self.assertEqual(to_manila(None).utcoffset(), datetime.timedelta(hours=8))

    def test_every_option_has_all_fare_keys(self):
        options = self.p.plan((14.600, 120.980), (14.650, 120.980), when=WHEN)
        for o in options:
            for key in ("fare", "fare_max", "fare_discounted", "fare_discounted_max",
                        "fare_estimated", "fare_source"):
                self.assertIn(key, o)
            self.assertLessEqual(o["fare"], o["fare_max"])
        json.dumps(options)  # must be JSON-serialisable for api.py

    def test_no_pnr_left_in_modes(self):
        from gtfs_planner import MODE_LABEL, RAIL_MODES
        self.assertNotIn("pnr", MODE_LABEL)
        self.assertNotIn("pnr", RAIL_MODES)


if __name__ == "__main__":
    unittest.main(verbosity=2)