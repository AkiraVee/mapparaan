# Mapparaan

## About

Mapparaan is an AI chatbot-based interactive mapping system built for Metro Manila commuters. It addresses the difficulty of navigating a fragmented public transportation system by combining route planning, fare computation, and applicable discounts into a single tool.

Through a natural language (Filipino/Taglish) interface, Mapparaan aims to:

- Recommend appropriate modes of transportation (walk, jeepney, bus, tricycle, UV Express, LRT/MRT/PNR, ride-hailing) based on user preference — cheapest, fastest, or fewest transfers
- Generate corresponding routes using multimodal trip-planning logic
- Compute estimated fares, with applicable **student, senior citizen, or PWD discounts** (20% off, non-stackable, per RA 11314 / RA 9994 / RA 10754)
- Provide estimated arrival times based on schedule and average traffic conditions

### Scope and Limitations

Mapparaan is a **static/schedule-based system**, not a live vehicle-tracking app. It does **not** provide:

- Live GPS positions of individual jeepneys/buses
- Live ETAs tied to a specific vehicle
- Live seat/capacity availability

This is a deliberate scoping decision: no public live-GPS feed currently exists for Metro Manila jeepneys. Route suggestions for public transport legs are based on static, headway-based GTFS data (Sakay.ph / DOTC, circa 2013–15) rather than live vehicle positions. Mapparaan **does** provide real-time user location tracking and real road geometry (OSRM) for walking/driving; it does **not** yet do traffic-aware routing.

> **Fares are placeholders.** The values in `data/references/fare_config.json` are not official and every mode is marked `verified: false`. Rail fares use a rough fallback formula in the planner. Do not present fares as real until they are checked against the current LTFRB / DOTr fare orders.

## Current Status

| Feature | Status |
|---|---|
| Interactive map (CARTO Voyager tiles, configurable color tint, Metro Manila default view and bounds) | Done |
| Place search (Nominatim, debounced, Metro Manila-biased) with "popular places" suggestions and quick filter chips | Done |
| "My location" button with permission handling, incl. dedicated location-disabled flow | Done |
| Selected-place pin, location details screen, Directions / Save / Share | Done — `LocationDetailsScreen` is now the main details/route screen, pushed from `HomeScreen` |
| Walking/driving geometry on the map (OSRM) | Done (public demo server; self-hosting planned for production) |
| Transit planner backend (custom Python GTFS planner, stdlib only) with `GET /plan` and `GET /health` | Done — runs locally; returns fastest / cheapest / fewest-transfers options with legs, per-leg paths, fares, and discounted fares |
| Transit routing in the app (`TransitPlannerService`) | Done — calls the backend; **falls back to mocked fare/ETA options (and an OSRM walking line) if the backend is unreachable**, flagged in the UI as offline fallback |
| Passenger type selector (Regular / Student / Senior / PWD) | Done — sent to the backend as `passenger=`; discounted fare shown in route cards |
| Fare and discount engine | Partial — distance-based fares + 0.8 multiplier implemented in the planner, but fare values are placeholders and rail fare tables are not filled in |
| Saved places (persisted locally) | Done — tap to re-center the map, remove from the list directly |
| Trip history (persisted locally) | Done — an entry is written the first time a route is calculated on the details screen; "Clear all" available. Origin is stored as a generic label ("Your location" / "Default location"), not the actual place |
| Side drawer (Profile, Saved Places, Trip History, Settings, Help) | Done |
| Settings: theme mode (system/light/dark) and Manila-landmark color palettes | Done — persisted, applied app-wide |
| Settings: high-contrast map, compact UI, metric units | Partial — toggles are stored but **not yet read anywhere else in the app** |
| Account sign-in / create account (`AuthScreen`) | **Mock only** — in-memory, no backend, nothing persisted; any email/password "signs in" |
| Memory pins ("Add Memory Photo", shown on the home map and in Profile) | **Prototype** — in-memory only, uses a mock image string, lost on restart; only shown when "logged in" |
| Basic natural-language query parsing ("from X to Y", preference keywords, passenger type) | Done (regex-based placeholder) |
| Chatbot / full NLU | Planned |
| Real jeepney/bus road geometry | Planned — feed has only 10 shapes, so most jeep/bus legs draw as straight lines between stops |
| UV Express, tricycle, ride-hailing routing | Planned — none in the GTFS data yet |
| OpenTripPlanner, PostgreSQL/PostGIS, hosted backend | Planned (see Tech Stack) |

