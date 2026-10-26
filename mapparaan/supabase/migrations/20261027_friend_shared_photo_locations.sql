-- Expose the saved place and exact coordinates only to recipients with an
-- active grant for that specific memory photo.
BEGIN;

ALTER TABLE public.memory_pin_shares
  ALTER COLUMN area_code DROP NOT NULL;

CREATE OR REPLACE FUNCTION public.set_memory_pin_shares(
  p_memory_pin_id UUID,
  p_friend_ids UUID[],
  p_area_code TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_friend_id UUID;
  v_friendship_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF p_memory_pin_id IS NULL OR p_friend_ids IS NULL
      OR cardinality(p_friend_ids) > 20 THEN
    RAISE EXCEPTION 'Invalid photo sharing request';
  END IF;
  IF p_area_code IS NOT NULL AND p_area_code NOT IN (
    'binondo', 'ermita', 'intramuros', 'malate', 'paco', 'pandacan',
    'port_area', 'quiapo', 'sampaloc', 'san_andres', 'san_miguel',
    'san_nicolas', 'santa_ana', 'santa_cruz', 'tondo'
  ) THEN
    RAISE EXCEPTION 'Choose an approved broad area';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(p_friend_ids) AS selected(friend_id)
    GROUP BY selected.friend_id HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Duplicate friend selection';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.memory_pins AS pin
    WHERE pin.id = p_memory_pin_id AND pin.user_id = v_user_id
      AND pin.image_path IS NOT NULL
      AND pin.image_path LIKE v_user_id::text || '/%'
  ) THEN
    RAISE EXCEPTION 'Photo not found or not owned by this account';
  END IF;

  DELETE FROM public.memory_pin_shares AS s
  WHERE s.memory_pin_id = p_memory_pin_id
    AND s.owner_id = v_user_id
    AND NOT (s.friend_id = ANY(p_friend_ids));

  FOREACH v_friend_id IN ARRAY p_friend_ids LOOP
    IF v_friend_id IS NULL OR v_friend_id = v_user_id THEN
      RAISE EXCEPTION 'Invalid friend selection';
    END IF;

    SELECT f.id INTO v_friendship_id
    FROM public.friendships AS f
    WHERE f.user_a = LEAST(v_user_id, v_friend_id)
      AND f.user_b = GREATEST(v_user_id, v_friend_id);

    IF v_friendship_id IS NULL THEN
      RAISE EXCEPTION 'All selected people must be accepted friends';
    END IF;

    INSERT INTO public.memory_pin_shares (
      memory_pin_id, owner_id, friend_id, friendship_id, area_code
    ) VALUES (
      p_memory_pin_id, v_user_id, v_friend_id, v_friendship_id, p_area_code
    )
    ON CONFLICT (memory_pin_id, friend_id)
    DO UPDATE SET area_code = EXCLUDED.area_code;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_shared_memory_photos_with_location()
RETURNS TABLE(
  photo_id UUID,
  owner_id UUID,
  owner_name TEXT,
  place_name TEXT,
  address TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  image_path TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT pin.id, s.owner_id, owner.full_name, pin.place_name, pin.address,
         public.ST_Y(pin.geom), public.ST_X(pin.geom), pin.image_path,
         s.created_at
  FROM public.memory_pin_shares AS s
  JOIN public.friendships AS f
    ON f.id = s.friendship_id
  JOIN public.memory_pins AS pin
    ON pin.id = s.memory_pin_id AND pin.user_id = s.owner_id
  JOIN public.users AS owner ON owner.id = s.owner_id
  WHERE auth.uid() IS NOT NULL
    AND s.friend_id = auth.uid()
    AND pin.geom IS NOT NULL
    AND pin.image_path LIKE s.owner_id::text || '/%'
  ORDER BY s.created_at DESC
  LIMIT 100;
$$;

REVOKE ALL ON FUNCTION public.list_shared_memory_photos_with_location()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_shared_memory_photos_with_location()
  TO authenticated;

COMMIT;
