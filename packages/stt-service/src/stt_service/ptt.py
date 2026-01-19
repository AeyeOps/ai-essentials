"""Push-to-Talk (PTT) hotkey listener using evdev.

Captures global hotkeys even when application doesn't have focus.
Requires read access to /dev/input/event* (typically 'input' group).
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


class HotkeyListener:
    """Global hotkey listener using evdev.

    Monitors keyboard for configured hotkey combo (e.g., Ctrl+Super).
    Fires callbacks when hotkey is pressed/released.
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


class PTTController:
    """Push-to-Talk controller managing state and audio feedback."""

    def __init__(self):
        self.state = PTTState.IDLE
        self._listener: Optional[HotkeyListener] = None
        self._on_start_recording: Optional[Callable[[], None]] = None
        self._on_stop_recording: Optional[Callable[[], None]] = None
        self._auto_submitted = False  # Track if we auto-submitted due to limit
        self._recording_start_time: float = 0
        self._max_duration = settings.ptt.max_duration_seconds
        self._duration_check_task: Optional[asyncio.Task] = None

    def _play_sound(self, sound_type: str) -> None:
        """Play audio feedback sound.

        Args:
            sound_type: 'click' for PTT activate, 'unclick' for deactivate
        """
        if not settings.ptt.click_sound:
            return

        try:
            import numpy as np
            import sounddevice as sd

            sample_rate = 44100
            duration = 0.08  # 80ms - subtle but audible

            t = np.linspace(0, duration, int(sample_rate * duration), False)

            if sound_type == "click":
                # Higher pitch rising tone - "on air"
                freq = 880  # A5
                envelope = np.exp(-t * 15) * (1 - np.exp(-t * 100))  # Quick attack, decay
                sound = np.sin(2 * np.pi * freq * t) * envelope
            else:
                # Lower pitch falling tone - "off air"
                freq = 440  # A4
                envelope = np.exp(-t * 20) * (1 - np.exp(-t * 100))
                sound = np.sin(2 * np.pi * freq * t) * envelope

            sound = (sound * 0.25).astype(np.float32)  # Subtle volume

            # Play non-blocking
            sd.play(sound, sample_rate)
        except Exception as e:
            logger.debug(f"Could not play {sound_type} sound: {e}")

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
        self._listener = HotkeyListener(
            on_activate=self._on_hotkey_activate,
            on_deactivate=self._on_hotkey_deactivate,
        )

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
