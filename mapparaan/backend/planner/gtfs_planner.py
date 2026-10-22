#!/usr/bin/env python3
"""
Lightweight multimodal transit planner for Metro Manila, built directly on the
patched Sakay GTFS feed (data/gtfs) and Mapparaan's fare config
(data/reference). Standard library only.

It is NOT a timetable router: the feed models jeepneys/buses as always-running
headway services, so a trip is "board whenever one comes, ride N stops".

Preferences
  fastest   - minimise total time
  cheapest  - minimise fare first (1 peso ~ 5 minutes), then time
  fewest    - minimise transfers first, then time

Usage (CLI)
  python3 gtfs_planner.py <data_dir> "14.5918,120.9786" "14.6567,121.0287"
  python3 gtfs_planner.py <data_dir> ORIGIN DEST --passenger student
"""
import csv
import datetime
import heapq
import json
import math
import os
import sys
from collections import defaultdict

# ── tunable assumptions (all documented in the README) ───────────────────────
WALK_SPEED_MPS = 1.2          # ~4.3 km/h
WALK_DETOUR = 1.3             # straight-line -> street distance
TRANSFER_WALK_M = 300         # max walk between two stops when transferring
ACCESS_RADII_M = (600, 1000, 1500)   # walk from origin/dest to first stop
WALK_ONLY_MAX_M = 1200        # offer a walk-only option below this distance
ROAD_DETOUR = 1.3             # straight-line stop distance -> road distance (fares)
MIN_WAIT_ROAD_S = 300         # feed headways for jeep/bus are ~1 min (synthetic)
MIN_WAIT_RAIL_S = 120
SEC_PER_PESO = 300            # "cheapest" trades 1 peso for 5 minutes
WALK_WEIGHT = 1.5             # walking feels longer than riding the same time

# Rail fares are not in the config yet (table: null) -> rough placeholder.
RAIL_FALLBACK = {"base_fare": 15.0, "base_km": 0, "per_km": 1.5}
FARE_SOURCE_LABEL = "Mapparaan fare configuration; verify current fare"

MODE_LABEL = {
    "jeepney": "Jeepney", "bus": "Bus", "uv_express": "UV Express",
    "lrt1": "LRT-1", "lrt2": "LRT-2", "mrt3": "MRT-3", "pnr": "PNR",
    "fort_bus": "Fort Bus",
}
RAIL_MODES = {"lrt1", "lrt2", "mrt3", "pnr"}

PREFS = {
    # transfer_penalty_s, peso_weight_s
    "fastest": (120, 0),
    "cheapest": (120, SEC_PER_PESO),
    "fewest_transfers": (1200, 0),
}


