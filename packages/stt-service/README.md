# STT Service

GPU-accelerated Speech-to-Text service using NVIDIA Parakeet ONNX models with WebSocket streaming.

## Features

- Real-time speech transcription via WebSocket
- Push-to-talk (PTT) client with multiple output modes
- GPU-only execution (CUDA/TensorRT) - fails fast if unavailable
- Configurable via environment variables
- 30-second max audio length per transcription

## Requirements

- Python >= 3.12.3
- NVIDIA GPU with CUDA support
- onnxruntime-gpu (for GPU acceleration)

## Installation

```bash
# Install base package
uv sync

# Install with GPU support (recommended)
uv sync --extra gpu

# Or manually install GPU runtime
pip install onnxruntime-gpu
```

## Quick Start

### Start the Server

```bash
# Default settings (localhost:9876, CUDA)
stt-server

# With options
stt-server --host 0.0.0.0 --port 8080 --provider tensorrt -v
```

### Run the Client

```bash
# Record and print to stdout
stt-client

# Type into focused window (Linux)
stt-client --output type

# Copy to clipboard
stt-client --output clipboard

# Test connection only
stt-client --test
```

## Configuration

All settings can be overridden via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `STT_SERVER_HOST` | `127.0.0.1` | Server bind address |
| `STT_SERVER_PORT` | `9876` | Server port |
| `STT_SERVER_MAX_CONNECTIONS` | `10` | Max concurrent connections |
| `STT_SERVER_REJECT_WHEN_FULL` | `true` | Reject vs queue when full |
| `STT_MODEL_NAME` | `nemo-parakeet-tdt-0.6b-v2` | Model name |
| `STT_MODEL_PROVIDER` | `cuda` | `cuda` or `tensorrt` |
| `STT_MODEL_DEVICE_ID` | `0` | GPU device ID |
| `STT_CLIENT_SERVER_URL` | `ws://127.0.0.1:9876` | Server URL |
| `STT_CLIENT_OUTPUT_MODE` | `stdout` | `stdout`, `type`, `clipboard` |
| `STT_AUDIO_SAMPLE_RATE` | `16000` | Audio sample rate (Hz) |
| `STT_AUDIO_CHUNK_MS` | `100` | Chunk duration (ms) |

## WebSocket Protocol

### Client → Server

```json
// Configuration (send first)
{"type": "config", "sample_rate": 16000, "language": "en"}

// Audio: Binary frames (16-bit PCM, mono)

// End stream
{"type": "end"}

// Keep alive
{"type": "keepalive"}
```

### Server → Client

```json
// Ready
{"type": "ready", "session_id": "abc123"}

// Final transcription
{"type": "final", "text": "hello world", "confidence": 1.0}

// Errors
{"type": "error", "code": "BUFFER_FULL", "message": "..."}
```

### Error Codes

| Code | Description |
|------|-------------|
| `NOT_CONFIGURED` | Audio sent before config message |
| `BUFFER_FULL` | Audio exceeds 30s limit |
| `PARSE_ERROR` | Invalid JSON message |
| `TRANSCRIPTION_ERROR` | Model inference failed |
| `SERVER_FULL` | Max connections reached |
| `INTERNAL` | Unexpected server error |

## Pre-downloading Models

Models are automatically downloaded on first use. For offline deployment:

```bash
# Download default model (English)
./scripts/download-models.sh

# Download multilingual model
./scripts/download-models.sh parakeet-tdt-0.6b-v3
```

## Python API

```python
from stt_service import Transcriber, PTTClient, settings

# Direct transcription
transcriber = Transcriber()
transcriber.load()
text = transcriber.transcribe(audio_array, sample_rate=16000)

# PTT client
async def main():
    client = PTTClient()
    await client.connect()
    text = await client.record_and_transcribe()
    await client.disconnect()
```

## Architecture

```
┌─────────────────┐     WebSocket      ┌─────────────────────────┐
│  PTT Client     │ ◄──────────────────► │  STT Server            │
│  (sounddevice)  │     PCM chunks      │  (onnx-asr + Parakeet) │
└─────────────────┘     ──────────►     │  GPU inference         │
                        ◄──────────     └─────────────────────────┘
                        JSON transcripts
```

## License

MIT
