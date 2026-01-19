#!/usr/bin/env bash
#
# Pop Shell Configuration
# Apply optimized settings for high-DPI displays and power users
#
# Usage: ./apply-settings.sh
#

set -euo pipefail

echo "Applying Pop Shell settings..."

# Enable tiling by default
dconf write /org/gnome/shell/extensions/pop-shell/tile-by-default true

# Gaps (4px for visual separation on large displays)
dconf write /org/gnome/shell/extensions/pop-shell/gap-inner 4
dconf write /org/gnome/shell/extensions/pop-shell/gap-outer 4

# Active window hint (colored border on focused window)
dconf write /org/gnome/shell/extensions/pop-shell/active-hint true

# Smart gaps (no gaps when only 1 window - maximizes space)
dconf write /org/gnome/shell/extensions/pop-shell/smart-gaps true

# Hide window titles (cleaner look, saves vertical space)
dconf write /org/gnome/shell/extensions/pop-shell/show-title false

echo "Pop Shell settings applied!"
echo ""
echo "Key bindings:"
echo "  Super + Y          Toggle tiling on/off"
echo "  Super + G          Float/unfloat window"
echo "  Super + Arrow      Move focus"
echo "  Super + Shift + Arrow  Move window"
echo "  Super + Enter      Resize mode"
echo "  Super + /          Launcher"
