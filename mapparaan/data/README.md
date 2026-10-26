# Mapparaan transit data

Static, schedule-based transit data **for the City of Manila only**. The routing
backend (`backend/planner`) reads `gtfs/` and `reference/`; the Flutter app talks
to that backend, not to these files directly.

## What is in the feed

531 stops, 599 routes (561 jeepney, 36 bus, LRT-1, LRT-2), 663 trips, 11,174 stop
times, 7 service patterns (6 from the source feed plus `FIX_SUNDAY`) and 5 shapes
(LRT-1, LRT-2 and one jeepney route).

## Scope: City of Manila

The original source feed is not stored in this repository; provide it separately
when rebuilding. `gtfs/` is patched and clipped to the official City of Manila
boundary (`reference/manila_boundary.geojson`, PSGC 1380600000, from
faeldon/philippines-json-maps, 2023, MIT):

- a stop is kept if it is inside the boundary or within 50 m of its edge
  (`--tolerance-m 50`), except when its name clearly identifies another city
- each trip is cut into runs of consecutive inside-stops; a trip that leaves and
  re-enters becomes two trips (`_a`, `_b`); runs under 2 stops are dropped. Trips
  `726109`, `726259` and `726260` are split this way
- shapes are cut to the inside part, and anything left unused is removed
- MRT-3 does not enter the City of Manila, so it is not in the feed
- PNR Metro Commuter (`ROUTE_880872`) has no service in Manila, so it is excluded
  (its route, 10 trips, 9 stops, agency, 2 service patterns and 2 shapes)
- some LTFRB stop names say Quezon City / Caloocan: those are LTFRB's labels, and the
  coordinates are inside the boundary

**Border stops.** Source coordinates are rounded to about 3 decimals (up to ~55 m error),
so the 50 m tolerance helps retain stops near the city boundary without adding stops
whose names identify another city. Use `--tolerance-m 0` only when a strict polygon
clip is specifically required.

## Layout

```
data/
├── README.md                this file
├── gtfs/                    patched, clipped, standard GTFS files only
│   ├── agency.txt           2 agencies (LRTA, LTFRB)
│   ├── routes.txt           599 routes
│   ├── trips.txt            663 trips
│   ├── stops.txt            531 stops
│   ├── stop_times.txt       11,174 rows (times relative to trip start)
│   ├── frequencies.txt      headway-based service (no fixed timetables)
│   ├── calendar.txt         7 service patterns
│   ├── shapes.txt           5 shapes (rail + 1 route), clipped
│   └── feed_info.txt
├── reference/               Mapparaan's own data (NOT part of GTFS)
│   ├── manila_boundary.geojson   City of Manila polygon used for clipping
│   ├── route_modes.csv      route_id -> mode (one row per route in routes.txt)
│   ├── fare_config.json     fare rules, tables and discounts (maintained by hand)
│   └── manifest.json        row counts and build info
├── gtfs_backup_before_drop_pnr/  original files saved by drop_pnr.py
├── build/                   generated OpenTripPlanner output (not committed)
└── tools/
    ├── patch_gtfs.py        patches the source feed (see "Patches")
    └── clip_gtfs.py         clips a patched feed to the boundary
```

