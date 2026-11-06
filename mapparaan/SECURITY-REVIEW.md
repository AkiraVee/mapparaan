# Mapparaan Security Review

**Review date:** 2026-11-07  
**Scope:** Static review of checked-in application, Supabase migrations, and deployment documentation.

## Summary

The source configuration previously bundled the root `.env` file into Flutter,
and the local ignored `.env` was confirmed to contain a `GEMINI_API_KEY`
variable. This created a real client-bundle secret exposure path. Flutter now
loads a separate `.env.client` containing only public client settings. Any
Gemini key previously included in a distributed build should still be rotated.
The deployed Supabase policies and provider configuration remain unverified.

| # | Severity | File | Lines | Finding | Confidence |
|---|---|---|---|---|---|
| 1 | HIGH if legacy policies remain | [README.md](README.md), [Actibe photo uploading.sql](supabase/migrations/Actibe%20photo%20uploading.sql) | README: 38–69; SQL: 1–7 | If legacy public-read storage policies remain active and private-photo hardening is absent, memory photos may be publicly readable. | 8/10 (conditional) |
| 2 | HIGH — fixed in source; rotate prior key | [pubspec.yaml](pubspec.yaml), [main.dart](lib/main.dart), [README.md](README.md) | pubspec Flutter assets; `main.dart` dotenv asset | The root `.env` was bundled by Flutter and contained a server-only `GEMINI_API_KEY` variable. The app now bundles only `.env.client`; rotate any key that may have shipped in an earlier build. | 10/10 |

## Findings and recommended actions

### 1. Verify deployed photo-storage policies

The checked-in migrations describe private-photo protections, but migrations in the repository do not prove those changes were applied to the live database. The README notes that the deployed migration history and policies were not verified, and the 20261029 storage-read migration is pending verification.

In the intended Supabase project, verify that the bucket is private and effective `storage.objects` policies allow reads only for the owner and explicitly authorized friends. Confirm the required migrations and helper functions are deployed. Do not rely on repository SQL alone to enforce access in the live project.

### 2. Client configuration and privileged secrets — fixed in source

The app now loads `.env.client`, not the backend `.env`; `.env.client` remains a
Flutter asset and must contain only public settings. The local `.env` variable
names confirmed `GEMINI_API_KEY`, so rotate that key if it was present in any
shared, published, or deployed Flutter artifact. The secret value is not
recorded here. The backend `.env` remains ignored by Git and is not included in
Flutter assets.

## CIA triad assessment

- **Confidentiality:** The primary concerns are conditional public access to stored photos and accidental bundling of privileged credentials.
- **Integrity:** No confirmed integrity vulnerability was established from the files reviewed. Continue enforcing authorization and ownership checks in Supabase policies and server-side operations.
- **Availability:** No confirmed availability vulnerability was established from the files reviewed. This was not a load, resilience, or live-service assessment.

## Limitations

This review did not inspect the live Supabase project, provider dashboards,
deployed service configuration, or historical repository contents; it did not
run active penetration tests or execute migrations. Verify deployed storage
policies, rotate any previously bundled Gemini key, and confirm the deployed
backend configuration.
