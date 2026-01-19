"""PTT (Push-to-Talk) WebSocket client for STT service."""

import argparse
import asyncio
import json
import logging
import os
import subprocess
import sys
import time
from typing import Optional

import numpy as np
import sounddevice as sd
import websockets

from .config import settings
from .protocol import ConfigMessage

logger = logging.getLogger(__name__)


# PTT mode imports (optional - only needed with --ptt flag)
def _import_ptt():
    """Import PTT module on demand."""
    try:
        from .ptt import PTTController, PTTState
        return PTTController, PTTState
    except ImportError as e:
        logger.error(
            f"PTT mode requires evdev. Install with: pip install evdev\n"
            f"Also ensure you have /dev/input access: sudo usermod -a -G input $USER"
        )
        raise


class PTTClient:
    """Push-to-talk client that streams audio to STT server."""

    def __init__(self, server_url: Optional[str] = None):
        self.server_url = server_url or settings.client.server_url
        self.websocket = None
        self.session_id: Optional[str] = None
        self._recording = False
        self._audio_queue: asyncio.Queue = asyncio.Queue()
        self._server_error: Optional[str] = None
        self._stop_event: asyncio.Event = asyncio.Event()

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
            # Check if we should stop due to server error
            if self._stop_event.is_set():
                break
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

    async def _listen_for_errors(self) -> None:
        """Listen for server error messages during recording."""
        while self._recording and not self._stop_event.is_set():
            try:
                # Non-blocking check for incoming messages
                response = await asyncio.wait_for(
                    self.websocket.recv(),
                    timeout=0.1,
                )
                msg = json.loads(response)

                if msg.get("type") == "error":
                    self._server_error = msg.get("message", "Unknown server error")
                    logger.error(f"Server error during recording: {self._server_error}")
                    self._stop_event.set()
                    self._recording = False
                    break
                else:
                    logger.debug(f"Received message during recording: {msg}")

            except asyncio.TimeoutError:
                continue
            except Exception as e:
                logger.debug(f"Error listener: {e}")
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

        # Reset state before recording
        self._audio_queue = asyncio.Queue(maxsize=1000)
        self._server_error = None
        self._stop_event = asyncio.Event()
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
                # Stream audio and listen for errors concurrently
                stream_task = asyncio.create_task(self._stream_audio())
                error_listener_task = asyncio.create_task(self._listen_for_errors())

                # Wait for user to press Enter (in executor to not block)
                loop = asyncio.get_running_loop()
                await loop.run_in_executor(None, input)

                # --- TIMING: Start ---
                import time
                t_enter = time.perf_counter()

                self._recording = False
                self._stop_event.set()

                # Wait for tasks to complete
                await stream_task
                error_listener_task.cancel()
                try:
                    await error_listener_task
                except asyncio.CancelledError:
                    pass

                t_stream_done = time.perf_counter()

        except Exception as e:
            logger.error(f"Recording error: {e}")
            self._recording = False
            return None

        # Check if server sent an error during recording
        if self._server_error:
            logger.error(f"Recording aborted: {self._server_error}")
            return None

        # Signal end of audio
        await self.websocket.send(json.dumps({"type": "end"}))
        t_end_sent = time.perf_counter()

        # Wait for transcription
        try:
            response = await asyncio.wait_for(
                self.websocket.recv(),
                timeout=30.0,
            )
            t_response = time.perf_counter()

            msg = json.loads(response)

            if msg.get("type") == "final":
                # --- TIMING: Report ---
                print(f"\n⏱  Latency breakdown (ms):")
                print(f"   Stream flush:    {(t_stream_done - t_enter) * 1000:7.1f} ms")
                print(f"   Send 'end':      {(t_end_sent - t_stream_done) * 1000:7.1f} ms")
                print(f"   Server process:  {(t_response - t_end_sent) * 1000:7.1f} ms")
                print(f"   ─────────────────────────")
                print(f"   Total:           {(t_response - t_enter) * 1000:7.1f} ms\n")
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
    """Run the PTT client (single recording mode)."""
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


