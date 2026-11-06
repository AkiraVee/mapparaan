-- Version the privacy notice to disclose AI-provider and backend context processing.
BEGIN;

DO $$
BEGIN
  IF to_regclass('public.legal_document_versions') IS NULL THEN
    RAISE EXCEPTION
      'Apply the legal acknowledgement migration before updating the privacy notice';
  END IF;
END
$$;

UPDATE public.legal_document_versions
SET is_current = FALSE
WHERE document_type = 'privacy_notice'
  AND is_current;

INSERT INTO public.legal_document_versions (
  document_type, version, is_current
) VALUES (
  'privacy_notice', '2026-11-07-v2', TRUE
)
ON CONFLICT (document_type, version)
DO UPDATE SET is_current = EXCLUDED.is_current;

COMMIT;
