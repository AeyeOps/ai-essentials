"""WebSocket protocol message types for STT service."""

import json
from typing import Literal, Union

from pydantic import BaseModel, Field


# Client -> Server messages


class ConfigMessage(BaseModel):
    """Initial configuration from client."""

    type: Literal["config"] = "config"
    sample_rate: int = Field(default=16000)
    language: str = Field(default="en")


class EndMessage(BaseModel):
    """Signal end of audio stream."""

    type: Literal["end"] = "end"


class KeepAliveMessage(BaseModel):
    """Keep connection alive."""

    type: Literal["keepalive"] = "keepalive"


ClientMessage = Union[ConfigMessage, EndMessage, KeepAliveMessage]


# Server -> Client messages


class ReadyMessage(BaseModel):
    """Server is ready to receive audio."""

    type: Literal["ready"] = "ready"
    session_id: str


class PartialMessage(BaseModel):
    """Partial (interim) transcription result."""

    type: Literal["partial"] = "partial"
    text: str


class FinalMessage(BaseModel):
    """Final transcription result."""

    type: Literal["final"] = "final"
    text: str
    confidence: float = Field(default=1.0, ge=0.0, le=1.0)


class ErrorMessage(BaseModel):
    """Error response."""

    type: Literal["error"] = "error"
    code: str
    message: str


ServerMessage = Union[ReadyMessage, PartialMessage, FinalMessage, ErrorMessage]


def parse_client_message(data: str) -> ClientMessage:
    """Parse a JSON message from client."""
    parsed = json.loads(data)
    msg_type = parsed.get("type")

    if msg_type == "config":
        return ConfigMessage(**parsed)
    elif msg_type == "end":
        return EndMessage(**parsed)
    elif msg_type == "keepalive":
        return KeepAliveMessage(**parsed)
    else:
        raise ValueError(f"Unknown message type: {msg_type}")


def serialize_server_message(msg: ServerMessage) -> str:
    """Serialize a server message to JSON."""
    return msg.model_dump_json()