async def run_ptt_mode(args: argparse.Namespace) -> int:
    """Run continuous PTT mode with global hotkey."""
    PTTController, PTTState = _import_ptt()

    output_mode = args.output or settings.client.output_mode
    server_url = args.server or settings.client.server_url

    ptt = PTTController()
    client: Optional[PTTClient] = None

    # Shared state for PTT callbacks
    recording_task: Optional[asyncio.Task] = None
    stream: Optional[sd.InputStream] = None
    audio_chunks: list[np.ndarray] = []

    async def ensure_connected() -> bool:
        """Ensure client is connected."""
        nonlocal client
        if client and client.websocket:
            return True

        client = PTTClient(server_url=server_url)
        for attempt in range(settings.client.reconnect_attempts):
            if await client.connect():
                return True
            logger.warning(f"Connection attempt {attempt + 1} failed...")
            await asyncio.sleep(settings.client.reconnect_delay * (2 ** attempt))

        logger.error("Failed to connect to server")
        return False

    def audio_callback(indata, frames, time_info, status):
        """Sounddevice callback - collect audio chunks."""
        if status:
            logger.warning(f"Audio status: {status}")
        audio_chunks.append(indata.copy())

    async def start_recording():
        """Start audio capture."""
        nonlocal stream, audio_chunks

        if not await ensure_connected():
            ptt.state = PTTState.IDLE
            return

        # Send config
        await client.send_config()

        # Clear previous audio
        audio_chunks.clear()

        # Start audio stream
        stream = sd.InputStream(
            samplerate=settings.audio.sample_rate,
            channels=settings.audio.channels,
            dtype=np.int16,
            blocksize=settings.audio.chunk_samples,
            callback=audio_callback,
        )
        stream.start()

    async def stop_recording():
        """Stop recording and submit for transcription."""
        nonlocal stream, audio_chunks

        # Stop audio stream
        if stream:
            stream.stop()
            stream.close()
            stream = None

        if not client or not client.websocket:
            ptt.on_processing_complete()
            return

        # Concatenate audio
        if not audio_chunks:
            logger.warning("No audio recorded")
            ptt.on_processing_complete()
            return

        audio = np.concatenate(audio_chunks)
        duration = len(audio) / settings.audio.sample_rate

        # Send audio to server
        t_start = time.perf_counter()

        try:
            # Stream audio chunks to server
            chunk_size = settings.audio.chunk_samples
            for i in range(0, len(audio), chunk_size):
                chunk = audio[i:i + chunk_size]
                await client.websocket.send(chunk.tobytes())

            # Signal end and wait for response
            await client.websocket.send(json.dumps({"type": "end"}))

            response = await asyncio.wait_for(
                client.websocket.recv(),
                timeout=30.0,
            )
            msg = json.loads(response)

            t_done = time.perf_counter()

            if msg.get("type") == "final":
                text = msg.get("text", "")
                if text:
                    logger.info(f"Transcribed ({duration:.1f}s audio in {(t_done-t_start)*1000:.0f}ms)")
                    output_text(text, output_mode)
                else:
                    logger.info("(silence)")
            elif msg.get("type") == "error":
                logger.error(f"Server error: {msg.get('message')}")

        except asyncio.TimeoutError:
            logger.error("Timeout waiting for transcription")
        except Exception as e:
            logger.error(f"Error during transcription: {e}")

        ptt.on_processing_complete()

    # Set up callbacks (these are called from sync context, schedule async work)
    loop = asyncio.get_event_loop()

    def on_start():
        nonlocal recording_task
        recording_task = loop.create_task(start_recording())

    def on_stop():
        nonlocal recording_task
        # Cancel any pending start task
        if recording_task and not recording_task.done():
            recording_task.cancel()
        loop.create_task(stop_recording())

    ptt.set_callbacks(on_start=on_start, on_stop=on_stop)

    # Print startup message
    hotkey_str = "+".join(settings.ptt.hotkey)
    print(f"\n🎤 PTT mode active. Hold [{hotkey_str}] to record, release to transcribe.")
    print(f"   Output: {output_mode}")
    print(f"   Server: {server_url}")
    print(f"   Press Ctrl+C to exit.\n")

    try:
        await ptt.run()
    except KeyboardInterrupt:
        print("\n\nPTT mode stopped.")
    finally:
        ptt.stop()
        if client:
            await client.disconnect()

    return 0


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
        "--ptt",
        action="store_true",
        help="Continuous PTT mode with global hotkey (Ctrl+Super by default)",
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
        if args.ptt:
            exit_code = asyncio.run(run_ptt_mode(args))
        else:
            exit_code = asyncio.run(run_client(args))
        sys.exit(exit_code)
    except KeyboardInterrupt:
        logger.info("Interrupted")
        sys.exit(130)


if __name__ == "__main__":
    main()
