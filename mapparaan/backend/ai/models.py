from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, Optional


@dataclass(slots=True)
class AiChatRequest:
    user_id: str
    message: str
    session_id: Optional[str] = None
    conversation_id: Optional[str] = None
    model: str = "gemini-flash-lite-latest"
    metadata: Dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_payload(cls, payload: Dict[str, Any]) -> "AiChatRequest":
        if not isinstance(payload, dict):
            raise ValueError("AI request payload must be a JSON object.")

        user_id = str(payload.get("user_id") or payload.get("user") or "").strip()
        message = str(payload.get("message") or payload.get("prompt") or "").strip()
        if not user_id:
            raise ValueError("A valid authenticated user_id is required.")
        if not message:
            raise ValueError("AI message content cannot be empty.")

        return cls(
            user_id=user_id,
            message=message,
            session_id=str(payload.get("session_id") or "").strip() or None,
            conversation_id=str(payload.get("conversation_id") or "").strip() or None,
            model=str(payload.get("model") or "gemini-flash-lite-latest").strip() or "gemini-flash-lite-latest",
            metadata={
                k: v
                for k, v in (payload.get("metadata") or {}).items()
                if isinstance(v, (dict, list, str, int, float, bool))
            },
        )


@dataclass(slots=True)
class AiUsageSnapshot:
    user_id: str
    user_day_used: int
    user_minute_used: int
    global_day_used: int
    user_day_limit: int = 10
    user_minute_limit: int = 5
    global_day_limit: int = 100
    reset_at: Optional[str] = None
    minute_reset_at: Optional[str] = None


@dataclass(slots=True)
class AiQuotaDecision:
    allowed: bool
    user_id: str
    reason: Optional[str] = None
    message: str = ""
    usage: Optional[AiUsageSnapshot] = None


AI_TOOL_SPECS = [
    {
        "name": "plan_route",
        "description": "Plan a route within the supported MapParaan geography using the existing transit planner.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "origin": {"type": "STRING"},
                "destination": {"type": "STRING"},
                "passenger_type": {"type": "STRING", "enum": ["general", "student", "senior", "pwd"]},
                "when": {"type": "STRING"},
            },
            "required": ["origin", "destination"],
        },
    },
    {
        "name": "search_nearby_places",
        "description": "Search GTFS stops or nearby supported places around the supplied coordinates.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "query": {"type": "STRING"},
                "latitude": {"type": "NUMBER"},
                "longitude": {"type": "NUMBER"},
                "radius_meters": {"type": "NUMBER"},
            },
            "required": ["query"],
        },
    },
    {
        "name": "get_fare_estimate",
        "description": "Estimate one-leg fare information using the existing MapParaan fare configuration.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "origin": {"type": "STRING"},
                "destination": {"type": "STRING"},
                "mode": {"type": "STRING"},
            },
            "required": ["origin", "destination"],
        },
    },
    {
        "name": "get_route_details",
        "description": "Return structured route details for an already planned trip using the existing planner output.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "origin": {"type": "STRING"},
                "destination": {"type": "STRING"},
                "passenger_type": {"type": "STRING", "enum": ["general", "student", "senior", "pwd"]},
                "when": {"type": "STRING"},
            },
            "required": ["origin", "destination"],
        },
    },
    {
        "name": "get_transport_schedule",
        "description": "Look up schedule context for a route or stop from the GTFS-backed planner data.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "route_name": {"type": "STRING"},
                "stop_name": {"type": "STRING"},
                "latitude": {"type": "NUMBER"},
                "longitude": {"type": "NUMBER"},
            },
        },
    },
]
