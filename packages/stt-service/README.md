# AEO Push-to-Talk

GPU-accelerated Speech-to-Text using NVIDIA Parakeet ONNX models with WebSocket streaming.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/AeyeOps/ai-essentials/main/packages/stt-service/install.sh | bash
```

The installer handles dependencies, GPU setup, and model download. Answer **yes** to all prompts for the full experience:

- **Input group** - enables global Ctrl+Super hotkey
- **Systemd service** - server auto-starts on boot
- **Auto-start client** - tray icon appears at login

Log out and back in after install. Press **Ctrl+Super** in any app to dictate.

## Quick Start (Manual)

If you skipped auto-start, run manually:

```bash
cd ~/stt-service
./scripts/stt-server.sh        # Terminal 1: Start server
./scripts/stt-client.sh --ptt  # Terminal 2: PTT mode
```

Output shows timing and transcription:
```
[2.1s → 45ms] hello this is a test
[0.3s → 38ms] (silence)
```

## PTT Modes

The client auto-detects the best mode based on your environment:

| Mode | Hotkey | When Used |
|------|--------|-----------|
| **Global** | Ctrl+Super | Desktop with input group access |
| **Terminal** | Spacebar | Docker, SSH, or no input access |

### Customizing Hotkeys

**Global mode** (evdev): Set `STT_PTT_HOTKEY` to a JSON array of [evdev key names](https://github.com/torvalds/linux/blob/master/include/uapi/linux/input-event-codes.h) (without `KEY_` prefix):

```bash
# Default: Ctrl+Super (Windows key)
export STT_PTT_HOTKEY='["LEFTCTRL", "LEFTMETA"]'

# Ctrl+Alt
export STT_PTT_HOTKEY='["LEFTCTRL", "LEFTALT"]'

# Right Ctrl + Right Alt
export STT_PTT_HOTKEY='["RIGHTCTRL", "RIGHTALT"]'

# Single key (F13)
export STT_PTT_HOTKEY='["F13"]'
```

**Terminal mode**: Set `STT_PTT_TERMINAL_HOTKEY` to a character:

```bash
# Default: spacebar
export STT_PTT_TERMINAL_HOTKEY=' '

# Ctrl+R (ASCII 18)
export STT_PTT_TERMINAL_HOTKEY=$'\x12'
```

## Configuration

All settings via environment variables:

### Server

| Variable | Default | Description |
|----------|---------|-------------|
| `STT_SERVER_HOST` | `127.0.0.1` | Bind address |
| `STT_SERVER_PORT` | `9876` | Port |
| `STT_MODEL_PROVIDER` | `cuda` | `cuda` or `tensorrt` |

### Client

| Variable | Default | Description |
|----------|---------|-------------|
| `STT_CLIENT_OUTPUT_MODE` | `stdout` | `stdout`, `type`, `clipboard` |
| `STT_CLIENT_SERVER_URL` | `ws://127.0.0.1:9876` | Server URL |

### PTT

| Variable | Default | Description |
|----------|---------|-------------|
| `STT_PTT_HOTKEY` | `["LEFTCTRL", "LEFTMETA"]` | Global mode keys |
| `STT_PTT_TERMINAL_HOTKEY` | ` ` (space) | Terminal mode key |
| `STT_PTT_CLICK_SOUND` | `true` | Audio feedback |
| `STT_PTT_MAX_DURATION_SECONDS` | `30` | Auto-submit threshold |

## Output Modes

```bash
./scripts/stt-client.sh --ptt                  # Print to stdout
./scripts/stt-client.sh --ptt --output type    # Type into focused window (xdotool)
./scripts/stt-client.sh --ptt --output clipboard  # Copy to clipboard
```

## System Tray (Auto-Start Mode)

When auto-start is enabled, a system tray icon shows PTT status:

| Color | State |
|-------|-------|
| Gray | Connecting to server |
| Green | Ready (listening for Ctrl+Super) |
| Red | Recording ("on air") |

Right-click the tray icon to quit.

**Requirements:** GNOME users may need the [AppIndicator extension](https://extensions.gnome.org/extension/615/appindicator-support/).

## Running as a Service

```bash
cd ~/stt-service && ./scripts/install-systemd.sh
```

## Uninstall

```bash
cd ~/stt-service && ./install.sh --uninstall
```

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| `CUDA not available` | Re-run installer, check GPU with `nvidia-smi` |
| `No accessible keyboards` | Run `sudo usermod -a -G input $USER`, log out/in |
| Server won't start | Check if port 9876 is in use: `lsof -i :9876` |

## Architecture

```
┌─────────────────┐     WebSocket      ┌─────────────────────────┐
│  PTT Client     │ ◄────────────────► │  STT Server             │
│  (sounddevice)  │     PCM chunks     │  (onnx-asr + Parakeet)  │
└─────────────────┘     ──────────►    │  GPU inference          │
                        ◄──────────    └─────────────────────────┘
                        JSON transcripts
```

## Features

- **Real-time transcription** (40-200ms latency after warmup)
- **System-wide auto-start**: Server on boot, client at login with tray icon
- **Push-to-Talk**: Global hotkey (Ctrl+Super) or terminal (spacebar)
- **Output modes**: stdout, type-to-window, clipboard
- **Audio feedback**: Click sounds with container support
- **30-second auto-submit** for long recordings
- **GPU-only** (CUDA/TensorRT) - fails fast if unavailable

---

<details>
<summary><strong>Advanced: Developer Setup</strong></summary>

### Git Clone

```bash
git clone https://github.com/AeyeOps/ai-essentials.git
cd ai-essentials/packages/stt-service
./scripts/install-gb10.sh
```

### Docker Sandbox

```bash
./scripts/test-sandbox.sh        # Start container
# Inside: run curl installer, test PTT
./scripts/test-sandbox.sh --clean  # Rebuild image
```

### Python API

```python
from stt_service import Transcriber

transcriber = Transcriber()
transcriber.load()
text = transcriber.transcribe(audio_array, sample_rate=16000)
```

### WebSocket Protocol

**Client → Server:**
```json
{"type": "config", "sample_rate": 16000}  // First
// Binary frames: 16-bit PCM mono
{"type": "end"}  // Triggers transcription
```

**Server → Client:**
```json
{"type": "ready", "session_id": "abc123"}
{"type": "final", "text": "hello", "confidence": 1.0}
{"type": "error", "code": "BUFFER_FULL", "message": "..."}
```

</details>

## License

MIT
