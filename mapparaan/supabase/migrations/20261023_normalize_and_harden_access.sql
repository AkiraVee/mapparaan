-- Incremental hardening for existing Mapparaan installations.
-- Review against the target project's current policies before applying.
BEGIN;

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_places ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memory_pins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Access own profile" ON public.users;
CREATE POLICY "Access own profile"
ON public.users
FOR ALL
TO authenticated
USING ((SELECT auth.uid()) = id)
WITH CHECK ((SELECT auth.uid()) = id);

DROP POLICY IF EXISTS "Enforce own profile boundary" ON public.users;
CREATE POLICY "Enforce own profile boundary"
ON public.users
AS RESTRICTIVE
FOR ALL
TO public
USING (auth.uid() IS NOT NULL AND auth.uid() = id)
WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = id);

DROP POLICY IF EXISTS "Access own preferences" ON public.user_preferences;
CREATE POLICY "Access own preferences"
ON public.user_preferences
FOR ALL
TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Enforce own preferences boundary" ON public.user_preferences;
CREATE POLICY "Enforce own preferences boundary"
ON public.user_preferences
AS RESTRICTIVE
FOR ALL
TO public
USING (auth.uid() IS NOT NULL AND auth.uid() = user_id)
WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);

DROP POLICY IF EXISTS "Access own saved places" ON public.saved_places;
CREATE POLICY "Access own saved places"
ON public.saved_places
FOR ALL
TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Enforce own saved places boundary" ON public.saved_places;
CREATE POLICY "Enforce own saved places boundary"
ON public.saved_places
AS RESTRICTIVE
FOR ALL
TO public
USING (auth.uid() IS NOT NULL AND auth.uid() = user_id)
WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);

DROP POLICY IF EXISTS "Access own memory pins" ON public.memory_pins;
CREATE POLICY "Access own memory pins"
ON public.memory_pins
FOR ALL
TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Enforce own memory pins boundary" ON public.memory_pins;
CREATE POLICY "Enforce own memory pins boundary"
ON public.memory_pins
AS RESTRICTIVE
FOR ALL
TO public
USING (auth.uid() IS NOT NULL AND auth.uid() = user_id)
WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);

DROP POLICY IF EXISTS "Access own trip history" ON public.trip_history;
CREATE POLICY "Access own trip history"
ON public.trip_history
FOR ALL
TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Enforce own trip history boundary" ON public.trip_history;
CREATE POLICY "Enforce own trip history boundary"
ON public.trip_history
AS RESTRICTIVE
FOR ALL
TO public
USING (auth.uid() IS NOT NULL AND auth.uid() = user_id)
WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.user_preferences'::regclass
      AND conname = 'user_preferences_theme_mode_valid'
  ) THEN
    ALTER TABLE public.user_preferences
      ADD CONSTRAINT user_preferences_theme_mode_valid
      CHECK (theme_mode IN ('system', 'light', 'dark')) NOT VALID;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.user_preferences'::regclass
      AND conname = 'user_preferences_color_palette_valid'
  ) THEN
    ALTER TABLE public.user_preferences
      ADD CONSTRAINT user_preferences_color_palette_valid
      CHECK (color_palette IN ('pasigDusk', 'intramuros', 'manilaBay', 'binondo'))
      NOT VALID;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.saved_places'::regclass
      AND conname = 'saved_places_name_nonempty'
  ) THEN
    ALTER TABLE public.saved_places
      ADD CONSTRAINT saved_places_name_nonempty
      CHECK (length(btrim(name)) > 0) NOT VALID;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.memory_pins'::regclass
      AND conname = 'memory_pins_place_name_nonempty'
  ) THEN
    ALTER TABLE public.memory_pins
      ADD CONSTRAINT memory_pins_place_name_nonempty
      CHECK (length(btrim(place_name)) > 0) NOT VALID;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.trip_history'::regclass
      AND conname = 'trip_history_duration_nonnegative'
  ) THEN
    ALTER TABLE public.trip_history
      ADD CONSTRAINT trip_history_duration_nonnegative
      CHECK (duration_minutes IS NULL OR duration_minutes >= 0) NOT VALID;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.trip_history'::regclass
      AND conname = 'trip_history_fare_nonnegative'
  ) THEN
    ALTER TABLE public.trip_history
      ADD CONSTRAINT trip_history_fare_nonnegative
      CHECK (fare_estimate IS NULL OR fare_estimate >= 0) NOT VALID;
  END IF;
END
$$;

ALTER TABLE public.user_preferences
  VALIDATE CONSTRAINT user_preferences_theme_mode_valid;
ALTER TABLE public.user_preferences
  VALIDATE CONSTRAINT user_preferences_color_palette_valid;
ALTER TABLE public.saved_places
  VALIDATE CONSTRAINT saved_places_name_nonempty;
ALTER TABLE public.memory_pins
  VALIDATE CONSTRAINT memory_pins_place_name_nonempty;
ALTER TABLE public.trip_history
  VALIDATE CONSTRAINT trip_history_duration_nonnegative;
ALTER TABLE public.trip_history
  VALIDATE CONSTRAINT trip_history_fare_nonnegative;

-- Email is already canonical in auth.users; public.users stores app profile data.
ALTER TABLE public.users DROP COLUMN IF EXISTS email;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.users (id, full_name)
  VALUES (NEW.id, NEW.raw_user_meta_data ->> 'full_name')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.user_preferences (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_new_user()
FROM PUBLIC, anon, authenticated;

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
SET public = false,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
WHERE id = 'memory-photos';

DROP POLICY IF EXISTS "Users can upload memory photos" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view memory photos" ON storage.objects;
DROP POLICY IF EXISTS "Restrict bucket listing" ON storage.objects;
DROP POLICY IF EXISTS "Owners can view memory photos" ON storage.objects;
CREATE POLICY "Owners can view memory photos"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'memory-photos'
  AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
);

DROP POLICY IF EXISTS "Owners can upload memory photos" ON storage.objects;
CREATE POLICY "Owners can upload memory photos"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'memory-photos'
  AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
);

DROP POLICY IF EXISTS "Owners can update memory photos" ON storage.objects;
DROP POLICY IF EXISTS "Block memory photo updates" ON storage.objects;
CREATE POLICY "Block memory photo updates"
ON storage.objects
AS RESTRICTIVE
FOR UPDATE
TO public
USING (bucket_id <> 'memory-photos')
WITH CHECK (
  bucket_id <> 'memory-photos'
);

DROP POLICY IF EXISTS "Owners can delete memory photos" ON storage.objects;
CREATE POLICY "Owners can delete memory photos"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'memory-photos'
  AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
);

-- Restrictive guard policies continue to constrain access if legacy permissive
-- policies remain on these tables. Unrelated buckets and rows are unaffected.
DROP POLICY IF EXISTS "Enforce memory photo owner boundary" ON storage.objects;
CREATE POLICY "Enforce memory photo owner boundary"
ON storage.objects
AS RESTRICTIVE
FOR ALL
TO public
USING (
  bucket_id <> 'memory-photos'
  OR (
    auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
)
WITH CHECK (
  bucket_id <> 'memory-photos'
  OR (
    auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
);

CREATE INDEX IF NOT EXISTS idx_saved_places_user_created
ON public.saved_places (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_memory_pins_user_created
ON public.memory_pins (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_trip_history_user_created
ON public.trip_history (user_id, created_at DESC);

COMMIT;
