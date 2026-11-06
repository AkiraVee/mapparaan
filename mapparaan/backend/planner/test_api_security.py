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


class _AiService:
    def __init__(self):
        self.requests = []

    def handle_request(self, request):
        self.requests.append(request)
        return {"status": "ok", "message": "Verified"}


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

    def _post_ai(self, authorization=None, user_id="claimed-user"):
        previous_service = api._AI_SERVICE
        service = _AiService()
        api._AI_SERVICE = service
        server = HTTPServer(("127.0.0.1", 0), api.TransitApiHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        headers = {"Content-Type": "application/json"}
        if authorization is not None:
            headers["Authorization"] = authorization
        request = urllib.request.Request(
            f"http://127.0.0.1:{server.server_port}/ai/chat",
            data=json.dumps({"user_id": user_id, "message": "Hello"}).encode(),
            headers=headers,
            method="POST",
        )
        try:
            try:
                with urllib.request.urlopen(request, timeout=3) as response:
                    return response.status, json.loads(response.read()), service
            except urllib.error.HTTPError as error:
                with error:
                    return error.code, json.loads(error.read()), service
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)
            api._AI_SERVICE = previous_service

    def test_ai_endpoint_requires_a_bearer_token(self):
        status, body, service = self._post_ai()
        self.assertEqual(status, 401)
        self.assertEqual(body["status"], "unauthorized")
        self.assertEqual(service.requests, [])

    def test_ai_endpoint_uses_verified_identity_not_client_identity(self):
        with patch.object(api, "verify_supabase_access_token", return_value="verified-user"):
            status, body, service = self._post_ai("Bearer valid-token", "verified-user")
        self.assertEqual(status, 200)
        self.assertEqual(body["status"], "ok")
        self.assertTrue(body["request_id"])
        self.assertEqual(service.requests[0].user_id, "verified-user")

    def test_ai_endpoint_rejects_mismatched_client_identity(self):
        with patch.object(api, "verify_supabase_access_token", return_value="verified-user"):
            status, body, service = self._post_ai("Bearer valid-token", "other-user")
        self.assertEqual(status, 403)
        self.assertEqual(body["status"], "forbidden")
        self.assertEqual(service.requests, [])

    def test_ai_endpoint_rejects_invalid_supabase_token(self):
        with patch.object(
            api,
            "verify_supabase_access_token",
            side_effect=api.SupabaseInvalidToken,
        ):
            status, body, service = self._post_ai("Bearer invalid-token")
        self.assertEqual(status, 401)
        self.assertEqual(body["status"], "unauthorized")
        self.assertEqual(service.requests, [])

    def test_ai_preflight_allows_authorization_header(self):
        server = HTTPServer(("127.0.0.1", 0), api.TransitApiHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        request = urllib.request.Request(
            f"http://127.0.0.1:{server.server_port}/ai/chat",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "authorization,content-type",
            },
            method="OPTIONS",
        )
        try:
            with urllib.request.urlopen(request, timeout=3) as response:
                self.assertIn("Authorization", response.headers["Access-Control-Allow-Headers"])
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

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
