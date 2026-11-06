-- Versioned Terms of Service and Data Privacy Notice acknowledgements.
-- Apply only after the account, memory, and friend-sharing schema exists.
BEGIN;

DO $$
BEGIN
  IF to_regclass('public.users') IS NULL
     OR to_regclass('public.user_preferences') IS NULL
     OR to_regclass('public.saved_places') IS NULL
     OR to_regclass('public.memory_pins') IS NULL
     OR to_regclass('public.trip_history') IS NULL
     OR to_regclass('public.friendships') IS NULL
     OR to_regclass('public.friend_invites') IS NULL
     OR to_regclass('public.memory_pin_shares') IS NULL
  THEN
    RAISE EXCEPTION
      'Apply the Mapparaan account and friend-sharing migrations first';
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS public.legal_document_versions (
  document_type TEXT NOT NULL
    CHECK (document_type IN ('terms_of_service', 'privacy_notice')),
  version TEXT NOT NULL,
  is_current BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (document_type, version)
);

CREATE UNIQUE INDEX IF NOT EXISTS legal_document_one_current_version
ON public.legal_document_versions (document_type)
WHERE is_current;

UPDATE public.legal_document_versions
SET is_current = FALSE
WHERE document_type IN ('terms_of_service', 'privacy_notice')
  AND is_current;

INSERT INTO public.legal_document_versions (
  document_type, version, is_current
) VALUES
  ('terms_of_service', '2026-11-07-v1', TRUE),
  ('privacy_notice', '2026-11-07-v1', TRUE)
ON CONFLICT (document_type, version)
DO UPDATE SET is_current = EXCLUDED.is_current;

CREATE TABLE IF NOT EXISTS public.user_legal_acknowledgements (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  document_type TEXT NOT NULL,
  version TEXT NOT NULL,
  acknowledged_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, document_type, version),
  FOREIGN KEY (document_type, version)
    REFERENCES public.legal_document_versions (document_type, version)
    ON UPDATE RESTRICT ON DELETE RESTRICT
);

ALTER TABLE public.legal_document_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_legal_acknowledgements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Legal versions are readable"
  ON public.legal_document_versions;
CREATE POLICY "Legal versions are readable"
ON public.legal_document_versions
FOR SELECT
TO anon, authenticated
USING (TRUE);

DROP POLICY IF EXISTS "Users can read own legal acknowledgements"
  ON public.user_legal_acknowledgements;
CREATE POLICY "Users can read own legal acknowledgements"
ON public.user_legal_acknowledgements
FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()));

REVOKE ALL ON public.user_legal_acknowledgements FROM anon, authenticated;
GRANT SELECT ON public.user_legal_acknowledgements TO authenticated;
REVOKE ALL ON public.legal_document_versions FROM anon, authenticated;
GRANT SELECT ON public.legal_document_versions TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.has_current_legal_acknowledgements()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT auth.uid() IS NOT NULL
    AND (
      SELECT count(*) = 2
      FROM public.legal_document_versions AS current_version
      JOIN public.user_legal_acknowledgements AS acknowledgement
        ON acknowledgement.document_type = current_version.document_type
       AND acknowledgement.version = current_version.version
       AND acknowledgement.user_id = auth.uid()
      WHERE current_version.is_current
        AND current_version.document_type IN (
          'terms_of_service', 'privacy_notice'
        )
    );
$$;

REVOKE ALL ON FUNCTION public.has_current_legal_acknowledgements()
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_current_legal_acknowledgements()
TO authenticated;

