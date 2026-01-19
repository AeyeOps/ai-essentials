"""WebSocket server for real-time speech-to-text."""

import argparse
import asyncio
import logging
import signal
import sys
import uuid
from typing import Optional

import numpy as np
import websockets
from websockets.server import WebSocketServerProtocol

from .config import settings
from .protocol import (
    ConfigMessage,
    ErrorMessage,
    FinalMessage,
    ReadyMessage,
    parse_client_message,
    serialize_server_message,
)
from .transcriber import GPUNotAvailableError, Transcriber

logger = logging.getLogger(__name__)


class STTSession:
    """Represents a single STT session with a client."""

    # Max buffer: 30 seconds at 16kHz (aligned with transcriber MAX_AUDIO_SECONDS)
    # This prevents accepting audio that would be rejected during transcription
    MAX_BUFFER_SAMPLES = 16000 * 30

    def __init__(self, session_id: str, websocket: WebSocketServerProtocol):
        self.session_id = session_id
        self.websocket = websocket
        self.audio_chunks: list[np.ndarray] = []
        self.sample_rate: int = 16000
        self.configured: bool = False
        self._total_samples: int = 0

    def add_chunk(self, data: bytes) -> bool:
        """Add an audio chunk to the session buffer.

        Returns:
            True if chunk was added, False if buffer is full.
        """
        # Convert bytes to numpy array (16-bit signed PCM)
        audio = np.frombuffer(data, dtype=np.int16)

        # Check buffer limit
        if self._total_samples + len(audio) > self.MAX_BUFFER_SAMPLES:
            return False

        self.audio_chunks.append(audio)
        self._total_samples += len(audio)
        return True

    def get_audio(self) -> Optional[np.ndarray]:
        """Get concatenated audio from all chunks."""
        if not self.audio_chunks:
            return None
        return np.concatenate(self.audio_chunks)

    def clear(self) -> None:
        """Clear audio buffer."""
        self.audio_chunks.clear()
        self._total_samples = 0


