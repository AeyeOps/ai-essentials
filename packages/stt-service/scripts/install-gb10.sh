#!/usr/bin/env bash
# Install AEO Push-to-Talk on NVIDIA GB10 (Grace Blackwell ARM64)
# Usage: curl -fsSL <url> | bash
set -euo pipefail

CURRENT_USER="$(whoami)"

# Detect curl-pipe mode vs local run
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "bash" ]]; then
    # Running via curl pipe - clone repo first
    INSTALL_DIR="$HOME/stt-service"
    echo "=== AEO Push-to-Talk GB10 Installer (curl mode) ==="
    echo "Install dir: $INSTALL_DIR"

    if ! command -v git &> /dev/null; then
        echo "ERROR: git not found. Install with: sudo apt install git"
        exit 1
    fi

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        echo "Updating existing installation..."
        cd "$INSTALL_DIR"
        git pull --ff-only
    else
        echo "Cloning repository..."
        rm -rf "$INSTALL_DIR"
        git clone --depth 1 https://github.com/AeyeOps/ai-essentials.git "$INSTALL_DIR"
    fi
    PROJECT_DIR="$INSTALL_DIR/packages/stt-service"
else
    # Running locally from cloned repo
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
    echo "=== AEO Push-to-Talk GB10 Installer ==="
    echo "Project: $PROJECT_DIR"
fi
echo "User: $CURRENT_USER"

# Check architecture
if [[ "$(uname -m)" != "aarch64" ]]; then
    echo "ERROR: This script is for ARM64 (aarch64) only"
    exit 1
fi

# Check for NVIDIA GPU
if ! command -v nvidia-smi &> /dev/null; then
    echo "ERROR: nvidia-smi not found."
    echo ""
    echo "Ensure NVIDIA drivers are installed. On Ubuntu:"
    echo "  sudo apt install nvidia-driver-570"
    echo ""
    echo "Or see: https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/"
    exit 1
fi

# Verify nvidia-smi actually detects a GPU
if ! nvidia-smi -L | grep -q GPU; then
    echo "ERROR: No GPU detected by nvidia-smi."
    echo ""
    nvidia-smi -L
    exit 1
fi

# Check for uv
if ! command -v uv &> /dev/null; then
    echo "ERROR: uv not found."
    echo ""
    echo "Install uv with:"
    echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"
    echo "  source ~/.bashrc  # or restart terminal"
    exit 1
fi

echo ""
echo "1. Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
    libportaudio2 \
    libcudnn9-cuda-12 \
    libcublas-12-6

echo ""
echo "2. Creating Python 3.12 virtual environment..."
cd "$PROJECT_DIR"
uv sync --python 3.12

echo ""
echo "3. Installing ARM64 onnxruntime-gpu wheel..."
uv pip install https://github.com/ultralytics/assets/releases/download/v0.0.0/onnxruntime_gpu-1.24.0-cp312-cp312-linux_aarch64.whl

echo ""
echo "4. Verifying GPU support..."
uv run python -c "
import onnxruntime as ort
providers = ort.get_available_providers()
print(f'Available providers: {providers}')
if 'CUDAExecutionProvider' not in providers:
    print('ERROR: CUDA not available!')
    exit(1)
print('GPU support verified')
"

echo ""
echo "5. Pre-downloading model..."
if true; then
    # Set CUDA 12 library path if available
    CUDA_LIB="/usr/local/cuda-12.6/targets/sbsa-linux/lib"
    if [[ -d "$CUDA_LIB" ]]; then
        export LD_LIBRARY_PATH="$CUDA_LIB:${LD_LIBRARY_PATH:-}"
    else
        echo "WARNING: CUDA 12.6 library path not found at $CUDA_LIB"
        echo "If model loading fails, check your CUDA installation."
    fi
    uv run python -c "
from stt_service.transcriber import Transcriber
t = Transcriber()
t.load()
print('Model downloaded and loaded successfully')
"
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "To run the server:"
echo "  cd $PROJECT_DIR"
echo "  ./scripts/stt-server.sh"
echo ""
echo "To install as systemd service:"
echo "  ./scripts/install-systemd.sh"

