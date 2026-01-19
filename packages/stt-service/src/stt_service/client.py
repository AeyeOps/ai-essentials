"""PTT (Push-to-Talk) WebSocket client for STT service."""

import argparse
import asyncio
import json
import logging
import os
import subprocess
import sys
from typing import Optional

import numpy as np
import sounddevice as sd
import websockets

from .config import settings
from .protocol import ConfigMessage

logger = logging.getLogger(__name__)


class PTTClient:
    """Push-to-talk client that streams audio to STT server."""

    def __init__(self, server_url: Optional[str] = None):
        self.server_url = server_url or settings.client.server_url
        self.websocket = None
        self.session_id: Optional[str] = None
        self._recording = False
        self._audio_queue: asyncio.Queue = asyncio.Queue()

    # Connection timeout in seconds
    CONNECT_TIMEOUT = 10.0

    async def connect(self) -> bool:
        """Connect to the STT server.

        Returns:
            True if connected successfully.
        """
        try:
            self.websocket = await asyncio.wait_for(
                websockets.connect(
                    self.server_url,
                    max_size=10 * 1024 * 1024,
                ),
                timeout=self.CONNECT_TIMEOUT,
            )

            # Wait for ready message with timeout
            response = await asyncio.wait_for(
                self.websocket.recv(),
                timeout=self.CONNECT_TIMEOUT,
            )
            msg = json.loads(response)

            if msg.get("type") == "ready":
                self.session_id = msg.get("session_id")
                logger.info(f"Connected to server, session: {self.session_id}")
                return True
            else:
                logger.error(f"Unexpected response: {msg}")
                return False

        except asyncio.TimeoutError:
            logger.error(f"Connection timeout after {self.CONNECT_TIMEOUT}s")
            return False
        except Exception as e:
            logger.error(f"Failed to connect: {e}")
            return False

    async def disconnect(self) -> None:
        """Disconnect from the server."""
        if self.websocket:
            await self.websocket.close()
            self.websocket = None
            self.session_id = None

    async def send_config(self) -> None:
        """Send configuration to server."""
        config = ConfigMessage(
            sample_rate=settings.audio.sample_rate,
            language="en",
        )
        await self.websocket.send(config.model_dump_json())

    def _audio_callback(
        self,
        indata: np.ndarray,
        frames: int,
        time_info,
        status,
    ) -> None:
        """Callback for audio input stream."""
        if status:
            logger.warning(f"Audio status: {status}")

        if self._recording:
            # Convert to bytes and queue
            audio_bytes = indata.tobytes()
            try:
                self._audio_queue.put_nowait(audio_bytes)
            except asyncio.QueueFull:
                logger.warning("Audio queue full, dropping chunk")

    async def _stream_audio(self) -> None:
        """Stream queued audio chunks to server."""
        while self._recording or not self._audio_queue.empty():
            try:
                chunk = await asyncio.wait_for(
                    self._audio_queue.get(),
                    timeout=0.1,
                )
                await self.websocket.send(chunk)
            except asyncio.TimeoutError:
                continue
            except Exception as e:
                logger.error(f"Error streaming audio: {e}")
                break

    async def record_and_transcribe(self) -> Optional[str]:
        """Record audio until stopped, then get transcription.

        Returns:
            Transcribed text, or None on error.
        """
        if not self.websocket:
            logger.error("Not connected to server")
            return None

        # Send config first
        await self.send_config()

        # Create queue BEFORE setting recording flag (avoid race condition)
        self._audio_queue = asyncio.Queue(maxsize=1000)
        self._recording = True

        stream = sd.InputStream(
            samplerate=settings.audio.sample_rate,
            channels=settings.audio.channels,
            dtype=np.int16,
            blocksize=settings.audio.chunk_samples,
            callback=self._audio_callback,
        )

        logger.info("Recording... (press Enter to stop)")

        try:
            with stream:
                # Stream audio in background
                stream_task = asyncio.create_task(self._stream_audio())

                # Wait for user to press Enter
                loop = asyncio.get_running_loop()
                await loop.run_in_executor(None, input)

                self._recording = False
                await stream_task

        except Exception as e:
            logger.error(f"Recording error: {e}")
            self._recording = False
            return None

        # Signal end of audio
        await self.websocket.send(json.dumps({"type": "end"}))

        # Wait for transcription
        try:
            response = await asyncio.wait_for(
                self.websocket.recv(),
                timeout=30.0,
            )
            msg = json.loads(response)

            if msg.get("type") == "final":
                return msg.get("text", "")
            elif msg.get("type") == "error":
                logger.error(f"Server error: {msg.get('message')}")
                return None
            else:
                logger.error(f"Unexpected response: {msg}")
                return None

        except asyncio.TimeoutError:
            logger.error("Timeout waiting for transcription")
            return None


