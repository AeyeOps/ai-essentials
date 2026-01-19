"""STT Service - Speech-to-Text with Parakeet ONNX models.

GPU-only service for real-time speech transcription using NVIDIA Parakeet models.

Example usage:
    from stt_service import Transcriber, PTTClient, settings

    # Server-side transcription
    transcriber = Transcriber()
    transcriber.load()
    text = transcriber.transcribe(audio_array)

    # Client-side PTT
    client = PTTClient()
    await client.connect()
    text = await client.record_and_transcribe()
"""

__version__ = "0.1.0"

from .config import Settings, settings
from .transcriber import GPUNotAvailableError, Transcriber, get_transcriber
from .client import PTTClient
from .server import STTServer, STTSession
from .protocol import (
    ConfigMessage,
    EndMessage,
    KeepAliveMessage,
    ReadyMessage,
    PartialMessage,
    FinalMessage,
    ErrorMessage,
)

__all__ = [
    # Version
    "__version__",
    # Config
    "Settings",
    "settings",
    # Transcriber
    "Transcriber",
    "GPUNotAvailableError",
    "get_transcriber",
    # Client
    "PTTClient",
    # Server
    "STTServer",
    "STTSession",
    # Protocol messages
    "ConfigMessage",
    "EndMessage",
    "KeepAliveMessage",
    "ReadyMessage",
    "PartialMessage",
    "FinalMessage",
    "ErrorMessage",
]
