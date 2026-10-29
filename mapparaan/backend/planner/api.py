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
  The data covers the City of Manila only. If the origin or destination is more
  than the planner's maximum walk to a stop (see SERVICE_MARGIN_M) outside the
  boundary in <data>/references/manila_boundary.geojson, /plan answers 200 with
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
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer, HTTPServer

# Ensure current directory is on sys.path for direct imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gtfs_planner import Planner

try:
    from gtfs_planner import ACCESS_RADII_M
    SERVICE_MARGIN_M = max(ACCESS_RADII_M)  # farthest the planner walks to a first stop
except ImportError:
    SERVICE_MARGIN_M = 1500

# Global planner instance loaded once at startup
_PLANNER = None
# Outer ring(s) of the City of Manila boundary, or None if the file is missing
_AREA = None


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
    )
    if not all(os.path.isfile(path) for path in required):
        raise FileNotFoundError(
            "Transit planner data is incomplete; check the configured data directory."
        )
    return resolved


def load_service_area(data_dir):
    """Reads manila_boundary.geojson from <data_dir>/references (or reference)."""
    for folder in ("references", "reference"):
        path = os.path.join(data_dir, folder, "manila_boundary.geojson")
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                gj = json.load(f)
            geom = gj["features"][0]["geometry"] if "features" in gj else gj["geometry"]
            polys = [geom["coordinates"]] if geom["type"] == "Polygon" else geom["coordinates"]
            return [p[0] for p in polys]
    return None


def _in_ring(lon, lat, ring):
    inside, j = False, len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i][0], ring[i][1]
        xj, yj = ring[j][0], ring[j][1]
        if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def _dist_to_ring_m(lon, lat, ring):
    best, kx, ky = 1e12, 111320.0 * math.cos(math.radians(lat)), 111320.0
    for p, q in zip(ring, ring[1:] + ring[:1]):
        ax, ay = (p[0] - lon) * kx, (p[1] - lat) * ky
        bx, by = (q[0] - lon) * kx, (q[1] - lat) * ky
        dx, dy = bx - ax, by - ay
        seg = dx * dx + dy * dy
        t = 0.0 if seg == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / seg))
        best = min(best, math.hypot(ax + t * dx, ay + t * dy))
    return best


def in_service_area(point):
    """True if point (lat, lon) is inside Manila or within walking reach of it.
    With no boundary file loaded nothing is blocked."""
    if _AREA is None:
        return True
    lat, lon = point
    if any(_in_ring(lon, lat, r) for r in _AREA):
        return True
    return min(_dist_to_ring_m(lon, lat, r) for r in _AREA) <= SERVICE_MARGIN_M


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
            self.send_header("Access-Control-Allow-Headers", "Content-Type")
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

            # Data covers the City of Manila only: say so instead of returning a
            # bare empty list the app would mistake for "no route found".
            if not (in_service_area(origin) and in_service_area(destination)):
                print("[PLAN] Request outside service area.")
                self._send_json(200, {
                    "status": "ok",
                    "passenger": passenger,
                    "options": [],
                    "reason": "outside_service_area",
                    "message": "Mapparaan currently covers the City of Manila only.",
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
    print("Service area: City of Manila boundary loaded." if _AREA else
          "Service area: manila_boundary.geojson not found, not restricting requests.")
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