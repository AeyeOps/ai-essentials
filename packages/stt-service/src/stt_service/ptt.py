"""Push-to-Talk (PTT) controller with pluggable hotkey listeners.

Supports two hotkey detection strategies:
- EvdevHotkeyListener: Global hotkeys via evdev (production, requires /dev/input access)
- TerminalHotkeyListener: Terminal raw mode (Docker/SSH testing, no special permissions)

The PTTController handles state machine, sounds, and duration enforcement.
Only the hotkey detection differs between environments.
"""

import asyncio
import logging
import time
from enum import Enum, auto
from pathlib import Path
from typing import Callable, Optional

from .config import settings

logger = logging.getLogger(__name__)


class PTTState(Enum):
    """PTT state machine states."""
    IDLE = auto()        # Waiting for hotkey press
    RECORDING = auto()   # Hotkey held, recording audio
    PROCESSING = auto()  # Transcribing, ignore key events


class EvdevHotkeyListener:
    """Global hotkey listener using evdev (production).

    Monitors keyboard for configured hotkey combo (e.g., Ctrl+Super).
    Fires callbacks when hotkey is pressed/released.

    Interface (duck typing):
        - __init__(on_activate, on_deactivate, ...)
        - async start() -> None
        - stop() -> None
    """

    def __init__(
        self,
        on_activate: Callable[[], None],
        on_deactivate: Callable[[], None],
        hotkey: Optional[list[str]] = None,
    ):
        """Initialize hotkey listener.

        Args:
            on_activate: Called when all hotkey keys are pressed
            on_deactivate: Called when any hotkey key is released
            hotkey: List of key names (evdev KEY_* without prefix).
                    Default from settings: ["LEFTCTRL", "LEFTMETA"]
        """
        self.on_activate = on_activate
        self.on_deactivate = on_deactivate
        self.hotkey = hotkey or settings.ptt.hotkey

        self._pressed_keys: set[int] = set()
        self._hotkey_codes: set[int] = set()
        self._hotkey_active = False
        self._running = False
        self._devices: list = []

    def _resolve_key_codes(self) -> None:
        """Convert key names to evdev key codes."""
        try:
            from evdev import ecodes
        except ImportError:
            raise ImportError(
                "evdev is required for PTT mode. Install with: pip install evdev"
            )

        self._hotkey_codes = set()
        for key_name in self.hotkey:
            code_name = f"KEY_{key_name}"
            if hasattr(ecodes, code_name):
                self._hotkey_codes.add(getattr(ecodes, code_name))
            else:
                raise ValueError(f"Unknown key name: {key_name} (tried {code_name})")

        logger.info(f"PTT hotkey: {self.hotkey} -> codes {self._hotkey_codes}")

    def _find_keyboards(self) -> list:
        """Find keyboard input devices."""
        try:
            from evdev import InputDevice, list_devices, ecodes
        except ImportError:
            raise ImportError("evdev is required for PTT mode")

        keyboards = []
        for path in list_devices():
            try:
                device = InputDevice(path)
                caps = device.capabilities()
                # Check if device has EV_KEY capability with typical keyboard keys
                if ecodes.EV_KEY in caps:
                    key_caps = caps[ecodes.EV_KEY]
                    # Look for common keyboard keys
                    if ecodes.KEY_A in key_caps and ecodes.KEY_ENTER in key_caps:
                        keyboards.append(device)
                        logger.debug(f"Found keyboard: {device.name} at {device.path}")
            except (PermissionError, OSError) as e:
                logger.debug(f"Cannot access {path}: {e}")

        if not keyboards:
            raise RuntimeError(
                "No keyboards found. Ensure you have read access to /dev/input/event*. "
                "Try: sudo usermod -a -G input $USER (then log out/in)"
            )

        return keyboards

    async def _read_device(self, device) -> None:
        """Read events from a single device."""
        try:
            from evdev import ecodes, categorize
        except ImportError:
            return

        try:
            async for event in device.async_read_loop():
                if not self._running:
                    break

                if event.type == ecodes.EV_KEY:
                    # Key event: value 0=release, 1=press, 2=repeat
                    if event.value == 1:  # Press
                        self._pressed_keys.add(event.code)
                        self._check_hotkey()
                    elif event.value == 0:  # Release
                        self._pressed_keys.discard(event.code)
                        self._check_hotkey()

        except (OSError, asyncio.CancelledError):
            pass

    def _check_hotkey(self) -> None:
        """Check if hotkey state changed."""
        all_pressed = self._hotkey_codes.issubset(self._pressed_keys)

        if all_pressed and not self._hotkey_active:
            # Hotkey just activated
            self._hotkey_active = True
            logger.debug("Hotkey activated")
            self.on_activate()

        elif not all_pressed and self._hotkey_active:
            # Hotkey just deactivated (a key was released)
            self._hotkey_active = False
            logger.debug("Hotkey deactivated")
            self.on_deactivate()

    async def start(self) -> None:
        """Start listening for hotkey."""
        self._resolve_key_codes()
        self._devices = self._find_keyboards()
        self._running = True

        logger.info(f"PTT listening on {len(self._devices)} keyboard(s)")

        # Read from all keyboards concurrently
        tasks = [
            asyncio.create_task(self._read_device(dev))
            for dev in self._devices
        ]

        try:
            await asyncio.gather(*tasks)
        except asyncio.CancelledError:
            pass
        finally:
            self._running = False

    def stop(self) -> None:
        """Stop listening."""
        self._running = False
        for device in self._devices:
            try:
                device.close()
            except Exception:
                pass


