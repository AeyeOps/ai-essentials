#!/usr/bin/env bash
#
# Test audio input/output devices and playback
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

uv run python << 'PYEOF'
import sounddevice as sd
import numpy as np

print("=" * 60)
print("Audio Device Test")
print("=" * 60)

# List devices
print("\nDevices (* = default output):\n")
default_out = sd.default.device[1]
for i, d in enumerate(sd.query_devices()):
    io = []
    if d['max_input_channels'] > 0:
        io.append(f"{d['max_input_channels']}in")
    if d['max_output_channels'] > 0:
        io.append(f"{d['max_output_channels']}out")
    if io:
        marker = '*' if i == default_out else ' '
        print(f"  {marker} [{i}] {d['name']} ({', '.join(io)})")

# Use system default (None = default device)
print(f"\nUsing system default output device...")

# Generate click sounds (same as PTT)
sr = 44100
duration = 0.08
t = np.linspace(0, duration, int(sr * duration), False)

# Click (880Hz, attack-decay envelope)
envelope = np.exp(-t * 15) * (1 - np.exp(-t * 100))
click = (np.sin(2 * np.pi * 880 * t) * envelope * 0.25).astype(np.float32)

# Unclick (440Hz)
envelope = np.exp(-t * 20) * (1 - np.exp(-t * 100))
unclick = (np.sin(2 * np.pi * 440 * t) * envelope * 0.25).astype(np.float32)

print("\nPlaying 'click' sound (880Hz - PTT activate)...")
sd.play(click, sr)
sd.wait()

import time
time.sleep(0.3)

print("Playing 'unclick' sound (440Hz - PTT deactivate)...")
sd.play(unclick, sr)
sd.wait()

print("\nDone. If you heard two tones, audio output is working.")
print("=" * 60)
PYEOF