def output_text(text: str, mode: str) -> None:
    """Output transcribed text according to mode."""
    if mode == "stdout":
        print(text)

    elif mode == "type":
        # Detect display server
        session_type = os.environ.get("XDG_SESSION_TYPE", "x11")

        if session_type == "wayland":
            try:
                subprocess.run(
                    ["wtype", "-"],
                    input=text.encode(),
                    check=True,
                )
            except FileNotFoundError:
                logger.error("wtype not found. Install with: apt install wtype")
                print(text)
        else:
            try:
                subprocess.run(
                    ["xdotool", "type", "--clearmodifiers", "--", text],
                    check=True,
                )
            except FileNotFoundError:
                logger.error("xdotool not found. Install with: apt install xdotool")
                print(text)

    elif mode == "clipboard":
        session_type = os.environ.get("XDG_SESSION_TYPE", "x11")

        if session_type == "wayland":
            try:
                subprocess.run(
                    ["wl-copy"],
                    input=text.encode(),
                    check=True,
                )
            except FileNotFoundError:
                logger.error("wl-copy not found. Install with: apt install wl-clipboard")
                print(text)
        else:
            try:
                subprocess.run(
                    ["xclip", "-selection", "clipboard"],
                    input=text.encode(),
                    check=True,
                )
            except FileNotFoundError:
                logger.error("xclip not found. Install with: apt install xclip")
                print(text)


def setup_logging(verbose: bool = False) -> None:
    """Configure logging."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )


async def run_client(args: argparse.Namespace) -> int:
    """Run the PTT client."""
    client = PTTClient(server_url=args.server)

    # Connect with retry
    for attempt in range(settings.client.reconnect_attempts):
        if await client.connect():
            break
        logger.warning(f"Connection attempt {attempt + 1} failed, retrying...")
        await asyncio.sleep(settings.client.reconnect_delay * (2 ** attempt))
    else:
        logger.error("Failed to connect to server")
        return 1

    try:
        if args.test:
            # Test mode: just verify connection
            logger.info("Test mode: connection successful")
            return 0

        # Record and transcribe
        text = await client.record_and_transcribe()

        if text:
            output_text(text, args.output or settings.client.output_mode)
            return 0
        else:
            return 1

    finally:
        await client.disconnect()


def main() -> None:
    """Main entry point for stt-client command."""
    parser = argparse.ArgumentParser(description="STT Push-to-Talk Client")
    parser.add_argument(
        "--server",
        default=None,
        help=f"Server URL (default: {settings.client.server_url})",
    )
    parser.add_argument(
        "--output", "-o",
        choices=["stdout", "type", "clipboard"],
        default=None,
        help=f"Output mode (default: {settings.client.output_mode})",
    )
    parser.add_argument(
        "--test",
        action="store_true",
        help="Test connection only",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Enable debug logging",
    )
    args = parser.parse_args()

    setup_logging(args.verbose)

    try:
        exit_code = asyncio.run(run_client(args))
        sys.exit(exit_code)
    except KeyboardInterrupt:
        logger.info("Interrupted")
        sys.exit(130)


if __name__ == "__main__":
    main()
