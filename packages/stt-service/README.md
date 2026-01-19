# STT Service

GPU-accelerated Speech-to-Text service using NVIDIA Parakeet ONNX models with WebSocket streaming.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/AeyeOps/ai-essentials/main/packages/stt-service/install.sh | bash
```

That's it. The installer handles everything—dependencies, GPU setup, model download.

<details>
<summary>What does the installer do?</summary>

- Checks system requirements (ARM64, NVIDIA GPU, disk space)
- Installs uv, CUDA libraries, and PortAudio if missing
- Downloads and configures STT Service
- Optionally downloads the speech model (~1GB)
- Optionally sets up a systemd service

Re-run the installer anytime to update.
</details>

---

## What You Need

- NVIDIA GB10 or ARM64 system with CUDA GPU
- Ubuntu 22.04+ (or similar Linux)
- Internet connection (model download ~1GB on first run)

## Quick Start

After installation, run:

```bash
cd ~/stt-service
./scripts/stt-server.sh        # Start server (terminal 1)
./scripts/stt-client.sh        # Run client (terminal 2)
```

## Uninstall

```bash
cd ~/stt-service && ./install.sh --uninstall
```

Or manually:
```bash
# Stop and remove service (if installed)
sudo systemctl stop stt-service
sudo systemctl disable stt-service
sudo rm /etc/systemd/system/stt-service.service

# Remove installation
rm -rf ~/stt-service

# Optionally remove cached model (~1GB)
rm -rf ~/.cache/onnx-asr
```

## Running as a System Service

```bash
cd ~/stt-service && ./scripts/install-systemd.sh
```

This generates a systemd service file from a template and optionally installs it.

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

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `uv: command not found` | uv not installed | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| `CUDA not available` | Missing GPU runtime | Install onnxruntime-gpu per instructions below |
| `libcudnn.so.9: cannot open` | Missing cuDNN | `sudo apt install libcudnn9-cuda-12` |
| `cublasLtGetVersion` | CUDA 12/13 mismatch | Set LD_LIBRARY_PATH (see "Running on CUDA 13") |
| `PortAudio library not found` | Missing audio lib | `sudo apt install libportaudio2` |
| `No module named 'huggingface_hub'` | Missing dep (older installs) | `uv sync` to reinstall |
| `TypeError: unexpected keyword argument 'path'` | Old onnx-asr (older installs) | `uv sync` to reinstall |

---

## Advanced Usage

### Developer Setup (Git Clone)

For contributing or developing:

```bash
git clone https://github.com/AeyeOps/ai-essentials.git
cd ai-essentials/packages/stt-service
./scripts/install-gb10.sh
```

### Testing in a Sandbox

Test the installer in a disposable Docker container with GPU passthrough:

```bash
# Interactive sandbox (recommended)
./scripts/test-sandbox.sh

# Inside the container:
bash /mnt/install.sh              # Test install
bash /mnt/install.sh --uninstall  # Test uninstall
nvidia-smi                        # Verify GPU
exit                              # Done (container auto-deletes)
```

Other modes:
```bash
./scripts/test-sandbox.sh --auto   # Non-interactive full test
./scripts/test-sandbox.sh --clean  # Remove image to rebuild fresh
```

Requires Docker and [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html).

### x86_64 Installation

For x86_64 systems with NVIDIA GPU:

```bash
# Install base package
uv sync

# Install with GPU support (x86_64 only)
uv sync --extra gpu

# Or manually install GPU runtime
pip install onnxruntime-gpu
```

### ARM64 / GB10 Manual Installation

If the install script doesn't work, here are the manual steps:

```bash
# Install base package (requires Python 3.12)
uv sync --python 3.12

# Install ARM64 GPU wheel (not available on PyPI)
uv pip install https://github.com/ultralytics/assets/releases/download/v0.0.0/onnxruntime_gpu-1.24.0-cp312-cp312-linux_aarch64.whl

# Install CUDA 12 compatibility libraries
sudo apt-get install -y libcudnn9-cuda-12 libcublas-12-6 libportaudio2

# Verify GPU is available
python -c "import onnxruntime as ort; print(ort.get_available_providers())"
# Should show: ['TensorrtExecutionProvider', 'CUDAExecutionProvider', 'CPUExecutionProvider']
```

### Running on CUDA 13

The Ultralytics wheel was built for CUDA 12. On CUDA 13 systems (GB10), set the library path to use CUDA 12 cuBLAS:

```bash
export LD_LIBRARY_PATH=/usr/local/cuda-12.6/targets/sbsa-linux/lib:$LD_LIBRARY_PATH
stt-server  # or any other command
```

The provided shell scripts (`stt-server.sh`, `stt-client.sh`) set this automatically.

### Pre-downloading Models

Models are automatically downloaded on first use. For offline deployment:

```bash
# Download default model (English)
./scripts/download-models.sh

# Download multilingual model
./scripts/download-models.sh nemo-parakeet-tdt-0.6b-v3

# List available models
./scripts/download-models.sh --list
```

### Server and Client Options

```bash
# Server with options
stt-server --host 0.0.0.0 --port 8080 --provider tensorrt -v

# Client modes
stt-client                  # Record and print to stdout
stt-client --output type    # Type into focused window (Linux)
stt-client --output clipboard  # Copy to clipboard
stt-client --test           # Test connection only
```

### Python API

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

### WebSocket Protocol

#### Client → Server

```json
// Configuration (send first)
{"type": "config", "sample_rate": 16000, "language": "en"}

// Audio: Binary frames (16-bit PCM, mono)

// End stream
{"type": "end"}

// Keep alive
{"type": "keepalive"}
```

#### Server → Client

```json
// Ready
{"type": "ready", "session_id": "abc123"}

// Final transcription
{"type": "final", "text": "hello world", "confidence": 1.0}

// Errors
{"type": "error", "code": "BUFFER_FULL", "message": "..."}
```

#### Error Codes

| Code | Description |
|------|-------------|
| `NOT_CONFIGURED` | Audio sent before config message |
| `BUFFER_FULL` | Audio exceeds 30s limit |
| `PARSE_ERROR` | Invalid JSON message |
| `TRANSCRIPTION_ERROR` | Model inference failed |
| `SERVER_FULL` | Max connections reached |
| `INTERNAL` | Unexpected server error |

## Architecture

```
┌─────────────────┐     WebSocket      ┌─────────────────────────┐
│  PTT Client     │ ◄──────────────────► │  STT Server            │
│  (sounddevice)  │     PCM chunks      │  (onnx-asr + Parakeet) │
└─────────────────┘     ──────────►     │  GPU inference         │
                        ◄──────────     └─────────────────────────┘
                        JSON transcripts
```

## Features

- Real-time speech transcription via WebSocket
- Push-to-talk (PTT) client with multiple output modes
- GPU-only execution (CUDA/TensorRT) - fails fast if unavailable
- Configurable via environment variables
- 30-second max audio length per transcription

## License

MIT
