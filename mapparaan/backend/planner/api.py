#!/usr/bin/env python3
"""
Lightweight transit planning HTTP API for Mapparaan.
Uses Python standard library only (no pip dependencies required).

Usage:
  python backend/planner/api.py [--port 8080] [--host 127.0.0.1]
  python backend/planner/api.py --data-dir path/to/data

Endpoint:
  POST /plan with JSON fields: from, to, passenger, when, and avoid

Service area:
  Route endpoints must be on the same side of the City of Manila boundary in
  <data>/reference/manila_boundary.geojson. Cross-boundary requests answer 200 with
      {"status": "ok", "options": [], "reason": "outside_service_area", "message": "..."}
  so the app can tell that apart from "no route found" (options empty, no reason).
"""

import argparse
import json
import math
import os
import sys
import time
import datetime
import urllib.parse
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer, HTTPServer

# Ensure the project root is on sys.path for direct script execution.
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
for candidate in (PROJECT_ROOT, os.path.dirname(os.path.abspath(__file__))):
    if candidate not in sys.path:
        sys.path.insert(0, candidate)

from gtfs_planner import Planner

try:
    from backend.ai import AiChatRequest, MapParaanAiService
    from backend.ai.auth import (
        SupabaseAuthNotConfigured,
        SupabaseAuthUnavailable,
        SupabaseInvalidToken,
        verify_supabase_access_token,
    )
    from backend.ai.telemetry import log_ai_event
except ImportError:
    raise

# Global planner instance loaded once at startup
_PLANNER = None
# Manila polygons as [polygon][ring][coordinate][longitude, latitude].
_AREA = None
_AI_SERVICE = MapParaanAiService()


def resolve_data_dir(data_dir=None):
    """Resolve the project data directory and fail clearly if it is missing."""
    if data_dir is None:
        data_dir = os.path.join(os.path.dirname(__file__), "..", "..", "data")
    resolved = os.path.abspath(data_dir)
    required = (
        os.path.join(resolved, "gtfs", "stops.txt"),
        os.path.join(resolved, "reference", "fare_config.json"),
        os.path.join(resolved, "reference", "service_schedules.json"),
        os.path.join(resolved, "reference", "route_modes.csv"),
        os.path.join(resolved, "reference", "manila_boundary.geojson"),
    )
    if not all(os.path.isfile(path) for path in required):
        raise FileNotFoundError(
            "Transit planner data is incomplete; check the configured data directory."
        )
    return resolved


def load_service_area(data_dir):
    """Reads the required Manila polygon from <data_dir>/reference(s)."""
    for folder in ("references", "reference"):
        path = os.path.join(data_dir, folder, "manila_boundary.geojson")
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                gj = json.load(f)
            geometries = (
                [feature["geometry"] for feature in gj["features"]]
                if gj.get("type") == "FeatureCollection"
                else [gj["geometry"]]
                if gj.get("type") == "Feature"
                else [gj]
            )
            polygons = []
            for geometry in geometries:
                if geometry["type"] == "Polygon":
                    polygons.append(geometry["coordinates"])
                elif geometry["type"] == "MultiPolygon":
                    polygons.extend(geometry["coordinates"])
                else:
                    raise ValueError("Unsupported Manila boundary geometry.")
            if not polygons or any(
                not polygon or len(polygon[0]) < 4 for polygon in polygons
            ):
                raise ValueError("Manila boundary contains an invalid polygon.")
            return polygons
    raise FileNotFoundError("Required Manila boundary GeoJSON was not found.")


def _point_on_ring(lon, lat, ring):
    epsilon = 1e-10
    for a, b in zip(ring, ring[1:] + ring[:1]):
        cross = (lat - a[1]) * (b[0] - a[0]) - (lon - a[0]) * (b[1] - a[1])
        if abs(cross) > epsilon:
            continue
        if (
            min(a[0], b[0]) - epsilon <= lon <= max(a[0], b[0]) + epsilon
            and min(a[1], b[1]) - epsilon <= lat <= max(a[1], b[1]) + epsilon
        ):
            return True
    return False


