#!/usr/bin/env bash
# Pre-download STT models for offline use
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Known models
MODELS=(
    "nemo-parakeet-tdt-0.6b-v2"
    "nemo-parakeet-tdt-0.6b-v3"
)

show_help() {
    echo "Usage: $(basename "$0") [MODEL|--list|--help]"
    echo ""
    echo "Pre-download STT models for offline use."
    echo ""
    echo "Options:"
    echo "  --list   Show available models"
    echo "  --help   Show this help message"
    echo ""
    echo "Available models:"
    echo "  nemo-parakeet-tdt-0.6b-v2  (default, English)"
    echo "  nemo-parakeet-tdt-0.6b-v3  (multilingual)"
}

# Handle flags
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --list)
        echo "Available models:"
        echo "  nemo-parakeet-tdt-0.6b-v2  (default, English)"
        echo "  nemo-parakeet-tdt-0.6b-v3  (multilingual)"
        exit 0
        ;;
esac

MODEL="${1:-nemo-parakeet-tdt-0.6b-v2}"

# Validate model name
valid=false
for m in "${MODELS[@]}"; do
    if [[ "$MODEL" == "$m" ]]; then
        valid=true
        break
    fi
done

if [[ "$valid" != "true" ]]; then
    echo "ERROR: Unknown model '$MODEL'"
    echo ""
    echo "Available models:"
    for m in "${MODELS[@]}"; do
        echo "  $m"
    done
    exit 1
fi

cd "$PROJECT_DIR"

# Set CUDA 12 library path for GB10 compatibility
CUDA_LIB="/usr/local/cuda-12.6/targets/sbsa-linux/lib"
if [[ -d "$CUDA_LIB" ]]; then
    export LD_LIBRARY_PATH="$CUDA_LIB:${LD_LIBRARY_PATH:-}"
fi

echo "=== STT Model Downloader ==="
echo "Model: $MODEL"
echo ""

# Check for uv
if ! command -v uv &> /dev/null; then
    echo "ERROR: uv not found."
    echo ""
    echo "Install uv with:"
    echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"
    echo "  source ~/.bashrc"
    exit 1
fi

# Verify GPU is available before attempting model load
echo "Verifying GPU availability..."
uv run python -c "
import onnxruntime as ort
providers = ort.get_available_providers()
if 'CUDAExecutionProvider' not in providers:
    print(f'ERROR: CUDA GPU not available. Found: {providers}')
    exit(1)
print('GPU verified: CUDA available')
"

echo ""
echo "Downloading and verifying model..."
uv run python -c "
from stt_service.transcriber import Transcriber
from stt_service.config import ModelConfig

config = ModelConfig(name='$MODEL')
t = Transcriber(config=config)
t.load()
print('')
print('Model ready: $MODEL')
print('Location: ~/.cache/onnx-asr/')
"

