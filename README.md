# Mapparaan

## About

Mapparaan is an interactive mapping and route-planning app for Metro Manila
commuters, with transit data focused on **Manila City**. It combines place
search, multimodal route options, estimated fares, and applicable discounts.

The app supports route preferences (fastest, cheapest, or fewest transfers),
scheduled departures, and public-transit alternatives based on the available
GTFS data. It does not provide live vehicle tracking or traffic-aware transit
ETAs.

## Scope and limitations

Mapparaan is a static, schedule-based system, not a live vehicle-tracking app.
It does not provide live GPS positions of public-transport vehicles, vehicle-
specific ETAs, or seat/capacity availability. Transit recommendations use the
Sakay.ph / DOTC GTFS feed (circa 2013–15), filtered to Manila City. User
location can be current, and walking route geometry is requested from OSRM,
but transit suggestions do not account for live traffic or service alerts.

LRT-1 and LRT-2 are excluded from recommendations when the supplied GTFS does
not show them as boardable at the selected departure time. They are not brought
back as a later-service or transfer leg. This is an estimate based on the
historical feed, not confirmation of current operator hours. The current feed
has no frequency windows extending past midnight, so it cannot verify
after-midnight service based on the previous service day.

If the API is reachable but finds no supported route, the app distinguishes
that result from an API or connectivity failure. It can return verified
partial transit segments or a street-routed walking option when available.
Next-service suggestions may use later bus or jeepney service windows and are
clearly marked as estimates; they do not mean those vehicles are operating at
the requested departure time. If the backend is unreachable, the app may show
clearly labeled sample fallback routes.

> **Fares are estimates, not live quotes.** The feed does not distinguish
> traditional from modern jeepneys or ordinary from air-conditioned buses, so
> road fares may be shown as a range. See
> [`mapparaan/data/reference/fare_config.json`](mapparaan/data/reference/fare_config.json)
> for fare sources and verification notes.

## Current status

| Feature | Status |
| --- | --- |
| Interactive map, place search, current-location controls, and place details | Implemented |
| Walking/driving route geometry via OSRM | Implemented; public demo service and not traffic-aware |
| Transit planner API and schedule-aware GTFS route search | Implemented; local backend changes require deployment to affect Render |
| Fastest, cheapest, fewest-transfer, and supported-mode alternatives | Implemented from available route data |
| LRT-1/LRT-2 availability filtering | Implemented against the historical GTFS; not a current operator timetable |
| Empty-result, API-error, and connectivity state handling | Implemented |
| Estimated fares and student, senior, and PWD discounts | Implemented; source data may need current verification |
| Saved places, trip history, preferences, and memory-photo sharing | Implemented; account-backed features require Supabase configuration |
| Basic natural-language query parsing | Implemented as a lightweight parser; not a full chatbot/NLU system |
| Live transit vehicle locations, live service alerts, and traffic-aware transit ETAs | Not available |
| Current verified operating schedules and broader-than-Manila transit coverage | Not available |
| Detailed road geometry for most jeepney and bus routes | Not available; many legs use stop-to-stop lines |

## Tech stack

| Layer | Technology | Notes |
| --- | --- | --- |
| App | Flutter / Dart | Android, iOS, web, and Windows development targets |
| Map rendering | `flutter_map`, `latlong2` | Interactive map, markers, and route overlays |
| Map tiles | CARTO Voyager / OpenStreetMap | Raster tiles with visible attribution |
| Place search | OpenStreetMap Nominatim | Metro Manila-biased; public service has usage limits |
| Device location | `geolocator` | Location access is requested when needed |
| Walking/driving geometry | OSRM public demo | External routing service; not traffic-aware |
| Transit routing | Custom Python GTFS planner | Python standard library; headway-based estimates |
| Backend API | Python `http.server` | `POST /plan`, `GET /health`; CORS configurable, no API authentication |
| Cloud data and account features | Supabase | Auth, database, Storage, and friend/photo-sharing data |
| Local preferences | `shared_preferences` | Saved app preferences and local data |
| Transit data | Sakay.ph / DOTC GTFS | Static feed filtered to Manila City; circa 2013–15 |
| Fare and discount rules | JSON fare configuration | Estimates; consult each mode's source and verification notes |
| Hosting | Render | Deployment blueprint is in [`render.yaml`](render.yaml); deployed service must be updated separately from local code |
| Natural-language assistance | Regex-based query parser | Placeholder for a future full NLU/chatbot integration |

## Requirements

- Flutter and Dart compatible with the SDK constraint in
  [`mapparaan/pubspec.yaml`](mapparaan/pubspec.yaml).
- Python 3 for the local transit planner API.
- A Supabase project and public client configuration for account-backed
  features. Guests can use map and local features without cloud configuration.

## Run locally

Commands below use PowerShell from the repository root.

### Run Flutter with the hosted planner

Contributors can use the deployed Render API without running the Python backend.

1. Create a local environment file if you do not already have one:

   ```powershell
   Copy-Item mapparaan\.env.example mapparaan\.env
   ```

