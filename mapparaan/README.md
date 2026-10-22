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

The transit planner binds to loopback by default. To make it available beyond
the local machine, set `MAPPARAAN_ALLOWED_ORIGINS` to the exact web origins,
use a trusted network during development, and put any public deployment behind
TLS and appropriate abuse controls. CORS is not authentication.

The Flutter planner sends route requests as JSON `POST /plan` requests so
coordinates are not placed in request URLs. Older `GET /plan` requests remain
supported for compatibility, but should not be used in new clients.

Account deletion is not implemented yet. The agreed design is immediate
permanent deletion or a cancellable 30-day grace period. Implementing it
requires a server-side privileged function and a scheduled worker to remove
both database rows and Storage objects; never put a Supabase service-role key
in the app.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
