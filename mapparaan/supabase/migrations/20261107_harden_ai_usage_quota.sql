-- Keep quota events read-only to clients; trusted backend operations own writes.
BEGIN;

REVOKE ALL ON TABLE public.ai_usage_events FROM anon, authenticated;
GRANT SELECT ON TABLE public.ai_usage_events TO authenticated;

DROP POLICY IF EXISTS "Users can insert own AI usage"
  ON public.ai_usage_events;
DROP POLICY IF EXISTS "Users cannot modify another user's AI usage"
  ON public.ai_usage_events;
DROP POLICY IF EXISTS "Users cannot delete another user's AI usage"
  ON public.ai_usage_events;

COMMIT;
