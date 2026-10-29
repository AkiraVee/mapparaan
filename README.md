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
When the estimated wait for the next GTFS service is within two hours, the
planner can also show that transit option with the wait clearly identified.
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

1. Configure the Flutter app:

   ```powershell
   Copy-Item mapparaan\.env.example mapparaan\.env
   ```

   Set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` in
   `mapparaan/.env` to enable Supabase-backed features. The app also accepts
   the legacy `SUPABASE_ANON_KEY`. `CARTO_API_KEY` is optional. The debug app
   defaults to the local transit API at `http://127.0.0.1:8080`.

   The `.env` file is bundled as a Flutter asset, so its values are visible in
   the built app. Only use public client keys there. Never put a Supabase
   `service_role` key or other privileged secret in it. For database and
   Storage setup, follow [`mapparaan/README.md`](mapparaan/README.md).

2. Start the transit planner in a terminal:

   ```powershell
   Set-Location mapparaan
   python backend\planner\api.py --host 127.0.0.1 --port 8080
   ```

   Check that it is ready from another terminal:

   ```powershell
   curl.exe http://127.0.0.1:8080/health
   ```

3. In another terminal, install Flutter packages and run the app:

   ```powershell
   Set-Location mapparaan
   flutter pub get
   flutter run
   ```

   The Android emulator's localhost URL is translated to the host machine by
   the app. A physical device needs a reachable host LAN address and a planner
   bound to the network interface; the API requires
   `MAPPARAAN_ALLOWED_ORIGINS` when binding beyond loopback. For Flutter web,
   configure the exact web origin in that allowlist. CORS is not
   authentication.

For a deployed planner, set `TRANSIT_API_URL` in `mapparaan/.env` to its HTTPS
base URL. Any configured service URL in a release build must use HTTPS;
configure a transit API endpoint to enable backend route planning in release
builds.
[`render.yaml`](render.yaml) defines a Render deployment, but the blueprint
must be deployed and configured before the hosted API is available. Do not
expose the unauthenticated planner publicly without suitable abuse controls.

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
