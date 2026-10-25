#!/usr/bin/env python3
"""Service-day tests on the REAL data: rail must run in both directions every day.

The source feed had no Sunday LRT-1 service toward Baclaran; patch_gtfs.py adds it.
This test makes sure that fix is (still) in the data you are running.

Run from the project root:
  python -m unittest backend.planner.test_service_days
  MAPPARAAN_DATA_DIR=path/to/data python3 backend/planner/test_service_days.py
"""
import datetime
import os
import sys
import unittest
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gtfs_planner import Planner, RAIL_MODES  # noqa: E402

DATA_DIR = os.environ.get(
    "MAPPARAAN_DATA_DIR",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data"),
)
TZ = datetime.timezone(datetime.timedelta(hours=8))
DAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]


def at(day_index, hour, minute=0):
    """A Manila time on the given weekday (0 = Monday), in the week of 2026-10-19."""
    d = datetime.datetime(2026, 10, 19, hour, minute, tzinfo=TZ) + datetime.timedelta(days=day_index)
    assert d.weekday() == day_index
    return d


class ServiceDayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.p = Planner(DATA_DIR)
        cls.stop = {n: (cls.p.stop_lat[i], cls.p.stop_lon[i]) for i, n in enumerate(cls.p.stop_name)}

    def test_every_rail_direction_runs_every_day_at_midday(self):
        patterns = defaultdict(list)
        for t in self.p.trips:
            if t["mode"] in RAIL_MODES:
                patterns[(t["route_id"], t["stops"][0], t["stops"][-1])].append(t)
        self.assertTrue(patterns, "no rail trips found in the data")
        for key, trips in patterns.items():
            for d in range(7):
                running = [t for t in trips if self.p.trip_wait_s(t, at(d, 12)) is not None]
                self.assertTrue(
                    running,
                    f"rail {self.p.stop_name[key[1]]} -> {self.p.stop_name[key[2]]} "
                    f"has no service on {DAYS[d]} at 12:00")

    def test_lrt1_both_directions_on_a_sunday(self):
        north, south = "Blumentritt LRT", "Vito Cruz LRT"
        for a, b in ((north, south), (south, north)):
            for hour, minute in ((6, 0), (12, 0), (17, 31), (20, 30)):
                options = self.p.plan(self.stop[a], self.stop[b], when=at(6, hour, minute))
                fastest = next(o for o in options if o["preference"] == "fastest")
                self.assertIn("lrt1", fastest["modes"], f"{a} -> {b} at {hour:02d}:{minute:02d} on Sunday")


if __name__ == "__main__":
    unittest.main(verbosity=2)