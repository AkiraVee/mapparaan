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
| Interactive map (CARTO Voyager tiles, warm tint, Metro Manila default view) | Done |
| Place search (Nominatim, debounced, Metro Manila-biased) | Done |
| "My location" button with permission handling | Done |
| Selected-place pin and location details sheet | Done (Directions / Save / Share not wired yet) |
| Side drawer (Profile, Saved Places, Trip History, Settings, Help) | Done (placeholder pages) |
| Location-disabled and location-details screens | UI only, not yet connected to the map |
| Route preference buttons (fastest / cheapest / fewest transfers) | UI only |
| Chatbot / NLU | Planned |
| Transit and road routing | Planned |
| Fare and discount engine | Planned |

## Tech Stack

| Layer | Technology | Notes |
|---|---|---|
| **Mobile app** | Flutter (Dart) | Single codebase for Android/iOS (also runs on web for development) |
| **Map rendering** | `flutter_map` + `latlong2` | Pure-Dart map widget; markers, polylines, route display. No API key or native SDK needed |
| **Map tiles** | CARTO Voyager raster tiles (OpenStreetMap data) | Free, no API key. A warm sepia tint is applied in `MapparaanTileLayer` to match the AnoTara look. `flutter_map_cancellable_tile_provider` is used for better web performance |
| **Place search** | Nominatim (OpenStreetMap) | Called from `PlaceSearchService`; limited to the Philippines and biased to Metro Manila. Public instance has usage limits, so self-host or switch providers for production |
| **User location** | `geolocator` | Requested only when the user taps "my location" |
| **Driving/walking routing** | OSRM (self-hosted) or Google Routes API | Planned. Traffic-aware ETAs for road-based legs |
| **Transit routing** | OpenTripPlanner (OTP) | Planned. Multimodal (walk + transit) routing, self-hosted, ingests GTFS + OSM |
| **Chatbot / NLU** | Claude or GPT API (tool-calling / function-calling) | Planned. Parses Taglish natural language into structured intent (origin, destination, preference, passenger type); does not compute routes itself |
| **Backend** | FastAPI (Python) or NestJS (Node.js) | Planned. Orchestrates chatbot → intent → routing engine → response |
| **Database** | PostgreSQL + PostGIS | Planned. Fare tables, cached routes, user data, spatial queries |
| **Fare & discount logic** | Custom rules engine | Planned. Config-driven fare tables (not hardcoded), 0.8 multiplier for eligible discounts |
| **Hosting** | Single VPS (DigitalOcean/Linode) | Planned. Runs OTP + backend + Postgres |

### Project Structure

```
lib/
├── main.dart
├── constants.dart                  # tile URL, default camera, search settings
├── screens/
│   ├── home_screen.dart            # main map, search bar, selected-place sheet
│   ├── search_location_screen.dart
│   ├── location_details_screen.dart
│   ├── location_disabled_screen.dart
│   └── drawer_destination_screen.dart
├── services/
│   └── place_search_service.dart   # Nominatim search
└── widgets/
    ├── ask_mapparaan_bar.dart
    ├── circle_icon_button.dart
    ├── location_details_sheet.dart
    ├── mapparaan_drawer.dart
    └── mapparaan_tile_layer.dart   # CARTO Voyager + warm tint
```

### Data Sources

- **Sakay.ph GTFS** (GitHub) — jeepney/bus/rail route data, community-maintained
- **OpenStreetMap** — Metro Manila road network extract for OTP/OSRM, plus the map data behind the tiles and Nominatim search
- **CARTO Voyager** — basemap tiles built on OpenStreetMap data
- **DOTr/LTFRB fare orders** — manually sourced fare tables
- **RA 11314 / RA 9994 / RA 10754** — legal basis for discount rules

### Attribution

Map data © OpenStreetMap contributors. Basemap tiles © CARTO. Both require visible attribution in the app.