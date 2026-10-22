#!/usr/bin/env python3
"""
Local HTTP API for the Mapparaan transit planner. Standard library only.

Start it (from the project root):
    python backend/planner/server.py
    python backend/planner/server.py --data data --port 8000
    python backend/planner/server.py --host 0.0.0.0     # let a phone on your Wi-Fi reach it

Endpoints
    GET /health
    GET /plan?from=14.5918,120.9786&to=14.6567,121.0287
        optional: when=2026-10-19T08:30   (Manila local time, default = now)

Response (JSON):  {"options": [ {title, summary, eta_minutes, fare,
                   fare_discounted, transfers, modes, legs: [...]}, ... ]}
"""
import argparse
import datetime
import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from gtfs_planner import Planner

MANILA = datetime.timezone(datetime.timedelta(hours=8))
LOCK = threading.Lock()  # the planner keeps small caches; keep queries serial


def parse_point(text):
    lat, lon = (float(x) for x in text.split(","))
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        raise ValueError("coordinates out of range")
    return lat, lon


def make_handler(planner):
    class Handler(BaseHTTPRequestHandler):
        def _send(self, status, payload):
            body = json.dumps(payload).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            # Flutter web runs on another origin (localhost:<random port>)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(body)

        def do_OPTIONS(self):
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "*")
            self.end_headers()

        def do_GET(self):
            url = urlparse(self.path)
            query = parse_qs(url.query)

            if url.path == "/health":
                self._send(200, {"status": "ok", "stops": planner.n_stops,
                                 "trips": len(planner.trips)})
                return

            if url.path == "/plan":
                try:
                    origin = parse_point(query["from"][0])
                    dest = parse_point(query["to"][0])
                    when = None
                    if "when" in query:
                        when = datetime.datetime.fromisoformat(query["when"][0])
                        if when.tzinfo is None:
                            when = when.replace(tzinfo=MANILA)
                except (KeyError, ValueError, IndexError) as error:
                    self._send(400, {"error": f"bad request: {error}"})
                    return
                try:
                    with LOCK:
                        options = planner.plan(origin, dest, when=when)
                except Exception as error:  # keep the server alive
                    self._send(500, {"error": f"planner failed: {error}"})
                    return
                self._send(200, {"options": options})
                return

            self._send(404, {"error": "not found"})

        def log_message(self, fmt, *args):
            print("%s - %s" % (self.address_string(), fmt % args))

    return Handler


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data", default=os.path.join(here, "..", "..", "data"),
                        help="path to the data/ folder (default: ../../data)")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()

    print("Loading GTFS data...")
    planner = Planner(args.data)
    print(f"Loaded {planner.n_stops} stops, {len(planner.trips)} trips.")
    server = ThreadingHTTPServer((args.host, args.port), make_handler(planner))
    print(f"Mapparaan planner listening on http://{args.host}:{args.port}  (Ctrl+C to stop)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()