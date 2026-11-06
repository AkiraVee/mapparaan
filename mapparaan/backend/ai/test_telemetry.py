import json
import unittest

from backend.ai.telemetry import log_ai_event


class AiTelemetryTests(unittest.TestCase):
    def test_event_is_structured_and_does_not_log_raw_user_or_token(self):
        user_id = "private-user-id"
        token = "private-access-token"
        with self.assertLogs("mapparaan.ai", level="WARNING") as captured:
            log_ai_event(
                request_id="request-123",
                user_id=user_id,
                error_category="invalid_bearer_token",
                http_status=401,
                processing_duration_ms=3.2,
            )

        payload = json.loads(captured.records[0].getMessage())
        self.assertEqual(payload["request_id"], "request-123")
        self.assertEqual(payload["error_category"], "invalid_bearer_token")
        self.assertEqual(payload["http_status"], 401)
        self.assertIsNotNone(payload["user_hash"])
        self.assertNotIn(user_id, captured.output[0])
        self.assertNotIn(token, captured.output[0])


if __name__ == "__main__":
    unittest.main()