## Tech Stack

| Layer | Technology | Notes |
|---|---|---|
| **Mobile app** | Flutter (Dart, SDK ^3.13) | Single codebase for Android/iOS (also runs on web for development) |
| **Map rendering** | `flutter_map` + `latlong2` | Pure-Dart map widget; markers, polylines, route display |
| **Map tiles** | CARTO Voyager raster tiles (OpenStreetMap data) | `MapparaanTileLayer` applies a configurable color wash (`MapTint`: none / warm / teal / faded — teal by default) as a cheap overlay. `flutter_map_cancellable_tile_provider` is used for better web performance |
| **Place search** | Nominatim (OpenStreetMap) | `PlaceSearchService`; limited to the Philippines and bounded to Metro Manila. Public instance has usage limits, so self-host or switch providers for production |
| **User location** | `geolocator` | Requested when the user taps "my location" or asks for directions |
| **Local persistence** | `shared_preferences` | Saved places, trip history, and commuter preferences (theme/palette/toggles) |
| **Sharing** | `share_plus` | Share a selected place |
| **Walking/driving routing** | OSRM public demo server (`router.project-osrm.org`) | Used for the walking line shown when the transit backend is offline. Self-hosted OSRM or Google Routes API planned for traffic-aware ETAs |
| **Transit routing** | Custom Python planner in `backend/planner/` | Standard library only. Loads the patched Sakay GTFS feed + fare config, models jeep/bus as headway services ("board whenever one comes, ride N stops"), and returns up to three options. Tunable assumptions (walk speed, transfer distance, wait times, peso-to-minutes weight) are constants at the top of `gtfs_planner.py`. OpenTripPlanner remains a possible future replacement |
| **Backend API** | `http.server` (`backend/planner/api.py`) | `GET /plan?from=lat,lon&to=lat,lon&passenger=<general, student, senior, or pwd>`, `GET /health`. CORS enabled. No auth |
| **Chatbot / NLU** | Claude or GPT API (tool-calling) | Planned. `AiAssistantService` is a regex placeholder that extracts origin/destination/preference/passenger type; it does not compute routes itself |
| **Database** | PostgreSQL + PostGIS | Planned. Fare tables, cached routes, user data, spatial queries |
| **Fare & discount logic** | Config-driven (`data/references/fare_config.json`) | Implemented in the planner: `base_fare + per_km × (km − base_km)`, × 0.8 for eligible passengers |
| **Hosting** | Single VPS (DigitalOcean/Linode) | Planned |

## Running Locally

**1. Start the transit planner API** (from the Flutter project root, `mapparaan/`):

```bash
python backend/planner/server.py            # or: python backend/planner/api.py --port 8080
# sanity check
curl "http://localhost:8080/plan?from=14.5918,120.9786&to=14.6567,121.0287&passenger=student"
```

**2. Point the app at it.** Edit `AppConstants.transitApiBaseUrl` in `lib/constants.dart`:

| Where the app runs | URL |
|---|---|
| Android emulator (default) | `http://10.0.2.2:8080` |
| Chrome / web | `http://localhost:8080` (auto-translated from `10.0.2.2`) |
| Physical device | `http://<your-PC-LAN-IP>:8080` |

**3. Run the app:**

```bash
flutter pub get
flutter run
```

If the API isn't reachable (5-second timeout), the app still works but shows mocked options flagged as an offline fallback.

**Tests:** `flutter test` (covers transit response parsing, fallback generation, passenger-type detection, and the location details screen).

## Project Structure

