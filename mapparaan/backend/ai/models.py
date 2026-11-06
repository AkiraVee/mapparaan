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
    request_id: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_payload(cls, payload: Dict[str, Any]) -> "AiChatRequest":
        if not isinstance(payload, dict):
            raise ValueError("AI request payload must be a JSON object.")

        allowed_fields = {
            "user_id",
            "user",
            "message",
            "prompt",
            "session_id",
            "conversation_id",
            "model",
            "metadata",
        }
        if set(payload) - allowed_fields:
            raise ValueError("AI request contains unsupported fields.")

        raw_user_id = payload.get("user_id") or payload.get("user") or ""
        raw_message = payload.get("message") or payload.get("prompt") or ""
        if not isinstance(raw_user_id, str) or not isinstance(raw_message, str):
            raise ValueError("AI user and message fields must be text.")
        user_id = raw_user_id.strip()
        message = raw_message.strip()
        if not user_id:
            raise ValueError("A valid authenticated user_id is required.")
        if not message:
            raise ValueError("AI message content cannot be empty.")
        if len(message) > 4000:
            raise ValueError("AI message content must be 4000 characters or fewer.")

        session_id = payload.get("session_id")
        conversation_id = payload.get("conversation_id")
        if session_id is not None and (
            not isinstance(session_id, str) or len(session_id) > 128
        ):
            raise ValueError("session_id must be text of at most 128 characters.")
        if conversation_id is not None and (
            not isinstance(conversation_id, str) or len(conversation_id) > 128
        ):
            raise ValueError("conversation_id must be text of at most 128 characters.")
        metadata = payload.get("metadata") or {}
        if not isinstance(metadata, dict):
            raise ValueError("metadata must be a JSON object.")

        return cls(
            user_id=user_id,
            message=message,
            session_id=session_id.strip() or None if session_id else None,
            conversation_id=conversation_id.strip() or None if conversation_id else None,
            metadata={
                k: v
                for k, v in metadata.items()
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
                "origin": {"type": "STRING", "description": "Starting place name or latitude,longitude."},
                "destination": {"type": "STRING", "description": "Destination place name or latitude,longitude."},
                "passenger_type": {"type": "STRING", "enum": ["general", "student", "senior", "pwd"]},
                "preferred_mode": {"type": "STRING", "enum": ["jeepney", "bus", "lrt1", "lrt2"]},
                "when": {"type": "STRING", "description": "Optional ISO-8601 departure time; Manila local time if no timezone is given."},
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
                "location": {"type": "STRING", "description": "Named location or latitude,longitude to search around."},
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
                "mode": {"type": "STRING", "enum": ["jeepney", "bus", "lrt1", "lrt2"]},
                "passenger_type": {"type": "STRING", "enum": ["general", "student", "senior", "pwd"]},
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
                "when": {"type": "STRING", "description": "Optional ISO-8601 query time in Manila local time unless timezone is supplied."},
                "mode": {"type": "STRING", "enum": ["jeepney", "bus", "lrt1", "lrt2"]},
            },
        },
    },
]
