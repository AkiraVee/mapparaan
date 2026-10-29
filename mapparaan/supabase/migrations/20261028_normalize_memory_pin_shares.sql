-- Remove the duplicated owner_id from photo grants. The pin is the
-- authoritative source for its owner; friendship membership is guarded below.
-- Apply after the 20261026 friend-sharing and 20261027 location migrations.
BEGIN;

DO $$
BEGIN
  IF to_regclass('public.memory_pin_shares') IS NULL
      OR to_regclass('public.memory_pins') IS NULL
      OR to_regclass('public.friendships') IS NULL
      OR to_regclass('public.users') IS NULL THEN
    RAISE EXCEPTION
      'Apply the base friend-sharing migration before this migration';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_attribute
    WHERE attrelid = 'public.memory_pin_shares'::regclass
      AND attname = 'owner_id'
      AND NOT attisdropped
  ) THEN
    RAISE EXCEPTION
      'Expected memory_pin_shares.owner_id; database may already be normalized';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_attribute
    WHERE attrelid = 'public.memory_pin_shares'::regclass
      AND attname = 'area_code'
      AND attnotnull
      AND NOT attisdropped
  ) THEN
    RAISE EXCEPTION
      'Apply the 20261027 sharing migration before this migration';
  END IF;

  IF to_regprocedure(
       'public.set_memory_pin_shares(uuid,uuid[],text)'
     ) IS NULL
     OR to_regprocedure('public.list_memory_pin_shares(uuid)') IS NULL
     OR to_regprocedure('public.list_shared_memory_photos()') IS NULL
     OR to_regprocedure(
       'public.list_shared_memory_photos_with_location()'
     ) IS NULL
     OR to_regprocedure('public.can_read_shared_memory_photo(text)') IS NULL
  THEN
    RAISE EXCEPTION
      'Expected friend-sharing RPCs are missing; confirm the 20261026 and 20261027 migrations ran';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc AS routine
    JOIN pg_namespace AS routine_schema
      ON routine_schema.oid = routine.pronamespace
    WHERE routine_schema.nspname NOT IN ('pg_catalog', 'information_schema')
      AND routine.prosrc ILIKE '%memory_pin_shares%'
      AND routine.prosrc ILIKE '%owner_id%'
      AND routine.oid NOT IN (
        to_regprocedure('public.set_memory_pin_shares(uuid,uuid[],text)')::oid,
        to_regprocedure('public.list_memory_pin_shares(uuid)')::oid,
        to_regprocedure('public.list_shared_memory_photos()')::oid,
        to_regprocedure('public.list_shared_memory_photos_with_location()')::oid,
        to_regprocedure('public.can_read_shared_memory_photo(text)')::oid
      )
  ) THEN
    RAISE EXCEPTION
      'A custom public function still references memory_pin_shares.owner_id; update it before normalizing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.memory_pin_shares AS share
    LEFT JOIN public.memory_pins AS pin
      ON pin.id = share.memory_pin_id
     AND pin.user_id = share.owner_id
    WHERE pin.id IS NULL
  ) THEN
    RAISE EXCEPTION
      'Cannot normalize shares: a share owner does not match its memory pin';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.memory_pin_shares AS share
    JOIN public.memory_pins AS pin
      ON pin.id = share.memory_pin_id
    LEFT JOIN public.friendships AS friendship
      ON friendship.id = share.friendship_id
     AND (
       (friendship.user_a = pin.user_id
        AND friendship.user_b = share.friend_id)
       OR
       (friendship.user_b = pin.user_id
        AND friendship.user_a = share.friend_id)
     )
    WHERE friendship.id IS NULL
       OR pin.user_id = share.friend_id
  ) THEN
    RAISE EXCEPTION
      'Cannot normalize shares: a share does not match its friendship';
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION public.validate_memory_pin_share_friendship()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_owner_id UUID;
  v_user_a UUID;
  v_user_b UUID;
BEGIN
  SELECT pin.user_id INTO v_owner_id
  FROM public.memory_pins AS pin
  WHERE pin.id = NEW.memory_pin_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Memory pin does not exist';
  END IF;
  IF v_owner_id = NEW.friend_id THEN
    RAISE EXCEPTION 'A memory pin cannot be shared with its owner';
  END IF;

  SELECT friendship.user_a, friendship.user_b
  INTO v_user_a, v_user_b
  FROM public.friendships AS friendship
  WHERE friendship.id = NEW.friendship_id
  FOR UPDATE;

  IF NOT FOUND OR NOT (
    (v_user_a = v_owner_id AND v_user_b = NEW.friend_id)
    OR
    (v_user_b = v_owner_id AND v_user_a = NEW.friend_id)
  ) THEN
    RAISE EXCEPTION
      'Share must reference the friendship between the pin owner and recipient';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_memory_pin_share_friendship()
FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.prevent_invalid_share_parent_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF TG_TABLE_NAME = 'memory_pins' THEN
    IF EXISTS (
      SELECT 1
      FROM public.memory_pin_shares AS share
      JOIN public.friendships AS friendship
        ON friendship.id = share.friendship_id
      WHERE share.memory_pin_id = OLD.id
        AND NOT (
          (friendship.user_a = NEW.user_id
           AND friendship.user_b = share.friend_id)
          OR
          (friendship.user_b = NEW.user_id
           AND friendship.user_a = share.friend_id)
        )
    ) THEN
      RAISE EXCEPTION
        'Cannot change pin owner while it has shares to unrelated friends';
    END IF;
  ELSIF TG_TABLE_NAME = 'friendships' THEN
    IF EXISTS (
      SELECT 1
      FROM public.memory_pin_shares AS share
      JOIN public.memory_pins AS pin
        ON pin.id = share.memory_pin_id
      WHERE share.friendship_id = OLD.id
        AND NOT (
          (NEW.user_a = pin.user_id AND NEW.user_b = share.friend_id)
          OR
          (NEW.user_b = pin.user_id AND NEW.user_a = share.friend_id)
        )
    ) THEN
      RAISE EXCEPTION
        'Cannot change friendship participants while photo shares reference it';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.prevent_invalid_share_parent_change()
FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS memory_pin_shares_friendship_guard
ON public.memory_pin_shares;
CREATE TRIGGER memory_pin_shares_friendship_guard
BEFORE INSERT OR UPDATE
ON public.memory_pin_shares
FOR EACH ROW
EXECUTE FUNCTION public.validate_memory_pin_share_friendship();

DROP TRIGGER IF EXISTS memory_pins_share_owner_guard
ON public.memory_pins;
CREATE TRIGGER memory_pins_share_owner_guard
BEFORE UPDATE OF user_id
ON public.memory_pins
FOR EACH ROW
WHEN (OLD.user_id IS DISTINCT FROM NEW.user_id)
EXECUTE FUNCTION public.prevent_invalid_share_parent_change();

