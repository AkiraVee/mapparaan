#!/usr/bin/env python3
"""
Lightweight multimodal transit planner for Metro Manila, built directly on the
patched Sakay GTFS feed (data/gtfs) and Mapparaan's fare config
(data/reference). Standard library only.

It is not an exact-timetable router: the feed uses service calendars and
headway windows, so the planner estimates whether a trip can be boarded and
how long to wait before riding its stop sequence.

Preferences
  fastest   - minimise total time
  cheapest  - minimise fare first (1 peso ~ 5 minutes), then time
  fewest    - minimise transfers first, then time

Usage (CLI)
  python3 gtfs_planner.py <data_dir> "14.5918,120.9786" "14.6567,121.0287"
  python3 gtfs_planner.py <data_dir> ORIGIN DEST --passenger student
  python3 gtfs_planner.py <data_dir> ORIGIN DEST --avoid jeepney,bus
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
PARTIAL_PROGRESS_MIN_M = 100  # avoid partial transit legs that barely advance
NEXT_SERVICE_MAX_WAIT_S = 2 * 60 * 60
ROAD_DETOUR = 1.3             # straight-line stop distance -> road distance (fares)
MIN_WAIT_ROAD_S = 300         # feed headways for jeep/bus are ~1 min (synthetic)
MIN_WAIT_RAIL_S = 120
SEC_PER_PESO = 300            # "cheapest" trades 1 peso for 5 minutes
WALK_WEIGHT = 1.5             # walking feels longer than riding the same time

# Fares (fare_config.json, LTFRB fare guides effective 2026-09-28)
FARE_QUANTUM = 0.25           # road fares round to the nearest P0.25
# The feed only says "jeepney" or "bus", not traditional vs modern/aircon, so every
# road ride gets a range: (lower-fare config key, higher-fare config key).
ROAD_FARE_MODES = {
    "jeepney": ("jeepney", "modern_jeepney"),
    "bus": ("bus", "aircon_bus"),
}
FARE_SOURCE_LABEL = "Estimated from LTFRB, LRTA and LRMC fare tables; verify before travel."
RAIL_FARE_NOTE = " Rail fares assume a Beep (stored value) card."

MODE_LABEL = {
    "jeepney": "Jeepney", "bus": "Bus", "uv_express": "UV Express",
    "lrt1": "LRT-1", "lrt2": "LRT-2", "mrt3": "MRT-3",
    "fort_bus": "Fort Bus",
}
RAIL_MODES = {"lrt1", "lrt2", "mrt3"}

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


def round_fare(value, step=FARE_QUANTUM):
    """Round half up to a multiple of `step` (Python's round() would round half to even)."""
    if not step:
        return round(value, 2)
    return math.floor(value / step + 0.5 + 1e-9) * step


def norm_name(name):
    return " ".join(str(name).lower().split())


MANILA_TZ = datetime.timezone(datetime.timedelta(hours=8))


def to_manila(when=None):
    """Return `when` as a Manila wall-clock time. Timetables and calendars are Manila
    local time, so an aware time (e.g. UTC from a phone) is converted; a naive time is
    taken to already be Manila time; None means now."""
    if when is None:
        return datetime.datetime.now(MANILA_TZ)
    if when.tzinfo is not None:
        return when.astimezone(MANILA_TZ)
    return when


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
        self.warnings = []
        self._init_fares()

        self.calendar = {c["service_id"]: c for c in read_csv(os.path.join(gtfs, "calendar.txt"))}
        calendar_dates_path = os.path.join(gtfs, "calendar_dates.txt")
        self.calendar_exceptions = defaultdict(dict)
        if os.path.isfile(calendar_dates_path):
            for exception in read_csv(calendar_dates_path):
                self.calendar_exceptions[exception["service_id"]][
                    exception["date"]
                ] = exception["exception_type"]
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
        skipped = []
        for t in trips:
            rows = by_trip.get(t["trip_id"])
            if not rows or len(rows) < 2:
                skipped.append(t["trip_id"])
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

        if skipped:
            self.warnings.append(
                f"{len(skipped)} trip(s) in trips.txt have fewer than 2 stop_times and are "
                f"ignored: {', '.join(skipped[:5])}{' ...' if len(skipped) > 5 else ''}")
        known = {t["trip_id"] for t in trips}
        orphans = sorted(set(by_trip) - known)
        if orphans:
            self.warnings.append(
                f"stop_times.txt has rows for {len(orphans)} trip id(s) that are not in "
                f"trips.txt and are ignored: {', '.join(orphans[:5])}{' ...' if len(orphans) > 5 else ''}")

        # grid index for neighbour search (~330 m cells)
        self.cell = 0.003
        self.grid = defaultdict(list)
        for i in range(self.n_stops):
            self.grid[self._cell(self.stop_lat[i], self.stop_lon[i])].append(i)
        self._walk_adj = {}

        for mode in sorted({t["mode"] for t in self.trips}):
            if mode in RAIL_MODES and mode not in self.rail:
                self.warnings.append(f"No usable rail fare table for '{mode}'; its fares are estimates.")
            elif mode not in RAIL_MODES and mode not in self.road:
                self.warnings.append(f"No fare rules for '{mode}'; priced like a bus.")

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
    _ROAD_KEYS = ("base_fare", "base_km", "per_km", "discounted_base_fare", "discounted_per_km")

    def _road_cfg(self, key):
        """A road fare rule, only if it is verified and complete; otherwise None."""
        cfg = self.fares["modes"].get(key)
        if (cfg and cfg.get("verified") is True
                and all(cfg.get(k) is not None for k in self._ROAD_KEYS)):
            return cfg
        return None

    def _init_fares(self):
        modes = self.fares["modes"]

        # Road modes: (lower fare rule, higher fare rule)
        self.road = {}
        for mode, (low_key, high_key) in ROAD_FARE_MODES.items():
            low = self._road_cfg(low_key)
            if low is None:
                continue
            self.road[mode] = (low, self._road_cfg(high_key) or low)
        for required in ("jeepney", "bus"):
            if required not in self.road:
                raise ValueError(f"fare_config.json has no verified, complete fare for '{required}'")

        # Rail modes: station-to-station tables
        feed_names = {norm_name(n) for n in self.stop_name}
        self.rail = {}
        self.promo_modes = {}
        for mode in sorted(RAIL_MODES):
            cfg = modes.get(mode)
            if not cfg or cfg.get("type") != "station_matrix":
                continue
            tickets = cfg["ticket_types"]
            table = tickets.get(cfg.get("default_ticket")) or tickets.get("all")
            if not table:
                continue
            station_idx = {name: i for i, name in enumerate(cfg["stations"])}
            lookup = {norm_name(feed_name): station_idx[station]
                      for feed_name, station in cfg.get("feed_stop_names", {}).items()
                      if station in station_idx}
            missing = [n for n in cfg.get("feed_stop_names", {}) if norm_name(n) not in feed_names]
            if missing:
                self.warnings.append(
                    f"{mode}: {len(missing)} fare-table stop name(s) not found in stops.txt: "
                    + ", ".join(missing))
            reg, dis = table["regular"], table["discounted"]
            promo = self._active_promo(cfg.get("temporary_discount"))
            if promo:
                # A temporary discount for ALL passengers (e.g. the 2026 LRT-2 / MRT-3
                # 50% cut): the regular fare is the discounted matrix.
                reg = dis
                self.promo_modes[mode] = promo
                self.warnings.append(
                    f"{mode}: temporary all-passenger discount is applied "
                    f"(since {promo.get('effective', '?')}); set temporary_discount.active "
                    f"to false in fare_config.json when it ends.")
            n = len(reg)
            off_r = [reg[i][j] for i in range(n) for j in range(n) if i != j and reg[i][j] is not None]
            off_d = [dis[i][j] for i in range(n) for j in range(n) if i != j and dis[i][j] is not None]
            diag = [reg[i][i] for i in range(n) if reg[i][i] is not None]
            board = min(diag) if diag else min(off_r)
            self.rail[mode] = {
                "lookup": lookup, "regular": reg, "discounted": dis,
                "mean_regular": sum(off_r) / len(off_r), "mean_discounted": sum(off_d) / len(off_d),
                # search heuristic only (the real fare comes from the table afterwards)
                "board": board, "per_stop": (max(off_r) - board) / max(1, n - 1),
            }

    @staticmethod
    def _active_promo(promo):
        """The temporary_discount block if it is switched on and has not ended, else None."""
        if not isinstance(promo, dict) or promo.get("active") is not True:
            return None
        if promo.get("regular_uses") != "discounted":
            return None
        end = promo.get("end_date")
        if end:
            try:
                if datetime.date.today() > datetime.date.fromisoformat(end):
                    return None
            except ValueError:
                return None
        return promo

    def _search_cost(self, mode):
        """(boarding fee, per-km, per-stop) used only to rank routes for 'cheapest'."""
        r = self.rail.get(mode)
        if r:
            return (r["board"], 0.0, r["per_stop"])
        low = (self.road.get(mode) or self.road["bus"])[0]
        return (max(0.0, low["base_fare"] - low["per_km"] * low["base_km"]), low["per_km"], None)

    @staticmethod
    def _distance_fare(cfg, km, discounted):
        base = cfg["discounted_base_fare"] if discounted else cfg["base_fare"]
        per_km = cfg["discounted_per_km"] if discounted else cfg["per_km"]
        return round_fare(base + per_km * max(0.0, km - cfg["base_km"]),
                          cfg.get("round_to") or FARE_QUANTUM)

    def rail_fare(self, mode, from_name, to_name):
        """(regular, discounted, exact) from the station table, or None if the mode has none.
        `exact` is False when a stop name is not in the table and the fare is an average."""
        r = self.rail.get(mode)
        if not r:
            return None
        i = r["lookup"].get(norm_name(from_name))
        j = r["lookup"].get(norm_name(to_name))
        if i is not None and j is not None:
            reg, dis = r["regular"][i][j], r["discounted"][i][j]
            if reg is not None and dis is not None:
                return float(reg), float(dis), True
        return (round_fare(r["mean_regular"]), round_fare(r["mean_discounted"]), False)

    def leg_fares(self, mode, km, from_name="", to_name=""):
        """Fares for one ride leg. Road legs get a range (traditional/ordinary up to
        modern/aircon); rail legs get one exact table fare. Student, senior and PWD
        fares use each mode's own discount (20% road, 50% rail)."""
        if mode in RAIL_MODES:
            got = self.rail_fare(mode, from_name, to_name)
            if got:
                reg, dis, exact = got
                return {"fare": reg, "fare_max": reg, "fare_discounted": dis,
                        "fare_discounted_max": dis, "estimated": not exact}
        low, high = self.road.get(mode) or self.road["bus"]
        fare = self._distance_fare(low, km, False)
        disc = self._distance_fare(low, km, True)
        return {
            "fare": fare,
            "fare_max": max(fare, self._distance_fare(high, km, False)),
            "fare_discounted": disc,
            "fare_discounted_max": max(disc, self._distance_fare(high, km, True)),
            "estimated": True,
        }

    # ── service filtering ────────────────────────────────────────────────────
    def trip_wait_s(self, trip, when, max_wait_s=None):
        """Estimated wait (s) for an active window, or its next window if allowed."""
        when = to_manila(when)
        cal = self.calendar.get(trip["service_id"])
        local_secs = when.hour * 3600 + when.minute * 60 + when.second
        candidates = [(when.date(), local_secs)]
        if trip["freq"] and any(end > 86400 for _, end, _ in trip["freq"]):
            previous_date = when.date() - datetime.timedelta(days=1)
            candidates.append((previous_date, local_secs + 86400))

        for service_day, service_secs in candidates:
            service_date = service_day.strftime("%Y%m%d")
            exception = self.calendar_exceptions.get(trip["service_id"], {}).get(service_date)
            if exception == "2":
                continue
            if exception == "1":
                service_active = True
            elif cal:
                if service_date < cal["start_date"] or service_date > cal["end_date"]:
                    continue
                day = ["monday", "tuesday", "wednesday", "thursday", "friday",
                       "saturday", "sunday"][service_day.weekday()]
                service_active = cal[day] == "1"
            else:
                # Without a calendar, do not invent a rail schedule.
                service_active = trip["mode"] not in RAIL_MODES
            if not service_active:
                continue

            headway = None
            window_end = None
            future_start = None
            floor = MIN_WAIT_RAIL_S if trip["mode"] in RAIL_MODES else MIN_WAIT_ROAD_S
            for start, end, hw in trip["freq"]:
                if start <= service_secs < end:
                    headway = hw
                    window_end = end
                    break
                if max_wait_s is not None and service_secs < start:
                    if future_start is None or start < future_start[0]:
                        future_start = (start, end, hw)
            if trip["freq"] and headway is None:
                if future_start is None:
                    continue
                start, window_end, headway = future_start
                estimated_boarding_wait = max(headway / 2, floor)
                wait = start - service_secs + estimated_boarding_wait
                if wait > max_wait_s:
                    continue
                if start + estimated_boarding_wait >= window_end:
                    continue
                return wait
            if not trip["freq"] and trip["mode"] in RAIL_MODES:
                continue

            wait = max(headway / 2 if headway else floor, floor)
            if window_end is not None and service_secs + wait >= window_end:
                continue
            return wait
        return None

    # ── search ───────────────────────────────────────────────────────────────
    def _search(self, origin, dest, pref, when, avoid_modes=None):
        avoid_modes = avoid_modes or set()
        transfer_pen, peso_w = PREFS[pref]
        ns = self.n_stops

        # Trip availability is checked when each boarding is reached; a route may
        # cross a service-window boundary while walking or transferring.
        offset, ridx_trip, ridx_pos = {}, [], []
        boardings = defaultdict(list)
        for ti, t in enumerate(self.trips):
            if t["mode"].lower() in avoid_modes:
                continue
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
        if not start_access:
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
        labels, node_labels, heap = [], defaultdict(list), []

        def relax(node, cost, elapsed, previous, wait_s=None, next_service=False):
            current = node_labels[node]
            if any(
                labels[index]["active"]
                and labels[index]["cost"] <= cost
                and labels[index]["elapsed"] <= elapsed
                for index in current
            ):
                return
            for index in current:
                label = labels[index]
                if label["active"] and cost <= label["cost"] and elapsed <= label["elapsed"]:
                    label["active"] = False
            index = len(labels)
            labels.append({
                "node": node,
                "cost": cost,
                "elapsed": elapsed,
                "previous": previous,
                "wait_s": wait_s,
                "next_service": next_service,
                "active": True,
            })
            current.append(index)
            heapq.heappush(heap, (cost, index))

        for s, d in start_access:
            walk_s = self.walk_secs(d)
            relax(wb + s, walk_s * WALK_WEIGHT, walk_s, None)

        def board_from(stop, label_index):
            label = labels[label_index]
            for ti, pos in boardings.get(stop, ()):
                board_time = when + datetime.timedelta(seconds=label["elapsed"])
                wait_s = self.trip_wait_s(self.trips[ti], board_time)
                next_service = False
                if wait_s is None:
                    wait_s = self.trip_wait_s(
                        self.trips[ti],
                        board_time,
                        max_wait_s=NEXT_SERVICE_MAX_WAIT_S,
                    )
                    next_service = wait_s is not None
                if wait_s is None:
                    continue
                board_fare = self._search_cost(self.trips[ti]["mode"])[0]
                relax(ns + offset[ti] + pos,
                      label["cost"] + wait_s + transfer_pen + peso_w * board_fare,
                      label["elapsed"] + wait_s,
                      label_index,
                      wait_s=wait_s,
                      next_service=next_service)

        end_label = None
        partial_label = None
        partial_remaining_m = None
        origin_to_dest_m = hav_m(origin[0], origin[1], dest[0], dest[1])
        while heap:
            _, label_index = heapq.heappop(heap)
            label = labels[label_index]
            if not label["active"]:
                continue
            node, cost, elapsed = label["node"], label["cost"], label["elapsed"]
            if node == END:
                end_label = label_index
                break
            if node >= wb:  # walked to a stop: must board
                board_from(node - wb, label_index)
            elif node < ns:  # alighted at a stop
                if end_label is None:
                    stop_distance = hav_m(
                        self.stop_lat[node],
                        self.stop_lon[node],
                        dest[0],
                        dest[1],
                    )
                    if stop_distance + PARTIAL_PROGRESS_MIN_M < origin_to_dest_m:
                        candidate = (
                            stop_distance,
                            elapsed,
                            label_index,
                        )
                        current_best = (
                            partial_remaining_m,
                            labels[partial_label]["elapsed"],
                            partial_label,
                        ) if partial_label is not None else None
                        if current_best is None or candidate < current_best:
                            partial_label = label_index
                            partial_remaining_m = stop_distance
                if node in end_access:
                    walk_s = self.walk_secs(end_access[node])
                    relax(
                        END,
                        cost + walk_s * WALK_WEIGHT,
                        elapsed + walk_s,
                        label_index,
                    )
                for j, d in self.walk_neighbours(node):
                    walk_s = self.walk_secs(d)
                    relax(
                        wb + j,
                        cost + walk_s * WALK_WEIGHT,
                        elapsed + walk_s,
                        label_index,
                    )
                board_from(node, label_index)
            else:  # riding
                r = node - ns
                ti, pos = ridx_trip[r], ridx_pos[r]
                t = self.trips[ti]
                previous = label["previous"]
                came_from = labels[previous]["node"]
                boarded_here = came_from < ns or came_from >= wb
                if not boarded_here:  # no point getting off where we got on
                    relax(t["stops"][pos], cost, elapsed, label_index)  # alight
                if pos + 1 < len(t["stops"]):
                    km = (t["cum_m"][pos + 1] - t["cum_m"][pos]) * ROAD_DETOUR / 1000
                    _, per_km, per_stop = self._search_cost(t["mode"])
                    hop_fare = per_stop if per_stop is not None else per_km * km
                    hop_s = t["hops"][pos]
                    relax(
                        node + 1,
                        cost + hop_s + peso_w * hop_fare,
                        elapsed + hop_s,
                        label_index,
                    )

        terminal_label = end_label if end_label is not None else partial_label
        if terminal_label is None:
            return None

        path_labels = []
        current = terminal_label
        while current is not None:
            path_labels.append(current)
            current = labels[current]["previous"]
        path_labels.reverse()
        path = [START] + [labels[index]["node"] for index in path_labels]
        waits = {
            ridx_trip[labels[index]["node"] - ns]: labels[index]["wait_s"]
            for index in path_labels
            if labels[index]["wait_s"] is not None
        }
        legs = self._build_option(
            path,
            origin,
            dest,
            ridx_trip,
            ridx_pos,
            waits,
            wb,
        )
        is_next_service = any(labels[index]["next_service"] for index in path_labels)
        return (
            legs,
            None if end_label is not None else partial_remaining_m,
            is_next_service,
        )

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
        fares = self.leg_fares(t["mode"], km, self.stop_name[sids[0]], self.stop_name[sids[-1]])
        return {
            "type": "ride", "mode": t["mode"], "mode_label": MODE_LABEL.get(t["mode"], t["mode"]),
            "route_id": t["route_id"], "route_code": t["short_name"] or t["route_id"],
            "route_name": t["route_name"],
            "from": self.stop_name[t["stops"][b]], "to": self.stop_name[t["stops"][a]],
            "stops": a - b,
            "wait_minutes": round(waits[cur["ti"]] / 60),
            "minutes": round(ride_s / 60),
            "km": round(km, 1),
            "fare": fares["fare"],
            "fare_max": fares["fare_max"],
            "fare_discounted": fares["fare_discounted"],
            "fare_discounted_max": fares["fare_discounted_max"],
            "fare_estimated": fares["estimated"],
            "path": [[self.stop_lat[s], self.stop_lon[s]] for s in sids],
        }

    # ── public API ───────────────────────────────────────────────────────────
    def plan(self, origin, dest, passenger="general", when=None, avoid_modes=None):
        """origin/dest = (lat, lon). Returns a list of route options.

        `passenger` is accepted for API symmetry; fares come back both regular
        and discounted, so it does not change the result. `avoid_modes` is a set
        of mode names (e.g. {"jeepney"}) whose routes are left out of the search."""
        when = to_manila(when)
        avoid_modes = {str(m).strip().lower() for m in (avoid_modes or ()) if str(m).strip()}
        # Both the regular and the discounted fare are always returned; the
        # client picks which one to show based on the passenger type.
        options, seen = [], set()

        direct_m = hav_m(origin[0], origin[1], dest[0], dest[1])
        walk_eta = None
        if direct_m <= WALK_ONLY_MAX_M:
            leg = self._walk_leg(list(origin), list(dest), "Your location", "Destination", direct_m)
            walk_opt = self._summarise("walk", [leg])
            walk_eta = walk_opt["eta_minutes"]
            options.append(walk_opt)

        titles = {"fastest": "Fastest route", "cheapest": "Cheapest route",
                  "fewest_transfers": "Fewest transfers"}
        for pref in ("fastest", "cheapest", "fewest_transfers"):
            search_result = self._search(
                origin,
                dest,
                pref,
                when,
                avoid_modes=avoid_modes,
            )
            if not search_result:
                continue
            legs, remaining_distance_m, is_next_service = search_result
            # Keep one result for each preference even when the same physical
            # route wins multiple cost functions. The client uses the
            # preference label to let commuters switch between route goals.
            key = (pref, tuple(l.get("route_id", "w") for l in legs))
            if key in seen:
                continue
            seen.add(key)
            opt = self._summarise(pref, legs)
            if is_next_service:
                opt["is_next_service"] = True
                opt["next_service_message"] = (
                    "No transit is scheduled at the selected time. This route "
                    "uses the next GTFS service window within 2 hours; waiting "
                    "time is estimated from frequency data."
                )
                opt["title"] = f"Next service: {titles[pref]}"
            if remaining_distance_m is not None:
                end_stop = next(
                    (leg["to"] for leg in reversed(legs) if leg["type"] == "ride"),
                    "the last served stop",
                )
                opt["is_partial"] = True
                opt["remaining_distance_m"] = round(remaining_distance_m)
                opt["partial_message"] = (
                    f"This verified transit segment ends at {end_stop}. "
                    f"The destination is about {remaining_distance_m / 1000:.1f} km "
                    "away in a straight line; no complete transit itinerary was found."
                )
                label = f"Next service: {titles[pref]}" if is_next_service else titles[pref]
                opt["title"] = f"{label} (partial)"
                options.append(opt)
                continue
            # A paid ride that is not faster than the free walk is never worth offering.
            if walk_eta is not None and opt["eta_minutes"] >= walk_eta:
                continue
            opt["title"] = titles[pref]
            options.append(opt)
        return options

    def _summarise(self, pref, legs):
        rides = [l for l in legs if l["type"] == "ride"]
        minutes = sum(l["minutes"] + l.get("wait_minutes", 0) for l in legs)

        def total(key):
            return round(sum(l[key] for l in rides), 2)

        has_rail = any(l["mode"] in RAIL_MODES for l in rides)
        if not rides:
            source = "Walking: no fare."
        else:
            source = FARE_SOURCE_LABEL + (RAIL_FARE_NOTE if has_rail else "")
            promo_modes = sorted({l["mode"] for l in rides if l["mode"] in self.promo_modes})
            if promo_modes:
                names = " and ".join(MODE_LABEL.get(m, m) for m in promo_modes)
                source += f" {names} fares include the temporary 50% discount for all passengers."
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
            # Regular and student/senior/PWD fares, each as the lowest fare and the
            # highest fare (modern jeepney / aircon bus). Rail legs have one fare.
            "fare": total("fare"),
            "fare_max": total("fare_max"),
            "fare_discounted": total("fare_discounted"),
            "fare_discounted_max": total("fare_discounted_max"),
            "fare_estimated": any(l["fare_estimated"] for l in rides),
            "fare_source": source,
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
    avoid = set()
    if "--avoid" in args:
        avoid = {m for m in args[args.index("--avoid") + 1].split(",") if m}
    planner = Planner(data_dir)
    for warning in planner.warnings:
        print(f"[warning] {warning}")
    for opt in planner.plan(o, d, passenger=passenger, avoid_modes=avoid):
        print(f"\n== {opt['title']}: {opt['eta_minutes']} min, "
              f"P{opt['fare']:g} up to P{opt['fare_max']:g} "
              f"(discounted P{opt['fare_discounted']:g} up to P{opt['fare_discounted_max']:g}), "
              f"{opt['transfers']} transfer(s)")
        for l in opt["legs"]:
            if l["type"] == "walk":
                print(f"   walk {l['minutes']} min ({l['meters']} m): {l['from']} -> {l['to']}")
            else:
                print(f"   {l['mode_label']} {l['route_code']} {l['route_name']}: "
                      f"{l['from']} -> {l['to']} | wait {l['wait_minutes']} + ride "
                      f"{l['minutes']} min, {l['stops']} stops, {l['km']} km, P{l['fare']:g}")


if __name__ == "__main__":
    main()