from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence


def _load_backend_env() -> None:
    """Load variables from the repository .env when the process environment is missing them."""
    project_root = Path(__file__).resolve().parents[2]
    candidates = [
        Path.cwd(),
        project_root,
        project_root / "backend",
    ]
    seen: set[Path] = set()
    for directory in candidates:
        env_path = directory / ".env"
        if env_path in seen or not env_path.is_file():
            continue
        seen.add(env_path)
        for raw_line in env_path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            os.environ.setdefault(key, value)


_load_backend_env()


class GeminiProviderError(RuntimeError):
    def __init__(self, category: str, message: str, *, retryable: bool = False):
        super().__init__(message)
        self.category = category
        self.retryable = retryable


class GeminiProvider:
    """Server-side Gemini wrapper for the Google AI Studio free tier."""

    DEFAULT_MODEL = "gemini-flash-lite-latest"
    BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"

    def __init__(
        self,
        api_key: Optional[str] = None,
        model: Optional[str] = None,
        timeout: int = 20,
        max_retries: int = 2,
    ):
        self.api_key = (api_key or os.environ.get("GEMINI_API_KEY") or "").strip()
        self.model = (model or os.environ.get("GEMINI_MODEL") or self.DEFAULT_MODEL).strip() or self.DEFAULT_MODEL
        self.timeout = timeout
        self.max_retries = max(0, min(max_retries, 2))

    @property
    def available(self) -> bool:
        return bool(self.api_key)

    def _build_url(self) -> str:
        return f"{self.BASE_URL}/{self.model}:generateContent?key={self.api_key}"

    def _normalize_history_item(self, item: Dict[str, Any]) -> Dict[str, Any]:
        role = str(item.get("role") or "user").strip().lower()
        if role == "assistant":
            role = "model"
        elif role in {"tool", "function"}:
            role = "user"
        elif role not in {"user", "model"}:
            role = "user"

        parts: List[Dict[str, Any]] = []
        text = item.get("text")
        if isinstance(text, str) and text.strip():
            parts.append({"text": text})

        function_call = item.get("function_call") or item.get("functionCall")
        if function_call:
            parts.append({"functionCall": function_call})

        function_response = item.get("function_response") or item.get("functionResponse")
        if function_response:
            parts.append({"functionResponse": function_response})

        return {"role": role, "parts": parts}

    def build_contents(
        self,
        prompt: str,
        *,
        history: Optional[Sequence[Dict[str, Any]]] = None,
        tool_calls: Optional[Sequence[Dict[str, Any]]] = None,
        tool_results: Optional[Sequence[Dict[str, Any]]] = None,
    ) -> List[Dict[str, Any]]:
        contents: List[Dict[str, Any]] = []
        for item in history or []:
            if isinstance(item, dict) and item.get("role"):
                contents.append(self._normalize_history_item(item))

        if prompt:
            contents.append({"role": "user", "parts": [{"text": prompt}]})

        if tool_calls:
            for call in tool_calls:
                if isinstance(call, dict):
                    contents.append({"role": "model", "parts": [{"functionCall": call}]})

        if tool_results:
            for result in tool_results:
                if isinstance(result, dict):
                    contents.append({
                        "role": "user",
                        "parts": [{
                            "functionResponse": {
                                "name": result.get("name"),
                                "response": {"content": result.get("content") or result.get("result")},
                            }
                        }],
                    })

        return contents

    def build_payload(
        self,
        prompt: str,
        *,
        system_prompt: Optional[str] = None,
        history: Optional[Sequence[Dict[str, Any]]] = None,
        tools: Optional[List[Dict[str, Any]]] = None,
        tool_calls: Optional[Sequence[Dict[str, Any]]] = None,
        tool_results: Optional[Sequence[Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        payload: Dict[str, Any] = {
            "contents": self.build_contents(prompt, history=history, tool_calls=tool_calls, tool_results=tool_results),
            "generationConfig": {
                "temperature": 0.2,
                "maxOutputTokens": 512,
            },
        }
        if system_prompt:
            payload["system_instruction"] = {"parts": [{"text": system_prompt}]}
        if tools:
            payload["tools"] = [{"functionDeclarations": tools}]
            payload["toolConfig"] = {"functionCallingConfig": {"mode": "AUTO"}}
        return payload

    def _parse_response(self, data: Dict[str, Any]) -> Dict[str, Any]:
        if not isinstance(data, dict):
            raise GeminiProviderError(
                "provider_invalid_response",
                "Gemini returned an invalid response. Please try again.",
            )
        candidates = data.get("candidates") or []
        if not isinstance(candidates, list):
            raise GeminiProviderError(
                "provider_invalid_response",
                "Gemini returned an invalid response. Please try again.",
            )
        candidate = candidates[0] if candidates else {}
        if not isinstance(candidate, dict):
            raise GeminiProviderError(
                "provider_invalid_response",
                "Gemini returned an invalid response. Please try again.",
            )
        content = candidate.get("content") or {}
        if not isinstance(content, dict):
            raise GeminiProviderError(
                "provider_invalid_response",
                "Gemini returned an invalid response. Please try again.",
            )
        parts = content.get("parts") or []
        if not isinstance(parts, list):
            raise GeminiProviderError(
                "provider_invalid_response",
                "Gemini returned an invalid response. Please try again.",
            )
        text = "".join(part.get("text", "") for part in parts if isinstance(part, dict) and isinstance(part.get("text"), str))
        function_calls: List[Dict[str, Any]] = []
        for part in parts:
            if not isinstance(part, dict):
                continue
            call = part.get("functionCall") or part.get("function_call")
            if call:
                if (
                    not isinstance(call, dict)
                    or not isinstance(call.get("name"), str)
                    or not isinstance(call.get("args") or {}, dict)
                ):
                    raise GeminiProviderError(
                        "provider_invalid_response",
                        "Gemini returned an invalid tool request. Please try again.",
                    )
                function_calls.append({
                    "name": call.get("name"),
                    "args": call.get("args") or {},
                })
        if not candidates or (not text.strip() and not function_calls):
            raise GeminiProviderError(
                "provider_empty_response",
                "Gemini did not return an answer. Please try again.",
            )
        return {
            "provider": "gemini",
            "model": self.model,
            "status": "ok",
            "text": text,
            "function_calls": function_calls,
            "raw": data,
        }

    def generate(
        self,
        prompt: str,
        *,
        system_prompt: Optional[str] = None,
        history: Optional[Sequence[Dict[str, Any]]] = None,
        tools: Optional[List[Dict[str, Any]]] = None,
        tool_calls: Optional[Sequence[Dict[str, Any]]] = None,
        tool_results: Optional[Sequence[Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        if not self.available:
            raise GeminiProviderError(
                "provider_not_configured",
                "MapParaan AI is not configured on the backend right now.",
            )

        payload = self.build_payload(
            prompt,
            system_prompt=system_prompt,
            history=history,
            tools=tools,
            tool_calls=tool_calls,
            tool_results=tool_results,
        )
        request = urllib.request.Request(
            self._build_url(),
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        body = None
        for attempt in range(self.max_retries + 1):
            try:
                with urllib.request.urlopen(request, timeout=self.timeout) as response:
                    body = response.read().decode("utf-8")
                break
            except urllib.error.HTTPError as exc:
                status_code = exc.code
                exc.close()
                if 500 <= status_code < 600 and attempt < self.max_retries:
                    time.sleep(0.25 * (2 ** attempt))
                    continue
                if status_code == 429:
                    raise GeminiProviderError(
                        "provider_quota_exceeded",
                        "Gemini is temporarily rate-limited or its provider quota is exhausted. Please try again later.",
                        retryable=False,
                    ) from None
                if status_code == 404:
                    raise GeminiProviderError(
                        "provider_model_unavailable",
                        "The configured AI model is unavailable. Please contact support.",
                    ) from None
                if status_code in {400, 401, 403}:
                    raise GeminiProviderError(
                        "provider_configuration_error",
                        "MapParaan AI could not use its configured provider. Please try again later.",
                    ) from None
                if 500 <= status_code < 600:
                    raise GeminiProviderError(
                        "provider_unavailable",
                        "Gemini is temporarily unavailable. Please try again later.",
                        retryable=True,
                    ) from None
                raise GeminiProviderError(
                    "provider_error",
                    "Gemini could not process this request. Please try again later.",
                ) from None
            except (urllib.error.URLError, TimeoutError, OSError):
                if attempt < self.max_retries:
                    time.sleep(0.25 * (2 ** attempt))
                    continue
                raise GeminiProviderError(
                    "provider_unavailable",
                    "Gemini is temporarily unavailable or timed out. Please try again.",
                    retryable=True,
                ) from None

        try:
            if body is None:
                raise GeminiProviderError(
                    "provider_unavailable",
                    "Gemini is temporarily unavailable. Please try again later.",
                    retryable=True,
                )
            data = json.loads(body)
        except (json.JSONDecodeError, UnicodeDecodeError):
            raise GeminiProviderError(
                "provider_invalid_response",
                "Gemini returned an invalid response. Please try again.",
            ) from None

        return self._parse_response(data)

    def build_request_body(
        self,
        prompt: str,
        *,
        system_prompt: Optional[str] = None,
        history: Optional[Sequence[Dict[str, Any]]] = None,
        tools: Optional[List[Dict[str, Any]]] = None,
        tool_calls: Optional[Sequence[Dict[str, Any]]] = None,
        tool_results: Optional[Sequence[Dict[str, Any]]] = None,
    ) -> str:
        return json.dumps(
            self.build_payload(
                prompt,
                system_prompt=system_prompt,
                history=history,
                tools=tools,
                tool_calls=tool_calls,
                tool_results=tool_results,
            ),
            ensure_ascii=False,
        )
