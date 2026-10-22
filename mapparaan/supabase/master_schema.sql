-- Safe, repeatable schema setup for Mapparaan.
-- This script does not drop application tables or delete user data.
BEGIN;

CREATE EXTENSION IF NOT EXISTS postgis SCHEMA public;

REVOKE ALL ON TABLE public.spatial_ref_sys
FROM anon, authenticated, PUBLIC;

CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  email TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_preferences (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  passenger_type TEXT
    CHECK (passenger_type IN ('general', 'student', 'senior', 'pwd'))
    DEFAULT 'general',
  theme_mode TEXT DEFAULT 'system',
  color_palette TEXT DEFAULT 'pasigDusk',
  use_metric_units BOOLEAN DEFAULT true,
  high_contrast_map BOOLEAN DEFAULT false,
  compact_ui BOOLEAN DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.saved_places (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  subtitle TEXT,
  geom GEOMETRY(Point, 4326),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_saved_places_geom
ON public.saved_places USING GIST (geom);

CREATE TABLE IF NOT EXISTS public.memory_pins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  place_name TEXT NOT NULL,
  address TEXT,
  geom GEOMETRY(Point, 4326),
  image_url TEXT,
  image_path TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_memory_pins_geom
ON public.memory_pins USING GIST (geom);

CREATE TABLE IF NOT EXISTS public.trip_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  origin_name TEXT,
  dest_name TEXT,
  preference TEXT,
  duration_minutes INT,
  fare_estimate NUMERIC,
  route_summary TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Bring existing installations up to date without rebuilding their tables.
ALTER TABLE public.saved_places
  ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;

ALTER TABLE public.memory_pins
  ADD COLUMN IF NOT EXISTS image_path TEXT;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.users (id, full_name, email)
  VALUES (NEW.id, NEW.raw_user_meta_data ->> 'full_name', NEW.email)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.user_preferences (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_new_user()
FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_places ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memory_pins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Access own profile" ON public.users;
DROP POLICY IF EXISTS "Access own preferences" ON public.user_preferences;
DROP POLICY IF EXISTS "Access own saved places" ON public.saved_places;
DROP POLICY IF EXISTS "Access own memory pins" ON public.memory_pins;
DROP POLICY IF EXISTS "Access own trip history" ON public.trip_history;

CREATE POLICY "Access own profile"
ON public.users
FOR ALL
TO authenticated
USING ((SELECT auth.uid()) = id)
WITH CHECK ((SELECT auth.uid()) = id);

CREATE POLICY "Access own preferences"
ON public.user_preferences
FOR ALL
TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Access own saved places"
ON public.saved_places
FOR ALL
TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Access own memory pins"
ON public.memory_pins
FOR ALL
TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Access own trip history"
ON public.trip_history
FOR ALL
TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);

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

COMMIT;
