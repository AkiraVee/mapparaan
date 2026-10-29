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
from gtfs_planner import LRT_MODES, Planner, RAIL_MODES  # noqa: E402

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

    def test_lrt1_terminal_hours_follow_weekday_and_weekend_schedule(self):
        checks = (
            ("Vito Cruz LRT", "Quirino Ave LRT", at(1, 4, 29), False),
            ("Vito Cruz LRT", "Quirino Ave LRT", at(1, 4, 30), True),
            ("Vito Cruz LRT", "Quirino Ave LRT", at(1, 22, 30), True),
            ("Vito Cruz LRT", "Quirino Ave LRT", at(1, 22, 31), False),
            ("Quirino Ave LRT", "Vito Cruz LRT", at(5, 4, 59), False),
            ("Quirino Ave LRT", "Vito Cruz LRT", at(5, 5, 0), True),
            ("Quirino Ave LRT", "Vito Cruz LRT", at(5, 21, 45), True),
            ("Quirino Ave LRT", "Vito Cruz LRT", at(5, 21, 46), False),
        )
        for station, next_station, when, expected in checks:
            with self.subTest(station=station, when=when):
                self.assertEqual(
                    self.p._rail_boarding_allowed(
                        "lrt1", station, next_station, when
                    ),
                    expected,
                )

    def test_lrt1_configured_holiday_uses_weekend_hours(self):
        holiday = "2026-10-20"
        with patch.object(self.p, "holiday_dates", {holiday}):
            self.assertFalse(
                self.p._rail_boarding_allowed(
                    "lrt1", "Vito Cruz LRT", "Quirino Ave LRT",
                    datetime.datetime(2026, 10, 20, 4, 59, tzinfo=TZ),
                )
            )
            self.assertTrue(
                self.p._rail_boarding_allowed(
                    "lrt1", "Vito Cruz LRT", "Quirino Ave LRT",
                    datetime.datetime(2026, 10, 20, 5, 0, tzinfo=TZ),
                )
            )

    def test_lrt2_opening_and_station_direction_closing_times(self):
        checks = (
            ("Recto LRT", "Legarda LRT", at(1, 4, 49), False),
            ("Recto LRT", "Legarda LRT", at(1, 4, 50), True),
            ("Recto LRT", "Legarda LRT", at(1, 21, 25), True),
            ("Recto LRT", "Legarda LRT", at(1, 21, 26), False),
            ("Legarda LRT", "Recto LRT", at(1, 21, 19), True),
            ("Legarda LRT", "Recto LRT", at(1, 21, 20), False),
            ("Katipunan LRT", "Santolan LRT", at(1, 21, 43), True),
            ("Katipunan LRT", "Santolan LRT", at(1, 21, 44), False),
            ("Antipolo LRT", "Marikina-Pasig LRT", at(1, 20, 55), True),
            ("Antipolo LRT", "Marikina-Pasig LRT", at(1, 20, 56), False),
            ("Recto LRT", "Legarda LRT", at(1, 0, 30), False),
        )
        for station, next_station, when, expected in checks:
            with self.subTest(station=station, next_station=next_station, when=when):
                self.assertEqual(
                    self.p._rail_boarding_allowed(
                        "lrt2", station, next_station, when
                    ),
                    expected,
                )

    def test_lrt2_schedule_source_is_marked_official_but_undated(self):
        source = self.p.service_schedules["lines"]["lrt2"]["source"]
        self.assertEqual(source["operator"], "Light Rail Transit Authority (LRTA)")
        self.assertIsNone(source["publication_date"])
        self.assertIsNone(source["effective_date"])
        self.assertEqual(source["schedule_status"], "official_source_date_unverified")

    def test_lrt2_daytime_route_remains_and_closing_blocks_rail_but_not_road_modes(self):
        recto = self.stop["Recto LRT"]
        v_mapa = self.stop["V. Mapa LRT"]
        daytime = self.p.plan(recto, v_mapa, when=at(1, 12, 0))
        self.assertTrue(any("lrt2" in option["modes"] for option in daytime))

        at_station_cutoff = self.p.plan(recto, v_mapa, when=at(1, 21, 24))
        self.assertTrue(at_station_cutoff)
        self.assertTrue(
            all("lrt2" not in option["modes"] for option in at_station_cutoff)
        )
        self.assertTrue(
            any(set(option["modes"]) & {"bus", "jeepney"} for option in at_station_cutoff)
        )

    def test_2305_pm_route_keeps_verified_road_options_without_lrt(self):
        options = self.p.plan(
            self.stop["Recto LRT"],
            self.stop["V. Mapa LRT"],
            when=at(1, 23, 5),
        )
        self.assertTrue(options)
        self.assertTrue(all(not (set(option["modes"]) & LRT_MODES) for option in options))
        self.assertTrue(
            any(set(option["modes"]) & {"bus", "jeepney"} for option in options)
        )

    def test_lrt_is_not_boardable_outside_its_feed_frequency_window(self):
        for hour, minute in ((4, 59), (22, 0)):
            when = at(1, hour, minute)
            for trip in self.p.trips:
                if trip["mode"] in RAIL_MODES:
                    self.assertIsNone(
                        self.p.trip_wait_s(trip, when),
                        f"{trip['mode']} should be closed at {when:%H:%M}",
                    )

    def test_early_friday_does_not_recommend_lrt_next_service(self):
        options = self.p.plan(
            self.stop["Blumentritt LRT"],
            self.stop["Vito Cruz LRT"],
            when=at(4, 3, 20),
        )

        self.assertTrue(
            all(not (set(option["modes"]) & LRT_MODES) for option in options)
        )
        self.assertTrue(
            all(
                not any(
                    leg.get("mode") in LRT_MODES
                    for leg in option["legs"]
                    if leg["type"] == "ride"
                )
                for option in options
            )
        )

    def test_early_friday_offers_road_alternative_without_closed_lrt(self):
        options = self.p.plan(
            (14.5943, 120.9721),
            self.stop["Blumentritt LRT"],
            when=at(4, 3, 34),
        )

        transit_options = [option for option in options if option["modes"]]
        self.assertTrue(transit_options)
        offered_modes = {
            mode for option in transit_options for mode in option["modes"]
        }
        self.assertIn("jeepney", offered_modes)
        self.assertFalse(offered_modes & LRT_MODES)
        self.assertTrue(all(option["is_next_service"] for option in transit_options))

    def test_bus_only_alternative_is_returned_when_its_next_window_is_available(self):
        origin = self.stop[
            "Dimasalang Birdge / New Antipolo Intersection, Quezon City"
        ]
        destination = self.stop["Valariano Fugoso, Manila"]
        options = self.p.plan(origin, destination, when=at(4, 3, 34))

        bus_options = [
            option for option in options if option["modes"] == ["bus"]
        ]
        self.assertTrue(bus_options, "the route list should include a bus-only choice")
        self.assertTrue(all(option["is_next_service"] for option in bus_options))
        self.assertTrue(
            any(
                leg["route_id"] == "LTFRB_PUB1138"
                for option in bus_options
                for leg in option["legs"]
                if leg["type"] == "ride"
            ),
            "include the verified bus line serving the selected stops",
        )

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

    def test_closed_lrt_lines_never_appear_in_late_night_or_after_midnight_options(self):
        for when in (at(1, 22, 15), at(4, 23, 5), at(5, 0, 30)):
            with self.subTest(departure=when):
                options = self.p.plan(
                    (14.6097, 120.9894),
                    self.stop["Vito Cruz LRT"],
                    when=when,
                )
                for option in options:
                    self.assertFalse(set(option["modes"]) & LRT_MODES)
                    self.assertFalse(
                        any(
                            leg.get("mode") in LRT_MODES
                            for leg in option["legs"]
                            if leg["type"] == "ride"
                        )
                    )

    def test_friday_2305_does_not_use_weekend_service_as_if_running_now(self):
        trip = next(t for t in self.p.trips if t["trip_id"] == "881763")
        friday_2305 = at(4, 23, 5)
        self.assertIsNone(self.p.trip_wait_s(trip, friday_2305))
        next_service_wait = self.p.trip_wait_s(
            trip,
            friday_2305,
            max_wait_s=12 * 60 * 60,
        )
        self.assertIsNotNone(next_service_wait)
        self.assertGreater(next_service_wait, 8 * 60 * 60)
        self.assertLessEqual(next_service_wait, 12 * 60 * 60)

        options = self.p.plan(
            (14.6097, 120.9894),
            self.stop["Vito Cruz LRT"],
            when=friday_2305,
        )
        self.assertTrue(
            all(not (set(option["modes"]) & LRT_MODES) for option in options)
        )

    def test_saturday_2305_returns_partial_from_the_active_gtfs_jeepney(self):
        options = self.p.plan(
            self.stop["A F. Torres, Manila"],
            (14.6161, 120.9500),
            when=at(5, 23, 5),
        )

        self.assertTrue(options)
        current_jeepney_options = [
            option
            for option in options
            if not option.get("is_next_service")
            and any(
                leg.get("route_id") == "LTFRB_PUJ2137"
                for leg in option["legs"]
                if leg["type"] == "ride"
            )
        ]
        self.assertTrue(
            current_jeepney_options,
            "preserve a route that is boardable now alongside later options",
        )
        self.assertTrue(
            all(option.get("is_partial") for option in current_jeepney_options)
        )
        self.assertTrue(
            all(
                option["remaining_distance_m"] > 1500
                for option in current_jeepney_options
            )
        )

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