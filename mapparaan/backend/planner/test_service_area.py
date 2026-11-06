import contextlib
import io
import json
import os
import threading
import unittest
import urllib.request
from http.server import HTTPServer
from unittest.mock import patch

from backend.planner import api


class _RecordingPlanner:
    trips = []
    n_stops = 0

    def __init__(self):
        self.calls = []

    def plan(self, origin, destination, **kwargs):
        self.calls.append((origin, destination))
        return [{"id": "test-route"}]


class ServiceAreaTests(unittest.TestCase):
    def setUp(self):
        self.polygon = [[
            [120.0, 14.0],
            [121.0, 14.0],
            [121.0, 15.0],
            [120.0, 15.0],
            [120.0, 14.0],
        ]]

    def test_only_points_inside_polygon_are_supported(self):
        with patch.object(api, "_AREA", [self.polygon]):
            self.assertTrue(api.in_service_area((14.5, 120.5)))
            self.assertTrue(api.in_service_area((14.0, 120.5)))
            self.assertFalse(api.in_service_area((14.01, 121.01)))
            self.assertFalse(api.in_service_area((14.5, 121.01)))

    def test_polygon_holes_are_not_supported_locations(self):
        polygon_with_hole = [
            self.polygon[0],
            [
                [120.4, 14.4],
                [120.6, 14.4],
                [120.6, 14.6],
                [120.4, 14.6],
                [120.4, 14.4],
            ],
        ]
        with patch.object(api, "_AREA", [polygon_with_hole]):
            self.assertTrue(api.in_service_area((14.2, 120.2)))
            self.assertFalse(api.in_service_area((14.5, 120.5)))
            self.assertTrue(api.in_service_area((14.4, 120.5)))

    def test_missing_boundary_fails_closed(self):
        with patch.object(api, "_AREA", None):
            self.assertFalse(api.in_service_area((14.59, 120.976)))

    def test_existing_manila_boundary_contains_central_city_point(self):
        data_dir = os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "data")
        )
        area = api.load_service_area(data_dir)
        with patch.object(api, "_AREA", area):
            self.assertTrue(api.in_service_area((14.59, 120.976)))
            self.assertFalse(api.in_service_area((14.6567, 121.0287)))

    def test_planner_allows_same_side_routes_and_blocks_boundary_crossings(self):
        previous_planner = api._PLANNER
        previous_area = api._AREA
        planner = _RecordingPlanner()
        api._PLANNER = planner
        api._AREA = [self.polygon]
        server = HTTPServer(("127.0.0.1", 0), api.TransitApiHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def plan(origin, destination):
            payload = json.dumps(
                {"from": origin, "to": destination, "passenger": "general"}
            ).encode()
            request = urllib.request.Request(
                f"http://127.0.0.1:{server.server_port}/plan",
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with contextlib.redirect_stdout(io.StringIO()):
                with urllib.request.urlopen(request, timeout=3) as response:
                    return json.loads(response.read().decode())

        try:
            manila_route = plan("14.5,120.5", "14.6,120.6")
            self.assertEqual(manila_route["options"], [{"id": "test-route"}])

            outside_route = plan("14.5,121.1", "14.6,121.2")
            self.assertEqual(outside_route["options"], [{"id": "test-route"}])

            crossing_route = plan("14.5,120.5", "14.5,121.1")
            self.assertEqual(crossing_route["reason"], "outside_service_area")
            self.assertIn("not supported", crossing_route["message"])
            self.assertEqual(len(planner.calls), 2)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)
            api._PLANNER = previous_planner
            api._AREA = previous_area

    def test_missing_boundary_fails_closed_for_route_planning(self):
        previous_planner = api._PLANNER
        previous_area = api._AREA
        planner = _RecordingPlanner()
        api._PLANNER = planner
        api._AREA = None
        server = HTTPServer(("127.0.0.1", 0), api.TransitApiHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        request = urllib.request.Request(
            f"http://127.0.0.1:{server.server_port}/plan",
            data=json.dumps(
                {"from": "14.5,121.1", "to": "14.6,121.2"}
            ).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                with urllib.request.urlopen(request, timeout=3) as response:
                    result = json.loads(response.read().decode())
            self.assertEqual(result["reason"], "outside_service_area")
            self.assertIn("could not be verified", result["message"])
            self.assertEqual(planner.calls, [])
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)
            api._PLANNER = previous_planner
            api._AREA = previous_area


if __name__ == "__main__":
    unittest.main()