```
mapparaan/                              # repo root
├── README.md
└── mapparaan/                          # Flutter project
    ├── lib/
    │   ├── main.dart                   # loads saved preferences, builds themed MaterialApp
    │   ├── constants.dart              # tile URL, camera/bounds, search settings, transit API URL
    │   ├── screens/
    │   │   ├── home_screen.dart               # main map, search/ask bar, selected-place pin, memory pins
    │   │   ├── search_location_screen.dart    # full search screen: debounce, popular places, filter chips, AI query bar
    │   │   ├── location_details_screen.dart   # place details, passenger type, route preference, transit options + map
    │   │   ├── location_disabled_screen.dart  # prompt to enable location services
    │   │   ├── auth_screen.dart               # mock sign-in / create account
    │   │   └── drawer_destination_screen.dart # profile, saved places, trip history, settings, help
    │   ├── services/
    │   │   ├── ai_assistant_service.dart        # regex Taglish parsing; defines PassengerType
    │   │   ├── place_search_service.dart        # Nominatim search
    │   │   ├── route_planner_service.dart       # OSRM geometry + mocked multimodal options
    │   │   ├── transit_planner_service.dart     # backend client, response models, offline fallback
    │   │   ├── saved_places_service.dart        # persisted saved places
    │   │   ├── trip_history_service.dart        # persisted trip history
    │   │   ├── commuter_preference_service.dart # theme mode, color palettes, toggles (persisted)
    │   │   ├── auth_service.dart                # mock in-memory auth state
    │   │   └── memory_pin_service.dart          # in-memory memory pins
    │   └── widgets/
    │       ├── ask_mapparaan_bar.dart         # pill-shaped search/ask input
    │       ├── circle_icon_button.dart        # circular overlay button
    │       ├── location_details_sheet.dart    # older bottom-sheet mode picker (currently not used by any screen)
    │       ├── mapparaan_drawer.dart          # side navigation menu
    │       └── mapparaan_tile_layer.dart      # CARTO tiles + configurable color tint
    ├── backend/
    │   └── planner/
    │       ├── api.py                  # HTTP API (/plan, /health)
    │       ├── gtfs_planner.py         # GTFS loader + multimodal planner + fare/discount calc (also a CLI)
    │       └── server.py               # convenience entry point
    ├── data/                           # see "Transit Data" below and data/Data_README.md
    │   ├── gtfs/                       # patched Sakay GTFS feed
    │   ├── references/                 # route_modes.csv, fare_config.json, manifest.json
    │   ├── build/mapparaan_gtfs.zip    # GTFS bundle (for OpenTripPlanner, if adopted)
    │   └── tools/patch_gtfs.py         # regenerates gtfs/, references/, build/ from the raw feed
    └── test/
        ├── location_details_screen_test.dart
        └── transit_planner_test.dart
```

## Transit Data

The planner reads `data/gtfs/` and `data/references/`. Details, schemas, and rebuild instructions are in [`data/Data_README.md`](mapparaan/data/Data_README.md). Key facts:

- 1,717 routes (1,522 jeepney, 189 bus, plus LRT-1, LRT-2, MRT-3, PNR, and 2 Fort Bus), 4,858 stops, headway-based (`frequencies.txt`), no fixed timetables
- Data is circa 2013–15, so some routes will be outdated or missing
- Only 10 shapes in the feed — jeep/bus legs have no road geometry
- No UV Express routes; no fares in the GTFS itself (fares come from `fare_config.json`)

## Known Gaps / TODO

- Replace placeholder fares with verified LTFRB / DOTr values; add rail fare tables
- Wire the high-contrast, compact UI, and metric-unit settings into the app, or remove them
- Replace mock auth and mock memory pins with real implementations (and persist them)
- Replace the regex parser with a real chatbot/NLU layer
- Generate road geometry for jeepney/bus routes
- Host the backend and self-host OSRM/Nominatim (or switch providers) before release
- Remove or reuse the unused `LocationDetailsSheet` widget

## Data Sources

- **Sakay.ph GTFS** (GitHub) — jeepney/bus/rail route data derived from DOTC data, community-maintained. Suggested credit: "Route data provided by the Department of Transportation and Communications (DOTC), via Sakay.ph." See `data/gtfs/LICENSE.md` for license terms
- **OpenStreetMap** — map data behind the tiles, Nominatim search, and OSRM
- **CARTO Voyager** — basemap tiles built on OpenStreetMap data
- **OSRM** (`router.project-osrm.org`) — walking/driving route geometry
- **DOTr/LTFRB fare orders** — to be manually sourced (currently placeholders)
- **RA 11314 / RA 9994 / RA 10754** — legal basis for discount rules

### Attribution

Map data © OpenStreetMap contributors. Basemap tiles © CARTO. Both require visible attribution in the app.