import json
import os
import unittest
import urllib.error
from unittest.mock import patch

from backend.ai.auth import (
    SupabaseAuthNotConfigured,
    SupabaseAuthUnavailable,
    SupabaseInvalidToken,
    verify_supabase_access_token,
)


class SupabaseAccessTokenTests(unittest.TestCase):
    def test_verifies_token_with_supabase_user_endpoint(self):
        class FakeResponse:
            def read(self):
                return json.dumps({"id": "verified-user"}).encode()

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return False

        with patch.dict(
            os.environ,
            {
                "SUPABASE_URL": "https://project.supabase.co/",
                "SUPABASE_ANON_KEY": "public-client-key",
            },
            clear=True,
        ), patch("urllib.request.urlopen", return_value=FakeResponse()) as urlopen:
            self.assertEqual(verify_supabase_access_token("signed-user-token"), "verified-user")

        request = urlopen.call_args.args[0]
        self.assertEqual(request.full_url, "https://project.supabase.co/auth/v1/user")
        self.assertEqual(request.get_header("Authorization"), "Bearer signed-user-token")
        self.assertEqual(request.get_header("Apikey"), "public-client-key")

    def test_missing_server_configuration_fails_closed(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(SupabaseAuthNotConfigured):
                verify_supabase_access_token("signed-user-token")

    def test_rejected_token_is_invalid(self):
        error = urllib.error.HTTPError(
            "https://project.supabase.co/auth/v1/user",
            401,
            "Unauthorized",
            {},
            None,
        )
        with patch.dict(
            os.environ,
            {
                "SUPABASE_URL": "https://project.supabase.co",
                "SUPABASE_PUBLISHABLE_KEY": "public-client-key",
            },
            clear=True,
        ), patch("urllib.request.urlopen", side_effect=error):
            with self.assertRaises(SupabaseInvalidToken):
                verify_supabase_access_token("invalid-token")

    def test_supabase_network_failure_is_unavailable(self):
        with patch.dict(
            os.environ,
            {
                "SUPABASE_URL": "https://project.supabase.co",
                "SUPABASE_ANON_KEY": "public-client-key",
            },
            clear=True,
        ), patch("urllib.request.urlopen", side_effect=urllib.error.URLError("offline")):
            with self.assertRaises(SupabaseAuthUnavailable):
                verify_supabase_access_token("signed-user-token")


if __name__ == "__main__":
    unittest.main()
