# mapparaan

A new Flutter project.

## Local configuration

Copy `.env.example` to `.env` and set the project URL and client keys before
running the app. The `.env` file is ignored by Git and included as a Flutter
asset because `flutter_dotenv` loads it at startup.

Values included in a Flutter app are extractable from the built app. Supabase's
anon key is a public client key, not a server secret; protect user data with
database Row Level Security and Storage policies. Never put a Supabase
`service_role` key or another privileged secret in `.env`.

After changing configuration or Flutter assets, run `flutter pub get` and
rebuild the app.

## Supabase database setup

The old dashboard "Master SQL Script" dropped all application tables before
recreating them. Do not run that destructive version against production.

Use `supabase/master_schema.sql` as the replacement setup script. It does not
drop application tables, can be rerun, enables owner-scoped table policies,
makes `memory-photos` private with owner-folder policies, and adds the
`image_path` column and saved-place ID default required by the app.

Alternatively, for a database already initialized with the original schema,
apply the incremental migration in `supabase/migrations`. Apply database
changes to the correct Supabase project after taking a backup. The scripts
cannot be applied from the Flutter client.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
