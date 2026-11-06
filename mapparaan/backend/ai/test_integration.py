import json
import os
import tempfile
import unittest
import urllib.error
from types import SimpleNamespace
from unittest.mock import patch

from backend.ai.models import AiChatRequest
from backend.ai.orchestrator import MapParaanAiService
from backend.ai.provider import GeminiProvider
from backend.ai.quota import AiQuotaService


class FakeProvider:
    def __init__(self, responses=None):
        self.responses = list(responses or [])
        self.calls = []
        self.available = True

    def generate(self, prompt, **kwargs):
        self.calls.append({"prompt": prompt, "kwargs": kwargs})
        if not self.responses:
            return {"text": "Assistant reply", "function_calls": []}
        result = self.responses.pop(0)
        return result


class FakePlanner:
    trips = []
    stop_name = []
    stop_lat = []
    stop_lon = []

    def plan(self, *args, **kwargs):
        return [{
            "modes": ["jeepney", "lrt1"],
            "fare": 25,
            "fare_max": 35,
            "fare_discounted": 20,
            "fare_discounted_max": 28,
            "minutes": 35,
            "transfers": 1,
        }]


class GeminiProviderTests(unittest.TestCase):
    def test_default_model_configuration(self):
        os.environ.pop("GEMINI_MODEL", None)
        provider = GeminiProvider(api_key="demo-key")
        self.assertTrue(provider.available)
        self.assertEqual(provider.model, "gemini-flash-lite-latest")

    def test_function_calling_payload_enables_tool_config(self):
        provider = GeminiProvider(api_key="demo-key")
        payload = provider.build_payload(
            "How do I get there?",
            tools=[{"name": "plan_route", "description": "Plan a route", "parameters": {"type": "object", "properties": {}}}],
        )
        self.assertIn("toolConfig", payload)
        self.assertEqual(payload["toolConfig"]["functionCallingConfig"]["mode"], "AUTO")

    @patch("urllib.request.urlopen")
    def test_generate_success_with_mocked_provider_response(self, mock_urlopen):
        class FakeResponse:
            def read(self):
                return json.dumps({
                    "candidates": [{
                        "content": {"parts": [{"text": "Hello there"}]}
                    }]
                }).encode("utf-8")
            def __enter__(self):
                return self
            def __exit__(self, exc_type, exc, tb):
                return False

        mock_urlopen.return_value = FakeResponse()
        provider = GeminiProvider(api_key="demo-key")
        result = provider.generate("Plan my route")
        self.assertEqual(result["text"], "Hello there")
        self.assertEqual(result["provider"], "gemini")

    @patch("urllib.request.urlopen", side_effect=urllib.error.URLError("boom"))
    def test_provider_errors_are_wrapped(self, _):
        provider = GeminiProvider(api_key="demo-key")
        with self.assertRaises(RuntimeError):
            provider.generate("Test")


class MapParaanAiServiceTests(unittest.TestCase):
    def setUp(self):
        temp_dir = tempfile.mkdtemp(prefix="mapparaan-ai-")
        self.db_path = os.path.join(temp_dir, "quota.sqlite3")

    def test_function_call_flow_executes_tool(self):
        fake_provider = FakeProvider([
            {
                "text": "",
                "function_calls": [{
                    "name": "plan_route",
                    "args": {
                        "origin": "14.5995,120.9842",
                        "destination": "14.5623,121.0198",
                        "passenger_type": "general",
                    },
                }],
            },
            {"text": "I planned a route for you.", "function_calls": []},
        ])
        service = MapParaanAiService(
            provider=fake_provider,
            quota_service=AiQuotaService(db_path=self.db_path),
            planner=FakePlanner(),
        )
        request = AiChatRequest(user_id="user-1", message="Plan my route to the office.")
        planner_module = SimpleNamespace(
            _AREA=[[]],
            in_service_area=lambda point: True,
            to_manila=lambda: None,
        )
        with patch.object(service, "_planner_module", return_value=planner_module):
            result = service.handle_request(request)
        self.assertEqual(result["status"], "ok")
        self.assertIn("message", result)

    def test_missing_origin_and_destination_is_rejected(self):
        service = MapParaanAiService(
            provider=FakeProvider(),
            quota_service=AiQuotaService(db_path=self.db_path),
        )
        result = service._plan_route({"origin": None, "destination": None})
        self.assertIn("error", result)

    def test_prompt_accepts_taglish_input(self):
        request = AiChatRequest.from_payload({
            "user_id": "user-2",
            "message": "Punta ka sa Makati, may route ba?",
            "metadata": {"history": [{"role": "user", "text": "Hi"}]},
        })
        self.assertIn("Punta", request.message)
        self.assertEqual(request.user_id, "user-2")


if __name__ == "__main__":
    unittest.main()