DROP TRIGGER IF EXISTS friendships_share_participant_guard
ON public.friendships;
CREATE TRIGGER friendships_share_participant_guard
BEFORE UPDATE OF user_a, user_b
ON public.friendships
FOR EACH ROW
WHEN (
  OLD.user_a IS DISTINCT FROM NEW.user_a
  OR OLD.user_b IS DISTINCT FROM NEW.user_b
)
EXECUTE FUNCTION public.prevent_invalid_share_parent_change();

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

  DELETE FROM public.memory_pin_shares AS share
  USING public.memory_pins AS pin
  WHERE pin.id = share.memory_pin_id
    AND pin.user_id = v_user_id
    AND share.memory_pin_id = p_memory_pin_id
    AND NOT (share.friend_id = ANY(p_friend_ids));

  FOREACH v_friend_id IN ARRAY p_friend_ids LOOP
    IF v_friend_id IS NULL OR v_friend_id = v_user_id THEN
      RAISE EXCEPTION 'Invalid friend selection';
    END IF;

    SELECT friendship.id INTO v_friendship_id
    FROM public.friendships AS friendship
    WHERE friendship.user_a = LEAST(v_user_id, v_friend_id)
      AND friendship.user_b = GREATEST(v_user_id, v_friend_id);

    IF v_friendship_id IS NULL THEN
      RAISE EXCEPTION 'All selected people must be accepted friends';
    END IF;

    INSERT INTO public.memory_pin_shares (
      memory_pin_id, friend_id, friendship_id, area_code
    ) VALUES (
      p_memory_pin_id, v_friend_id, v_friendship_id, p_area_code
    )
    ON CONFLICT (memory_pin_id, friend_id)
    DO UPDATE SET area_code = EXCLUDED.area_code;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_memory_pin_shares(
  p_memory_pin_id UUID
)
RETURNS TABLE(friend_id UUID, friend_name TEXT, area_code TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT share.friend_id, friend.full_name, share.area_code
  FROM public.memory_pin_shares AS share
  JOIN public.users AS friend ON friend.id = share.friend_id
  JOIN public.memory_pins AS pin
    ON pin.id = share.memory_pin_id
  JOIN public.friendships AS friendship
    ON friendship.id = share.friendship_id
   AND (
     (friendship.user_a = pin.user_id
      AND friendship.user_b = share.friend_id)
     OR
     (friendship.user_b = pin.user_id
      AND friendship.user_a = share.friend_id)
   )
  WHERE auth.uid() IS NOT NULL
    AND pin.user_id = auth.uid()
    AND share.memory_pin_id = p_memory_pin_id
  ORDER BY friend.full_name NULLS LAST, friend.id;
$$;

CREATE OR REPLACE FUNCTION public.list_shared_memory_photos()
RETURNS TABLE(
  photo_id UUID,
  owner_id UUID,
  owner_name TEXT,
  area_code TEXT,
  image_path TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT pin.id, pin.user_id, owner.full_name, share.area_code,
         pin.image_path, share.created_at
  FROM public.memory_pin_shares AS share
  JOIN public.friendships AS friendship
    ON friendship.id = share.friendship_id
  JOIN public.memory_pins AS pin
    ON pin.id = share.memory_pin_id
   AND (
     (friendship.user_a = pin.user_id
      AND friendship.user_b = share.friend_id)
     OR
     (friendship.user_b = pin.user_id
      AND friendship.user_a = share.friend_id)
   )
  JOIN public.users AS owner ON owner.id = pin.user_id
  WHERE auth.uid() IS NOT NULL
    AND share.friend_id = auth.uid()
    AND pin.image_path LIKE pin.user_id::text || '/%'
  ORDER BY share.created_at DESC
  LIMIT 100;
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
  SELECT pin.id, pin.user_id, owner.full_name, pin.place_name, pin.address,
         public.ST_Y(pin.geom), public.ST_X(pin.geom), pin.image_path,
         share.created_at
  FROM public.memory_pin_shares AS share
  JOIN public.friendships AS friendship
    ON friendship.id = share.friendship_id
  JOIN public.memory_pins AS pin
    ON pin.id = share.memory_pin_id
   AND (
     (friendship.user_a = pin.user_id
      AND friendship.user_b = share.friend_id)
     OR
     (friendship.user_b = pin.user_id
      AND friendship.user_a = share.friend_id)
   )
  JOIN public.users AS owner ON owner.id = pin.user_id
  WHERE auth.uid() IS NOT NULL
    AND share.friend_id = auth.uid()
    AND pin.geom IS NOT NULL
    AND pin.image_path LIKE pin.user_id::text || '/%'
  ORDER BY share.created_at DESC
  LIMIT 100;
$$;

CREATE OR REPLACE FUNCTION public.can_read_shared_memory_photo(
  p_object_name TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.memory_pin_shares AS share
    JOIN public.friendships AS friendship
      ON friendship.id = share.friendship_id
    JOIN public.memory_pins AS pin
      ON pin.id = share.memory_pin_id
     AND (
       (friendship.user_a = pin.user_id
        AND friendship.user_b = share.friend_id)
       OR
       (friendship.user_b = pin.user_id
        AND friendship.user_a = share.friend_id)
     )
    WHERE share.friend_id = auth.uid()
      AND pin.image_path = p_object_name
      AND pin.image_path LIKE pin.user_id::text || '/%'
  );
$$;

REVOKE ALL ON FUNCTION public.set_memory_pin_shares(UUID, UUID[], TEXT)
FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_memory_pin_shares(UUID)
FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_shared_memory_photos()
FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_shared_memory_photos_with_location()
FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_read_shared_memory_photo(TEXT)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.set_memory_pin_shares(UUID, UUID[], TEXT)
TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_memory_pin_shares(UUID)
TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_shared_memory_photos()
TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_shared_memory_photos_with_location()
TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_read_shared_memory_photo(TEXT)
TO anon, authenticated;

ALTER TABLE public.memory_pin_shares
  DROP COLUMN owner_id;

ALTER TABLE public.memory_pins
  DROP CONSTRAINT IF EXISTS memory_pins_id_user_unique;

ALTER TABLE public.memory_pin_shares
  ADD CONSTRAINT memory_pin_shares_memory_pin_id_fk
  FOREIGN KEY (memory_pin_id)
  REFERENCES public.memory_pins(id)
  ON DELETE CASCADE
  NOT VALID;

ALTER TABLE public.memory_pin_shares
  VALIDATE CONSTRAINT memory_pin_shares_memory_pin_id_fk;

COMMIT;
