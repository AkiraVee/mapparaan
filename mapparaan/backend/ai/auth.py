"""Supabase access-token verification for authenticated AI requests."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request


class SupabaseAuthError(Exception):
    """Base error for Supabase token verification."""


class SupabaseAuthNotConfigured(SupabaseAuthError):
    """Raised when the backend has no Supabase verification configuration."""


class SupabaseInvalidToken(SupabaseAuthError):
    """Raised when Supabase rejects an access token."""


class SupabaseAuthUnavailable(SupabaseAuthError):
    """Raised when Supabase cannot verify a token."""


def verify_supabase_access_token(access_token: str) -> str:
    """Return the authenticated user ID only after Supabase validates the token."""
    supabase_url = os.environ.get("SUPABASE_URL", "").strip().rstrip("/")
    client_key = (
        os.environ.get("SUPABASE_PUBLISHABLE_KEY", "").strip()
        or os.environ.get("SUPABASE_ANON_KEY", "").strip()
    )
    if not supabase_url or not client_key:
        raise SupabaseAuthNotConfigured

    request = urllib.request.Request(
        f"{supabase_url}/auth/v1/user",
        headers={
            "apikey": client_key,
            "Authorization": f"Bearer {access_token}",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            user = json.loads(response.read())
    except urllib.error.HTTPError as error:
        if error.code in (401, 403):
            error.close()
            raise SupabaseInvalidToken from None
        error.close()
        raise SupabaseAuthUnavailable from None
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError):
        raise SupabaseAuthUnavailable from None

    if not isinstance(user, dict) or not isinstance(user.get("id"), str):
        raise SupabaseAuthUnavailable
    user_id = user["id"].strip()
    if not user_id:
        raise SupabaseAuthUnavailable
    return user_id
