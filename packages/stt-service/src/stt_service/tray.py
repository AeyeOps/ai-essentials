"""System tray indicator for AEO Push-to-Talk daemon mode.

Provides visual feedback for PTT state:
- Gray: Disconnected / starting up
- Green: Ready (connected, waiting for hotkey)
- Red: Recording ("on air")
- Yellow: Degraded (connected but no input devices, e.g., KVM switched away)
"""

import logging
import threading
from enum import Enum
from typing import Callable, Optional

logger = logging.getLogger(__name__)


class TrayState(Enum):
    """PTT tray indicator states."""
    DISCONNECTED = "gray"    # Starting up / no server connection
    READY = "green"          # Connected, waiting for hotkey
    RECORDING = "red"        # On air - currently recording
    DEGRADED = "yellow"      # Connected but no input devices (KVM switched away)


class TrayIndicator:
    """System tray indicator using pystray.

    Runs in a background thread to avoid blocking the asyncio event loop.
    Thread-safe state updates via set_state().
    """

    # Icon colors (hex)
    COLORS = {
        "gray": "#666666",
        "green": "#22c55e",
        "red": "#ef4444",
        "yellow": "#eab308",
    }

    def __init__(self, on_quit: Callable[[], None]):
        """Initialize tray indicator.

        Args:
            on_quit: Callback invoked when user selects Quit from menu.
                     Should trigger graceful shutdown of the PTT client.
        """
        self.state = TrayState.DISCONNECTED
        self.on_quit = on_quit
        self._icon = None
        self._thread: Optional[threading.Thread] = None

    def _create_icon_image(self, color: str):
        """Create a solid circle icon image.

        Args:
            color: Color name from COLORS dict.

        Returns:
            PIL Image object (RGBA, 22x22 pixels).
        """
        try:
            from PIL import Image, ImageDraw
        except ImportError:
            logger.error("PIL not installed. Install with: uv pip install pillow")
            raise

        size = 22
        img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)

        hex_color = self.COLORS.get(color, self.COLORS["gray"])
        draw.ellipse([2, 2, size - 2, size - 2], fill=hex_color)

        return img

    def set_state(self, state: TrayState) -> None:
        """Update tray state and icon (thread-safe).

        Args:
            state: New TrayState value.
        """
        self.state = state
        if self._icon:
            try:
                self._icon.icon = self._create_icon_image(state.value)
            except Exception as e:
                logger.debug(f"Could not update tray icon: {e}")

    def _do_quit(self) -> None:
        """Handle quit menu action."""
        logger.info("Quit requested from tray menu")
        if self._icon:
            self._icon.stop()
        self.on_quit()

    def start(self) -> None:
        """Start tray icon in background thread (non-blocking).

        Call this from the main asyncio context. The tray runs in its own
        thread and won't block the event loop.
        """
        try:
            import pystray
        except ImportError:
            logger.error("pystray not installed. Install with: uv pip install pystray")
            raise

        menu = pystray.Menu(
            pystray.MenuItem("Quit", lambda: self._do_quit())
        )

        self._icon = pystray.Icon(
            "aeo-ptt",
            self._create_icon_image(self.state.value),
            "AEO Push-to-Talk",
            menu
        )

        # Run in daemon thread so it exits when main program exits
        self._thread = threading.Thread(target=self._icon.run, daemon=True)
        self._thread.start()

        logger.debug("Tray indicator started")

    def stop(self) -> None:
        """Stop the tray icon."""
        if self._icon:
            try:
                self._icon.stop()
            except Exception as e:
                logger.debug(f"Error stopping tray icon: {e}")
            self._icon = None
        logger.debug("Tray indicator stopped")
