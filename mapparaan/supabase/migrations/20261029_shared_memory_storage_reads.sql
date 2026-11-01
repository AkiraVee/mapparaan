-- Permit a signed-in friend to read only explicitly shared memory photos.
-- Uploads and deletes remain owner-scoped; Storage updates stay disabled.
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public.can_read_shared_memory_photo(text)') IS NULL THEN
    RAISE EXCEPTION
      'Apply and verify the friend-sharing migrations before this migration';
  END IF;
END
$$;

DROP POLICY IF EXISTS "Enforce memory photo owner boundary"
  ON storage.objects;
DROP POLICY IF EXISTS "Enforce memory photo select boundary"
  ON storage.objects;
DROP POLICY IF EXISTS "Enforce memory photo insert boundary"
  ON storage.objects;
DROP POLICY IF EXISTS "Enforce memory photo update boundary"
  ON storage.objects;
DROP POLICY IF EXISTS "Enforce memory photo delete boundary"
  ON storage.objects;
DROP POLICY IF EXISTS "Friends can read explicitly shared memory photos"
  ON storage.objects;

CREATE POLICY "Enforce memory photo select boundary"
ON storage.objects
AS RESTRICTIVE
FOR SELECT
TO public
USING (
  bucket_id <> 'memory-photos'
  OR (
    auth.uid() IS NOT NULL
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR public.can_read_shared_memory_photo(name)
    )
  )
);

CREATE POLICY "Friends can read explicitly shared memory photos"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'memory-photos'
  AND public.can_read_shared_memory_photo(name)
);

CREATE POLICY "Enforce memory photo insert boundary"
ON storage.objects
AS RESTRICTIVE
FOR INSERT
TO public
WITH CHECK (
  bucket_id <> 'memory-photos'
  OR (
    auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
);

CREATE POLICY "Enforce memory photo delete boundary"
ON storage.objects
AS RESTRICTIVE
FOR DELETE
TO public
USING (
  bucket_id <> 'memory-photos'
  OR (
    auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
);

COMMIT;