class TerminalHotkeyListener:
    """Terminal-based hotkey listener for Docker/SSH testing.

    Uses terminal raw mode to detect key press/release.
    Detects release via key repeat timeout (no evdev required).

    Interface (duck typing - same as EvdevHotkeyListener):
        - __init__(on_activate, on_deactivate, ...)
        - async start() -> None
        - stop() -> None
    """

    # Key release detection timeouts
    # Initial repeat delay is ~250-500ms (OS/user configurable), then ~30-50ms intervals
    INITIAL_REPEAT_TIMEOUT = 0.6  # Wait for first repeat (longer than initial delay)
    REPEAT_INTERVAL_TIMEOUT = 0.15  # Subsequent repeats come faster

    def __init__(
        self,
        on_activate: Callable[[], None],
        on_deactivate: Callable[[], None],
        hotkey_char: Optional[str] = None,
    ):
        """Initialize terminal hotkey listener.

        Args:
            on_activate: Called when hotkey is pressed
            on_deactivate: Called when hotkey is released
            hotkey_char: Control character to detect (e.g., '\\x12' for Ctrl+R).
                         Default from settings.ptt.terminal_hotkey.
        """
        self.on_activate = on_activate
        self.on_deactivate = on_deactivate
        self.hotkey_char = hotkey_char or settings.ptt.terminal_hotkey
        self._running = False
        self._old_settings = None

    async def start(self) -> None:
        """Start listening for hotkey in terminal raw mode."""
        import sys
        import tty
        import termios
        import select

        fd = sys.stdin.fileno()
        self._old_settings = termios.tcgetattr(fd)
        self._running = True

        hotkey_name = settings.ptt.terminal_hotkey_name

        try:
            tty.setraw(fd)
            loop = asyncio.get_event_loop()

            while self._running:
                # Wait for keypress
                logger.debug(f"Terminal listener waiting for {hotkey_name}")
                char = await loop.run_in_executor(None, sys.stdin.read, 1)

                if not self._running:
                    break

                if char.lower() == 'q' or char == '\x1b':  # 'q' or ESC
                    logger.info("Quit key pressed")
                    break

                if char == self.hotkey_char:
                    # Key down - activate
                    logger.debug("Terminal hotkey activated")
                    self.on_activate()

                    # Two-phase key release detection:
                    # Phase 1: Wait for FIRST repeat (initial delay is ~250-500ms)
                    # Phase 2: Once repeats start, use shorter timeout
                    first_repeat_received = False
                    timeout = self.INITIAL_REPEAT_TIMEOUT

                    while self._running:
                        # Yield to event loop so start_recording() can run
                        await asyncio.sleep(0.01)

                        # Check for key repeat with current timeout
                        # Use multiple short checks to allow event loop yielding
                        elapsed = 0.0
                        key_received = False
                        while elapsed < timeout and self._running:
                            ready, _, _ = select.select([sys.stdin], [], [], 0.05)
                            if ready:
                                next_char = sys.stdin.read(1)
                                if next_char == self.hotkey_char:
                                    key_received = True
                                    first_repeat_received = True
                                    break
                                else:
                                    # Different key - treat as release
                                    break
                            elapsed += 0.05
                            await asyncio.sleep(0.01)  # Yield between checks

                        if not key_received:
                            # Timeout with no repeat - key was released
                            break

                        # Switch to shorter timeout after first repeat
                        if first_repeat_received:
                            timeout = self.REPEAT_INTERVAL_TIMEOUT

                    # Key up - deactivate
                    logger.debug("Terminal hotkey deactivated")
                    self.on_deactivate()

                    # Drain any remaining key repeats from buffer
                    while True:
                        ready, _, _ = select.select([sys.stdin], [], [], 0.05)
                        if ready:
                            sys.stdin.read(1)  # Discard
                        else:
                            break

        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, self._old_settings)

    def stop(self) -> None:
        """Stop listening."""
        self._running = False

    def print_normal(self, *args, **kwargs) -> None:
        """Print with normal terminal settings (exits raw mode temporarily).

        Use this from callbacks to ensure output displays correctly.
        In raw mode, newlines don't include carriage returns, causing
        garbled horizontal output. This method temporarily restores
        normal terminal settings before printing.
        """
        import sys
        import tty
        import termios

        if self._old_settings is None:
            # Not in raw mode, just print
            print(*args, **kwargs)
            return

        fd = sys.stdin.fileno()
        # Restore normal terminal
        termios.tcsetattr(fd, termios.TCSADRAIN, self._old_settings)
        try:
            print(*args, **kwargs)
            sys.stdout.flush()
        finally:
            # Return to raw mode
            tty.setraw(fd)


