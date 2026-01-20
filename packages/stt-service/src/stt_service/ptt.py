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

    Supports device hot-plug for KVM switch scenarios:
    - Automatically detects device disconnection (normal operation)
    - Periodically scans for new/reconnected devices
    - Clears key state when devices disconnect to prevent stuck hotkeys

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
        on_device_count_changed: Optional[Callable[[int], None]] = None,
    ):
        """Initialize hotkey listener.

        Args:
            on_activate: Called when all hotkey keys are pressed
            on_deactivate: Called when any hotkey key is released
            hotkey: List of key names (evdev KEY_* without prefix).
                    Default from settings: ["LEFTCTRL", "LEFTMETA"]
            on_device_count_changed: Optional callback when device count changes.
                    Called with new device count (for tray state updates).
        """
        self.on_activate = on_activate
        self.on_deactivate = on_deactivate
        self.hotkey = hotkey or settings.ptt.hotkey
        self.on_device_count_changed = on_device_count_changed

        # Per-device key tracking (path -> set of pressed key codes)
        self._pressed_keys_by_device: dict[str, set[int]] = {}
        self._hotkey_codes: set[int] = set()
        self._hotkey_active = False
        self._running = False

        # Device management for hot-plug support
        self._device_tasks: dict[str, asyncio.Task] = {}  # path -> read task
        self._device_names: dict[str, str] = {}  # path -> device name (for logging)
        self._device_scan_interval = settings.ptt.device_scan_interval

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

    def _find_keyboards(self, exclude_paths: Optional[set[str]] = None) -> list:
        """Find keyboard input devices.

        Args:
            exclude_paths: Set of device paths to skip (already being monitored)

        Returns:
            List of InputDevice objects for keyboards not in exclude_paths.
            Returns empty list if no keyboards found (normal during KVM switch).

        Note:
            Deduplicates by device name - some keyboards (e.g., Logi K950) create
            multiple input nodes. We only monitor one per unique name to prevent
            duplicate hotkey events.
        """
        try:
            from evdev import InputDevice, list_devices, ecodes
        except ImportError:
            raise ImportError("evdev is required for PTT mode")

        exclude = exclude_paths or set()
        keyboards = []
        seen_names: set[str] = set()

        # Also track names of devices we're already monitoring
        for path in exclude:
            if path in self._device_names:
                seen_names.add(self._device_names[path])

        for path in list_devices():
            if path in exclude:
                continue  # Already monitoring this device

            try:
                device = InputDevice(path)

                # Skip if we already have a device with this name
                if device.name in seen_names:
                    logger.debug(f"Skipping duplicate device: {device.name} at {device.path}")
                    continue

                caps = device.capabilities()
                # Check if device has EV_KEY capability with typical keyboard keys
                if ecodes.EV_KEY in caps:
                    key_caps = caps[ecodes.EV_KEY]
                    # Look for common keyboard keys
                    if ecodes.KEY_A in key_caps and ecodes.KEY_ENTER in key_caps:
                        keyboards.append(device)
                        seen_names.add(device.name)
                        logger.debug(f"Found keyboard: {device.name} at {device.path}")
            except (PermissionError, OSError) as e:
                logger.debug(f"Cannot access {path}: {e}")

        # Don't raise on empty - KVM switch may reconnect devices later
        if not keyboards and not exclude:
            logger.warning(
                "No keyboards currently accessible. "
                "Waiting for devices (normal during KVM switch)."
            )

        return keyboards

    async def _read_device(self, device) -> None:
        """Read events from a single device with disconnect recovery.

        When the device disconnects (KVM switch, unplug), this method logs
        the event and cleans up. The device scanner will detect reconnection.
        """
        try:
            from evdev import ecodes
        except ImportError:
            return

        device_path = device.path
        device_name = device.name

        try:
            async for event in device.async_read_loop():
                if not self._running:
                    break

                if event.type == ecodes.EV_KEY:
                    # Key event: value 0=release, 1=press, 2=repeat
                    if event.value == 1:  # Press
                        self._pressed_keys_by_device.setdefault(device_path, set()).add(event.code)
                        self._check_hotkey()
                    elif event.value == 0:  # Release
                        if device_path in self._pressed_keys_by_device:
                            self._pressed_keys_by_device[device_path].discard(event.code)
                        self._check_hotkey()

        except OSError as e:
            # Device disconnected - normal for KVM switch
            logger.info(f"Device disconnected: {device_name} ({device_path})")
        except asyncio.CancelledError:
            pass
        finally:
            # Clean up this device's state
            self._on_device_disconnected(device_path, device_name)

    def _get_all_pressed_keys(self) -> set[int]:
        """Get union of all pressed keys across all devices."""
        all_keys: set[int] = set()
        for keys in self._pressed_keys_by_device.values():
            all_keys.update(keys)
        return all_keys

    def _check_hotkey(self) -> None:
        """Check if hotkey state changed."""
        all_pressed = self._hotkey_codes.issubset(self._get_all_pressed_keys())

        if all_pressed and not self._hotkey_active:
            # Hotkey just activated
            self._hotkey_active = True
            logger.debug("Hotkey activated")
            try:
                self.on_activate()
            except Exception as e:
                logger.error(f"Hotkey activate callback failed: {e}")

        elif not all_pressed and self._hotkey_active:
            # Hotkey just deactivated (a key was released)
            self._hotkey_active = False
            logger.debug("Hotkey deactivated")
            try:
                self.on_deactivate()
            except Exception as e:
                logger.error(f"Hotkey deactivate callback failed: {e}")

    def _on_device_disconnected(self, path: str, name: str) -> None:
        """Handle device disconnection (KVM switch, unplug).

        Cleans up device state and notifies listeners of device count change.
        """
        # Clear pressed keys for this device (prevents stuck hotkey)
        if path in self._pressed_keys_by_device:
            del self._pressed_keys_by_device[path]

        # Remove from tracking
        self._device_tasks.pop(path, None)
        self._device_names.pop(path, None)

        # If hotkey was active and keys are now incomplete, deactivate
        if self._hotkey_active and not self._hotkey_codes.issubset(self._get_all_pressed_keys()):
            self._hotkey_active = False
            logger.debug("Hotkey auto-deactivated due to device disconnect")
            try:
                self.on_deactivate()
            except Exception as e:
                logger.error(f"Hotkey deactivate callback failed: {e}")

        # Notify of device count change
        device_count = len(self._device_tasks)
        if device_count == 0:
            logger.warning("All keyboards disconnected (waiting for reconnection)")

        if self.on_device_count_changed:
            try:
                self.on_device_count_changed(device_count)
            except Exception as e:
                logger.debug(f"Device count callback failed: {e}")

    def _start_device_task(self, device) -> None:
        """Start a read task for a device."""
        path = device.path
        if path in self._device_tasks:
            return  # Already monitoring

        self._device_names[path] = device.name
        self._pressed_keys_by_device[path] = set()
        task = asyncio.create_task(self._read_device(device))
        self._device_tasks[path] = task
        logger.debug(f"Started monitoring: {device.name} ({path})")

    async def _device_scanner_loop(self) -> None:
        """Periodically scan for new/reconnected keyboard devices.

        This enables transparent KVM switch support - when devices
        disconnect and reconnect, they are automatically picked up.
        """
        while self._running:
            await asyncio.sleep(self._device_scan_interval)

            if not self._running:
                break

            # Clean up completed tasks (devices that disconnected)
            completed = [p for p, t in self._device_tasks.items() if t.done()]
            for path in completed:
                self._device_tasks.pop(path, None)
                self._device_names.pop(path, None)

            # Scan for new devices (excluding ones we're already monitoring)
            try:
                current_paths = set(self._device_tasks.keys())
                new_devices = self._find_keyboards(exclude_paths=current_paths)

                for device in new_devices:
                    logger.info(f"New keyboard detected: {device.name} ({device.path})")
                    self._start_device_task(device)

                    # Notify of device count change
                    if self.on_device_count_changed:
                        try:
                            self.on_device_count_changed(len(self._device_tasks))
                        except Exception as e:
                            logger.debug(f"Device count callback failed: {e}")

            except Exception as e:
                logger.debug(f"Device scan error: {e}")

    async def start(self) -> None:
        """Start listening for hotkey with hot-plug support.

        Supports KVM switch scenarios:
        - Starts with whatever keyboards are available (may be zero)
        - Continuously scans for new/reconnected devices
        - Automatically resumes when devices return
        """
        self._resolve_key_codes()
        self._running = True

        # Initial device scan
        initial_devices = self._find_keyboards()
        for device in initial_devices:
            self._start_device_task(device)

        device_count = len(self._device_tasks)
        if device_count > 0:
            logger.info(f"PTT listening on {device_count} keyboard(s)")
        else:
            logger.info("PTT waiting for keyboards (KVM may be switched away)")

        # Notify initial device count
        if self.on_device_count_changed:
            try:
                self.on_device_count_changed(device_count)
            except Exception:
                pass

        # Start device scanner for hot-plug detection
        scanner_task = asyncio.create_task(self._device_scanner_loop())

        try:
            # Keep running until stopped
            while self._running:
                await asyncio.sleep(0.5)
        except asyncio.CancelledError:
            pass
        finally:
            self._running = False
            scanner_task.cancel()

            # Cancel all device read tasks
            for task in list(self._device_tasks.values()):
                task.cancel()

    def stop(self) -> None:
        """Stop listening and clean up all devices."""
        self._running = False

        # Cancel all device tasks (they'll clean up in finally blocks)
        for task in list(self._device_tasks.values()):
            task.cancel()

        # Clear state
        self._device_tasks.clear()
        self._device_names.clear()
        self._pressed_keys_by_device.clear()
        self._hotkey_active = False


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
    _use_paplay: Optional[bool] = None  # None = not yet detected

    @classmethod
    def _detect_audio_backend(cls) -> None:
        """Detect whether to use sounddevice or paplay for audio output.

        Prefers sounddevice if it has PulseAudio backend, otherwise falls back
        to paplay if available. This handles Docker containers where PortAudio
        may lack PulseAudio support but paplay works via mounted socket.
        """
        if cls._use_paplay is not None:
            return

        # Check if sounddevice has PulseAudio backend
        try:
            import sounddevice as sd
            hostapis = sd.query_hostapis()
            has_pulse = any("pulse" in api["name"].lower() for api in hostapis)
            if has_pulse:
                cls._use_paplay = False
                logger.debug("Using sounddevice (PulseAudio backend available)")
                return
        except Exception:
            pass

        # Check if paplay is available
        import shutil
        if shutil.which("paplay"):
            cls._use_paplay = True
            logger.debug("Using paplay fallback (sounddevice lacks PulseAudio)")
        else:
            cls._use_paplay = False
            logger.debug("Using sounddevice (paplay not available)")

    @classmethod
    def _init_sounds(cls) -> None:
        """Pre-generate click sounds at class load time.

        Generates sounds in two formats:
        - float32 for sounddevice
        - int16 for paplay (more compatible, less artifacts)
        """
        if cls._sounds is not None:
            return

        # Detect audio backend
        cls._detect_audio_backend()

        try:
            import numpy as np

            sr = cls._sample_rate
            duration = 0.08  # 80ms tone

            # Add silence padding to prevent click/pop artifacts from audio subsystem
            pad_ms = 20  # 20ms padding (generous for paplay latency)
            pad_samples = int(sr * pad_ms / 1000)
            tone_samples = int(sr * duration)

            t = np.linspace(0, duration, tone_samples, False)

            # Smooth fade-in/out (cosine ramp, 5ms)
            fade_samples = int(sr * 0.005)
            fade_in = 0.5 * (1 - np.cos(np.pi * np.arange(fade_samples) / fade_samples))
            fade_out = fade_in[::-1]

            # Click sound - higher pitch (880Hz)
            freq = 880
            envelope = np.exp(-t * 15) * (1 - np.exp(-t * 100))
            click_tone = np.sin(2 * np.pi * freq * t) * envelope * 0.3
            click_tone[:fade_samples] *= fade_in
            click_tone[-fade_samples:] *= fade_out

            # Unclick sound - lower pitch (440Hz)
            freq = 440
            envelope = np.exp(-t * 20) * (1 - np.exp(-t * 100))
            unclick_tone = np.sin(2 * np.pi * freq * t) * envelope * 0.3
            unclick_tone[:fade_samples] *= fade_in
            unclick_tone[-fade_samples:] *= fade_out

            # Build padded sounds in both formats
            pad_f32 = np.zeros(pad_samples, dtype=np.float32)
            pad_i16 = np.zeros(pad_samples, dtype=np.int16)

            # float32 for sounddevice
            click_f32 = np.concatenate([pad_f32, click_tone.astype(np.float32), pad_f32])
            unclick_f32 = np.concatenate([pad_f32, unclick_tone.astype(np.float32), pad_f32])

            # int16 for paplay (scale to int16 range)
            click_i16 = np.concatenate([
                pad_i16, (click_tone * 32767).astype(np.int16), pad_i16
            ])
            unclick_i16 = np.concatenate([
                pad_i16, (unclick_tone * 32767).astype(np.int16), pad_i16
            ])

            cls._sounds = {
                "click": click_f32,
                "unclick": unclick_f32,
                "click_i16": click_i16,
                "unclick_i16": unclick_i16,
            }
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
        self._processing_start_time: float = 0  # For stuck state watchdog
        self._max_duration = settings.ptt.max_duration_seconds
        self._processing_timeout = settings.ptt.processing_timeout_seconds
        self._duration_check_task: Optional[asyncio.Task] = None
        self._watchdog_task: Optional[asyncio.Task] = None

        # Initialize sounds on first instance
        self._init_sounds()

    def _play_sound_sync(self, sound_type: str) -> None:
        """Synchronous sound playback (called from executor).

        Uses paplay when sounddevice lacks PulseAudio support (e.g., Docker).
        """
        if not self._sounds or sound_type not in self._sounds:
            return

        sound_data = self._sounds[sound_type]

        if self._use_paplay:
            # Use paplay for PulseAudio output (Docker/containers)
            # Use int16 format (s16le) - more compatible, fewer artifacts
            try:
                import subprocess
                sound_key = f"{sound_type}_i16"
                if sound_key not in self._sounds:
                    return
                proc = subprocess.Popen(
                    ["paplay", "--raw", f"--rate={self._sample_rate}",
                     "--channels=1", "--format=s16le"],
                    stdin=subprocess.PIPE,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                proc.stdin.write(self._sounds[sound_key].tobytes())
                proc.stdin.close()
                proc.wait(timeout=1.0)
                logger.debug(f"Playing {sound_type} sound via paplay")
            except Exception as e:
                logger.debug(f"Could not play {sound_type} sound via paplay: {e}")
        else:
            # Use sounddevice (has PulseAudio or ALSA)
            try:
                import sounddevice as sd
                sd.play(sound_data, self._sample_rate)
                logger.debug(f"Playing {sound_type} sound via sounddevice")
            except Exception as e:
                logger.debug(f"Could not play {sound_type} sound via sounddevice: {e}")

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
        self._processing_start_time = time.perf_counter()  # Track for watchdog

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

    async def _state_watchdog(self) -> None:
        """Monitor for stuck states and auto-recover.

        If PTT gets stuck in PROCESSING state (e.g., server disconnect, callback
        failure), this watchdog will reset it to IDLE after the configured timeout.
        """
        try:
            while True:
                await asyncio.sleep(5.0)  # Check every 5 seconds

                if self.state == PTTState.PROCESSING and self._processing_start_time > 0:
                    elapsed = time.perf_counter() - self._processing_start_time
                    if elapsed > self._processing_timeout:
                        logger.warning(
                            f"PTT stuck in PROCESSING for {elapsed:.1f}s, resetting to IDLE"
                        )
                        self.state = PTTState.IDLE
                        self._processing_start_time = 0

        except asyncio.CancelledError:
            pass

    def on_processing_complete(self) -> None:
        """Called when transcription processing is complete."""
        if self.state == PTTState.PROCESSING:
            self.state = PTTState.IDLE
            self._processing_start_time = 0  # Reset watchdog timer
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

        # Start state watchdog for stuck PROCESSING recovery
        self._watchdog_task = asyncio.create_task(self._state_watchdog())

        try:
            await self._listener.start()
        finally:
            self._listener.stop()
            if self._watchdog_task:
                self._watchdog_task.cancel()

    def stop(self) -> None:
        """Stop the PTT controller."""
        if self._listener:
            self._listener.stop()
        if self._duration_check_task:
            self._duration_check_task.cancel()
        if self._watchdog_task:
            self._watchdog_task.cancel()
