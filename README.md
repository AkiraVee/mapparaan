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

## Tech Stack
 
| Layer | Technology | Notes |
|---|---|---|
| **Mobile app** | Flutter (Dart) | Single codebase for Android/iOS |
| **Map rendering** | Google Maps SDK (`google_maps_flutter`) | Markers, polylines, route display |
| **Driving/walking routing** | Google Routes API / OSRM (self-hosted) | Traffic-aware ETAs for road-based legs |
| **Transit routing** | OpenTripPlanner (OTP) | Multimodal (walk + transit) routing, self-hosted, ingests GTFS + OSM |
| **Chatbot / NLU** | Claude or GPT API (tool-calling / function-calling) | Parses Taglish natural language into structured intent (origin, destination, preference, passenger type); does not compute routes itself |
| **Backend** | FastAPI (Python) or NestJS (Node.js) | Orchestrates chatbot → intent → routing engine → response |
| **Database** | PostgreSQL + PostGIS | Fare tables, cached routes, user data, spatial queries |
| **Fare & discount logic** | Custom rules engine | Config-driven fare tables (not hardcoded), 0.8 multiplier for eligible discounts |
| **Hosting** | Single VPS (DigitalOcean/Linode) | Runs OTP + backend + Postgres |
 
