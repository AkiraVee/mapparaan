BEGIN;

DROP POLICY IF EXISTS "Enforce own profile boundary" ON public.users;
CREATE POLICY "Enforce own profile boundary"
ON public.users
AS RESTRICTIVE
FOR ALL
TO public
USING ((SELECT auth.uid()) IS NOT NULL AND (SELECT auth.uid()) = id)
WITH CHECK ((SELECT auth.uid()) IS NOT NULL AND (SELECT auth.uid()) = id);

DROP POLICY IF EXISTS "Enforce own preferences boundary" ON public.user_preferences;
CREATE POLICY "Enforce own preferences boundary"
ON public.user_preferences
AS RESTRICTIVE
FOR ALL
TO public
USING ((SELECT auth.uid()) IS NOT NULL AND (SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) IS NOT NULL AND (SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Enforce own saved places boundary" ON public.saved_places;
CREATE POLICY "Enforce own saved places boundary"
ON public.saved_places
AS RESTRICTIVE
FOR ALL
TO public
USING ((SELECT auth.uid()) IS NOT NULL AND (SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) IS NOT NULL AND (SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Enforce own memory pins boundary" ON public.memory_pins;
CREATE POLICY "Enforce own memory pins boundary"
ON public.memory_pins
AS RESTRICTIVE
FOR ALL
TO public
USING ((SELECT auth.uid()) IS NOT NULL AND (SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) IS NOT NULL AND (SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Enforce own trip history boundary" ON public.trip_history;
CREATE POLICY "Enforce own trip history boundary"
ON public.trip_history
AS RESTRICTIVE
FOR ALL
TO public
USING ((SELECT auth.uid()) IS NOT NULL AND (SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) IS NOT NULL AND (SELECT auth.uid()) = user_id);

COMMIT;