The original raw GTFS feed is not included in this repository; supply it separately if
rebuilding the feed. **gtfs/** is generated and can be rebuilt from that source;
hand edits belong in the scripts, not in generated files. **fare_config.json** is
maintained separately and must not be overwritten by a feed rebuild. Keep
`route_modes.csv` in step with `gtfs/routes.txt`. The OpenTripPlanner ZIP is generated
output, is not used by the current planner, and is intentionally not tracked. Generate
a fresh bundle from current GTFS data before using OpenTripPlanner.

## Rebuild

```
# 1. patch the full feed (see "Patches" below): tools/patch_gtfs.py
# 2. clip the patched feed to Manila
python3 tools/clip_gtfs.py <patched_full_feed_dir> data/reference/manila_boundary.geojson data/gtfs \
    --tolerance-m 50 --exclude-routes ROUTE_880872
# other options: --tolerance-m 0 (strict polygon), --review-csv stops_to_review.csv
```

Given the patched feed, step 2 reproduces the current Manila-focused GTFS.

## Patches applied to the source feed

1. `calendar.txt`: start/end dates set to 2020-01-01 – 2035-12-31 (source expired 2020-06-30). Dates are stretched only; the schedules themselves are still the original data.
2. `routes.txt`: empty `route_short_name` filled from the LTFRB code (e.g. `PUJ1094`). `route_type` untouched.
3. Sunday LRT-1: the source has no Sunday service from R. Papa toward Vito Cruz (toward Baclaran). Trip `882223_sun` on service `FIX_SUNDAY` (Sundays only) is a copy of the Saturday trip `882223`, running 05:00 to 21:30 every 5 minutes on shape `882188`. `backend/planner/test_service_days.py` checks that every rail direction runs every day.

## Schemas

**reference/route_modes.csv**

| column | meaning |
|---|---|
| route_id | matches `routes.txt` |
| mode | `jeepney`, `bus`, `lrt1`, `lrt2` in the Manila data (`mrt3`, `fort_bus`, `uv_express` are reserved; no routes use them) |

Mode comes from LTFRB's route codes: `PUJ` = jeepney (561 here), `PUB` = bus (36 here).

**reference/fare_config.json**

Every mode has a `verified` flag: `true` only when checked against an official fare source (see its `source`).

| modes | what they hold | status |
|---|---|---|
| `jeepney`, `modern_jeepney`, `bus`, `aircon_bus` | road fares: `base_fare` covers `base_km`, then `per_km` beyond it. Student / senior / PWD fares use `discounted_base_fare` and `discounted_per_km` the same way. Rounded to the nearest P0.25 | verified, LTFRB fare guides effective 2026-09-28 |
| `lrt1`, `lrt2` | station-to-station tables (`ticket_types.<type>.regular` / `.discounted`), looked up with `stations` and `feed_stop_names`. `lrt1` has the 12 Manila stations, `lrt2` all 13 | verified; see "Rail discounts" |
| `mrt3` | 13-station table, kept for completeness | verified, not in the Manila feed |
| `uv_express`, `modern_uv_express` | per-km rates only | provisional, valid to 2026-12-31, no routes in the feed, not used |
| `fort_bus` | empty | unverified, not used |

`discount.multiplier` (0.8) is the road discount rate, for reference only. The planner does not
multiply by it: the road discount uses each mode's own add-on rates, which are not always the same
as 0.8 × the regular fare.

**How the planner prices a trip**

- Road: the feed only says "jeepney" or "bus", so every road ride gets a range. The low end is the
  traditional jeepney or ordinary bus fare; the high end is the modern jeepney or aircon bus fare.
  Distance is the straight-line stop distance × 1.3, not rounded up to whole km. Road fares are
  always marked as estimates.
- Rail: one exact fare from the station table, using the default ticket type (Beep stored value).
  If a stop name is not in the table, the fare falls back to the table average and is marked as an estimate.
- A trip's fare is the sum of its ride legs. Each ride is priced as a separate ticket, so a
  LRT-1 to LRT-2 transfer is two tickets.

**Rail discounts**

- Students, seniors and PWDs get 50% off on rail, for both ticket types.
- `lrt2` has a temporary discount: `temporary_discount.active` is `true` (effective 2026-03-23, no end
  date). DOTr gave all passengers a 50% discount on LRT-2 and MRT-3 from that date "until further
  notice" (LRT-1 was not included). While it is active the planner reads the *regular* fare from the
  discounted tables, and students, seniors and PWDs pay the same fare (the two are not stacked, because
  no source says whether they stack). The API prints a start-up warning while it is applied. Set `active`
  to `false`, or give an `end_date`, when it ends, and check periodically that it is still in effect.
- `lrt1` discounted tables are derived, not copied from a poster: stored value is exactly half the
  regular fare; single journey is half, rounded up to a whole peso (as LRT-2 does). Replace them with
  the official tables if LRMC publishes them.

## Checks

From the project root:

```
python backend/planner/check_all.py
```

It checks that `fare_config.json` is the real file (not a placeholder), that the data has the
Sunday LRT-1 trip and no PNR, runs `test_trips`, `test_fares`, `test_service_days` and
`test_api_security`, and makes a live `POST /plan` against the real API code. It prints PASS / FAIL for
each check and exits with code 1 if anything fails. Run it after every data or fare change.

## Known gaps

- Data is circa 2013–15 (DOTC / Philippine Transit App Challenge); some routes will be outdated or missing.
- Times are estimates: schedules are headway-based, and the feed's jeepney and bus headways are about 1 minute (synthetic), so the planner assumes a minimum wait.
- No road geometry for jeepney/bus routes: they draw as straight lines between stops until shapes are generated.
- No UV Express or PNR routes.
- Road fares cannot tell a traditional from a modern jeepney, or an ordinary from an aircon bus, so they are shown as a range.
- UV Express rates are provisional and expire on 2026-12-31.
- The `lrt1` discounted tables are derived, and the `lrt2` temporary discount has no announced end date.
- No fares in the GTFS itself; fares come from `fare_config.json`.

## Source and license

- Source: https://github.com/sakayph/gtfs (original DOTC data modified by Sakay.ph; the original is on its `dotc` branch).
- License: DOTC Developer License Agreement (`raw/sakay_gtfs/LICENSE.md`). Summary, not legal advice: use is limited to assisting mass-transit riders / promoting public transport; the data may not be sold separately from the app; no implied DOTC endorsement; credit optional; DOTC may revoke the license and require deletion.
- Suggested credit line: "Route data provided by the Department of Transportation and Communications (DOTC), via Sakay.ph." The license also accepts "Data provided by DOTC" or "Powered by DOTC data".
- Map data © OpenStreetMap contributors. Basemap © CARTO.