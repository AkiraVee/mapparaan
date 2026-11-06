-- Legacy policy cleanup only. Do not use this as a setup migration.
-- Authenticated bucket access is enforced by the versioned owner/share policies.
BEGIN;

DROP POLICY IF EXISTS "Restrict bucket listing" ON storage.objects;

COMMIT;
