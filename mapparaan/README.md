# mapparaan

A new Flutter project.

## Local configuration

Copy `.env.client.example` to `.env.client` and set the public client
configuration before running the Flutter app. `.env.client` is ignored by Git
and bundled as a Flutter asset, so every value in it is extractable. It may
contain only public client configuration such as the Supabase URL and
publishable/anon key, plus provider-restricted public map keys. Never place
`GEMINI_API_KEY`, a Supabase `service_role` key, or any other privileged secret
in `.env.client`.

For the Python backend, copy `.env.example` to `.env`. Keep server-only
credentials such as `GEMINI_API_KEY` in that backend environment only. The
backend loads `.env` locally; it is not included in the Flutter asset bundle.

Supabase's publishable/anon key is a public client key; protect user data with
database Row Level Security and Storage policies. CARTO keys are also visible
to clients and should be restricted by provider-side domain, quota, and
allowed API settings. Never put a Supabase `service_role` key or another
privileged secret in `.env.client`.

Release builds require HTTPS URLs for Supabase and the transit API. The
localhost transit URL is a development fallback only. Route planning sends
coordinates to the configured transit API; place searches and map tiles also
contact their configured providers, which can observe request metadata and
queries/viewport locations. The app uses HTTPS for remote providers where
available, but does not implement end-to-end encryption: Supabase and the
configured providers must process the data needed to provide their services.
Tell users which providers receive location data and avoid sending more than
each feature needs.

After creating `.env.client` or changing Flutter assets, run `flutter pub get`
and rebuild the app.

## Supabase database setup

The destructive dashboard "Master SQL Script" drops application tables before
recreating them. Do not run it against a project containing data.

This checkout does not contain `supabase/master_schema.sql` or the original
`20261026_friend_memory_sharing.sql` migration referenced by older setup notes.
It is therefore not a complete fresh-project database setup, and the missing
schema/migration must be recovered from a trusted source before provisioning a
new project. Do not recreate missing historical migrations from memory.

For an existing project, compare its migration history and current policies
with the checked-in SQL before applying any migration. Back up the database
first. SQL files are not applied by the Flutter app, and this workspace cannot
verify or change the live project's migration history or settings.

The two unversioned SQL files in `supabase/migrations` are legacy-policy
cleanup scripts only; they are not schema setup or ordered migrations. The
versioned private-photo migrations replace the old public-read and broad
upload policies with owner-scoped policies.

### Friend-only memory photo sharing

The checked-in migrations include private-photo hardening (20261022/20261023),
shared-photo location support (20261027), and normalization/validation of
sharing records (20261028). The 20261027 and 20261028 migrations depend on the
friend-sharing schema and RPCs from the missing 20261026 migration. Do not
apply them to a project unless its migration history confirms those
prerequisites are present.

The pending `supabase/migrations/20261029_shared_memory_storage_reads.sql`
allows accepted recipients to read only explicitly shared image objects.
Apply it only after confirming the deployed
`public.can_read_shared_memory_photo(text)` function and earlier sharing
schema exist. It replaces the restrictive all-command owner boundary with
separate command policies: reads allow the owner or a selected recipient;
uploads and deletes remain owner-only; Storage updates remain blocked. The
migration fails with an explicit error if the helper function is missing.
Never edit or re-run historical migrations already applied to a database.

### Terms and privacy acknowledgements

The registration flow requires users to open and review both notices before
enabling the account-creation button. The current notice versions are declared
in `lib/legal/legal_documents.dart` and must match
`supabase/migrations/20261107_terms_privacy_acknowledgements.sql`. The migration
records acknowledgements on the server and blocks account-data access until
both current versions are recorded. Do not apply it until the missing trusted
friend-sharing schema/migration has been recovered and the migration's target
tables and function signatures have been checked against the live project.
The migration replaces the known invite, friendship, and memory-sharing RPCs
with versions that enforce the current acknowledgement gate; it requires the
base friend-sharing tables and functions to exist, including `friend_invites`.
This checkout still lacks the historical base friend-sharing migration, so a
fresh database cannot be provisioned from these files alone.