CREATE OR REPLACE FUNCTION public.record_current_legal_acknowledgements(
  p_terms_version TEXT,
  p_privacy_version TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.legal_document_versions
    WHERE document_type = 'terms_of_service'
      AND version = p_terms_version
      AND is_current
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.legal_document_versions
    WHERE document_type = 'privacy_notice'
      AND version = p_privacy_version
      AND is_current
  ) THEN
    RAISE EXCEPTION 'The current legal document versions must be acknowledged';
  END IF;

  INSERT INTO public.user_legal_acknowledgements (
    user_id, document_type, version, acknowledged_at
  ) VALUES
    (v_user_id, 'terms_of_service', p_terms_version, now()),
    (v_user_id, 'privacy_notice', p_privacy_version, now())
  ON CONFLICT (user_id, document_type, version) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.record_current_legal_acknowledgements(TEXT, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_current_legal_acknowledgements(TEXT, TEXT)
TO authenticated;

DO $$
BEGIN
  IF to_regprocedure('public.create_friend_invite()') IS NULL
     OR to_regprocedure('public.accept_friend_invite(text)') IS NULL
     OR to_regprocedure('public.list_friends()') IS NULL
     OR to_regprocedure('public.remove_friend(uuid)') IS NULL THEN
    RAISE EXCEPTION
      'Apply the trusted friend-sharing migration before this migration';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_friend_invite()
RETURNS TABLE(invite_code TEXT, expires_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_code TEXT;
  v_expiry TIMESTAMPTZ := now() + interval '24 hours';
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF NOT public.has_current_legal_acknowledgements() THEN
    RAISE EXCEPTION 'Current legal acknowledgements are required';
  END IF;

  PERFORM 1 FROM auth.users AS u WHERE u.id = v_user_id FOR UPDATE;

  IF (
    SELECT count(*)
    FROM public.friend_invites AS i
    WHERE i.inviter_id = v_user_id
      AND i.created_at > now() - interval '24 hours'
  ) >= 5 THEN
    RAISE EXCEPTION 'Invite limit reached; try again later';
  END IF;

  v_code := encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO public.friend_invites (inviter_id, token_hash, expires_at)
  VALUES (
    v_user_id,
    encode(extensions.digest(v_code, 'sha256'), 'hex'),
    v_expiry
  );

  RETURN QUERY SELECT v_code, v_expiry;
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_friend_invite(p_invite_code TEXT)
RETURNS TABLE(friend_id UUID, friend_name TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_invite public.friend_invites%ROWTYPE;
  v_a UUID;
  v_b UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF NOT public.has_current_legal_acknowledgements() THEN
    RAISE EXCEPTION 'Current legal acknowledgements are required';
  END IF;
  IF p_invite_code IS NULL OR p_invite_code !~ '^[0-9A-Fa-f]{64}$' THEN
    RAISE EXCEPTION 'Invite code is invalid';
  END IF;

  SELECT i.* INTO v_invite
  FROM public.friend_invites AS i
  WHERE i.token_hash = encode(
    extensions.digest(lower(p_invite_code), 'sha256'),
    'hex'
  )
    AND i.accepted_at IS NULL
    AND i.revoked_at IS NULL
    AND i.expires_at > now()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invite code is invalid, expired, or already used';
  END IF;
  IF v_invite.inviter_id = v_user_id THEN
    RAISE EXCEPTION 'You cannot accept your own invite';
  END IF;

  v_a := LEAST(v_invite.inviter_id, v_user_id);
  v_b := GREATEST(v_invite.inviter_id, v_user_id);

  INSERT INTO public.friendships (user_a, user_b)
  VALUES (v_a, v_b)
  ON CONFLICT (user_a, user_b) DO NOTHING;

  IF EXISTS (
    SELECT 1 FROM public.friendships AS f
    WHERE f.user_a = v_a AND f.user_b = v_b
  ) AND EXISTS (
    SELECT 1 FROM public.friend_invites AS i
    WHERE i.inviter_id = v_invite.inviter_id
      AND i.token_hash = v_invite.token_hash
  ) THEN
    UPDATE public.friend_invites
    SET accepted_at = now(), accepted_by = v_user_id
    WHERE id = v_invite.id;
  END IF;

  RETURN QUERY
  SELECT p.id, p.full_name
  FROM public.users AS p
  WHERE p.id = v_invite.inviter_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_friends()
RETURNS TABLE(friend_id UUID, friend_name TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    CASE WHEN f.user_a = auth.uid() THEN f.user_b ELSE f.user_a END,
    p.full_name
  FROM public.friendships AS f
  JOIN public.users AS p
    ON p.id = CASE WHEN f.user_a = auth.uid() THEN f.user_b ELSE f.user_a END
  WHERE public.has_current_legal_acknowledgements()
    AND auth.uid() IS NOT NULL
    AND auth.uid() IN (f.user_a, f.user_b)
  ORDER BY p.full_name NULLS LAST, p.id;
$$;

CREATE OR REPLACE FUNCTION public.remove_friend(p_friend_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL OR p_friend_id IS NULL OR v_user_id = p_friend_id THEN
    RAISE EXCEPTION 'Invalid friend';
  END IF;
  IF NOT public.has_current_legal_acknowledgements() THEN
    RAISE EXCEPTION 'Current legal acknowledgements are required';
  END IF;

  DELETE FROM public.friendships AS f
  WHERE f.user_a = LEAST(v_user_id, p_friend_id)
    AND f.user_b = GREATEST(v_user_id, p_friend_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.require_current_legal_ack_for_signup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.raw_user_meta_data ->> 'terms_acknowledged' IS DISTINCT FROM 'true'
     OR NEW.raw_user_meta_data ->> 'privacy_notice_acknowledged'
       IS DISTINCT FROM 'true'
     OR NOT EXISTS (
       SELECT 1
       FROM public.legal_document_versions
       WHERE document_type = 'terms_of_service'
         AND version = NEW.raw_user_meta_data ->> 'terms_version'
         AND is_current
     )
     OR NOT EXISTS (
       SELECT 1
       FROM public.legal_document_versions
       WHERE document_type = 'privacy_notice'
         AND version = NEW.raw_user_meta_data ->> 'privacy_notice_version'
         AND is_current
     )
  THEN
    RAISE EXCEPTION
      'Current Terms of Service and Data Privacy Notice acknowledgement is required'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_signup_legal_acknowledgements()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.user_legal_acknowledgements (
    user_id, document_type, version, acknowledged_at
  ) VALUES
    (
      NEW.id,
      'terms_of_service',
      NEW.raw_user_meta_data ->> 'terms_version',
      now()
    ),
    (
      NEW.id,
      'privacy_notice',
      NEW.raw_user_meta_data ->> 'privacy_notice_version',
      now()
    )
  ON CONFLICT (user_id, document_type, version) DO NOTHING;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.require_current_legal_ack_for_signup()
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_signup_legal_acknowledgements()
FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS mapparaan_require_legal_ack_for_signup ON auth.users;
CREATE TRIGGER mapparaan_require_legal_ack_for_signup
BEFORE INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.require_current_legal_ack_for_signup();

DROP TRIGGER IF EXISTS mapparaan_record_signup_legal_acknowledgements
ON auth.users;
CREATE TRIGGER mapparaan_record_signup_legal_acknowledgements
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.record_signup_legal_acknowledgements();

CREATE OR REPLACE FUNCTION public.enforce_current_legal_ack_on_app_data()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF TG_OP <> 'DELETE'
     AND auth.uid() IS NOT NULL
     AND NOT public.has_current_legal_acknowledgements() THEN
    RAISE EXCEPTION 'Current legal acknowledgements are required';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_current_legal_ack_on_app_data()
FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  table_name TEXT;
  app_tables TEXT[] := ARRAY[
    'users', 'user_preferences', 'saved_places', 'memory_pins',
    'trip_history', 'friendships', 'memory_pin_shares'
  ];
BEGIN
  FOREACH table_name IN ARRAY app_tables LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS %I ON public.%I',
      'Require current legal acknowledgements',
      table_name
    );
    EXECUTE format(
      'DROP POLICY IF EXISTS %I ON public.%I',
      'Require current legal acknowledgements for select',
      table_name
    );
    EXECUTE format(
      'DROP POLICY IF EXISTS %I ON public.%I',
      'Require current legal acknowledgements for insert',
      table_name
    );
    EXECUTE format(
      'DROP POLICY IF EXISTS %I ON public.%I',
      'Require current legal acknowledgements for update',
      table_name
    );
    EXECUTE format(
      'DROP POLICY IF EXISTS %I ON public.%I',
      'Require current legal acknowledgements for delete',
      table_name
    );
    EXECUTE format(
      'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated '
      'USING (public.has_current_legal_acknowledgements())',
      'Require current legal acknowledgements for select',
      table_name
    );
    EXECUTE format(
      'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated '
      'WITH CHECK (public.has_current_legal_acknowledgements())',
      'Require current legal acknowledgements for insert',
      table_name
    );
    EXECUTE format(
      'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated '
      'USING (public.has_current_legal_acknowledgements()) '
      'WITH CHECK (public.has_current_legal_acknowledgements())',
      'Require current legal acknowledgements for update',
      table_name
    );
    EXECUTE format(
      'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR DELETE TO authenticated '
      'USING (TRUE)',
      'Require current legal acknowledgements for delete',
      table_name
    );

    EXECUTE format(
      'DROP TRIGGER IF EXISTS %I ON public.%I',
      'require_current_legal_acknowledgements',
      table_name
    );
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE INSERT OR UPDATE OR DELETE ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION '
      'public.enforce_current_legal_ack_on_app_data()',
      'require_current_legal_acknowledgements',
      table_name
    );
  END LOOP;
END;
$$;

DROP POLICY IF EXISTS "Require current legal acknowledgement for memory photos"
ON storage.objects;
CREATE POLICY "Require current legal acknowledgement for memory photos"
ON storage.objects
AS RESTRICTIVE
FOR SELECT
TO authenticated
USING (
  bucket_id <> 'memory-photos'
  OR public.has_current_legal_acknowledgements()
);

DROP POLICY IF EXISTS "Require current legal acknowledgement for memory photo inserts"
ON storage.objects;
CREATE POLICY "Require current legal acknowledgement for memory photo inserts"
ON storage.objects
AS RESTRICTIVE
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id <> 'memory-photos'
  OR public.has_current_legal_acknowledgements()
);

DROP POLICY IF EXISTS "Require current legal acknowledgement for memory photo updates"
ON storage.objects;
CREATE POLICY "Require current legal acknowledgement for memory photo updates"
ON storage.objects
AS RESTRICTIVE
FOR UPDATE
TO authenticated
USING (
  bucket_id <> 'memory-photos'
  OR public.has_current_legal_acknowledgements()
)
WITH CHECK (
  bucket_id <> 'memory-photos'
  OR public.has_current_legal_acknowledgements()
);

DROP POLICY IF EXISTS "Require current legal acknowledgement for memory photo deletes"
ON storage.objects;
CREATE POLICY "Require current legal acknowledgement for memory photo deletes"
ON storage.objects
AS RESTRICTIVE
FOR DELETE
TO authenticated
USING (TRUE);

-- These SECURITY DEFINER RPCs bypass table RLS, so include the consent gate.
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
  IF NOT public.has_current_legal_acknowledgements() THEN
    RAISE EXCEPTION 'Current legal acknowledgements are required';
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
  WHERE public.has_current_legal_acknowledgements()
    AND auth.uid() IS NOT NULL
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
  WHERE public.has_current_legal_acknowledgements()
    AND auth.uid() IS NOT NULL
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
  WHERE public.has_current_legal_acknowledgements()
    AND auth.uid() IS NOT NULL
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
  SELECT public.has_current_legal_acknowledgements()
    AND auth.uid() IS NOT NULL
    AND EXISTS (
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

COMMIT;
