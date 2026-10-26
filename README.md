# Mapparaan

## About

Mapparaan is an interactive mapping and route-planning app for Metro Manila commuters, with transit data focused on **Manila City**. It combines place search, route options, fare estimates, and applicable discounts.

Through a natural language (Filipino/Taglish) interface, Mapparaan aims to:

- Recommend available modes of transportation (walking, jeepney, bus, and LRT) based on user preference — cheapest, fastest, or fewest transfers
- Generate corresponding routes using multimodal trip-planning logic
- Compute estimated fares, with applicable **student, senior citizen, or PWD discounts** (20% off, non-stackable, per RA 11314 / RA 9994 / RA 10754)
- Provide approximate travel times based on static, headway-based service data; live traffic and vehicle tracking are not available

### Scope and Limitations

Mapparaan is a **static/schedule-based system**, not a live vehicle-tracking app. It does **not** provide:

- Live GPS positions of individual jeepneys/buses
- Live ETAs tied to a specific vehicle
- Live seat/capacity availability

This is a deliberate scoping decision: no public live-GPS feed currently exists for Metro Manila jeepneys. Route suggestions for public transport legs are based on static, headway-based GTFS data (Sakay.ph / DOTC, circa 2013–15, filtered to Manila City) rather than live vehicle positions. Mapparaan **does** provide real-time user location tracking and real road geometry (OSRM) for walking/driving; it does **not** yet do traffic-aware routing.

> **Fares are estimates, not live quotes.** Check `data/reference/fare_config.json` for each mode's verification status and source. The feed cannot distinguish traditional from modern jeepneys or ordinary from air-conditioned buses, so road fares may be shown as a range; UV Express rates are provisional and are not used because there are no UV Express routes in the feed.

## Current Status

| Feature                                                                                                           | Status                                                                                                                                                                                                         |
| ----------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Interactive map (CARTO Voyager tiles, configurable color tint, Metro Manila default view and bounds)              | Done                                                                                                                                                                                                           |
| Place search (Nominatim, debounced, Metro Manila-biased) with "popular places" suggestions and quick filter chips | Done                                                                                                                                                                                                           |
| "My location" button with permission handling, incl. dedicated location-disabled flow                             | Done                                                                                                                                                                                                           |
| Selected-place pin, location details screen, Directions / Save / Share                                            | Done — `LocationDetailsScreen` is now the main details/route screen, pushed from `HomeScreen`                                                                                                                  |
| Walking/driving geometry on the map (OSRM)                                                                        | Done (public demo server; self-hosting planned for production)                                                                                                                                                 |
| Transit planner backend (custom Python GTFS planner, stdlib only) with `POST /plan` and `GET /health`             | Done — runs locally; returns fastest / cheapest / fewest-transfers options with legs, per-leg paths, fares, and discounted fares; `GET /plan` remains supported for compatibility |
| Transit routing in the app (`TransitPlannerService`)                                                              | Done — calls the backend; **falls back to mocked fare/ETA options (and an OSRM walking line) if the backend is unreachable**, flagged in the UI as offline fallback                                            |
| Passenger type selector (Regular / Student / Senior / PWD)                                                        | Done — sent to the backend as `passenger=`; discounted fare shown in route cards                                                                                                                               |
| Fare and discount engine                                                                                          | Implemented from `data/reference/fare_config.json`; some vehicle types remain estimates, and UV Express fares are provisional                                                                                 |
| Saved places (persisted locally)                                                                                  | Done — tap to re-center the map, remove from the list directly                                                                                                                                                 |
| Trip history (persisted locally)                                                                                  | Done — an entry is written the first time a route is calculated on the details screen; "Clear all" available. Origin is stored as a generic label ("Your location" / "Default location"), not the actual place |
| Side drawer (Profile, Saved Places, Trip History, Settings, Help)                                                 | Done                                                                                                                                                                                                           |
| Settings: theme mode (system/light/dark) and Manila-landmark color palettes                                       | Done — persisted, applied app-wide                                                                                                                                                                             |
| Settings: high-contrast map, compact UI, metric units                                                             | Partial — toggles are stored but **not yet read anywhere else in the app**                                                                                                                                     |
| Account sign-in / create account (`AuthScreen`)                                                                   | **Mock only** — in-memory, no backend, nothing persisted; any email/password "signs in"                                                                                                                        |
| Memory pins ("Add Memory Photo", shown on the home map and in Profile)                                            | **Prototype** — in-memory only, uses a mock image string, lost on restart; only shown when "logged in"                                                                                                         |
| Basic natural-language query parsing ("from X to Y", preference keywords, passenger type)                         | Done (regex-based placeholder)                                                                                                                                                                                 |
| Chatbot / full NLU                                                                                                | Planned                                                                                                                                                                                                        |
| Real jeepney/bus road geometry                                                                                    | Planned — feed has only a handful of shapes, so most jeep/bus legs draw as straight lines between stops                                                                                                        |
| UV Express, tricycle, ride-hailing routing                                                                        | Planned — none in the GTFS data yet                                                                                                                                                                            |
| OpenTripPlanner, PostgreSQL/PostGIS                                                                               | Planned (see Tech Stack); a Render blueprint exists for hosting the current planner API                                                                                                                         |

