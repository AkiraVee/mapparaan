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
from unittest.mock import patch

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

    def test_lrt_is_not_boardable_outside_its_feed_frequency_window(self):
        for hour, minute in ((4, 59), (22, 0)):
            when = at(1, hour, minute)
            for trip in self.p.trips:
                if trip["mode"] in RAIL_MODES:
                    self.assertIsNone(
                        self.p.trip_wait_s(trip, when),
                        f"{trip['mode']} should be closed at {when:%H:%M}",
                    )

    def test_early_friday_trip_uses_next_real_rail_window_with_wait(self):
        options = self.p.plan(
            self.stop["Blumentritt LRT"],
            self.stop["Vito Cruz LRT"],
            when=at(4, 3, 20),
        )

        transit_options = [option for option in options if option["modes"]]
        self.assertTrue(transit_options)
        for option in transit_options:
            self.assertTrue(option["is_next_service"])
            self.assertIn("within 2 hours", option["next_service_message"])
            self.assertIn("lrt1", option["modes"])
            ride = next(leg for leg in option["legs"] if leg["type"] == "ride")
            self.assertGreaterEqual(ride["wait_minutes"], 100)
            self.assertLessEqual(ride["wait_minutes"], 120)

    def test_road_routes_remain_available_after_lrt_closes(self):
        when = at(1, 22, 15)
        options = self.p.plan(
            (14.6097, 120.9894),
            self.stop["Vito Cruz LRT"],
            when=when,
        )
        self.assertTrue(options, "road alternatives should remain available")
        for option in options:
            self.assertFalse(set(option["modes"]) & RAIL_MODES)
        self.assertTrue(
            any(set(option["modes"]) & {"jeepney", "bus"} for option in options)
        )

    def test_friday_2305_has_no_service_from_weekend_only_late_window(self):
        options = self.p.plan(
            (14.6097, 120.9894),
            self.stop["Vito Cruz LRT"],
            when=at(4, 23, 5),
        )
        self.assertEqual(options, [])

    def test_saturday_2305_returns_partial_from_the_active_gtfs_jeepney(self):
        options = self.p.plan(
            self.stop["A F. Torres, Manila"],
            (14.6161, 120.9500),
            when=at(5, 23, 5),
        )

        self.assertTrue(options)
        self.assertTrue(all(option.get("is_partial") for option in options))
        for option in options:
            ride_legs = [leg for leg in option["legs"] if leg["type"] == "ride"]
            self.assertTrue(ride_legs)
            self.assertEqual(
                {leg["route_id"] for leg in ride_legs},
                {"LTFRB_PUJ2137"},
            )
            self.assertGreater(option["remaining_distance_m"], 1500)

    def test_transfer_arrival_time_is_used_for_lrt_boarding(self):
        options = self.p.plan(
            (14.6097, 120.9894),
            self.stop["Vito Cruz LRT"],
            when=at(1, 21, 55),
        )
        self.assertTrue(options, "a practical road alternative should be returned")
        self.assertTrue(
            all(not (set(option["modes"]) & RAIL_MODES) for option in options),
            "do not recommend rail when the first transfer would arrive after closing",
        )

    def test_previous_service_day_can_cover_after_midnight_frequency(self):
        service_id = "TEST_MONDAY_OVERNIGHT"
        calendar = {
            "service_id": service_id,
            "monday": "1",
            "tuesday": "0",
            "wednesday": "0",
            "thursday": "0",
            "friday": "0",
            "saturday": "0",
            "sunday": "0",
            "start_date": "20200101",
            "end_date": "20351231",
        }
        trip = {
            "service_id": service_id,
            "mode": "jeepney",
            "freq": [(23 * 3600, 26 * 3600, 600)],
        }
        with patch.dict(self.p.calendar, {service_id: calendar}):
            self.assertEqual(self.p.trip_wait_s(trip, at(1, 0, 30)), 300)

    def test_after_midnight_does_not_use_inactive_previous_service_day(self):
        service_id = "TEST_TUESDAY_ONLY"
        calendar = {
            "service_id": service_id,
            "monday": "0",
            "tuesday": "1",
            "wednesday": "0",
            "thursday": "0",
            "friday": "0",
            "saturday": "0",
            "sunday": "0",
            "start_date": "20200101",
            "end_date": "20351231",
        }
        trip = {
            "service_id": service_id,
            "mode": "jeepney",
            "freq": [(23 * 3600, 26 * 3600, 600)],
        }
        with patch.dict(self.p.calendar, {service_id: calendar}):
            self.assertIsNone(self.p.trip_wait_s(trip, at(1, 0, 30)))

    def test_current_data_does_not_invent_service_after_midnight(self):
        after_midnight = at(1, 0, 30)
        for trip in self.p.trips:
            self.assertIsNone(self.p.trip_wait_s(trip, after_midnight))


if __name__ == "__main__":
    unittest.main(verbosity=2)