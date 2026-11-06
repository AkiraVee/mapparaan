# Mapparaan Security Review

**Review date:** 2026-11-07  
**Scope:** Read-only review of checked-in application, Supabase migration, and deployment documentation.

## Summary

No confirmed exploitable vulnerability was established from the checked-in files reviewed. Two conditional risks need verification against the deployed Supabase project and release configuration. The live Supabase policies and the local `.env` contents were not inspected.

| # | Severity | File | Lines | Finding | Confidence |
|---|---|---|---|---|---|
| 1 | HIGH if legacy policies remain | [README.md](README.md), [Actibe photo uploading.sql](supabase/migrations/Actibe%20photo%20uploading.sql) | README: 38–66; SQL: 1–5 | If legacy public-read storage policies remain active and private-photo hardening is absent, memory photos may be publicly readable. | 8/10 (conditional) |
| 2 | HIGH if a privileged secret is bundled | [pubspec.yaml](pubspec.yaml), [README.md](README.md) | pubspec: 75–79; README: 7–17 | `.env` is included in Flutter assets and can be extracted from a release build. A service-role key or other privileged credential in it would be exposed. | 9/10 (exposure path; contents unverified) |

## Findings and recommended actions

### 1. Verify deployed photo-storage policies

The checked-in migrations describe private-photo protections, but migrations in the repository do not prove those changes were applied to the live database. The README notes that the deployed migration history and policies were not verified, and the 20261029 storage-read migration is pending verification.

In the intended Supabase project, verify that the photo bucket is private and that effective `storage.objects` policies allow reads only for the owner and explicitly authorized friends. Confirm the required migrations and helper functions are deployed. Do not rely on the client app or repository SQL alone to enforce storage access.

### 2. Keep privileged secrets out of the Flutter asset bundle

The Flutter asset declaration includes `.env`. Values shipped in a mobile or web app should be treated as public because users can extract them. The documented Supabase publishable key and appropriately restricted provider client configuration can be public; a Supabase service-role key or any other privileged credential must not be included.

Ensure `.env` contains only public client configuration, and add a release-build secret scan or equivalent check to prevent privileged credentials from being bundled. The local `.env` contents were not inspected in this review.

## CIA triad assessment

- **Confidentiality:** The primary concerns are conditional public access to stored photos and accidental bundling of privileged credentials.
- **Integrity:** No confirmed integrity vulnerability was established from the files reviewed. Continue enforcing authorization and ownership checks in Supabase policies and server-side operations.
- **Availability:** No confirmed availability vulnerability was established from the files reviewed. This was not a load, resilience, or live-service assessment.

## Limitations

This was a static, read-only review of checked-in material. It did not inspect the live Supabase project, local `.env` values, provider dashboards, deployed service configuration, or historical repository contents; it did not run active penetration tests or execute migrations. The conditional findings should be verified before treating the deployment as secure.
