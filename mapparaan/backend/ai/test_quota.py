import os
import tempfile
import unittest
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from backend.ai.quota import AiQuotaService


class AiQuotaServiceTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp(prefix="mapparaan-ai-")
        self.db_path = os.path.join(self.temp_dir, "quota.sqlite3")
        self.service = AiQuotaService(db_path=self.db_path)

    def test_user_day_limit_is_enforced(self):
        base = datetime(2025, 1, 2, 8, 0, tzinfo=ZoneInfo("Asia/Manila"))
        for index in range(11):
            self.service._now_manila = lambda idx=index: base + timedelta(minutes=idx * 2)
            decision = self.service.allow_request("user-1", session_id=f"s-{index}")
            if index < 10:
                self.assertTrue(decision.allowed)
            else:
                self.assertFalse(decision.allowed)
                self.assertEqual(decision.reason, "user_daily_limit")

    def test_user_minute_limit_is_enforced(self):
        base = datetime(2025, 1, 2, 8, 0, tzinfo=ZoneInfo("Asia/Manila"))
        for index in range(6):
            self.service._now_manila = lambda idx=index: base + timedelta(seconds=idx)
            decision = self.service.allow_request("user-2", session_id=f"m-{index}")
            if index < 5:
                self.assertTrue(decision.allowed)
            else:
                self.assertFalse(decision.allowed)
                self.assertEqual(decision.reason, "user_minute_limit")

    def test_global_day_limit_is_enforced(self):
        base = datetime(2025, 1, 2, 8, 0, tzinfo=ZoneInfo("Asia/Manila"))
        for index in range(101):
            self.service._now_manila = lambda idx=index: base + timedelta(seconds=idx)
            decision = self.service.allow_request(f"user-{index}", session_id=f"g-{index}")
            if index < 100:
                self.assertTrue(decision.allowed)
            else:
                self.assertFalse(decision.allowed)
                self.assertEqual(decision.reason, "global_daily_limit")

    def test_manila_day_reset_uses_manila_timezone(self):
        manila = ZoneInfo("Asia/Manila")
        fake_now = datetime(2025, 1, 2, 0, 0, 0, tzinfo=manila)
        self.service._now_manila = lambda: fake_now

        decision = self.service.allow_request("user-3", session_id="day-reset")
        self.assertTrue(decision.allowed)

        self.service._now_manila = lambda: fake_now + timedelta(days=1)
        next_decision = self.service.allow_request("user-3", session_id="day-reset-next")
        self.assertTrue(next_decision.allowed)


if __name__ == "__main__":
    unittest.main()