def _in_ring(lon, lat, ring):
    if _point_on_ring(lon, lat, ring):
        return True
    inside, j = False, len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i][0], ring[i][1]
        xj, yj = ring[j][0], ring[j][1]
        if (
            (yi > lat) != (yj > lat)
            and lon < (xj - xi) * (lat - yi) / (yj - yi) + xi
        ):
            inside = not inside
        j = i
    return inside


def in_service_area(point):
    """True only when point (lat, lon) lies within the loaded city polygon."""
    if not _AREA:
        return False
    lat, lon = point
    for polygon in _AREA:
        rings = [ring for ring in polygon if len(ring) >= 4]
        if not rings or not _in_ring(lon, lat, rings[0]):
            continue
        if any(
            _in_ring(lon, lat, hole) and not _point_on_ring(lon, lat, hole)
            for hole in rings[1:]
        ):
            continue
        return True
    return False


def parse_coords(val):
    """Parses 'lat,lon' string into tuple of floats (lat, lon)."""
    if not val:
        return None
    try:
        parts = val.strip().split(",")
        if len(parts) != 2:
            return None
        latitude, longitude = (
            float(parts[0].strip()),
            float(parts[1].strip()),
        )
        if (
            not math.isfinite(latitude)
            or not math.isfinite(longitude)
            or not (-90 <= latitude <= 90)
            or not (-180 <= longitude <= 180)
        ):
            return None
        return latitude, longitude
    except (ValueError, AttributeError):
        return None


def _allowed_origins():
    configured = os.environ.get("MAPPARAAN_ALLOWED_ORIGINS", "").strip()
    if configured:
        return {
            origin.strip().rstrip("/")
            for origin in configured.split(",")
            if origin.strip()
        }
    return None


def _is_allowed_origin(origin):
    if not origin:
        return False
    configured = _allowed_origins()
    if configured is not None:
        return origin.rstrip("/") in configured

    parsed = urllib.parse.urlparse(origin)
    return (
        parsed.scheme == "http"
        and parsed.hostname in {"localhost", "127.0.0.1"}
        and parsed.username is None
        and parsed.password is None
    )


