# Mapparaan

## About

Mapparaan is an AI chatbot-based interactive mapping system built for Metro Manila commuters. It addresses the difficulty of navigating a fragmented public transportation system by combining route planning, fare computation, and applicable discounts into a single tool.

Through a natural language (Filipino/Taglish) chatbot interface, Mapparaan:

- Recommends appropriate modes of transportation (walk, jeepney, bus, tricycle, UV Express, LRT/MRT/PNR, ride-hailing) based on user preference — cheapest, fastest, or fewest transfers
- Generates corresponding routes using multimodal trip-planning logic
- Computes estimated fares, with applicable **student, senior citizen, or PWD discounts** (20% off, non-stackable, per RA 11314 / RA 9994 / RA 10754)
- Provides estimated arrival times based on schedule and average traffic conditions

### Scope and Limitations

Mapparaan is a **static/schedule-based system**, not a live vehicle-tracking app. It does **not** provide:

- Live GPS positions of individual jeepneys/buses
- Live ETAs tied to a specific vehicle
- Live seat/capacity availability

This is a deliberate scoping decision: no public live-GPS feed currently exists for Metro Manila jeepneys. Route suggestions for public transport legs are based on static/schedule-based GTFS data (Sakay.ph / DOTr) rather than live vehicle positions. Mapparaan **does** provide real-time traffic-aware routing for road-based legs, real-time user location tracking, and a live conversational chatbot interface.

## Current Status

| Feature | Status |
|---|---|
| Interactive map (CARTO Voyager tiles, configurable color tint, Metro Manila default view) | Done |
| Place search (Nominatim, debounced, Metro Manila-biased) | Done |
| "My location" button with permission handling, incl. dedicated location-disabled flow | Done |
| Selected-place pin and location details sheet | Done — Directions, Save, and Share are wired up |
| Walking/driving directions on the map (real routing via OSRM) | Done (public demo server; self-hosting planned for production) |
| Saved places (persisted locally) | Done |
| Trip history (persisted locally, surfaced in drawer) | Partial — storage and UI are done, but nothing currently writes a trip entry after a completed route |
| Side drawer (Profile, Saved Places, Trip History, Settings, Help) | Done |
| Location-details screen with route preference buttons (fastest / cheapest / fewest transfers) | Done — uses mocked multimodal fare/ETA data, not yet wired into the main home flow |
| Basic natural-language query parsing ("from X to Y", preference keywords) | Done (regex-based) |
| Chatbot / full NLU | Planned (regex parser above is a placeholder for this) |
| Transit (jeep/bus/UV/LRT-MRT) routing | Planned — currently mocked fare/ETA estimates only |
| Fare and discount engine | Planned |

## Tech Stack

| Layer | Technology | Notes |
|---|---|---|
| **Mobile app** | Flutter (Dart) | Single codebase for Android/iOS (also runs on web for development) |
| **Map rendering** | `flutter_map` + `latlong2` | Pure-Dart map widget; markers, polylines, route display. No API key or native SDK needed |
| **Map tiles** | CARTO Voyager raster tiles (OpenStreetMap data) | Free, no API key. `MapparaanTileLayer` applies a configurable color wash (`MapTint`: none / warm / teal / faded — teal by default) as a cheap overlay rather than a per-pixel filter, so panning/zooming stays fast. `flutter_map_cancellable_tile_provider` is used for better web performance |
| **Place search** | Nominatim (OpenStreetMap) | Called from `PlaceSearchService`; limited to the Philippines and biased to Metro Manila. Public instance has usage limits, so self-host or switch providers for production |
| **User location** | `geolocator` | Requested when the user taps "my location"; a dedicated `LocationDisabledScreen` walks the user through enabling it |
| **Local persistence** | `shared_preferences` | Backs `SavedPlacesService` and `TripHistoryService` |
| **Sharing** | `share_plus` | Used to share a selected place |
| **Driving/walking routing** | OSRM public demo server (`router.project-osrm.org`) | Live — `RoutePlannerService.fetchRoute` fetches real walking/driving geometry for the "Directions" action. Self-hosted OSRM or Google Routes API planned for production/traffic-aware ETAs |
| **Transit routing** | OpenTripPlanner (OTP) | Planned. Multimodal (walk + transit) routing, self-hosted, ingests GTFS + OSM. The current mode cards and route-preference options use mocked fare/ETA data (`RoutePlannerService.generateRouteOptions`) as a placeholder |
| **Chatbot / NLU** | Claude or GPT API (tool-calling / function-calling) | Planned. A lightweight regex-based parser (`AiAssistantService`) already extracts origin/destination/preference from Taglish queries like "from X to Y" as a placeholder; does not compute routes itself |
| **Backend** | FastAPI (Python) or NestJS (Node.js) | Planned. Orchestrates chatbot → intent → routing engine → response |
| **Database** | PostgreSQL + PostGIS | Planned. Fare tables, cached routes, user data, spatial queries |
| **Fare & discount logic** | Custom rules engine | Planned. Config-driven fare tables (not hardcoded), 0.8 multiplier for eligible discounts |
| **Hosting** | Single VPS (DigitalOcean/Linode) | Planned. Runs OTP + backend + Postgres |

### Project Structure

```
lib/
├── main.dart
├── constants.dart                     # tile URL, default camera, Manila bounds, search settings
├── screens/
│   ├── home_screen.dart               # main map, search bar, selected-place sheet, directions
│   ├── search_location_screen.dart    # full search screen with debounce + AI query bar
│   ├── location_details_screen.dart   # standalone place/route details screen
│   ├── location_disabled_screen.dart  # map + prompt to enable location services
│   └── drawer_destination_screen.dart # profile, saved places, trip history, settings, help
├── services/
│   ├── ai_assistant_service.dart      # regex-based Taglish query parsing (origin/destination/preference)
│   ├── place_search_service.dart      # Nominatim search
│   ├── route_planner_service.dart     # OSRM walking/driving routes + mocked multimodal options
│   ├── saved_places_service.dart      # persisted saved places (shared_preferences)
│   └── trip_history_service.dart      # persisted trip history (shared_preferences)
└── widgets/
    ├── ask_mapparaan_bar.dart         # reusable pill-shaped search/ask input
    ├── circle_icon_button.dart        # circular overlay button (menu, back, location, etc.)
    ├── location_details_sheet.dart    # draggable bottom sheet with transport mode picker
    ├── mapparaan_drawer.dart          # side navigation menu
    └── mapparaan_tile_layer.dart      # CARTO Voyager tiles + configurable color tint
```

### Data Sources

- **Sakay.ph GTFS** (GitHub) — jeepney/bus/rail route data, community-maintained
- **OpenStreetMap** — Metro Manila road network extract for OTP/OSRM, plus the map data behind the tiles and Nominatim search
- **CARTO Voyager** — basemap tiles built on OpenStreetMap data
- **OSRM** (`router.project-osrm.org`) — real walking/driving route geometry, distance, and duration
- **DOTr/LTFRB fare orders** — manually sourced fare tables
- **RA 11314 / RA 9994 / RA 10754** — legal basis for discount rules

### Attribution

Map data © OpenStreetMap contributors. Basemap tiles © CARTO. Both require visible attribution in the app.