## Tech Stack

| Layer                       | Technology                                          | Notes                                                                                                                                                                                                                                                                                                                                                                                 |
| --------------------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Mobile app**              | Flutter (Dart, SDK ^3.13)                           | Single codebase   for Android/iOS (also runs on web for development)                                                                                                                                                                                                                                                                                                                    |
| **Map rendering**           | `flutter_map` + `latlong2`                          | Pure-Dart map widget; markers, polylines, route display                                                                                                                                                                                                                                                                                                                               |
| **Map tiles**               | CARTO Voyager raster tiles (OpenStreetMap data)     | `MapparaanTileLayer` applies a configurable color wash (`MapTint`: none / warm / teal / faded — teal by default) as a cheap overlay. `flutter_map_cancellable_tile_provider` is used for better web performance                                                                                                                                                                       |
| **Place search**            | Nominatim (OpenStreetMap)                           | `PlaceSearchService`; limited to the Philippines and bounded to Metro Manila. Public instance has usage limits, so self-host or switch providers for production                                                                                                                                                                                                                       |
| **User location**           | `geolocator`                                        | Requested when the user taps "my location" or asks for directions                                                                                                                                                                                                                                                                                                                     |
| **Local persistence**       | `shared_preferences`                                | Saved places, trip history, and commuter preferences (theme/palette/toggles)                                                                                                                                                                                                                                                                                                          |
| **Sharing**                 | `share_plus`                                        | Share a selected place                                                                                                                                                                                                                                                                                                                                                                |
| **Walking/driving routing** | OSRM public demo server (`router.project-osrm.org`) | Used for the walking line shown when the transit backend is offline. Self-hosted OSRM or Google Routes API planned for traffic-aware ETAs                                                                                                                                                                                                                                             |
| **Transit routing**         | Custom Python planner in `backend/planner/`         | Standard library only. Loads the patched/filtered Sakay GTFS feed + fare config, models jeep/bus as headway services ("board whenever one comes, ride N stops"), and returns up to three options. Tunable assumptions (walk speed, transfer distance, wait times, peso-to-minutes weight) are constants at the top of `gtfs_planner.py`. OpenTripPlanner remains a possible future replacement |
| **Backend API**             | `http.server` (`backend/planner/api.py`)            | `POST /plan` with JSON coordinates, `GET /health`; legacy `GET /plan` is supported. CORS is configurable; the API has no authentication                                                                                                                                                                                                                                                     |
| **Chatbot / NLU**           | Claude or GPT API (tool-calling)                    | Planned. `AiAssistantService` is a regex placeholder that extracts origin/destination/preference/passenger type; it does not compute routes itself                                                                                                                                                                                                                                    |
| **Database**                | PostgreSQL + PostGIS                                | Planned. Fare tables, cached routes, user data, spatial queries                                                                                                                                                                                                                                                                                                                       |
| **Fare & discount logic**   | Config-driven (`data/reference/fare_config.json`)   | Implemented in the planner; check each mode's verification status and notes                                                                                                                                                                                                                                                                                                           |
| **Hosting**                 | Render blueprint (`render.yaml`)                   | Deployment configuration is checked in; the hosted service must be deployed and its HTTPS URL configured in the app                                                                                                                                                                                                                                                                   |

