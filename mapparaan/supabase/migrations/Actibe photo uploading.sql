-- Legacy policy cleanup only. Do not use this as a setup migration.
-- The old policies allowed public reads and uploads outside owner folders.
BEGIN;

DROP POLICY IF EXISTS "Users can upload memory photos" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view memory photos" ON storage.objects;

COMMIT;
