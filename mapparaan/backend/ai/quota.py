from __future__ import annotations

import os
import sqlite3
import threading
from datetime import datetime, timedelta
from typing import Optional
from zoneinfo import ZoneInfo

from .models import AiQuotaDecision, AiUsageSnapshot

MANILA_TZ = ZoneInfo("Asia/Manila")


class AiQuotaError(RuntimeError):
    def __init__(self, decision: AiQuotaDecision):
        super().__init__(decision.message)
        self.decision = decision


class AiQuotaService:
    """Server-side quota enforcement for authenticated AI requests."""

    USER_DAILY_LIMIT = 10
    USER_MINUTE_LIMIT = 5
    GLOBAL_DAILY_LIMIT = 100

    def __init__(self, db_path: Optional[str] = None):
        self.db_path = db_path or os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "data", "ai_usage.sqlite3")
        )
        self._lock = threading.RLock()
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=30)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA foreign_keys=ON")
        return conn

    def _initialize(self) -> None:
        conn = self._connect()
        try:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS ai_usage_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id TEXT NOT NULL,
                    session_id TEXT,
                    conversation_id TEXT,
                    model TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    created_day TEXT NOT NULL,
                    minute_bucket TEXT NOT NULL
                )
                """
            )
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_ai_usage_user_day ON ai_usage_events (user_id, created_day)"
            )
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_ai_usage_user_minute ON ai_usage_events (user_id, minute_bucket)"
            )
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_ai_usage_day ON ai_usage_events (created_day)"
            )
            conn.commit()
        finally:
            conn.close()

    def _now_manila(self) -> datetime:
        return datetime.now(MANILA_TZ)

    def _user_day(self, now: datetime) -> str:
        return now.astimezone(MANILA_TZ).strftime("%Y-%m-%d")

    def _base_usage(self, user_id: str, now: datetime) -> AiUsageSnapshot:
        day_key = self._user_day(now)
        minute_start = (now - timedelta(minutes=1)).isoformat()
        conn = self._connect()
        try:
            user_day_used = int(
                conn.execute(
                    "SELECT COUNT(*) FROM ai_usage_events WHERE user_id = ? AND created_day = ?",
                    (user_id, day_key),
                ).fetchone()[0]
            )
            user_minute_used = int(
                conn.execute(
                    "SELECT COUNT(*) FROM ai_usage_events WHERE user_id = ? AND created_at >= ?",
                    (user_id, minute_start),
                ).fetchone()[0]
            )
            global_day_used = int(
                conn.execute(
                    "SELECT COUNT(*) FROM ai_usage_events WHERE created_day = ?",
                    (day_key,),
                ).fetchone()[0]
            )
        finally:
            conn.close()
        return AiUsageSnapshot(
            user_id=user_id,
            user_day_used=user_day_used,
            user_minute_used=user_minute_used,
            global_day_used=global_day_used,
            user_day_limit=self.USER_DAILY_LIMIT,
            user_minute_limit=self.USER_MINUTE_LIMIT,
            global_day_limit=self.GLOBAL_DAILY_LIMIT,
            reset_at=(datetime.combine(now.date(), datetime.min.time(), tzinfo=MANILA_TZ) + timedelta(days=1)).isoformat(),
            minute_reset_at=(now + timedelta(minutes=1)).isoformat(),
        )

    def allow_request(
        self,
        user_id: str,
        *,
        session_id: Optional[str] = None,
        conversation_id: Optional[str] = None,
        model: str = "gemini-flash-lite-latest",
    ) -> AiQuotaDecision:
        if not user_id or not str(user_id).strip():
            raise ValueError("A valid authenticated user_id is required for AI quota enforcement.")

        user_id = str(user_id).strip()
        now = self._now_manila()
        day_key = self._user_day(now)
        minute_bucket = now.strftime("%Y-%m-%dT%H:%M")

        with self._lock:
            conn = self._connect()
            try:
                conn.execute("BEGIN IMMEDIATE")
                user_day_used = int(
                    conn.execute(
                        "SELECT COUNT(*) FROM ai_usage_events WHERE user_id = ? AND created_day = ?",
                        (user_id, day_key),
                    ).fetchone()[0]
                )
                user_minute_used = int(
                    conn.execute(
                        "SELECT COUNT(*) FROM ai_usage_events WHERE user_id = ? AND created_at >= ?",
                        (user_id, (now - timedelta(minutes=1)).isoformat()),
                    ).fetchone()[0]
                )
                global_day_used = int(
                    conn.execute(
                        "SELECT COUNT(*) FROM ai_usage_events WHERE created_day = ?",
                        (day_key,),
                    ).fetchone()[0]
                )

                if user_day_used >= self.USER_DAILY_LIMIT:
                    usage = AiUsageSnapshot(
                        user_id=user_id,
                        user_day_used=user_day_used,
                        user_minute_used=user_minute_used,
                        global_day_used=global_day_used,
                        user_day_limit=self.USER_DAILY_LIMIT,
                        user_minute_limit=self.USER_MINUTE_LIMIT,
                        global_day_limit=self.GLOBAL_DAILY_LIMIT,
                        reset_at=(datetime.combine(now.date(), datetime.min.time(), tzinfo=MANILA_TZ) + timedelta(days=1)).isoformat(),
                        minute_reset_at=(now + timedelta(minutes=1)).isoformat(),
                    )
                    decision = AiQuotaDecision(
                        allowed=False,
                        user_id=user_id,
                        reason="user_daily_limit",
                        message=(
                            "You have reached the daily AI usage limit for this user account. "
                            f"Limit: {self.USER_DAILY_LIMIT} messages per day."
                        ),
                        usage=usage,
                    )
                    conn.close()
                    return decision

                if user_minute_used >= self.USER_MINUTE_LIMIT:
                    usage = AiUsageSnapshot(
                        user_id=user_id,
                        user_day_used=user_day_used,
                        user_minute_used=user_minute_used,
                        global_day_used=global_day_used,
                        user_day_limit=self.USER_DAILY_LIMIT,
                        user_minute_limit=self.USER_MINUTE_LIMIT,
                        global_day_limit=self.GLOBAL_DAILY_LIMIT,
                        reset_at=(datetime.combine(now.date(), datetime.min.time(), tzinfo=MANILA_TZ) + timedelta(days=1)).isoformat(),
                        minute_reset_at=(now + timedelta(minutes=1)).isoformat(),
                    )
                    decision = AiQuotaDecision(
                        allowed=False,
                        user_id=user_id,
                        reason="user_minute_limit",
                        message=(
                            "You have reached the per-minute AI usage limit. "
                            f"Limit: {self.USER_MINUTE_LIMIT} messages in a rolling minute."
                        ),
                        usage=usage,
                    )
                    conn.close()
                    return decision

                if global_day_used >= self.GLOBAL_DAILY_LIMIT:
                    usage = AiUsageSnapshot(
                        user_id=user_id,
                        user_day_used=user_day_used,
                        user_minute_used=user_minute_used,
                        global_day_used=global_day_used,
                        user_day_limit=self.USER_DAILY_LIMIT,
                        user_minute_limit=self.USER_MINUTE_LIMIT,
                        global_day_limit=self.GLOBAL_DAILY_LIMIT,
                        reset_at=(datetime.combine(now.date(), datetime.min.time(), tzinfo=MANILA_TZ) + timedelta(days=1)).isoformat(),
                        minute_reset_at=(now + timedelta(minutes=1)).isoformat(),
                    )
                    decision = AiQuotaDecision(
                        allowed=False,
                        user_id=user_id,
                        reason="global_daily_limit",
                        message=(
                            "The global AI usage cap has been reached for the current Manila day. "
                            f"Limit: {self.GLOBAL_DAILY_LIMIT} messages per day."
                        ),
                        usage=usage,
                    )
                    conn.close()
                    return decision

                conn.execute(
                    """
                    INSERT INTO ai_usage_events (
                        user_id,
                        session_id,
                        conversation_id,
                        model,
                        created_at,
                        created_day,
                        minute_bucket
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        user_id,
                        session_id,
                        conversation_id,
                        model,
                        now.isoformat(),
                        day_key,
                        minute_bucket,
                    ),
                )
                conn.commit()

                usage = AiUsageSnapshot(
                    user_id=user_id,
                    user_day_used=user_day_used + 1,
                    user_minute_used=user_minute_used + 1,
                    global_day_used=global_day_used + 1,
                    user_day_limit=self.USER_DAILY_LIMIT,
                    user_minute_limit=self.USER_MINUTE_LIMIT,
                    global_day_limit=self.GLOBAL_DAILY_LIMIT,
                    reset_at=(datetime.combine(now.date(), datetime.min.time(), tzinfo=MANILA_TZ) + timedelta(days=1)).isoformat(),
                    minute_reset_at=(now + timedelta(minutes=1)).isoformat(),
                )
                result = AiQuotaDecision(
                    allowed=True,
                    user_id=user_id,
                    message="AI request accepted and quota recorded.",
                    usage=usage,
                )
                return result
            finally:
                conn.close()

    def get_usage_snapshot(self, user_id: str) -> AiUsageSnapshot:
        if not user_id:
            raise ValueError("A valid user_id is required.")
        now = self._now_manila()
        return self._base_usage(str(user_id).strip(), now)