class TransitApiHandler(BaseHTTPRequestHandler):
    server_version = "MapparaanPlanner/1.0"

    def _send_cors_headers(self):
        origin = self.headers.get("Origin")
        if _is_allowed_origin(origin):
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
            self.send_header("Access-Control-Max-Age", "600")
        self.send_header("Vary", "Origin")

    def do_OPTIONS(self):
        """Handle CORS preflight requests."""
        self.send_response(204)
        self._send_cors_headers()
        self.end_headers()

    def _send_json(self, status_code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self._send_cors_headers()
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        parsed_url = urllib.parse.urlparse(self.path)
        if parsed_url.path.rstrip("/") in {"/ai", "/ai/chat"}:
            request_id = uuid.uuid4().hex
            started_at = time.perf_counter()
            authenticated_user_id = None

            def log_event(category, status_code, failed_tool_name=None):
                log_ai_event(
                    request_id=request_id,
                    user_id=authenticated_user_id,
                    error_category=category,
                    http_status=status_code,
                    processing_duration_ms=(time.perf_counter() - started_at) * 1000,
                    failed_tool_name=failed_tool_name,
                )

            if self.headers.get_content_type() != "application/json":
                log_event("invalid_content_type", 415)
                self._send_json(415, {
                    "status": "error",
                    "error": "Content-Type must be application/json.",
                    "request_id": request_id,
                })
                return
            try:
                content_length = int(self.headers.get("Content-Length", "0"))
                if content_length <= 0 or content_length > 65536:
                    raise ValueError("invalid body size")
                payload = json.loads(self.rfile.read(content_length))
                if not isinstance(payload, dict):
                    raise ValueError("request body must be an object")
                authorization = self.headers.get("Authorization", "")
                scheme, separator, access_token = authorization.partition(" ")
                if scheme.lower() != "bearer" or not separator or not access_token.strip():
                    log_event("missing_bearer_token", 401)
                    self._send_json(
                        401,
                        {
                            "status": "unauthorized",
                            "error": "Please sign in to use MapParaan AI.",
                            "request_id": request_id,
                        },
                    )
                    return
                try:
                    authenticated_user_id = verify_supabase_access_token(access_token.strip())
                except SupabaseInvalidToken:
                    log_event("invalid_bearer_token", 401)
                    self._send_json(
                        401,
                        {
                            "status": "unauthorized",
                            "error": "Your session is invalid or expired. Please sign in again.",
                            "request_id": request_id,
                        },
                    )
                    return
                except SupabaseAuthNotConfigured:
                    log_event("auth_not_configured", 503)
                    self._send_json(
                        503,
                        {
                            "status": "not_configured",
                            "error": "AI authentication is not configured on the backend.",
                            "request_id": request_id,
                        },
                    )
                    return
                except SupabaseAuthUnavailable:
                    log_event("auth_service_unavailable", 503)
                    self._send_json(
                        503,
                        {
                            "status": "auth_unavailable",
                            "error": "Sign-in verification is temporarily unavailable.",
                            "request_id": request_id,
                        },
                    )
                    return
                supplied_user_id = str(payload.get("user_id") or payload.get("user") or "").strip()
                if supplied_user_id and supplied_user_id != authenticated_user_id:
                    log_event("user_identity_mismatch", 403)
                    self._send_json(
                        403,
                        {
                            "status": "forbidden",
                            "error": "The request user does not match the signed-in account.",
                            "request_id": request_id,
                        },
                    )
                    return
                payload["user_id"] = authenticated_user_id
                request = AiChatRequest.from_payload(payload)
                request.request_id = request_id
                result = _AI_SERVICE.handle_request(request)
                tool_results = result.get("tool_results", [])
                if not isinstance(tool_results, list):
                    tool_results = []
                failed_tool = next(
                    (
                        item.get("name")
                        for item in tool_results
                        if isinstance(item, dict)
                        and item.get("status") in {
                            "tool_error",
                            "invalid_tool",
                            "invalid_arguments",
                            "invalid_request",
                            "planner_unavailable",
                            "planner_error",
                            "place_search_unavailable",
                            "boundary_unavailable",
                            "duplicate_tool_call",
                            "provider_quota_exceeded",
                        }
                    ),
                    None,
                )
                result["request_id"] = request_id
                result_status = result.get("status", "error")
                if result.get("status") == "quota_exceeded":
                    log_event("application_quota_exceeded", 429)
                    self._send_json(429, result)
                    return
                if result_status in {
                    "not_configured",
                    "auth_unavailable",
                    "provider_quota_exceeded",
                    "provider_model_unavailable",
                    "provider_configuration_error",
                    "provider_unavailable",
                    "provider_error",
                    "provider_invalid_response",
                    "provider_empty_response",
                }:
                    log_event(result_status, 503)
                    self._send_json(503, result)
                    return
                log_event(result_status if result_status != "ok" else "success", 200, failed_tool)
                self._send_json(200, result)
                return
            except (ValueError, TypeError, json.JSONDecodeError) as exc:
                log_event("invalid_request", 400)
                self._send_json(400, {
                    "status": "invalid_request",
                    "error": str(exc),
                    "request_id": request_id,
                })
                return
            except Exception:
                log_event("internal_error", 500)
                self._send_json(500, {
                    "status": "error",
                    "error": "The AI backend could not process this request.",
                    "request_id": request_id,
                })
                return

        if parsed_url.path.rstrip("/") != "/plan":
            self._send_json(404, {"status": "error", "error": "Route not found."})
            return
        if self.headers.get_content_type() != "application/json":
            self._send_json(
                415,
                {"status": "error", "error": "Content-Type must be application/json."},
            )
            return
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length <= 0 or content_length > 4096:
                raise ValueError("invalid body size")
            payload = json.loads(self.rfile.read(content_length))
            if not isinstance(payload, dict):
                raise ValueError("request body must be an object")
            query = urllib.parse.urlencode(
                {
                    key: value
                    for key, value in payload.items()
                    if key in {"from", "to", "origin", "destination", "dest",
                               "passenger", "passenger_type", "when", "avoid"}
                    and isinstance(value, (str, int, float))
                }
            )
        except (ValueError, TypeError, json.JSONDecodeError):
            self._send_json(400, {"status": "error", "error": "Invalid request body."})
            return

        self.path = f"/plan?{query}"
        self.do_GET()

    def do_GET(self):
        parsed_url = urllib.parse.urlparse(self.path)
        path = parsed_url.path.rstrip("/")
        query_params = urllib.parse.parse_qs(parsed_url.query)

        # Health check / status
        if path == "" or path == "/health":
            self._send_json(200, {
                "status": "ok",
                "service": "Mapparaan Transit Planner API",
                "trips": len(_PLANNER.trips) if _PLANNER else 0,
                "stops": _PLANNER.n_stops if _PLANNER else 0,
            })
            return

        # AI endpoint: /ai/health
        if path == "/ai/health":
            self._send_json(200, {
                "status": "ok",
                "service": "Mapparaan AI scaffolding",
                "configured": _AI_SERVICE.provider.available,
                "quota": {
                    "user_daily_limit": _AI_SERVICE.quota_service.USER_DAILY_LIMIT,
                    "user_minute_limit": _AI_SERVICE.quota_service.USER_MINUTE_LIMIT,
                    "global_daily_limit": _AI_SERVICE.quota_service.GLOBAL_DAILY_LIMIT,
                    "reset_timezone": "Asia/Manila",
                },
            })
            return

        # Route planning endpoint: /plan
        if path == "/plan":
            from_param = (
                query_params.get("from", [None])[0]
                or query_params.get("origin", [None])[0]
            )
            to_param = (
                query_params.get("to", [None])[0]
                or query_params.get("destination", [None])[0]
                or query_params.get("dest", [None])[0]
            )
            passenger = (
                query_params.get("passenger", ["general"])[0]
                or query_params.get("passenger_type", ["general"])[0]
            )
            when_param = query_params.get("when", [None])[0]
            when = None
            if when_param:
                try:
                    when = datetime.datetime.fromisoformat(
                        when_param.replace("Z", "+00:00")
                    )
                except ValueError:
                    self._send_json(400, {
                        "status": "error",
                        "error": "Invalid 'when'. Use an ISO-8601 date/time.",
                    })
                    return
            avoid_modes = {
                item.strip().lower()
                for item in query_params.get("avoid", [""])[0].split(",")
                if item.strip()
            }

            origin = parse_coords(from_param)
            destination = parse_coords(to_param)

            if not origin or not destination:
                self._send_json(400, {
                    "status": "error",
                    "error": "Invalid or missing coordinates.",
                })
                return
            if passenger not in {"general", "student", "senior", "pwd"}:
                self._send_json(400, {
                    "status": "error",
                    "error": "Invalid passenger type.",
                })
                return

            origin_in_manila = in_service_area(origin)
            destination_in_manila = in_service_area(destination)
            if not _AREA:
                message = (
                    "The City of Manila boundary could not be verified; route "
                    "planning is unavailable until boundary data is restored."
                )
            elif origin_in_manila != destination_in_manila:
                message = (
                    "Routes between Manila City and locations outside Manila are "
                    "not supported. Choose both locations on the same side of "
                    "the City of Manila boundary."
                )
            else:
                message = None

            if message is not None:
                print("[PLAN] Request rejected by service-area boundary check.")
                self._send_json(200, {
                    "status": "ok",
                    "passenger": passenger,
                    "options": [],
                    "reason": "outside_service_area",
                    "message": message,
                })
                return

            t0 = time.time()
            try:
                options = _PLANNER.plan(
                    origin,
                    destination,
                    passenger=passenger,
                    when=when,
                    avoid_modes=avoid_modes,
                )
                elapsed = time.time() - t0
                print(
                    f"[PLAN] passenger={passenger} options={len(options)} "
                    f"duration={elapsed:.3f}s"
                )
                self._send_json(200, {
                    "status": "ok",
                    "passenger": passenger,
                    "data_notice": (
                        "Routes use circa 2013-15 static GTFS schedules and estimated fares; "
                        "LRT-1 terminal hours are based on LRMC's 2025-03-26 schedule; "
                        "the official LRTA station-closing graphic has no verified publication "
                        "date. No Philippine holiday calendar or live service alerts are included. "
                        "Verify current operator hours before travel."
                    ),
                    "options": options,
                })
            except Exception as error:
                print(f"[ERROR] Planning failed ({type(error).__name__}).")
                self._send_json(500, {
                    "status": "error",
                    "error": "Route planning is temporarily unavailable.",
                })
            return

        # Unknown route
        self._send_json(404, {
            "status": "error",
            "error": f"Route not found: {path}. Available endpoints: /plan, /health",
        })

    def log_message(self, format, *args):
        message = format % args
        request_path = urllib.parse.urlparse(self.path).path
        if self.path and self.path in message:
            message = message.replace(self.path, request_path)
        sys.stdout.write(f"[{self.log_date_time_string()}] {message}\n")
        sys.stdout.flush()


def run_server(host="127.0.0.1", port=8080, data_dir=None):
    global _PLANNER, _AREA
    if host not in {"127.0.0.1", "localhost", "::1"} and not _allowed_origins():
        raise ValueError(
            "Set MAPPARAAN_ALLOWED_ORIGINS before binding beyond loopback."
        )
    resolved_dir = resolve_data_dir(data_dir)
    print("=" * 64)
    print(" Mapparaan Local Transit Planner API")
    print("=" * 64)
    print(f"Loading GTFS & fare data from: {resolved_dir}")
    t0 = time.time()
    _PLANNER = Planner(resolved_dir)
    load_time = time.time() - t0
    print(f"Loaded {len(_PLANNER.trips)} trips and {_PLANNER.n_stops} stops in {load_time:.2f}s.")
    for warning in _PLANNER.warnings:
        print(f"[WARNING] {warning}")
    _AREA = load_service_area(resolved_dir)
    _AI_SERVICE.planner = _PLANNER
    _AI_SERVICE.service_area = _AREA
    print("Service area: strict City of Manila boundary loaded.")
    print("-" * 64)
    print(f"Server listening on http://{host}:{port}/")
    print(f"Local health check: http://localhost:{port}/health")
    print("=" * 64)

    server_class = ThreadingHTTPServer if hasattr(ThreadingHTTPServer, "__mro__") else HTTPServer
    server = server_class((host, port), TransitApiHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        server.server_close()


def main():
    parser = argparse.ArgumentParser(description="Mapparaan Transit Planner API")
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Host interface to bind to (default: 127.0.0.1; use 0.0.0.0 only on a trusted network)",
    )
    parser.add_argument("--port", type=int, default=int(os.environ.get("PORT", 8080)), help="Port to listen on (default: 8080)")
    parser.add_argument("--data-dir", default=None, help="Path to data directory containing gtfs and references")
    args = parser.parse_args()

    run_server(host=args.host, port=args.port, data_dir=args.data_dir)


if __name__ == "__main__":
    main()