2. Set `TRANSIT_API_URL` in `mapparaan/.env` to the deployed planner URL:

   ```dotenv
   TRANSIT_API_URL=https://mapparaan-planner.onrender.com
   ```

   Set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` to enable Supabase-backed
   features. `CARTO_API_KEY` is optional. Do not share or commit `.env`; it is
   bundled into the app, so only public client keys belong there.

3. Optionally wake the free Render service and check that it is ready:

   ```powershell
   Invoke-RestMethod https://mapparaan-planner.onrender.com/health
   ```

   A free service may sleep when idle. Its first request after inactivity can
   take longer while Render starts it; wait for the health check to return
   `status: ok` before retrying route planning.

4. Run Flutter web from the project directory:

   ```powershell
   Set-Location mapparaan
   flutter pub get
   flutter run -d edge --web-port 5000
   ```

   The deployed API must allow the web app's origin (for example,
   `http://localhost:5000`) in Render's `MAPPARAAN_ALLOWED_ORIGINS` setting.
   CORS is not authentication.

### Run the planner locally

The debug app defaults to `http://127.0.0.1:8080` when `TRANSIT_API_URL` is
unset. To use the local planner, start it from `mapparaan/`:

```powershell
Set-Location mapparaan
python backend\planner\api.py --host 127.0.0.1 --port 8080
```

In another terminal, run Flutter as above. If `.env` sets `TRANSIT_API_URL` to
Render, the app continues using Render instead of this local server.

The Android emulator's localhost URL is translated to the host machine by the
app. A physical device needs a reachable host LAN address and a planner bound
to the network interface; the API requires `MAPPARAAN_ALLOWED_ORIGINS` when
binding beyond loopback.

Release builds require HTTPS for configured service URLs and a configured
transit API endpoint for backend route planning.

## Deploy planner changes

Changing Python code locally does not update the hosted service. For a
GitHub-connected Render service:

1. Confirm the Render service's configured repository and auto-deploy branch.
2. Commit and push the intended backend changes to that branch.
3. Wait for the Render deployment to finish successfully.
4. Check `/health`, then make a route request for the changed behavior against
   the hosted API. A healthy `/health` response alone does not confirm that a
   particular code change has deployed.

When diagnosing a mismatch, check which API host the app is configured to use
and test that same host. A cold start can delay a request, but it does not
indicate that new backend code has been deployed. Do not expose the
unauthenticated planner publicly without suitable abuse controls.

## API

The Python standard-library API loads GTFS and fare data at startup:

- `GET /health` — readiness check.
- `POST /plan` — plan a route using JSON coordinates, passenger type, and
  optional departure time. Returns route options and schedule/data notices.
- `GET /plan` — retained for compatibility; use `POST /plan` in new clients.

The API defaults to `127.0.0.1:8080`; see
[`mapparaan/backend/planner/api.py`](mapparaan/backend/planner/api.py) for
host, port, data-directory, and CORS options.

## Tests and checks

Run from the Flutter project directory (`mapparaan/`):

```powershell
flutter test
flutter analyze
python backend\planner\check_all.py
```

The backend checks include fare and service-day tests, schedule-boundary and
transfer behavior, and API security/smoke checks.

## Project structure

```text
repository/
├── README.md                         Project overview and setup
├── render.yaml                       Render planner-service blueprint
└── mapparaan/
    ├── lib/                          App screens, services, widgets, utilities
    ├── test/                         Flutter tests
    ├── backend/planner/              Python API, GTFS planner, tests, checks
    ├── data/
    │   ├── gtfs/                     Static transit feed
    │   ├── reference/                Fare rules, route modes, boundary, manifest
    │   └── tools/                    GTFS preparation scripts
    ├── supabase/                     Database schema and migrations
    ├── android/ ios/ web/ windows/   Flutter platform projects
    ├── .env.example                  Local configuration template
    ├── Dockerfile                    Planner API container
    └── pubspec.yaml                  Flutter dependencies and SDK constraints
```

## Transit data

The planner reads `mapparaan/data/gtfs/` and `mapparaan/data/reference/`.
Details, schemas, and rebuild instructions are in
[`mapparaan/data/README.md`](mapparaan/data/README.md).

| Entity | Count | Notes |
| --- | ---: | --- |
| Stops | 531 | Manila-focused GTFS stops |
| Routes | 599 | Jeepney, bus, LRT-1, and LRT-2 |
| Trips | 663 | Headway-based; no fixed departure timetable |
| Stop times | 11,174 | Manila-focused feed |
| Shape points | 125 | Geometry exists for five routes; most road legs use stop-to-stop lines |
| Agencies | 2 | PNR routes are excluded |

**Source:** Sakay.ph / DOTC GTFS (circa 2013–15), cleaned and geographically
restricted to Manila City. Some routes may be outdated or missing. The GTFS
does not contain fare data; fares come from `fare_config.json`. Rebuild and
filter the feed using the tools under `mapparaan/data/tools/`.

## Data sources and attribution

- **Sakay.ph GTFS** — route data derived from DOTC data; see
  [`mapparaan/data/gtfs/LICENSE.md`](mapparaan/data/gtfs/LICENSE.md).
- **OpenStreetMap** — map data used by the basemap, place search, and OSRM.
- **CARTO Voyager** — basemap tiles.
- **OSRM** — walking/driving route geometry.
- **DOTr/LTFRB fare orders** — sources and verification notes in
  `mapparaan/data/reference/fare_config.json`.
- **RA 11314 / RA 9994 / RA 10754** — legal basis for applicable discounts.

Display the required OpenStreetMap and CARTO attribution in the app.

## Known gaps

- GTFS routes, schedules, and fare estimates need current verification.
- Most road-transit legs do not have route shape geometry.
- Search, tiles, and OSRM use public services with usage limits; production use
  may require self-hosting or another provider.
- The planner API has no user authentication; secure any public deployment with
  appropriate network and abuse controls.
- Full chatbot/NLU integration and live transit service data are not available.
