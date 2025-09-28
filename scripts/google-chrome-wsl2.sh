#!/bin/bash

# WSL2 Chrome launcher with comprehensive error handling
# This script addresses D-Bus, GPU, and display issues in WSL2

# Create necessary directories
mkdir -p ~/.local/run ~/.dbus/session-bus 2>/dev/null

# Function to start D-Bus session
start_dbus() {
    # Check if D-Bus daemon is already running
    if ! pgrep -x "dbus-daemon" > /dev/null; then
        eval $(dbus-launch --sh-syntax)
        echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS" > ~/.dbus-session
    else
        # Source existing session if available
        if [ -f ~/.dbus-session ]; then
            source ~/.dbus-session
        fi
    fi
}

# Function to detect best platform
detect_platform() {
    # For WSL2, prefer X11 even if Wayland vars are set
    # as Wayland connection often fails
    if [ ! -z "$DISPLAY" ]; then
        echo "x11"
    elif [ ! -z "$WAYLAND_DISPLAY" ]; then
        echo "wayland"
    else
        echo "headless"
    fi
}

# Start D-Bus
start_dbus

# Detect platform
PLATFORM=$(detect_platform)

# Base Chrome flags for WSL2
CHROME_FLAGS=(
    --disable-gpu
    --disable-software-rasterizer
    --disable-dev-shm-usage
    --no-sandbox
    --disable-accelerated-2d-canvas
    --disable-gpu-sandbox
    --force-device-scale-factor=2.0
    --disable-features=UseChromeOSDirectVideoDecoder
    --disable-gpu-memory-buffer-video-frames
)

# Add platform-specific flags
case $PLATFORM in
    wayland)
        CHROME_FLAGS+=(
            --ozone-platform=wayland
            --enable-features=UseOzonePlatform,WaylandWindowDecorations
        )
        ;;
    x11)
        CHROME_FLAGS+=(
            --ozone-platform=x11
        )
        ;;
    headless)
        CHROME_FLAGS+=(
            --headless
            --disable-gpu
        )
        ;;
esac

# Additional WSL2 specific flags
CHROME_FLAGS+=(
    --disable-background-timer-throttling
    --disable-backgrounding-occluded-windows
    --disable-renderer-backgrounding
    --disable-features=TranslateUI
    --disable-ipc-flooding-protection
    --password-store=basic
    --use-mock-keychain
    --disable-session-crashed-bubble
    --disable-infobars
    --hide-crash-restore-bubble
    --test-type
)

# Export necessary environment variables
export DISPLAY=:0
export LIBGL_ALWAYS_INDIRECT=1
export NO_AT_BRIDGE=1
export DBUS_SESSION_BUS_ADDRESS

# Launch Chrome with all flags
exec /opt/google/chrome/google-chrome "${CHROME_FLAGS[@]}" "$@"