def hav_m(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 6371000 * 2 * math.asin(math.sqrt(a))


def to_sec(t):
    h, m, s = (int(x) for x in t.split(":"))
    return h * 3600 + m * 60 + s


def read_csv(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


class Planner:
    def __init__(self, data_dir):
        gtfs = os.path.join(data_dir, "gtfs")
        ref = os.path.join(data_dir, "reference")

        with open(os.path.join(ref, "fare_config.json"), encoding="utf-8") as f:
            self.fares = json.load(f)
        self.modes_by_route = {
            r["route_id"]: r["mode"]
            for r in read_csv(os.path.join(ref, "route_modes.csv"))
        }

        routes = {r["route_id"]: r for r in read_csv(os.path.join(gtfs, "routes.txt"))}
        stops = read_csv(os.path.join(gtfs, "stops.txt"))
        self.stop_ids = [s["stop_id"] for s in stops]
        self.stop_idx = {sid: i for i, sid in enumerate(self.stop_ids)}
        self.stop_name = [s["stop_name"] for s in stops]
        self.stop_lat = [float(s["stop_lat"]) for s in stops]
        self.stop_lon = [float(s["stop_lon"]) for s in stops]
        self.n_stops = len(stops)

        self.calendar = {c["service_id"]: c for c in read_csv(os.path.join(gtfs, "calendar.txt"))}
        trips = read_csv(os.path.join(gtfs, "trips.txt"))
        freq = {}
        for f in read_csv(os.path.join(gtfs, "frequencies.txt")):
            freq.setdefault(f["trip_id"], []).append(
                (to_sec(f["start_time"]), to_sec(f["end_time"]), int(f["headway_secs"]))
            )

        by_trip = defaultdict(list)
        for s in read_csv(os.path.join(gtfs, "stop_times.txt")):
            by_trip[s["trip_id"]].append(s)

        # per-trip arrays
        self.trips = []
        for t in trips:
            rows = by_trip.get(t["trip_id"])
            if not rows or len(rows) < 2:
                continue
            rows.sort(key=lambda r: int(r["stop_sequence"]))
            sidx = [self.stop_idx[r["stop_id"]] for r in rows if r["stop_id"] in self.stop_idx]
            arr = [to_sec(r["arrival_time"]) for r in rows]
            dep = [to_sec(r["departure_time"]) for r in rows]
            hops = [max(0, arr[i + 1] - dep[i]) for i in range(len(rows) - 1)]
            cum = [0.0]
            for i in range(len(sidx) - 1):
                a, b = sidx[i], sidx[i + 1]
                cum.append(cum[-1] + hav_m(self.stop_lat[a], self.stop_lon[a],
                                           self.stop_lat[b], self.stop_lon[b]))
            rid = t["route_id"]
            self.trips.append({
                "trip_id": t["trip_id"],
                "route_id": rid,
                "service_id": t["service_id"],
                "route_name": routes[rid]["route_long_name"],
                "short_name": routes[rid]["route_short_name"],
                "mode": self.modes_by_route.get(rid, "bus"),
                "stops": sidx,
                "hops": hops,
                "cum_m": cum,
                "freq": freq.get(t["trip_id"], []),
            })

        # grid index for neighbour search (~330 m cells)
        self.cell = 0.003
        self.grid = defaultdict(list)
        for i in range(self.n_stops):
            self.grid[self._cell(self.stop_lat[i], self.stop_lon[i])].append(i)
        self._walk_adj = {}

    # ── geometry helpers ─────────────────────────────────────────────────────
    def _cell(self, lat, lon):
        return (int(lat / self.cell), int(lon / self.cell))

    def stops_within(self, lat, lon, radius_m):
        r = int(radius_m / 111000 / self.cell) + 1
        cx, cy = self._cell(lat, lon)
        found = []
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                for i in self.grid.get((cx + dx, cy + dy), ()):
                    d = hav_m(lat, lon, self.stop_lat[i], self.stop_lon[i])
                    if d <= radius_m:
                        found.append((i, d))
        return found

    def walk_neighbours(self, s):
        if s not in self._walk_adj:
            self._walk_adj[s] = [
                (j, d) for j, d in self.stops_within(
                    self.stop_lat[s], self.stop_lon[s], TRANSFER_WALK_M)
                if j != s
            ]
        return self._walk_adj[s]

    @staticmethod
    def walk_secs(straight_m):
        return straight_m * WALK_DETOUR / WALK_SPEED_MPS

    # ── fares ────────────────────────────────────────────────────────────────
    def fare_cfg(self, mode):
        cfg = self.fares["modes"].get(mode, {})
        if cfg.get("base_fare") is None:
            return RAIL_FALLBACK if mode in RAIL_MODES or not cfg else RAIL_FALLBACK
        return cfg

    def ride_fare(self, mode, km):
        c = self.fare_cfg(mode)
        return round(c["base_fare"] + c["per_km"] * max(0.0, km - c["base_km"]))

    # ── service filtering ────────────────────────────────────────────────────
    def trip_wait_s(self, trip, when):
        """Average wait (s) for this trip at `when`, or None if not running."""
        cal = self.calendar.get(trip["service_id"])
        if cal:
            day = ["monday", "tuesday", "wednesday", "thursday", "friday",
                   "saturday", "sunday"][when.weekday()]
            if cal[day] != "1":
                return None
        secs = when.hour * 3600 + when.minute * 60
        headway = None
        for start, end, hw in trip["freq"]:
            if start <= secs < end:
                headway = hw
                break
        if trip["freq"] and headway is None:
            return None
        floor = MIN_WAIT_RAIL_S if trip["mode"] in RAIL_MODES else MIN_WAIT_ROAD_S
        return max(headway / 2 if headway else floor, floor)

    # ── search ───────────────────────────────────────────────────────────────
    def _search(self, origin, dest, pref, when, avoid_modes=None):
        avoid_modes = avoid_modes or set()
        transfer_pen, peso_w = PREFS[pref]
        ns = self.n_stops

        # runnable trips + node numbering for riding states
        waits, offset, ridx_trip, ridx_pos = {}, {}, [], []
        boardings = defaultdict(list)
        for ti, t in enumerate(self.trips):
            if t["mode"].lower() in avoid_modes:
                continue
            w = self.trip_wait_s(t, when)
            if w is None:
                continue
            waits[ti] = w
            offset[ti] = len(ridx_trip)
            for pos in range(len(t["stops"])):
                ridx_trip.append(ti)
                ridx_pos.append(pos)
                if pos < len(t["stops"]) - 1:
                    boardings[t["stops"][pos]].append((ti, pos))

        def access(point):
            for radius in ACCESS_RADII_M:
                found = self.stops_within(point[0], point[1], radius)
                if found:
                    return found
            return []

        start_access = access(origin)
        end_access = dict(access(dest))
        if not start_access or not end_access:
            return None

        # Node numbering
        #   0 .. ns-1            standing at a stop after getting off a vehicle
        #                        (may walk ONE hop, board, or finish)
        #   ns .. wb-1           riding a trip at a given position
        #   wb .. wb+ns-1        standing at a stop after walking (must board)
        # Allowing only one walk between rides stops the search from "walking
        # the whole city", and ending only after a ride guarantees a transit leg.
        wb = ns + len(ridx_trip)
        START, END = -2, -1
        best, prev, heap = {}, {}, []

        def relax(node, cost, frm):
            if cost < best.get(node, float("inf")):
                best[node] = cost
                prev[node] = frm
                heapq.heappush(heap, (cost, node))

        for s, d in start_access:
            relax(wb + s, self.walk_secs(d) * WALK_WEIGHT, START)

        def board_from(stop, cost, frm):
            for ti, pos in boardings.get(stop, ()):
                t = self.trips[ti]
                c = self.fare_cfg(t["mode"])
                board_fare = max(0.0, c["base_fare"] - c["per_km"] * c["base_km"])
                relax(ns + offset[ti] + pos,
                      cost + waits[ti] + transfer_pen + peso_w * board_fare, frm)

        while heap:
            cost, node = heapq.heappop(heap)
            if cost > best.get(node, float("inf")):
                continue
            if node == END:
                break
            if node >= wb:  # walked to a stop: must board
                board_from(node - wb, cost, node)
            elif node < ns:  # alighted at a stop
                if node in end_access:
                    relax(END, cost + self.walk_secs(end_access[node]) * WALK_WEIGHT, node)
                for j, d in self.walk_neighbours(node):
                    relax(wb + j, cost + self.walk_secs(d) * WALK_WEIGHT, node)
                board_from(node, cost, node)
            else:  # riding
                r = node - ns
                ti, pos = ridx_trip[r], ridx_pos[r]
                t = self.trips[ti]
                came_from = prev[node]
                boarded_here = came_from < ns or came_from >= wb
                if not boarded_here:  # no point getting off where we got on
                    relax(t["stops"][pos], cost, node)  # alight
                if pos + 1 < len(t["stops"]):
                    km = (t["cum_m"][pos + 1] - t["cum_m"][pos]) * ROAD_DETOUR / 1000
                    per_km = self.fare_cfg(t["mode"])["per_km"]
                    relax(node + 1, cost + t["hops"][pos] + peso_w * per_km * km, node)

        if END not in best:
            return None

        path = [END]
        while path[-1] != START:
            path.append(prev[path[-1]])
        path.reverse()
        return self._build_option(path, origin, dest, ridx_trip, ridx_pos, waits, wb)

    def _build_option(self, path, origin, dest, ridx_trip, ridx_pos, waits, wb):
        ns = self.n_stops
        legs, cur = [], None

        def pt(s):
            return [self.stop_lat[s], self.stop_lon[s]]

        def stop_of(n):
            return n - wb if n >= wb else n

        def is_stop(n):
            return n < ns or n >= wb

        for a, b in zip(path, path[1:]):
            if a == -2:  # origin -> first stop
                s = stop_of(b)
                d = hav_m(origin[0], origin[1], self.stop_lat[s], self.stop_lon[s])
                legs.append(self._walk_leg(list(origin), pt(s), "Your location", self.stop_name[s], d))
            elif b == -1:  # last stop -> destination
                s = stop_of(a)
                d = hav_m(self.stop_lat[s], self.stop_lon[s], dest[0], dest[1])
                legs.append(self._walk_leg(pt(s), list(dest), self.stop_name[s], "Destination", d))
            elif is_stop(a) and b >= wb:  # transfer walk
                sa, sb = stop_of(a), stop_of(b)
                d = hav_m(self.stop_lat[sa], self.stop_lon[sa], self.stop_lat[sb], self.stop_lon[sb])
                legs.append(self._walk_leg(pt(sa), pt(sb), self.stop_name[sa], self.stop_name[sb], d))
            elif is_stop(a):  # board
                r = b - ns
                cur = {"ti": ridx_trip[r], "board": ridx_pos[r], "alight": ridx_pos[r]}
            elif not is_stop(b):  # riding on
                cur["alight"] = ridx_pos[b - ns]
            else:  # alight
                cur["alight"] = ridx_pos[a - ns]
                legs.append(self._ride_leg(cur, waits))
                cur = None
        return [l for l in legs if not (l["type"] == "walk" and l["meters"] < 30)]

    def _walk_leg(self, p_from, p_to, n_from, n_to, d):
        return {
            "type": "walk", "from": n_from, "to": n_to,
            "minutes": round(self.walk_secs(d) / 60),
            "meters": round(d * WALK_DETOUR),
            "path": [p_from, p_to],
        }

    def _ride_leg(self, cur, waits):
        t = self.trips[cur["ti"]]
        b, a = cur["board"], cur["alight"]
        km = (t["cum_m"][a] - t["cum_m"][b]) * ROAD_DETOUR / 1000
        ride_s = sum(t["hops"][b:a])
        sids = t["stops"][b:a + 1]
        return {
            "type": "ride", "mode": t["mode"], "mode_label": MODE_LABEL.get(t["mode"], t["mode"]),
            "route_id": t["route_id"], "route_code": t["short_name"] or t["route_id"],
            "route_name": t["route_name"],
            "from": self.stop_name[t["stops"][b]], "to": self.stop_name[t["stops"][a]],
            "stops": a - b,
            "wait_minutes": round(waits[cur["ti"]] / 60),
            "minutes": round(ride_s / 60),
            "km": round(km, 1),
            "fare": self.ride_fare(t["mode"], km),
            "path": [[self.stop_lat[s], self.stop_lon[s]] for s in sids],
        }

    # ── public API ───────────────────────────────────────────────────────────
    def plan(self, origin, dest, passenger="general", when=None):
        """origin/dest = (lat, lon). Returns a list of route options.

        `passenger` is accepted for API symmetry; fares come back both regular
        and discounted, so it does not change the result."""
        when = when or datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8)))
        # Both the regular and the discounted fare are always returned; the
        # client picks which one to show based on the passenger type.
        discount = self.fares["discount"]["multiplier"]
        options, seen = [], set()

        direct_m = hav_m(origin[0], origin[1], dest[0], dest[1])
        if direct_m <= WALK_ONLY_MAX_M:
            leg = self._walk_leg(list(origin), list(dest), "Your location", "Destination", direct_m)
            options.append(self._summarise("walk", [leg], discount))

        titles = {"fastest": "Fastest route", "cheapest": "Cheapest route",
                  "fewest_transfers": "Fewest transfers"}
        for pref in ("fastest", "cheapest", "fewest_transfers"):
            legs = self._search(origin, dest, pref, when, avoid_modes=avoid_modes)
            if not legs:
                continue
            # Keep one result for each preference even when the same physical
            # route wins multiple cost functions. The client uses the
            # preference label to let commuters switch between route goals.
            key = (pref, tuple(l.get("route_id", "w") for l in legs))
            if key in seen:
                continue
            seen.add(key)
            opt = self._summarise(pref, legs, discount)
            opt["title"] = titles[pref]
            options.append(opt)
        return options

    def _summarise(self, pref, legs, discount):
        rides = [l for l in legs if l["type"] == "ride"]
        minutes = sum(l["minutes"] + l.get("wait_minutes", 0) for l in legs)
        fare = sum(l["fare"] for l in rides)
        parts = []
        for l in legs:
            if l["type"] == "walk":
                parts.append(f"Walk {l['minutes']} min")
            else:
                parts.append(f"{l['mode_label']} {l['route_code']} ({l['minutes']} min)")
        return {
            "preference": pref,
            "title": "Walk" if pref == "walk" else pref,
            "summary": " → ".join(parts),
            "eta_minutes": minutes,
            "fare": fare,
            "fare_discounted": round(fare * discount),
            "fare_source": FARE_SOURCE_LABEL,
            "transfers": max(0, len(rides) - 1),
            "modes": sorted({l["mode"] for l in rides}),
            "legs": legs,
        }


def main():
    args = sys.argv[1:]
    if len(args) < 3:
        print(__doc__)
        sys.exit(1)
    data_dir = args[0]
    o = tuple(float(x) for x in args[1].split(","))
    d = tuple(float(x) for x in args[2].split(","))
    passenger = "general"
    if "--passenger" in args:
        passenger = args[args.index("--passenger") + 1]
    planner = Planner(data_dir)
    for opt in planner.plan(o, d, passenger=passenger):
        print(f"\n== {opt['title']}: {opt['eta_minutes']} min, "
              f"P{opt['fare']} (discounted P{opt['fare_discounted']}), "
              f"{opt['transfers']} transfer(s)")
        for l in opt["legs"]:
            if l["type"] == "walk":
                print(f"   walk {l['minutes']} min ({l['meters']} m): {l['from']} -> {l['to']}")
            else:
                print(f"   {l['mode_label']} {l['route_code']} {l['route_name']}: "
                      f"{l['from']} -> {l['to']} | wait {l['wait_minutes']} + ride "
                      f"{l['minutes']} min, {l['stops']} stops, {l['km']} km, P{l['fare']}")


if __name__ == "__main__":
    main()