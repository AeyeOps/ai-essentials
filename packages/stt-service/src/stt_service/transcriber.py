"""ONNX-based speech transcription using Parakeet models.

This module requires GPU acceleration (CUDA or TensorRT).
It will fail fast if no GPU is available - no CPU fallback.
"""

import logging
from typing import Optional

import numpy as np

from .config import ModelConfig, settings

logger = logging.getLogger(__name__)


class GPUNotAvailableError(RuntimeError):
    """Raised when GPU is required but not available."""

    pass


def _verify_gpu_available() -> None:
    """Verify CUDA GPU is available. Raises GPUNotAvailableError if not."""
    try:
        import onnxruntime as ort

        available = ort.get_available_providers()
        if "CUDAExecutionProvider" not in available:
            raise GPUNotAvailableError(
                f"CUDA not available. Found providers: {available}. "
                "Install onnxruntime-gpu and ensure CUDA is configured."
            )
    except ImportError:
        raise GPUNotAvailableError(
            "onnxruntime not installed. Install with: pip install onnxruntime-gpu"
        )


class Transcriber:
    """Transcriber using onnx-asr with Parakeet TDT models.

    GPU-only: Fails fast if CUDA/TensorRT not available.
    """

    def __init__(self, config: Optional[ModelConfig] = None):
        """Initialize transcriber with model configuration.

        Args:
            config: Model configuration. Uses global settings if not provided.

        Raises:
            GPUNotAvailableError: If GPU is not available.
        """
        self.config = config or settings.model
        self._model = None

        # Fail fast: verify GPU on initialization
        _verify_gpu_available()

    def _get_providers(self) -> list:
        """Get ONNX execution providers. GPU only, no CPU fallback."""
        if self.config.provider == "tensorrt":
            return [
                (
                    "TensorrtExecutionProvider",
                    {
                        "device_id": self.config.device_id,
                        "trt_max_workspace_size": 6 * 1024**3,  # 6GB
                        "trt_fp16_enable": True,
                    },
                ),
                ("CUDAExecutionProvider", {"device_id": self.config.device_id}),
            ]
        else:  # cuda (default)
            return [
                ("CUDAExecutionProvider", {"device_id": self.config.device_id}),
            ]

    def load(self) -> None:
        """Load the ONNX model.

        Uses path if models_dir exists and contains the model,
        otherwise lets onnx-asr download from HuggingFace.

        Raises:
            ImportError: If onnx-asr is not installed.
            GPUNotAvailableError: If GPU provider fails to initialize.
        """
        try:
            import onnx_asr
        except ImportError as e:
            raise ImportError(
                "onnx-asr is required. Install with: pip install onnx-asr"
            ) from e

        providers = self._get_providers()

        # Check for local model directory
        model_path = None
        if self.config.models_dir.exists():
            # Look for model subdirectory matching the model name pattern
            # e.g., "nemo-parakeet-tdt-0.6b-v2" -> "parakeet-tdt-0.6b-v2"
            model_short_name = self.config.name.removeprefix("nemo-")
            potential_dir = self.config.models_dir / model_short_name
            if potential_dir.exists():
                model_path = str(potential_dir)
                logger.info(f"Using local model from: {model_path}")

        logger.info(f"Loading model {self.config.name} with GPU providers: {providers}")

        try:
            self._model = onnx_asr.load_model(
                self.config.name,
                path=model_path,
                providers=providers,
            )
        except Exception as e:
            raise GPUNotAvailableError(
                f"Failed to load model with GPU providers: {e}. "
                "Ensure CUDA and onnxruntime-gpu are properly installed."
            ) from e

        logger.info("Model loaded successfully on GPU")

    @property
    def is_loaded(self) -> bool:
        """Check if model is loaded."""
        return self._model is not None

    # Maximum audio duration in seconds (onnx-asr models max out around 30s)
    MAX_AUDIO_SECONDS = 30

    def transcribe(self, audio: np.ndarray, sample_rate: int = 16000) -> str:
        """Transcribe audio to text.

        Args:
            audio: Audio samples as numpy array (float32, normalized to [-1, 1]).
            sample_rate: Sample rate of audio (default 16000 Hz).

        Returns:
            Transcribed text.

        Raises:
            RuntimeError: If model is not loaded.
            ValueError: If audio exceeds maximum duration.
        """
        import time
        t_start = time.perf_counter()

        if not self.is_loaded:
            raise RuntimeError("Model not loaded. Call load() first.")

        # Ensure audio is float32 and normalized
        if audio.dtype != np.float32:
            if audio.dtype == np.int16:
                audio = audio.astype(np.float32) / 32767.0  # Correct normalization
            else:
                audio = audio.astype(np.float32)

        # Ensure mono
        if audio.ndim > 1:
            audio = audio.mean(axis=1)

        # Validate audio length
        duration_seconds = len(audio) / sample_rate
        if duration_seconds > self.MAX_AUDIO_SECONDS:
            raise ValueError(
                f"Audio too long: {duration_seconds:.1f}s exceeds max {self.MAX_AUDIO_SECONDS}s. "
                "Record shorter segments or implement VAD chunking."
            )

        t_preprocess = time.perf_counter()

        # onnx-asr uses recognize(), not transcribe()
        result = self._model.recognize(audio, sample_rate=sample_rate)

        t_inference = time.perf_counter()

        # Handle different return types from onnx-asr
        if isinstance(result, str):
            text = result.strip()
        elif hasattr(result, "text"):
            # VAD segment result
            text = result.text.strip()
        else:
            text = str(result).strip()

        logger.info(
            f"[timing] Transcriber: preprocess={1000*(t_preprocess-t_start):.0f}ms, "
            f"inference={1000*(t_inference-t_preprocess):.0f}ms"
        )

        return text

    def transcribe_chunks(
        self, chunks: list[np.ndarray], sample_rate: int = 16000
    ) -> str:
        """Transcribe multiple audio chunks.

        Args:
            chunks: List of audio chunks.
            sample_rate: Sample rate of audio.

        Returns:
            Transcribed text from all chunks.
        """
        if not chunks:
            return ""

        # Concatenate all chunks
        audio = np.concatenate(chunks)
        return self.transcribe(audio, sample_rate)


# Singleton transcriber instance
_transcriber: Optional[Transcriber] = None


def get_transcriber() -> Transcriber:
    """Get or create the global transcriber instance."""
    global _transcriber
    if _transcriber is None:
        _transcriber = Transcriber()
    return _transcriber
