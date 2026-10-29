# Mapparaan

Mapparaan is a Flutter mapping and public-transit trip planner for commuters in
Metro Manila. Transit coverage is focused on the City of Manila. The app runs
on Android and iOS, with Flutter web and Windows targets available for
development.

## Features

- Explore a map, search for places, use your current location, and view place
  details.
- Compare walking and public-transit routes by **fastest**, **cheapest**, or
  **fewest transfers**.
- Choose **Leave now** or schedule a future departure in Manila local time.
  The planner estimates service availability at each boarding time, including
  time spent walking, waiting, riding, and transferring. When LRT service is
  outside the supplied frequency window, it avoids that rail leg and can still
  suggest available jeepney or bus routes.
- Review estimated fares and eligible student, senior, and PWD discounts.
- Save places and review trip history and commuter preferences.
- Sign in with Supabase to use account-backed memory photos and friend-only
  photo sharing.
- Use a responsive interface designed for mobile as well as larger screens.

## Important limitations

Transit schedules come from a static Sakay.ph / DOTC GTFS feed dating from
circa 2013–15. The calendar dates in the feed were extended, but the service
patterns are not current operator confirmations. Schedule-aware routing is an
estimate based on the feed's service days and headway windows; it does not
model exact vehicle departures, live closures, or real-time alerts. Verify
current operating hours before traveling.

If the API responds successfully but no supported service is available for the
selected time, the app reports that no transit route was found rather than
showing an offline warning or inventing a transit route. If a scheduled transit
segment is available but does not reach the destination, the API can return a
labeled partial route using its real stops and fare data; the remaining
distance is a straight-line estimate, not walking directions. For an empty
transit result, the app can show a street-routed walking option when the
pedestrian router returns a verified path, with walking time marked estimated.
When the estimated wait for the next GTFS service is within 12 hours, the
planner can also show that transit option with the wait clearly identified.
This can include jeepney or bus routes that begin after rail service resumes;
it does not imply those routes are running at the selected departure time.
LRT-1 and LRT-2 are excluded from every recommendation when the supplied GTFS
does not show them as boardable at the selected departure time; they are not
reintroduced as a later-service or transfer leg. This availability check is
based on the historical feed, not a verified current operator timetable.
The planner includes feasible alternatives for each supported mode in its
actual route data rather than only showing the overall fastest, cheapest, and
fewest-transfer winners.
A previous service day is considered after midnight only when the GTFS
frequency window explicitly extends beyond 24:00. The current feed has no such
after-midnight frequency windows, so it cannot support verified transit
recommendations after midnight.

The app does not track public-transport vehicles, provide live vehicle ETAs,
or account for live traffic. Fares are estimates; the feed does not distinguish
traditional and modern jeepneys or ordinary and air-conditioned buses, so some
road fares are ranges. See
[`mapparaan/data/README.md`](mapparaan/data/README.md) and
[`mapparaan/data/reference/fare_config.json`](mapparaan/data/reference/fare_config.json)
for data scope, sources, and fare notes.

The transit planner covers the City of Manila feed; places elsewhere in Metro
Manila may be outside practical transit coverage. Map tiles, place search, and
walking/driving geometry use external providers. These features are not
traffic-aware.

## Requirements

- Flutter and Dart compatible with the SDK constraint in
  [`mapparaan/pubspec.yaml`](mapparaan/pubspec.yaml).
- Python 3 for the standard-library transit planner API.
- A Supabase project for sign-in, account-backed memory photos, and friend
  sharing. Guests can use the map and local features without cloud
  configuration.

## Run locally

Commands below use PowerShell from the repository root.

### Run the app with the hosted planner

Contributors can use the deployed Render API without running the Python backend:

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

Any configured service URL in a release build must use HTTPS; configure a
transit API endpoint to enable backend route planning in release builds.
[`render.yaml`](render.yaml) defines a Render deployment, but the blueprint
must be deployed and configured before the hosted API is available. Do not
expose the unauthenticated planner publicly without suitable abuse controls.

### Deploy planner changes

The Flutter app uses the API URL in its `.env`; changing Python code locally
does not update the hosted service. For a GitHub-connected Render service:

1. Confirm the Render service's configured repository and auto-deploy branch.
2. Commit and push the intended backend changes to that branch.
3. Wait for the Render deployment to finish successfully.
4. Check `/health`, then make a route request for the changed behavior against
   the hosted API. A healthy `/health` response alone does not confirm that a
   particular code change has deployed.

When diagnosing a mismatch, check which API host the app is configured to use
and test that same host. A cold start can delay a request, but it does not
indicate that new backend code has been deployed.

## API

The Python standard-library API loads the local GTFS and fare data at startup:

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
├── README.md                         Project overview and quick start
├── render.yaml                       Render planner-service blueprint
└── mapparaan/
    ├── lib/
    │   ├── screens/                  App screens
    │   ├── services/                 Routing, search, auth, data, and sharing
    │   ├── widgets/                  Reusable UI and map widgets
    │   └── utils/                    Shared utilities
    ├── test/                         Flutter widget and unit tests
    ├── backend/planner/              Python API, GTFS planner, tests, checks
    ├── data/
    │   ├── gtfs/                     Static transit feed
    │   ├── reference/                Fare rules, route modes, boundary, manifest
    │   └── tools/                    GTFS preparation scripts
    ├── supabase/                     Database schema and migrations
    ├── android/ ios/ web/ windows/   Flutter platform projects
    ├── .env.example                  Local configuration template
    ├── Dockerfile                    Planner API container
    └── pubspec.yaml                  Flutter package and SDK constraints
```

## Data and attribution

The current feed contains 531 stops, 599 routes, 663 trips, and 11,174 stop
times. It includes jeepney, bus, LRT-1, and LRT-2 services; only a small number
of routes have shape geometry. More detail and feed rebuild instructions are
in [`mapparaan/data/README.md`](mapparaan/data/README.md).

- Transit data: Sakay.ph / DOTC GTFS; see
  [`mapparaan/data/gtfs/LICENSE.md`](mapparaan/data/gtfs/LICENSE.md).
- Map data: © OpenStreetMap contributors.
- Basemap tiles: © CARTO.
- Walking/driving route geometry: OSRM public demo service.
- Fare sources and verification notes: `mapparaan/data/reference/fare_config.json`.
- Discount rules: RA 11314, RA 9994, and RA 10754.

The app should display the required OpenStreetMap and CARTO attribution.

## Known gaps

- GTFS routes, schedules, and fare estimates need current verification.
- Most road-transit legs do not have route shape geometry.
- Search, tiles, and OSRM use public services with usage limits; production use
  may require self-hosting or another provider.
- The planner API has no user authentication; secure any public deployment
  with appropriate network and abuse controls.
