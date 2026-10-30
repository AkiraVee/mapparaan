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


class _Planner:
    trips = []
    n_stops = 0

    def plan(self, *args, **kwargs):
        return []


class TransitApiSecurityTests(unittest.TestCase):
    def test_parse_coords_rejects_invalid_values(self):
        self.assertEqual(api.parse_coords("14.5,120.9"), (14.5, 120.9))
        self.assertIsNone(api.parse_coords("nan,120.9"))
        self.assertIsNone(api.parse_coords("91,120.9"))
        self.assertIsNone(api.parse_coords("14.5,181"))

    def test_cors_allows_only_configured_origins(self):
        with patch.dict(
            os.environ,
            {"MAPPARAAN_ALLOWED_ORIGINS": "https://app.example.com"},
            clear=False,
        ):
            self.assertTrue(api._is_allowed_origin("https://app.example.com"))
            self.assertFalse(api._is_allowed_origin("https://attacker.example"))

    def test_non_loopback_binding_requires_an_origin_allowlist(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, "MAPPARAAN_ALLOWED_ORIGINS"):
                api.run_server(host="0.0.0.0")

    def test_post_route_hides_coordinates_from_response_headers_and_logs(self):
        previous_planner = api._PLANNER
        previous_area = api._AREA
        api._PLANNER = _Planner()
        api._AREA = [[[
            [120.9, 14.5],
            [121.1, 14.5],
            [121.1, 14.7],
            [120.9, 14.7],
            [120.9, 14.5],
        ]]]
        server = HTTPServer(("127.0.0.1", 0), api.TransitApiHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        logs = io.StringIO()
        thread.start()
        origin = "14.5918,120.9786"
        destination = "14.6567,121.0287"
        request = urllib.request.Request(
            f"http://127.0.0.1:{server.server_port}/plan",
            data=json.dumps(
                {"from": origin, "to": destination, "passenger": "general"}
            ).encode(),
            headers={
                "Content-Type": "application/json",
                "Origin": "https://attacker.example",
            },
            method="POST",
        )
        try:
            with contextlib.redirect_stdout(logs):
                with urllib.request.urlopen(request, timeout=3) as response:
                    body = response.read().decode()
                    self.assertNotIn("Access-Control-Allow-Origin", response.headers)
            self.assertNotIn(origin, body)
            self.assertNotIn(destination, body)
            self.assertNotIn(origin, logs.getvalue())
            self.assertNotIn(destination, logs.getvalue())
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)
            api._PLANNER = previous_planner
            api._AREA = previous_area


if __name__ == "__main__":
    unittest.main()