class STTServer:
    """WebSocket server for speech-to-text."""

    def __init__(self):
        self.transcriber: Optional[Transcriber] = None
        self.sessions: dict[str, STTSession] = {}
        self._shutdown_event = asyncio.Event()
        self._connection_semaphore: Optional[asyncio.Semaphore] = None

    async def initialize(self) -> None:
        """Initialize the server and load the model.

        Raises:
            GPUNotAvailableError: If GPU is not available.
        """
        logger.info("Initializing STT server...")
        self.transcriber = Transcriber()
        self.transcriber.load()
        self._connection_semaphore = asyncio.Semaphore(settings.server.max_connections)
        logger.info(
            f"STT server initialized (max {settings.server.max_connections} connections)"
        )

    async def handle_connection(self, websocket: WebSocketServerProtocol) -> None:
        """Handle a WebSocket connection.

        Uses semaphore to enforce max_connections limit. Behavior when full
        depends on settings.server.reject_when_full:
        - True (default): Immediately reject with SERVER_FULL error
        - False: Queue connection until a slot becomes available
        """
        # Check if we should reject when at capacity
        if settings.server.reject_when_full:
            if self._connection_semaphore.locked():
                logger.warning(
                    f"Rejecting connection: server full ({len(self.sessions)} active)"
                )
                await websocket.send(
                    serialize_server_message(
                        ErrorMessage(
                            code="SERVER_FULL",
                            message=f"Server at capacity ({settings.server.max_connections} connections). Try again later.",
                        )
                    )
                )
                await websocket.close()
                return

        async with self._connection_semaphore:
            session_id = str(uuid.uuid4())[:8]
            session = STTSession(session_id, websocket)
            self.sessions[session_id] = session

            logger.info(f"New connection: {session_id} ({len(self.sessions)} active)")

            try:
                # Send ready message
                await websocket.send(
                    serialize_server_message(ReadyMessage(session_id=session_id))
                )

                async for message in websocket:
                    await self._handle_message(session, message)

            except websockets.exceptions.ConnectionClosed:
                logger.info(f"Connection closed: {session_id}")
            except Exception as e:
                logger.error(f"Error in session {session_id}: {e}")
                try:
                    await websocket.send(
                        serialize_server_message(
                            ErrorMessage(code="INTERNAL", message=str(e))
                        )
                    )
                except Exception:
                    pass
            finally:
                del self.sessions[session_id]

    async def _handle_message(
        self, session: STTSession, message: bytes | str
    ) -> None:
        """Handle a single message from client."""
        if isinstance(message, bytes):
            # Binary message = audio chunk
            if not session.configured:
                await session.websocket.send(
                    serialize_server_message(
                        ErrorMessage(
                            code="NOT_CONFIGURED",
                            message="Send config message before audio",
                        )
                    )
                )
                return

            if not session.add_chunk(message):
                await session.websocket.send(
                    serialize_server_message(
                        ErrorMessage(
                            code="BUFFER_FULL",
                            message="Audio buffer full (max 30s). Send 'end' to transcribe.",
                        )
                    )
                )
                return

        else:
            # Text message = JSON control message
            try:
                msg = parse_client_message(message)
            except Exception as e:
                await session.websocket.send(
                    serialize_server_message(
                        ErrorMessage(code="PARSE_ERROR", message=str(e))
                    )
                )
                return

            if isinstance(msg, ConfigMessage):
                session.sample_rate = msg.sample_rate
                session.configured = True
                logger.debug(f"Session {session.session_id} configured: {msg}")

            elif msg.type == "end":
                await self._process_audio(session)

            elif msg.type == "keepalive":
                pass  # Connection stays alive

    async def _process_audio(self, session: STTSession) -> None:
        """Process accumulated audio and send transcription."""
        import time
        t_start = time.perf_counter()

        audio = session.get_audio()
        session.clear()

        if audio is None or len(audio) == 0:
            await session.websocket.send(
                serialize_server_message(FinalMessage(text="", confidence=0.0))
            )
            return

        t_prep = time.perf_counter()
        audio_duration = len(audio) / session.sample_rate

        try:
            # Run transcription in thread pool to not block event loop
            loop = asyncio.get_running_loop()
            text = await loop.run_in_executor(
                None,
                self.transcriber.transcribe,
                audio,
                session.sample_rate,
            )
            t_transcribe = time.perf_counter()

            await session.websocket.send(
                serialize_server_message(FinalMessage(text=text, confidence=1.0))
            )
            t_sent = time.perf_counter()

            # Log timing breakdown
            logger.info(
                f"⏱  Server timing: prep={1000*(t_prep-t_start):.0f}ms, "
                f"transcribe={1000*(t_transcribe-t_prep):.0f}ms, "
                f"send={1000*(t_sent-t_transcribe):.0f}ms, "
                f"total={1000*(t_sent-t_start):.0f}ms "
                f"(audio={audio_duration:.1f}s)"
            )
            logger.debug(f"Transcribed: {text[:50]}..." if len(text) > 50 else f"Transcribed: {text}")

        except Exception as e:
            logger.error(f"Transcription error: {e}")
            await session.websocket.send(
                serialize_server_message(
                    ErrorMessage(code="TRANSCRIPTION_ERROR", message=str(e))
                )
            )

    async def run(self) -> None:
        """Run the WebSocket server."""
        host = settings.server.host
        port = settings.server.port

        logger.info(f"Starting STT server on ws://{host}:{port}")

        async with websockets.serve(
            self.handle_connection,
            host,
            port,
            max_size=10 * 1024 * 1024,  # 10MB max message size
        ):
            await self._shutdown_event.wait()

        logger.info("STT server stopped")

    def shutdown(self) -> None:
        """Signal server to shutdown."""
        self._shutdown_event.set()


def setup_logging(verbose: bool = False) -> None:
    """Configure logging."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )


def main() -> None:
    """Main entry point for stt-server command."""
    parser = argparse.ArgumentParser(description="STT WebSocket Server")
    parser.add_argument(
        "--host",
        default=None,
        help=f"Bind address (default: {settings.server.host})",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=None,
        help=f"Port (default: {settings.server.port})",
    )
    parser.add_argument(
        "--provider",
        choices=["cuda", "tensorrt"],
        default=None,
        help=f"ONNX provider (default: {settings.model.provider})",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Enable debug logging",
    )
    args = parser.parse_args()

    setup_logging(args.verbose)

    # Override settings from args
    if args.host:
        settings.server.host = args.host
    if args.port:
        settings.server.port = args.port
    if args.provider:
        settings.model.provider = args.provider

    server = STTServer()

    try:
        asyncio.run(_run_server(server))
    except GPUNotAvailableError as e:
        logger.error(f"GPU not available: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        logger.info("Interrupted")


async def _setup_signals(server: STTServer) -> None:
    """Setup signal handlers within the event loop."""
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, server.shutdown)


async def _run_server(server: STTServer) -> None:
    """Initialize and run the server."""
    await _setup_signals(server)
    await server.initialize()
    await server.run()


if __name__ == "__main__":
    main()