class PTTController:
    """Push-to-Talk controller managing state and audio feedback."""

    # Pre-generated sounds (class-level, generated once)
    _sounds: Optional[dict] = None
    _sample_rate: int = 44100

    @classmethod
    def _init_sounds(cls) -> None:
        """Pre-generate click sounds at class load time."""
        if cls._sounds is not None:
            return

        try:
            import numpy as np

            duration = 0.08  # 80ms
            t = np.linspace(0, duration, int(cls._sample_rate * duration), False)

            # Click sound - higher pitch rising tone
            freq = 880
            envelope = np.exp(-t * 15) * (1 - np.exp(-t * 100))
            click = (np.sin(2 * np.pi * freq * t) * envelope * 0.25).astype(np.float32)

            # Unclick sound - lower pitch falling tone
            freq = 440
            envelope = np.exp(-t * 20) * (1 - np.exp(-t * 100))
            unclick = (np.sin(2 * np.pi * freq * t) * envelope * 0.25).astype(np.float32)

            cls._sounds = {"click": click, "unclick": unclick}
        except Exception as e:
            logger.debug(f"Could not initialize sounds: {e}")
            cls._sounds = {}

    def __init__(self, listener=None):
        """Initialize PTT controller.

        Args:
            listener: HotkeyListener instance (EvdevHotkeyListener or TerminalHotkeyListener).
                      If None, defaults to EvdevHotkeyListener (production).
        """
        self.state = PTTState.IDLE
        self._listener = listener
        self._on_start_recording: Optional[Callable[[], None]] = None
        self._on_stop_recording: Optional[Callable[[], None]] = None
        self._auto_submitted = False  # Track if we auto-submitted due to limit
        self._recording_start_time: float = 0
        self._max_duration = settings.ptt.max_duration_seconds
        self._duration_check_task: Optional[asyncio.Task] = None

        # Initialize sounds on first instance
        self._init_sounds()

    # Cached output device (None = not checked, -1 = no valid device found)
    _output_device: Optional[int] = None

    @classmethod
    def _find_output_device(cls) -> Optional[int]:
        """Find a device with output capability."""
        if cls._output_device is not None:
            return None if cls._output_device == -1 else cls._output_device

        try:
            import sounddevice as sd
            devices = sd.query_devices()

            # First try default output
            try:
                default = sd.query_devices(kind='output')
                if default['max_output_channels'] > 0:
                    cls._output_device = default['index']
                    return cls._output_device
            except Exception:
                pass

            # Search for any device with output channels
            for i, dev in enumerate(devices):
                if dev['max_output_channels'] > 0:
                    cls._output_device = i
                    logger.debug(f"Using audio output device: {dev['name']}")
                    return cls._output_device

            cls._output_device = -1  # No valid device
            return None
        except Exception as e:
            logger.debug(f"Could not query audio devices: {e}")
            cls._output_device = -1
            return None

    def _play_sound_sync(self, sound_type: str) -> None:
        """Synchronous sound playback (called from executor)."""
        try:
            import sounddevice as sd
            device = self._find_output_device()
            if device is not None and self._sounds and sound_type in self._sounds:
                logger.debug(f"Playing {sound_type} sound on device {device}")
                sd.play(self._sounds[sound_type], self._sample_rate, device=device)
            else:
                logger.debug(f"Cannot play {sound_type}: device={device}, sounds={bool(self._sounds)}")
        except Exception as e:
            logger.debug(f"Could not play {sound_type} sound: {e}")

    def _play_sound(self, sound_type: str) -> None:
        """Play pre-generated audio feedback sound (fully async, zero blocking).

        Args:
            sound_type: 'click' for PTT activate, 'unclick' for deactivate
        """
        if not settings.ptt.click_sound:
            return

        if not self._sounds or sound_type not in self._sounds:
            return

        # Fire and forget in thread pool - no await, no blocking
        try:
            loop = asyncio.get_event_loop()
            loop.run_in_executor(None, self._play_sound_sync, sound_type)
        except Exception:
            pass  # Ignore if no event loop

    def _on_hotkey_activate(self) -> None:
        """Called when PTT hotkey is pressed."""
        if self.state != PTTState.IDLE:
            logger.debug(f"Ignoring hotkey activate in state {self.state}")
            return

        self.state = PTTState.RECORDING
        self._auto_submitted = False
        self._recording_start_time = time.perf_counter()

        self._play_sound("click")
        logger.info("PTT: Recording started")

        if self._on_start_recording:
            self._on_start_recording()

        # Start duration monitoring
        if self._duration_check_task:
            self._duration_check_task.cancel()
        self._duration_check_task = asyncio.create_task(self._monitor_duration())

    def _on_hotkey_deactivate(self) -> None:
        """Called when PTT hotkey is released."""
        if self.state != PTTState.RECORDING:
            logger.debug(f"Ignoring hotkey deactivate in state {self.state}")
            return

        if self._auto_submitted:
            # Already submitted due to limit, just reset state
            logger.debug("Ignoring key release - already auto-submitted")
            self._auto_submitted = False
            self.state = PTTState.IDLE
            return

        self._submit_recording()

    def _submit_recording(self) -> None:
        """Submit the current recording for transcription."""
        if self._duration_check_task:
            self._duration_check_task.cancel()
            self._duration_check_task = None

        duration = time.perf_counter() - self._recording_start_time
        self.state = PTTState.PROCESSING

        self._play_sound("unclick")
        logger.info(f"PTT: Recording stopped ({duration:.1f}s), processing...")

        if self._on_stop_recording:
            self._on_stop_recording()

    async def _monitor_duration(self) -> None:
        """Monitor recording duration and auto-submit if limit reached."""
        try:
            await asyncio.sleep(self._max_duration)

            if self.state == PTTState.RECORDING:
                logger.info(f"PTT: Max duration ({self._max_duration}s) reached, auto-submitting")
                self._auto_submitted = True
                self._submit_recording()

        except asyncio.CancelledError:
            pass

    def on_processing_complete(self) -> None:
        """Called when transcription processing is complete."""
        if self.state == PTTState.PROCESSING:
            self.state = PTTState.IDLE
            logger.debug("PTT: Processing complete, ready for next recording")

    def set_callbacks(
        self,
        on_start: Callable[[], None],
        on_stop: Callable[[], None],
    ) -> None:
        """Set recording callbacks.

        Args:
            on_start: Called when recording should start
            on_stop: Called when recording should stop and submit
        """
        self._on_start_recording = on_start
        self._on_stop_recording = on_stop

    async def run(self) -> None:
        """Run the PTT controller."""
        # Use injected listener, or create default (evdev for production)
        if self._listener is None:
            self._listener = EvdevHotkeyListener(
                on_activate=self._on_hotkey_activate,
                on_deactivate=self._on_hotkey_deactivate,
            )
        else:
            # Wire callbacks to injected listener
            self._listener.on_activate = self._on_hotkey_activate
            self._listener.on_deactivate = self._on_hotkey_deactivate

        try:
            await self._listener.start()
        finally:
            self._listener.stop()

    def stop(self) -> None:
        """Stop the PTT controller."""
        if self._listener:
            self._listener.stop()
        if self._duration_check_task:
            self._duration_check_task.cancel()
