-- Incremental production-safe hardening; this migration does not rebuild tables.
BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM storage.buckets
    WHERE id = 'memory-photos'
  ) THEN
    RAISE EXCEPTION 'Storage bucket memory-photos does not exist';
  END IF;
END
$$;

UPDATE storage.buckets
SET public = false
WHERE id = 'memory-photos';

DROP POLICY IF EXISTS "Users can upload memory photos" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view memory photos" ON storage.objects;
DROP POLICY IF EXISTS "Restrict bucket listing" ON storage.objects;
DROP POLICY IF EXISTS "Owners can view memory photos" ON storage.objects;
DROP POLICY IF EXISTS "Owners can upload memory photos" ON storage.objects;
DROP POLICY IF EXISTS "Owners can update memory photos" ON storage.objects;
DROP POLICY IF EXISTS "Owners can delete memory photos" ON storage.objects;

CREATE POLICY "Owners can view memory photos"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'memory-photos'
  AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
);

CREATE POLICY "Owners can upload memory photos"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'memory-photos'
  AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
);

CREATE POLICY "Owners can update memory photos"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'memory-photos'
  AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
)
WITH CHECK (
  bucket_id = 'memory-photos'
  AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
);

CREATE POLICY "Owners can delete memory photos"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'memory-photos'
  AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
);

ALTER TABLE public.memory_pins
ADD COLUMN IF NOT EXISTS image_path text;

ALTER TABLE public.saved_places
ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;

ALTER FUNCTION public.handle_new_user()
SET search_path = pg_catalog;

COMMIT;