## Running Locally

**1. Start the transit planner API** (from the Flutter project root, `mapparaan/`):

```bash
python backend/planner/api.py --host 127.0.0.1 --port 8080
```

In another terminal, confirm that the API loaded its GTFS data:

```bash
curl http://127.0.0.1:8080/health
```

**2. Configure the app.** Set `TRANSIT_API_URL` in the ignored Flutter `.env` file:

| Where the app runs         | URL                                                       |
| -------------------------- | --------------------------------------------------------- |
| Windows / Chrome (local)   | `http://127.0.0.1:8080` (default)                        |
| Android emulator           | `http://127.0.0.1:8080` (translated to `10.0.2.2` by the app) |
| Physical device (debug)    | `http://<your-PC-LAN-IP>:8080`; allow the web origin in CORS if using Flutter web |

**3. Run the app:**

```bash
flutter pub get
flutter run
```

Release builds require an HTTPS API URL. If the API cannot be reached, the app falls back to clearly labeled sample routes.

**Tests:** Run `flutter test` and `python backend/planner/check_all.py` from the Flutter project root.

## Project Structure

```
repository/
├── README.md
├── render.yaml                     # hosted planner service blueprint
└── mapparaan/                      # Flutter app and planner backend
    ├── lib/                        # screens, services, widgets, and utilities
    ├── test/                       # Flutter tests
    ├── backend/planner/            # API, GTFS planner, tests, and checks
    ├── data/                       # GTFS, reference data, and build tools
    ├── supabase/                   # database schema
    ├── android/ ios/ web/ windows/ # Flutter platform projects
    ├── Dockerfile
    ├── .env.example
    └── pubspec.yaml
```

## Transit Data

The planner reads `data/gtfs/` and `data/reference/`. Details, schemas, and rebuild instructions are in [`mapparaan/data/README.md`](mapparaan/data/README.md).

**Current feed (Manila City–focused):**

| Entity        | Count   | Notes |
|---------------|---------|-------|
| Stops         | 531     | Manila-focused GTFS stops |
| Routes        | 599     | Jeepney, bus, LRT-1, and LRT-2 routes |
| Trips         | 663     | Headway-based (`frequencies.txt`), no fixed timetables |
| Stop times    | 11,174  | Manila-focused feed |
| Shapes        | 125     | Only five routes have shapes; most road legs are straight lines between stops |
| Agencies      | 2       | PNR routes are excluded |

**Key facts:**
- Source: Sakay.ph / DOTC GTFS (circa 2013–15), cleaned and geographically restricted to Manila City
- The source feed is old, so some routes may be outdated or missing
- No UV Express routes; no fares in the GTFS itself (fares come from `fare_config.json`)
- Rebuild / re-filter from the raw feed using the tools under `data/tools/`

## Known Gaps / TODO

- Keep fare sources and verification status current; road fares may be ranges because vehicle types are not identified by the feed
- Wire the high-contrast, compact UI, and metric-unit settings into the app, or remove them
- Replace mock auth and mock memory pins with real implementations (and persist them)
- Replace the regex parser with a real chatbot/NLU layer
- Generate road geometry for jeepney/bus routes
- Deploy the backend and self-host OSRM/Nominatim (or switch providers) before release
- Consider expanding the GTFS filter back to full Metro Manila if broader coverage is needed

## Data Sources

- **Sakay.ph GTFS** (GitHub) — jeepney/bus/rail route data derived from DOTC data, community-maintained. Suggested credit: "Route data provided by the Department of Transportation and Communications (DOTC), via Sakay.ph." See `data/gtfs/LICENSE.md` for license terms
- **OpenStreetMap** — map data behind the tiles, Nominatim search, and OSRM
- **CARTO Voyager** — basemap tiles built on OpenStreetMap data
- **OSRM** (`router.project-osrm.org`) — walking/driving route geometry
- **DOTr/LTFRB fare orders** — sources and verification notes are maintained per mode in `data/reference/fare_config.json`
- **RA 11314 / RA 9994 / RA 10754** — legal basis for discount rules

### Attribution

Map data © OpenStreetMap contributors. Basemap tiles © CARTO. Both require visible attribution in the app.
