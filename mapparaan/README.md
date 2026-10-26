# mapparaan

A new Flutter project.

## Local configuration

Copy `.env.example` to `.env` and set the project URL and client keys before
running the app. The `.env` file is ignored by Git and included as a Flutter
asset because `flutter_dotenv` loads it at startup. That means every value in
it is extractable from a distributed app.

Values included in a Flutter app are extractable from the built app. Supabase's
publishable/anon key is a public client key, not a server secret; protect user
data with database Row Level Security and Storage policies. CARTO keys are
also visible to clients and should be restricted by provider-side domain,
quota, and allowed API settings. Never put a Supabase `service_role` key or
another privileged secret in `.env`.

Release builds require HTTPS URLs for Supabase and the transit API. The
localhost transit URL is a development fallback only. Route planning sends
coordinates to the configured transit API; place searches and map tiles also
contact their configured providers, which can observe request metadata and
queries/viewport locations. The app uses HTTPS for remote providers where
available, but does not implement end-to-end encryption: Supabase and the
configured providers must process the data needed to provide their services.
Tell users which providers receive location data and avoid sending more than
each feature needs.

After changing configuration or Flutter assets, run `flutter pub get` and
rebuild the app.

## Supabase database setup

The old dashboard "Master SQL Script" dropped all application tables before
recreating them. Do not run that destructive version against production.

Use `supabase/master_schema.sql` as the replacement setup script for a new
project. It does not drop application tables or user rows, can be rerun, enables
owner-scoped table policies, makes `memory-photos` private with owner-folder
policies and upload limits, and adds the `image_path` column and saved-place ID
default required by the app. It removes the duplicate `public.users.email`
column; the canonical email remains in `auth.users`.

Alternatively, for a database already initialized with the original schema,
apply the incremental migrations in `supabase/migrations` in filename order.
The October 23 migration also removes the duplicate `public.users.email`
column and adds restrictive owner-boundary policies and photo upload limits.
It validates preference, place-name, duration, and fare constraints, so the
migration will stop rather than silently accept legacy rows that violate them.
Review the target project's existing policies and dependencies, take a backup,
and apply the scripts to the correct Supabase project. These SQL files are
not applied from the Flutter client; this workspace cannot verify or change
the live project's settings.

### Friend-only memory photo sharing

The friend-sharing feature is a separate incremental change. For an existing
project, first apply the 20261022 and 20261023 migrations if they have not
already been applied, then apply
`supabase/migrations/20261026_friend_memory_sharing.sql` once. For a new
project, run `supabase/master_schema.sql` first, then migrations 20261026 and
20261027 in order. Do not replace or edit migrations already applied to a
database.

If the sharing migration 20261026 has already been applied, apply only
`supabase/migrations/20261027_friend_shared_photo_locations.sql` next before
using this updated app. It does not modify or replace the earlier migration.

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
Friend invite codes are bearer secrets: share them privately. Acceptance
requires a signed-in account and an explicit action. Removing a friend deletes
their photo grants, and re-adding them does not restore those grants. Verify
both migrations and Storage policies in the intended Supabase project before
testing with real accounts.

Before treating sharing as verified, use test accounts A, B, and C to check:

- B cannot see A's photos before accepting A's invite, and cannot see any
  unshared photo after accepting.
- After A shares one photo with B only, B can see that image and broad area;
  C and other signed-in users cannot. The friend-facing response must not
  contain the pin geometry, address, or place name.
- B cannot upload to or delete from A's Storage folder. A can still manage
  A's own photos.
- Removing B revokes future access and removes the grant. An already issued
  signed URL may remain usable for up to two minutes.
- An invite cannot be accepted by its creator, accepted twice, or accepted
  after expiry.

Run the transit planner locally from this directory with
`python backend/planner/api.py --host 127.0.0.1 --port 8080`. The app's default
`TRANSIT_API_URL` points to this local service; Android emulators are routed to
the host machine automatically. If the app displays "Server offline", first
check `http://127.0.0.1:8080/health`.

The Render blueprint is at the repository root (`render.yaml`). Deploy that
blueprint to create the hosted planner, then set `TRANSIT_API_URL` in the
Flutter app's `.env` to the deployed HTTPS service URL. For Flutter web, also
set `MAPPARAAN_ALLOWED_ORIGINS` on Render to the exact web-app origin. The API
binds to loopback locally; public deployments require that allowlist, TLS, and
appropriate abuse controls. CORS is not authentication.

The Flutter planner sends route requests as JSON `POST /plan` requests so
coordinates are not placed in request URLs. Older `GET /plan` requests remain
supported for compatibility, but should not be used in new clients.

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
