#!/bin/bash

# WSL2 Chrome launcher - Windows Edition
# This script launches Chrome from the Windows side while running in WSL2

# Function to find Chrome executable on Windows
find_chrome() {
    # Common Chrome installation paths on Windows
    local CHROME_PATHS=(
        "/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"
        "/mnt/c/Program Files (x86)/Google/Chrome/Application/chrome.exe"
        "$LOCALAPPDATA/Google/Chrome/Application/chrome.exe"
    )

    for path in "${CHROME_PATHS[@]}"; do
        if [ -f "$path" ]; then
            echo "$path"
            return 0
        fi
    done

    # Try to find via Windows registry
    local reg_path=$(cmd.exe /c reg query "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\chrome.exe" /ve 2>/dev/null | grep -oP '(?<=REG_SZ\s{4}).*')
    if [ ! -z "$reg_path" ]; then
        # Convert Windows path to WSL path
        echo "$reg_path" | sed 's/\\/\//g' | sed 's/C:/\/mnt\/c/g'
        return 0
    fi

    return 1
}

# Find Chrome executable
CHROME_EXE=$(find_chrome)

if [ -z "$CHROME_EXE" ]; then
    echo "Error: Could not find Chrome installation on Windows" >&2
    exit 1
fi

# Chrome flags optimized for Windows Chrome launched from WSL2
CHROME_FLAGS=(
    --new-window
    --remote-debugging-port=9222
    --disable-features=TranslateUI
    --disable-session-crashed-bubble
    --disable-infobars
    --hide-crash-restore-bubble
    --password-store=basic
    --use-mock-keychain
)

# Convert WSL paths to Windows paths for any file arguments
ARGS=()
for arg in "$@"; do
    if [[ "$arg" == /* ]] && [ -e "$arg" ]; then
        # Convert WSL path to Windows path
        WIN_PATH=$(wslpath -w "$arg" 2>/dev/null)
        if [ $? -eq 0 ]; then
            ARGS+=("$WIN_PATH")
        else
            ARGS+=("$arg")
        fi
    else
        ARGS+=("$arg")
    fi
done

# Launch Windows Chrome from WSL2 using cmd.exe /c start for proper desktop attachment
cmd.exe /c start "" "$(wslpath -w "$CHROME_EXE")" "${CHROME_FLAGS[@]}" "${ARGS[@]}"
