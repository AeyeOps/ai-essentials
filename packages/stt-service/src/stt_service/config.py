"""Configuration settings for STT service."""

from pathlib import Path
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class AudioConfig(BaseSettings):
    """Audio capture and processing settings."""

    model_config = SettingsConfigDict(env_prefix="STT_AUDIO_")

    sample_rate: int = Field(default=16000, description="Audio sample rate in Hz")
    channels: int = Field(default=1, description="Number of audio channels (mono)")
    bit_depth: int = Field(default=16, description="Bits per sample")
    chunk_ms: int = Field(default=100, description="Chunk duration in milliseconds")

    @property
    def chunk_samples(self) -> int:
        """Number of samples per chunk."""
        return int(self.sample_rate * self.chunk_ms / 1000)

    @property
    def chunk_bytes(self) -> int:
        """Bytes per chunk (16-bit = 2 bytes per sample)."""
        return self.chunk_samples * (self.bit_depth // 8) * self.channels


class ServerConfig(BaseSettings):
    """WebSocket server settings."""

    model_config = SettingsConfigDict(env_prefix="STT_SERVER_")

    host: str = Field(default="127.0.0.1", description="Server bind address")
    port: int = Field(default=9876, description="Server port")
    max_connections: int = Field(default=10, description="Maximum concurrent connections")
    reject_when_full: bool = Field(
        default=True,
        description="If True, reject new connections when at capacity. "
        "If False, queue connections until a slot is available.",
    )


class ModelConfig(BaseSettings):
    """ONNX model settings.

    GPU-only: Only CUDA and TensorRT providers are supported.
    Service will fail fast if GPU is not available.
    """

    model_config = SettingsConfigDict(env_prefix="STT_MODEL_")

    name: str = Field(
        default="nemo-parakeet-tdt-0.6b-v2",
        description="Model name for onnx-asr",
    )
    models_dir: Path = Field(
        default=Path(__file__).parent.parent.parent / "models",
        description="Directory containing ONNX models",
    )
    provider: Literal["cuda", "tensorrt"] = Field(
        default="cuda",
        description="ONNX execution provider (GPU only, no CPU fallback)",
    )
    device_id: int = Field(default=0, description="GPU device ID")


class PTTConfig(BaseSettings):
    """Push-to-Talk settings."""

    model_config = SettingsConfigDict(env_prefix="STT_PTT_")

    # Global hotkey (evdev KEY_* names without KEY_ prefix) - for production
    hotkey: list[str] = Field(
        default=["LEFTCTRL", "LEFTMETA"],
        description="PTT hotkey as list of key names (e.g., ['LEFTCTRL', 'LEFTMETA'])",
    )
    # Terminal hotkey for Docker/SSH testing
    # Using spacebar - intuitive for PTT and not intercepted by terminals
    terminal_hotkey: str = Field(
        default=" ",  # Spacebar
        description="Terminal PTT key (default: spacebar)",
    )
    terminal_hotkey_name: str = Field(
        default="SPACE",
        description="Human-readable name for terminal hotkey",
    )
    click_sound: bool = Field(
        default=True,
        description="Play click sound when PTT activates",
    )
    auto_submit_on_limit: bool = Field(
        default=True,
        description="Auto-submit when 30s buffer limit is reached",
    )
    max_duration_seconds: float = Field(
        default=30.0,
        description="Maximum recording duration before auto-submit",
    )
    processing_timeout_seconds: float = Field(
        default=60.0,
        description="Max time in PROCESSING state before auto-reset to IDLE",
    )
    device_scan_interval: float = Field(
        default=2.0,
        description="Interval between device scans for hot-plug detection (seconds)",
    )


class ClientConfig(BaseSettings):
    """Client settings."""

    model_config = SettingsConfigDict(env_prefix="STT_CLIENT_")

    server_url: str = Field(
        default="ws://127.0.0.1:9876",
        description="WebSocket server URL",
    )
    output_mode: Literal["stdout", "type", "clipboard"] = Field(
        default="stdout",
        description="Where to output transcribed text",
    )
    reconnect_attempts: int = Field(default=3, description="Max reconnection attempts")
    reconnect_delay: float = Field(default=1.0, description="Initial reconnect delay in seconds")


class Settings(BaseSettings):
    """Combined settings for STT service."""

    audio: AudioConfig = Field(default_factory=AudioConfig)
    server: ServerConfig = Field(default_factory=ServerConfig)
    model: ModelConfig = Field(default_factory=ModelConfig)
    client: ClientConfig = Field(default_factory=ClientConfig)
    ptt: PTTConfig = Field(default_factory=PTTConfig)


# Global settings instance
settings = Settings()
