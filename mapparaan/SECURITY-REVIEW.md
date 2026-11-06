# Mapparaan Security Review

**Review date:** 2026-11-07  
**Scope:** Static review of checked-in application, Supabase migrations, and deployment documentation.

## Summary

No confirmed exploitable vulnerability was established from the checked-in files reviewed. Two conditional risks require deployment verification: effective Supabase storage policies and ensuring the bundled `.env` contains only public client configuration. The local `.env` was not inspected by the original review.

| # | Severity | File | Lines | Finding | Confidence |
|---|---|---|---|---|---|
| 1 | HIGH if legacy policies remain | [README.md](README.md), [Actibe photo uploading.sql](supabase/migrations/Actibe%20photo%20uploading.sql) | README: 38–69; SQL: 1–7 | If legacy public-read storage policies remain active and private-photo hardening is absent, memory photos may be publicly readable. | 8/10 (conditional) |
| 2 | HIGH if a privileged secret is bundled | [pubspec.yaml](pubspec.yaml), [README.md](README.md) | pubspec assets; README: 5–24 | `.env` is bundled as a Flutter asset and values can be extracted from a release build. A privileged credential in it would be exposed. | 9/10 (exposure path; contents unverified) |

## Findings and recommended actions

### 1. Verify deployed photo-storage policies

The checked-in migrations describe private-photo protections, but migrations in the repository do not prove those changes were applied to the live database. The README notes that the deployed migration history and policies were not verified, and the 20261029 storage-read migration is pending verification.

In the intended Supabase project, verify that the bucket is private and effective `storage.objects` policies allow reads only for the owner and explicitly authorized friends. Confirm the required migrations and helper functions are deployed. Do not rely on repository SQL alone to enforce access in the live project.

### 2. Client configuration and privileged secrets

The `.env` file is bundled into Flutter releases and can be extracted. This is acceptable only for public client configuration such as Supabase's publishable/anon key. Never put a Supabase `service_role` key or another privileged credential in it. The original review did not inspect the local `.env` contents.

## CIA triad assessment

- **Confidentiality:** The primary concerns are conditional public access to stored photos and accidental bundling of privileged credentials.
- **Integrity:** No confirmed integrity vulnerability was established from the files reviewed. Continue enforcing authorization and ownership checks in Supabase policies and server-side operations.
- **Availability:** No confirmed availability vulnerability was established from the files reviewed. This was not a load, resilience, or live-service assessment.

## Limitations

This review did not inspect the live Supabase project, local `.env` contents, provider dashboards, deployed service configuration, or historical repository contents; it did not run active penetration tests or execute migrations. Verify deployed storage policies and ensure `.env` contains no privileged secrets.