Before release, replace the privacy/contact placeholders in the notice with
verified controller and contact details, retention/deletion procedures, and
provider processing information. The document is a project draft, not legal
advice. Client-supplied acknowledgement metadata is an assertion, not
cryptographic proof of a user's UI actions; the backend enforces that current
version records exist before allowing account-data access.

The migration adds normalized friendships, hashed single-use invite codes
(24-hour expiry, maximum five invites created per account per 24 hours), and
per-photo/per-recipient grants. Existing photos stay private. Migration 20261027
adds a friend-only RPC that returns the saved place name, address, and exact
map coordinates only for photos explicitly shared with the signed-in
recipient. Shared photos appear as markers on the map; tapping a marker shows
the photo and location. Multiple shared photos at the same coordinates are
grouped into a marker with next/previous controls. The map layer selector
switches between your photos, photos shared with you, or both. Selecting a
friend is explicit consent to share that precise location as well as the
image. Review saved place data before sharing: an incorrect or overly specific
address will be shown as stored.

The Storage bucket remains private and friends can request a signed image URL
only while the friendship and that exact photo grant remain active. Friend URLs
expire after two minutes, but cannot recall an image already downloaded or
copied. Photo contents themselves may reveal more than the saved location.
Owner photo URLs expire after ten minutes and are refreshed when the app loads
the owner's photo list.
Friend invite codes are bearer secrets: share them privately. Acceptance
requires a signed-in account and an explicit action. Removing a friend deletes
their photo grants, and re-adding them does not restore those grants. Verify
both migrations and Storage policies in the intended Supabase project before
testing with real accounts.

Before treating sharing as verified, use test accounts A, B, and C to check:

- B cannot see A's photos before accepting A's invite, and cannot see any
  unshared photo after accepting.
- After A shares one photo with B only, B can see that image and its saved
  location details; C and other signed-in users cannot receive the image or
  location.
- B cannot upload to or delete from A's Storage folder. A can still manage
  A's own photos.
- Removing B revokes future access and removes the grant. An already issued
  signed URL may remain usable for up to two minutes.
- An invite cannot be accepted by its creator, accepted twice, or accepted
  after expiry.

Password brute-force defenses are configured in the Supabase project, not by
Flutter client-side throttling. Verify the project's Auth rate limits and
configure CAPTCHA/abuse protection where available. Do not treat a client-side
lockout as a security boundary. The bundled Supabase anon/publishable key and map-provider keys are public
client configuration; never put a `service_role` or other privileged key in
`.env.client`, and restrict provider keys in their respective dashboards.

Run the transit planner locally from this directory with
`python backend/planner/api.py --host 127.0.0.1 --port 8080`. The app's default
`TRANSIT_API_URL` points to this local service; Android emulators are routed to
the host machine automatically. If the app displays "Server offline", first
check `http://127.0.0.1:8080/health`.

The Render blueprint is at the repository root (`render.yaml`). Deploy that
blueprint to create the hosted planner, then set `TRANSIT_API_URL` in the
Flutter app's `.env.client` to the deployed HTTPS service URL. For Flutter web, also
set `MAPPARAAN_ALLOWED_ORIGINS` on Render to the exact web-app origin. The API
binds to loopback locally; public deployments require that allowlist, TLS, and
appropriate abuse controls. CORS is not authentication.

### AI backend scaffolding and quota enforcement

The Python backend now includes a lightweight AI orchestration layer for the
existing server, rather than a separate FastAPI deployment. This keeps the
transport planner and the AI scaffold in one place, avoids extra runtime cost,
and preserves the current architecture. The existing Flutter chat client sends requests to this backend and uses the
current Supabase session for authentication.

