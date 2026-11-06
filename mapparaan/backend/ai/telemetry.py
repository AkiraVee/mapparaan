from __future__ import annotations

import hashlib
import json
import logging
from datetime import datetime, timezone
from typing import Optional


_LOGGER = logging.getLogger("mapparaan.ai")


def log_ai_event(
    *,
    request_id: str,
    user_id: Optional[str],
    error_category: str,
    http_status: int,
    processing_duration_ms: float,
    failed_tool_name: Optional[str] = None,
) -> None:
    user_hash = (
        hashlib.blake2b(user_id.encode("utf-8"), digest_size=8).hexdigest()
        if user_id
        else None
    )
    event = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "request_id": request_id,
        "user_hash": user_hash,
        "error_category": error_category,
        "failed_tool_name": failed_tool_name,
        "http_status": http_status,
        "processing_duration_ms": round(processing_duration_ms, 2),
    }
    message = json.dumps(event, separators=(",", ":"), ensure_ascii=True)
    if http_status < 400 and error_category == "success":
        _LOGGER.info(message)
    else:
        _LOGGER.warning(message)