Server-side configuration stays in the backend environment, not in Flutter.
Set `GEMINI_API_KEY` in the backend environment before enabling live Gemini
calls, `SUPABASE_URL` plus `SUPABASE_PUBLISHABLE_KEY` (or the legacy
`SUPABASE_ANON_KEY`) so the backend can validate session tokens, and optionally
`GEMINI_MODEL` to override the default model. Use only a Supabase public client
key for token verification; never configure a `service_role` key. The
project currently targets the Google AI Studio free-tier
`gemini-flash-lite-latest` alias, which resolves to `gemini-3.5-flash-lite`
and supports function calling under the current Free Tier; verify the active AI
Studio model list before production use because Google refreshes aliases over
time. The AI quota ledger persists locally in `data/ai_usage.sqlite3` by
default, with a matching Supabase migration at
`supabase/migrations/20261106_ai_usage_quota.sql` for projects that want to
move the same policy into a managed database. Apply
`supabase/migrations/20261107_harden_ai_usage_quota.sql` after that schema
migration: client roles can read only their own quota rows and cannot insert,
update, or delete events. The enforced limits are:

- 10 messages per authenticated user per day
- 5 messages per authenticated user per minute
- 100 AI messages globally per day
- reset based on `Asia/Manila` local time

The quota is keyed by the identity returned by Supabase after validating the
Bearer access token, so a client-supplied `user_id` cannot change quota
attribution. Requests without a valid token are rejected; requests that exceed
quota return a 429 response. Flutter sends the Supabase session access token in
the `Authorization` header. The backend verifies it through Supabase Auth and
does not expose Gemini credentials to Flutter. For web clients, include the
app's exact origin in `MAPPARAAN_ALLOWED_ORIGINS`; CORS is not authentication.

The assistant can geocode named locations, find nearby supported places or
GTFS stops, estimate fares using planner output, and inspect static GTFS
service estimates. Route and schedule recommendations are not live traffic or
vehicle data; missing schedule data is reported as unknown rather than proof
that a service is closed. AI question text and up to ten recent messages are
sent to Gemini. Named locations may be sent to Nominatim for geocoding, and
nearby searches may send a category and location to Overpass. Limited
conversation context is held in backend memory for up to 30 minutes after
activity, while quota records are stored in the backend's local SQLite
database. Render restarts or multiple instances do not share that SQLite quota
ledger or conversation context; configure shared persistent storage/rate
limiting before relying on these controls in production.

The current privacy notice documents this processing as version
`2026-11-07-v2`. Before deploying the updated Flutter app, apply
`supabase/migrations/20261107_update_ai_privacy_notice.sql` after the existing
legal-acknowledgement migration so users are asked to acknowledge the updated
notice. Confirm migration prerequisites and deployed state first; this
workspace cannot verify the live Supabase project.

The Flutter planner sends route requests as JSON `POST /plan` requests so
coordinates are not placed in request URLs. Older `GET /plan` requests remain
supported for compatibility, but should not be used in new clients.

The location picker supports map pins for pickup and destination. Pin
coordinates are checked against the City of Manila boundary polygon in
`data/reference/manila_boundary.geojson` for map-pin selection. The route API
allows trips whose origin and destination are both within Manila or both
outside it, and blocks trips with one endpoint on each side. Reverse geocoding
may add an address label, but routing uses the confirmed coordinates and does
not depend on an address being found. Place-name search and reverse geocoding
use Nominatim; nearby categories query OpenStreetMap Overpass using the selected
category and device coordinates. Transit planning uses the available static
GTFS data, not live vehicle locations. Fare and travel-time values may be
estimates; when the planner is offline, the app does not invent transit routes
and shows only a street-walking alternative if one can be retrieved.

The current transit feed has 531 stops concentrated within the City of Manila.
Outside-to-outside requests are passed to the planner, but transit service is
not available throughout Metro Manila; locations without nearby feed stops may
return no transit itinerary. The planner can provide a street-walking fallback
when a verified walking route is available.

Memory photos are selected at up to 1600 pixels per side and recompressed to
JPEG with `flutter_image_compress` (including orientation correction and EXIF
removal). The app retries at lower quality and dimensions until the result is
under its 8 MB client limit. The Supabase bucket should also enforce its
server-side file-size and MIME-type limits; client compression is not a
substitute for those controls.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
